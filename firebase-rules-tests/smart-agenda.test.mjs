import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInAnonymously} from 'firebase/auth';
import {getFunctions, connectFunctionsEmulator, httpsCallable} from 'firebase/functions';
import {getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc, updateDoc, Timestamp, onSnapshot, collection, getDocs} from 'firebase/firestore';
import {getStorage, connectStorageEmulator, ref, uploadBytes, getBytes} from 'firebase/storage';
const projectId='demo-group-bomb', groupID='44444444-4444-4444-8444-444444444444';
const path=`groups/${groupID}/smartAgenda/current`;
let env, leader, member, outsider;
const apps=[];
async function client(name) {
 const app=initializeApp({projectId,apiKey:'demo-api-key',storageBucket:`${projectId}.appspot.com`},name); apps.push(app);
 const auth=getAuth(app); connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
 const {user}=await signInAnonymously(auth);
 const db=getFirestore(app); connectFirestoreEmulator(db,'127.0.0.1',8080);
 const functions=getFunctions(app,'asia-east1'); connectFunctionsEmulator(functions,'127.0.0.1',5001);
 const storage=getStorage(app); connectStorageEmulator(storage,'127.0.0.1',9199);
 return {uid:user.uid,db,storage,call:async(action,fields={})=>(await httpsCallable(functions,'updateSmartAgenda')({groupID,action,...fields})).data};
}
async function read(who=leader) { return (await getDoc(doc(who.db,path))).data(); }
async function seed(uid,role) {
 await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),`groups/${groupID}/members/${uid}`),
   {userID:uid,displayName:role==='leader'?'Mia':'Alex',role,joinedAt:Timestamp.now()}));
}
before(async()=>{
 env=await initializeTestEnvironment({projectId});
 await env.clearFirestore();
 await env.clearStorage();
 [leader,member,outsider]=await Promise.all(['agenda-leader','agenda-member','agenda-outsider'].map(client));
 await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),`groups/${groupID}`),{name:'Agenda integration test'}));
 await seed(leader.uid,'leader'); await seed(member.uid,'member');
});
after(async()=>{ await Promise.all(apps.map(deleteApp)); await env.cleanup(); });

test('leader sets meeting; members read it; outsiders and direct writes are denied',async()=>{
 const meeting={topic:'Finalize Our Demo',meetingAtMillis:Date.now()+3600000,duration:20,expectedRevision:null};
 await assert.rejects(member.call('meeting',meeting),e=>e.code==='functions/permission-denied');
 await assert.rejects(outsider.call('meeting',meeting),e=>e.code==='functions/permission-denied');
 await leader.call('meeting',meeting);
 const value=await read(member); assert.equal(value.topic,meeting.topic); assert.equal(value.memberUIDs.length,2);
 await assertFails(getDoc(doc(outsider.db,path)));
 await assertFails(updateDoc(doc(member.db,path),{topic:'Overwrite'}));
 // Retrying the same save after a lost response is safe, while different stale settings conflict.
 await leader.call('meeting',meeting);
 assert.deepEqual(await read(),value);
 await assert.rejects(leader.call('meeting',{...meeting,duration:30}),e=>e.code==='functions/aborted');
});

test('note-only preparation counts; own-account permission and live cross-account updates',async()=>{
 const observed=new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>{ stop(); reject(Error('Realtime update timed out')); },10000);
  const stop=onSnapshot(doc(member.db,path),snapshot=>{
   if(snapshot.data()?.materials?.[leader.uid]?.note==='Confirm the opening') {clearTimeout(timeout);stop();resolve();}
  },reject);
 });
 await leader.call('material',{note:'Confirm the opening',attachment:null,expectedRevision:null});
 await observed;
 assert.equal((await read(member)).preparedUIDs.length,1);
 await assert.rejects(member.call('material',{note:'Attack',attachment:null,expectedRevision:null,userID:leader.uid}),e=>e.code==='functions/invalid-argument');
 assert.equal((await read()).materials[leader.uid].note,'Confirm the opening');
 await assert.rejects(leader.call('retry'),e=>e.code==='functions/failed-precondition');
});

