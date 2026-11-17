// Siguiente (GPL-3.0). Extrae los datos de QuestieDB para Forever (CBOR en base64 dentro del .toc) a un JSON compacto.
// Uso: node tools/questie-a-json.js "<AddOns>/QuestieDB" questie.json
const fs = require("fs"), path = require("path");
const [, , dir, out] = process.argv;

function cbor(buf) {
  let p = 0;
  function len(ai) {
    if (ai < 24) return ai;
    if (ai === 24) return buf[p++];
    if (ai === 25) { const v = buf.readUInt16BE(p); p += 2; return v; }
    if (ai === 26) { const v = buf.readUInt32BE(p); p += 4; return v; }
    if (ai === 27) { const v = Number(buf.readBigUInt64BE(p)); p += 8; return v; }
    if (ai === 31) return -1;
    throw new Error("bad ai " + ai);
  }
  function item() {
    const b = buf[p++], mt = b >> 5, ai = b & 31;
    switch (mt) {
      case 0: return len(ai);
      case 1: return -1 - len(ai);
      case 2: case 3: { const n = len(ai); const s = buf.slice(p, p + n); p += n; return mt === 3 ? s.toString("utf8") : s.toString("latin1"); }
      case 4: { const n = len(ai); const a = []; if (n < 0) { while (buf[p] !== 0xff) a.push(item()); p++; } else for (let i = 0; i < n; i++) a.push(item()); return a; }
      case 5: { const n = len(ai); const o = {}; if (n < 0) { while (buf[p] !== 0xff) { const k = item(); o[k] = item(); } p++; } else for (let i = 0; i < n; i++) { const k = item(); o[k] = item(); } return o; }
      case 6: len(ai); return item();
      case 7:
        if (ai === 20) return false; if (ai === 21) return true; if (ai === 22 || ai === 23) return null;
        if (ai === 25) { const h = buf.readUInt16BE(p); p += 2; const s = h & 0x8000 ? -1 : 1, e = (h >> 10) & 31, f = h & 1023;
          return e === 0 ? s * f * 2 ** -24 : e === 31 ? (f ? NaN : s * Infinity) : s * (1 + f / 1024) * 2 ** (e - 15); }
        if (ai === 26) { const v = buf.readFloatBE(p); p += 4; return v; }
        if (ai === 27) { const v = buf.readDoubleBE(p); p += 8; return v; }
        throw new Error("bad simple " + ai);
    }
  }
  return item();
}
// Lua arrays decode as CBOR arrays; Lua sparse tables as maps. Normalize map-with-int-keys too.
const raw = new Map();
for (const ln of fs.readFileSync(path.join(dir, "QuestieDB_Forever.toc"), "utf8").split(/\r?\n/)) {
  const m = ln.match(/^## X-(Npc|Object|Quest|Item)-(\d+)-(\d+)(?:-(\d+))?: (.*)$/);
  if (!m) continue;
  const key = `${m[1]}-${m[2]}-${m[3]}`;
  if (m[4]) { const r = raw.get(key) || { parts: [] }; r.parts[+m[4]] = m[5]; raw.set(key, r); }
  else if (/^~\d+~$/.test(m[5])) { const r = raw.get(key) || { parts: [] }; raw.set(key, r); }
  else raw.set(key, m[5]);
}
const dec = (kind, id, f) => { let v = raw.get(`${kind}-${id}-${f}`); if (v == null) return null;
  if (typeof v !== "string") v = v.parts.slice(1).join("");
  try { return cbor(Buffer.from(v, "base64")); } catch (e) { return null; } };
const ids = kind => { const s = new Set(); for (const k of raw.keys()) { const [a, b] = k.split("-"); if (a === kind) s.add(+b); } return [...s]; };
const at = (o, i) => o == null ? null : Array.isArray(o) ? o[i - 1] : o[i];
const vals = o => o == null ? [] : Array.isArray(o) ? o : Object.values(o);
const spawnsOf = o => { const r = {}; if (!o) return r; for (const [z, list] of Object.entries(o)) r[z] = vals(list).map(c => [vals(c)[0], vals(c)[1]]).filter(c => typeof c[0] === "number" && c[0] >= 0); return r; };

const db = { npc: {}, obj: {}, quest: {}, item: {} };
for (const id of ids("Npc")) { const s = spawnsOf(dec("Npc", id, 7)); const w = dec("Npc", id, 8);
  if (w) for (const [z, paths] of Object.entries(w)) for (const p of vals(paths)) { s[z] = s[z] || []; for (const c of vals(p)) { const v = vals(c); if (typeof v[0] === "number" && v[0] >= 0) s[z].push([v[0], v[1]]); } }
  if (Object.keys(s).length) db.npc[id] = s; }
for (const id of ids("Object")) { const s = spawnsOf(dec("Object", id, 4)); if (Object.keys(s).length) db.obj[id] = s; }
for (const id of ids("Item")) { const n = vals(dec("Item", id, 2)), o = vals(dec("Item", id, 3)); if (n.length || o.length) db.item[id] = { n, o }; }
for (const id of ids("Quest")) {
  const st = dec("Quest", id, 2), fi = dec("Quest", id, 3), te = dec("Quest", id, 9), ob = dec("Quest", id, 10);
  const ids2 = (x) => vals(x).map(e => Array.isArray(e) ? e[0] : (e && typeof e === "object" ? vals(e)[0] : e)).filter(n => typeof n === "number");
  const q = { sn: vals(at(st, 1)), so: vals(at(st, 2)), fn: vals(at(fi, 1)), fo: vals(at(fi, 2)),
    on: ids2(at(ob, 1)), oo: ids2(at(ob, 2)), oi: ids2(at(ob, 3)) };
  if (te) q.te = spawnsOf(at(te, 2));
  db.quest[id] = q;
}
fs.writeFileSync(out, JSON.stringify(db));
console.log("npc", Object.keys(db.npc).length, "obj", Object.keys(db.obj).length, "quest", Object.keys(db.quest).length, "item", Object.keys(db.item).length);
console.log("q760", JSON.stringify(db.quest[760]), "npc2948", JSON.stringify(db.npc[2948]));
