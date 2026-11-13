const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const gid = '11111111-1111-4111-8111-111111111111';
function fixture() {
  const documents = new Map([
    [`groups/${gid}`, {name:'Team',deadline:{toMillis:()=>Date.now()+60000}}],
    [`groups/${gid}/members/leader`, {userID:'leader',role:'leader'}],
    ['groupInviteCodes/ABC123',{groupID:gid,isActive:true}],
  ]);
  const snap = ref => ({ref,id:ref.id,exists:documents.has(ref.path),data:()=>documents.get(ref.path)});
  function collection(path) { return {path,doc:id=>ref(`${path}/${id}`),get:async()=>({docs:[...documents.keys()]
    .filter(p=>p.startsWith(path+'/') && !p.slice(path.length+1).includes('/')).map(p=>snap(ref(p)))})}; }
  function ref(path) {return {path,id:path.split('/').at(-1),collection:name=>collection(`${path}/${name}`),get:async()=>snap(ref(path))};}
  const db = {collection,runTransaction:async fn=>{
    const writes=[]; const result=await fn({get:r=>r.get(),
      create:(r,d)=>writes.push(()=>{assert(!documents.has(r.path));documents.set(r.path,d);}),
      set:(r,d)=>writes.push(()=>documents.set(r.path,d)),
      update:(r,d)=>writes.push(()=>documents.set(r.path,{...documents.get(r.path),...d}))});
    writes.forEach(f=>f()); return result;
  }};
  class HttpsError extends Error {constructor(code,message){super(message);this.code=code;}}
  const context={exports:{},require:name=>{
    if(name==='firebase-admin/app') return {initializeApp(){}};
    if(name==='firebase-admin/firestore') return {getFirestore:()=>db,FieldValue:{serverTimestamp:()=>123},Timestamp:class{}};
    if(name==='firebase-admin/auth') return {getAuth:()=>({getUser:async()=>({displayName:'Applicant'})})};
    if(name==='firebase-admin/storage') return {getStorage:()=>({})};
    if(name==='firebase-admin/messaging') return {getMessaging:()=>({})};
    if(name==='firebase-functions/v2/https') return {onCall:(_,fn)=>fn,HttpsError};
    if(name==='firebase-functions/v2/firestore') return {onDocumentCreated:(_,fn)=>fn};
    if(['./group-admission','./group-membership','./task-progress','./peer-review','./smart-agenda','./smart-agenda-reminders'].includes(name)) return {};
    return require(name);
  }};
  vm.runInNewContext(fs.readFileSync(__dirname+'/index.js','utf8'),context);
  const admission={...context,exports:{}};
  vm.runInNewContext(fs.readFileSync(__dirname+'/group-admission.js','utf8'),admission);
  const application=()=>documents.get(`groups/${gid}/joinRequests/applicant`);
  return {documents,application,
    join:(uid='applicant',inviteCode='ABC123')=>context.exports.joinGroupByInviteCode({auth:{uid},data:{inviteCode}}),
    review:(uid='leader',decision='approved',requestID=application()?.requestID)=>admission.exports.reviewGroupJoinRequest({auth:{uid},data:{groupID:gid,applicantID:'applicant',requestID,decision}}),
    profile:(uid='leader')=>admission.exports.getJoinApplicantProfile({auth:{uid},data:{groupID:gid,applicantID:'applicant',requestID:application()?.requestID}}),
  };
}
test('join creates one pending application, no membership; retries preserve request identity',async()=>{
 const s=fixture(); const first=await s.join(); const id=s.application().requestID;
 assert.equal(first.status,'pending'); assert.equal(first.alreadyMember,false);
 await s.join(); assert.equal(s.application().requestID,id);
 assert(!s.documents.has(`groups/${gid}/members/applicant`));
 assert.equal(s.documents.get(`users/applicant/groupJoinRequests/${gid}`).status,'pending');
});
test('only leader can review; approving creates member atomically and retries are safe',async()=>{
 const s=fixture(); await s.join();
 for(const uid of ['applicant','outsider']) await assert.rejects(s.review(uid),e=>e.code==='permission-denied');
 await s.review(); await s.review();
 assert.equal(s.documents.get(`groups/${gid}/members/applicant`).role,'member');
 assert.equal(s.documents.get(`users/applicant/groupJoinRequests/${gid}`).status,'approved');
 await assert.rejects(s.review('leader','rejected'),e=>e.code==='failed-precondition');
 assert.equal((await s.join()).alreadyMember,true);
});
test('rejection grants no access; reapplication has a new identity and rejects stale decisions',async()=>{
 const s=fixture(); await s.join(); const old=s.application().requestID;
 await s.review('leader','rejected'); assert(!s.documents.has(`groups/${gid}/members/applicant`));
 await s.join(); assert.notEqual(s.application().requestID,old);
 await assert.rejects(s.review('leader','approved',old),e=>e.code==='failed-precondition');
});
test('profile returns only published summaries for a pending applicant to the current leader',async()=>{
 const s=fixture(); await s.join();
 s.documents.set('users/applicant/peerReviewProjects/p',{groupName:'Past',reviewCount:2,taskCompletionScoreTotal:8,
   completedAt:{toMillis:()=>42},comment:'private',reviewerUID:'private'});
 const result=await s.profile(); assert.equal(result.projects[0].taskCompletionScore,4);
 assert.equal(result.projects[0].comment,undefined); assert.equal(result.projects[0].reviewerUID,undefined);
 await assert.rejects(s.profile('applicant'),e=>e.code==='permission-denied');
 await assert.rejects(s.profile('outsider'),e=>e.code==='permission-denied');
 await s.review(); await assert.rejects(s.profile(),e=>e.code==='failed-precondition');
});
test('new applicants have an empty profile; expired groups cannot approve; transferred leaders lose access',async()=>{
 const s=fixture(); await s.join(); assert.equal((await s.profile()).projects.length,0);
 s.documents.set(`groups/${gid}`,{deadline:{toMillis:()=>0}});
 await assert.rejects(s.review(),e=>e.code==='failed-precondition');
 assert.equal(s.application().status,'pending');
 s.documents.set(`groups/${gid}/members/leader`,{userID:'leader',role:'member'});
 await assert.rejects(s.profile(),e=>e.code==='permission-denied');
});