test('real uploaded PDF bytes are readable by the other member; attachment-only counts',async()=>{
 const storagePath=`groups/${groupID}/agendaMaterials/${member.uid}/55555555-5555-4555-8555-555555555555/file.pdf`;
 const bytes=new TextEncoder().encode('%PDF-1.7\nAgenda file transfer verification\n%%EOF');
 await assertSucceeds(uploadBytes(ref(member.storage,storagePath),bytes,{contentType:'application/pdf',customMetadata:{uploaderID:member.uid}}));
 const attachment={fileName:'Feature Priorities.pdf',storagePath,contentType:'application/pdf',byteSize:bytes.length};
 await member.call('material',{note:'',attachment,expectedRevision:null});
 const value=await read(leader); assert.equal(value.preparedUIDs.length,2); assert.equal(value.materials[member.uid].attachment.fileName,attachment.fileName);
 assert.deepEqual(new Uint8Array(await getBytes(ref(leader.storage,storagePath))),bytes);
 await assertFails(getBytes(ref(outsider.storage,storagePath)));
 await assertFails(uploadBytes(ref(leader.storage,storagePath),bytes,{contentType:'application/pdf',customMetadata:{uploaderID:leader.uid}}));
 await assert.rejects(leader.call('material',{note:'Stolen file',attachment,expectedRevision:value.materials[leader.uid].revision}),e=>e.code==='functions/invalid-argument');
});

test('new entries append across accounts; editing one preserves the original file and unique readiness',async()=>{
 const firstID='aaaaaaaa-1111-4111-8111-111111111111', secondID='bbbbbbbb-2222-4222-8222-222222222222';
 const before=await read(), original=before.materials[member.uid];
 const observed=new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>{stop();reject(Error('Appended entry did not sync'));},10000);
  const stop=onSnapshot(doc(leader.db,path),snapshot=>{
   if(snapshot.data()?.materials?.[firstID]?.note==='Additional detail') {clearTimeout(timeout);stop();resolve();}
  },reject);
 });
 const payload={materialID:firstID,note:'Additional detail',attachment:null,expectedRevision:null};
 await member.call('material',payload); await observed;
 await member.call('material',{...payload,materialID:secondID,note:'Second detail'});
 await member.call('material',payload); // Lost-response retry must not duplicate.
 let value=await read(leader);
 assert.equal(Object.keys(value.materials).length,4);
 assert.deepEqual(value.materials[member.uid],original);
 assert.equal(value.preparedUIDs.length,2);
 await assert.rejects(leader.call('material',{...payload,note:'Other member edit',expectedRevision:value.materials[firstID].revision}),e=>e.code==='functions/permission-denied');
 await member.call('material',{...payload,note:'Updated extra',expectedRevision:value.materials[firstID].revision});
 value=await read();
 assert.equal(value.materials[firstID].note,'Updated extra');
 assert.equal(value.materials[secondID].note,'Second detail');
 assert((await getBytes(ref(leader.storage,original.attachment.storagePath))).byteLength>0);
 for(const materialID of [firstID,secondID]) {
  const removal={materialID,note:'',attachment:null,expectedRevision:value.materials[materialID].revision};
  await member.call('material',removal);
  const removed=await read();
  await member.call('material',removal);
  assert.deepEqual(await read(),removed);
 }
 value=await read();
 assert.equal(value.preparedUIDs.length,2);
 assert.deepEqual(value.materials[member.uid],original);
});

test('retrying an attached edit preserves the exact uploaded object and another account sees one record',async()=>{
 const before=await read(), own=before.materials[member.uid];
 const request={materialID:member.uid,note:'Discuss this PDF',attachment:own.attachment,expectedRevision:own.revision};
 await member.call('material',request);
 const saved=await read(leader);
 await member.call('material',request);
 assert.deepEqual(await read(leader),saved);
 assert.equal(saved.materials[member.uid].attachment.storagePath,own.attachment.storagePath);
 assert.equal(Object.keys(saved.materials).length,2);
 assert.equal(saved.preparedUIDs.length,2);
 assert((await getBytes(ref(leader.storage,own.attachment.storagePath))).byteLength>0);
 await assert.rejects(member.call('material',{...request,note:'Conflicting stale change'}),e=>e.code==='functions/aborted');
});

