// Merges rule files from `yarn search` into one gallery list:
//   node scripts/merge-rules.mjs --per-kind 4 web/rules.json niches.json > merged.json
// Rules closer than 40 table entries to an earlier one are dropped, each kind
// keeps at most `--per-kind` rules (best score first), and the output is
// ordered by kind so similar behaviors sit together. Rules without a `kind`
// get one from their metrics, with the same bins as `niche_label` in
// src/search/niches.mbt.
import { readFileSync } from "node:fs";

const decode = (hex) => {
  const t = [];
  for (let k = 0; k < hex.length / 2; k++) {
    let v = Number.parseInt(hex.slice(2 * k, 2 * k + 2), 16);
    for (let i = 0; i < 5; i++) {
      t.push(v % 3);
      v = Math.floor(v / 3);
    }
  }
  return t;
};
const distance = (a, b) => a.reduce((n, v, i) => n + (v !== b[i] ? 1 : 0), 0);
const kindOf = (r) => {
  const speed = r.churn < 0.02 ? "slow" : r.churn < 0.06 ? "calm" : r.churn < 0.15 ? "busy" : r.churn < 0.35 ? "fast" : "frantic";
  const density = r.live < 0.06 ? "sparse" : r.live < 0.15 ? "light" : r.live < 0.3 ? "full" : "dense";
  const shape = r.clumping < 2 ? "even" : r.clumping < 5 ? "patchy" : "clumped";
  return `${speed} ${density} ${shape}`;
};

const args = process.argv.slice(2);
let perKind = Infinity;
const paths = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--per-kind") perKind = Number.parseInt(args[++i]);
  else paths.push(args[i]);
}
const files = paths.map((f) => JSON.parse(readFileSync(f, "utf8")));
const all = files.flatMap((f) => f.rules.map((r) => ({ ...r, kind: r.kind ?? kindOf(r) })));
all.sort((a, b) => b.score - a.score);
const kept = [];
const perKindCount = new Map();
for (const rule of all) {
  const table = decode(rule.hex);
  if (kept.some((k) => distance(k.table, table) < 40)) continue;
  const n = perKindCount.get(rule.kind) ?? 0;
  if (n >= perKind) continue;
  perKindCount.set(rule.kind, n + 1);
  kept.push({ table, rule });
}
const order = (words) => (kind) => words.indexOf(kind.split(" ")[words.length === 5 ? 0 : words.length === 4 ? 1 : 2]);
const bySpeed = order(["slow", "calm", "busy", "fast", "frantic"]);
const byDensity = order(["sparse", "light", "full", "dense"]);
const byShape = order(["even", "patchy", "clumped"]);
kept.sort(
  (a, b) =>
    bySpeed(a.rule.kind) - bySpeed(b.rule.kind) ||
    byDensity(a.rule.kind) - byDensity(b.rule.kind) ||
    byShape(a.rule.kind) - byShape(b.rule.kind) ||
    b.rule.score - a.rule.score
);
process.stdout.write(
  JSON.stringify({ encoding: files[0].encoding, rules: kept.map((k) => k.rule) }, null, 2) + "\n"
);
