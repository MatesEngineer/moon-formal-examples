// Re-pin the rolling MoonBit artifacts in `nix/toolchain.lock.json`.
//
// MoonBit publishes its toolchain only under `latest` — there are no immutable
// per-version download paths — so the lock pins the *content*. When upstream
// rolls, every hash in it stops matching at once and `nix develop` fails with a
// hash mismatch rather than silently changing compiler. This is the other half
// of that bargain: the command that moves the pin deliberately.
//
//   nix run .#update-toolchain          re-pin, and say what moved
//   nix run .#update-toolchain -- --dry-run   say what would move
//
// The version fields are informational, and refreshed anyway — by unpacking
// the host platform's tarball and asking it — so that a stale pin is legible
// at a glance rather than only as a hash.
//
// It runs on Node rather than on MoonBit, and that is a cycle rather than a
// preference: a MoonBit script is run by `moon`, `moon` comes from the
// toolchain, and the toolchain comes from the derivation whose hashes this
// script exists to repair. When the pin is stale — the only time anyone runs
// this — there is no `moon` to start it with. It uses nothing but `nix` and
// `tar`.

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const LOCK = resolve("nix/toolchain.lock.json");
const dryRun = process.argv.includes("--dry-run");

/** The SRI hash Nix computes for a URL's contents, and where it stored them. */
const prefetch = (url) => {
  const out = execFileSync(
    "nix",
    ["store", "prefetch-file", "--json", "--hash-type", "sha256", url],
    { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
  );
  return JSON.parse(out);
};

/** This machine, as the lock names platforms. */
const hostSystem = () => {
  const arch = process.arch === "arm64" ? "aarch64" : "x86_64";
  return process.platform === "darwin" ? `${arch}-darwin` : `${arch}-linux`;
};

const lock = JSON.parse(readFileSync(LOCK, "utf8"));
const { moonbit } = lock;
const changes = [];

const note = (what, before, after) => {
  if (before !== after) changes.push(`  ${what}\n    ${before}\n -> ${after}`);
};

// -- the hashes ---------------------------------------------------------------

const core = prefetch(moonbit.coreUrl);
note("core-latest.zip", moonbit.coreHash, core.hash);
moonbit.coreHash = core.hash;

const fetched = {};
for (const [system, spec] of Object.entries(moonbit.platforms)) {
  const result = prefetch(`${moonbit.baseUrl}/${spec.asset}`);
  note(spec.asset, spec.hash, result.hash);
  spec.hash = result.hash;
  fetched[system] = result.storePath;
}

// -- the version fields -------------------------------------------------------

const host = hostSystem();
if (fetched[host]) {
  const dir = mkdtempSync(join(tmpdir(), "moonbit-toolchain-"));
  try {
    execFileSync("tar", ["-xzf", fetched[host], "-C", dir, "./bin/moon", "./bin/moonc"]);
    execFileSync("chmod", ["+x", join(dir, "bin/moon"), join(dir, "bin/moonc")]);
    const ask = (bin, args) =>
      execFileSync(join(dir, "bin", bin), args, { encoding: "utf8" }).trim();
    // `moon version` reports `moon 0.1.20260827 (d0aaa07 2026-08-27)`.
    const [, version, , date] = ask("moon", ["version"]).match(/moon (\S+) \((\S+) (\S+)\)/) ?? [];
    const moonc = ask("moonc", ["-v"]).split(/\s+/)[0];
    if (version) {
      note("version", moonbit.version, version);
      note("date", moonbit.date, date);
      moonbit.version = version;
      moonbit.date = date;
    }
    if (moonc) {
      note("moonc", moonbit.moonc, moonc);
      moonbit.moonc = moonc;
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
} else {
  console.warn(`no pinned artifact for ${host}; leaving the version fields alone.`);
}

// -- the verdict --------------------------------------------------------------

if (changes.length === 0) {
  console.log("toolchain.lock.json is already current.");
  process.exit(0);
}

console.log(`${changes.length} field(s) moved:\n${changes.join("\n")}`);
if (dryRun) {
  console.log("\n--dry-run: nothing written.");
  process.exit(0);
}

writeFileSync(LOCK, `${JSON.stringify(lock, null, 2)}\n`);
console.log(`\nwrote ${LOCK}. Run \`nix develop\` to build against it.`);
