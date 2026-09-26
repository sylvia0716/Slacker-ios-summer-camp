const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const core=require('./smart-agenda-core');
function setup(generate) {
 const members=[{id:'a',role:'leader'},{id:'b',role:'member'}];
 let agenda={...core.invalidateAgenda({topic:'Demo',duration:20,materials:{
  a:{note:'Opening',revision:'a1',membershipVersion:'legacy'},b:{note:'Order',revision:'b1',membershipVersion:'legacy'}
 }},members),meetingRevision:'m1'};
 const ref={path:'groups/11111111-1111-4111-8111-111111111111/smartAgenda/current',parent:{parent:null}};
 const memberQuery={kind:'members',doc:id=>({kind:'member',id,get:async()=>({exists:members.some(m=>m.id===id)})})};
 const group={kind:'group',collection:name=>name==='members'?memberQuery:{doc:()=>ref}};
 ref.parent.parent=group;
 const snapshot=()=>({exists:true,ref,data:()=>agenda});
 let tail=Promise.resolve();
 const db={collection:()=>({doc:()=>group}),runTransaction(fn){
  const run=tail.then(async()=>{
   const writes=[];
   const result=await fn({get:async target=>target===ref?snapshot():target===group?{exists:true,data:()=>({})}:{docs:members.map(m=>({id:m.id,data:()=>m}))},
    set:(_,data)=>writes.push(()=>{agenda=data;}),update:(_,data)=>writes.push(()=>{agenda={...agenda,...data};})});
   writes.forEach(w=>w());return result;
  });tail=run.catch(()=>{});return run;
 }};
 class HttpsError extends Error {constructor(code,message){super(message);this.code=code;}}
 let calls=0;
 const context={exports:{},URL,console:{warn(){}},require:name=>{
  if(name==='node:crypto')return require(name);
  if(name==='./smart-agenda-core')return core;
  if(name==='./smart-agenda-ai')return {model:'test-model',generatePlan:async input=>{calls++;return generate(input);}};
  if(name==='firebase-admin/firestore')return {getFirestore:()=>db,FieldValue:{serverTimestamp:()=>({toMillis:()=>Date.now()})},Timestamp:{fromMillis:value=>({toMillis:()=>value})}};
  if(name==='firebase-admin/storage')return {getStorage(){throw Error('Unexpected Storage call');}};
  if(name==='firebase-functions/v2/https')return {onCall:(_,fn)=>fn,HttpsError};
  if(name==='firebase-functions/v2/firestore')return {onDocumentWritten:(_,fn)=>fn};
  if(name==='firebase-functions/params')return {defineSecret:()=>({value:()=> 'test-key'})};
  throw Error(name);
 }};
 vm.runInNewContext(fs.readFileSync(__dirname+'/smart-agenda.js','utf8'),context);
 return {get agenda(){return agenda;},set agenda(value){agenda=value;},members,get calls(){return calls;},
  trigger:()=>context.exports.generateSmartAgendaPlan({params:{groupID:'test'},data:{after:snapshot()}}),
  call:(action,fields={},uid='a')=>context.exports.updateSmartAgenda({auth:{uid},data:{groupID:'11111111-1111-4111-8111-111111111111',action,...fields}})};
}
const stages=[{start:0,end:5,title:'Opening',goal:'Approve hook'},{start:5,end:12,title:'Order',goal:'Choose features'},{start:12,end:20,title:'Owners',goal:'Assign edits'}];
test('all-prepared produces one server plan; duplicate events do not charge twice',async()=>{
 let finish,started;const began=new Promise(r=>{started=r;});
 const s=setup(async()=>{started();return new Promise(r=>{finish=r;});});
 const first=s.trigger();await began;await s.trigger();assert.equal(s.calls,1);
 finish(stages);await first;assert.equal(s.agenda.planState,'ready');assert.equal(s.agenda.planSource,'openai');
 assert.deepEqual(s.agenda.stages,stages);await s.trigger();assert.equal(s.calls,1);
});
test('editing preparation during generation discards the old response',async()=>{
 let finish,started;const began=new Promise(r=>{started=r;});
 const s=setup(async()=>{started();return new Promise(r=>{finish=r;});});
 const running=s.trigger();await began;
 await s.call('material',{note:'New opening',attachment:null,expectedRevision:'a1'});
 finish(stages);await running;assert.equal(s.agenda.planState,'waiting');assert.equal(s.agenda.stages.length,0);
});
test('membership changes invalidate a completed response',async()=>{
 let finish,started;const began=new Promise(r=>{started=r;});
 const s=setup(async()=>{started();return new Promise(r=>{finish=r;});});
 const running=s.trigger();await began;s.members.push({id:'c',role:'member'});
 finish(stages);await running;assert.equal(s.agenda.memberUIDs.length,3);assert.equal(s.agenda.stages.length,0);
});
test('missing preparation never calls AI; quota failure is shared and does not loop',async()=>{
 const s=setup(async()=>{throw Object.assign(Error('Do not expose provider text'),{code:'quota'});});
 const prepared=s.agenda;s.agenda={...prepared,preparedUIDs:['a']};await s.trigger();assert.equal(s.calls,0);
 s.agenda=prepared;await s.trigger();assert.equal(s.agenda.planState,'failed');assert.equal(s.agenda.planError,'quota');
 await s.trigger();assert.equal(s.calls,1);
 await assert.rejects(s.call('retry'),e=>e.code==='resource-exhausted');
 s.agenda={...s.agenda,lastGenerationAt:{toMillis:()=>0}};await s.call('retry');assert.equal(s.agenda.planState,'waiting');
});
test('clients cannot publish arbitrary plans, and outsiders cannot retry',async()=>{
 const s=setup(async()=>stages);
 await assert.rejects(s.call('publish',{token:'fake',phases:[]}),e=>e.code==='invalid-argument');
 await assert.rejects(s.call('claim'),e=>e.code==='invalid-argument');
 await assert.rejects(s.call('retry',{},'outside'),e=>e.code==='permission-denied');
});
test('members can generate at least five plans after revising their own materials',async()=>{
 const s=setup(async()=>stages);
 for(let attempt=1;attempt<=5;attempt++) {
  await s.call('material',{note:`Revised discussion ${attempt}`,attachment:null,expectedRevision:s.agenda.materials.b.revision},'b');
  await s.trigger();
  assert.equal(s.agenda.planState,'ready');
  assert.equal(s.calls,attempt);
 }
});
test('the edit entry changes only the caller material and keeps meeting edits leader-only',async()=>{
 const s=setup(async()=>stages),leaderMaterial=s.agenda.materials.a;
 await s.call('material',{note:'My updated preparation',attachment:null,expectedRevision:'b1'},'b');
 assert.equal(s.agenda.materials.b.note,'My updated preparation');
 assert.deepEqual(s.agenda.materials.a,leaderMaterial);
 await assert.rejects(s.call('meeting',{topic:'Unauthorized change',meetingAtMillis:Date.now(),duration:20,expectedRevision:'m1'},'b'),e=>e.code==='permission-denied');
 await s.call('meeting',{topic:'Updated meeting',meetingAtMillis:Date.now(),duration:20,expectedRevision:'m1'},'a');
 assert.equal(s.agenda.topic,'Updated meeting');
});

