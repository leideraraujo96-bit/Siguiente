-- Ruta: guía paso a paso (aceptar, hacer, entregar) armada con los datos de Questie.
-- Se recalcula sola cuando aceptas, entregas, abandonas, subes de nivel o aparecen misiones nuevas.

local _, ns = ...

local Route = {
    enabled = true,
    steps = {},        -- { kind = "accept"|"do"|"turnin", qid, title, level, loc, num, done }
    known = {},        -- misiones del diario que la ruta ya tuvo en cuenta (incluidas las que descartó)
    ignored = {},      -- [qid] = hasta cuándo saltarla
    turnedIn = {},     -- [qid] = true al entregarla en esta sesión
    status = nil,
    dirty = true,
    dirtyAt = 0,
    lastPlan = 0,
    availSet = {},
}
ns.Route = Route

local MAX_STEPS = 50       -- pasos que se planean por adelantado
local MAX_DIST = 3000      -- yardas: hasta dónde buscar misiones nuevas para aceptar
local PINS_ON_MAP = 50     -- pasos numerados en el mapa del mundo
local PINS_ON_MINIMAP = 3  -- pasos en el minimapa

local KIND_TEXT = { accept = "Acepta", ["do"] = "Haz", turnin = "Entrega", travel = "Viaja" }
local KIND_HEX = { accept = "ffd100", ["do"] = "ff8040", turnin = "40ff40", travel = "80c0ff" }
local KIND_RGB = { accept = { 1, 0.82, 0 }, ["do"] = { 1, 0.5, 0.15 }, turnin = { 0.3, 1, 0.3 }, travel = { 0.45, 0.75, 1 } }

---------------------------------------------------------------------------
-- Acceso a Questie (solo lectura)
---------------------------------------------------------------------------
local Q
local function GetQ()
    if Q then return Q end
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local HBD = ns.QuestieHBD()
    local Pins = ns.QuestieHBDPins()
    if not (HBD and Pins) then return nil end
    local q = {
        HBD = HBD,
        Pins = Pins,
        DB = QuestieLoader:ImportModule("QuestieDB"),
        Available = QuestieLoader:ImportModule("AvailableQuests"),
        ZoneDB = QuestieLoader:ImportModule("ZoneDB"),
        XP = QuestieLoader:ImportModule("QuestXP"),
    }
    if not (q.DB.GetQuest and q.DB.GetNPC and q.DB.GetObject and q.Available.__availableQuests
        and q.ZoneDB.GetUiMapIdByAreaId) then
        return nil
    end
    Q = q
    return q
end

local function Ignored(qid)
    return Route.ignored[qid] and Route.ignored[qid] > GetTime()
end

local function IsDone(qid)
    if Route.turnedIn[qid] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(qid) and true or false
    elseif IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(qid) and true or false
    end
    return false
end

local function XPOf(qid)
    if not (Q.XP and Q.XP.GetQuestLogRewardXP) then return 0 end
    local ok, xp = pcall(Q.XP.GetQuestLogRewardXP, Q.XP, qid, false)
    return ok and tonumber(xp) or 0
end

local function SnapshotAvailable()
    local set = {}
    for qid in pairs(Q.Available.__availableQuests) do set[qid] = true end
    return set
end

-- ¿Apareció alguna misión disponible que no estaba cuando se planeó? (cadenas, subir de nivel)
local function NewAvailable()
    for qid in pairs(Q.Available.__availableQuests) do
        if not Route.availSet[qid] then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Lugares: dónde se acepta, dónde se hace y dónde se entrega cada misión
---------------------------------------------------------------------------
local placeCache = {}

-- Mapa de un área de Questie; si es una subzona sin mapa propio, probamos con su zona padre.
local function AreaMap(areaId)
    local ok, uiMap = pcall(Q.ZoneDB.GetUiMapIdByAreaId, Q.ZoneDB, areaId)
    if ok and uiMap then return uiMap end
    if Q.ZoneDB.GetParentZoneId then
        local ok2, parent = pcall(Q.ZoneDB.GetParentZoneId, Q.ZoneDB, areaId)
        if ok2 and parent and parent ~= areaId then
            local ok3, m = pcall(Q.ZoneDB.GetUiMapIdByAreaId, Q.ZoneDB, parent)
            if ok3 then return m end
        end
    end
    return nil
end

