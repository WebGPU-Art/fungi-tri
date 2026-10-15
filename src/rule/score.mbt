///|
/// What a simulation run looked like at the end, and how interesting it is.
pub struct Metrics {
  /// fraction of the grid that is non-zero at the end
  live : Double
  /// mean fraction of cells changing per step over the final window
  churn : Double
  /// share of the rarer of states 1 and 2 among live cells, in [0, 0.5]
  balance : Double
  /// mutual information of neighboring cells inside the active region,
  /// normalized by the cell entropy: ~0 for noise, high for structure
  structure : Double
  /// fraction of the grid ever non-zero during the run
  coverage : Double
  /// mean number of live neighbors (of 8) around live cells: low for dust
  /// and gliders, high for solid growth
  cohesion : Double
  /// variance of live counts over 8x8 blocks relative to a random grid of
  /// the same density: ~1 for gas, large for clumps, domains and fronts
  clumping : Double
  /// smallest period found at the end (1 = still), 0 when none was found
  period : Int
  score : Double
  /// like `score` but without preferring a particular activity or density,
  /// used by the niche search where those are the niche coordinates
  quality : Double
} derive(Debug, ToJson)

///|
pub(all) struct ScoreConfig {
  size : Int
  steps : Int
  window : Int
  radius : Double
}

///|
pub let default_config : ScoreConfig = {
  size: 96,
  steps: 300,
  window: 100,
  radius: 16.0,
}

///|
fn hash_cells(g : Grid) -> UInt64 {
  let mut h = 0xcbf29ce484222325UL
  for v in g.cells {
    h = (h ^ v.to_uint64()) * 0x100000001b3UL
  }
  h
}

///|
fn bell(x : Double, center : Double, width : Double) -> Double {
  let d = (x - center) / width
  @math.exp(-d * d)
}

///|
fn clamp01(x : Double) -> Double {
  if x < 0.0 {
    0.0
  } else if x > 1.0 {
    1.0
  } else {
    x
  }
}

///|
/// Normalized mutual information between each cell and its right and lower
/// neighbor, counting only pairs inside `mask`.
fn structure_of(g : Grid, mask : FixedArray[Bool]) -> Double {
  let joint = FixedArray::make(9, 0.0)
  let mut total = 0.0
  for y in 0..<g.h {
    for x in 0..<g.w {
      let i = y * g.w + x
      let a = g.cells[i]
      let right = y * g.w + (x + 1) % g.w
      let down = (y + 1) % g.h * g.w + x
      if mask[i] && mask[right] {
        joint[a * 3 + g.cells[right]] += 1.0
        joint[g.cells[right] * 3 + a] += 1.0
        total += 2.0
      }
      if mask[i] && mask[down] {
        joint[a * 3 + g.cells[down]] += 1.0
        joint[g.cells[down] * 3 + a] += 1.0
        total += 2.0
      }
    }
  }
  if total < 50.0 {
    return 0.0
  }
  let p = FixedArray::make(3, 0.0)
  for a in 0..<3 {
    for b in 0..<3 {
      joint[a * 3 + b] = joint[a * 3 + b] / total
      p[a] += joint[a * 3 + b]
    }
  }
  let mut entropy = 0.0
  for a in 0..<3 {
    if p[a] > 0.0 {
      entropy -= p[a] * @math.ln(p[a])
    }
  }
  if entropy < 1.0e-6 {
    return 0.0
  }
  let mut mi = 0.0
  for a in 0..<3 {
    for b in 0..<3 {
      let pab = joint[a * 3 + b]
      if pab > 0.0 {
        mi += pab * @math.ln(pab / (p[a] * p[b]))
      }
    }
  }
  mi / entropy
}

///|
fn clumping_of(g : Grid) -> Double {
  let b = 8
  let bw = g.w / b
  let bh = g.h / b
  let counts = FixedArray::make(bw * bh, 0.0)
  for y in 0..<(bh * b) {
    for x in 0..<(bw * b) {
      if g.cells[y * g.w + x] != 0 {
        counts[y / b * bw + x / b] += 1.0
      }
    }
  }
  let k = (bw * bh).to_double()
  let mut mean = 0.0
  for c in counts {
    mean += c
  }
  mean = mean / k
  let cells = (b * b).to_double()
  let p = mean / cells
  let expected = cells * p * (1.0 - p)
  if expected < 1.0e-6 {
    return 0.0
  }
  let mut v = 0.0
  for c in counts {
    v += (c - mean) * (c - mean)
  }
  v / k / expected
}

///|
fn cohesion_of(g : Grid) -> Double {
  let mut live = 0
  let mut neighbors = 0
  for y in 0..<g.h {
    for x in 0..<g.w {
      if g.cells[y * g.w + x] != 0 {
        live += 1
        for dy in -1..<=1 {
          for dx in -1..<=1 {
            let nx = (x + dx + g.w) % g.w
            let ny = (y + dy + g.h) % g.h
            if (dx != 0 || dy != 0) && g.cells[ny * g.w + nx] != 0 {
              neighbors += 1
            }
          }
        }
      }
    }
  }
  if live == 0 {
    0.0
  } else {
    neighbors.to_double() / live.to_double()
  }
}