const firstID='aaaaaaaa-1111-4111-8111-111111111111', secondID='bbbbbbbb-2222-4222-8222-222222222222';
const newMaterial=(materialID,note)=>({materialID,note,attachment:null,expectedRevision:null});
test('adding entries preserves the original, counts each member once, and feeds every note to AI',async()=>{
 let input;
 const s=setup(async value=>{input=value;return stages;}), original=s.agenda.materials.a;
 await Promise.all([s.call('material',newMaterial(firstID,'First extra')),s.call('material',newMaterial(secondID,'Second extra'))]);
 assert.equal(Object.keys(s.agenda.materials).length,4);
 assert.deepEqual(s.agenda.materials.a,original);
 assert.deepEqual(s.agenda.preparedUIDs,['a','b']);
 await s.trigger();
 assert.deepEqual(Array.from(input.members[0].materials,m=>m.note).sort(),['First extra','Opening','Second extra']);
 assert.deepEqual(Array.from(input.members[1].materials,m=>m.note),['Order']);
});
test('duplicate add retries are idempotent and cannot overwrite an existing entry',async()=>{
 const s=setup(async()=>stages), request=newMaterial(firstID,'Additional note');
 await s.call('material',request);
 const revision=s.agenda.inputRevision;
 await s.call('material',request);
 assert.equal(s.agenda.inputRevision,revision);
 assert.equal(Object.keys(s.agenda.materials).length,3);
 await assert.rejects(s.call('material',{...request,note:'Overwrite'}),e=>e.code==='aborted');
 assert.equal(s.agenda.materials[firstID].note,'Additional note');
});
test('editing targets one own entry; empty edits remove only that entry and readiness stays',async()=>{
 const s=setup(async()=>stages);
 await s.call('material',newMaterial(firstID,'First'));
 await s.call('material',newMaterial(secondID,'Second'));
 const original=s.agenda.materials.a, second=s.agenda.materials[secondID];
 const revision=s.agenda.materials[firstID].revision;
 await s.call('material',{...newMaterial(firstID,'Edited'),expectedRevision:revision});
 assert.equal(s.agenda.materials[firstID].note,'Edited');
 assert.deepEqual(s.agenda.materials.a,original);
 assert.deepEqual(s.agenda.materials[secondID],second);
 await assert.rejects(s.call('material',{...newMaterial(firstID,'Stale'),expectedRevision:revision}),e=>e.code==='aborted');
 await s.call('material',{...newMaterial(firstID,''),expectedRevision:s.agenda.materials[firstID].revision});
 assert.equal(s.agenda.materials[firstID],undefined);
 assert.deepEqual(s.agenda.preparedUIDs,['a','b']);
});
test('other members cannot edit or delete a record even with its ID and revision',async()=>{
 const s=setup(async()=>stages);
 await s.call('material',newMaterial(firstID,'Private ownership'));
 for(const note of ['Changed','']) {
  await assert.rejects(s.call('material',{...newMaterial(firstID,note),expectedRevision:s.agenda.materials[firstID].revision},'b'),e=>e.code==='permission-denied');
 }
 assert.equal(s.agenda.materials[firstID].note,'Private ownership');
});
test('blank new entries are rejected without changing existing data',async()=>{
 const s=setup(async()=>stages), before=s.agenda;
 await assert.rejects(s.call('material',newMaterial(firstID,'  ')),e=>e.code==='invalid-argument');
 assert.equal(s.agenda,before);
});

