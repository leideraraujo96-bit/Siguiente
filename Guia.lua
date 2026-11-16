-- Guía: sigue las rutas de leveo de Polestar (importadas en Guias/Guias.lua, GPL-3.0) sin necesitar Polestar.
-- Elige la ruta por raza, facción y nivel, filtra los pasos por clase/raza/condiciones, detecta lo que
-- haces (misiones, objetivos, llegar a un punto, vuelos, hogar, entrenador, nivel) y pasa sola a la siguiente.

local _, ns = ...
local Guide = { current = nil, statuses = {}, latch = {}, flew = {}, focus = nil }
ns.Guide = Guide

local TRAVEL = { ["goto"] = true, enter = true, fly = true, getfp = true }
local OBJECTIVE = { kill = true, collect = true, talk = true, interact = true, use = true, complete = true,
    explore = true, enter = true, escort = true }
local KIND = { accept = "accept", turnin = "turnin", ["goto"] = "travel", enter = "travel", fly = "travel",
    getfp = "travel", sethome = "travel" }

---------------------------------------------------------------------------
-- Datos del personaje y nombres
---------------------------------------------------------------------------
local function Player()
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    return { faction = UnitFactionGroup("player"), race = race, class = class, level = UnitLevel("player") }
end

local function Name(kind, id)
    id = tonumber(id)
    if not id then return nil end
    if kind == "zone" then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        return info and info.name
    end
    if kind == "area" then
        local n = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
        if n and n ~= "" then return n end
    end
    if kind == "item" and GetItemInfo then
        local n = GetItemInfo(id)
        if n then return n end
    end
    local t = ns.NOMBRES and ns.NOMBRES[kind]
    return t and t[id]
end
Guide.Name = Name

-- "{zone:1413}" → "Los Baldíos", etc.
function Guide.Text(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("{(%a+):(%d+)}", function(kind, id) return Name(kind, id) or ("#" .. id) end))
end
local Text = Guide.Text

local function Has(list, value)
    if type(list) ~= "table" then return list == value end
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

local function Matches(only, P)
    if not only then return true end
    if only.factions and not Has(only.factions, P.faction) then return false end
    if only.races and not Has(only.races, P.race) then return false end
    if only.classes and not Has(only.classes, P.class) then return false end
    return true
end

local function Compare(a, op, b)
    a, b = a or 0, b or 0
    if op == "<" then return a < b elseif op == "<=" then return a <= b elseif op == ">" then return a > b
    elseif op == "==" or op == "=" then return a == b end
    return a >= b
end

local function Completed(q)
    if not q then return false end
    if ns.Route and ns.Route.turnedIn and ns.Route.turnedIn[q] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(q) and true or false end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(q) and true or false end
    return false
end

local function AreaIs(area, name)
    local here = { GetRealZoneText and GetRealZoneText() or "", GetZoneText and GetZoneText() or "",
        GetSubZoneText and GetSubZoneText() or "" }
    local want = Name("area", area)
    for _, h in ipairs(here) do
        if h ~= "" and (h == want or h == name) then return true end
    end
    return false
end

local function KnowsTaxi(node, name)
    local db = ns.GetDB()
    if not (db and db.taxi) then return false end
    local want = { Name("taxi", node), name }
    for known in pairs(db.taxi) do
        for _, w in ipairs(want) do
            if w and (known == w or known:find(w, 1, true)) then return true end
        end
    end
    return false
end

local function BoundTo(area, name)
    local bind = GetBindLocation and GetBindLocation()
    if not bind then return false end
    return bind == Name("area", area) or bind == name
end

local function SkillRank(line)
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    for i = 1, GetNumSkillLines() do
        local name, header, _, rank = GetSkillLineInfo(i)
        if not header and line and name then
            local info = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
            if info then
                local ok, p = pcall(info, line)
                if ok and p and p.professionName == name then return rank end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Guías: cuál te toca y cuál sigue
---------------------------------------------------------------------------
local function Levels(g, faction)
    local fl = g.factionLevels and g.factionLevels[faction]
    return (fl and fl.min) or g.minLevel or 1, (fl and fl.max) or g.maxLevel or 60
end

local function GuideMatches(g, P)
    if g.faction and g.faction ~= P.faction then return false end
    if not g.faction and g.factionLevels and not g.factionLevels[P.faction] then return false end
    if g.races and not Has(g.races, P.race) then return false end
    return true
end

local function PlayerZone()
    return ns.Route and ns.Route.PlayerZone and ns.Route.PlayerZone()
end