///|
/// Runs `rule` from the given starting grid and measures the result.
///
/// `spread_target` is the coverage needed for full credit; pass 0 for starts
/// that already fill the grid.
pub fn run_metrics(
  rule : Rule,
  start : Grid,
  cfg : ScoreConfig,
  spread_target? : Double = 0.0,
) -> Metrics {
  let n = start.w * start.h
  let nd = n.to_double()
  let mut a = start
  let mut b = Grid::new(start.w, start.h)
  let ever = FixedArray::make(n, false)
  let recent = FixedArray::make(n, false)
  let history : Array[UInt64] = []
  let mut churn = 0.0
  for t in 0..<cfg.steps {
    let changed = step(rule, a, b)
    let tmp = a
    a = b
    b = tmp
    let in_window = t >= cfg.steps - cfg.window
    let mut alive = 0
    for i in 0..<n {
      if a.cells[i] != 0 {
        alive += 1
        ever[i] = true
        if in_window {
          recent[i] = true
        }
      }
    }
    if in_window {
      churn += changed.to_double() / nd
      history.push(hash_cells(a))
    }
    if alive == 0 {
      break
    }
  }
  churn = churn / cfg.window.to_double()
  let mut n1 = 0
  let mut n2 = 0
  let mut covered = 0
  for i in 0..<n {
    match a.cells[i] {
      1 => n1 += 1
      2 => n2 += 1
      _ => ()
    }
    if ever[i] {
      covered += 1
    }
  }
  let live_count = n1 + n2
  let live = live_count.to_double() / nd
  let balance = if live_count == 0 {
    0.0
  } else {
    (if n1 < n2 { n1 } else { n2 }).to_double() / live_count.to_double()
  }
  let mut period = 0
  let last = history.length() - 1
  for p in 1..<=16 {
    if period == 0 && last - p >= 0 && history[last] == history[last - p] {
      period = p
    }
  }
  let structure = structure_of(a, recent)
  let coverage = covered.to_double() / nd
  let cohesion = cohesion_of(a)
  let clumping = clumping_of(a)
  let quality = if live_count == 0 ||
    churn < 0.003 ||
    churn > 0.7 ||
    live > 0.85 {
    0.0
  } else {
    let period_factor = match period {
      0 => 1.0
      1 | 2 => 0.05
      _ => 0.35
    }
    let spread = if spread_target > 0.0 {
      clamp01(coverage / spread_target)
    } else {
      1.0
    }
    period_factor *
    clamp01(structure / 0.2) *
    clamp01(balance / 0.15) *
    spread *
    (0.3 + 0.7 * clamp01((cohesion - 1.0) / 2.0)) *
    (0.4 + 0.6 * clamp01((clumping - 1.0) / 4.0))
  }
  let score = if live_count == 0 {
    0.0
  } else {
    let period_factor = match period {
      0 => 1.0
      1 | 2 => 0.05
      _ => 0.35
    }
    let activity = bell(@math.ln(churn + 1.0e-6), @math.ln(0.04), 1.3)
    let density = bell(live, 0.32, 0.2)
    let solid = clamp01((cohesion - 1.0) / 2.0)
    let clumps = 0.2 + 0.8 * clamp01((clumping - 1.0) / 4.0)
    let shape = clamp01(structure / 0.2)
    let mix = clamp01(balance / 0.2)
    let spread = if spread_target > 0.0 {
      clamp01(coverage / spread_target)
    } else {
      1.0
    }
    period_factor * activity * density * shape * mix * spread * solid * clumps
  }
  {
    live,
    churn,
    balance,
    structure,
    coverage,
    cohesion,
    clumping,
    period,
    score,
    quality,
  }
}

///|
/// Scores a rule over several random starts, so the curated rules do not
/// depend on one particular seed:
///
/// - a sparse random soup over the whole grid,
/// - a dense random soup,
/// - a random patch in the middle of an empty grid, which has to spread.
///
/// The score is the mean of the three, halved when the rule dies in any of
/// them. Returns the metrics of the dense soup, the default start in the
/// renderer.
pub fn evaluate(rule : Rule, cfg : ScoreConfig, rng : Rng) -> (Double, Metrics) {
  let g = Grid::new(cfg.size, cfg.size)
  g.seed_soup(0.4, rng)
  let dense = run_metrics(rule, g, cfg)
  if dense.score < 0.01 {
    return (0.0, dense)
  }
  g.seed_soup(0.15, rng)
  let sparse = run_metrics(rule, g, cfg)
  g.seed_noise(cfg.radius, rng)
  let patch = run_metrics(rule, g, cfg, spread_target=0.3)
  let mean = (dense.score + sparse.score + patch.score) / 3.0
  let died = sparse.live == 0.0 || patch.live == 0.0
  (if died { mean * 0.5 } else { mean }, dense)
}

///|
/// Same starts as `evaluate`, averaging `quality` instead of `score`.
pub fn evaluate_quality(
  rule : Rule,
  cfg : ScoreConfig,
  rng : Rng,
) -> (Double, Metrics) {
  let g = Grid::new(cfg.size, cfg.size)
  g.seed_soup(0.4, rng)
  let dense = run_metrics(rule, g, cfg)
  if dense.quality < 0.01 {
    return (0.0, dense)
  }
  g.seed_soup(0.15, rng)
  let sparse = run_metrics(rule, g, cfg)
  g.seed_noise(cfg.radius, rng)
  let patch = run_metrics(rule, g, cfg, spread_target=0.3)
  let mean = (dense.quality + sparse.quality + patch.quality) / 3.0
  let died = sparse.live == 0.0 || patch.live == 0.0
  (if died { mean * 0.5 } else { mean }, dense)
}
