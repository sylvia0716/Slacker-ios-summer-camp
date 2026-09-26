const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const gid = '11111111-1111-4111-8111-111111111111';
function setup(uids) {
  const documents = new Map([[`groups/${gid}`, {}], ...uids.map((uid, i) => [`groups/${gid}/members/${uid}`, {userID: uid, role: i === 0 ? 'leader' : 'member'}])]);
  let storageFailures = 0;
  const removedPrefixes = [];
  const snapshot = ref => ({ref, id: ref.id, exists: documents.has(ref.path), data: () => documents.get(ref.path)});
  function collection(path) {
    return {path, doc: id => reference(`${path}/${id}`), limit() {return this;}, where(field, op, value) {return {...this, filter: d => d[field] === value};}, async get() {
      const docs = [...documents.keys()].filter(p => p.startsWith(path+'/') && !p.slice(path.length+1).includes('/'))
        .map(p => snapshot(reference(p))).filter(d => !this.filter || this.filter(d.data()));
      return {docs, empty: docs.length === 0};
    }};
  }
  function reference(path) {return {path, id: path.split('/').at(-1), collection: name => collection(`${path}/${name}`),
    get: async () => snapshot(reference(path)), delete: async () => documents.delete(path),
    listCollections: async () => [...new Set([...documents.keys()].filter(p => p.startsWith(path+'/')).map(p => p.slice(path.length+1).split('/')[0]))].map(name => collection(`${path}/${name}`))};}
  const db = {collection, runTransaction: async fn => {
    const writes = [];
    const result = await fn({get: ref => ref.get(), delete: ref => writes.push(() => documents.delete(ref.path)),
      update: (ref, data) => writes.push(() => documents.set(ref.path, {...documents.get(ref.path), ...data}))});
    writes.forEach(f => f()); return result;
  }, recursiveDelete: async ref => {for(const key of documents.keys()) if(key.startsWith(ref.path+'/')) documents.delete(key);}};
  class HttpsError extends Error {constructor(code, message) {super(message); this.code=code;}}
  const context = {exports:{}, require: name => {
    if(name === 'firebase-admin/app') return {initializeApp(){}};
    if(name === 'firebase-admin/auth') return {getAuth:()=>({getUser:async()=>({displayName:'Test'})})};
    if(name === 'firebase-admin/messaging') return {getMessaging:()=>({sendEachForMulticast:async()=>({responses:[]})})};
    if(name === 'node:crypto') return require('node:crypto');
    if(name === './poke-notification') return require('./poke-notification');
    if(name === './member-display-name') return {memberDisplayName:()=> 'Test'};
    if(name === './task-progress' || name === './group-membership' || name === './peer-review' || name === './smart-agenda') return {};
    if(name === 'firebase-admin/firestore') return {getFirestore:()=>db, FieldValue:{serverTimestamp:()=>1}, Timestamp:class Timestamp {}};
    if(name === 'firebase-admin/storage') return {getStorage:()=>({bucket:()=>({deleteFiles:async ({prefix})=>{if(storageFailures-- > 0) throw Error('storage unavailable'); removedPrefixes.push(prefix);}})})};
    if(name === 'firebase-functions/v2/https') return {onCall:(opts,fn)=>fn, HttpsError};
    if(name === 'firebase-functions/v2/firestore') return {onDocumentCreated:(opts,fn)=>fn, onDocumentUpdated:(opts,fn)=>fn};
    throw Error(name);
  }};
  vm.runInNewContext(fs.readFileSync(__dirname+'/group-membership.js','utf8'),context);
  const joinContext = {...context, exports:{}};
  vm.runInNewContext(fs.readFileSync(__dirname+'/index.js','utf8'),joinContext);
  return {join: code => joinContext.exports.joinGroupByInviteCode({auth:{uid:'new'},data:{inviteCode:code}}), documents, removedPrefixes, failStorage:()=>storageFailures++, leave: uid => context.exports.leaveGroup({auth:{uid},data:{groupID:gid}}),
    remove: (uid, memberUID) => context.exports.removeGroupMember({auth:{uid},data:{groupID:gid,memberUID}}),
    choose: (uid, candidateUID, action, electionID) => context.exports.chooseGroupLeader({auth:{uid},data:{groupID:gid,candidateUID,action,...(electionID ? {electionID} : {})}}),
    decide: (uid, departureID, included) => context.exports.setDepartedTasksInclusion({auth:{uid},data:{groupID:gid,departureID,included}}),
    call: context.exports.leaveGroup, clean:()=>context.exports.cleanupEmptyGroup({params:{groupID:gid},data:{after:{data:()=>({deleting:true})}}})};
}
test('leader removes a member and detaches their tasks without removing other members', async()=>{
 const s=setup(['leader','member','other']);
 const path=`groups/${gid}/tasks/assigned`;
 s.documents.set(path,{ownerMemberID:'member',subtasks:[{weight:1,isComplete:true},{weight:1,isComplete:false}]});
 await s.remove('leader','member');
 assert(!s.documents.has(`groups/${gid}/members/member`));
 assert(s.documents.has(`groups/${gid}/members/other`));
 assert.equal(s.documents.get(path).ownerMemberID,null);
 assert.equal(s.documents.get(path).departedProgress,50);
});
test('only the leader can remove another current member', async()=>{
 const s=setup(['leader','member','other']);
 await assert.rejects(s.remove('member','other'),e=>e.code==='permission-denied');
 await assert.rejects(s.remove('outsider','member'),e=>e.code==='permission-denied');
 await assert.rejects(s.remove('leader','leader'),e=>e.code==='invalid-argument');
 await assert.rejects(s.remove('leader','missing'),e=>e.code==='failed-precondition');
 assert(s.documents.has(`groups/${gid}/members/member`));
});
test('only caller leaves; another member and task remain; leadership transfers', async()=>{
 const s=setup(['a','b']); s.documents.set(`groups/${gid}/tasks/t`,{title:'Keep'});
 await s.leave('a'); assert(!s.documents.has(`groups/${gid}/members/a`));
 assert.equal(s.documents.get(`groups/${gid}/members/b`).role,'leader');
 assert(s.documents.has(`groups/${gid}/tasks/t`)); assert.notEqual(s.documents.get(`groups/${gid}`).deleting,true);
});
test('outsider cannot remove members or request another user exit',async()=>{
 const s=setup(['a']); await s.leave('outsider'); assert(s.documents.has(`groups/${gid}/members/a`));
 await assert.rejects(s.call({auth:{uid:'a'},data:{groupID:gid,userID:'b'}}), e=>e.code==='invalid-argument');
 await assert.rejects(s.call({data:{groupID:gid}}),e=>e.code==='unauthenticated');
});
test('last exit marks group; cleanup removes nested data and every invite; repeated exit safe',async()=>{
 const s=setup(['a']); s.documents.set(`groups/${gid}/tasks/t/attachments/x`,{});
 s.documents.set(`groupInviteCodes/ABC123`,{groupID:gid}); s.documents.set('groupInviteCodes/OTHER1',{groupID:'other'});
 await s.leave('a'); await s.leave('a'); assert.equal(s.documents.get(`groups/${gid}`).deleting,true);
 await s.clean(); await s.clean(); assert(!s.documents.has(`groups/${gid}`));
 assert(!s.documents.has(`groups/${gid}/tasks/t/attachments/x`)); assert(!s.documents.has('groupInviteCodes/ABC123'));
 assert(s.documents.has('groupInviteCodes/OTHER1')); assert.deepEqual(s.removedPrefixes,[`groups/${gid}/`]);
});
test('failed file cleanup preserves marker for retry',async()=>{
 const s=setup(['a']); await s.leave('a'); s.failStorage(); await assert.rejects(s.clean());
 assert.equal(s.documents.get(`groups/${gid}`).deleting,true); await s.clean(); assert(!s.documents.has(`groups/${gid}`));
});
test('cleanup refuses a group that still has a member',async()=>{
 const s=setup(['a']); s.documents.set(`groups/${gid}`,{deleting:true}); await assert.rejects(s.clean());
 assert(s.documents.has(`groups/${gid}/members/a`)); assert.equal(s.removedPrefixes.length,0);
});

