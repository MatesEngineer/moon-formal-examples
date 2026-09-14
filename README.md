# moon-formal-examples

Worked examples of [MoonBit](https://www.moonbitlang.com/)'s formal
verification (`moon prove`, Why3, Z3 and cvc5), with the whole toolchain
pinned so that `nix develop` gives you the same solvers this was written
against.

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
nix develop            # moon, why3, z3, cvc5, all pinned
./scripts/prove.sh     # discharge every proof obligation
moon -C src test       # run the tests
```

Without Nix: any MoonBit toolchain with `moon prove`, plus Why3 1.7+ and at
least one of z3, cvc5, alt-ergo on `PATH`.

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
conditions*, and the strategy in `scripts/why3-config.mjs` splits any condition
that does not discharge quickly, so a machine under load reports more of them
for the same source.

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
./scripts/prove.sh --machine-int
```

What actually happens, on the pinned toolchain:

| Package      | default | `--machine-int`             |
| ------------ | ------- | --------------------------- |
| `gap`        | proved  | proved                      |
| `saturating` | proved  | 19 proved, **3 timeout**    |
| `pitfall`    | proved  | **both functions fail**     |

`pitfall` failing is the point. That is what those two functions are for, and
under `--machine-int` the failure is reported against the *subtraction* rather
than against the post-condition, which is the more useful place to be told.

`saturating` not closing is the more interesting row. The proofs are not
unsound and the guards do short-circuit correctly in the generated Why3 (`if …
then … else false`); the goals simply do not discharge inside the time limit,
because every arithmetic operation now drags its own no-overflow obligation
through a function that already has five post-conditions. **The machine-integer
prelude is not a free switch.** It buys a real class of bug and it costs proof
time, and on this example the trade is visibly not free.

Which is the argument for what `src/saturating` does under the default prelude:
put the machine range into the contract by hand. It is verbose, and it closes
in seconds. Read the two alongside each other and the verbosity turns into a
choice rather than a ritual.

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

## Layout

```
flake.nix                    the dev shell: moon, why3, z3, cvc5
nix/moonbit.nix              the MoonBit toolchain as a Nix package
nix/toolchain.lock.json      content hashes for the rolling upstream artifacts
scripts/prove.sh             `moon prove` with a real solver strategy
scripts/why3-config.mjs      registers every solver on PATH; escalating strategy
scripts/nix/update-toolchain.mjs   re-pin when upstream rolls `latest`
src/saturating/              contracts on arithmetic
src/gap/                     a theorem about an array
src/pitfall/                 proved and wrong
```

MoonBit publishes its toolchain only under a rolling `latest` URL, so the lock
pins content hashes. When upstream rolls, the build fails loudly instead of
silently changing compiler; `nix run .#update-toolchain` moves the pin
deliberately.

## Licence

MIT.
