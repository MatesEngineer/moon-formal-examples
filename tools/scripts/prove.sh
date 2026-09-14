#!/usr/bin/env sh
# Discharge every proof obligation in the module.
#
# Wraps `moon prove` with a generated Why3 configuration (see
# `why3-config.sh`) so that every solver on PATH is registered and the time
# limit is high enough for the quantified array invariants in `gap`.
#
# Usage: ./tools/scripts/prove.sh [--machine-int] [package ...]
#
# `--machine-int` swaps the proof prelude for the machine-integer one the
# toolchain also ships, in which `Int` is a Why3 range type and every
# arithmetic operation carries a no-overflow obligation. `saturating` and `gap`
# prove under both; `pitfall` proves only under the default, which is what it
# is for.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONF="$ROOT/src/_build/verif/why3.conf"

if [ "${1:-}" = "--machine-int" ]; then
  shift
  MOON_PROVE_PRELUDE_OVERRIDE="$(dirname "$(command -v moon)")/../lib/prelude_proof_machine_int"
  export MOON_PROVE_PRELUDE_OVERRIDE
  echo "prelude -> $MOON_PROVE_PRELUDE_OVERRIDE"
fi

"$ROOT/tools/scripts/why3-config.sh" "$CONF"

if [ "$#" -eq 0 ]; then
  exec moon -C "$ROOT/src" prove --why3-config "$CONF"
fi

status=0
for pkg in "$@"; do
  moon -C "$ROOT/src" prove --why3-config "$CONF" "$pkg" || status=1
done
exit "$status"