test('invite cannot admit a new member once final exit has marked cleanup', async()=>{
 const s=setup(['a']); s.documents.set('groupInviteCodes/ABC123',{groupID:gid,isActive:true});
 await s.leave('a'); await assert.rejects(s.join('ABC123'),e=>e.code==='not-found');
 assert(!s.documents.has(`groups/${gid}/members/new`));
});

test('invite cannot add a new member after the group deadline', async()=>{
 const s=setup(['a']);
 s.documents.set(`groups/${gid}`, {deadline:{toMillis:()=>Date.now()-1}});
 s.documents.set('groupInviteCodes/ABC123',{groupID:gid,isActive:true});
 await assert.rejects(s.join('ABC123'),e=>e.code==='failed-precondition');
 assert(!s.documents.has(`groups/${gid}/members/new`));
});

test('exit detaches tasks, freezes progress and keeps them included; rejoin cannot reclaim them', async()=>{
 const s=setup(['leader','member']);
 const path=`groups/${gid}/tasks/old`;
 s.documents.set(path,{ownerMemberID:'member',subtasks:[{weight:1,isComplete:true},{weight:3,isComplete:false}]});
 await s.leave('member');
 const task=s.documents.get(path);
 assert.equal(task.ownerMemberID,null);
 assert.equal(task.departedProgress,25);
 assert.equal(task.includedInProgress,true);
 assert.equal(task.departureReviewed,false);
 assert(task.departureID);
 s.documents.set(`groups/${gid}/members/member`,{userID:'member',role:'member'});
 assert.equal(s.documents.get(path).ownerMemberID,null);
 await assert.rejects(s.decide('member',task.departureID,false),e=>e.code==='permission-denied');
 await assert.rejects(s.decide('outsider',task.departureID,false),e=>e.code==='permission-denied');
 await s.decide('leader',task.departureID,false);
 assert.equal(s.documents.get(path).includedInProgress,false);
 assert.equal(s.documents.get(path).departureReviewed,true);
 assert.equal(s.documents.get(path).departedProgress,25);
 await s.decide('leader',task.departureID,true);
 assert.equal(s.documents.get(path).includedInProgress,true);
});
test('leader decision covers one departure only, preserving another member task',async()=>{
 const s=setup(['leader','member','other']);
 s.documents.set(`groups/${gid}/tasks/a`,{ownerMemberID:'member',subtasks:[]});
 s.documents.set(`groups/${gid}/tasks/b`,{ownerMemberID:'member',subtasks:[]});
 s.documents.set(`groups/${gid}/tasks/c`,{ownerMemberID:'other',subtasks:[]});
 await s.leave('member');
 const departure=s.documents.get(`groups/${gid}/tasks/a`).departureID;
 await s.decide('leader',departure,false);
 assert.equal(s.documents.get(`groups/${gid}/tasks/b`).includedInProgress,false);
 assert.equal(s.documents.get(`groups/${gid}/tasks/c`).ownerMemberID,'other');
 assert.equal(s.documents.get(`groups/${gid}/tasks/c`).includedInProgress,undefined);
});