test('saving unchanged preparation keeps the published plan, timer and revision without another AI call',async()=>{
 const s=setup(async()=>stages); await s.trigger();
 const started={toMillis:()=>1000}; s.agenda={...s.agenda,meetingStartedAt:started};
 const before=s.agenda;
 await s.call('material',{note:'  Opening  ',attachment:null,expectedRevision:'a1'});
 assert.equal(s.agenda.inputRevision,before.inputRevision);
 assert.equal(s.agenda.meetingStartedAt,started);
 assert.deepEqual(s.agenda.stages,stages);
 await s.trigger();assert.equal(s.calls,1);
});
test('saving the same meeting leaves a ready plan intact',async()=>{
 const s=setup(async()=>stages);s.agenda={...s.agenda,meetingAt:{toMillis:()=>123456000}};
 await s.trigger(); const before=s.agenda;
 await s.call('meeting',{topic:'Demo',meetingAtMillis:123456000,duration:20,expectedRevision:'m1'});
 assert.equal(s.agenda.inputRevision,before.inputRevision);
 assert.equal(s.agenda.meetingRevision,'m1');
 assert.deepEqual(s.agenda.stages,stages);
});
test('an unchanged save still reconciles a membership change',async()=>{
 const s=setup(async()=>stages);await s.call('material',newMaterial(firstID,'Extra'));
 s.members.push({id:'c',role:'member'});
 await s.call('material',newMaterial(firstID,'Extra'));
 assert.equal(s.agenda.memberUIDs.length,3);
 assert.equal(s.agenda.preparedUIDs.length,2);
});

test('an expired generation can be retried and the previous response cannot replace the new plan',async()=>{
 let finish,started,count=0;const began=new Promise(r=>{started=r;});
 const s=setup(async()=>{if(++count===1){started();return new Promise(r=>{finish=r;});}return stages;});
 const first=s.trigger();await began;
 s.agenda={...s.agenda,generation:{...s.agenda.generation,expiresAt:{toMillis:()=>0}},lastGenerationAt:{toMillis:()=>0}};
 await s.call('retry');await s.trigger();
 finish([{start:0,end:20,title:'Stale response',goal:'Must not be published'}]);await first;
 assert.equal(s.calls,2);assert.equal(s.agenda.planState,'ready');assert.deepEqual(s.agenda.stages,stages);
});

