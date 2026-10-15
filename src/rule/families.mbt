///|
/// Builds a table from a function of the center state and the neighbor
/// counts: `(center, orth1, orth2, diag1, diag2) -> next`.
pub fn Rule::build(f : (Int, Int, Int, Int, Int) -> Int) -> Rule {
  let table = FixedArray::make(ENTRIES, 0)
  for c in 0..<3 {
    for a in 0..<5 {
      for b in 0..<(5 - a) {
        for d in 0..<5 {
          for e in 0..<(5 - d) {
            table[entry_index(c, a, b, d, e)] = f(c, a, b, d, e)
          }
        }
      }
    }
  }
  Rule::new(table)
}

///|
/// Random subset of `0..=max` holding `count` numbers.
fn random_set(rng : Rng, max : Int, count : Int) -> FixedArray[Bool] {
  let set = FixedArray::make(max + 1, false)
  for _ in 0..<count {
    set[rng.int(max + 1)] = true
  }
  set
}

///|
/// Scrambles a share of the table so a family is a starting point rather
/// than a fixed formula.
fn Rule::with_noise(self : Rule, rng : Rng, noise : Double) -> Rule {
  self.mutate(rng, (noise * ENTRIES.to_double()).to_int())
}

///|
/// Outer-totalistic rule: the next state only depends on the center and the
/// total counts of each state among all 8 neighbors (3 * 45 cases), which
/// makes smoother, more isotropic rules than a fully random table.
pub fn Rule::totalistic(rng : Rng, lambda : Double, bias : Double) -> Rule {
  let sub = FixedArray::make(3 * 81, 0)
  for i in 0..<(3 * 81) {
    if rng.double() < lambda {
      sub[i] = if rng.double() < bias { 1 } else { 2 }
    }
  }
  Rule::build(fn(c, a, b, d, e) { sub[c * 81 + (a + d) * 9 + (b + e)] })
}

///|
/// Excitable medium, the kind that makes waves and spirals: one live state
/// is "excited", the other "refractory". Excited turns refractory,
/// refractory rests, and a resting cell gets excited when the weighted count
/// of excited neighbors (orthogonal twice, diagonal once) falls in a band.
pub fn Rule::excitable(rng : Rng, noise : Double) -> Rule {
  let excited = 1 + rng.int(2)
  let refractory = 3 - excited
  let lo = 1 + rng.int(4)
  let hi = lo + rng.int(5)
  let triggers = FixedArray::make(13, false)
  for k in lo..<=hi {
    if k < 13 {
      triggers[k] = rng.double() < 0.85
    }
  }
  Rule::build(fn(c, a, b, d, e) {
    let (oe, de) = if excited == 1 { (a, d) } else { (b, e) }
    if c == excited {
      refractory
    } else if c == refractory {
      0
    } else if triggers[2 * oe + de] {
      excited
    } else {
      0
    }
  }).with_noise(rng, noise)
}

///|
/// Cyclic (rock-paper-scissors) rule: 0 is eaten by 1, 1 by 2, 2 by 0, each
/// when enough neighbors of the eating state are around. Known for spirals
/// and rotating domains. Half of the rules only count orthogonal neighbors.
pub fn Rule::cyclic(rng : Rng, noise : Double) -> Rule {
  let orth_only = rng.double() < 0.5
  let t0 = 1 + rng.int(3)
  let t1 = 1 + rng.int(3)
  let t2 = 1 + rng.int(if orth_only { 3 } else { 5 })
  Rule::build(fn(c, a, b, d, e) {
    let n1 = if orth_only { a } else { a + d }
    let n2 = if orth_only { b } else { b + e }
    let n0 = (if orth_only { 4 } else { 8 }) - n1 - n2
    match c {
      0 => if n1 >= t0 { 1 } else { 0 }
      1 => if n2 >= t1 { 2 } else { 1 }
      _ => if n0 >= t2 { 0 } else { 2 }
    }
  }).with_noise(rng, noise)
}

///|
/// Two Life-like species sharing a grid: each state has its own birth and
/// survival sets over the count of same-state neighbors, and may convert
/// the other species when enough of its own kind surrounds it.
pub fn Rule::life(rng : Rng, noise : Double) -> Rule {
  let birth1 = random_set(rng, 8, 1 + rng.int(3))
  let birth2 = random_set(rng, 8, 1 + rng.int(3))
  let survive1 = random_set(rng, 8, 2 + rng.int(4))
  let survive2 = random_set(rng, 8, 2 + rng.int(4))
  let convert1 = if rng.double() < 0.5 { 9 } else { 3 + rng.int(4) }
  let convert2 = if rng.double() < 0.5 { 9 } else { 3 + rng.int(4) }
  let dominant = 1 + rng.int(2)
  Rule::build(fn(c, a, b, d, e) {
    let n1 = a + d
    let n2 = b + e
    match c {
      0 =>
        if birth1[n1] && birth2[n2] {
          dominant
        } else if birth1[n1] {
          1
        } else if birth2[n2] {
          2
        } else {
          0
        }
      1 => if n2 >= convert2 { 2 } else if survive1[n1] { 1 } else { 0 }
      _ => if n1 >= convert1 { 1 } else if survive2[n2] { 2 } else { 0 }
    }
  }).with_noise(rng, noise)
}

///|
/// Predator and prey: prey (1) spreads into empty cells, predators (2) eat
/// adjacent prey and starve without it. Makes chasing fronts and pulses.
pub fn Rule::predator(rng : Rng, noise : Double) -> Rule {
  let grow = 1 + rng.int(3)
  let eat = 1 + rng.int(3)
  let starve = 1 + rng.int(2)
  let crowd = if rng.double() < 0.5 { 9 } else { 6 + rng.int(3) }
  Rule::build(fn(c, a, b, d, e) {
    let n1 = a + d
    let n2 = b + e
    match c {
      0 => if n1 >= grow { 1 } else { 0 }
      1 => if n2 >= eat { 2 } else if n1 >= crowd { 0 } else { 1 }
      _ => if n1 < starve { 0 } else { 2 }
    }
  }).with_noise(rng, noise)
}

///|
/// Voting: a cell takes the most common state of its 3x3 block. On its own
/// this freezes into domains, so the noise share matters here.
pub fn Rule::vote(rng : Rng, noise : Double) -> Rule {
  let tie = rng.int(3)
  Rule::build(fn(c, a, b, d, e) {
    let n1 = a + d + (if c == 1 { 1 } else { 0 })
    let n2 = b + e + (if c == 2 { 1 } else { 0 })
    let n0 = 9 - n1 - n2
    if n1 > n2 && n1 > n0 {
      1
    } else if n2 > n1 && n2 > n0 {
      2
    } else if n0 > n1 && n0 > n2 {
      0
    } else {
      tie
    }
  }).with_noise(rng, noise)
}

///|
/// Number of rule families `Rule::family` knows.
pub const FAMILIES : Int = 7

///|
/// A random rule from family `k` (0..FAMILIES).
pub fn Rule::family(rng : Rng, k : Int) -> Rule {
  let noise = 0.2 * rng.double()
  match k % FAMILIES {
    0 => Rule::random(rng, 0.1 + 0.6 * rng.double(), 0.2 + 0.6 * rng.double())
    1 =>
      Rule::totalistic(rng, 0.2 + 0.6 * rng.double(), 0.2 + 0.6 * rng.double())
    2 => Rule::excitable(rng, noise)
    3 => Rule::cyclic(rng, noise)
    4 => Rule::life(rng, noise)
    5 => Rule::predator(rng, noise)
    _ => Rule::vote(rng, noise)
  }
}