test('only current leader can transfer leadership; all roles change atomically',async()=>{
 const s=setup(['a','b','c']);
 await assert.rejects(s.choose('b','c','transfer'),e=>e.code==='permission-denied');
 await assert.rejects(s.choose('outsider','c','transfer'),e=>e.code==='permission-denied');
 await assert.rejects(s.choose('a','missing','transfer'),e=>e.code==='failed-precondition');
 await s.choose('a','b','transfer');
 assert.equal(s.documents.get(`groups/${gid}/members/a`).role,'member');
 assert.equal(s.documents.get(`groups/${gid}/members/b`).role,'leader');
 await assert.rejects(s.choose('a','c','transfer'),e=>e.code==='permission-denied');
});
test('leader exit starts election; tie stays open and changed vote elects majority',async()=>{
 const s=setup(['a','b','c']); await s.leave('a');
 const election=s.documents.get(`groups/${gid}`).leaderElectionID;
 assert(election);
 assert.equal(s.documents.get(`groups/${gid}/members/b`).role,'member');
 await s.choose('b','b','vote',election);
 await s.choose('c','c','vote',election);
 assert.equal(s.documents.get(`groups/${gid}`).leaderElectionID,election);
 await s.choose('c','b','vote',election);
 assert.equal(s.documents.get(`groups/${gid}/members/b`).role,'leader');
 assert.equal(s.documents.get(`groups/${gid}`).leaderElectionID,null);
 await assert.rejects(s.choose('c','c','vote',election),e=>e.code==='failed-precondition');
});
test('voting twice does not add votes and an obsolete election cannot be used',async()=>{
 const s=setup(['a','b','c','d']); await s.leave('a');
 const election=s.documents.get(`groups/${gid}`).leaderElectionID;
 await s.choose('b','c','vote',election); await s.choose('b','c','vote',election);
 assert.equal(s.documents.get(`groups/${gid}/members/c`).role,'member');
 await assert.rejects(s.choose('d','c','vote','22222222-2222-4222-8222-222222222222'),e=>e.code==='failed-precondition');
 await s.choose('c','c','vote',election);
 assert.equal(s.documents.get(`groups/${gid}/members/c`).role,'leader');
});
test('departing candidate votes are removed; last remaining member becomes leader',async()=>{
 const s=setup(['a','b','c','d']); await s.leave('a');
 const election=s.documents.get(`groups/${gid}`).leaderElectionID;
 await s.choose('b','c','vote',election); await s.leave('c');
 assert.equal(s.documents.get(`groups/${gid}/members/b`).leaderVoteUID,null);
 await s.leave('d');
 assert.equal(s.documents.get(`groups/${gid}/members/b`).role,'leader');
 assert.equal(s.documents.get(`groups/${gid}`).leaderElectionID,null);
});
