// Importa las rutas de leveo de Polestar instalado a Siguiente.
// Uso: node tools/importar-polestar.js "<carpeta AddOns de WoW Forever>"
// Requiere fengari (npm install en tools/). Genera Guias/Guias.lua y Guias/Nombres.lua,
// y copia los avisos de licencia de los datos (LICENSE-DATA.txt).
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const ADDONS = process.argv[2] || "A:/World of Warcraft/_forever_/Interface/AddOns";
const ROOT = path.join(__dirname, "..");
const OUT = path.join(ROOT, "Guias");
const LOCALE = "esMX";

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name)) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(name + ": " + lua.lua_tojsstring(L, -1));
  }
}
function getString(name) {
  lua.lua_getglobal(L, to_luastring(name));
  const s = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  return s;
}

const version = (fs.readFileSync(path.join(ADDONS, "Polestar/Polestar.toc"), "utf8").match(/^## Version:\s*(.+)$/m) || [])[1];

// Polestar falso: solo lo que los archivos de datos llaman
run(`
GUIDES, RETIRED, TEXTS, NAMES = {}, {}, {}, {}
POLESTAR_VERSION = ${JSON.stringify(version || "?")}
local function decode(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
Polestar = {
  RegisterGuide = function(g) GUIDES[#GUIDES + 1] = g end,
  RegisterPack = function() end,
  RegisterExperimental = function() end,
  RetireGuides = function(_, ids) for _, id in ipairs(ids) do RETIRED[id] = true end end,
  RegisterGuideTexts = function(loc, pack, t)
    if loc ~= "${LOCALE}" then return end
    for id, map in pairs(t.guides or {}) do TEXTS[id] = map end
  end,
  Names = { AddChunk = function(loc, kind, lo, hi, text)
    if loc ~= "${LOCALE}" then return end
    NAMES[kind] = NAMES[kind] or {}
    for id, name in text:gmatch("(%d+)\\t([^\\n]*)") do NAMES[kind][tonumber(id)] = decode(name) end
  end },
}
Polestar.L = setmetatable({}, { __newindex = function() end })
function GetLocale() return "${LOCALE}" end
`, "polestar-falso");

for (const f of ["Polestar_Guides/Guides.lua", "Polestar_Guides_Horde/Guides.lua", "Polestar_Guides_Alliance/Guides.lua",
                 `Polestar_${LOCALE}/Texts.lua`, `Polestar_${LOCALE}/Names.lua`]) {
  run(fs.readFileSync(path.join(ADDONS, f), "utf8"), f);
}
run(fs.readFileSync(path.join(__dirname, "importar.lua"), "utf8"), "importar.lua");

fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, "Guias.lua"), getString("OUT_GUIAS"));
fs.writeFileSync(path.join(OUT, "Nombres.lua"), getString("OUT_NOMBRES"));
const notices = ["Polestar_Guides/LICENSE-DATA.txt", `Polestar_${LOCALE}/LICENSE-DATA.txt`]
  .map(f => "==== " + f + " ====\n" + fs.readFileSync(path.join(ADDONS, f), "utf8")).join("\n\n");
fs.writeFileSync(path.join(OUT, "LICENSE-DATA.txt"), notices);
console.log("Polestar " + version + ": " + getString("SUMMARY"));
for (const f of ["Guias.lua", "Nombres.lua"]) console.log("  " + f + ": " + Math.round(fs.statSync(path.join(OUT, f)).size / 1024) + " KB");