test('device-generated plan is validated, stored in Firebase and streamed to another account',async()=>{
 const {randomUUID}=await import('node:crypto');
 const before=await read(),fields={inputRevision:before.inputRevision,token:randomUUID()};
 const phases=[{minutes:5,title:'Review materials',goal:'Confirm the opening',titleZhHant:'檢視資料',goalZhHant:'確認開場'},
  {minutes:7,title:'Decide order',goal:'Choose features',titleZhHant:'決定順序',goalZhHant:'選定功能'},
  {minutes:8,title:'Finalize',goal:'Assign revisions',titleZhHant:'完成決議',goalZhHant:'分派修改'}];
 await assert.rejects(outsider.call('claimPlan',fields),e=>e.code==='functions/permission-denied');
 const claim=await leader.call('claimPlan',fields);
 assert.equal(claim.status,'claimed');
 assert.equal(claim.input.duration,20);
 assert.equal(claim.input.members.length,2);
 assert(claim.input.members.some(m=>m.materials.some(v=>v.fileName==='Feature Priorities.pdf')));
 assert.equal((await member.call('claimPlan',{...fields,token:randomUUID()})).status,'busy');
 await assert.rejects(member.call('completePlan',{...fields,phases}),e=>e.code==='functions/failed-precondition');
 await assert.rejects(leader.call('completePlan',{...fields,phases:phases.slice(0,2)}),e=>e.code==='functions/invalid-argument');
 await assertFails(updateDoc(doc(member.db,path),{stages:phases,planSource:'appleIntelligence'}));
 const observed=new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>{stop();reject(Error('Published plan did not sync'));},10000);
  const stop=onSnapshot(doc(member.db,path),snapshot=>{
   if(snapshot.data()?.planSource==='appleIntelligence' && snapshot.data()?.stages?.length===3) {
    clearTimeout(timeout);stop();resolve(snapshot.data());
   }
  },reject);
 });
 await leader.call('completePlan',{...fields,phases});
 const shared=await observed;
 assert.equal(shared.stages[0].titleZhHant,'檢視資料');
 const value=await read(leader);
 assert.deepEqual(value.stages,shared.stages);
 assert.deepEqual(value.stages.map(s=>[s.start,s.end]),[[0,5],[5,12],[12,20]]);
 await leader.call('completePlan',{...fields,phases});
 assert.deepEqual(await read(),value);
 await assert.rejects(member.call('start',{inputRevision:value.inputRevision}),e=>e.code==='functions/permission-denied');
 await leader.call('start',{inputRevision:value.inputRevision});
 assert((await read(member)).meetingStartedAt);
 await assert.rejects(member.call('end',{inputRevision:value.inputRevision}),e=>e.code==='functions/permission-denied');
 await leader.call('end',{inputRevision:value.inputRevision});
 assert.equal((await read()).meetingStartedAt,null);
});

test('meeting links sync to another account without changing preparation or the AI plan',async()=>{
 const before=await read();
 const linkID='eeeeeeee-4444-4444-8444-444444444444';
 const request={linkID,title:'Meeting room',url:'https://example.com/room',expectedRevision:null};
 const observed=new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>{stop();reject(Error('Meeting link did not sync'));},10000);
  const stop=onSnapshot(doc(leader.db,path),snapshot=>{
   if(snapshot.data()?.links?.[linkID]?.url===request.url) {clearTimeout(timeout);stop();resolve();}
  },reject);
 });
 await member.call('link',request);await observed;
 const saved=await read(leader);
 assert.equal(saved.links[linkID].ownerUID,member.uid);
 for(const key of ['materials','preparedUIDs','inputRevision','stages','planState','meetingStartedAt']) assert.deepEqual(saved[key],before[key],key);
 await member.call('link',request);assert.deepEqual(await read(),saved);
 await assert.rejects(outsider.call('link',request),e=>e.code==='functions/permission-denied');
 await assertFails(updateDoc(doc(member.db,path),{links:{}}));
 await assert.rejects(member.call('link',{...request,url:'javascript:alert(1)'}),e=>e.code==='functions/invalid-argument');
 await leader.call('link',{...request,title:'Updated room',expectedRevision:saved.links[linkID].revision});
 const updated=await read(member);assert.equal(updated.links[linkID].title,'Updated room');
 await assert.rejects(member.call('link',{...request,title:'Stale overwrite',expectedRevision:saved.links[linkID].revision}),e=>e.code==='functions/aborted');
 const removal={...request,title:'',url:'',expectedRevision:updated.links[linkID].revision};
 await member.call('link',removal);const removed=await read(leader);
 assert(!removed.links[linkID]);
 await member.call('link',removal);assert.deepEqual(await read(),removed);
});

test('saving unchanged meeting and attached material preserves the published plan and original revisions',async()=>{
 const before=await read();
 await leader.call('meeting',{topic:before.topic,meetingAtMillis:before.meetingAt.toMillis(),duration:before.duration,expectedRevision:before.meetingRevision});
 const own=before.materials[member.uid];
 await member.call('material',{materialID:member.uid,note:own.note,attachment:own.attachment,expectedRevision:own.revision});
 const after=await read();
 assert.deepEqual(after,before);
 const missing={...own.attachment,storagePath:`groups/${groupID}/agendaMaterials/${member.uid}/99999999-9999-4999-8999-999999999999/file.pdf`};
 await assert.rejects(member.call('material',{materialID:member.uid,note:own.note,attachment:missing,expectedRevision:own.revision}),e=>e.code==='functions/failed-precondition' && e.message.includes('Choose the file again'));
 assert.deepEqual(await read(),before);
});