test('retrying a committed edit after a lost response keeps the same plan and revision',async()=>{
 const s=setup(async()=>stages);
 const request={note:'New opening',attachment:null,expectedRevision:'a1'};
 await s.call('material',request);
 await s.trigger();
 const before=s.agenda;
 await s.call('material',request);
 assert.equal(s.agenda,before);
 await assert.rejects(s.call('material',{...request,note:'Stale different change'}),e=>e.code==='aborted');
 assert.equal(s.agenda,before);
});

test('retrying a committed meeting save is safe but stale different settings are rejected',async()=>{
 const s=setup(async()=>stages);
 const request={topic:'Revised meeting',meetingAtMillis:123456000,duration:30,expectedRevision:'m1'};
 await s.call('meeting',request);
 const before=s.agenda;
 await s.call('meeting',request);
 assert.equal(s.agenda,before);
 await assert.rejects(s.call('meeting',{...request,duration:40}),e=>e.code==='aborted');
 assert.equal(s.agenda,before);
});

test('retrying a committed deletion succeeds without removing a recreated entry',async()=>{
 const s=setup(async()=>stages);
 await s.call('material',newMaterial(firstID,'Extra'));
 const request={...newMaterial(firstID,''),expectedRevision:s.agenda.materials[firstID].revision};
 await s.call('material',request);
 const before=s.agenda;
 await s.call('material',request);
 assert.equal(s.agenda,before);
 await s.call('material',newMaterial(firstID,'Recreated'));
 await assert.rejects(s.call('material',request),e=>e.code==='aborted');
 assert.equal(s.agenda.materials[firstID].note,'Recreated');
});

const linkID='dddddddd-1111-4111-8111-111111111111';
const newLink=(overrides={})=>({linkID,title:'Meeting room',url:'https://meet.google.com/test-room',expectedRevision:null,...overrides});
test('meeting links preserve preparation and a ready AI plan; duplicate saves remain idempotent',async()=>{
 const s=setup(async()=>stages); await s.trigger();
 const before=s.agenda;
 await s.call('link',newLink(), 'b');
 const saved=s.agenda;
 assert.equal(saved.links[linkID].ownerUID,'b');
 for(const key of ['materials','preparedUIDs','inputRevision','stages','planState','generationRequest','meetingStartedAt']) {
  assert.deepEqual(saved[key],before[key],key);
 }
 await s.call('link',newLink(),'b'); assert.equal(s.agenda,saved);
 await s.trigger(); assert.equal(s.calls,1);
 await assert.rejects(s.call('link',newLink({title:'stale'}),'b'),e=>e.code==='aborted');
});
test('link permissions, unsafe URLs and group-size limits are enforced server-side',async()=>{
 const s=setup(async()=>stages);
 await assert.rejects(s.call('link',newLink(),'outside'),e=>e.code==='permission-denied');
 for(const url of ['javascript:alert(1)','file:///etc/passwd','data:text/html,test','https://user:password@example.com','https://exa mple.com','example.com']) {
  await assert.rejects(s.call('link',newLink({url})),e=>e.code==='invalid-argument');
 }
 await s.call('link',newLink());
 const revision=s.agenda.links[linkID].revision;
 await assert.rejects(s.call('link',newLink({title:'Other person',expectedRevision:revision}),'b'),e=>e.code==='permission-denied');
 const links={...s.agenda.links};
 for(let i=0;i<19;i++) links[`existing-${i}`]={...links[linkID]};
 s.agenda={...s.agenda,links};
 await assert.rejects(s.call('link',newLink({linkID:'eeeeeeee-1111-4111-8111-111111111111'})),e=>e.code==='resource-exhausted');
 await s.call('link',newLink({title:'Updated',expectedRevision:revision}));
 assert.equal(s.agenda.links[linkID].title,'Updated');
});
test('leaders can manage shared links; retried deletes cannot remove a recreated link',async()=>{
 const s=setup(async()=>stages); await s.call('link',newLink(),'b');
 await s.call('link',newLink({title:'Approved room',expectedRevision:s.agenda.links[linkID].revision}));
 assert.equal(s.agenda.links[linkID].ownerUID,'b');
 const request=newLink({title:'',url:'',expectedRevision:s.agenda.links[linkID].revision});
 await s.call('link',request,'b');const removed=s.agenda;
 await s.call('link',request,'b');assert.equal(s.agenda,removed);
 await s.call('link',newLink(),'b');
 await assert.rejects(s.call('link',request,'b'),e=>e.code==='aborted');
 assert(s.agenda.links[linkID]);
});
