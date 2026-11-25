// Input is a consented/synthetic recorded JSONL response set; no provider call, action,
// deployment or model selection is performed by this command.
const fs = require('node:fs');
const { aiEvaluationReleaseGate, summarizeAIEvaluations } = require('../lib/aiEvaluation');
function argument(name) { const i = process.argv.indexOf(name); return i < 0 ? undefined : process.argv[i + 1]; }
try {
  const input = argument('--input');
  const output = argument('--output');
  const budget = Number(argument('--p95-budget-ms'));
  if (!input || !output || !Number.isFinite(budget) || budget <= 0) throw new Error('Pass --input cases.jsonl --output report.json --p95-budget-ms <measured-route-budget>');
  const cases = fs.readFileSync(input, 'utf8').split(/\r?\n/).filter(l => l.trim()).map(l => JSON.parse(l));
  const gate = aiEvaluationReleaseGate(cases, budget);
  const slices = {};
  for (const field of ['route','language','split']) {
    slices[field] = Object.fromEntries([...new Set(cases.map(c => c[field]))].map(key => [key, summarizeAIEvaluations(cases.filter(c => c[field] === key))]));
  }
  // Report contains scores and opaque case IDs, not prompts, account identifiers or raw output.
  fs.writeFileSync(output, JSON.stringify({...gate, slices}, null, 2) + '\n', {mode: 0o600});
  console.log(JSON.stringify({cases: cases.length, eligible: gate.eligible, blockers: gate.blockers, output}));
  if (!gate.eligible) process.exitCode = 2;
} catch (error) { console.error('Evaluation failed: ' + error.message); process.exitCode = 1; }
