///|
/// A 3-state Fungi rule.
///
/// The full 3x3 pattern space has 3^9 = 19683 neighborhoods, which is far too
/// large to search with random tables (they are almost always noise). Instead a
/// rule looks at:
///
/// - the state of the center cell (0, 1 or 2),
/// - how many of the 4 orthogonal neighbors are in state 1 and in state 2,
/// - how many of the 4 diagonal neighbors are in state 1 and in state 2.
///
/// A pair of counts `(a, b)` with `a + b <= 4` has 15 possibilities, so the
/// table has `3 * 15 * 15 = 675` entries, each holding the next state.
/// Separating orthogonal from diagonal neighbors keeps the rule isotropic
/// while still allowing the crystal-like shapes the original Fungi rules show.
pub const STATES : Int = 3

///|
pub const PAIRS : Int = 15

///|
pub const ENTRIES : Int = 675

///|
/// Trits packed per byte in the hex encoding (3^5 = 243 < 256).
const TRITS_PER_BYTE : Int = 5

///|
pub const ENCODED_BYTES : Int = 135

///|
/// Maps `a + 5 * b` (count of state 1 plus five times count of state 2 among 4
/// neighbors) to the index of the pair `(a, b)`, or -1 when `a + b > 4`.
pub let pair_lut : FixedArray[Int] = {
  let lut = FixedArray::make(25, -1)
  let mut idx = 0
  for a in 0..<5 {
    for b in 0..<(5 - a) {
      lut[a + 5 * b] = idx
      idx += 1
    }
  }
  lut
}

///|
pub fn pair_index(a : Int, b : Int) -> Int {
  pair_lut[a + 5 * b]
}

///|
pub fn entry_index(center : Int, o1 : Int, o2 : Int, d1 : Int, d2 : Int) -> Int {
  center * PAIRS * PAIRS + pair_index(o1, o2) * PAIRS + pair_index(d1, d2)
}

///|
pub struct Rule {
  table : FixedArray[Int]
}

///|
pub fn Rule::new(table : FixedArray[Int]) -> Rule {
  // an empty neighborhood must stay empty, otherwise the background flickers
  table[0] = 0
  { table, }
}

///|
pub fn Rule::copy(self : Rule) -> Rule {
  let t = FixedArray::make(ENTRIES, 0)
  for i in 0..<ENTRIES {
    t[i] = self.table[i]
  }
  { table: t }
}

///|
pub fn Rule::get(self : Rule, idx : Int) -> Int {
  self.table[idx]
}

///|
/// Number of table entries where two rules disagree.
pub fn Rule::distance(self : Rule, other : Rule) -> Int {
  let mut d = 0
  for i in 0..<ENTRIES {
    if self.table[i] != other.table[i] {
      d += 1
    }
  }
  d
}

///|
let hex_digits : String = "0123456789abcdef"

///|
/// Packs the table into 135 bytes (5 trits per byte, little-endian trits)
/// and writes them as 270 lowercase hex characters.
pub fn Rule::to_hex(self : Rule) -> String {
  let buf = StringBuilder::new()
  for k in 0..<ENCODED_BYTES {
    let mut v = 0
    let mut mul = 1
    for i in 0..<TRITS_PER_BYTE {
      v += self.table[k * TRITS_PER_BYTE + i] * mul
      mul *= 3
    }
    buf.write_char(hex_digits.get_char(v >> 4).unwrap())
    buf.write_char(hex_digits.get_char(v & 15).unwrap())
  }
  buf.to_string()
}

///|
fn hex_value(c : Char) -> Int? {
  match c {
    '0'..='9' => Some(c.to_int() - '0'.to_int())
    'a'..='f' => Some(c.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(c.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
pub fn Rule::from_hex(s : String) -> Rule? {
  let chars = s.to_array()
  guard chars.length() == ENCODED_BYTES * 2 else { return None }
  let table = FixedArray::make(ENTRIES, 0)
  for k in 0..<ENCODED_BYTES {
    guard hex_value(chars[2 * k]) is Some(hi) else { return None }
    guard hex_value(chars[2 * k + 1]) is Some(lo) else { return None }
    let mut v = hi * 16 + lo
    guard v < 243 else { return None }
    for i in 0..<TRITS_PER_BYTE {
      table[k * TRITS_PER_BYTE + i] = v % 3
      v = v / 3
    }
  }
  Some(Rule::new(table))
}

///|
/// Random rule where each entry is non-zero with probability `lambda`; a
/// non-zero entry picks state 1 with probability `bias`.
pub fn Rule::random(rng : Rng, lambda : Double, bias : Double) -> Rule {
  let table = FixedArray::make(ENTRIES, 0)
  for i in 0..<ENTRIES {
    if rng.double() < lambda {
      table[i] = if rng.double() < bias { 1 } else { 2 }
    }
  }
  Rule::new(table)
}

///|
/// Copy of the rule with `n` randomly chosen entries reassigned.
pub fn Rule::mutate(self : Rule, rng : Rng, n : Int) -> Rule {
  let r = self.copy()
  for _ in 0..<n {
    let i = 1 + rng.int(ENTRIES - 1)
    r.table[i] = (r.table[i] + 1 + rng.int(2)) % 3
  }
  r
}

///|
/// Uniform crossover of two parents.
pub fn Rule::cross(self : Rule, other : Rule, rng : Rng) -> Rule {
  let t = FixedArray::make(ENTRIES, 0)
  for i in 0..<ENTRIES {
    t[i] = if rng.double() < 0.5 { self.table[i] } else { other.table[i] }
  }
  Rule::new(t)
}
