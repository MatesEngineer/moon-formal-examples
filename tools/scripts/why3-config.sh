#!/usr/bin/env sh
# Render a Why3 configuration for `moon prove`.
#
# `moon prove` writes a default configuration that registers whichever solver
# it happened to find and gives every goal five seconds. That is fine for the
# arithmetic in `saturating` and not enough for the quantified array
# invariants in `gap`, where Z3 and cvc5 have visibly different strengths and
# some goals are closed by only one of them.
#
# So this registers every supported solver on PATH and builds a strategy that
# escalates: a fast pass over each solver in turn to sweep up the easy goals,
# then `compute_specified` and `split_vc` to break the survivors apart, then a
# second pass over each solver with a long time limit.
#
# Note that this is sequential, not parallel. In Why3's strategy language a
# `c <prover> <time> <mem>` line stops the strategy when that prover succeeds
# and falls through to the next line when it does not, so consecutive `c`
# lines are alternatives tried in order. `running_provers_max` bounds how many
# prover processes Why3 may run at once across goals; it does not turn these
# lines into a parallel race on one goal. The time limit below is therefore
# per prover call, not per goal.
#
# Usage: ./scripts/why3-config.sh <output path>
set -eu

OUT=${1:?usage: why3-config.sh <output path>}
TIMELIMIT=${PROVE_TIMELIMIT:-120}

# Why3's data and library directories ship with the *toolchain*, not with the
# mutable registry, and under Nix those are two different places: the
# toolchain is a read-only store path, while MOON_HOME stays writable so that
# `moon add` keeps working. Deriving the root from wherever `moon` itself is
# covers both, and needs no environment variable to have been exported.
#
# MOON_HOME was the obvious reading and the wrong one: it finds a directory
# with no `share/why3` in it, and `moon prove` then fails with
# `provers-detection-data.conf: No such file or directory`, naming a path
# nobody wrote down.
if [ -n "${MOON_TOOLCHAIN_ROOT:-}" ]; then
  TOOLCHAIN=$MOON_TOOLCHAIN_ROOT
elif moonbin=$(command -v moon 2>/dev/null); then
  TOOLCHAIN=$(CDPATH= cd -- "$(dirname -- "$moonbin")/.." && pwd)
else
  TOOLCHAIN=${MOON_HOME:-$HOME/.moon}
fi

# Solvers Why3 knows how to drive, in the order we prefer them. Each line is
# `binary name version-extractor`, where the extractor is a sed script run
# over the binary's own `--version` output.
solver_version() {
  case $1 in
  z3) z3 --version 2>/dev/null | sed -n 's/.*Z3 version \([0-9][0-9.]*\).*/\1/p' | head -n1 ;;
  cvc5) cvc5 --version 2>/dev/null | sed -n 's/^cvc5 \([0-9][0-9.]*\).*/\1/p' | head -n1 ;;
  alt-ergo) alt-ergo --version 2>/dev/null | sed -n 's/.*\([0-9][0-9.]*\).*/\1/p' | head -n1 ;;
  esac
}

solver_label() {
  case $1 in
  z3) echo Z3 ;;
  cvc5) echo CVC5 ;;
  alt-ergo) echo Alt-Ergo ;;
  esac
}

provers=
quick=
deep=
found=
for bin in z3 cvc5 alt-ergo; do
  command -v "$bin" >/dev/null 2>&1 || continue
  version=$(solver_version "$bin")
  [ -n "$version" ] || continue
  name=$(solver_label "$bin")
  path=$(command -v "$bin")
  provers="${provers}[partial_prover]
name = \"$name\"
path = \"$path\"
version = \"$version\"

"
  quick="${quick}c $name,$version 1 2000
"
  deep="${deep}c $name,$version $TIMELIMIT 16000
"
  found="${found}${found:+, }$name $version"
done

if [ -z "$found" ]; then
  echo "no SMT solver found on PATH. \`nix develop\` provides z3 and cvc5;" >&2
  echo "outside Nix, install at least one of z3, cvc5, alt-ergo. Why3 itself" >&2
  echo "is not needed separately: the MoonBit toolchain ships its data and" >&2
  echo "why3server, and moon prove drives those." >&2
  exit 1
fi

mkdir -p "$(dirname -- "$OUT")"
cat > "$OUT" <<CONF
[main]
magic = 14
datadir = "$TOOLCHAIN/share/why3"
libdir = "$TOOLCHAIN/lib/why3"
memlimit = 16000
running_provers_max = 16
timelimit = $TIMELIMIT.000000

$provers[strategy]
code = "start:
$quick t compute_specified start
t split_vc start
$deep"
desc = "escalating@ strategy"
name = "Escalating"
shortcut = "4"
CONF

echo "why3 config -> $OUT  solvers: $found  timelimit: ${TIMELIMIT}s"
