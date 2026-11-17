// Siguiente (GPL-3.0). Compara cada objetivo de Guias/Guias.lua con las posiciones de QuestieDB para Forever.
// Uso: node tools/auditar-coords.js Guias/Guias.lua questie.json "<AddOns>/QuestieDB/support/Forever/Zones/areaIdToUiMapId.lua" sospechosos.json
// Revisa cada sospechoso a mano y apunta los errores reales en Guias/Correcciones.lua.
const fs = require("fs");
const [, , guias, qj, areaFile, out] = process.argv;
const db = JSON.parse(fs.readFileSync(qj, "utf8"));
const area2map = {};
for (const m of fs.readFileSync(areaFile, "utf8").matchAll(/\[(\d+)\]\s*=\s*(\d+)/g)) if (!(m[1] in area2map) || +m[2]) area2map[m[1]] = +m[2];
const pts = (spawns, map) => { const r = []; if (!spawns) return r; for (const [z, l] of Object.entries(spawns)) if (area2map[z] === map) for (const c of l) r.push(c); return r; };
const npcPts = (ids, map) => ids.flatMap(id => pts(db.npc[id], map));
const objPts = (ids, map) => ids.flatMap(id => pts(db.obj[id], map));
const itemPts = (ids, map) => ids.flatMap(id => { const it = db.item[id]; return it ? [...npcPts(it.n, map), ...objPts(it.o, map)] : []; });

const G = fs.readFileSync(guias, "utf8");
const goals = [];
for (const gm of G.matchAll(/\nG\["([^"]+)"\]=/g)) {
  const start = gm.index + 1, end = G.indexOf('\nG["', start + 5);
  const body = G.slice(start, end > 0 ? end : undefined);
  let stepNo = 0; const re = /\{goals=|\{([^{}]*?\bmap=(\d+)[^{}]*?)\}/g; let m;
  while ((m = re.exec(body))) {
    if (m[0] === "{goals=") { stepNo++; continue; }
    const s = m[1], g = { guide: gm[1], step: stepNo, map: +m[2] };
    for (const k of ["quest", "x", "y", "npc", "item", "oi"]) { const r = s.match(new RegExp("\\b" + k + "=(-?[\\d.]+)")); if (r) g[k] = +r[1]; }
    for (const k of ["t", "title", "npcName", "itemName"]) { const r = s.match(new RegExp("\\b" + k + '="([^"]*)"')); if (r) g[k] = r[1]; }
    if (g.x != null) goals.push(g);
  }
}
const res = { checked: 0, nodata: 0, flagged: [] };
for (const g of goals) {
  const q = g.quest && db.quest[g.quest];
  let cand = [], kind;
  if (g.npc) { cand = npcPts([g.npc], g.map); kind = "npc"; }
  else if (q && g.t === "accept") { cand = [...npcPts(q.sn, g.map), ...objPts(q.so, g.map)]; kind = "start"; }
  else if (q && g.t === "turnin") { cand = [...npcPts(q.fn, g.map), ...objPts(q.fo, g.map)]; kind = "end"; }
  else if (q && g.t === "kill") { cand = [...npcPts(q.on, g.map), ...pts(q.te, g.map)]; kind = "mobs"; }
  else if (g.t === "collect" && (g.item || q)) { cand = [...itemPts(g.item ? [g.item] : q.oi, g.map), ...(q ? pts(q.te, g.map) : [])]; kind = "drops"; }
  else if (q) { cand = [...pts(q.te, g.map), ...npcPts(q.on, g.map), ...objPts(q.oo, g.map), ...itemPts(q.oi, g.map)]; kind = "objective"; }
  else if (g.item) { cand = itemPts([g.item], g.map); kind = "drops"; }
  if (!cand.length) { res.nodata++; continue; }
  res.checked++;
  let best = null;
  for (const c of cand) { const d = Math.hypot(c[0] - g.x, (c[1] - g.y) * 0.66); if (!best || d < best.d) best = { d, c }; }
  const lim = (kind === "mobs" || kind === "drops") ? 5 : 2;
  if (best.d > lim) {
    // centroid of the candidate cluster nearest to the best point (for multi-spawn mobs)
    const near = cand.filter(c => Math.hypot(c[0] - best.c[0], (c[1] - best.c[1]) * 0.66) < 6);
    const cx = near.reduce((a, c) => a + c[0], 0) / near.length, cy = near.reduce((a, c) => a + c[1], 0) / near.length;
    res.flagged.push({ ...g, kind, off: +best.d.toFixed(1), nearest: best.c, centroid: [+cx.toFixed(2), +cy.toFixed(2)], n: cand.length });
  }
}
res.flagged.sort((a, b) => b.off - a.off);
fs.writeFileSync(out, JSON.stringify(res, null, 1));
console.log(`goals ${goals.length}, checked ${res.checked}, no questie data ${res.nodata}, flagged ${res.flagged.length}`);
const byKind = {}; for (const f of res.flagged) byKind[f.kind] = (byKind[f.kind] || 0) + 1; console.log(byKind);
for (const f of res.flagged.slice(0, 60)) console.log(`${f.off.toString().padStart(5)}  ${f.guide} #${f.step} ${f.t} ${f.kind} q${f.quest || ""} ${f.npcName || f.itemName || f.title || ""} map${f.map} ${f.x},${f.y} -> ${f.nearest.join(",")} (n${f.n})`);
