-- Puente con Polestar: si Polestar está instalado, su ruta (optimizada para WoW Forever, por raza,
-- clase y facción) se muestra en la ventana de Siguiente. Polestar sigue haciendo el trabajo
-- (qué paso toca, qué está hecho, su flecha que camina por caminos reales); Siguiente solo lo pinta.
-- Todo va protegido: si una versión de Polestar cambia por dentro, Siguiente vuelve a su propia ruta.

local _, ns = ...
local Bridge = {}
ns.Bridge = Bridge

local TRAVEL = { ["goto"] = true, fly = true, hearth = true, boat = true, zeppelin = true, tram = true, portal = true, ride = true }

local function PS()
    local P = _G.Polestar
    if type(P) ~= "table" then return nil end
    local E, UI = P.Engine, P.UI
    if not (E and UI and E.GetGuide and E.GetStepView and E.GetStepCount and E.GetStepIndex
        and UI.GoalLine and UI.StepSummary) then
        return nil
    end
    return P, E, UI
end

local function Try(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    Bridge.lastError = a
    return nil
end

-- ¿Se usa la ruta de Polestar ahora? (instalado, con una guía abierta, y la opción activada)
function Bridge.Active()
    local db = ns.GetDB and ns.GetDB()
    if db and db.opt and db.opt.usePolestar == false then return false end
    local P, E = PS()
    if not P then return false end
    if Try(E.GetGuide) == nil then return false end
    -- Comprobación de salud: si leer el paso falla (Polestar cambió por dentro), usamos la ruta propia.
    local at = Try(E.GetStepIndex)
    if at and Try(E.GetStepView, at, true) == nil then return false end
    return true
end

function Bridge.Installed()
    return PS() ~= nil
end

-- Por qué se usa (o no) la ruta de Polestar, en palabras simples (para /sig debug).
function Bridge.Status()
    local db = ns.GetDB and ns.GetDB()
    if not _G.Polestar then return false, "Polestar no está instalado o no está activado" end
    local P, E = PS()
    if not P then return false, "esta versión de Polestar no tiene lo que Siguiente necesita" end
    if db and db.opt and db.opt.usePolestar == false then return false, "la opción 'Usar la ruta de Polestar' está apagada" end
    local guide = Try(E.GetGuide)
    if not guide then return false, "Polestar no tiene una guía abierta (/polestar guides)" end
    local at = Try(E.GetStepIndex)
    if at and Try(E.GetStepView, at, true) == nil then
        return false, "no se pudo leer el paso de Polestar: " .. tostring(Bridge.lastError)
    end
    return true, "conectado: " .. tostring(guide.title or guide.id) .. ", paso " .. tostring(at)
end

-- Tipo de paso (para el color del círculo): aceptar, entregar, viajar o hacer.
local function KindOf(UI, view)
    local verb = Try(UI.FirstVerb, view) or "note"
    if verb == "accept" then return "accept" end
    if verb == "turnin" then return "turnin" end
    if TRAVEL[verb] then return "travel" end
    return "do"
end

local function StepNo(E, UI, i)
    return (UI.StepNo and Try(UI.StepNo, i)) or i
end

local function Applies(E, UI, i, view)
    if not view or view.status == "na" then return false end
    if UI.StepHidden and Try(UI.StepHidden, i) then return false end
    return true
end

-- Líneas de objetivos de un paso, con el texto de Polestar (en tu idioma).
local function GoalLines(UI, view, max)
    local out = {}
    for _, goal in ipairs(view.goals or {}) do
        if goal.status ~= "na" and not goal.folded then
            local g = (UI.ReadingGoal and Try(UI.ReadingGoal, view, goal)) or goal
            local text = Try(UI.GoalLine, g) or g.text
            if text and text ~= "" then
                if goal.status == "done" then
                    text = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t |cff909090"
                        .. ((UI.PlainGoalText and Try(UI.PlainGoalText, g)) or text) .. "|r"
                end
                out[#out + 1] = text
                if #out >= (max or 4) then break end
            end
        end
    end
    return out
end

-- A dónde lleva la flecha de Polestar ahora: nombre del lugar, zona y tiempo estimado.
local function Where(P)
    local api = P.Nav and P.Nav.API
    local t = api and api.Target and Try(api.Target)
    if not t then return nil end
    local stop = t.next or t
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(stop.map)
    local text = (stop.title and stop.title ~= "" and (stop.title .. " · ") or "")
        .. (info and info.name or "") .. string.format(" (%.0f, %.0f)", (stop.x or 0) * 100, (stop.y or 0) * 100)
    local secs = api.Estimate and Try(api.Estimate, nil, nil, nil, t.map, t.x, t.y)
    if secs then
        text = text .. ((secs < 20) and " · estás aquí" or (" · ~" .. (secs < 60 and (math.floor(secs + 0.5) .. " s")
            or (math.floor(secs / 60 + 0.5) .. " min"))))
    end
    return text
end

-- Lo que la ventana necesita, armado desde Polestar.
-- rows: { num, title, sub, kind, done, current, index }
function Bridge.Model(listOpen, scroll, maxRows)
    local P, E, UI = PS()
    if not P then return nil end
    local guide = Try(E.GetGuide)
    if not guide then return nil end
    local count = Try(E.GetStepCount) or 0
    local at = Try(E.GetStepIndex)
    local live = (E.GetLiveStep and Try(E.GetLiveStep)) or at
    local total = (E.StepTotal and Try(E.StepTotal)) or count
    local m = { rows = {}, guideTitle = guide.title, fromPolestar = true }

    if not at then
        m.title = "Guía terminada"
        m.detail = "Elige la siguiente guía con /polestar guides."
        return m
    end

    local view = Try(E.GetStepView, at, true)
    if not view then return nil end
    m.kind = KindOf(UI, view)
    m.num = StepNo(E, UI, at)
    m.total = total
    m.viewing = (live and at ~= live) and live or nil
    m.title = Try(UI.StepSummary, view) or ""
    local lines = GoalLines(UI, view, 4)
    -- Si la primera línea solo repite el título, no la mostramos dos veces.
    if lines[1] and lines[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == m.title then table.remove(lines, 1) end
    m.detail = table.concat(lines, "\n")
    m.where = Where(P)
    if E.GroupQuestion then
        local q, qtitle = Try(E.GroupQuestion)
        if q then m.group = { quest = q, title = qtitle } end
    end

    -- Filas: los siguientes pasos (o la lista completa con scroll)
    local function plain(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function add(i, v, isCurrent)
        local title = Try(UI.StepSummary, v) or ""
        local sub
        if v.status == "done" or v.status == "skipped" then
            sub = v.status == "done" and "hecho" or "saltado"
        else
            -- La primera línea de objetivo que no repite el título
            for _, line in ipairs(GoalLines(UI, v, 3)) do
                if plain(line) ~= title then sub = line break end
            end
        end
        m.rows[#m.rows + 1] = {
            index = i, num = StepNo(E, UI, i), kind = KindOf(UI, v), title = title, sub = sub or "",
            done = v.status == "done" or v.status == "skipped", current = isCurrent,
        }
    end
    if listOpen then
        local start = math.max(1, (live or at) - 2)
        local skipped, shown = 0, 0
        for i = start, count do
            local v = Try(E.GetStepView, i, true)
            if Applies(E, UI, i, v) then
                if skipped < scroll then
                    skipped = skipped + 1
                else
                    add(i, v, i == at)
                    shown = shown + 1
                    if shown >= maxRows then break end
                end
            end
        end
    else
        for i = at + 1, count do
            local v = Try(E.GetStepView, i, true)
            if Applies(E, UI, i, v) and v.status ~= "done" and v.status ~= "skipped" then
                add(i, v, false)
                if #m.rows >= maxRows then break end
            end
        end
    end
    m.remaining = math.max(0, total - (m.num or 0))
    return m
end

---------------------------------------------------------------------------
-- Acciones (lo mismo que los botones de Polestar)
---------------------------------------------------------------------------
function Bridge.Goto(i)
    local _, E = PS()
    if E and E.Goto then Try(E.Goto, i) end
end

function Bridge.BackToLive()
    local _, E = PS()
    local live = E and E.GetLiveStep and Try(E.GetLiveStep)
    if live then Bridge.Goto(live) end
end

function Bridge.Skip(i)
    local _, E = PS()
    if not (E and E.Skip) then return end
    if i and E.Goto and i ~= Try(E.GetStepIndex) then Try(E.Goto, i) end
    Try(E.Skip)
end

function Bridge.AnswerGroup(q, answer)
    local _, E = PS()
    if E and E.AnswerGroup then Try(E.AnswerGroup, q, answer) end
end

-- Mostrar u ocultar la ventana de Polestar (su flecha y sus marcas en el mapa siguen).
function Bridge.ShowPolestarWindow(show)
    local P = PS()
    if not (P and P.Set) then return false end
    Try(P.Set, "ui.shown", show and true or false)
    if show and P.Fire then Try(P.Fire, "SHOW_FRAME") end
    return true
end

function Bridge.PolestarWindowShown()
    local P = PS()
    return P and P.Get and Try(P.Get, "ui.shown") ~= false
end

-- Avisos de Polestar: cuando cambia el paso o la guía, la ventana se actualiza al momento.
local hooked = false
function Bridge.Hook()
    if hooked then return end
    local P = PS()
    if not (P and P.On) then return end
    for _, msg in ipairs({ "STEP_CHANGED", "GUIDE_CHANGED", "TABS_CHANGED" }) do
        Try(P.On, msg, function()
            if ns.RequestRefresh then ns.RequestRefresh() end
            if ns.Route and ns.Route.DrawPins then ns.Route.DrawPins() end
        end)
    end
    hooked = true
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(1, function()
        Bridge.Hook()
        if ns.RequestRefresh then ns.RequestRefresh() end
    end)
end)
