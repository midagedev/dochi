import { readFileSync, readdirSync } from "fs";
import { join } from "path";

// ── Constants ───────────────────────────────────────────────────────────────
const SUPABASE_URL = "https://seeubusbkaevsokigkvq.supabase.co";
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_ROLE_KEY) {
  console.error("Error: SUPABASE_SERVICE_ROLE_KEY environment variable is required.");
  process.exit(1);
}
const WORKSPACE_ID = "253a985e-bbb7-43ba-915a-4ea34f13d6c4";
const OWNER_ID = "f7a45e83-02b8-4aba-90b6-8e4b67b76707";

const DATA_DIR = join(
  process.env.HOME,
  "Library/Application Support/Dochi"
);

// ── Helpers ─────────────────────────────────────────────────────────────────

async function supabaseInsert(table, rows) {
  const url = `${SUPABASE_URL}/rest/v1/${table}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify(rows),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(
      `[${table}] ${res.status} ${res.statusText}: ${body}`
    );
  }
  return res;
}

function readTextFile(name) {
  return readFileSync(join(DATA_DIR, name), "utf-8");
}

function readJsonFile(name) {
  return JSON.parse(readFileSync(join(DATA_DIR, name), "utf-8"));
}

// ── 1. Context files ────────────────────────────────────────────────────────

async function migrateContextFiles() {
  console.log("\n── Migrating context_files ──");

  const files = [
    { name: "system.md", file_type: "system" },
    { name: "memory.md", file_type: "memory" },
    { name: "family.md", file_type: "family_memory" },
  ];

  const rows = files.map(({ name, file_type }) => {
    const content = readTextFile(name);
    console.log(`  Read ${name} (${content.length} chars)`);
    return {
      workspace_id: WORKSPACE_ID,
      file_type,
      content,
      user_id: null,
      version: 1,
      updated_by: OWNER_ID,
    };
  });

  await supabaseInsert("context_files", rows);
  console.log(`  Inserted ${rows.length} context files`);
}

// ── 2. Profiles ─────────────────────────────────────────────────────────────

async function migrateProfiles() {
  console.log("\n── Migrating profiles ──");

  const profiles = readJsonFile("profiles.json");
  console.log(`  Read ${profiles.length} profiles from profiles.json`);

  const rows = profiles.map((p) => ({
    id: p.id,
    workspace_id: WORKSPACE_ID,
    name: p.name,
    aliases: [],
    description: p.description,
  }));

  await supabaseInsert("profiles", rows);
  console.log(`  Inserted ${rows.length} profiles`);
}

// ── 3. Conversations ────────────────────────────────────────────────────────

async function migrateConversations() {
  console.log("\n── Migrating conversations ──");

  const convDir = join(DATA_DIR, "conversations");
  const files = readdirSync(convDir).filter((f) => f.endsWith(".json"));
  console.log(`  Found ${files.length} conversation files`);

  const rows = files.map((file) => {
    const raw = JSON.parse(readFileSync(join(convDir, file), "utf-8"));
    return {
      id: raw.id,
      workspace_id: WORKSPACE_ID,
      device_id: null,
      title: raw.title,
      messages: raw.messages,
      user_id: null,
      created_at: raw.createdAt,
      updated_at: raw.updatedAt,
    };
  });

  await supabaseInsert("conversations", rows);
  console.log(`  Inserted ${rows.length} conversations`);
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log("Starting Dochi local → cloud migration");
  console.log(`  Data dir: ${DATA_DIR}`);
  console.log(`  Supabase: ${SUPABASE_URL}`);
  console.log(`  Workspace: ${WORKSPACE_ID}`);

  try {
    await migrateContextFiles();
    await migrateProfiles();
    await migrateConversations();
    console.log("\nMigration completed successfully!");
  } catch (err) {
    console.error("\nMigration failed:", err.message);
    process.exit(1);
  }
}

main();
