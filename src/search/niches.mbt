///|
/// Behavior coordinates of a run from the dense soup: activity, density and
/// clumping, binned. The niche search keeps the best rule in each bin, so
/// the output covers kinds of behavior the main search never prefers (fast
/// waves, sparse gliders, dense boiling domains...).
fn niche_of(m : @rule.Metrics) -> Int {
  let churn_bin = if m.churn < 0.02 {
    0
  } else if m.churn < 0.06 {
    1
  } else if m.churn < 0.15 {
    2
  } else if m.churn < 0.35 {
    3
  } else {
    4
  }
  let live_bin = if m.live < 0.06 {
    0
  } else if m.live < 0.15 {
    1
  } else if m.live < 0.3 {
    2
  } else {
    3
  }
  let clump_bin = if m.clumping < 2.0 {
    0
  } else if m.clumping < 5.0 {
    1
  } else {
    2
  }
  (churn_bin * 4 + live_bin) * 3 + clump_bin
}

///|
/// Words for a niche, shown when hovering a tile.
fn niche_label(m : @rule.Metrics) -> String {
  let speed = if m.churn < 0.02 {
    "slow"
  } else if m.churn < 0.06 {
    "calm"
  } else if m.churn < 0.15 {
    "busy"
  } else if m.churn < 0.35 {
    "fast"
  } else {
    "frantic"
  }
  let density = if m.live < 0.06 {
    "sparse"
  } else if m.live < 0.15 {
    "light"
  } else if m.live < 0.3 {
    "full"
  } else {
    "dense"
  }
  let shape = if m.clumping < 2.0 {
    "even"
  } else if m.clumping < 5.0 {
    "patchy"
  } else {
    "clumped"
  }
  "\{speed} \{density} \{shape}"
}

///|
const NICHES : Int = 60

///|
/// MAP-Elites style search: start from rules of every family, then
/// repeatedly mutate or cross an elite and keep the child if it beats the
/// elite of its own niche.
fn niche_search(opts : Options, rng : @rule.Rng) -> Array[Candidate] {
  let cfg = @rule.default_config
  let archive : Array[Candidate?] = Array::make(NICHES, None)
  let offer = fn(r : @rule.Rule) {
    let (q, m) = @rule.evaluate_quality(r, cfg, rng)
    if q <= 0.0 {
      return
    }
    let k = niche_of(m)
    match archive[k] {
      Some(old) if old.score >= q => ()
      _ => archive[k] = Some({ rule: r, score: q, metrics: m })
    }
  }
  for k in 0..<opts.random {
    offer(@rule.Rule::family(rng, k))
    if opts.verbose && k % 500 == 0 {
      println(
        "seed \{k} filled \{archive.filter(fn(c) { c is Some(_) }).length()}",
      )
    }
  }
  for k in 0..<opts.evals {
    let filled : Array[Candidate] = []
    for c in archive {
      if c is Some(x) {
        filled.push(x)
      }
    }
    if filled.length() == 0 {
      break
    }
    let parent = filled[rng.int(filled.length())]
    let child = if rng.double() < 0.25 {
      parent.rule.cross(filled[rng.int(filled.length())].rule, rng)
    } else {
      parent.rule.mutate(rng, 1 + rng.int(10))
    }
    offer(child)
    if opts.verbose && k % 500 == 0 {
      println("eval \{k} filled \{filled.length()}")
    }
  }
  let out : Array[Candidate] = []
  for c in archive {
    if c is Some(x) {
      out.push(x)
    }
  }
  sort_desc(out)
  out
}
