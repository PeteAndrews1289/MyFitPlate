/** Reproducible evaluation of recorded synthetic responses. This never executes an AI
 * action and never equates contract validity with human coaching quality. */
export interface AIResponseEvaluationCase {
  id: string;
  split: "development" | "holdout";
  language: string;
  route: string;
  promptVersion: string;
  scenarioID?: string;
  caseType?: "typical" | "edge" | "adversarial";
  model: string;
  content: string;
  finishReason: string;
  durationMs?: number;
  fallbackUsed?: boolean;
  criteria: {
    jsonObject?: boolean;
    facts?: Array<{path: string; value: string | number | boolean | null; tolerance?: number}>;
    arrays?: Array<{path: string; allowedValues: Array<string | number>; minItems?: number; maxItems?: number}>;
    requiredPaths?: string[];
  };
  humanReview?: {accepted: boolean; reviewer: string; rubricVersion: string};
}
export interface AIEvaluationResult {
  id: string; contractPassed: boolean; semanticPassed: boolean;
  failures: string[]; humanAccepted: boolean | null;
}
function atPath(value: unknown, path: string): unknown {
  if (!path || path.split('.').some(part => ['__proto__','constructor','prototype'].includes(part))) return undefined;
  return path.split('.').reduce<unknown>((current, key) =>
    current && typeof current === 'object' && Object.prototype.hasOwnProperty.call(current, key)
      ? (current as Record<string, unknown>)[key] : undefined, value);
}
export function evaluateAIResponse(value: AIResponseEvaluationCase): AIEvaluationResult {
  const failures: string[] = [];
  let parsed: unknown;
  const needsJSON = value.criteria.jsonObject || (value.criteria.facts?.length ?? 0) > 0
    || (value.criteria.arrays?.length ?? 0) > 0 || (value.criteria.requiredPaths?.length ?? 0) > 0;
  if (value.finishReason !== 'stop' || !value.content.trim()) failures.push('incomplete_response');
  if (needsJSON) {
    try { parsed = JSON.parse(value.content); } catch { failures.push('invalid_json'); }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) failures.push('not_json_object');
  }
  for (const path of value.criteria.requiredPaths ?? []) {
    if (atPath(parsed, path) === undefined) failures.push(`missing:${path}`);
  }
  const contractPassed = failures.length === 0;
  for (const fact of value.criteria.facts ?? []) {
    const actual = atPath(parsed, fact.path);
    const matches = typeof fact.value === 'number'
      ? typeof actual === 'number' && Number.isFinite(actual) && Number.isFinite(fact.value)
        && Math.abs(actual - fact.value) <= Math.max(0, fact.tolerance ?? 0)
      : actual === fact.value;
    if (!matches) failures.push(`wrong_fact:${fact.path}`);
  }
  for (const criterion of value.criteria.arrays ?? []) {
    const actual = atPath(parsed, criterion.path);
    if (!Array.isArray(actual) || actual.some(item => !criterion.allowedValues.includes(item))
      || actual.length < (criterion.minItems ?? 0) || actual.length > (criterion.maxItems ?? Number.MAX_SAFE_INTEGER)) {
      failures.push(`unsupported_values:${criterion.path}`);
    }
  }
  const humanAccepted = value.humanReview?.reviewer.trim() && value.humanReview.rubricVersion.trim()
    ? value.humanReview.accepted : null;
  return {id: value.id, contractPassed, semanticPassed: failures.length === 0, failures, humanAccepted};
}
function quantile(values: number[], q: number): number | null {
  if (!values.length) return null;
  const sorted = [...values].sort((a,b) => a-b);
  return sorted[Math.max(0, Math.ceil(q * sorted.length) - 1)];
}
export function summarizeAIEvaluations(cases: AIResponseEvaluationCase[]) {
  if (new Set(cases.map(c => c.id)).size !== cases.length) throw new Error('Evaluation case IDs must be unique');
  const results = cases.map(evaluateAIResponse);
  const latencies = cases.flatMap(c => typeof c.durationMs === 'number' && Number.isFinite(c.durationMs) && c.durationMs >= 0 ? [c.durationMs] : []);
  const human = results.filter(r => r.humanAccepted !== null);
  const factCases = cases.filter(c => (c.criteria.facts?.length ?? 0) + (c.criteria.arrays?.length ?? 0) > 0);
  return {
    version: 1, cases: cases.length, holdoutCases: cases.filter(c => c.split === 'holdout').length,
    contractPassRate: cases.length ? results.filter(r => r.contractPassed).length / cases.length : null,
    semanticFixturePassRate: factCases.length ? results.filter((r,i) => factCases.includes(cases[i]) && r.semanticPassed).length / factCases.length : null,
    semanticCoverage: factCases.length, humanReviewedCases: human.length,
    humanQualityPassRate: human.length ? human.filter(r => r.humanAccepted).length / human.length : null,
    measuredLatencyCases: latencies.length, p50LatencyMs: quantile(latencies, .5), p95LatencyMs: quantile(latencies, .95),
    modelVersions: [...new Set(cases.map(c => c.model))], promptVersions: [...new Set(cases.map(c => c.promptVersion))],
    languages: [...new Set(cases.map(c => c.language))],
    distinctScenarios: new Set(cases.map(c => c.scenarioID).filter(Boolean)).size,
    caseTypes: Object.fromEntries(["typical", "edge", "adversarial"].map(type => [type, cases.filter(c => c.caseType === type).length])), results,
  };
}
export function aiEvaluationReleaseGate(cases: AIResponseEvaluationCase[], p95BudgetMs: number) {
  const summary = summarizeAIEvaluations(cases);
  const blockers: string[] = [];
  if (summary.cases < 200 || summary.holdoutCases < 40) blockers.push('insufficient_representative_cases');
  if (summary.distinctScenarios < 40 || summary.languages.length < 3
    || Object.values(summary.caseTypes).some(count => count < 10)) blockers.push('insufficient_scenario_coverage');
  if (summary.contractPassRate !== 1) blockers.push('contract_failures');
  if (summary.semanticCoverage < 200 || (summary.semanticFixturePassRate ?? 0) < .98) blockers.push('semantic_quality_not_established');
  if (summary.humanReviewedCases < 20 || (summary.humanQualityPassRate ?? 0) < .9) blockers.push('human_quality_not_established');
  if (summary.measuredLatencyCases < 200 || summary.p95LatencyMs === null || !Number.isFinite(p95BudgetMs)
    || p95BudgetMs <= 0 || summary.p95LatencyMs > p95BudgetMs) blockers.push('latency_not_established');
  if (summary.modelVersions.length !== 1 || summary.promptVersions.length !== 1) blockers.push('mixed_candidate_versions');
  return {eligible: blockers.length === 0, blockers, summary};
}