test('clearing a preparation invalidates the plan and removes readiness',async()=>{
 const old=await read();
 await member.call('material',{note:' ',attachment:null,expectedRevision:old.materials[member.uid].revision});
 const value=await read(); assert.equal(value.preparedUIDs.length,1); assert.deepEqual(value.stages,[]);
 await assert.rejects(member.call('material',{note:'Stale write',attachment:null,expectedRevision:old.materials[member.uid].revision}),e=>e.code==='functions/aborted');
});

const agendaA='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', agendaB='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const meetingRequest=(agendaID,topic)=>({agendaID,topic,meetingAtMillis:Date.now()+7200000,duration:20,expectedRevision:null});
const readAgenda=async(id,who=leader)=>(await getDoc(doc(who.db,`groups/${groupID}/smartAgenda/${id}`))).data();
test('multiple meetings append alongside the legacy agenda and enforce leader-only management',async()=>{
 const before=await read(), a=meetingRequest(agendaA,'Planning'), b=meetingRequest(agendaB,'Review');
 await assert.rejects(member.call('createMeeting',a),e=>e.code==='functions/permission-denied');
 await assert.rejects(outsider.call('createMeeting',a),e=>e.code==='functions/permission-denied');
 await Promise.all([leader.call('createMeeting',a),leader.call('createMeeting',b)]);
 await leader.call('createMeeting',a);
 assert.deepEqual(await read(),before);
 const all=await getDocs(collection(member.db,`groups/${groupID}/smartAgenda`));
 assert.equal(all.docs.filter(d=>!d.data().deleted).length,3);
 assert.equal((await readAgenda(agendaA,member)).topic,'Planning');
 await assertFails(getDocs(collection(outsider.db,`groups/${groupID}/smartAgenda`)));
 await assertFails(setDoc(doc(member.db,`groups/${groupID}/smartAgenda/${agendaA}`),{topic:'Bypass'}));
 await assert.rejects(leader.call('createMeeting',{...a,topic:'Overwrite'}),e=>e.code==='functions/already-exists');
 await assert.rejects(leader.call('createMeeting',{...a,agendaID:'../escape'}),e=>e.code==='functions/invalid-argument');
});
test('editing, material preparation and plan generation target only the selected agenda',async()=>{
 const legacy=await read(), untouched=await readAgenda(agendaB), a=await readAgenda(agendaA);
 const edit={agendaID:agendaA,topic:'Updated planning',meetingAtMillis:a.meetingAt.toMillis(),duration:30,expectedRevision:a.meetingRevision};
 await assert.rejects(member.call('meeting',edit),e=>e.code==='functions/permission-denied');
 await leader.call('meeting',edit);
 await leader.call('material',{agendaID:agendaA,note:'Scope',attachment:null,expectedRevision:null});
 await member.call('material',{agendaID:agendaA,note:'Demo',attachment:null,expectedRevision:null});
 const {randomUUID}=await import('node:crypto');
 const prepared=await readAgenda(agendaA);
 assert.equal(prepared.preparedUIDs.length,2);
 const claim={agendaID:agendaA,inputRevision:prepared.inputRevision,token:randomUUID()};
 const result=await leader.call('claimPlan',claim);assert.equal(result.input.duration,30);
 await assert.rejects(leader.call('completePlan',{...claim,agendaID:agendaB,phases:[]}),e=>e.code==='functions/failed-precondition');
 const phases=['Review','Discuss','Decide','Assign'].map(title=>({minutes:5,title,goal:'Confirm decision',titleZhHant:'討論',goalZhHant:'完成決議'}));
 await leader.call('completePlan',{...claim,phases});
 assert.equal((await readAgenda(agendaA,member)).stages.length,4);
 assert.equal((await readAgenda(agendaA,member)).stages.at(-1).end,30);
 assert.deepEqual(await readAgenda(agendaB),untouched);assert.deepEqual(await read(),legacy);
});
test('deleting an agenda cleans its uploads but retains a file used by another meeting',async()=>{
 const storagePath=`groups/${groupID}/agendaMaterials/${member.uid}/cccccccc-cccc-4ccc-8ccc-cccccccccccc/file.pdf`;
 const bytes=new TextEncoder().encode('%PDF-1.7\nMultiple meeting upload\n%%EOF');
 await uploadBytes(ref(member.storage,storagePath),bytes,{contentType:'application/pdf',customMetadata:{uploaderID:member.uid}});
 const attachment={fileName:'Meeting notes.pdf',storagePath,contentType:'application/pdf',byteSize:bytes.length};
 const newID='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
 await leader.call('createMeeting',meetingRequest(newID,'Temporary meeting'));
 await member.call('material',{agendaID:newID,note:'',attachment,expectedRevision:null});
 await member.call('material',{agendaID:agendaB,note:'Keep file',attachment,expectedRevision:null});
 await leader.call('deleteMeeting',{agendaID:newID,expectedRevision:(await readAgenda(newID)).meetingRevision});
 await new Promise(r=>setTimeout(r,800));
 assert.deepEqual(new Uint8Array(await getBytes(ref(leader.storage,storagePath))),bytes);
 const saved=await readAgenda(agendaB);
 await member.call('material',{agendaID:agendaB,note:'Keep note',attachment:null,expectedRevision:saved.materials[member.uid].revision});
 const start=Date.now();let removed=false;
 while(Date.now()-start<15000) {
  try {await getBytes(ref(leader.storage,storagePath));} catch(e) {if(e.code==='storage/object-not-found'){removed=true;break;}throw e;}
  await new Promise(r=>setTimeout(r,100));
 }
 assert.equal(removed,true);
 assert.equal((await readAgenda(agendaB)).materials[member.uid].note,'Keep note');
});

