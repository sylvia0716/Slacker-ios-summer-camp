import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInAnonymously} from 'firebase/auth';
import {getFunctions, connectFunctionsEmulator, httpsCallable} from 'firebase/functions';
import {getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc, updateDoc, Timestamp, onSnapshot} from 'firebase/firestore';
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

test('clients cannot publish AI output; server-owned plan and meeting timer are shared',async()=>{
 await assert.rejects(leader.call('claim'),e=>e.code==='functions/invalid-argument');
 await assert.rejects(member.call('publish',{token:'fake',phases:[]}),e=>e.code==='functions/invalid-argument');
 // Provider and concurrency behavior are covered separately in smart-agenda-workflow.test.js.
 const stages=[{start:0,end:5,title:'Review materials',goal:'Confirm the opening'},
  {start:5,end:12,title:'Decide order',goal:'Choose features'},{start:12,end:20,title:'Finalize',goal:'Assign revisions'}];
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),path),{stages,planState:'ready',generation:null,planSource:'test'}));
 const value=await read(leader);
 assert.deepEqual(value.stages.map(s=>[s.start,s.end]),[[0,5],[5,12],[12,20]]);
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

test('membership changes refresh the denominator and rejoining never restores an old preparation',async()=>{
 const waitFor=async predicate=>{
  for(let i=0;i<40;i++){ const value=await read(member); if(predicate(value)) return value; await new Promise(r=>setTimeout(r,100)); }
  throw Error('Membership synchronization timed out');
 };
 await seed(outsider.uid,'member');
 await waitFor(a=>a.memberUIDs.length===3);
 const {deleteDoc}=await import('firebase/firestore');
 await env.withSecurityRulesDisabled(c=>deleteDoc(doc(c.firestore(),`groups/${groupID}/members/${leader.uid}`)));
 const left=await waitFor(a=>a.memberUIDs.length===2);
 assert(!left.materials[leader.uid]);
 await seed(leader.uid,'leader');
 const rejoined=await waitFor(a=>a.memberUIDs.length===3);
 assert(!rejoined.materials[leader.uid]); assert.deepEqual(rejoined.stages,[]);
});
