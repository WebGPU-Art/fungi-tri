///|
/// Small deterministic generator (splitmix64), identical on every target so a
/// search seed always reproduces the same rules.
pub struct Rng {
  mut state : UInt64
}

///|
pub fn Rng::new(seed : UInt64) -> Rng {
  { state: seed }
}

///|
pub fn Rng::next(self : Rng) -> UInt64 {
  self.state = self.state + 0x9E3779B97F4A7C15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}

///|
/// Uniform double in [0, 1).
pub fn Rng::double(self : Rng) -> Double {
  (self.next() >> 11).to_double() / 9007199254740992.0
}

///|
/// Uniform int in [0, limit).
pub fn Rng::int(self : Rng, limit : Int) -> Int {
  (self.next() % limit.to_uint64()).to_int()
}
