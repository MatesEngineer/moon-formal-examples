// Two functions. Both are accepted, both are proved, and both are wrong.
//
// They are wrong in the same way, and it is the way that matters most when
// verifying a numeric algorithm: the default proof model gives `Int` the
// semantics of a *mathematical* integer, so overflow is not merely unchecked,
// it is unrepresentable. A contract stated in that model cannot mention the
// machine, and a proof discharged in it is a proof about a program that
// resembles the one being compiled.
//
// Two ways out, and this package exists to demonstrate both:
//
//   * write the machine range into the contract by hand, which is what
//     `src/saturating` does;
//   * or prove against the machine-integer prelude the toolchain also ships,
//     where `Int` is a Why3 range type and every arithmetic operation carries
//     its own no-overflow obligation:
//
//         ./scripts/prove.sh --machine-int pitfall
//
//     Under that prelude both functions below stop proving, which is the
//     result to look at. Under the default one they pass.

///|
/// `|x|`, with a pre-condition that the default model cannot use.
///
/// The intent is to exclude the one value whose negation is not an `Int`. Two
/// things about that intent go wrong at once, and neither produces a
/// diagnostic:
///
///   * under the default prelude the clause is inert. `Int` is unbounded
///     there, so `0 <= |x|` holds for every `x` and the hypothesis carries no
///     weight. Deleting it changes nothing, which is a good way to discover
///     that a pre-condition you believed in is decorative;
///   * a `proof_require` is a *proof* obligation on callers, not a runtime
///     check. Nothing stops the value being passed, and the test alongside
///     this file passes it: the result is negative, and no contract was
///     violated as far as anything executing is concerned.
///
/// So the domain restriction is real, unenforced, and, in the model it was
/// written in, unused. `./scripts/prove.sh --machine-int` is where it starts
/// meaning something.
///
/// A historical note, which is why this repository pins its toolchain: on
/// toolchains before roughly 0.1.20260904, writing `-2147483648` in a contract
/// produced *no verification condition at all* rather than an inert one. `Int`
/// cannot hold `2147483648`, so the literal is a negation of a value that does
/// not exist, and the clause silently vanished from the generated Why3. The
/// function then appeared proved with a hypothesis nobody had checked. On the
/// pinned toolchain the clause does survive; `grep requires` in
/// `src/_build/verif/pitfall/*.mlw` after a run shows it. Behaviour like this
/// moves between versions, which is the argument for pinning it rather than
/// for remembering it.
pub fn abs_unguarded(
  x : Int,
) -> Int where {
  proof_require: -2147483648 < x,
  proof_ensure: result => 0 <= result,
  proof_reasoning: (
    #| Under the default prelude: two branches, and over ℤ negation of a
    #| negative is positive. The hypothesis is not used.
    #|
    #| Under the machine-integer prelude the goal is not the post-condition but
    #| the negation itself, which has a no-overflow obligation of its own, and
    #| `-2147483648 < x` is exactly strong enough to discharge it. Same text,
    #| different theorem.
  ),
} {
  if x < 0 {
    -x
  } else {
    x
  }
}

///|
/// `|a - b|`.
///
/// `proof_ensure: 0 <= result` is proved, and on the machine the result can be
/// negative. Both statements are true, about different things: over the
/// integers `2147483647 - (-2147483647)` is `4294967294`, which is duly
/// non-negative; in an `Int` it wraps to `-2`.
///
/// This is the sharper of the two, because nothing about the contract looks
/// incomplete. There is no missing hypothesis to notice, no literal out of
/// range, no clause that fails to appear in the generated Why3. The proof is
/// correct and the conclusion does not hold of the code, and the only signal
/// is that the model was the wrong one.
///
/// A unit test found it on the first run, which is the pairing this whole
/// repository is about: the proof covers the case analysis a test cannot
/// enumerate, and the test covers the machine the proof cannot see.
pub fn abs_diff_unsound(
  a : Int,
  b : Int,
) -> Int where {
  proof_ensure: result => 0 <= result,
  proof_reasoning: (
    #| Two branches, each subtracting the smaller from the larger, so over ℤ
    #| the result is non-negative. Every step of that is right and the
    #| conclusion is false of the compiled program.
    #|
    #| Under the machine-integer prelude the subtraction carries a no-overflow
    #| obligation which nothing in the contract discharges, and it fails,
    #| naming the operation rather than the post-condition. That is the more
    #| useful place to be told.
  ),
} {
  if a < b {
    b - a
  } else {
    a - b
  }
}
