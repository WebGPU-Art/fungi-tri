# Fungi Tri

A 3-state sibling of [Fungi Collection](https://github.com/WebGPU-Art/fungi-collection): a MoonBit program searches for cellular automata rules that grow into interesting, long-lived patterns, and a WebGPU compute shader plays the curated rules side by side.

### Rule space

Fungi rules map every 3×3 pattern of black/white cells to the next state, a table of 2^9 = 512 bits. With 3 states the same idea needs 3^9 = 19683 entries, and random tables that large are almost always noise. Fungi Tri keeps the table small and isotropic instead. The next state depends on:

- the center cell (0, 1 or 2),
- how many of the 4 orthogonal neighbors are 1 and how many are 2 (15 combinations),
- how many of the 4 diagonal neighbors are 1 and how many are 2 (15 combinations).

That gives 3 × 15 × 15 = 675 entries, each a trit. Entry 0 (empty cell, empty neighborhood) is forced to 0 so the background stays still. A rule is written as 270 hex characters: 5 trits per byte, little-endian (`src/rule/rule.mbt`, `decodeRule` in `web/main.ts`).

### Search and scoring

`src/search` samples random rules over a range of densities, then evolves a diverse elite with mutation and crossover. Each rule runs for 300 steps on a 96×96 torus from three random starts: a dense random soup (40% live), a sparse one (15% live) and a random patch in an empty grid. The score (`src/rule/score.mbt`) is the mean over those starts, halved if the rule dies in any of them. Each run multiplies:

- activity: cells changing per step near 4%, so neither frozen nor boiling,
- density: live fraction near a third,
- structure: mutual information between neighboring cells, which is near zero for noise,
- cohesion: live cells have live neighbors, so not just dust,
- clumping: live cells gather into blobs, domains and fronts instead of an even gas (block-count variance against a random grid),
- mix: both states 1 and 2 survive,
- spread (patch start only): the pattern grows beyond the patch,
- a penalty for still lifes and short cycles, and zero for rules that die.

The final set keeps rules at least 60 table entries apart.

That search converges on one kind of behavior, so there is a second mode, `--niches`, in the spirit of MAP-Elites: rules are binned by how they behave from a dense soup (how fast cells change, how full the grid is, how clumped the live cells are) and the best rule of every bin is kept. It starts from rules of several families (`src/rule/families.mbt`), each with some random noise mixed in:

- random and outer-totalistic tables,
- excitable media (waves and spirals),
- cyclic rock-paper-scissors rules,
- two Life-like species sharing a grid,
- predator and prey,
- voting rules.

`scripts/merge-rules.mjs` merges several search outputs into one gallery, capping the number of rules per kind and ordering them by kind.

```bash
yarn search --seed 7 > web/rules.json            # default: 4000 random + 30 generations, keeps 64
yarn search --niches --seed 11 --keep 60 > niches-11.json
node scripts/merge-rules.mjs --per-kind 4 web/rules.json niches-11.json > merged.json
```

### Renderer

```bash
yarn
yarn dev
```

The gallery plays every rule in `web/rules.json` on its own 96×96 torus, starting from a fresh random soup. All tiles advance in one compute dispatch (workgroup z selects the rule), and one full-screen fragment pass draws them straight from the cell buffer. Click a tile to open it full screen.

URL parameters: `?index=3` opens a curated rule, `?rule=<hex>` any rule, `grid=2` cell size as a power of two (single view), `cell=2` cell pixels and `size=96` grid size (gallery), `radius=16` patch radius, `fill=0.4` soup density, `slow=2` frames per step, `speed=1` steps per frame, `skip=300` steps to run before the first frame, `seed=soup|patch|disk` starting state. Keys: Space pause, R new random start, N cycle the starting state, Esc back to the gallery.

### Workflow

Same deploy as Fungi Collection: CI checks and tests the MoonBit code, runs a tiny search, builds with Vite and rsyncs `dist/` on pushes to `main`.

### License

Apache License 2.0
