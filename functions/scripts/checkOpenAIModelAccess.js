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
  const kinds = ["general", "coaching", "planning", "meal_photo", "nutrition_label", "menu_photo", "receipt_photo", "recipe_photo", "pantry_observation"];
  const models = new Map([[MAIA_SPEECH_MODEL, "Maia Natural speech"]]);
  for (const kind of kinds) {
    const route = resolveAIRequestRoute(kind);
    for (const model of [route.model, ...(route.fallbackModels ?? [])]) {
      const purpose = `${kind} ${model === route.model ? "primary" : "fallback"}`;
      models.set(model, models.has(model) ? `${models.get(model)}; ${purpose}` : purpose);
    }
  }
  return Array.from(models, ([model, purpose]) => ({ model, purpose }));
}

async function checkModel(apiKey, entry) {
  const response = await fetch(
    `https://api.openai.com/v1/models/${encodeURIComponent(entry.model)}`,
    { headers: { Authorization: `Bearer ${apiKey}` } }
  );
  const data = response.ok ? await response.json() : {};
  return { ...entry, available: response.ok, status: response.status, shutdownDate: data.shutdown_date ?? null };
}

async function main() {
  const apiKey = loadAPIKey();
  const results = await Promise.all(modelContract().map((entry) => checkModel(apiKey, entry)));

  console.table(results.map((result) => ({
    model: result.model,
    available: result.available ? "yes" : "no",
    status: result.status,
    shutdown: result.shutdownDate ?? "none announced",
    purpose: result.purpose,
  })));

  const unavailable = results.filter(result => !result.available || result.shutdownDate);
  if (unavailable.length) {
    console.error(`Model access or retirement requires attention: ${unavailable.map(item => item.model).join(", ")}.`);
    process.exitCode = 1;
  }

}

main().catch((error) => {
  console.error(`OpenAI model preflight failed: ${error.message}`);
  process.exitCode = 1;
});