local function AddSpawns(out, spawns, name)
    for areaId, list in pairs(spawns or {}) do
        local uiMap = type(list) == "table" and AreaMap(areaId)
        if uiMap then
            for _, c in ipairs(list) do
                if type(c) == "table" and c[1] and c[2] and c[1] >= 0 and c[2] >= 0 then
                    local wx, wy, inst = Q.HBD:GetWorldCoordinatesFromZone(c[1] / 100, c[2] / 100, uiMap)
                    if wx then
                        out[#out + 1] = { uiMap = uiMap, x = c[1], y = c[2], wx = wx, wy = wy, inst = inst, name = name }
                    end
                end
            end
        end
    end
end

local function AddNPCs(out, ids, friendlyOnly)
    local before = #out
    for _, id in pairs(ids or {}) do
        local npc = Q.DB:GetNPC(id)
        if npc and npc.spawns and (not friendlyOnly or npc.friendly) then
            AddSpawns(out, npc.spawns, npc.name)
        end
    end
    -- Si ninguno quedó por el filtro de "amistoso" (datos incompletos), los aceptamos igual.
    if friendlyOnly and #out == before then
        for _, id in pairs(ids or {}) do
            local npc = Q.DB:GetNPC(id)
            if npc and npc.spawns then AddSpawns(out, npc.spawns, npc.name) end
        end
    end
end

local function AddObjects(out, ids)
    for _, id in pairs(ids or {}) do
        local obj = Q.DB:GetObject(id)
        if obj and obj.spawns then AddSpawns(out, obj.spawns, obj.name) end
    end
end

local function Places(qid, part)
    local cache = placeCache[qid]
    if not cache then
        cache = {}
        placeCache[qid] = cache
    end
    if cache[part] then return cache[part] end

    local out = {}
    local ok, quest = pcall(Q.DB.GetQuest, qid)
    if ok and quest then
        pcall(function()
            if part == "start" then
                AddNPCs(out, quest.Starts and quest.Starts.NPC, true)
                AddObjects(out, quest.Starts and quest.Starts.GameObject)
            elseif part == "finish" then
                AddNPCs(out, quest.Finisher and quest.Finisher.NPC, true)
                AddObjects(out, quest.Finisher and quest.Finisher.GameObject)
            else
                for _, od in ipairs(quest.ObjectiveData or {}) do
                    if od.Type == "monster" then
                        AddNPCs(out, { od.Id })
                    elseif od.Type == "object" then
                        AddObjects(out, { od.Id })
                    elseif od.Type == "killcredit" then
                        AddNPCs(out, od.IdList)
                    elseif od.Type == "item" then
                        local item = Q.DB:GetItem(od.Id)
                        for _, src in ipairs(item and item.Sources or {}) do
                            if not src.Vendor then
                                if src.Type == "monster" then
                                    AddNPCs(out, { src.Id })
                                elseif src.Type == "object" then
                                    AddObjects(out, { src.Id })
                                end
                            end
                        end
                    end
                end
                if type(quest.triggerEnd) == "table" and type(quest.triggerEnd[2]) == "table" then
                    AddSpawns(out, quest.triggerEnd[2], quest.triggerEnd[1])
                end
            end
        end)
    end
    cache[part] = out
    return out
end

local function Nearest(cands, x, y, inst)
    local best, bestD
    for _, c in ipairs(cands) do
        local d = (c.inst == inst) and ((c.wx - x) ^ 2 + (c.wy - y) ^ 2) or math.huge
        if not bestD or d < bestD then best, bestD = c, d end
    end
    if not best then return nil, math.huge end
    return best, (bestD == math.huge) and math.huge or math.sqrt(bestD)
end

local function QuestCheck(name, qid)
    local fn = Q.DB[name]
    if not fn then return false end
    local ok, yes = pcall(fn, qid)
    return ok and yes and true or false
end

-- ¿Vale la pena aceptar esta misión? Depende de las opciones (grupo, mazmorras, naranjas).
local function WorthAccepting(qid, quest, level, opt)
    if quest.IsRepeatable then return false end
    if not ((quest.Starts and (quest.Starts.NPC or quest.Starts.GameObject))) then return false end
    local d = ns.Difficulty(quest.level or 0, level)
    if d == "gris" or d == "rojo" then return false end
    if d == "naranja" and not opt.allowOrange then return false end
    if QuestCheck("IsRaidQuest", qid) or QuestCheck("IsPvPQuest", qid) then return false end
    if QuestCheck("IsDungeonQuest", qid) and not opt.allowDungeon then return false end
    if QuestCheck("IsGroupQuest", qid) and not opt.allowGroup then return false end
    return true
end

---------------------------------------------------------------------------
-- Viajes: zonas, maestros de vuelo, barcos y zepelines
---------------------------------------------------------------------------
local QUEST_SECONDS = 240   -- tiempo medio de una misión yendo solo (aceptar, hacer, entregar)
local DOCK_SECONDS = 240    -- esperar y hacer el viaje en barco o zepelín
local FLY_SPEED = 30        -- yardas por segundo en un vuelo (aprox.)

local function RunSpeed(level)
    -- caminando ~7 yd/s; con montura (nivel 40) ~ +60%
    return (level >= 40) and 11 or 7
end

-- Barcos y zepelines (coordenadas aproximadas de los muelles). Se pueden tomar en los dos sentidos.
-- f: "A" Alianza, "H" Horda, "N" para todos.
local TRANSPORTS = {
    { f = "A", kind = "barco", a = { 1437, 4.6, 57.2, "Puerto de Menethil" }, b = { 1439, 32.4, 43.8, "Auberdine" } },
    { f = "A", kind = "barco", a = { 1437, 5.0, 63.4, "Puerto de Menethil" }, b = { 1445, 71.6, 56.4, "Theramore" } },
    { f = "H", kind = "zepelín", a = { 1411, 50.8, 13.8, "la torre de zepelines de Orgrimmar" }, b = { 1420, 60.7, 58.8, "la torre de zepelines de Entrañas" } },
    { f = "H", kind = "zepelín", a = { 1411, 50.6, 12.6, "la torre de zepelines de Orgrimmar" }, b = { 1434, 31.6, 29.1, "Grom'gol" } },
    { f = "H", kind = "zepelín", a = { 1420, 61.9, 59.0, "la torre de zepelines de Entrañas" }, b = { 1434, 31.6, 29.1, "Grom'gol" } },
    { f = "N", kind = "barco", a = { 1434, 25.9, 73.1, "Bahía del Botín" }, b = { 1413, 63.7, 38.6, "Trinquete" } },
}

local function Spot(def)
    local wx, wy, inst = Q.HBD:GetWorldCoordinatesFromZone(def[2] / 100, def[3] / 100, def[1])
    if not wx then return nil end
    return { uiMap = def[1], x = def[2], y = def[3], wx = wx, wy = wy, inst = inst, name = def[4] }
end

local function Dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- Mejor barco/zepelín para ir de un continente a otro: devuelve muelle de salida, de llegada y el transporte.
local function BestDock(fx, fy, finst, target)
    local faction = UnitFactionGroup("player") == "Alliance" and "A" or "H"
    local best, bestCost
    for _, t in ipairs(TRANSPORTS) do
        if t.f == "N" or t.f == faction then
            for _, dir in ipairs({ { t.a, t.b }, { t.b, t.a } }) do
                local from, to = Spot(dir[1]), Spot(dir[2])
                if from and to and from.inst == finst and to.inst == target.inst then
                    local cost = Dist(fx, fy, from.wx, from.wy) + Dist(to.wx, to.wy, target.wx, target.wy)
                    if not bestCost or cost < bestCost then
                        best, bestCost = { from = from, to = to, kind = t.kind }, cost
                    end
                end
            end
        end
    end
    return best
end

-- Segundos aproximados para llegar de un punto a otro (caminando, o en barco si cambia el continente).
local function TravelSeconds(fx, fy, finst, target, speed)
    if finst == target.inst then
        return Dist(fx, fy, target.wx, target.wy) / speed
    end
    local dock = BestDock(fx, fy, finst, target)
    if not dock then return nil end
    return (Dist(fx, fy, dock.from.wx, dock.from.wy) + Dist(dock.to.wx, dock.to.wy, target.wx, target.wy)) / speed
        + DOCK_SECONDS
end

-- Maestros de vuelo amistosos (de la lista de Questie), con su lugar.
local flightMasters
local function FlightMasters()
    if flightMasters then return flightMasters end
    flightMasters = {}
    local Townsfolk = QuestieLoader:ImportModule("Townsfolk")
    local ids = Townsfolk and Townsfolk.townsfolk and Townsfolk.townsfolk["Flight Master"]
    if type(ids) == "table" and #ids > 0 then
        AddNPCs(flightMasters, ids, true)
    else
        flightMasters = nil -- Questie aún no armó la lista: reintentar luego
        return {}
    end
    return flightMasters
end

-- ¿Conoces un vuelo hacia esta zona? (se aprende al abrir el mapa de vuelo de cualquier maestro)
local function KnownNodeIn(zoneName)
    local db = ns.GetDB()
    if not (db and db.taxi and zoneName) then return nil end
    for node in pairs(db.taxi) do
        if node:find(zoneName, 1, true) then return node end
    end
    return nil
end

-- Zona (uiMapID de tipo zona) a la que pertenece un mapa.
local function ZoneOf(uiMap)
    local id = uiMap
    for _ = 1, 6 do
        local info = id and C_Map.GetMapInfo(id)
        if not info then return uiMap end
        if info.mapType == 3 then return id end
        if info.mapType and info.mapType < 3 then return uiMap end
        id = info.parentMapID
    end
    return uiMap
end

local function PlayerZone()
    local m = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    return m and ZoneOf(m)
end
Route.PlayerZone = PlayerZone

local function MapName(uiMap)
    local info = uiMap and C_Map.GetMapInfo(uiMap)
    return info and info.name or ("zona " .. tostring(uiMap))
end

-- Pasos para llegar a la zona elegida: barco o zepelín si hace falta, vuelo si lo conoces, y llegar.
local function TravelSteps(fx, fy, finst, target, zoneMap, questCount, speed)
    local out = {}
    local zoneName = MapName(zoneMap)
    local ax, ay, ainst = fx, fy, finst

    if finst ~= target.inst then
        local dock = BestDock(fx, fy, finst, target)
        if dock then
            out[#out + 1] = {
                kind = "travel", sub = "dock", toInst = dock.to.inst, zone = zoneMap,
                title = "Toma el " .. dock.kind .. " a " .. dock.to.name,
                detail = "Ve a " .. dock.from.name .. " y sube al " .. dock.kind .. ".",
                loc = dock.from,
            }
            ax, ay, ainst = dock.to.wx, dock.to.wy, dock.to.inst
        else
            out[#out + 1] = {
                kind = "travel", sub = "zone", zone = zoneMap, title = "Viaja a " .. zoneName,
                detail = "Está en otro continente.", loc = target,
            }
            return out
        end
    end

    -- ¿Conviene volar? Solo si conoces un vuelo a esa zona y el camino es largo.
    local walk = Dist(ax, ay, target.wx, target.wy)
    local node = KnownNodeIn(zoneName)
    if node and walk > 1200 then
        local fm, fmDist = Nearest(FlightMasters(), ax, ay, ainst)
        if fm and fmDist < walk * 0.5 then
            out[#out + 1] = {
                kind = "travel", sub = "fly", zone = zoneMap,
                title = "Vuela a " .. node,
                detail = "Habla con " .. (fm.name or "el maestro de vuelo") .. ".",
                loc = fm,
            }
        end
    end

    out[#out + 1] = {
        kind = "travel", sub = "zone", zone = zoneMap,
        title = "Ve a " .. zoneName,
        detail = questCount .. " misiones para tu nivel te esperan ahí.",
        loc = target,
    }
    return out
end

-- ¿La misión te saca de la zona? (objetivo o entrega en otra zona y a más de ~1500 yardas de donde se acepta)
-- Ej.: "Boticaria Zamah" se acepta en El Cruce y se entrega en Cima del Trueno.
local FAR_OTHER_ZONE = 1500
local function LeavesZone(qid, start)
    local zone = ZoneOf(start.uiMap)
    local obj = Nearest(Places(qid, "obj"), start.wx, start.wy, start.inst)
    local from = obj or start
    local fin = Nearest(Places(qid, "finish"), from.wx, from.wy, from.inst)
    for _, p in ipairs({ obj or false, fin or false }) do
        if p then
            if p.inst ~= start.inst then return true end
            if ZoneOf(p.uiMap) ~= zone and Dist(start.wx, start.wy, p.wx, p.wy) > FAR_OTHER_ZONE then
                return true
            end
        end
    end
    return false
end

-- Tiempo estimado de una misión (segundos) para comparar cuáles rinden más.
local function QuestSeconds(qid, sx, sy, sinst, speed)
    local obj = Nearest(Places(qid, "obj"), sx, sy, sinst)
    local ox, oy = sx, sy
    local t = 30
    if obj then
        t = t + Dist(sx, sy, obj.wx, obj.wy) / speed + 150
        ox, oy = obj.wx, obj.wy
    end
    local fin = Nearest(Places(qid, "finish"), ox, oy, sinst)
    if fin then t = t + Dist(ox, oy, fin.wx, fin.wy) / speed end
    return t
end

---------------------------------------------------------------------------
-- Planificar
---------------------------------------------------------------------------
function Route.Current()
    for i, s in ipairs(Route.steps) do
        if not s.done then return s, i end
    end
    return nil
end

function Route.MarkDirty(delay)
    Route.dirty = true
    Route.dirtyAt = GetTime() + (delay or 0)
end

function Route.Plan()
    local db = ns.GetDB()
    if not db then return end
    Route.lastPlan = GetTime()
    Route.dirty = false
    if not GetQ() or not Q.DB.QuestPointers then
        Route.status = "La ruta necesita Questie (cargando...)."
        Route.MarkDirty(3)
        return
    end
    local px, py, pinst = Q.HBD:GetPlayerWorldPosition()
    if not px then
        Route.status = "Sin posición (¿estás en una mazmorra?)."
        Route.MarkDirty(5)
        return
    end

    local level = UnitLevel("player")
    local opt = db.opt or {}
    local speed = RunSpeed(level)
    local maxQ = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
        or MAX_QUESTLOG_QUESTS or 20
    local here = PlayerZone()

    -- 1. Lo que ya tienes en el diario (con el lugar a donde hay que ir y su zona)
    local tasks, inLog = {}, {}
    local logQuests = ns.ReadQuests()
    Route.known = {}
    for _, q in ipairs(logQuests) do
        if q.id then
            inLog[q.id] = true
            Route.known[q.id] = true
            local d = ns.Difficulty(q.level, level)
            -- Mazmorra, élite o banda: fuera de la ruta yendo solo (se activan en opciones para ir en grupo).
            local isGroup = q.group or QuestCheck("IsGroupQuest", q.id)
            local isDungeon = QuestCheck("IsDungeonQuest", q.id)
            local okGroup = (not isGroup or opt.allowGroup) and (not isDungeon or opt.allowDungeon)
                and not QuestCheck("IsRaidQuest", q.id)
            -- Si ya está completa (aunque sea de mazmorra), la entrega sí entra.
            if not Ignored(q.id) and not q.failed and (q.complete or (okGroup and d ~= "rojo")) then
                local stage = (q.complete or #q.objectives == 0) and "turnin" or "do"
                local where = Nearest(Places(q.id, stage == "do" and "obj" or "finish"), px, py, pinst)
                tasks[#tasks + 1] = {
                    qid = q.id, title = q.title, level = q.level, xp = XPOf(q.id),
                    stage = stage, where = where, zone = where and ZoneOf(where.uiMap),
                }
            end
        end
    end
    local logN = #logQuests

    -- 2. Todas las misiones disponibles para ti, en todas las zonas (los "!" de Questie)
    for qid in pairs(Q.Available.__availableQuests) do
        if not inLog[qid] and not Ignored(qid) and not IsDone(qid) then
            local ok, quest = pcall(Q.DB.GetQuest, qid)
            if ok and quest and WorthAccepting(qid, quest, level, opt) then
                local start = Nearest(Places(qid, "start"), px, py, pinst)
                if start and LeavesZone(qid, start) then
                    start = nil -- se hace o se entrega en otra zona lejos: no conviene aceptarla aquí
                end
                if start then
                    local hasObjectives = (quest.ObjectiveData and #quest.ObjectiveData > 0)
                        or type(quest.triggerEnd) == "table"
                    tasks[#tasks + 1] = {
                        qid = qid, title = quest.name or ("Misión " .. qid), level = quest.level or 0,
                        xp = XPOf(qid), stage = "accept", needDo = hasObjectives,
                        where = start, zone = ZoneOf(start.uiMap),
                    }
                end
            end
        end
    end

    -- 3. ¿Qué zona rinde más XP por hora, contando el viaje?
    local zones = {}
    for _, t in ipairs(tasks) do
        if t.where and t.zone then
            local z = zones[t.zone]
            if not z then
                z = { uiMap = t.zone, xp = 0, n = 0, sx = 0, sy = 0, inst = t.where.inst, list = {} }
                zones[t.zone] = z
            end
            if z.inst == t.where.inst then
                z.xp = z.xp + (t.xp or 0)
                z.n = z.n + 1
                z.sx, z.sy = z.sx + t.where.wx, z.sy + t.where.wy
                z.list[#z.list + 1] = t
            end
        end
    end
    local target, bestRate, hereRate
    for map, z in pairs(zones) do
        if z.n > 0 then
            z.wx, z.wy = z.sx / z.n, z.sy / z.n
            -- punto de llegada: la misión de esa zona más cercana al centro
            local arrive = Nearest((function()
                local l = {}
                for _, t in ipairs(z.list) do l[#l + 1] = t.where end
                return l
            end)(), z.wx, z.wy, z.inst)
            z.arrive = arrive
            local travel = (map == here) and 0 or TravelSeconds(px, py, pinst, arrive, speed)
            if travel then
                z.rate = z.xp / (travel + z.n * QUEST_SECONDS)
                if map == here then hereRate = z.rate end
                -- Quedarse en la zona actual tiene ventaja: cambiar solo si otra rinde claramente más.
                local rate = (map == here) and z.rate * 1.3 or z.rate
                if z.n >= 3 or map == here then
                    if not bestRate or rate > bestRate then bestRate, target = rate, z end
                end
            end
        end
    end
    -- Sin viajes automáticos, o si saltaste el viaje: quedarse en la zona actual.
    if opt.autoTravel == false or (Route.stayUntil and Route.stayUntil > GetTime()) then
        if zones[here] then target = zones[here] end
    end

    -- Solo se planean las tareas de la zona elegida. Lo demás se planea al llegar.
    local chosen = {}
    if target then
        local inChosen = {}
        for _, t in ipairs(target.list) do
            chosen[#chosen + 1] = t
            inChosen[t] = true
        end
        -- Misiones del diario de zonas vecinas que quedan cerca (ej.: entregar en la ciudad de al lado).
        local ref = target.arrive or { wx = px, wy = py, inst = pinst }
        for _, t in ipairs(tasks) do
            if not inChosen[t] and t.stage ~= "accept" and t.where and t.where.inst == ref.inst
                and Dist(t.where.wx, t.where.wy, ref.wx, ref.wy) <= 1500 then
                chosen[#chosen + 1] = t
            end
        end
    end

    -- 4. Descartar misiones que rinden poco para el tiempo que toman (XP por segundo muy bajo).
    local rates = {}
    for _, t in ipairs(chosen) do
        if t.stage == "accept" then
            t.rate = (t.xp or 0) / QuestSeconds(t.qid, t.where.wx, t.where.wy, t.where.inst, speed)
            rates[#rates + 1] = t.rate
        end
    end
    if #rates >= 4 then
        table.sort(rates)
        local median = rates[math.floor(#rates / 2) + 1]
        local kept = {}
        for _, t in ipairs(chosen) do
            if t.stage ~= "accept" or t.rate >= median * 0.35 then kept[#kept + 1] = t end
        end
        chosen = kept
    end
    tasks = chosen

    local avgXP = 0
    for _, t in ipairs(tasks) do avgXP = avgXP + (t.xp or 0) end
    avgXP = math.max(1, avgXP / math.max(1, #tasks))

    local steps = {}
    local cx, cy, cinst = px, py, pinst

    -- Pasos seguidos del mismo tipo en el mismo lugar (mismo NPC) comparten número: "Entrega 3 misiones a Thork".
    local function SamePlace(a, b)
        return a and b and a.uiMap == b.uiMap and math.abs(a.x - b.x) < 0.6 and math.abs(a.y - b.y) < 0.6
    end
    local function NextNum(kind, loc)
        local prev = steps[#steps]
        if prev and kind ~= "travel" and prev.kind == kind and SamePlace(prev.loc, loc) then
            return prev.num
        end
        return (prev and prev.num or db.route.done) + 1
    end

    -- 5. Viaje, si la mejor zona no es en la que estás
    if target and target.uiMap ~= here and target.arrive then
        for _, s in ipairs(TravelSteps(px, py, pinst, target.arrive, target.uiMap, target.n, speed)) do
            s.num = NextNum("travel", s.loc)
            s.qid = "viaje:" .. tostring(target.uiMap) .. ":" .. (s.sub or "")
            steps[#steps + 1] = s
        end
        cx, cy, cinst = target.arrive.wx, target.arrive.wy, target.arrive.inst
    end

    local function PlaceFor(t)
        local part = (t.stage == "accept" and "start") or (t.stage == "do" and "obj") or "finish"
        return Nearest(Places(t.qid, part), cx, cy, cinst)
    end

    local function Emit(t, loc)
        steps[#steps + 1] = {
            kind = t.stage, qid = t.qid, title = t.title, level = t.level, loc = loc,
            num = NextNum(t.stage, loc),
        }
        if loc and loc.inst == cinst then cx, cy = loc.wx, loc.wy end
        if t.stage == "accept" then
            logN = logN + 1
            t.stage = t.needDo and "do" or "turnin"
        elseif t.stage == "do" then
            t.stage = "turnin"
        else
            logN = logN - 1
            t.stage = nil
        end
    end

    -- El paso en el que estás se queda primero, para que la flecha no salte.
    local cur = Route.Current()
    if cur then
        for _, t in ipairs(tasks) do
            if t.qid == cur.qid and t.stage == cur.kind then
                Emit(t, (PlaceFor(t)))
                break
            end
        end
    end

    while #steps < MAX_STEPS do
        local best, bestLoc, bestCost
        for _, t in ipairs(tasks) do
            if t.stage and not (t.stage == "accept" and logN >= maxQ) then
                local loc, dist = PlaceFor(t)
                local cost = loc and dist or 1e7
                if cost == math.huge then cost = 1e8 end
                if t.stage == "turnin" then
                    cost = cost * 0.8
                elseif t.stage == "accept" then
                    cost = cost * (1.2 - 0.4 * math.min(1, (t.xp or 0) / avgXP))
                end
                if not bestCost or cost < bestCost then
                    best, bestLoc, bestCost = t, loc, cost
                end
            end
        end
        if not best then break end
        Emit(best, bestLoc)
    end

    Route.steps = steps
    Route.availSet = SnapshotAvailable()
    Route.targetZone = target and target.uiMap
    Route.status = (#steps == 0)
        and "No quedan misiones buenas para tu nivel. Sube matando enemigos de tu nivel (mira los consejos de zona)."
        or nil
    Route.DrawPins()
    if ns.RequestRefresh then ns.RequestRefresh() end
    if ns.ArrowRescan then ns.ArrowRescan() end
end

---------------------------------------------------------------------------
-- Detectar avances
---------------------------------------------------------------------------
function Route.Sync()
    local db = ns.GetDB()
    if not db or not Route.enabled then return end
    -- Con Polestar, la ruta es la suya: la propia descansa (sin números en el mapa).
    if (ns.Guide and ns.Guide.Active()) or (ns.Bridge and ns.Bridge.Active()) then
        if Route.pinsShown then Route.DrawPins() end
        return
    end
    if not GetQ() then
        Route.status = "La ruta necesita Questie activado."
        return
    end

    local inLog, complete = {}, {}
    for _, q in ipairs(ns.ReadQuests()) do
        if q.id then
            inLog[q.id] = true
            complete[q.id] = q.complete
        end
    end

    local changed = false
    local pendingAccept = {}
    local zoneNow = PlayerZone()
    local _, _, instNow = Q.HBD:GetPlayerWorldPosition()
    for _, s in ipairs(Route.steps) do
        if not s.done then
            local done
            if s.kind == "travel" then
                local arrived = zoneNow ~= nil and zoneNow == s.zone
                if s.sub == "dock" then
                    done = arrived or (instNow ~= nil and instNow == s.toInst)
                elseif s.sub == "fly" then
                    done = arrived or (UnitOnTaxi and UnitOnTaxi("player"))
                else
                    done = arrived
                end
            elseif s.kind == "accept" then
                done = inLog[s.qid] or IsDone(s.qid)
            elseif s.kind == "do" then
                done = complete[s.qid] or IsDone(s.qid)
            else
                done = IsDone(s.qid)
            end
            if done then
                s.done = true
                changed = true
            elseif s.kind == "accept" then
                pendingAccept[s.qid] = true
            elseif s.kind ~= "travel" and not inLog[s.qid] and not pendingAccept[s.qid] then
                Route.MarkDirty(0) -- la abandonaste
            end
        end
    end

    -- Un paso (grupo con el mismo número) cuenta como hecho cuando se completó todo lo que incluye.
    if changed then
        local all = {}
        for _, s in ipairs(Route.steps) do
            if all[s.num] == nil then all[s.num] = true end
            if not s.done then all[s.num] = false end
        end
        for _, s in ipairs(Route.steps) do
            if all[s.num] and not s.counted then
                db.route.done = db.route.done + 1
                for _, o in ipairs(Route.steps) do
                    if o.num == s.num then o.counted = true end
                end
            end
        end
    end

    -- Aceptaste algo que la ruta no conocía
    local inRoute = {}
    for _, s in ipairs(Route.steps) do inRoute[s.qid] = true end
    for qid in pairs(inLog) do
        if not Route.known[qid] and not inRoute[qid] then
            Route.known[qid] = true
            Route.MarkDirty(0)
        end
    end

    -- Aparecieron o desaparecieron misiones disponibles (cadenas, subir de nivel)
    if Q.DB.QuestPointers and not Route.dirty and NewAvailable() then
        Route.MarkDirty(3)
    end

    if not Route.Current() and not Route.dirty then Route.MarkDirty(1) end

    if changed then
        Route.DrawPins()
        if ns.RequestRefresh then ns.RequestRefresh() end
        if ns.ArrowRescan then ns.ArrowRescan() end
    end

    if Route.dirty and GetTime() >= Route.dirtyAt and GetTime() - Route.lastPlan >= 2 then
        Route.Plan()
    end
end

function Route.Skip(step)
    if not step then return end
    if step.kind == "travel" then
        -- Saltar un viaje = quedarse en la zona actual un rato.
        Route.stayUntil = GetTime() + 900
        print("|cffffd100Siguiente|r: me quedo en esta zona 15 minutos antes de proponer otro viaje.")
    else
        Route.ignored[step.qid] = GetTime() + 1800
        print("|cffffd100Siguiente|r: salto \"" .. step.title .. "\" por 30 minutos.")
    end
    Route.Plan()
end

function Route.Reset()
    local db = ns.GetDB()
    if db then db.route.done = 0 end
    wipe(Route.ignored)
    Route.steps = {}
    Route.Plan()
end

function Route.SetEnabled(on)
    Route.enabled = on
    local db = ns.GetDB()
    if db then db.route.enabled = on end
    if on then
        Route.Plan()
    else
        Route.DrawPins()
    end
    if ns.RequestRefresh then ns.RequestRefresh() end
    if ns.ArrowRescan then ns.ArrowRescan() end
end

---------------------------------------------------------------------------
-- Textos
---------------------------------------------------------------------------
local logCache -- se llena mientras se dibujan los números, para no leer el diario 50 veces
local function LogQuest(qid)
    for _, q in ipairs(logCache or ns.ReadQuests()) do
        if q.id == qid then return q end
    end
end

-- Título sin colores ("Acepta: X" o, en viajes, "Toma el barco a Y")
function Route.PlainTitle(s)
    if s.kind == "travel" then return s.title end
    return KIND_TEXT[s.kind] .. ": " .. s.title
end

function Route.StepTitle(s)
    if s.kind == "travel" then return ns.Color(KIND_HEX.travel, s.title) end
    return ns.Color(KIND_HEX[s.kind], KIND_TEXT[s.kind] .. ": ") .. s.title
end

function Route.StepDetail(s)
    if s.kind == "travel" then return s.detail end
    if s.kind == "do" then
        local q = LogQuest(s.qid)
        if q then
            local parts = {}
            for _, o in ipairs(q.objectives) do
                if not o.done and o.text and o.text ~= "" then parts[#parts + 1] = o.text end
            end
            if #parts > 0 then return table.concat(parts, " · ") end
        end
        return s.loc and s.loc.name and ("en " .. s.loc.name) or "lee la misión"
    end
    local who = s.loc and s.loc.name
    if not who then return nil end
    return (s.kind == "accept" and "con " or "a ") .. who
end

---------------------------------------------------------------------------
-- Pasos agrupados: lo que se muestra en pantalla (mismo número = un paso)
---------------------------------------------------------------------------
Route.KIND_HEX = KIND_HEX
Route.KIND_RGB = KIND_RGB

function Route.Groups()
    local out, byNum = {}, {}
    for _, s in ipairs(Route.steps) do
        local g = byNum[s.num]
        if not g then
            g = { num = s.num, kind = s.kind, steps = {}, done = true }
            byNum[s.num] = g
            out[#out + 1] = g
        end
        g.steps[#g.steps + 1] = s
        if not s.done then g.done = false end
    end
    return out
end

-- El paso actual: el que elegiste con un clic (si sigue pendiente) o el primero sin hacer.
function Route.CurrentGroup()
    local groups = Route.Groups()
    if Route.focusNum then
        for _, g in ipairs(groups) do
            if g.num == Route.focusNum and not g.done then return g, groups end
        end
        Route.focusNum = nil
    end
    for _, g in ipairs(groups) do
        if not g.done then return g, groups end
    end
    return nil, groups
end

function Route.Focus(num)
    Route.focusNum = num
    Route.DrawPins()
    if ns.RequestRefresh then ns.RequestRefresh() end
    if ns.ArrowRescan then ns.ArrowRescan() end
end

function Route.LastNum()
    local last = Route.steps[#Route.steps]
    return last and last.num or 0
end

-- Texto de un paso agrupado: título, detalle (misiones u objetivos) y dónde.
function Route.GroupText(g)
    local live = {}
    for _, s in ipairs(g.steps) do
        if not s.done then live[#live + 1] = s end
    end
    if #live == 0 then live = g.steps end
    local first = live[1]
    local who = first.loc and first.loc.name
    local title, detail
    if g.kind == "travel" then
        title, detail = first.title, first.detail
    elseif #live == 1 then
        title = KIND_TEXT[g.kind] .. ": " .. first.title
        detail = Route.StepDetail(first)
    else
        if g.kind == "accept" then
            title = "Acepta " .. #live .. " misiones" .. (who and (" de " .. who) or "")
        elseif g.kind == "turnin" then
            title = "Entrega " .. #live .. " misiones" .. (who and (" a " .. who) or "")
        else
            title = "Haz " .. #live .. " misiones aquí"
        end
        local parts = {}
        for _, s in ipairs(live) do
            parts[#parts + 1] = (g.kind == "do") and (Route.StepDetail(s) or s.title) or s.title
        end
        detail = table.concat(parts, " · ")
    end
    local where
    if first.loc then
        where = MapName(first.loc.uiMap) .. string.format(" (%.0f, %.0f)", first.loc.x, first.loc.y)
    end
    return title, detail, where
end

function Route.PrintList()
    local cur, groups = Route.CurrentGroup()
    if not cur then
        print("|cffffd100Siguiente|r: " .. (Route.status or "no hay ruta todavía."))
        return
    end
    print("|cffffd100Siguiente|r: próximos pasos")
    local shown = 0
    for _, g in ipairs(groups) do
        if not g.done then
            local title, detail, where = Route.GroupText(g)
            print("  " .. g.num .. ". " .. ns.Color(KIND_HEX[g.kind], title) .. (detail and (" — " .. detail) or "")
                .. (where and (" — " .. where) or ""))
            shown = shown + 1
            if shown >= 30 then break end
        end
    end
end

-- Para la flecha: a dónde ir en el paso actual.
function Route.ArrowTarget()
    if not Route.enabled then return nil end
    local g = Route.CurrentGroup()
    if not g then return nil end
    local s
    for _, o in ipairs(g.steps) do
        if not o.done then s = o break end
    end
    s = s or g.steps[1]
    local loc = s.loc and {
        x = s.loc.wx, y = s.loc.wy, inst = s.loc.inst, uiMap = s.loc.uiMap,
        mapX = s.loc.x, mapY = s.loc.y, name = s.loc.name,
    }
    -- En "haz", si ya la tienes, Questie sabe cuál objetivo te falta y dónde está el más cercano.
    if s.kind == "do" and ns.GetQuestie and ns.LocateQuest then
        local QQ = ns.GetQuestie()
        local live = QQ and ns.LocateQuest(QQ, s.qid)
        if live then loc = live end
    end
    local title = Route.GroupText(g)
    return {
        step = s,
        group = g,
        loc = loc,
        quest = { id = s.qid, title = s.title, complete = s.kind == "turnin" },
        heading = ns.Color("ffffff", "Paso " .. g.num .. ": ") .. ns.Color(KIND_HEX[g.kind], title),
    }
end

-- Saltar un paso agrupado entero.
function Route.SkipGroup(g)
    if not g then return end
    if g.kind == "travel" then return Route.Skip(g.steps[1]) end
    for _, s in ipairs(g.steps) do Route.ignored[s.qid] = GetTime() + 1800 end
    local title = Route.GroupText(g)
    print("|cffffd100Siguiente|r: salto \"" .. title .. "\" por 30 minutos.")
    Route.focusNum = nil
    Route.Plan()
end

-- Diagnóstico: pasos sin lugar conocido (para /sig debug).
function Route.DebugMissing()
    local out = {}
    for _, s in ipairs(Route.steps) do
        if not s.done and not s.loc and s.kind ~= "travel" then
            local quest = Q and Q.DB.GetQuest(s.qid)
            local ids = {}
            local who = quest and ((s.kind == "accept" and quest.Starts and quest.Starts.NPC)
                or (s.kind == "turnin" and quest.Finisher and quest.Finisher.NPC)) or {}
            for _, id in pairs(who) do
                local npc = Q.DB:GetNPC(id)
                local areas = {}
                for a in pairs(npc and npc.spawns or {}) do areas[#areas + 1] = tostring(a) .. "->" .. tostring(AreaMap(a)) end
                ids[#ids + 1] = tostring(id) .. (npc and (" " .. tostring(npc.name) .. " amistoso=" .. tostring(npc.friendly)
                    .. " áreas=" .. table.concat(areas, ",")) or " (no está en la base)")
            end
            out[#out + 1] = s.kind .. " " .. tostring(s.qid) .. " " .. tostring(s.title) .. " :: " .. table.concat(ids, " | ")
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Números en el mapa y el minimapa
---------------------------------------------------------------------------
local worldPins, miniPins = {}, {}

local function MakePin(pool, i)
    local p = pool[i]
    if p then return p end
    p = CreateFrame("Frame", nil, UIParent)
    p:SetSize(20, 20)
    p.edge = p:CreateTexture(nil, "BACKGROUND")
    p.edge:SetPoint("TOPLEFT", -2, 2)
    p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    p.edge:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    p.edge:SetVertexColor(0, 0, 0, 0.9)
    p.bg = p:CreateTexture(nil, "ARTWORK")
    p.bg:SetAllPoints()
    p.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.text:SetPoint("CENTER", 0, 0)
    p.text:SetTextColor(0, 0, 0)
    if p.text.SetShadowOffset then p.text:SetShadowOffset(0, 0) end
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, line in ipairs(self.tip) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pool[i] = p
    return p
end

-- pin: lista de pasos agrupados que caen en el mismo lugar (ej.: entregar y aceptar con el mismo NPC = "3-4")
local function StylePin(p, pin, isCurrent)
    local first, last = pin[1], pin[#pin]
    local label = (first.num ~= last.num) and (first.num .. "-" .. last.num) or tostring(first.num)
    local size = isCurrent and 24 or 18
    p.text:SetText(label)
    p:SetSize(math.max(size, (p.text:GetStringWidth() or 0) + 8), size)
    local rgb = KIND_RGB[first.kind]
    p.bg:SetVertexColor(rgb[1], rgb[2], rgb[3])
    p.tip = {}
    for _, g in ipairs(pin) do
        local title, detail = Route.GroupText(g)
        p.tip[#p.tip + 1] = "Paso " .. g.num .. ": " .. ns.Color(KIND_HEX[g.kind], title)
            .. (detail and ("\n   " .. detail) or "")
    end
end

local function PinLoc(g)
    for _, s in ipairs(g.steps) do
        if not s.done and s.loc then return s.loc end
    end
end

function Route.DrawPins()
    if not Q then return end
    pcall(Q.Pins.RemoveAllWorldMapIcons, Q.Pins, Route)
    pcall(Q.Pins.RemoveAllMinimapIcons, Q.Pins, Route)
    for _, p in pairs(worldPins) do p:Hide() end
    for _, p in pairs(miniPins) do p:Hide() end
    Route.pinsShown = false
    if not Route.enabled then return end
    if (ns.Guide and ns.Guide.Active()) or (ns.Bridge and ns.Bridge.Active()) then return end
    Route.pinsShown = true

    -- Un círculo por lugar: pasos seguidos en el mismo sitio comparten círculo ("3-4").
    logCache = ns.ReadQuests()
    local pins = {}
    local current = Route.CurrentGroup()
    for _, g in ipairs(Route.Groups()) do
        local loc = not g.done and PinLoc(g)
        if loc then
            if #pins >= PINS_ON_MAP then break end
            local pin = pins[#pins]
            local prev = pin and PinLoc(pin[#pin])
            if prev and prev.uiMap == loc.uiMap and math.abs(prev.x - loc.x) < 0.6 and math.abs(prev.y - loc.y) < 0.6 then
                pin[#pin + 1] = g
            else
                pins[#pins + 1] = { g, loc = loc }
            end
        end
    end

    local flag = HBD_PINS_WORLDMAP_SHOW_PARENT or 1
    local opt = (ns.GetDB() and ns.GetDB().opt) or {}
    for i, pin in ipairs(pins) do
        local loc = pin.loc
        local isCurrent = false
        for _, g in ipairs(pin) do
            if g == current or (current and g.num == current.num) then isCurrent = true end
        end
        local g = pin
        if opt.mapPins ~= false then
            local wp = MakePin(worldPins, i)
            StylePin(wp, g, isCurrent)
            wp:Show()
            pcall(Q.Pins.AddWorldMapIconMap, Q.Pins, Route, wp, loc.uiMap, loc.x / 100, loc.y / 100, flag)
        end
        if i <= PINS_ON_MINIMAP and opt.miniPins ~= false then
            local mp = MakePin(miniPins, i)
            StylePin(mp, g, isCurrent)
            mp:Show()
            pcall(Q.Pins.AddMinimapIconMap, Q.Pins, Route, mp, loc.uiMap, loc.x / 100, loc.y / 100, true, isCurrent)
        end
    end
    logCache = nil
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "QUEST_REMOVED", "PLAYER_LEVEL_UP", "TAXIMAP_OPENED", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(ev.RegisterEvent, ev, e)
end

-- Al abrir el mapa de vuelo guardamos qué vuelos conoce este personaje (para proponer "vuela a X").
local function RecordTaxiNodes()
    local db = ns.GetDB()
    if not db then return end
    db.taxi = db.taxi or {}
    if NumTaxiNodes and TaxiNodeName then
        for i = 1, NumTaxiNodes() do
            local kind = TaxiNodeGetType and TaxiNodeGetType(i)
            if kind == "REACHABLE" or kind == "CURRENT" then
                local name = TaxiNodeName(i)
                if name then db.taxi[name] = true end
            end
        end
    end
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_Map and C_Map.GetBestMapForUnit then
        local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, C_Map.GetBestMapForUnit("player"))
        if ok and type(nodes) == "table" then
            for _, n in ipairs(nodes) do
                -- state: 0 = donde estás, 1 = alcanzable, 2 = no descubierto
                if n.name and (n.state == 0 or n.state == 1) then db.taxi[n.name] = true end
            end
        end
    end
end

local syncQueued = false
local function QueueSync(delay)
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(delay or 0.5, function()
        syncQueued = false
        Route.Sync()
    end)
end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "QUEST_TURNED_IN" and arg1 then
        Route.turnedIn[arg1] = true
    elseif event == "PLAYER_LEVEL_UP" then
        Route.MarkDirty(4)
    elseif event == "TAXIMAP_OPENED" then
        RecordTaxiNodes()
        return
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        QueueSync(1)
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        Route.MarkDirty(5)
    end
    QueueSync(0.5)
end)

C_Timer.NewTicker(2, function() Route.Sync() end)
