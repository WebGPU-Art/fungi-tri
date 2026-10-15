///|
test "pair lut covers 15 pairs" {
  let mut n = 0
  for v in pair_lut {
    if v >= 0 {
      n += 1
    }
  }
  inspect(n, content="15")
  inspect(pair_index(0, 0), content="0")
  inspect(pair_index(0, 4), content="4")
  inspect(pair_index(4, 0), content="14")
}

///|
test "hex round trip" {
  let rng = Rng::new(42)
  let r = Rule::random(rng, 0.4, 0.5)
  let hex = r.to_hex()
  inspect(hex.length(), content="270")
  let back = Rule::from_hex(hex).unwrap()
  inspect(back.distance(r), content="0")
  inspect(back.get(0), content="0")
}

///|
test "rejects bad hex" {
  inspect(Rule::from_hex("00") is None, content="true")
  inspect(Rule::from_hex("ff" + "00".repeat(134)) is None, content="true")
}

///|
test "empty rule kills the seed" {
  let r = Rule::new(FixedArray::make(ENTRIES, 0))
  let g = Grid::new(32, 32)
  g.seed_disk(5.0)
  let m = run_metrics(r, g, { size: 32, steps: 10, window: 5, radius: 5.0 })
  inspect(m.live, content="0")
  inspect(m.score, content="0")
}

///|
test "families build valid tables" {
  let rng = Rng::new(7)
  for k in 0..<FAMILIES {
    let r = Rule::family(rng, k)
    inspect(r.get(0), content="0")
    let back = Rule::from_hex(r.to_hex()).unwrap()
    inspect(back.distance(r), content="0")
  }
}

///|
test "cyclic rule keeps moving from a soup" {
  let rng = Rng::new(3)
  let r = Rule::cyclic(rng, 0.0)
  let g = Grid::new(48, 48)
  g.seed_soup(0.6, rng)
  let m = run_metrics(r, g, { size: 48, steps: 60, window: 20, radius: 8.0 })
  inspect(m.live > 0.0, content="true")
}