-- Las guías para tu personaje, por nivel.
function Guide.List()
    local P = Player()
    local out = {}
    for id, g in pairs(ns.GUIAS or {}) do
        if GuideMatches(g, P) then
            local lo, hi = Levels(g, P.faction)
            out[#out + 1] = { id = id, lo = lo, hi = hi, title = Guide.Title(g) }
        end
    end
    table.sort(out, function(a, b)
        if a.lo ~= b.lo then return a.lo < b.lo end
        return a.id < b.id
    end)
    return out
end

function Guide.Title(g)
    local P = Player()
    local lo, hi = Levels(g, P.faction)
    return Text(g.title or g.zoneName or g.id) .. " (" .. lo .. "–" .. hi .. ")"
end

-- La mejor guía para empezar: la de tu raza si te toca por nivel; si no, la de tu nivel (y si puede, tu zona).
function Guide.Choose()
    local P = Player()
    local here = PlayerZone()
    local best, bestScore
    for id, g in pairs(ns.GUIAS or {}) do
        if GuideMatches(g, P) then
            local lo, hi = Levels(g, P.faction)
            local score
            if P.level >= lo and P.level <= hi then score = 0
            elseif P.level < lo then score = lo - P.level
            else score = (P.level - hi) * 2 end
            if g.races then score = score - 0.5 end
            if here and g.zone == here then score = score - 0.7 end
            if not bestScore or score < bestScore or (score == bestScore and id < best) then best, bestScore = id, score end
        end
    end
    return best
end

local function NextOf(g)
    local P = Player()
    local list = {}
    if g.next then list[#list + 1] = g.next end
    for _, id in ipairs(g.nextChoices or {}) do list[#list + 1] = id end
    for _, id in ipairs(list) do
        local n = ns.GUIAS[id]
        if n and GuideMatches(n, P) then return id end
    end
    return nil
end

local function State()
    local db = ns.GetDB()
    db.guia = db.guia or { skips = {} }
    db.guia.skips = db.guia.skips or {}
    return db.guia
end

function Guide.Get()
    local st = State()
    local g = st.id and ns.GUIAS and ns.GUIAS[st.id]
    if g and GuideMatches(g, Player()) then return g end
    return nil
end

function Guide.Set(id)
    local st = State()
    st.id = id
    Guide.focus = nil
    Guide.latch = {}
    Guide.Evaluate()
    if ns.RequestRefresh then ns.RequestRefresh() end
    if ns.ArrowRescan then ns.ArrowRescan() end
end

function Guide.Active()
    local db = ns.GetDB and ns.GetDB()
    if not (db and ns.GUIAS) then return false end
    if db.opt and db.opt.useGuides == false then return false end
    if Guide.Get() then return true end
    -- Primera vez (o la ruta guardada ya no sirve): elegir la que te toca
    local id = Guide.Choose()
    if id then
        State().id = id
        Guide.latch = {}
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Estado de cada paso
---------------------------------------------------------------------------
local ctx -- se arma en cada evaluación

local function Cond(w)
    local k, r = w.k, true
    local qs = type(w.q) == "table" and w.q or { w.q }
    if k == "level" then
        r = Compare(ctx.level, w.op, w.n)
    elseif k == "onquest" then
        r = false
        for _, q in ipairs(qs) do if ctx.inLog[q] then r = true end end
    elseif k == "turnedin" then
        r = false
        for _, q in ipairs(qs) do if Completed(q) then r = true end end
    elseif k == "complete" then
        r = false
        for _, q in ipairs(qs) do if ctx.inLog[q] and ctx.inLog[q].complete then r = true end end
    elseif k == "group" then
        r = ctx.opt.allowGroup == true
    elseif k == "dungeon" then
        r = ctx.opt.allowDungeon == true
    elseif k == "zone" then
        r = AreaIs(w.area, w.name)
    elseif k == "has" then
        r = (GetItemCount and GetItemCount(w.item) or 0) >= (w.n or 1)
    elseif k == "knows" then
        r = w.spell and ((IsPlayerSpell and IsPlayerSpell(w.spell)) or (IsSpellKnown and IsSpellKnown(w.spell))) and true or false
    elseif k == "taxi" then
        r = KnowsTaxi(w.node, w.name)
    elseif k == "bound" then
        r = BoundTo(w.area, w.name)
    elseif k == "money" then
        r = Compare(GetMoney and GetMoney() or 0, w.op, w.n)
    elseif k == "skill" then
        local rank = SkillRank(w.skillLine)
        r = rank ~= nil and rank >= (w.n or 1)
    elseif k == "available" then
        local q = qs[1]
        r = q and not Completed(q) and not ctx.inLog[q] and ctx.level >= (w.minLevel or 0)
    elseif k == "done" then
        r = Guide.LabelDone(w.label)
    end
    if w.neg then r = not r end
    return r
end

local function Applies(step)
    if not Matches(step.only, ctx.P) then return false end
    for _, w in ipairs(step.when or {}) do
        if not Cond(w) then return false end
    end
    return true
end

-- Distancia en yardas del jugador a un punto del mapa (con la librería de mapas de Questie).
local function Distance(map, x, y)
    local HBD = ns.QuestieHBD and ns.QuestieHBD()
    if not (HBD and map and x and y) then return nil end
    local px, py, pinst = HBD:GetPlayerWorldPosition()
    local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, map)
    if not (px and wx) or pinst ~= inst then return nil end
    return math.sqrt((px - wx) ^ 2 + (py - wy) ^ 2)
end
Guide.Distance = Distance

local function Latch(i, gi)
    local key = ctx.id .. ":" .. i .. ":" .. gi
    return Guide.latch[key], key
end

-- ¿Está hecho este objetivo? → true/false, y "na" si no es para ti.
local function GoalDone(i, gi, goal)
    if goal.only and not Matches(goal.only, ctx.P) then return true, "na" end
    local t, q = goal.t, goal.quest
    if t == "accept" then return (ctx.inLog[q] or Completed(q)) and true or false end
    if t == "turnin" then return Completed(q) end
    if t == "abandon" then return not ctx.inLog[q] end
    if q and OBJECTIVE[t] then
        if Completed(q) then return true end
        local lq = ctx.inLog[q]
        if not lq then return false end
        if lq.complete then return true end
        local o = goal.oi and lq.objectives[goal.oi]
        if o then return o.done and true or false end
        return false
    end
    if t == "collect" and goal.item then
        return (GetItemCount and GetItemCount(goal.item) or 0) >= (goal.count or 1)
    end
    if t == "level" then return ctx.level >= (goal.level or 0) end
    if t == "goto" or t == "enter" then
        local done, key = Latch(i, gi)
        if done then return true end
        local d = Distance(goal.map, goal.x, goal.y)
        if d and d <= math.max(goal.r or 0, 25) then
            Guide.latch[key] = true
            return true
        end
        return false
    end
    if t == "fly" then
        local _, key = Latch(i, gi)
        if UnitOnTaxi and UnitOnTaxi("player") then Guide.flew[key] = true return false end
        if Guide.flew[key] then return true end
        return AreaIs(goal.area, goal.location)
    end
    if t == "getfp" then
        if KnowsTaxi(goal.node, goal.location) then return true end
        local done, key = Latch(i, gi)
        if done then return true end
        local d = Distance(goal.map, goal.x, goal.y)
        if d and d <= 12 then Guide.latch[key] = true return true end
        return false
    end
    if t == "sethome" then return BoundTo(goal.area, goal.location) end
    if t == "train" then return (State().trainedAt or 0) >= ctx.level end
    if t == "learn" then
        if goal.spell and ((IsPlayerSpell and IsPlayerSpell(goal.spell)) or (IsSpellKnown and IsSpellKnown(goal.spell))) then return true end
        return (State().trainedAt or 0) >= ctx.level
    end
    if t == "buy" and goal.item and not goal.optional then
        return (GetItemCount and GetItemCount(goal.item) or 0) >= (goal.count or 1)
    end
    -- note, vendor, kill/explore sin misión, die, money, rep, skill, craft, auction, task: no bloquean
    return true
end

-- done: todo lo que pide está hecho; progress: algo de misiones ya hecho (prueba de que pasaste por aquí)
local function StepStatus(i, step)
    local travelOnly, travelDone, mainDone, progress, hasQuest = true, true, true, false, false
    local goals = {}
    for gi, goal in ipairs(step.goals or {}) do
        local done, na = GoalDone(i, gi, goal)
        goals[gi] = { done = done, na = na == "na" }
        if na ~= "na" then
            -- Lo que falta es de una misión que tienes: entonces sí hay algo que hacer aquí aunque la ruta haya seguido.
            if not done and goal.quest and ctx.inLog[goal.quest] and goal.t ~= "accept" then hasQuest = true end
            if TRAVEL[goal.t] then
                -- En un viaje cuenta llegar al destino final: el último punto manda.
                travelDone = done and true or false
            else
                travelOnly = false
                local blocking = not (goal.optional) and goal.t ~= "note"
                if blocking and not done then mainDone = false end
                -- Prueba de que la ruta ya pasó por aquí: una misión ENTREGADA. Aceptar o adelantar
                -- objetivos de algo de más adelante es normal y no debe hacerte saltar pasos.
                if done and goal.quest and goal.t == "turnin" then
                    progress = true
                end
            end
        end
    end
    local done
    if travelOnly then done = travelDone else done = mainDone end
    return { done = done, progress = progress, travelOnly = travelOnly, hasQuest = hasQuest, goals = goals }
end

function Guide.LabelDone(label)
    if not (label and Guide.guide) then return false end
    for i, s in ipairs(Guide.guide.steps) do
        if s.label == label then
            local st = Guide.statuses[i]
            return st and st.done or false
        end
    end
    return false
end

function Guide.Evaluate()
    local db = ns.GetDB()
    if not (db and ns.GUIAS) then return end
    local st = State()
    if not Guide.Get() then
        st.id = Guide.Choose()
        Guide.latch = {}
    end
    local g = Guide.Get()
    Guide.guide = g
    if not g then Guide.current = nil return end

    local inLog = {}
    for _, q in ipairs(ns.ReadQuests()) do if q.id then inLog[q.id] = q end end
    ctx = { P = Player(), level = UnitLevel("player"), inLog = inLog, opt = db.opt or {}, id = g.id }

    local statuses, lastProgress = {}, 0
    local skips = st.skips[g.id] or {}
    -- Pasos ya cumplidos quedan cumplidos (fijar el hogar en otra posada o gastar un objeto no los deshace).
    st.done = st.done or {}
    st.done[g.id] = st.done[g.id] or {}
    local doneMemo = st.done[g.id]
    for i, step in ipairs(g.steps) do
        if Applies(step) then
            local s = StepStatus(i, step)
            s.applies = true
            if s.done then doneMemo[i] = true elseif doneMemo[i] then s.done = true end
            statuses[i] = s
            if s.progress then lastProgress = i end
        else
            statuses[i] = { applies = false }
        end
    end
    Guide.statuses = statuses

    local current
    for i, s in ipairs(statuses) do
        if s.applies and not s.done and not skips[i] then
            -- Pasos que quedaron atrás: si no tienes ninguna de sus misiones, la ruta ya siguió de largo.
            if i < lastProgress and (s.travelOnly or not s.hasQuest) then
                s.behind = true
            else
                current = i
                break
            end
        end
    end

    -- Guía terminada: a la siguiente
    if not current then
        local nextId = NextOf(g)
        if nextId and not Guide.chaining then
            Guide.chaining = true
            st.id = nextId
            Guide.latch = {}
            Guide.Evaluate()
            Guide.chaining = false
            return
        end
    end
    Guide.current = current
    if Guide.focus and not (statuses[Guide.focus] and statuses[Guide.focus].applies and not statuses[Guide.focus].done) then
        Guide.focus = nil
    end
end

---------------------------------------------------------------------------
-- Textos de un paso
---------------------------------------------------------------------------
local function QuestName(goal) return Name("quest", goal.quest) or goal.title or ("misión " .. tostring(goal.quest)) end
local function NpcName(goal) return (goal.npc and Name("npc", goal.npc)) or goal.npcName end
local function ItemName(goal) return (goal.item and Name("item", goal.item)) or goal.itemName end

-- Progreso de un objetivo según tu diario ("0/1") y el nombre de lo que pide ("Jarra de agua").
local function Progress(goal)
    if not (goal.quest and goal.oi and ctx and ctx.inLog[goal.quest]) then return nil, nil end
    local o = ctx.inLog[goal.quest].objectives[goal.oi]
    if not (o and o.text) then return nil, nil end
    local prog = o.text:match("(%d+%s*/%s*%d+)")
    local thing = o.text:gsub("%d+%s*/%s*%d+", ""):gsub("^[%s:]+", ""):gsub("[%s:]+$", "")
    return prog, (thing ~= "" and thing or nil)
end
Guide.Progress = Progress

function Guide.GoalText(goal)
    local t = goal.t
    -- Objetivos de misión: verbo + qué + progreso ("Consigue Jarra de agua 0/1")
    if goal.quest and OBJECTIVE[t] then
        local prog, thing = Progress(goal)
        local verb, what
        if t == "kill" then verb, what = "Mata a", NpcName(goal) or goal.target or thing
        elseif t == "collect" then verb, what = "Consigue", ItemName(goal) or thing
        elseif t == "talk" then verb, what = "Habla con", NpcName(goal) or thing
        elseif t == "interact" then verb, what = "Usa", (goal.object and Name("object", goal.object)) or goal.objName or thing
        elseif t == "use" then verb, what = "Usa", ItemName(goal) or thing
        elseif t == "explore" or t == "enter" then verb, what = "Explora", thing or (goal.text and Text(goal.text))
        elseif t == "escort" then verb, what = "Escolta a", NpcName(goal) or thing
        else verb, what = "Completa", thing or QuestName(goal) end
        if not prog and goal.count and goal.count > 1 then prog = "0/" .. goal.count end
        return verb .. " " .. (what or "") .. (prog and ("  |cffffffff" .. prog .. "|r") or "")
    end
    if t == "accept" then
        local who = NpcName(goal)
        return "Acepta " .. QuestName(goal) .. (who and (" · " .. who) or "")
    elseif t == "turnin" then
        local who = NpcName(goal)
        return "Entrega " .. QuestName(goal) .. (who and (" a " .. who) or "")
    elseif t == "kill" then
        return "Mata " .. ((goal.count and goal.count > 1) and (goal.count .. " ") or "") .. (NpcName(goal) or goal.target or "")
    elseif t == "collect" then
        return "Consigue " .. ((goal.count and goal.count > 1) and (goal.count .. " ") or "") .. (ItemName(goal) or "")
    elseif t == "talk" then
        return "Habla con " .. (NpcName(goal) or "")
    elseif t == "interact" then
        return "Usa " .. ((goal.object and Name("object", goal.object)) or goal.objName or "el objeto")
    elseif t == "use" then
        return "Usa " .. (ItemName(goal) or "el objeto")
    elseif t == "complete" then
        return "Completa " .. QuestName(goal)
    elseif t == "fly" then
        return "Vuela a " .. ((goal.node and Name("taxi", goal.node)) or (goal.area and Name("area", goal.area)) or goal.location or "")
    elseif t == "getfp" then
        return "Aprende la ruta de vuelo" .. ((NpcName(goal) and (" con " .. NpcName(goal))) or "")
    elseif t == "sethome" then
        return "Fija tu hogar" .. ((NpcName(goal) and (" con " .. NpcName(goal))) or "")
    elseif t == "train" then
        return "Entrena tus hechizos nuevos con tu instructor"
    elseif t == "learn" then
        return "Aprende " .. ((goal.spell and GetSpellInfo and GetSpellInfo(goal.spell)) or "el hechizo")
    elseif t == "level" then
        return "Llega a nivel " .. tostring(goal.level) .. (goal.note and (": " .. Text(goal.note)) or "")
    elseif t == "buy" then
        return "Compra " .. ((goal.count and goal.count > 1) and (goal.count .. " ") or "") .. (ItemName(goal) or "")
    elseif t == "vendor" then
        return "Vende y repara"
    elseif t == "die" then
        return "Muere aquí (vuelves como espíritu, es más rápido)"
    elseif t == "abandon" then
        return "Abandona " .. QuestName(goal)
    end
    return Text(goal.text or goal.note or "")
end

local function StepKind(step, status)
    for gi, goal in ipairs(step.goals or {}) do
        local gs = status and status.goals and status.goals[gi]
        if not (gs and (gs.done or gs.na)) and goal.t ~= "note" then
            return KIND[goal.t] or "do"
        end
    end
    local g1 = step.goals and step.goals[1]
    return g1 and (KIND[g1.t] or "do") or "do"
end

-- Primer lugar pendiente del paso (para "dónde", la flecha y el mapa)
local function StepPlace(step, status)
    for gi, goal in ipairs(step.goals or {}) do
        local gs = status and status.goals and status.goals[gi]
        if not (gs and (gs.done or gs.na)) and goal.map and goal.x and goal.y then return goal end
    end
    return nil
end
Guide.StepPlace = StepPlace

local function StepTitle(step, status)
    if step.title and step.title ~= "" then return Text(step.title) end
    for gi, goal in ipairs(step.goals or {}) do
        local gs = status and status.goals and status.goals[gi]
        if not (gs and gs.na) then return Guide.GoalText(goal) end
    end
    return ""
end

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t "

-- Objetivos pendientes del paso (sin notas), en orden.
local function Pending(step, status)
    local out, done = {}, 0
    for gi, goal in ipairs(step.goals or {}) do
        local gs = status and status.goals and status.goals[gi]
        if not (gs and gs.na) and goal.t ~= "note" then
            if gs and gs.done then done = done + 1 else out[#out + 1] = goal end
        end
    end
    return out, done
end

local function Plain(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Lo que tienes que hacer ahora en este paso, en una frase ("Consigue Jarra de agua 0/1", "Acepta 3 misiones de Thork").
local function Headline(step, status)
    local pend = Pending(step, status)
    if #pend == 0 then return StepTitle(step, status) end
    local first = pend[1]
    -- Varias misiones para aceptar o entregar seguidas: una sola frase
    if first.t == "accept" or first.t == "turnin" then
        local same, npc = 0, first.npc
        for _, gl in ipairs(pend) do
            if gl.t == first.t then
                same = same + 1
                if gl.npc ~= npc then npc = nil end
            end
        end
        if same > 1 then
            local who = npc and NpcName(first)
            if first.t == "accept" then return "Acepta " .. same .. " misiones" .. (who and (" de " .. who) or "") end
            return "Entrega " .. same .. " misiones" .. (who and (" a " .. who) or "")
        end
    end
    return Guide.GoalText(first)
end
Guide.Headline = Headline

-- Las líneas debajo del título: qué falta (con su misión), lo hecho resumido y la pista de la ruta.
local function DetailLines(step, status, headline)
    local pend, doneCount = Pending(step, status)
    local lines = {}
    local title = Text(step.title or "")
    if title ~= "" and Plain(title) ~= Plain(headline) then
        lines[#lines + 1] = "|cffc8b88a" .. title .. "|r"
    end
    local several = #pend > 1
    for k, goal in ipairs(pend) do
        if k > 5 then break end
        if several then
            local text = (goal.t == "accept" or goal.t == "turnin") and QuestName(goal) or Guide.GoalText(goal)
            if goal.optional then text = text .. " |cff909090(opcional)|r" end
            lines[#lines + 1] = "• " .. text
        end
        -- La misión a la que pertenece un objetivo (si no se ve ya)
        if goal.quest and OBJECTIVE[goal.t] and not several then
            lines[#lines + 1] = "|cffa0a0a0Misión:|r " .. QuestName(goal)
        end
    end
    if doneCount > 0 then
        lines[#lines + 1] = CHECK .. "|cff909090" .. doneCount .. (doneCount == 1 and " hecho" or " hechos") .. "|r"
    end
    return lines
end

-- Objetivos del paso: primero lo que falta, después lo ya hecho (con su marca).
local function GoalLines(step, status, max)
    local todo, done = {}, {}
    for gi, goal in ipairs(step.goals or {}) do
        local gs = status and status.goals and status.goals[gi]
        if not (gs and gs.na) then
            local text = Guide.GoalText(goal)
            if text and text ~= "" then
                if goal.optional then text = text .. " |cff909090(opcional)|r" end
                if gs and gs.done then
                    done[#done + 1] = CHECK .. "|cff909090" .. text .. "|r"
                else
                    todo[#todo + 1] = text
                end
            end
        end
    end
    local out = {}
    for _, t in ipairs(todo) do out[#out + 1] = t end
    for _, t in ipairs(done) do out[#out + 1] = t end
    while #out > (max or 5) do table.remove(out) end
    return out
end

local function Where(goal)
    if not goal then return nil end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(goal.map)
    local d = Distance(goal.map, goal.x, goal.y)
    return (info and info.name or "") .. string.format(" (%.0f, %.0f)", goal.x, goal.y)
        .. (d and ((d < 15) and " · estás aquí" or (" · " .. ns.Num(d) .. " yd")) or "")
end

---------------------------------------------------------------------------
-- Lo que la ventana necesita (mismo formato que la ruta propia)
---------------------------------------------------------------------------
function Guide.Model(open, scroll, maxRows)
    Guide.Evaluate()
    local g = Guide.guide
    if not g then return nil end
    local m = { rows = {}, guideTitle = Guide.Title(g), total = #g.steps }
    local i = Guide.focus or Guide.current
    if not i then
        m.title = "Ruta terminada"
        m.detail = "Llegaste al final de las rutas. ¡Felicidades!"
        return m
    end
    local step, status = g.steps[i], Guide.statuses[i]
    m.num = i
    m.focus = Guide.focus ~= nil
    m.kind = StepKind(step, status)
    m.title = Headline(step, status)
    local lines = DetailLines(step, status, m.title)
    m.note = step.note and Text(step.note)
    -- La primera frase de la explicación de la ruta, como pista (la explicación entera, al pasar el mouse)
    if m.note and #lines < 4 then
        -- La primera frase completa (termina en . ! ?), no cortada en ":"
        local hint = m.note:match("^(.-[%.!?])%s") or m.note
        if #hint > 160 then hint = hint:sub(1, 157) .. "..." end
        lines[#lines + 1] = "|cff909090" .. hint .. "|r"
    end
    m.detail = table.concat(lines, "\n")
    -- Dónde: el NPC u objeto al que vas, la zona, coordenadas y distancia
    local place = StepPlace(step, status)
    local who = place and (NpcName(place) or (place.object and Name("object", place.object)) or place.objName)
    m.where = place and ((who and (who .. " · ") or "") .. Where(place)) or nil

    local function add(k, isCurrent)
        local s, stt = g.steps[k], Guide.statuses[k]
        local place = StepPlace(s, stt)
        local first = GoalLines(s, stt, 2)
        local sub
        if stt.done then sub = "hecho" elseif stt.behind then sub = "pasado" else
            sub = place and Where(place) or first[1] or ""
        end
        m.rows[#m.rows + 1] = {
            gindex = k, num = k, kind = StepKind(s, stt), title = (stt.done or stt.behind) and StepTitle(s, stt) or Headline(s, stt), sub = sub,
            done = stt.done or stt.behind or false, current = isCurrent,
        }
    end
    local skips = State().skips[g.id] or {}
    if open then
        local skipped, shown = 0, 0
        for k = math.max(1, (Guide.current or i) - 2), #g.steps do
            local stt = Guide.statuses[k]
            if stt and stt.applies and not skips[k] then
                if skipped < scroll then
                    skipped = skipped + 1
                else
                    add(k, k == i)
                    shown = shown + 1
                    if shown >= maxRows then break end
                end
            end
        end
    else
        for k = i + 1, #g.steps do
            local stt = Guide.statuses[k]
            if stt and stt.applies and not stt.done and not skips[k] then
                add(k, false)
                if #m.rows >= maxRows then break end
            end
        end
    end
    local remaining = 0
    for k = (Guide.current or i), #g.steps do
        local stt = Guide.statuses[k]
        if stt and stt.applies and not stt.done and not skips[k] then remaining = remaining + 1 end
    end
    m.remaining = remaining
    return m
end

-- Para la flecha
function Guide.ArrowTarget()
    if not Guide.guide then return nil end
    local i = Guide.focus or Guide.current
    if not i then return nil end
    local step, status = Guide.guide.steps[i], Guide.statuses[i]
    local goal = StepPlace(step, status)
    local loc
    if goal then
        local HBD = ns.QuestieHBD and ns.QuestieHBD()
        if HBD then
            local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(goal.x / 100, goal.y / 100, goal.map)
            if wx then
                loc = { x = wx, y = wy, inst = inst, uiMap = goal.map, mapX = goal.x, mapY = goal.y,
                    name = NpcName(goal) or (goal.text and Text(goal.text)) }
            end
        end
    end
    -- Sin coordenadas: si es una misión que tienes, Questie sabe dónde está lo que falta.
    if not loc and ns.GetQuestie and ns.LocateQuest then
        for gi, gl in ipairs(step.goals or {}) do
            local gs = status.goals[gi]
            if gl.quest and not (gs and (gs.done or gs.na)) then
                local QQ = ns.GetQuestie()
                loc = QQ and ns.LocateQuest(QQ, gl.quest)
                if loc then break end
            end
        end
    end
    local title = Headline(step, status)
    return {
        loc = loc,
        quest = { id = "guia:" .. i, title = title },
        heading = ns.Color("ffffff", "Paso " .. i .. ": ") .. ns.Color(ns.Route.KIND_HEX[StepKind(step, status)] or "ffffff", title),
        guideStep = i,
    }
end

---------------------------------------------------------------------------
-- Acciones
---------------------------------------------------------------------------
function Guide.Focus(i)
    Guide.focus = i
    Guide.DrawPins()
    if ns.RequestRefresh then ns.RequestRefresh() end
    if ns.ArrowRescan then ns.ArrowRescan() end
end

function Guide.Skip(i)
    local g = Guide.guide
    i = i or Guide.focus or Guide.current
    if not (g and i) then return end
    local st = State()
    st.skips[g.id] = st.skips[g.id] or {}
    st.skips[g.id][i] = true
    if Guide.focus == i then Guide.focus = nil end
    print("|cffffd100Siguiente|r: salto el paso " .. i .. " (" .. (StepTitle(g.steps[i], Guide.statuses[i]) or "") .. ").")
    Guide.Evaluate()
    Guide.DrawPins()
    if ns.RequestRefresh then ns.RequestRefresh() end
    if ns.ArrowRescan then ns.ArrowRescan() end
end

function Guide.NextGuide()
    local g = Guide.Get()
    local nextId = g and NextOf(g)
    if nextId then Guide.Set(nextId) end
    return nextId
end

function Guide.ResetSkips()
    local g = Guide.Get()
    if g then
        State().skips[g.id] = nil
        if State().done then State().done[g.id] = nil end
    end
    Guide.Evaluate()
    if ns.RequestRefresh then ns.RequestRefresh() end
end

---------------------------------------------------------------------------
-- Números en el mapa (paso actual y los siguientes)
---------------------------------------------------------------------------
local pins, minis = {}, {}
local PINS_ON_MAP, PINS_ON_MINIMAP = 30, 3

local function Pin(pool, k)
    local p = pool[k]
    if p then return p end
    p = CreateFrame("Frame", nil, UIParent)
    p:SetSize(18, 18)
    p.edge = p:CreateTexture(nil, "BACKGROUND")
    p.edge:SetPoint("TOPLEFT", -2, 2)
    p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    p.edge:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    p.edge:SetVertexColor(0, 0, 0, 0.9)
    p.bg = p:CreateTexture(nil, "ARTWORK")
    p.bg:SetAllPoints()
    p.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.text:SetPoint("CENTER")
    p.text:SetTextColor(0, 0, 0)
    if p.text.SetShadowOffset then p.text:SetShadowOffset(0, 0) end
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pool[k] = p
    return p
end

function Guide.DrawPins()
    local Pins = ns.QuestieHBDPins and ns.QuestieHBDPins()
    if not Pins then return end
    pcall(Pins.RemoveAllWorldMapIcons, Pins, Guide)
    pcall(Pins.RemoveAllMinimapIcons, Pins, Guide)
    for _, p in pairs(pins) do p:Hide() end
    for _, p in pairs(minis) do p:Hide() end
    if not Guide.Active() or not Guide.guide then return end
    local opt = ns.GetDB().opt or {}
    local g = Guide.guide
    local skips = State().skips[g.id] or {}
    local cur = Guide.focus or Guide.current
    if not cur then return end
    -- El paso actual y los próximos N (opción "Pasos en el mapa"), no toda la ruta.
    local limit = 1 + math.max(0, math.min(PINS_ON_MAP, opt.mapPinCount or 8))
    local n = 0
    for k = cur, #g.steps do
        local stt = Guide.statuses[k]
        if stt and stt.applies and not stt.done and not stt.behind and not skips[k] then
            local place = StepPlace(g.steps[k], stt)
            if place then
                n = n + 1
                local kind = StepKind(g.steps[k], stt)
                local rgb = ns.Route.KIND_RGB[kind] or { 1, 1, 1 }
                local tip = "Paso " .. k .. ": " .. Headline(g.steps[k], stt)
                local isCur = k == cur
                local function Style(p)
                    local size = isCur and 28 or 18
                    p.text:SetText(k)
                    p:SetSize(math.max(size, (p.text:GetStringWidth() or 0) + 8), size)
                    p.bg:SetVertexColor(rgb[1], rgb[2], rgb[3])
                    -- El actual con borde dorado grueso; los demás con borde negro fino.
                    local e = isCur and 4 or 2
                    p.edge:ClearAllPoints()
                    p.edge:SetPoint("TOPLEFT", -e, e)
                    p.edge:SetPoint("BOTTOMRIGHT", e, -e)
                    if isCur then p.edge:SetVertexColor(1, 0.82, 0, 1) else p.edge:SetVertexColor(0, 0, 0, 0.9) end
                    p.tip = (isCur and "|cffffd100Paso actual|r\n" or "") .. tip
                    p:Show()
                end
                if opt.mapPins ~= false then
                    local p = Pin(pins, n)
                    Style(p)
                    pcall(Pins.AddWorldMapIconMap, Pins, Guide, p, place.map, place.x / 100, place.y / 100, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
                end
                if n <= PINS_ON_MINIMAP and opt.miniPins ~= false then
                    local p = Pin(minis, n)
                    Style(p)
                    pcall(Pins.AddMinimapIconMap, Pins, Guide, p, place.map, place.x / 100, place.y / 100, true, isCur)
                end
                if n >= limit then break end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Eventos: reevaluar cuando algo cambia (y cada segundo, para "llegar a un punto")
---------------------------------------------------------------------------
local lastCurrent
local function TickRaw()
    if not Guide.Active() then
        if lastCurrent ~= nil then lastCurrent = nil Guide.DrawPins() end
        return
    end
    Guide.Evaluate()
    local key = tostring(Guide.guide and Guide.guide.id) .. ":" .. tostring(Guide.current) .. ":" .. tostring(Guide.focus)
    if key ~= lastCurrent then
        lastCurrent = key
        Guide.DrawPins()
        if ns.RequestRefresh then ns.RequestRefresh() end
        if ns.ArrowRescan then ns.ArrowRescan() end
    end
end
local function Tick()
    local ok, err = pcall(TickRaw)
    if not ok and ns.ReportError then ns.ReportError("ruta", err) end
end
Guide.Tick = Tick

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP",
    "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "TRAINER_SHOW", "TAXIMAP_OPENED", "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED", "BAG_UPDATE_DELAYED", "LEARNED_SPELL_IN_TAB" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if not ns.GetDB() then return end
    if event == "TRAINER_SHOW" then State().trainedAt = UnitLevel("player") end
    C_Timer.After(0.3, Tick)
end)
C_Timer.NewTicker(1, function() if ns.GetDB() then Tick() end end)
