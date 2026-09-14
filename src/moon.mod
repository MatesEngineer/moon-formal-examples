// Worked examples of MoonBit's formal verification.
//
// Three packages, in the order the README reads them:
//
//   saturating  contracts on plain integer arithmetic, and the machine-range
//               clauses that make them true of the machine and not only of
//               the mathematics
//   gap         a predicate, a loop invariant, and a theorem about an array:
//               the shape a real proof takes
//   pitfall     contracts that are accepted, proved, and wrong. Each one is a
//               failure mode of the verifier itself, pinned by a test.
//
// `source = "."` so that package paths read `mates/formal-examples/gap`
// rather than `mates/formal-examples/src/gap`.

name = "mates/formal-examples"

version = "0.1.0"

license = "MIT"

description = "Worked examples of formal verification in MoonBit"

keywords = [
  "moonbit",
  "formal-verification",
  "why3",
  "smt",
]

source = "."

preferred_target = "wasm"
