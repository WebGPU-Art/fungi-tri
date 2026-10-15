import computeWgsl from "./shaders/compute.wgsl?raw";
import renderWgsl from "./shaders/render.wgsl?raw";
import rulesJson from "./rules.json";

const ENTRIES = 675;
const ENCODED_HEX = 270;

interface RuleInfo {
  hex: string;
  kind?: string;
  score: number;
  live: number;
  churn: number;
  balance: number;
  structure: number;
  period: number;
}

const rules: RuleInfo[] = (rulesJson as { rules: RuleInfo[] }).rules;

/** Same packing as `Rule::from_hex` in src/rule/rule.mbt: 5 trits per byte. */
export function decodeRule(hex: string): Uint32Array | null {
  if (hex.length !== ENCODED_HEX || !/^[0-9a-fA-F]+$/.test(hex)) return null;
  const table = new Uint32Array(ENTRIES);
  for (let k = 0; k < ENCODED_HEX / 2; k++) {
    let v = Number.parseInt(hex.slice(2 * k, 2 * k + 2), 16);
    if (v >= 243) return null;
    for (let i = 0; i < 5; i++) {
      table[k * 5 + i] = v % 3;
      v = Math.floor(v / 3);
    }
  }
  table[0] = 0;
  return table;
}

const params = new URLSearchParams(location.search);
const numParam = (key: string, fallback: number) => {
  const v = Number.parseFloat(params.get(key) ?? "");
  return Number.isFinite(v) ? v : fallback;
};

type SeedMode = "soup" | "patch" | "disk";
const SEED_MODES: SeedMode[] = ["soup", "patch", "disk"];
const SEED_NAMES: Record<SeedMode, string> = {
  soup: "random soup",
  patch: "random patch",
  disk: "symmetric disk",
};

/**
 * Starting states, matching the search in src/rule/sim.mbt:
 * soup fills the whole grid at random (live with probability `fill`),
 * patch is a random disk in an empty grid, disk is a disk of 1 around a disk of 2.
 */
function seedCells(cells: Uint32Array, offset: number, w: number, h: number, radius: number, fill: number, mode: SeedMode) {
  const cx = w / 2;
  const cy = h / 2;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const dx = x + 0.5 - cx;
      const dy = y + 0.5 - cy;
      const d2 = dx * dx + dy * dy;
      let s = 0;
      if (mode === "soup") {
        if (Math.random() < fill) s = 1 + Math.floor(Math.random() * 2);
      } else if (mode === "patch") {
        if (d2 < radius * radius) s = Math.floor(Math.random() * 3);
      } else if (d2 < radius * radius * 0.25) s = 2;
      else if (d2 < radius * radius) s = 1;
      cells[offset + y * w + x] = s;
    }
  }
}

interface Layout {
  /** rule tables to play, one tile each */
  tables: Uint32Array[];
  /** labels shown on hover, parallel to tables */
  labels: string[];
  w: number;
  h: number;
  cols: number;
  cellPx: number;
  gap: number;
  canvasW: number;
  canvasH: number;
  radius: number;
}

function pickLayout(): Layout {
  const radius = numParam("radius", 16);
  const ruleParam = params.get("rule");
  const indexParam = params.get("index");
  let single: { table: Uint32Array; label: string } | null = null;
  if (ruleParam) {
    const table = decodeRule(ruleParam);
    if (table) single = { table, label: "custom rule" };
    else console.warn("invalid rule in url, showing the gallery");
  } else if (indexParam !== null) {
    const i = Number.parseInt(indexParam);
    const info = rules[i];
    if (info) single = { table: decodeRule(info.hex)!, label: `#${i}  ${info.kind ?? ""}` };
  }

  if (single) {
    const cellPx = Math.max(1, 2 ** numParam("grid", 2));
    const w = Math.floor(window.innerWidth / cellPx);
    const h = Math.floor(window.innerHeight / cellPx);
    return {
      tables: [single.table],
      labels: [single.label],
      w,
      h,
      cols: 1,
      cellPx,
      gap: 0,
      canvasW: w * cellPx,
      canvasH: h * cellPx,
      radius,
    };
  }

  // gallery: every curated rule on a 96x96 torus, the size used for scoring
  const size = numParam("size", 96);
  const cellPx = numParam("cell", 2);
  // the gap under each tile holds its caption
  const gap = 26;
  const tileSpan = size * cellPx + gap;
  const cols = Math.max(1, Math.floor((window.innerWidth - gap) / tileSpan));
  const rows = Math.ceil(rules.length / cols);
  return {
    tables: rules.map((r) => decodeRule(r.hex)!),
    labels: rules.map(
      (r, i) =>
        `#${i}  ${r.kind ?? ""}  live ${r.live.toFixed(2)}  churn ${r.churn.toFixed(3)}  structure ${r.structure.toFixed(2)}`
    ),
    w: size,
    h: size,
    cols,
    cellPx,
    gap,
    canvasW: cols * tileSpan - gap,
    canvasH: rows * tileSpan - gap,
    radius,
  };
}

