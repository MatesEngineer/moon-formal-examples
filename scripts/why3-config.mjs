// Render a Why3 configuration for `moon prove`.
//
// `moon prove` writes a default configuration that registers whichever solver
// it happened to find and gives every goal five seconds. That is fine for the
// arithmetic in `saturating` and not enough for the quantified array
// invariants in `gap`, where Z3 and cvc5 have visibly different strengths —
// some goals only one of them closes.
//
// This script detects every supported solver on `PATH`, registers all of them,
// and builds a strategy that escalates: a fast pass to sweep up the easy goals,
// then `split_vc` to break the survivors apart, then a long pass with every
// solver in parallel.

import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const which = (bin) => {
  try {
    return execFileSync("sh", ["-c", `command -v ${bin}`], { encoding: "utf8" }).trim() || null;
  } catch {
    return null;
  }
};

const versionOf = (path, args, re) => {
  try {
    const out = execFileSync(path, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    return out.match(re)?.[1] ?? null;
  } catch {
    return null;
  }
};

/** Solvers Why3 knows how to drive, in the order we prefer them. */
const CANDIDATES = [
  { bin: "z3", name: "Z3", args: ["--version"], re: /Z3 version ([\d.]+)/ },
  { bin: "cvc5", name: "CVC5", args: ["--version"], re: /cvc5 ([\d.]+)/ },
  { bin: "alt-ergo", name: "Alt-Ergo", args: ["--version"], re: /([\d.]+)/ },
];

// Why3's data and library directories ship with the *toolchain*, not with the
// mutable registry, and under Nix those are two different places: the toolchain
// is a read-only store path, while `MOON_HOME` stays writable so that
// `moon add` keeps working. Deriving the root from wherever `moon` itself is
// covers both — `$out/bin/moon` in the store, `~/.moon/bin/moon` outside it —
// and needs no environment variable to have been exported.
//
// `MOON_HOME` was the obvious reading and the wrong one: it finds a directory
// with no `share/why3` in it, and `moon prove` then fails with
// `provers-detection-data.conf: No such file or directory`, naming a path
// nobody wrote down.
const toolchainRoot = () => {
  if (process.env.MOON_TOOLCHAIN_ROOT) return process.env.MOON_TOOLCHAIN_ROOT;
  const bin = which("moon");
  if (bin) return resolve(dirname(bin), "..");
  return process.env.MOON_HOME ?? resolve(process.env.HOME ?? "", ".moon");
};
const toolchain = toolchainRoot();
const out = process.argv[2] ?? "src/_build/verif/why3.conf";
const timeLimit = Number(process.env.PROVE_TIMELIMIT ?? 120);

const found = [];
for (const c of CANDIDATES) {
  const path = which(c.bin);
  if (!path) continue;
  const version = versionOf(path, c.args, c.re);
  if (!version) continue;
  found.push({ ...c, path, version });
}

if (found.length === 0) {
  console.error(
    "no SMT solver found on PATH. `nix develop` provides z3 and cvc5; " +
      "outside Nix, install at least one of z3, cvc5, alt-ergo.",
  );
  process.exit(1);
}

const provers = found
  .map(
    (p) => `[partial_prover]\nname = "${p.name}"\npath = "${p.path}"\nversion = "${p.version}"\n`,
  )
  .join("\n");

// Escalating strategy: cheap sweep, structural split, then a long parallel run.
const quick = found.map((p) => `c ${p.name},${p.version} 1 2000`).join("\n");
const deep = found.map((p) => `c ${p.name},${p.version} ${timeLimit} 16000`).join("\n");

const conf = `[main]
magic = 14
datadir = "${toolchain}/share/why3"
libdir = "${toolchain}/lib/why3"
memlimit = 16000
running_provers_max = 16
timelimit = ${timeLimit}.000000

${provers}
[strategy]
code = "start:
${quick}
t compute_specified start
t split_vc start
${deep}
"
desc = "escalating@ strategy"
name = "Escalating"
shortcut = "4"
`;

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, conf);
console.log(
  `why3 config -> ${out}  solvers: ${found.map((p) => `${p.name} ${p.version}`).join(", ")}  timelimit: ${timeLimit}s`,
);