test('deleting one agenda syncs, preserves the others and cannot be undone by a delayed retry',async()=>{
 const a=await readAgenda(agendaA), b=await readAgenda(agendaB), legacy=await read();
 const removal={agendaID:agendaA,expectedRevision:a.meetingRevision};
 await assert.rejects(member.call('deleteMeeting',removal),e=>e.code==='functions/permission-denied');
 await assert.rejects(leader.call('deleteMeeting',{...removal,expectedRevision:'stale'}),e=>e.code==='functions/aborted');
 const observed=new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>{stop();reject(Error('Deletion did not sync'));},10000);
  const stop=onSnapshot(doc(member.db,`groups/${groupID}/smartAgenda/${agendaA}`),s=>{
   if(s.data()?.deleted){clearTimeout(timeout);stop();resolve();}
  },reject);
 });
 await leader.call('deleteMeeting',removal);await observed;
 await leader.call('deleteMeeting',removal);
 const removed=await readAgenda(agendaA);
 assert.deepEqual(Object.keys(removed).sort(),['deleted','updatedAt']);
 await assert.rejects(leader.call('createMeeting',meetingRequest(agendaA,'Resurrect')),e=>e.code==='functions/not-found');
 await assert.rejects(leader.call('meeting',{...meetingRequest(agendaA,'Resurrect'),expectedRevision:a.meetingRevision}),e=>e.code==='functions/not-found');
 await assert.rejects(member.call('material',{agendaID:agendaA,note:'Late preparation',attachment:null,expectedRevision:null}),e=>e.code==='functions/not-found');
 assert.deepEqual(await readAgenda(agendaB),b);assert.deepEqual(await read(),legacy);
});

test('membership changes refresh the denominator and rejoining never restores an old preparation',async()=>{
 // Full-suite trigger queues can take longer than a fixed four-second polling window.
 // Wait for the actual cross-account update; a missing synchronization still fails.
 const waitFor=predicate=>new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>{stop();reject(Error('Membership synchronization timed out'));},15000);
  const stop=onSnapshot(doc(member.db,path),snapshot=>{
   const value=snapshot.data();
   if(value && predicate(value)){clearTimeout(timeout);stop();resolve(value);}
  },error=>{clearTimeout(timeout);stop();reject(error);});
 });
 await seed(outsider.uid,'member');
 await waitFor(a=>a.memberUIDs.length===3);
 const {deleteDoc}=await import('firebase/firestore');
 await env.withSecurityRulesDisabled(c=>deleteDoc(doc(c.firestore(),`groups/${groupID}/members/${leader.uid}`)));
 const left=await waitFor(a=>a.memberUIDs.length===2);
 assert(!left.materials[leader.uid]);
 await seed(leader.uid,'leader');
 const rejoined=await waitFor(a=>a.memberUIDs.length===3);
 assert(!rejoined.materials[leader.uid]); assert.deepEqual(rejoined.stages,[]);
 const start=Date.now();
 while ((await readAgenda(agendaB)).memberUIDs.length!==3 && Date.now()-start<15000) await new Promise(r=>setTimeout(r,100));
 assert.equal((await readAgenda(agendaB)).memberUIDs.length,3);
 assert.equal((await readAgenda(agendaA)).deleted,true);
});
