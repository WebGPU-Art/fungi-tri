// One invocation per cell; z selects which rule/grid (tile) is updated, so
// every rule in the gallery advances in a single dispatch.

struct Dims {
  w: u32,
  h: u32,
  n: u32,
  _pad: u32,
}

@group(0) @binding(0) var<uniform> dims: Dims;
@group(0) @binding(1) var<storage, read> current: array<u32>;
@group(0) @binding(2) var<storage, read_write> next: array<u32>;
// n rules, 675 entries each: center * 225 + pair(orth) * 15 + pair(diag)
@group(0) @binding(3) var<storage, read> rules: array<u32>;

// weight of a neighbor state in the count key `a + 5 * b`
var<private> WEIGHT: array<u32, 3> = array<u32, 3>(0u, 1u, 5u);

// `a + 5 * b` -> index of the pair (a, b) with a + b <= 4
var<private> PAIR: array<u32, 25> = array<u32, 25>(
  0u, 5u, 9u, 12u, 14u,
  1u, 6u, 10u, 13u, 0u,
  2u, 7u, 11u, 0u, 0u,
  3u, 8u, 0u, 0u, 0u,
  4u, 0u, 0u, 0u, 0u,
);

fn cell(base: u32, x: u32, y: u32) -> u32 {
  return WEIGHT[current[base + y * dims.w + x]];
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let w = dims.w;
  let h = dims.h;
  if id.x >= w || id.y >= h || id.z >= dims.n {
    return;
  }
  let base = id.z * w * h;
  let x = id.x;
  let y = id.y;
  let l = (x + w - 1u) % w;
  let r = (x + 1u) % w;
  let u = (y + h - 1u) % h;
  let d = (y + 1u) % h;

  let orth = cell(base, x, u) + cell(base, x, d) + cell(base, l, y) + cell(base, r, y);
  let diag = cell(base, l, u) + cell(base, r, u) + cell(base, l, d) + cell(base, r, d);
  let center = current[base + y * w + x];
  let idx = center * 225u + PAIR[orth] * 15u + PAIR[diag];
  next[base + y * w + x] = rules[id.z * 675u + idx];
}