async function main() {
  const info = document.querySelector(".info") as HTMLElement;
  if (!navigator.gpu) {
    info.textContent = "This page needs WebGPU (try a recent Chrome).";
    return;
  }
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    info.textContent = "No WebGPU adapter available.";
    return;
  }
  const device = await adapter.requestDevice();
  const layout = pickLayout();
  const n = layout.tables.length;
  const cellCount = layout.w * layout.h * n;

  const canvas = document.querySelector("canvas") as HTMLCanvasElement;
  canvas.width = layout.canvasW;
  canvas.height = layout.canvasH;
  canvas.style.width = `${layout.canvasW}px`;
  canvas.style.height = `${layout.canvasH}px`;
  const isGallery = !params.has("rule") && !params.has("index");
  if (isGallery) {
    // captions sit in the gap under each tile, over the canvas
    const board = canvas.parentElement as HTMLElement;
    board.style.width = `${layout.canvasW}px`;
    const spanX = layout.w * layout.cellPx + layout.gap;
    const spanY = layout.h * layout.cellPx + layout.gap;
    rules.forEach((r, i) => {
      const caption = document.createElement("div");
      caption.className = "caption";
      caption.textContent = `#${i}  ${r.kind ?? ""}`;
      caption.style.left = `${(i % layout.cols) * spanX}px`;
      caption.style.top = `${Math.floor(i / layout.cols) * spanY + layout.h * layout.cellPx}px`;
      caption.style.width = `${layout.w * layout.cellPx}px`;
      board.appendChild(caption);
    });
  }
  const context = canvas.getContext("webgpu") as GPUCanvasContext;
  const format = navigator.gpu.getPreferredCanvasFormat();
  context.configure({ device, format, alphaMode: "opaque" });

  const dims = device.createBuffer({ size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  device.queue.writeBuffer(dims, 0, new Uint32Array([layout.w, layout.h, n, 0]));

  const viewData = new Int32Array([layout.w, layout.h, n, layout.cols, layout.cellPx, layout.gap, -1, 0]);
  const viewBuf = device.createBuffer({ size: 32, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  device.queue.writeBuffer(viewBuf, 0, viewData);

  const ruleData = new Uint32Array(n * ENTRIES);
  layout.tables.forEach((t, i) => ruleData.set(t, i * ENTRIES));
  const ruleBuf = device.createBuffer({ size: ruleData.byteLength, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
  device.queue.writeBuffer(ruleBuf, 0, ruleData);

  const cellBufs = [0, 1].map(() =>
    device.createBuffer({ size: cellCount * 4, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST })
  );

  const fill = numParam("fill", 0.4);
  let seedMode: SeedMode = SEED_MODES.find((m) => m === params.get("seed")) ?? "soup";
  let current = 0;
  let generation = 0;
  const reset = () => {
    const cells = new Uint32Array(cellCount);
    for (let i = 0; i < n; i++) {
      seedCells(cells, i * layout.w * layout.h, layout.w, layout.h, layout.radius, fill, seedMode);
    }
    device.queue.writeBuffer(cellBufs[0], 0, cells);
    current = 0;
    generation = 0;
  };
  reset();

  const computePipeline = device.createComputePipeline({
    layout: "auto",
    compute: { module: device.createShaderModule({ code: computeWgsl }), entryPoint: "main" },
  });
  const renderModule = device.createShaderModule({ code: renderWgsl });
  const renderPipeline = device.createRenderPipeline({
    layout: "auto",
    vertex: { module: renderModule, entryPoint: "vert_main" },
    fragment: { module: renderModule, entryPoint: "frag_main", targets: [{ format }] },
    primitive: { topology: "triangle-list" },
  });

  const computeGroups = [0, 1].map((i) =>
    device.createBindGroup({
      layout: computePipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: dims } },
        { binding: 1, resource: { buffer: cellBufs[i] } },
        { binding: 2, resource: { buffer: cellBufs[1 - i] } },
        { binding: 3, resource: { buffer: ruleBuf } },
      ],
    })
  );
  const renderGroups = [0, 1].map((i) =>
    device.createBindGroup({
      layout: renderPipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: viewBuf } },
        { binding: 1, resource: { buffer: cellBufs[i] } },
      ],
    })
  );

  // `slow`: frames per generation, `speed`: generations per frame
  const slow = Math.max(1, numParam("slow", 2));
  const speed = Math.max(1, numParam("speed", 1));
  let paused = false;
  let frame = 0;
  // `skip`: generations to run before the first frame
  let pending = Math.max(0, numParam("skip", 0));

  const frameLoop = () => {
    frame++;
    const encoder = device.createCommandEncoder();
    const runSteps = pending > 0 ? pending : !paused && frame % slow === 0 ? speed : 0;
    pending = 0;
    {
      for (let s = 0; s < runSteps; s++) {
        const pass = encoder.beginComputePass();
        pass.setPipeline(computePipeline);
        pass.setBindGroup(0, computeGroups[current]);
        pass.dispatchWorkgroups(Math.ceil(layout.w / 8), Math.ceil(layout.h / 8), n);
        pass.end();
        current = 1 - current;
        generation++;
      }
    }
    const pass = encoder.beginRenderPass({
      colorAttachments: [
        { view: context.getCurrentTexture().createView(), loadOp: "clear", storeOp: "store", clearValue: [0, 0, 0, 1] },
      ],
    });
    pass.setPipeline(renderPipeline);
    pass.setBindGroup(0, renderGroups[current]);
    pass.draw(3);
    pass.end();
    device.queue.submit([encoder.finish()]);
    requestAnimationFrame(frameLoop);
  };
  requestAnimationFrame(frameLoop);

  const hint = isGallery
    ? "Click a tile to open it. Space pause, R new random start, N change start."
    : "Space pause, R new random start, N change start, Esc back to gallery.";
  let lastLabel = "";
  const showInfo = (label: string) => {
    lastLabel = label;
    info.textContent = `${label}\nstart: ${SEED_NAMES[seedMode]}\n${hint}`;
  };
  showInfo(isGallery ? `${n} rules` : layout.labels[0]);

  const tileAt = (e: MouseEvent): number => {
    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const spanX = layout.w * layout.cellPx + layout.gap;
    const spanY = layout.h * layout.cellPx + layout.gap;
    const col = Math.floor(x / spanX);
    const row = Math.floor(y / spanY);
    if (col >= layout.cols || x % spanX >= spanX - layout.gap || y % spanY >= spanY - layout.gap) return -1;
    const tile = row * layout.cols + col;
    return tile < n ? tile : -1;
  };

  if (isGallery) {
    canvas.addEventListener("mousemove", (e) => {
      const tile = tileAt(e);
      if (tile !== viewData[6]) {
        viewData[6] = tile;
        device.queue.writeBuffer(viewBuf, 0, viewData);
        showInfo(tile >= 0 ? layout.labels[tile] : `${n} rules`);
      }
    });
    canvas.addEventListener("click", (e) => {
      const tile = tileAt(e);
      if (tile >= 0) location.search = `?index=${tile}`;
    });
  }

  window.addEventListener("keydown", (e) => {
    if (e.key === " ") {
      paused = !paused;
      e.preventDefault();
    } else if (e.key === "r") {
      reset();
    } else if (e.key === "n") {
      seedMode = SEED_MODES[(SEED_MODES.indexOf(seedMode) + 1) % SEED_MODES.length];
      reset();
      showInfo(lastLabel);
    } else if (e.key === "Escape" && !isGallery) {
      location.search = "";
    }
  });

  // exposed for debugging in the console
  (window as any).fungiTri = { rules, layout, generation: () => generation };
}

main();
