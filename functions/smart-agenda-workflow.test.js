const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const core=require('./smart-agenda-core');
const {randomUUID}=require('node:crypto');
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
  if(name==='firebase-admin/firestore')return {getFirestore:()=>db,FieldValue:{serverTimestamp:()=>({toMillis:()=>Date.now()})},Timestamp:{fromMillis:value=>({toMillis:()=>value})}};
  if(name==='firebase-admin/storage')return {getStorage(){throw Error('Unexpected Storage call');}};
  if(name==='firebase-functions/v2/https')return {onCall:(_,fn)=>fn,HttpsError};
  if(name==='firebase-functions/v2/firestore')return {onDocumentWritten:(_,fn)=>fn};
  throw Error(name);
 }};
 vm.runInNewContext(fs.readFileSync(__dirname+'/smart-agenda.js','utf8'),context);
 const call=(action,fields={},uid='a')=>context.exports.updateSmartAgenda({auth:{uid},data:{groupID:'11111111-1111-4111-8111-111111111111',action,...fields}});
 return {get agenda(){return agenda;},set agenda(value){agenda=value;},members,get calls(){return calls;},call,
  cloudEvent:()=>context.exports.generateSmartAgendaPlan({data:{after:snapshot()}}),
  // Model output is a test fixture; this exercises the same claim/publish boundary as the app.
  trigger:async()=>{
   const fields={inputRevision:agenda.inputRevision,token:randomUUID()};
   const claim=await call('claimPlan',fields);
   if(claim.status!=='claimed')return;
   calls++;
   try { const result=await generate(claim.input); await call('completePlan',{...fields,phases:phases(result)}); }
   catch(error) { try {await call('failPlan',fields);}catch{} throw error; }
  }};
}
const stages=[{start:0,end:5,title:'Opening',goal:'Approve hook'},{start:5,end:12,title:'Order',goal:'Choose features'},{start:12,end:20,title:'Owners',goal:'Assign edits'}];
const phases=result=>result.map(s=>({minutes:s.end-s.start,title:s.title,goal:s.goal,titleZhHant:'討論重點',goalZhHant:'確認具體決議'}));
const claimFields=s=>({inputRevision:s.agenda.inputRevision,token:randomUUID()});
test('one device claims generation; other devices cannot publish or cancel its work',async()=>{
 const s=setup(),fields=claimFields(s);
 assert.equal((await s.call('claimPlan',fields)).status,'claimed');
 assert.equal((await s.call('claimPlan',claimFields(s),'b')).status,'busy');
 await assert.rejects(s.call('completePlan',{...fields,phases:phases(stages)},'b'),e=>e.code==='failed-precondition');
 await assert.rejects(s.call('failPlan',fields,'b'),e=>e.code==='failed-precondition');
 await s.call('completePlan',{...fields,phases:phases(stages)});
 assert.equal(s.agenda.planSource,'appleIntelligence');
 assert.equal(s.agenda.planState,'ready');
 assert.equal((await s.call('claimPlan',claimFields(s),'b')).status,'ready');
 const published=s.agenda;
 await s.call('completePlan',{...fields,phases:phases(stages)});
 assert.equal(s.agenda,published);
});
test('preparation changes reject old device output even after a successful publication',async()=>{
 const s=setup(),fields=claimFields(s);await s.call('claimPlan',fields);
 await s.call('completePlan',{...fields,phases:phases(stages)});
 await s.call('material',{note:'New opening',attachment:null,expectedRevision:'a1'});
 await assert.rejects(s.call('completePlan',{...fields,phases:phases(stages)}),e=>e.code==='failed-precondition');
 assert.equal(s.agenda.planState,'waiting');assert.equal(s.agenda.stages.length,0);
});
test('changed or departed memberships cannot publish a stale plan',async()=>{
 const s=setup(),fields=claimFields(s);await s.call('claimPlan',fields);
 s.members.push({id:'c',role:'member'});
 await assert.rejects(s.call('completePlan',{...fields,phases:phases(stages)}),e=>e.code==='failed-precondition');
 s.members.splice(0,1);
 await assert.rejects(s.call('completePlan',{...fields,phases:phases(stages)}),e=>e.code==='permission-denied');
 assert.equal(s.agenda.stages.length,0);
});
test('unprepared teams and outsiders cannot claim; failed generation can be retried on another device',async()=>{
 const s=setup(),original=s.agenda;
 s.agenda={...original,preparedUIDs:['a']};
 await assert.rejects(s.call('claimPlan',claimFields(s)),e=>e.code==='failed-precondition');
 s.agenda=original;
 await assert.rejects(s.call('claimPlan',claimFields(s),'outside'),e=>e.code==='permission-denied');
 const fields=claimFields(s);await s.call('claimPlan',fields);await s.call('failPlan',fields);
 assert.equal(s.agenda.planState,'failed');assert.equal(s.agenda.generation,null);
 assert.equal((await s.call('claimPlan',claimFields(s),'b')).status,'claimed');
});
test('invalid phases or missing translations never publish; valid phases use the exact meeting duration',async()=>{
 const s=setup(),fields=claimFields(s);await s.call('claimPlan',fields);
 for(const invalid of [[],phases(stages).slice(0,2),[...phases(stages),...phases(stages)],
  phases(stages).map(p=>({...p,minutes:0})),phases(stages).map(p=>({...p,goalZhHant:''}))]) {
  await assert.rejects(s.call('completePlan',{...fields,phases:invalid}),e=>e.code==='invalid-argument');
  assert.equal(s.agenda.stages.length,0);
 }
 await s.call('completePlan',{...fields,phases:phases(stages).map(p=>({...p,minutes:9}))});
 assert.equal(s.agenda.stages.length,3);assert.equal(s.agenda.stages[0].start,0);
 assert.equal(s.agenda.stages.at(-1).end,20);
 assert(s.agenda.stages.every((p,i)=>p.end>p.start && (i===0 || p.start===s.agenda.stages[i-1].end)));
});
test('legacy cloud failures and ownerless leases do not block Apple Intelligence',async()=>{
 const s=setup();s.agenda={...s.agenda,planState:'failed',planError:'quota',generation:{token:'old',expiresAt:{toMillis:()=>Date.now()+180000}}};
 const fields=claimFields(s);assert.equal((await s.call('claimPlan',fields)).status,'claimed');
 assert.equal(s.agenda.planError,null);assert.equal(s.agenda.generation.ownerUID,'a');
 const lease=s.agenda.generation;
 await s.call('claimPlan',fields);assert.equal(s.agenda.generation,lease);
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
 assert.deepEqual(s.agenda.stages,core.timedStages(phases(stages),20));
 await s.trigger();assert.equal(s.calls,1);
});
test('only the leader starts a meeting; new preparation keeps the live plan until the leader ends it',async()=>{
 const s=setup(async()=>stages);await s.trigger();
 const revision=s.agenda.inputRevision;
 await assert.rejects(s.call('start',{inputRevision:revision},'b'),e=>e.code==='permission-denied');
 await s.call('start',{inputRevision:revision});
 const started=s.agenda.meetingStartedAt, published=s.agenda.stages;
 await s.call('material',{note:'Updated order',attachment:null,expectedRevision:'b1'},'b');
 assert.equal(s.agenda.meetingStartedAt,started);
 assert.equal(s.agenda.inputRevision,revision);
 assert.deepEqual(s.agenda.stages,published);
 assert.equal(s.agenda.materials.b.note,'Updated order');
 await assert.rejects(s.call('meeting',{topic:'New topic',meetingAtMillis:123456000,duration:20,expectedRevision:'m1'}),e=>e.code==='failed-precondition');
 await assert.rejects(s.call('end',{inputRevision:revision},'b'),e=>e.code==='permission-denied');
 await s.call('material',{note:'',attachment:null,expectedRevision:s.agenda.materials.b.revision},'b');
 assert.deepEqual(s.agenda.preparedUIDs,['a']);
 assert.deepEqual(s.agenda.stages,published);
 s.members.push({id:'c',role:'member'});
 await s.call('end',{inputRevision:revision});
 assert.equal(s.agenda.meetingStartedAt,null);
 assert.equal(s.agenda.stages.length,0);
 assert.equal(s.agenda.planState,'waiting');
});
test('saving the same meeting leaves a ready plan intact',async()=>{
 const s=setup(async()=>stages);s.agenda={...s.agenda,meetingAt:{toMillis:()=>123456000}};
 await s.trigger(); const before=s.agenda;
 await s.call('meeting',{topic:'Demo',meetingAtMillis:123456000,duration:20,expectedRevision:'m1'});
 assert.equal(s.agenda.inputRevision,before.inputRevision);
 assert.equal(s.agenda.meetingRevision,'m1');
 assert.deepEqual(s.agenda.stages,core.timedStages(phases(stages),20));
});
test('an unchanged save still reconciles a membership change',async()=>{
 const s=setup(async()=>stages);await s.call('material',newMaterial(firstID,'Extra'));
 s.members.push({id:'c',role:'member'});
 await s.call('material',newMaterial(firstID,'Extra'));
 assert.equal(s.agenda.memberUIDs.length,3);
 assert.equal(s.agenda.preparedUIDs.length,2);
});

test('expired leases can be reclaimed and cannot overwrite newer device results',async()=>{
 const s=setup(),old=claimFields(s);await s.call('claimPlan',old);
 s.agenda={...s.agenda,generation:{...s.agenda.generation,expiresAt:{toMillis:()=>0}}};
 await assert.rejects(s.call('completePlan',{...old,phases:phases(stages)}),e=>e.code==='failed-precondition');
 const current=claimFields(s);await s.call('claimPlan',current,'b');
 await s.call('completePlan',{...current,phases:phases(stages)},'b');
 await assert.rejects(s.call('completePlan',{...old,phases:phases(stages)}),e=>e.code==='failed-precondition');
 assert.equal(s.agenda.completedGeneration.ownerUID,'b');
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


test('the retained cloud trigger never calls a provider or changes agenda data',async()=>{
 const s=setup(()=>{throw Error('Cloud AI must not run');});
 const before=s.agenda;
 await s.cloudEvent();await s.cloudEvent();
 assert.equal(s.agenda,before);assert.equal(s.calls,0);
});
