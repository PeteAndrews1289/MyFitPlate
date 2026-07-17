const { execFileSync } = require("node:child_process");

const { resolveAIRequestRoute } = require("../lib/aiRequestRouting.js");
const { MAIA_SPEECH_MODEL } = require("../lib/maiaSpeech.js");

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function loadAPIKey() {
  if (process.env.OPENAI_API_KEY) {
    return process.env.OPENAI_API_KEY.trim();
  }

  const project = argumentValue("--firebase-project");
  if (!project) {
    throw new Error(
      "Set OPENAI_API_KEY or pass --firebase-project <firebase-project-id>."
    );
  }

  return execFileSync(
    "npx",
    [
      "firebase-tools",
      "functions:secrets:access",
      "OPENAI_API_KEY",
      "--project",
      project,
    ],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
  ).trim();
}

function modelContract() {
  const visionKinds = [
    "meal_photo",
    "nutrition_label",
    "menu_photo",
    "receipt_photo",
    "recipe_photo",
  ];
  const routes = visionKinds.map(resolveAIRequestRoute);
  const required = new Map([
    [resolveAIRequestRoute("general").model, "General AI and vision compatibility fallback"],
    [MAIA_SPEECH_MODEL, "Maia Natural speech"],
  ]);
  const preferred = new Map();

  const appendPurpose = (map, model, purpose) => {
    const existing = map.get(model);
    map.set(model, existing ? `${existing}; ${purpose}` : purpose);
  };

  for (const route of routes) {
    appendPurpose(preferred, route.model, `${route.kind} preferred route`);
    for (const fallback of route.fallbackModels ?? []) {
      appendPurpose(required, fallback, `${route.kind} compatibility fallback`);
    }
  }

  return [
    ...Array.from(required, ([model, purpose]) => ({ model, purpose, tier: "required" })),
    ...Array.from(preferred, ([model, purpose]) => ({ model, purpose, tier: "preferred" })),
  ];
}

async function checkModel(apiKey, entry) {
  const response = await fetch(
    `https://api.openai.com/v1/models/${encodeURIComponent(entry.model)}`,
    { headers: { Authorization: `Bearer ${apiKey}` } }
  );
  return { ...entry, available: response.ok, status: response.status };
}

async function main() {
  const apiKey = loadAPIKey();
  const results = await Promise.all(modelContract().map((entry) => checkModel(apiKey, entry)));

  console.table(results.map((result) => ({
    model: result.model,
    tier: result.tier,
    available: result.available ? "yes" : "no",
    status: result.status,
    purpose: result.purpose,
  })));

  const missingRequired = results.filter(
    (result) => result.tier === "required" && !result.available
  );
  const missingPreferred = results.filter(
    (result) => result.tier === "preferred" && !result.available
  );

  if (missingPreferred.length > 0) {
    console.warn(
      `Preferred model access missing: ${missingPreferred.map((item) => item.model).join(", ")}. ` +
      "Vision requests will use the compatibility route."
    );
  }
  if (missingRequired.length > 0) {
    console.error(
      `Required model access missing: ${missingRequired.map((item) => item.model).join(", ")}.`
    );
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(`OpenAI model preflight failed: ${error.message}`);
  process.exitCode = 1;
});
