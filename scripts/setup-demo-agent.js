// Demo only: sets up and publishes the Agentforce demo agent, Support Search Agent.
// Usage: node scripts/setup-demo-agent.js [--target-org <alias>]
// Needs an org created from config/project-scratch-def.json (Agentforce enabled) with the
// project deployed. Safe to run more than once; each run publishes a new agent version.
const { execSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const args = process.argv.slice(2);
const orgIndex = args.indexOf("--target-org");
const orgFlag = orgIndex >= 0 ? ` --target-org ${args[orgIndex + 1]}` : "";

const AGENT = "Support_Search_Agent";
const PLACEHOLDER = "SET_BY_SETUP_SCRIPT";
const bundleDir = path.join(
  __dirname,
  "..",
  "demo",
  "main",
  "default",
  "aiAuthoringBundles",
  AGENT
);

function sf(command, cwd) {
  const output = execSync(`sf ${command}${orgFlag} --json`, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 20 * 1024 * 1024
  });
  return JSON.parse(output).result;
}

function fail(error) {
  const result = JSON.parse(error.stdout || "{}");
  console.error(
    result.result?.exceptionMessage ||
      result.result?.compileProblem ||
      result.message ||
      error.message
  );
  process.exit(1);
}

// 1. Agent user and its permission sets (Apex, see setup-demo-agent.apex).
let apex;
try {
  apex = sf(
    `apex run --file "${path.join(__dirname, "setup-demo-agent.apex")}"`
  );
} catch (error) {
  fail(error);
}
const lines = apex.logs
  .split("\n")
  .filter((line) => line.includes("|USER_DEBUG|") && line.includes("SETUP"))
  .map((line) => line.split("|DEBUG|")[1] ?? "");
for (const message of lines) {
  if (!message.startsWith("SETUP_AGENT_USER")) {
    console.log(message.replace(/^SETUP /, ""));
  }
}
const username = lines
  .find((message) => message.startsWith("SETUP_AGENT_USER "))
  .split(" ")[1]
  .trim();

// 2. Publish with this org's agent user. The username is org-specific, so the committed
//    bundle keeps a placeholder and is never edited: a copy with the username goes into a
//    temporary project, and the agent is published from there. (sf agent publish also only
//    looks in the default package directory, which isn't demo/.)
//    --skip-retrieve: the org-generated agent metadata isn't written anywhere.
const original = fs.readFileSync(
  path.join(bundleDir, `${AGENT}.agent`),
  "utf8"
);
if (!original.includes(PLACEHOLDER)) {
  console.error(`The committed ${AGENT}.agent should contain ${PLACEHOLDER}.`);
  process.exit(1);
}
const tempProject = fs.mkdtempSync(path.join(os.tmpdir(), "sskit-agent-"));
try {
  const tempBundle = path.join(
    tempProject,
    "force-app",
    "main",
    "default",
    "aiAuthoringBundles",
    AGENT
  );
  fs.mkdirSync(tempBundle, { recursive: true });
  fs.copyFileSync(
    path.join(bundleDir, `${AGENT}.bundle-meta.xml`),
    path.join(tempBundle, `${AGENT}.bundle-meta.xml`)
  );
  fs.writeFileSync(
    path.join(tempBundle, `${AGENT}.agent`),
    original.replace(PLACEHOLDER, username)
  );
  const project = JSON.parse(
    fs.readFileSync(path.join(__dirname, "..", "sfdx-project.json"), "utf8")
  );
  fs.writeFileSync(
    path.join(tempProject, "sfdx-project.json"),
    JSON.stringify({
      packageDirectories: [{ path: "force-app", default: true }],
      sourceApiVersion: project.sourceApiVersion
    })
  );
  sf(
    `agent publish authoring-bundle --api-name ${AGENT} --skip-retrieve`,
    tempProject
  );
  console.log(`agent: ${AGENT} published, running as ${username}`);
} catch (error) {
  fail(error);
} finally {
  // On Windows the CLI can still hold a file in the temporary project for a moment, so retry,
  // and never let a leftover temp folder stop the activation below.
  try {
    fs.rmSync(tempProject, {
      recursive: true,
      force: true,
      maxRetries: 10,
      retryDelay: 500
    });
  } catch (error) {
    console.warn(
      `note: could not remove the temporary project ${tempProject} (${error.code}); delete it later`
    );
  }
}

// 3. Activate the published version.
try {
  sf(`agent activate --api-name ${AGENT}`);
  console.log(`agent: ${AGENT} activated`);
} catch (error) {
  fail(error);
}

console.log(
  `\nDone. Try it: sf agent preview --api-name ${AGENT} --use-live-actions${orgFlag}`
);
