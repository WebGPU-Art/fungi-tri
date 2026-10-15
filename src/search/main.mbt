///|
/// Rule search. Prints the curated rules as JSON on stdout:
///
/// ```
/// moon run src/search --target native -- --seed 7 > web/rules.json
/// ```
///
/// Options: `--seed N` (default 1), `--random N` random candidates (default
/// 4000), `--gens N` evolution rounds (default 30), `--keep N` rules in the
/// output (default 64), `--verbose` progress lines on stdout.
///
/// `--niches` switches to the niche search (see `niche_search`): `--random N`
/// starting rules, then `--evals N` (default 8000) mutations, keeping the best
/// rule per behavior niche instead of the best rules overall.
struct Options {
  mut seed : Int
  mut random : Int
  mut gens : Int
  mut keep : Int
  mut verbose : Bool
  mut niches : Bool
  mut evals : Int
}

///|
fn parse_options() -> Options {
  let opts = {
    seed: 1,
    random: 4000,
    gens: 30,
    keep: 64,
    verbose: false,
    niches: false,
    evals: 8000,
  }
  let args = @env.args()
  let mut i = 0
  while i < args.length() {
    let next_int = fn(fallback : Int) -> Int {
      if i + 1 < args.length() {
        @string.parse_int(args[i + 1]) catch {
          _ => fallback
        }
      } else {
        fallback
      }
    }
    match args[i] {
      "--seed" => opts.seed = next_int(opts.seed)
      "--random" => opts.random = next_int(opts.random)
      "--gens" => opts.gens = next_int(opts.gens)
      "--keep" => opts.keep = next_int(opts.keep)
      "--verbose" => opts.verbose = true
      "--niches" => opts.niches = true
      "--evals" => opts.evals = next_int(opts.evals)
      _ => ()
    }
    i += 1
  }
  opts
}

///|
struct Candidate {
  rule : @rule.Rule
  score : Double
  metrics : @rule.Metrics
}

///|
fn sort_desc(xs : Array[Candidate]) -> Unit {
  xs.sort_by(fn(a, b) { b.score.compare(a.score) })
}

///|
/// Picks the best candidates while keeping chosen rules at least
/// `min_distance` table entries apart, so the set is not one rule repeated.
fn diverse_top(
  xs : Array[Candidate],
  keep : Int,
  min_distance : Int,
) -> Array[Candidate] {
  let out : Array[Candidate] = []
  for c in xs {
    if out.length() >= keep || c.score <= 0.0 {
      break
    }
    if out.iter().all(fn(o) { o.rule.distance(c.rule) >= min_distance }) {
      out.push(c)
    }
  }
  out
}

///|
fn top_search(opts : Options, rng : @rule.Rng) -> Array[Candidate] {
  let cfg = @rule.default_config
  let pool : Array[Candidate] = []
  let consider = fn(r : @rule.Rule) {
    let (score, metrics) = @rule.evaluate(r, cfg, rng)
    pool.push({ rule: r, score, metrics })
  }
  // phase 1: random rules over a range of densities and state mixes
  for k in 0..<opts.random {
    let lambda = 0.1 + 0.45 * rng.double()
    let bias = 0.2 + 0.6 * rng.double()
    consider(@rule.Rule::random(rng, lambda, bias))
    if opts.verbose && k % 500 == 0 {
      println("random \{k}")
    }
  }
  sort_desc(pool)
  // phase 2: evolve a diverse elite with mutation and crossover
  // the elite has to be larger than the output to leave room for diversity
  let elite_size = opts.keep + opts.keep / 4
  for g in 0..<opts.gens {
    let elite = diverse_top(pool, elite_size, 40)
    let children : Array[@rule.Rule] = []
    for c in elite {
      children.push(c.rule.mutate(rng, 1 + rng.int(12)))
      children.push(c.rule.mutate(rng, 1 + rng.int(4)))
      let other = elite[rng.int(elite.length())]
      children.push(c.rule.cross(other.rule, rng))
    }
    pool.clear()
    for c in elite {
      pool.push(c)
    }
    for r in children {
      consider(r)
    }
    sort_desc(pool)
    if opts.verbose {
      println("gen \{g} best \{pool[0].score}")
    }
  }
  diverse_top(pool, opts.keep, 60)
}

///|
fn main {
  let opts = parse_options()
  let rng = @rule.Rng::new(opts.seed.to_uint64() * 0x2545F4914F6CDD1DUL + 1UL)
  let chosen = if opts.niches {
    diverse_top(niche_search(opts, rng), opts.keep, 60)
  } else {
    top_search(opts, rng)
  }
  let rules : Array[Json] = chosen.map(fn(c) {
    let m = c.metrics
    {
      "hex": c.rule.to_hex().to_json(),
      "kind": niche_label(m).to_json(),
      "score": c.score.to_json(),
      "live": m.live.to_json(),
      "churn": m.churn.to_json(),
      "balance": m.balance.to_json(),
      "structure": m.structure.to_json(),
      "cohesion": m.cohesion.to_json(),
      "clumping": m.clumping.to_json(),
      "period": m.period.to_json(),
    }
  })
  let out : Json = {
    "encoding": "fungi-tri/v1: 675 trits (center*225 + pair(orth1,orth2)*15 + pair(diag1,diag2)), 5 trits per byte little-endian, hex".to_json(),
    "seed": opts.seed.to_json(),
    "rules": Json::array(rules),
  }
  println(out.stringify(indent=2))
}
