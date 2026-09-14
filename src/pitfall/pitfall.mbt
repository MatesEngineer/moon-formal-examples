///|
/// `|x|`, restricted to the values whose negation is representable.
///
/// The contract is honest and the implementation honours it: `Int::MIN_VALUE`
/// is the one value whose absolute value is not an `Int`, the pre-condition
/// excludes exactly that value, and everything else is fine. `moon prove`
/// discharges this under both proof models.
///
/// The pitfall is what the pre-condition *is*. `proof_require` is an
/// obligation on callers, discharged when the caller is itself verified. It is
/// not a runtime check. Nothing prevents a caller passing `MIN_VALUE`, nothing
/// reports it when they do, and the function then returns a negative absolute
/// value with no contract violated as far as anything executing is concerned.
/// The test alongside this file does exactly that.
///
/// So a chain of proofs is only as good as its ends. Where verified code meets
/// unverified code, the pre-condition has to be re-established by something
/// that runs: a check, a type, or a value that cannot be out of range in the
/// first place.
///
/// One more thing worth knowing, because the two models disagree about it.
/// Under the default prelude this pre-condition does no work at all: `Int` is
/// unbounded there, so `0 <= |x|` holds for every `x` and deleting the clause
/// changes nothing. Under `--machine-int` the negation carries a no-overflow
/// obligation of its own, and the clause is exactly what discharges it. Same
/// text, two different theorems, and only one of them needed the hypothesis.
pub fn abs_unguarded(
  x : Int,
) -> Int where {
  proof_require: -2147483648 < x,
  proof_ensure: result => 0 <= result,
  proof_reasoning: (
    #| Under the default prelude: two branches, and over ℤ the negation of a
    #| negative is positive. The hypothesis is not used.
    #|
    #| Under the machine-integer prelude the interesting goal is not the
    #| post-condition but the negation's own range obligation, and
    #| `-2147483648 < x` is exactly strong enough to close it.
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
/// `proof_ensure: 0 <= result` is proved under the default prelude, and on the
/// machine the result can be negative. Both statements are true, about
/// different things: over the integers `2147483647 - (-2147483647)` is
/// `4294967294`, which is duly non-negative; in an `Int` it wraps to `-2`.
///
/// This is the sharper of the two, because nothing about the contract looks
/// incomplete. There is no missing hypothesis to notice and no clause absent
/// from the generated Why3. The proof is correct and its conclusion does not
/// hold of the compiled program, and the only thing wrong is that the model
/// was the wrong one.
///
/// A unit test found it on the first run, which is the pairing this repository
/// is about: the proof covers the case analysis a test cannot enumerate, and
/// the test covers the machine the proof cannot see.
///
/// Under `--machine-int` this function stops being provable. Note the shape of
/// that result: on the pinned toolchain its goals come back **timeout**, not
/// invalid. The solver ran out of time; it did not produce a counterexample.
/// A timeout says only that this configuration did not close the goal, and the
/// reason to believe the function is actually broken is the test below, not
/// the failed proof.
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
    #| obligation which nothing in the contract discharges. Fixing it means
    #| bounding both operands, which is what `src/saturating` does.
  ),
} {
  if a < b {
    b - a
  } else {
    a - b
  }
}
