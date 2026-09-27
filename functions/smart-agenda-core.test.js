const {test} = require('node:test');
const assert = require('node:assert/strict');
const {timedStages, invalidateAgenda, membershipSignature} = require('./smart-agenda-core');
const phases = weights => weights.map((minutes,i) => ({title:`Discussion ${i}`,goal:`Decide ${i}`,minutes}));
test('3–4 phases cover every supported duration exactly without zero slots or gaps', () => {
  for (let duration=5; duration<=180; duration++) {
    for (const weights of [[5,7,8],[1,180,1],[2,3,3,2],[180,1,1,1]]) {
      const stages = timedStages(phases(weights),duration);
      assert.equal(stages[0].start,0);
      assert.equal(stages.at(-1).end,duration);
      stages.forEach((s,i) => { assert(s.end>s.start); if(i) assert.equal(s.start,stages[i-1].end); });
    }
  }
  assert.deepEqual(timedStages(phases([5,7,8]),20).map(s=>[s.start,s.end]),[[0,5],[5,12],[12,20]]);
});
test('invalid or missing goals and excessive phase counts are rejected', () => {
  for (const value of [phases([1,2]),phases([1,2,3,4,5]),phases([1,0,3]),phases([1,2.5,3]),
    [{title:'Review',goal:'',minutes:5},...phases([7,8])]]) assert.throws(()=>timedStages(value,20));
});
test('empty preparations, departed members and previous membership materials do not count', () => {
  const members=[{id:'leader',joinedAt:{seconds:1,nanoseconds:0}},{id:'member',joinedAt:{seconds:2,nanoseconds:0}}];
  const current={topic:'Demo',duration:20,materials:{
    leader:{note:'Decide the script',membershipVersion:'1.0'},member:{note:'Old',membershipVersion:'1.0'},
    departed:{note:'Old',membershipVersion:'1.0'}},stages:phases([5,7,8]),generation:{token:'old'},meetingStartedAt:null};
  const next=invalidateAgenda(current,members);
  assert.deepEqual(next.preparedUIDs,['leader']); assert.equal(next.memberUIDs.length,2);
  assert.equal(next.generation,null); assert.equal(next.meetingStartedAt,null); assert.deepEqual(next.stages,[]);
  current.materials.member={note:'',attachment:{fileName:'Deck.pdf'},membershipVersion:'2.0'};
  assert.equal(invalidateAgenda(current,members).preparedUIDs.length,2);
  current.materials.member={note:'  ',membershipVersion:'2.0'};
  assert.equal(invalidateAgenda(current,members).preparedUIDs.length,1);
});
test('preparation changes preserve a meeting in progress until it ends', () => {
  const members=[{id:'leader'},{id:'member'}], started={toMillis:()=>1000};
  const current={materials:{leader:{note:'Opening',membershipVersion:'legacy'},
    member:{note:'Order',membershipVersion:'legacy'}},memberUIDs:['leader','member'],
    preparedUIDs:['leader','member'],inputRevision:'published',stages:phases([5,7,8]),
    planState:'ready',planSource:'appleIntelligence',meetingStartedAt:started};
  const during=invalidateAgenda({...current,materials:{...current.materials,
    member:{note:'Updated order',membershipVersion:'legacy'}}},members);
  assert.equal(during.meetingStartedAt,started);
  assert.equal(during.inputRevision,'published');
  assert.deepEqual(during.stages,current.stages);
  assert.equal(during.preparationChangedDuringMeeting,true);
  const after=invalidateAgenda({...during,meetingStartedAt:null},members);
  assert.equal(after.meetingStartedAt,null);
  assert.deepEqual(after.stages,[]);
  assert.equal(after.preparationChangedDuringMeeting,false);
});
test('membership fingerprint ignores role/name edits but catches rejoining', () => {
  const member={id:'one',role:'leader',displayName:'Name',joinedAt:{seconds:1,nanoseconds:123}};
  assert.equal(membershipSignature([member]),membershipSignature([{...member,role:'member',displayName:'New'}]));
  assert.notEqual(membershipSignature([member]),membershipSignature([{...member,joinedAt:{seconds:2,nanoseconds:123}}]));
});

test('multiple entries count unique owners and all entries are removed on departure or rejoin', () => {
 const members=[{id:'a'},{id:'b'}];
 const materials={a:{note:'Legacy',membershipVersion:'legacy'},
  one:{ownerUID:'a',note:'First',membershipVersion:'legacy'},
  two:{ownerUID:'a',note:'Second',membershipVersion:'legacy'},
  three:{ownerUID:'b',note:'Other',membershipVersion:'legacy'}};
 const next=invalidateAgenda({materials},members);
 assert.equal(Object.keys(next.materials).length,4);
 assert.deepEqual(next.preparedUIDs,['a','b']);
 const left=invalidateAgenda(next,[{id:'b'}]);
 assert.deepEqual(Object.keys(left.materials),['three']);
 const rejoined=invalidateAgenda(next,[{id:'a',joinedAt:{seconds:10,nanoseconds:0}},{id:'b'}]);
 assert.deepEqual(Object.keys(rejoined.materials),['three']);
});
