// Draws every tile straight from the cell buffer: a full-screen triangle whose
// fragment shader maps each pixel to (tile, cell).

struct View {
  w: u32,
  h: u32,
  n: u32,
  cols: u32,
  cell_px: u32,
  gap: u32,
  hover: i32,
  _pad: u32,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var<storage, read> cells: array<u32>;

@vertex
fn vert_main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
  let p = array<vec2<f32>, 3>(vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
  return vec4<f32>(p[i], 0.0, 1.0);
}

const BACKGROUND = vec3<f32>(0.06, 0.06, 0.08);
const EMPTY = vec3<f32>(0.0, 0.0, 0.0);
const STATE1 = vec3<f32>(0.98, 0.62, 0.22);
const STATE2 = vec3<f32>(0.30, 0.78, 0.95);

@fragment
fn frag_main(@builtin(position) pos: vec4<f32>) -> @location(0) vec4<f32> {
  let px = u32(pos.x);
  let py = u32(pos.y);
  let tile_w = view.w * view.cell_px;
  let tile_h = view.h * view.cell_px;
  let span_x = tile_w + view.gap;
  let span_y = tile_h + view.gap;
  let col = px / span_x;
  let row = py / span_y;
  let lx = px % span_x;
  let ly = py % span_y;
  let tile = row * view.cols + col;
  if col >= view.cols || lx >= tile_w || ly >= tile_h || tile >= view.n {
    return vec4<f32>(BACKGROUND, 1.0);
  }
  let cx = lx / view.cell_px;
  let cy = ly / view.cell_px;
  let s = cells[tile * view.w * view.h + cy * view.w + cx];
  var c = EMPTY;
  if s == 1u {
    c = STATE1;
  } else if s == 2u {
    c = STATE2;
  }
  if i32(tile) == view.hover && s == 0u {
    c = vec3<f32>(0.04, 0.04, 0.05);
  }
  return vec4<f32>(c, 1.0);
}
