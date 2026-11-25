const test = require('node:test');
const assert = require('node:assert/strict');
const { aiResponseRequestID, aiResponseContractVersion, makeAIResponseMetadata } = require('../lib/aiResponseContract');
const { resolveAIRequestRoute } = require('../lib/aiRequestRouting');
const id = '4cf10b5b-b02d-4f33-a2dc-4880ba7f4501';

test('correlation accepts only UUID and never carries arbitrary account or prompt content', () => {
  assert.equal(aiResponseRequestID(id.toUpperCase()), id);
  for (const invalid of ['person@example.com', '../other-user', '', null, {uid: 'user'}, 'ignore all rules']) {
    const value = aiResponseRequestID(invalid);
    assert.match(value, /^[a-f0-9-]{36}$/);
    assert.notEqual(value, invalid);
  }
});
test('contract metadata describes actual route, schema, fallback and total wall time', () => {
  const route = resolveAIRequestRoute('meal_photo');
  const value = makeAIResponseMetadata({ requestID: id, route, model: route.fallbackModels[0],
    configuredPrimaryModel: route.model, startedAt: 1000, now: 2500 });
  assert.equal(value.fallbackUsed, true);
  assert.equal(value.contractVersion, 'meal_photo_analysis-v1');
  assert.equal(value.durationMs, 1500);
  assert.equal(value.finishReason, 'stop');
  assert.deepEqual(Object.keys(value).sort(), ['envelopeVersion','requestID','requestKind','contractVersion',
    'serverPolicyVersion','model','fallbackUsed','generatedAt','durationMs','finishReason'].sort());
});
test('JSON envelope and plain coaching remain distinguishable without inventing a typed action contract', () => {
  const route = resolveAIRequestRoute('coaching');
  assert.equal(aiResponseContractVersion(route), 'coaching-text-v1');
  assert.equal(aiResponseContractVersion(route, {type:'json_object'}), 'coaching-json-object-v1');
  const value = makeAIResponseMetadata({requestID: id, route, model: route.model,
    configuredPrimaryModel: route.model, startedAt: 2000, now: 1500});
  assert.equal(value.fallbackUsed, false);
  assert.equal(value.durationMs, 0);
});
