const test = require('node:test');
const assert = require('node:assert/strict');
const {evaluateAIResponse, summarizeAIEvaluations, aiEvaluationReleaseGate} = require('../lib/aiEvaluation');
function example(overrides={}) {
  return {id:'nutrition-001',split:'holdout',language:'en',route:'coaching',promptVersion:'test-v1',model:'recorded-candidate',
    content:JSON.stringify({remaining:600,sourceIDs:['day-1'],action:'review_meal'}),finishReason:'stop',durationMs:1000,
    criteria:{jsonObject:true,requiredPaths:['action'],facts:[{path:'remaining',value:600},{path:'action',value:'review_meal'}],
      arrays:[{path:'sourceIDs',allowedValues:['day-1'],minItems:1,maxItems:1}]},...overrides};
}
test('valid syntax cannot hide wrong arithmetic or fabricated evidence',()=>{
  const wrong=evaluateAIResponse(example({content:JSON.stringify({remaining:1600,sourceIDs:['invented'],action:'review_meal'})}));
  assert.equal(wrong.contractPassed,true);assert.equal(wrong.semanticPassed,false);
  assert.ok(wrong.failures.includes('wrong_fact:remaining'));assert.ok(wrong.failures.includes('unsupported_values:sourceIDs'));
});
test('truncation, malformed JSON and inherited paths do not pass contracts',()=>{
  assert.equal(evaluateAIResponse(example({finishReason:'length'})).contractPassed,false);
  assert.equal(evaluateAIResponse(example({content:'```json\n{}\n```'})).contractPassed,false);
  assert.equal(evaluateAIResponse(example({criteria:{requiredPaths:['__proto__.anything']}})).contractPassed,false);
});
test('multilingual values and missing observations remain exact instead of invented zero',()=>{
  const value=example({language:'ja',content:'{"name":"豆腐丼","remaining":null}',
    criteria:{facts:[{path:'name',value:'豆腐丼'},{path:'remaining',value:null}]}});
  assert.equal(evaluateAIResponse(value).semanticPassed,true);
  assert.equal(evaluateAIResponse({...value,content:'{"name":"豆腐丼","remaining":0}'}).semanticPassed,false);
});
test('latency quantiles exclude absent values and unreviewed output is not human-approved',()=>{
  const cases=[100,200,300,400,undefined].map((durationMs,i)=>example({id:String(i),durationMs}));
  const result=summarizeAIEvaluations(cases);
  assert.equal(result.p50LatencyMs,200);assert.equal(result.p95LatencyMs,400);
  assert.equal(result.humanQualityPassRate,null);assert.equal(result.measuredLatencyCases,4);
  assert.equal(aiEvaluationReleaseGate(cases,500).eligible,false);
});
test('release gate rejects mixed candidates and no semantic or human coverage even if parse is perfect',()=>{
  const cases=Array.from({length:200},(_,i)=>example({id:String(i),model:i%2?'one':'two',criteria:{jsonObject:true}}));
  const gate=aiEvaluationReleaseGate(cases,2000);
  assert.equal(gate.eligible,false);
  assert.ok(gate.blockers.includes('semantic_quality_not_established'));
  assert.ok(gate.blockers.includes('human_quality_not_established'));
  assert.ok(gate.blockers.includes('mixed_candidate_versions'));
  assert.throws(()=>summarizeAIEvaluations([example(),example()]));
});

test('checked-in smoke corpus is explicitly synthetic and cannot be promoted as model quality evidence',()=>{
  const fs=require('node:fs');const path=require('node:path');
  const cases=fs.readFileSync(path.join(__dirname,'fixtures/ai-evaluation-smoke.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  const report=aiEvaluationReleaseGate(cases,30000);
  assert.equal(report.eligible,false);
  assert.equal(report.summary.cases,5);
  assert.equal(report.summary.measuredLatencyCases,0);
  assert.equal(report.summary.humanReviewedCases,0);
  assert.equal(report.summary.results.filter(r=>r.semanticPassed).length,3);
});
