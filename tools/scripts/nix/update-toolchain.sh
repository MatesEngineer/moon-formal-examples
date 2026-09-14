#!/usr/bin/env sh
# Re-pin the rolling MoonBit artifacts in `tools/nix/toolchain.lock.json`.
#
# MoonBit publishes its toolchain only under `latest`; there are no immutable
# per-version download paths. So the lock pins the *content*, and when upstream
# rolls, every hash in it stops matching at once and `nix develop` fails with a
# hash mismatch rather than silently changing compiler. This is the other half
# of that bargain: the command that moves the pin deliberately.
#
#   nix run .#update-toolchain              re-pin, and say what moved
#   nix run .#update-toolchain -- --dry-run say what would move
#
# The version fields are informational, and refreshed anyway, by unpacking the
# host platform's tarball and asking it. A stale pin is then legible at a
# glance rather than only as a hash.
#
# It uses nothing but `nix`, `jq` and `tar`, and deliberately does not use the
# toolchain it repairs: when the pin is stale, which is the only time anyone
# runs this, there is no working `moon` to start it with.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
LOCK="$ROOT/tools/nix/toolchain.lock.json"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
changes="$work/changes"
: > "$changes"

note() { # what before after
  [ "$2" = "$3" ] && return 0
  printf '  %s\n    %s\n -> %s\n' "$1" "$2" "$3" >> "$changes"
}

# The SRI hash Nix computes for a URL's contents, and where it stored them.
prefetch() { nix store prefetch-file --json --hash-type sha256 "$1"; }

jqr() { jq -r "$1" "$LOCK"; }

base_url=$(jqr '.moonbit.baseUrl')
core_url=$(jqr '.moonbit.coreUrl')
systems=$(jqr '.moonbit.platforms | keys[]')

# This machine, as the lock names platforms.
case $(uname -m) in
arm64 | aarch64) arch=aarch64 ;;
*) arch=x86_64 ;;
esac
case $(uname -s) in
Darwin) host="$arch-darwin" ;;
*) host="$arch-linux" ;;
esac

updated="$work/lock.json"
cp "$LOCK" "$updated"

# -- the hashes --------------------------------------------------------------

core=$(prefetch "$core_url")
core_hash=$(printf '%s' "$core" | jq -r .hash)
note "core-latest.zip" "$(jqr '.moonbit.coreHash')" "$core_hash"
jq --arg h "$core_hash" '.moonbit.coreHash = $h' "$updated" > "$work/t" && mv "$work/t" "$updated"

host_store=
for system in $systems; do
  asset=$(jq -r --arg s "$system" '.moonbit.platforms[$s].asset' "$updated")
  before=$(jq -r --arg s "$system" '.moonbit.platforms[$s].hash' "$updated")
  result=$(prefetch "$base_url/$asset")
  hash=$(printf '%s' "$result" | jq -r .hash)
  note "$asset" "$before" "$hash"
  jq --arg s "$system" --arg h "$hash" '.moonbit.platforms[$s].hash = $h' "$updated" > "$work/t" && mv "$work/t" "$updated"
  [ "$system" = "$host" ] && host_store=$(printf '%s' "$result" | jq -r .storePath)
done

# -- the version fields ------------------------------------------------------

if [ -n "$host_store" ]; then
  unpacked="$work/toolchain"
  mkdir -p "$unpacked"
  tar -xzf "$host_store" -C "$unpacked" ./bin/moon ./bin/moonc
  chmod +x "$unpacked/bin/moon" "$unpacked/bin/moonc"
  # `moon version` reports `moon 0.1.20260904 (94521db 2026-09-04)`.
  reported=$("$unpacked/bin/moon" version)
  version=$(printf '%s' "$reported" | sed -n 's/^moon \([^ ]*\) (.*/\1/p')
  date=$(printf '%s' "$reported" | sed -n 's/^moon [^ ]* ([^ ]* \([^)]*\))/\1/p')
  moonc=$("$unpacked/bin/moonc" -v | awk '{print $1}')
  if [ -n "$version" ]; then
    note "version" "$(jq -r '.moonbit.version' "$updated")" "$version"
    note "date" "$(jq -r '.moonbit.date' "$updated")" "$date"
    jq --arg v "$version" --arg d "$date" \
      '.moonbit.version = $v | .moonbit.date = $d' "$updated" > "$work/t" && mv "$work/t" "$updated"
  fi
  if [ -n "$moonc" ]; then
    note "moonc" "$(jq -r '.moonbit.moonc' "$updated")" "$moonc"
    jq --arg m "$moonc" '.moonbit.moonc = $m' "$updated" > "$work/t" && mv "$work/t" "$updated"
  fi
else
  echo "no pinned artifact for $host; leaving the version fields alone." >&2
fi

# -- the verdict -------------------------------------------------------------

if [ ! -s "$changes" ]; then
  echo "toolchain.lock.json is already current."
  exit 0
fi

echo "$(grep -c '^  [^ ]' "$changes") field(s) moved:"
cat "$changes"

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "--dry-run: nothing written."
  exit 0
fi

mv "$updated" "$LOCK"
echo
echo "wrote $LOCK. Run \`nix develop\` to build against it."
