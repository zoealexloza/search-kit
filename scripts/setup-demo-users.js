// Demo only: sets up guest access and a demo customer for the Support Portal site:
// role, guest permission sets, the customer user, site membership and guest API access.
// Also moves three known issues' reported dates into the last 30 days for the demo boost.
// Creates and publishes the demo Knowledge articles if they don't exist yet.
// Usage: node scripts/setup-demo-users.js [--target-org <alias>]
// Safe to run more than once. Needs the site, the deployed metadata and the sample data.
const { execSync } = require("child_process");
const path = require("path");

const args = process.argv.slice(2);
const orgIndex = args.indexOf("--target-org");
const orgFlag = orgIndex >= 0 ? ` --target-org ${args[orgIndex + 1]}` : "";

function sf(command) {
  const output = execSync(`sf ${command}${orgFlag} --json`, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 20 * 1024 * 1024
  });
  return JSON.parse(output).result;
}

/**
 * Runs an Apex script file, prints its "SETUP ..." debug lines and returns all of them.
 * Exits the process with the Apex error if the script fails.
 */
function runApex(fileName) {
  const apexFile = path.join(__dirname, fileName);
  let apex;
  try {
    apex = sf(`apex run --file "${apexFile}"`);
  } catch (error) {
    const result = JSON.parse(error.stdout || "{}").result || {};
    console.error(
      result.exceptionMessage || result.compileProblem || error.message
    );
    process.exit(1);
  }
  // Only debug output, not the source lines the log echoes.
  const setupLines = apex.logs
    .split("\n")
    .filter((line) => line.includes("|USER_DEBUG|") && line.includes("SETUP"));
  for (const line of setupLines) {
    const message = line.split("|DEBUG|")[1];
    if (message && !message.startsWith("SETUP_MEMBERSHIP")) {
      console.log(message.replace(/^SETUP /, ""));
    }
  }
  return setupLines;
}

// 1. Role, guest permission sets, customer user (Apex, see setup-demo-users.apex).
const lines = runApex("setup-demo-users.apex");

// 1b. Recent reported dates for the demo boost. A separate transaction: Apex can't mix
//     setup records (users) and regular records (issues) in one (MIXED_DML_OPERATION).
runApex("setup-demo-issues.apex");

// 1c. Demo Knowledge articles (English and Spanish, with categories and channels). Also its own
//     transaction, after 1 made the running user a Knowledge user.
runApex("setup-demo-knowledge.apex");

// 2. Site membership for the customer profile (API only; Apex can't insert it).
const membership = lines.find((line) => line.includes("SETUP_MEMBERSHIP "));
const [networkId, profileId, isMember] = membership
  .split("SETUP_MEMBERSHIP ")[1]
  .trim()
  .split(" ");
if (isMember === "true") {
  console.log("site membership: customer profile is already a member");
} else {
  sf(
    `data create record --sobject NetworkMemberGroup --values "NetworkId=${networkId} ParentId=${profileId}"`
  );
  console.log("site membership: customer profile added to the site");
}

// 3. Guest access to the UI API, so record pages load for guests ("Allow guest users to
//    access public APIs" in the site's Administration > Preferences; stored as
//    Network.OptionsGuestChatterEnabled for historical reasons).
sf(
  `data update record --sobject Network --record-id ${networkId} --values "OptionsGuestChatterEnabled=true"`
);
console.log("site preference: guest users can access public APIs");

console.log(
  "\nDone. Guest search results can take a few minutes to appear after the first run."
);
