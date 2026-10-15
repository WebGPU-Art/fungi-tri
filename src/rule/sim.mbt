///|
/// A toroidal grid of cells in states 0, 1, 2.
pub struct Grid {
  w : Int
  h : Int
  cells : FixedArray[Int]
}

///|
pub fn Grid::new(w : Int, h : Int) -> Grid {
  { w, h, cells: FixedArray::make(w * h, 0) }
}

///|
pub fn Grid::get(self : Grid, x : Int, y : Int) -> Int {
  self.cells[y * self.w + x]
}

///|
/// Same seed the renderer uses: a disk of state 1 around a smaller disk of
/// state 2, centered in the grid.
pub fn Grid::seed_disk(self : Grid, radius : Double) -> Unit {
  let cx = self.w.to_double() / 2.0
  let cy = self.h.to_double() / 2.0
  for y in 0..<self.h {
    for x in 0..<self.w {
      let dx = x.to_double() + 0.5 - cx
      let dy = y.to_double() + 0.5 - cy
      let d2 = dx * dx + dy * dy
      self.cells[y * self.w + x] = if d2 < radius * radius * 0.25 {
        2
      } else if d2 < radius * radius {
        1
      } else {
        0
      }
    }
  }
}

///|
/// A disk of random states, so a rule is also judged without the symmetry of
/// the disk seed.
pub fn Grid::seed_noise(self : Grid, radius : Double, rng : Rng) -> Unit {
  let cx = self.w.to_double() / 2.0
  let cy = self.h.to_double() / 2.0
  for y in 0..<self.h {
    for x in 0..<self.w {
      let dx = x.to_double() + 0.5 - cx
      let dy = y.to_double() + 0.5 - cy
      self.cells[y * self.w + x] = if dx * dx + dy * dy < radius * radius {
        rng.int(3)
      } else {
        0
      }
    }
  }
}

///|
/// Weight of a neighbor state inside the `a + 5 * b` count key.
let count_weight : FixedArray[Int] = [0, 1, 5]

///|
/// Writes the next generation of `src` into `dst`, returns how many cells
/// changed.
pub fn step(rule : Rule, src : Grid, dst : Grid) -> Int {
  let w = src.w
  let h = src.h
  let c = src.cells
  let out = dst.cells
  let mut changed = 0
  for y in 0..<h {
    let up = (y + h - 1) % h * w
    let mid = y * w
    let down = (y + 1) % h * w
    for x in 0..<w {
      let l = (x + w - 1) % w
      let r = (x + 1) % w
      let orth = count_weight[c[up + x]] +
        count_weight[c[down + x]] +
        count_weight[c[mid + l]] +
        count_weight[c[mid + r]]
      let diag = count_weight[c[up + l]] +
        count_weight[c[up + r]] +
        count_weight[c[down + l]] +
        count_weight[c[down + r]]
      let center = c[mid + x]
      let next = rule.table[center * 225 + pair_lut[orth] * 15 + pair_lut[diag]]
      out[mid + x] = next
      if next != center {
        changed += 1
      }
    }
  }
  changed
}
