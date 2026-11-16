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

local KIND_TEXT = { accept = "Acepta", ["do"] = "Haz", turnin = "Entrega" }
local KIND_HEX = { accept = "ffd100", ["do"] = "ff8040", turnin = "40ff40" }
local KIND_RGB = { accept = { 1, 0.82, 0 }, ["do"] = { 1, 0.5, 0.15 }, turnin = { 0.3, 1, 0.3 } }

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

local function AddSpawns(out, spawns, name)
    for areaId, list in pairs(spawns or {}) do
        local uiMap = type(list) == "table" and Q.ZoneDB:GetUiMapIdByAreaId(areaId)
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
    for _, id in pairs(ids or {}) do
        local npc = Q.DB:GetNPC(id)
        if npc and npc.spawns and (not friendlyOnly or npc.friendly) then
            AddSpawns(out, npc.spawns, npc.name)
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

-- ¿Vale la pena aceptar esta misión yendo solo?
local function WorthAccepting(qid, quest, level)
    if quest.IsRepeatable then return false end
    if not ((quest.Starts and (quest.Starts.NPC or quest.Starts.GameObject))) then return false end
    local d = ns.Difficulty(quest.level or 0, level)
    if d == "gris" or d == "rojo" or d == "naranja" then return false end
    for _, check in ipairs({ "IsDungeonQuest", "IsRaidQuest", "IsPvPQuest", "IsGroupQuest" }) do
        local fn = Q.DB[check]
        if fn then
            local ok, yes = pcall(fn, qid)
            if ok and yes then return false end
        end
    end
    return true
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
    local maxQ = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
        or MAX_QUESTLOG_QUESTS or 20

    -- 1. Lo que ya tienes en el diario
    local tasks, inLog = {}, {}
    local logQuests = ns.ReadQuests()
    Route.known = {}
    for _, q in ipairs(logQuests) do
        if q.id then
            inLog[q.id] = true
            Route.known[q.id] = true
            local d = ns.Difficulty(q.level, level)
            if not Ignored(q.id) and not q.failed and (q.complete or (d ~= "rojo" and not q.group)) then
                tasks[#tasks + 1] = {
                    qid = q.id, title = q.title, level = q.level, xp = XPOf(q.id),
                    stage = (q.complete or #q.objectives == 0) and "turnin" or "do",
                }
            end
        end
    end
    local logN = #logQuests

    -- 2. Misiones disponibles cerca (los "!" de Questie)
    for qid in pairs(Q.Available.__availableQuests) do
        if not inLog[qid] and not Ignored(qid) and not IsDone(qid) then
            local ok, quest = pcall(Q.DB.GetQuest, qid)
            if ok and quest and WorthAccepting(qid, quest, level) then
                local _, dist = Nearest(Places(qid, "start"), px, py, pinst)
                if dist <= ((db.opt and db.opt.maxDist) or MAX_DIST) then
                    local hasObjectives = (quest.ObjectiveData and #quest.ObjectiveData > 0)
                        or type(quest.triggerEnd) == "table"
                    tasks[#tasks + 1] = {
                        qid = qid, title = quest.name or ("Misión " .. qid), level = quest.level or 0,
                        xp = XPOf(qid), stage = "accept", needDo = hasObjectives,
                    }
                end
            end
        end
    end

    -- 3. Ordenar: siempre lo más cercano, con un empujón a entregar y a lo que da más XP
    local avgXP = 0
    for _, t in ipairs(tasks) do avgXP = avgXP + (t.xp or 0) end
    avgXP = math.max(1, avgXP / math.max(1, #tasks))

    local steps = {}
    local cx, cy, cinst = px, py, pinst

    local function PlaceFor(t)
        local part = (t.stage == "accept" and "start") or (t.stage == "do" and "obj") or "finish"
        return Nearest(Places(t.qid, part), cx, cy, cinst)
    end

    local function Emit(t, loc)
        steps[#steps + 1] = {
            kind = t.stage, qid = t.qid, title = t.title, level = t.level, loc = loc,
            num = db.route.done + #steps + 1,
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
    Route.status = (#steps == 0) and "No hay misiones cerca para tu nivel: muévete a otra zona." or nil
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
    for _, s in ipairs(Route.steps) do
        if not s.done then
            local done
            if s.kind == "accept" then
                done = inLog[s.qid] or IsDone(s.qid)
            elseif s.kind == "do" then
                done = complete[s.qid] or IsDone(s.qid)
            else
                done = IsDone(s.qid)
            end
            if done then
                s.done = true
                db.route.done = db.route.done + 1
                changed = true
            elseif s.kind == "accept" then
                pendingAccept[s.qid] = true
            elseif not inLog[s.qid] and not pendingAccept[s.qid] then
                Route.MarkDirty(0) -- la abandonaste
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
    Route.ignored[step.qid] = GetTime() + 1800
    print("|cffffd100Siguiente|r: salto \"" .. step.title .. "\" por 30 minutos.")
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

function Route.StepTitle(s)
    return ns.Color(KIND_HEX[s.kind], KIND_TEXT[s.kind] .. ": ") .. s.title
end

function Route.StepDetail(s)
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

function Route.WindowText()
    if not Route.enabled then return nil end
    local cur = Route.Current()
    if not cur then
        return ns.Color("ffd100", "RUTA") .. "\n" .. ns.Color("c0c0c0", Route.status or "Calculando...")
    end
    local remaining = 0
    for _, s in ipairs(Route.steps) do if not s.done then remaining = remaining + 1 end end

    local lines = { ns.Color("ffd100", "RUTA") .. ns.Color("909090", "  (" .. remaining .. " pasos por delante)") }
    local shown = 0
    for _, s in ipairs(Route.steps) do
        if not s.done then
            shown = shown + 1
            if shown == 1 then
                lines[#lines + 1] = ns.Color("ffffff", "Paso " .. s.num .. ". ") .. Route.StepTitle(s)
                local detail = Route.StepDetail(s)
                if detail then lines[#lines + 1] = "      " .. ns.Color("c0c0c0", detail) end
            else
                lines[#lines + 1] = ns.Color("909090", s.num .. ". " .. KIND_TEXT[s.kind] .. ": " .. s.title)
            end
            if shown >= 5 then break end
        end
    end
    return table.concat(lines, "\n")
end

function Route.PrintList()
    if not Route.Current() then
        print("|cffffd100Siguiente|r: " .. (Route.status or "no hay ruta todavía."))
        return
    end
    print("|cffffd100Siguiente|r: próximos pasos")
    local shown = 0
    for _, s in ipairs(Route.steps) do
        if not s.done then
            local detail = Route.StepDetail(s)
            local where = s.loc and string.format(" (%.0f, %.0f)", s.loc.x, s.loc.y) or ""
            print("  " .. s.num .. ". " .. Route.StepTitle(s) .. (detail and (" — " .. detail) or "") .. where)
            shown = shown + 1
            if shown >= 30 then break end
        end
    end
end

-- Para la flecha: a dónde ir en el paso actual.
function Route.ArrowTarget()
    if not Route.enabled then return nil end
    local s = Route.Current()
    if not s then return nil end
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
    return {
        step = s,
        loc = loc,
        quest = { id = s.qid, title = s.title, complete = s.kind == "turnin" },
        heading = ns.Color("ffffff", "Paso " .. s.num .. ": ") .. Route.StepTitle(s),
    }
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

local function StylePin(p, group, isCurrent)
    local first, last = group[1], group[#group]
    local label = (#group > 1) and (first.num .. "-" .. last.num) or tostring(first.num)
    local size = isCurrent and 24 or 18
    p.text:SetText(label)
    p:SetSize(math.max(size, (p.text:GetStringWidth() or 0) + 8), size)
    local rgb = KIND_RGB[first.kind]
    p.bg:SetVertexColor(rgb[1], rgb[2], rgb[3])
    p.tip = {}
    for _, s in ipairs(group) do
        local detail = Route.StepDetail(s)
        p.tip[#p.tip + 1] = "Paso " .. s.num .. ": " .. Route.StepTitle(s) .. (detail and ("\n   " .. detail) or "")
    end
end

function Route.DrawPins()
    if not Q then return end
    pcall(Q.Pins.RemoveAllWorldMapIcons, Q.Pins, Route)
    pcall(Q.Pins.RemoveAllMinimapIcons, Q.Pins, Route)
    for _, p in pairs(worldPins) do p:Hide() end
    for _, p in pairs(miniPins) do p:Hide() end
    if not Route.enabled then return end

    -- Pasos seguidos en el mismo lugar van en un solo círculo ("4-6").
    local groups = {}
    local count = 0
    for _, s in ipairs(Route.steps) do
        if not s.done and s.loc then
            count = count + 1
            if count > PINS_ON_MAP then break end
            local g = groups[#groups]
            local prev = g and g[#g]
            if prev and prev.loc.uiMap == s.loc.uiMap and math.abs(prev.loc.x - s.loc.x) < 0.5
                and math.abs(prev.loc.y - s.loc.y) < 0.5 then
                g[#g + 1] = s
            else
                groups[#groups + 1] = { s }
            end
        end
    end

    local flag = HBD_PINS_WORLDMAP_SHOW_PARENT or 1
    local opt = (ns.GetDB() and ns.GetDB().opt) or {}
    logCache = ns.ReadQuests()
    for i, g in ipairs(groups) do
        local loc = g[1].loc
        if opt.mapPins ~= false then
            local wp = MakePin(worldPins, i)
            StylePin(wp, g, i == 1)
            wp:Show()
            pcall(Q.Pins.AddWorldMapIconMap, Q.Pins, Route, wp, loc.uiMap, loc.x / 100, loc.y / 100, flag)
        end
        if i <= PINS_ON_MINIMAP and opt.miniPins ~= false then
            local mp = MakePin(miniPins, i)
            StylePin(mp, g, i == 1)
            mp:Show()
            pcall(Q.Pins.AddMinimapIconMap, Q.Pins, Route, mp, loc.uiMap, loc.x / 100, loc.y / 100, true, i == 1)
        end
    end
    logCache = nil
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
    pcall(ev.RegisterEvent, ev, e)
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        Route.MarkDirty(5)
    end
    QueueSync(0.5)
end)

C_Timer.NewTicker(2, function() Route.Sync() end)
