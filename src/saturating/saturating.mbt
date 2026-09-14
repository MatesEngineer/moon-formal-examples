// `a + b`, clamped rather than wrapped.
//
// The verifier reasons about *mathematical* integers. To it `a + b` is simply
// `a + b`, always correct, never overflowing, which is precisely the wrong
// model for the bug this module exists to prevent. So the machine range is
// stated explicitly, in both directions:
//
//   * as pre-conditions, because an `Int` parameter is, to the solver, an
//     arbitrary integer. Without `INT_FLOOR <= a` there is nothing stopping
//     `a` from being negative beyond any bound, and the claim that the result
//     is representable is then simply false;
//   * as post-conditions, because "the result is representable" and "the
//     result is the true sum" are different claims and only the first one
//     holds unconditionally.
//
// Both are trivial for callers to satisfy: every caller is holding a machine
// integer already.

///|
/// The largest `Int`, and the ceiling this module saturates at.
pub const INT_MAX : Int = 2147483647

///|
/// The most negative value this module works with.
///
/// Not `Int::min_value`, which is one lower, and the reason is about the
/// contract language rather than about the arithmetic: `-2147483648` cannot be
/// written as a literal. It is the negation of `2147483648`, which is not an
/// `Int`. A `proof_require` containing it does not fail to compile and does not
/// warn. It produces *no verification condition at all*: the clause vanishes,
/// `moon prove` reports the function proved, and nothing about it was ever
/// asked.
///
/// See `src/pitfall` for that failure demonstrated in isolation.
pub const INT_FLOOR : Int = -2147483647

///|
/// `a + b`, clamped to `[INT_FLOOR, INT_MAX]`.
///
/// ```moonbit nocheck
/// assert_eq(@saturating.add(2, 3), 5)
/// assert_eq(@saturating.add(2147483647, 1), 2147483647)
/// ```
pub fn add(
  a : Int,
  b : Int,
) -> Int where {
  proof_require: -2147483647 <= a,
  proof_require: a <= 2147483647,
  proof_require: -2147483647 <= b,
  proof_require: b <= 2147483647,
  proof_ensure: result => -2147483647 <= result,
  proof_ensure: result => result <= 2147483647,
  proof_ensure: result => {
    -2147483647 <= a + b && a + b <= 2147483647 → result == a + b
  },
  proof_ensure: result => 2147483647 < a + b → result == 2147483647,
  proof_ensure: result => a + b < -2147483647 → result == -2147483647,
  proof_reasoning: (
    #| Three branches, and they are the same three cases the post-conditions
    #| are stated in. That correspondence is the whole strategy: every
    #| obligation reduces to one branch, and the solver is never asked to
    #| discover a case split of its own.
    #|
    #| The guards are written as comparisons against the *headroom*
    #| (`INT_MAX - b`) rather than against the sum, because computing the sum
    #| in order to test it is the overflow. On the machine that distinction is
    #| the entire point; to the verifier the two are equivalent, which is why
    #| a proof alone would not have caught writing it the other way.
  ),
} {
  if b > 0 && a > INT_MAX - b {
    INT_MAX
  } else if b < 0 && a < INT_FLOOR - b {
    INT_FLOOR
  } else {
    a + b
  }
}

///|
/// `|x|`.
///
/// `Int::min_value` is excluded by the pre-condition rather than handled,
/// because its absolute value is not an `Int` and there is no answer to give.
/// Every caller in a real program holds a value that came from somewhere with
/// a narrower range (a coordinate, a length, an index) and satisfies it
/// without thinking about it.
pub fn iabs(
  x : Int,
) -> Int where {
  proof_require: -2147483647 <= x,
  proof_require: x <= 2147483647,
  proof_ensure: result => 0 <= result,
  proof_ensure: result => result <= 2147483647,
  proof_ensure: result => 0 <= x → result == x,
  proof_ensure: result => x < 0 → result == -x,
  proof_reasoning: (
    #| Two branches matching the last two clauses. The bound `result <= INT_MAX`
    #| needs the pre-condition and nothing else: `-x` for `x >= INT_FLOOR` is at
    #| most `INT_MAX`, which is exactly why `INT_FLOOR` is `-INT_MAX` and not
    #| `Int::min_value`.
  ),
} {
  if x < 0 {
    -x
  } else {
    x
  }
}
