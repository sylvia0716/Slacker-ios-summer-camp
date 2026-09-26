const {test}=require('node:test');
const assert=require('node:assert/strict');
const {generatePlan}=require('./smart-agenda-ai');
const phases=Array.from({length:4},(_,i)=>({title:`Discuss ${i}`,goal:`Decide ${i}`,titleZhHant:`討論 ${i}`,goalZhHant:`決定 ${i}`,minutes:7}));
const input={topic:'Demo',duration:20,members:[{member:1,note:'Opening',fileName:'Demo.pdf'}]};
test('Responses API uses strict schema, no stored response, and exact contiguous allocation',async()=>{
 const stages=await generatePlan(input,'test-key',async(url,options)=>{
  assert.equal(url,'https://api.openai.com/v1/responses');
  const body=JSON.parse(options.body);
  assert.equal(body.store,false);assert.equal(body.text.format.strict,true);
  assert.equal(body.text.format.schema.properties.phases.minItems,3);
  assert.equal(body.text.format.schema.properties.phases.maxItems,4);
  assert(body.text.format.schema.properties.phases.items.required.includes('titleZhHant'));
  assert(body.text.format.schema.properties.phases.items.required.includes('goalZhHant'));
  assert.deepEqual(JSON.parse(body.input),input);
  return {ok:true,json:async()=>({status:'completed',output:[{type:'reasoning'},{type:'message',content:[{type:'output_text',text:JSON.stringify({phases})}]}]})};
 });
 assert.deepEqual(stages.map(s=>[s.start,s.end]),[[0,5],[5,10],[10,15],[15,20]]);
 assert.equal(stages[0].title,'Discuss 0'); assert.equal(stages[0].titleZhHant,'討論 0');
 assert.equal(stages[0].goalZhHant,'決定 0');
});
test('missing or oversized translations never produce an English-only plan',async()=>{
 for (const invalid of [phases.map(({titleZhHant,goalZhHant,...p})=>p),
   phases.map(p=>({...p,titleZhHant:' '})),phases.map(p=>({...p,goalZhHant:'長'.repeat(301)}))]) {
  await assert.rejects(generatePlan(input,'test-key',async()=>({ok:true,json:async()=>({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({phases:invalid})}]}]})})),e=>e.code==='invalid-plan');
 }
});
test('exhausted credits are not treated as a transient rate limit',async()=>{
 for(const code of ['credit_balance_exhausted','insufficient_quota']) {
  await assert.rejects(generatePlan(input,'test-key',async()=>({ok:false,status:429,json:async()=>({error:{code,type:'insufficient_quota'}})})),e=>e.code==='quota');
 }
 await assert.rejects(generatePlan(input,'test-key',async()=>({ok:false,status:429,json:async()=>({error:{code:'rate_limit_exceeded'}})})),e=>e.code==='unavailable');
});
test('refusals, incomplete responses and malformed phases never produce a fake agenda',async()=>{
 for(const response of [{status:'incomplete'},{status:'completed',output:[{type:'message',content:[{type:'refusal'}]}]},
  {status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({phases:phases.slice(0,2)})}]}]}]) {
  await assert.rejects(generatePlan(input,'test-key',async()=>({ok:true,json:async()=>response})),e=>e.code==='invalid-plan');
 }
});
