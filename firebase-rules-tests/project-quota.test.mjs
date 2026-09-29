import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {before, after, test} from 'node:test';
import {initializeTestEnvironment, assertFails} from '@firebase/rules-unit-testing';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInAnonymously} from 'firebase/auth';
import {getFunctions, connectFunctionsEmulator, httpsCallable} from 'firebase/functions';
import {doc, getDoc, setDoc, updateDoc, Timestamp} from 'firebase/firestore';

const projectId = 'demo-group-bomb';
let env;
const apps = [];
before(async()=>{
  env = await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:8080,
    rules:readFileSync(new URL('../firestore.rules',import.meta.url),'utf8')}});
});
after(async()=>{await Promise.all(apps.map(deleteApp)); await env?.cleanup();});
async function client() {
  const app = initializeApp({projectId,apiKey:'demo-key',authDomain:`${projectId}.firebaseapp.com`},`quota-${apps.length}`);
  apps.push(app);
  const auth=getAuth(app); connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
  const {user}=await signInAnonymously(auth);
  const functions=getFunctions(app,'asia-east1'); connectFunctionsEmulator(functions,'127.0.0.1',5001);
  const call=(name,data)=>httpsCallable(functions,name)(data).then(r=>r.data);
  return {uid:user.uid,
    create:()=>call('createGroup',{name:'Quota test',displayName:'Tester',deadlineMillis:Date.now()+86400000}),
    join:group=>call('joinGroupByInviteCode',{inviteCode:group.inviteCode}),
    review:(group,applicant,requestID,decision='approved')=>call('reviewGroupJoinRequest',{
      groupID:group.groupID,applicantID:applicant.uid,requestID,decision}),
  };
}
async function application(group,applicant) {
  let result;
  await env.withSecurityRulesDisabled(async ctx=>{
    result=(await getDoc(doc(ctx.firestore(),`groups/${group.groupID}/joinRequests/${applicant.uid}`))).data();
  });
  return result;
}
const quotaError=e=>e.code==='functions/resource-exhausted' && e.details?.reason==='active-project-limit';

test('create + approved join share capacity; overflow cannot write and settled projects release capacity',async()=>{
  const owner=await client(), user=await client();
  const {group}=await owner.create(); const first=await user.create();
  assert.notEqual(owner.uid,user.uid);
  assert.equal((await user.join(group)).status,'pending'); const request=await application(group,user);
  await owner.review(group,user,request.requestID);
  await assert.rejects(user.create(),quotaError);
  assert.equal((await user.join(group)).alreadyMember,true);
  const another=await owner.create(); await assert.rejects(user.join(another.group),quotaError);
  await env.withSecurityRulesDisabled(ctx=>updateDoc(doc(ctx.firestore(),`groups/${first.group.groupID}`),{settledAt:Timestamp.now()}));
  await user.create(); await assert.rejects(user.create(),quotaError);
});

test('concurrent create and approval cannot both consume the final slot; failed approval stays pending',async()=>{
  const owner=await client(), user=await client();
  const {group}=await owner.create(); await user.create(); await user.join(group);
  const request=await application(group,user);
  const results=await Promise.allSettled([user.create(),owner.review(group,user,request.requestID)]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert(quotaError(results.find(r=>r.status==='rejected').reason));
  await assert.rejects(user.create(),quotaError);
  const current=await application(group,user);
  if(results[1].status==='rejected') {
    assert.equal(current.status,'pending');
    await owner.review(group,user,request.requestID,'rejected');
    assert.equal((await application(group,user)).status,'rejected');
  } else assert.equal(current.status,'approved');
});

test('parallel creates enforce limit and clients cannot manipulate quota locks',async()=>{
  const user=await client();
  const results=await Promise.allSettled([user.create(),user.create(),user.create()]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,2);
  assert(quotaError(results.find(r=>r.status==='rejected').reason));
  const db=env.authenticatedContext(user.uid).firestore();
  await assertFails(getDoc(doc(db,`projectQuotaLocks/${user.uid}`)));
  await assertFails(setDoc(doc(db,`projectQuotaLocks/${user.uid}`),{revision:'bypass'}));
});
