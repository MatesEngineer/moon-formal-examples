# moon-formal-examples

Worked examples of [MoonBit](https://www.moonbitlang.com/)'s formal
verification (`moon prove`, Why3, Z3 and cvc5), with the whole toolchain
pinned so that `nix develop` gives you the same compiler and solvers this was
written against.

Three packages, in the order they are meant to be read:

| Package           | What it shows                                                              |
| ----------------- | -------------------------------------------------------------------------- |
| `src/saturating`  | a contract on plain arithmetic, and the machine range written in by hand   |
| `src/gap`         | a predicate, a loop invariant, and a theorem about an array                |
| `src/pitfall`     | contracts that are accepted, proved, and wrong                             |

They are extracted from a real use: a shape-matching algorithm whose integer
skeleton is proved and whose floating-point half is not. `gap` is the part of
it that mattered most, reduced to the size worth reading.

## Run it

```bash
nix develop --command ./tools/scripts/prove.sh   # discharge every obligation
nix develop --command moon -C src test           # run the tests
```

Or `nix develop` once for an interactive shell and run them from inside it.
(`nix develop && ...` does not work: `nix develop` *is* the shell, so the
right-hand side would run after you exit it.)

Without Nix: any MoonBit toolchain with `moon prove`, plus at least one of
z3, cvc5 or alt-ergo on `PATH`.

Note what is *not* in that list. **Why3 does not have to be installed
separately.** The MoonBit toolchain ships Why3's data and drivers under
`share/why3` and its `why3server` under `lib/why3`, and `moon prove` drives
those directly; this repository proves clean with no `why3` binary on `PATH` at
all. Under Nix that is worth more than tidiness, because nixpkgs' `why3` is
built from OCaml and pulls an OCaml toolchain into a closure that otherwise has
none.

Expected output:

```
mates/formal-examples/gap
  Succeeded: 4 goals proved

mates/formal-examples/pitfall
  Succeeded: 2 goals proved

mates/formal-examples/saturating
  Succeeded: 2 goals proved

Summary:
  3 of 3 packages proved
  8 goals proved
```

The goal count is not a property of the code. It counts *verification
conditions*, and the strategy in `tools/scripts/why3-config.sh` splits any
condition that does not discharge quickly, so a machine under load reports more
of them for the same source.

Everything measured in this README was run with the toolchain this repository
pins: **moon 0.1.20260904** (`moonc v0.10.12+1634b282e`), **Why3 1.8.2**,
**Z3 4.16.0**, **cvc5 1.3.4**, on aarch64-darwin, 120s per prover call.

## The one thing to know first

A contracted function may not contain floating-point operations at all:

```
only Bool, Byte, Int, UInt, Int64, and UInt64 constants are supported
in contracted function body
```

For a numeric algorithm that sounds like the end of the conversation, and it is
not. The move is to split each computation in two. The arithmetic that decides
an **index** goes in a package with contracts; the arithmetic that decides a
**value** stays outside, with no index expression of its own left to get
wrong. `clamp_div` in `src/gap` is the seam: it takes an integer
chosen by floating-point code it knows nothing about, and clamps rather than
trusts it. A numeric solver returning nonsense still cannot produce a malformed
array.

That is the whole technique. Everything else is detail.

## Two models of `Int`

The toolchain ships two proof preludes, and which one you are in decides what
your contracts mean.

**Default** (`lib/prelude_proof`). `Int` is a mathematical integer: `type t =
int`, `in_bounds` is `true`, and overflow does not exist. Proofs are fast and
say nothing about the machine.

**Machine integers** (`lib/prelude_proof_machine_int`). `Int` is a Why3 range
type, `< range -0x8000_0000 0x7fff_ffff >`, and every arithmetic operation
carries its own no-overflow obligation.

```bash
nix develop --command ./tools/scripts/prove.sh --machine-int
```

`--machine-int` is this repository's own flag, handled by `prove.sh`: it sets
`MOON_PROVE_PRELUDE_OVERRIDE` to the machine-integer prelude in the toolchain.

What actually happens, measured on the pinned toolchain below, at the default
120s per prover call in the long pass (the strategy tries each solver in turn,
so a goal may spend more than that before it is given up on):

| Package      | default          | `--machine-int`                             |
| ------------ | ---------------- | ------------------------------------------- |
| `gap`        | 4 valid          | 4 valid                                     |
| `saturating` | 2 valid          | 19 valid, 3 timeout, all in `add`           |
| `pitfall`    | 2 valid          | 2 valid, 2 timeout, all in `abs_diff_unsound` |

Three things are worth reading carefully in that table.

**Nothing comes back `invalid`.** Every failure is a *timeout*: the solver ran
out of time, which is not the same as reporting the goal false. Why3
distinguishes these and so should any claim made from them. That
`abs_diff_unsound` is genuinely broken is established by the test next to it,
not by the failed proof.

**Only `add` and `abs_diff_unsound` stop closing.** `iabs` and
`abs_unguarded` prove under both models. `abs_unguarded` in particular is
*correct*: its pre-condition excludes the one value that would break it, and
the machine-integer model is precisely where that pre-condition starts doing
work. What it demonstrates is not a wrong proof but an unenforced one.

**Why `add` times out is not established.** The guards do short-circuit
correctly in the generated Why3 (`if … then … else false`), so that particular
suspicion is ruled out. The plausible remaining explanation is the extra range
obligation on every arithmetic operation inside a function that already has
five post-conditions, but a timeout on its own does not prove that, and no
attempt was made here to close the goals with auxiliary lemmas or a longer
limit.

So: the machine-integer prelude buys a real class of bug and costs proof time,
and on this example the trade is visibly not free. That is the argument for
what `src/saturating` does under the default prelude, which is to put the
machine range into the contract by hand. It is verbose, and it closes in
seconds.

## What a proof is not

Worth being clear about, because "formally verified" invites more than is
being claimed:

- **A proof is about the contract, not about the intent.** `moon prove` shows
  the code satisfies what you wrote down. Whether what you wrote down is what
  you meant is not a formal question, which is why `gap` also exports
  `is_total`, the same property as a runtime check, sharing nothing with the
  proof but the predicate.
- **A pre-condition is an obligation on callers, not a runtime check.** Nothing
  stops a caller violating one, and nothing reports it when they do. See
  `abs_unguarded` in `src/pitfall`.
- **A proof discharged in the wrong model is worth nothing.** See
  `abs_diff_unsound` in `src/pitfall`: proved, and false.
- **A proof covers the inputs the pre-conditions admit, not all inputs.**
  "For every input" always means "for every input satisfying the contract".
- **A predicate proves what it says, not what its name suggests.** `gap`'s
  `total` says no entry equals `-1`. It does not say the entries are valid
  indices into anything, and an array of `-2`s satisfies it. Making the
  downstream read safe needs a second property about the range of the values,
  which this example deliberately does not carry.
- **A failed proof is usually a timeout, and a timeout is not a
  counterexample.** Nothing in this repository ever comes back `invalid`.

## Layout

```
flake.nix                     the dev shell: the pinned moon, plus z3 and cvc5
tools/scripts/prove.sh        `moon prove` with a real solver strategy
tools/scripts/why3-config.sh  every solver on PATH; escalating strategy
src/saturating/               contracts on arithmetic
src/gap/                      a theorem about an array
src/pitfall/                  proved, and not what the name suggests
```

The toolchain comes from
[moonbit-overlay](https://github.com/moonbit-community/moonbit-overlay), pinned
to the exact version every measurement here was taken with
(`v0.10.12+1634b282e+94521db`). That is worth a sentence, because upstream
publishes its toolchain only under a rolling `latest` URL: a lock against that
URL stops resolving once upstream moves and the old artifact leaves every
cache. The overlay mirrors each version to its own GitHub release, so the URL
this flake resolves is immutable. Bumping the toolchain means changing one
string in `flake.nix` and re-running the measurements.

## Licence

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).

Read it, learn from it, adapt it, write about it. Attribute it, do not use it
commercially, and share adaptations under the same terms. If you want it for
something commercial, ask.
