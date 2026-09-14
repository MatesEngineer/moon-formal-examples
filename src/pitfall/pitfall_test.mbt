// Both functions in this package are proved. Both are wrong. These tests are
// the record of how, so that the gap between the model and the machine is a
// documented fact rather than a surprise.

///|
/// The most negative `Int`, spelled the only way it can be spelled.
///
/// Not a literal — that is the whole subject of `abs_unguarded` — so it is
/// computed, which is also how a caller would come to be holding one.
fn int_min() -> Int {
  -2147483647 - 1
}

///|
test "abs_unguarded: the pre-condition excluded nothing" {
  // The contract says `-2147483648 < x`, which was meant to keep this value
  // out. The clause never became a verification condition, so the function is
  // defined here — and returns a negative absolute value.
  let broken = @pitfall.abs_unguarded(int_min())
  assert_eq(broken, int_min())
  assert_true(broken < 0)
}

///|
test "abs_diff_unsound: `0 <= result` is proved, and false" {
  // 2147483647 - (-2147483647) is 4294967294 over the integers, and -2 in an
  // `Int`. The proof is about the first number.
  let broken = @pitfall.abs_diff_unsound(2147483647, -2147483647)
  assert_eq(broken, -2)
  assert_true(broken < 0)
}

///|
test "abs_diff_unsound is correct wherever the true value is representable" {
  // The bug is exactly the overflow, which is worth pinning too: it is not
  // that the function is nonsense, it is that its contract does not say where
  // it stops holding.
  assert_eq(@pitfall.abs_diff_unsound(10, 4), 6)
  assert_eq(@pitfall.abs_diff_unsound(4, 10), 6)
  assert_eq(@pitfall.abs_diff_unsound(-3, -9), 6)
}
