-- Importador de las guías de leveo de Polestar (GPL-3.0) a datos de Siguiente.
-- Se ejecuta con tools/importar-polestar.js, que carga antes las guías, textos y nombres de Polestar
-- en GUIDES, RETIRED, TEXTS (esMX) y NAMES (esMX), y luego lee OUT_GUIAS y OUT_NOMBRES.

local KEEP_STEP = { title = true, note = true, only = true, when = true, label = true }
local KEEP_GOAL = {
    t = true, quest = true, oi = true, npc = true, object = true, item = true, map = true, x = true, y = true,
    r = true, count = true, optional = true, text = true, note = true, area = true, location = true, node = true,
    level = true, spell = true, target = true, title = true, npcName = true, itemName = true, objName = true,
    class = true, zone = true, group = true, only = true, startItem = true, escort = true,
}

local used = { quest = {}, npc = {}, item = {}, object = {}, taxi = {}, spell = {}, instance = {} }
local english = {}

local function noteTokens(s)
    if type(s) ~= "string" then return end
    for kind, id in s:gmatch("{(%a+):(%d+)}") do
        id = tonumber(id)
        if used[kind] then used[kind][id] = true end
    end
end

local function tr(guideId, s)
    if type(s) ~= "string" then return s end
    local g = TEXTS[guideId]
    local out = (g and g[s]) or s
    noteTokens(out)
    return out
end

-- Serializador compacto de tablas Lua
local function ser(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
    if t == "number" then
        if v == math.floor(v) then return tostring(math.floor(v)) end
        return string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
    end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = ser(v[i]) end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. ser(k) .. "]")
        parts[#parts + 1] = key .. "=" .. ser(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function copyOnly(src, keep)
    local o = {}
    for k, v in pairs(src) do if keep[k] then o[k] = v end end
    return o
end

local out, count, stepsN = {}, 0, 0
local order = {}
for _, g in ipairs(GUIDES) do
    if g.category == "Leveling" and not RETIRED[g.id] then
        count = count + 1
        local steps = {}
        for _, s in ipairs(g.steps or {}) do
            stepsN = stepsN + 1
            local ns_ = copyOnly(s, KEEP_STEP)
            ns_.title = tr(g.id, s.title)
            ns_.note = tr(g.id, s.note)
            ns_.goals = {}
            for _, goal in ipairs(s.goals or {}) do
                local ng = copyOnly(goal, KEEP_GOAL)
                ng.text = tr(g.id, goal.text)
                ng.note = tr(g.id, goal.note)
                if goal.quest then used.quest[goal.quest] = true end
                if goal.npc then used.npc[goal.npc] = true end
                if goal.item then used.item[goal.item] = true end
                if goal.object then used.object[goal.object] = true end
                if goal.node then used.taxi[goal.node] = true end
                ns_.goals[#ns_.goals + 1] = ng
            end
            steps[#steps + 1] = ns_
        end
        noteTokens(g.title)
        for key, name in pairs(g.names or {}) do english[key] = name end
        local entry = {
            id = g.id, title = g.title, zone = g.zone, zoneName = g.zoneName, faction = g.faction, races = g.races,
            minLevel = g.minLevel, maxLevel = g.maxLevel, factionLevels = g.factionLevels,
            next = g.next, nextChoices = g.nextChoices, steps = steps,
        }
        order[#order + 1] = g.id
        out[#out + 1] = "G[" .. string.format("%q", g.id) .. "]=" .. ser(entry)
    end
end
table.sort(order)

OUT_GUIAS = table.concat({
    "-- Rutas de leveo de Polestar (https://github.com/fitzforge/polestar), GPL-3.0-only.",
    "-- Importadas con tools/importar-polestar.js desde Polestar " .. tostring(POLESTAR_VERSION) .. ". No editar a mano.",
    "-- Créditos y licencias de los datos: Guias/LICENSE-DATA.txt y CREDITOS.md.",
    "local _, ns = ...",
    "ns.GUIAS = ns.GUIAS or {}",
    "local G = ns.GUIAS",
    table.concat(out, "\n"),
    "",
}, "\n")

-- Nombres: en español (esMX) los que hay; si no, el inglés de la guía.
local nombres = {}
for kind, ids in pairs(used) do
    nombres[kind] = {}
    for id in pairs(ids) do
        local es = NAMES[kind] and NAMES[kind][id]
        local en = english[kind .. ":" .. id]
        if es or en then nombres[kind][id] = es or en end
    end
end
OUT_NOMBRES = table.concat({
    "-- Nombres del juego en español (esMX) que usan las rutas. Los nombres son de Blizzard Entertainment.",
    "-- Fuentes (vía Polestar, GPL-3.0): tablas del cliente, DingDB (GPL-3.0), pfQuest (MIT). Ver Guias/LICENSE-DATA.txt.",
    "local _, ns = ...",
    "ns.NOMBRES = " .. ser(nombres),
    "",
}, "\n")

SUMMARY = string.format("%d guías de leveo, %d pasos", count, stepsN)
