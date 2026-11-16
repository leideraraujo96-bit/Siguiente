-- Siguiente: mira tu nivel, tu zona y tus misiones y te dice qué hacer ahora.
-- Comandos: /sig (mostrar/ocultar), /sig ruta, /sig pasos, /sig flecha, /sig reset, /sig entrene, /sig debug

local _, ns = ...
ns = ns or {}
local db
ns.GetDB = function() return db end

-- Opciones por defecto (se cambian en Opciones > AddOns > Siguiente)
ns.DEFAULTS = {
    lockWindow = false,  -- no dejar arrastrar la ventana
    windowScale = 1,     -- tamaño de la ventana
    bgAlpha = 0.8,       -- opacidad del fondo
    maxTips = 4,         -- consejos que se muestran
    lockArrow = false,
    arrowScale = 1,
    mapPins = true,      -- números en el mapa del mundo
    miniPins = true,     -- números en el minimapa
    autoTravel = true,   -- llevarte a otra zona cuando rinda más XP por hora
    allowOrange = false, -- incluir misiones naranjas (más XP, más difíciles)
    allowGroup = false,  -- incluir misiones de grupo (élite)
    allowDungeon = false,-- incluir misiones de mazmorra
    listOpen = false,    -- lista completa de pasos abierta
    usePolestar = true,  -- si Polestar está instalado, usar su ruta
}
local eventFrame = CreateFrame("Frame")

-- Rama de talentos recomendada para subir de nivel yendo solo, por clase.
local CLASS_TIPS = {
    WARRIOR = { spec = "Armas (Arms), con arma a dos manos" },
    PALADIN = { spec = "Reprensión (Retribution), con arma a dos manos" },
    HUNTER  = { spec = "Dominio de bestias (Beast Mastery)" },
    ROGUE   = { spec = "Combate (Combat), con espadas" },
    PRIEST  = { spec = "Sombras (Shadow): Spirit Tap primero" },
    SHAMAN  = { spec = "Mejora (Enhancement), con arma a dos manos" },
    MAGE    = { spec = "Escarcha (Frost)" },
    WARLOCK = { spec = "Aflicción (Affliction)" },
    DRUID   = { spec = "Combate feral (Feral), en forma de oso o felino" },
}
ns.CLASS_TIPS = CLASS_TIPS

---------------------------------------------------------------------------
-- Zonas: [uiMapID] = { nivel mínimo, nivel máximo, facción, continente, nombre en inglés }
-- Facción: "A" Alianza, "H" Horda, "C" disputada. Continente: "K" Kalimdor, "E" Reinos del Este.
-- Los niveles son los de Classic; si Forever los cambió, se ajustan aquí.
---------------------------------------------------------------------------
local ZONES = {
    -- Alianza
    [1429] = { 1, 10, "A", "E", "Elwynn Forest" },
    [1426] = { 1, 10, "A", "E", "Dun Morogh" },
    [1438] = { 1, 10, "A", "K", "Teldrassil" },
    [1436] = { 10, 20, "A", "E", "Westfall" },
    [1432] = { 10, 20, "A", "E", "Loch Modan" },
    [1439] = { 10, 20, "A", "K", "Darkshore" },
    [1433] = { 15, 25, "A", "E", "Redridge Mountains" },
    [1437] = { 20, 30, "A", "E", "Wetlands" },
    -- Horda
    [1411] = { 1, 10, "H", "K", "Durotar" },
    [1412] = { 1, 10, "H", "K", "Mulgore" },
    [1420] = { 1, 10, "H", "E", "Tirisfal Glades" },
    [1413] = { 10, 25, "H", "K", "The Barrens" },
    [1421] = { 10, 20, "H", "E", "Silverpine Forest" },
    -- Disputadas
    [1431] = { 18, 30, "C", "E", "Duskwood" },
    [1442] = { 15, 27, "C", "K", "Stonetalon Mountains" },
    [1440] = { 18, 30, "C", "K", "Ashenvale" },
    [1424] = { 20, 30, "C", "E", "Hillsbrad Foothills" },
    [1441] = { 25, 35, "C", "K", "Thousand Needles" },
    [1416] = { 30, 40, "C", "E", "Alterac Mountains" },
    [1417] = { 30, 40, "C", "E", "Arathi Highlands" },
    [1443] = { 30, 40, "C", "K", "Desolace" },
    [1434] = { 30, 45, "C", "E", "Stranglethorn Vale" },
    [1445] = { 35, 45, "C", "K", "Dustwallow Marsh" },
    [1418] = { 35, 45, "C", "E", "Badlands" },
    [1435] = { 35, 45, "C", "E", "Swamp of Sorrows" },
    [1444] = { 40, 50, "C", "K", "Feralas" },
    [1425] = { 40, 50, "C", "E", "The Hinterlands" },
    [1446] = { 40, 50, "C", "K", "Tanaris" },
    [1427] = { 43, 50, "C", "E", "Searing Gorge" },
    [1447] = { 45, 55, "C", "K", "Azshara" },
    [1419] = { 45, 55, "C", "E", "Blasted Lands" },
    [1449] = { 48, 55, "C", "K", "Un'Goro Crater" },
    [1448] = { 48, 55, "C", "K", "Felwood" },
    [1428] = { 50, 58, "C", "E", "Burning Steppes" },
    [1422] = { 51, 58, "C", "E", "Western Plaguelands" },
    [1423] = { 53, 60, "C", "E", "Eastern Plaguelands" },
    [1452] = { 53, 60, "C", "K", "Winterspring" },
    [1451] = { 55, 60, "C", "K", "Silithus" },
}

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
local function Num(n)
    n = math.floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function Duration(seconds)
    if not seconds or seconds <= 0 or seconds ~= seconds then return "?" end
    local m = math.floor(seconds / 60 + 0.5)
    if m < 60 then return m .. " min" end
    return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

local function Color(hex, text) return "|cff" .. hex .. text .. "|r" end

local function ZoneName(id)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    if info and info.name then return info.name end
    return ZONES[id] and ZONES[id][5] or ("Mapa " .. tostring(id))
end

-- Sube por los mapas padre hasta encontrar una zona conocida.
local function CurrentZone()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local raw = C_Map.GetBestMapForUnit("player")
    local id = raw
    for _ = 1, 6 do
        if not id then break end
        if ZONES[id] then return id, raw end
        local info = C_Map.GetMapInfo(id)
        if not info or (info.mapType and info.mapType <= 2) then break end
        id = info.parentMapID
    end
    return nil, raw
end

local function MyFaction()
    local f = UnitFactionGroup("player")
    if f == "Alliance" then return "A" elseif f == "Horde" then return "H" end
    return nil
end

-- Rango "verde": las misiones por debajo de nivel - rango son grises (casi no dan XP).
local function GreenRange(level)
    if GetQuestGreenRange then
        local r = GetQuestGreenRange()
        if r and r > 0 then return r end
    end
    if level <= 5 then return 5
    elseif level <= 39 then return math.floor(level / 10) + 5
    elseif level <= 59 then return math.floor(level / 5) + 1
    end
    return 9
end

local DIFF = {
    rojo     = { "ff3030", 5 },
    naranja  = { "ff8040", 4 },
    amarillo = { "ffff00", 3 },
    verde    = { "40c040", 2 },
    gris     = { "909090", 1 },
}

local function Difficulty(questLevel, level)
    if not questLevel or questLevel <= 0 then return "amarillo" end
    local d = questLevel - level
    if d >= 5 then return "rojo"
    elseif d >= 3 then return "naranja"
    elseif d >= -2 then return "amarillo"
    elseif questLevel > level - GreenRange(level) then return "verde"
    end
    return "gris"
end

---------------------------------------------------------------------------
-- Diario de misiones
---------------------------------------------------------------------------
local function Objectives(questID, index)
    local out = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives and questID then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
            table.insert(out, { text = o.text, done = o.finished })
        end
    elseif GetNumQuestLeaderBoards and index then
        for j = 1, GetNumQuestLeaderBoards(index) or 0 do
            local text, _, done = GetQuestLogLeaderBoard(j, index)
            table.insert(out, { text = text, done = done })
        end
    end
    return out
end

local function ReadQuests()
    local quests = {}
    local n = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        n = C_QuestLog.GetNumQuestLogEntries() or 0
    elseif GetNumQuestLogEntries then
        n = GetNumQuestLogEntries() or 0
    end

    local header
    for i = 1, n do
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    header = info.title
                elseif not info.isHidden then
                    local id = info.questID
                    table.insert(quests, {
                        id = id,
                        title = info.title or "?",
                        level = info.level or 0,
                        header = header,
                        onMap = info.isOnMap,
                        group = (info.suggestedGroup or 0) > 1,
                        complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false,
                        failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) or false,
                        objectives = Objectives(id, i),
                    })
                end
            end
        elseif GetQuestLogTitle then
            local title, level, suggestedGroup, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if isHeader then
                header = title
            elseif title then
                table.insert(quests, {
                    id = questID,
                    title = title,
                    level = level or 0,
                    header = header,
                    group = (tonumber(suggestedGroup) or 0) > 1,
                    complete = isComplete == 1,
                    failed = isComplete == -1,
                    objectives = Objectives(nil, i),
                })
            end
        end
    end
    return quests
end

---------------------------------------------------------------------------
-- XP: XP por hora y XP por muerte
---------------------------------------------------------------------------
local session = { start = nil, gained = 0, lastXP = nil, lastMax = nil, kills = {} }

local function ResetSession()
    session.start = GetTime()
    session.gained = 0
    session.lastXP = UnitXP("player")
    session.lastMax = UnitXPMax("player")
end

local function OnXPUpdate()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if session.lastXP then
        local delta
        if cur >= session.lastXP then
            delta = cur - session.lastXP
        else -- subiste de nivel
            delta = (session.lastMax - session.lastXP) + cur
        end
        session.gained = session.gained + math.max(delta, 0)
    end
    session.lastXP, session.lastMax = cur, max
end

-- Construye un patrón a partir del texto del juego "%s muere, ganas %d de experiencia",
-- así funciona en cualquier idioma.
local killPattern
do
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON
    if fmt then
        fmt = fmt:gsub("%%%d%$", "%%")
        local cut = fmt:find("%%d")
        if cut then
            fmt = fmt:sub(1, cut + 1)
            fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            fmt = fmt:gsub("%%s", "(.-)")
            fmt = fmt:gsub("%%d", "([%%d%%.,]+)")
            killPattern = "^" .. fmt
        end
    end
end

local function OnXPMessage(msg)
    if not killPattern or not msg then return end
    -- El número siempre es la última captura (cortamos el patrón justo después de %d).
    local caps = { msg:match(killPattern) }
    local num = caps[#caps]
    local xp = num and tonumber((num:gsub("%D", "")))
    if xp and xp > 0 then
        table.insert(session.kills, xp)
        if #session.kills > 15 then table.remove(session.kills, 1) end
    end
end

local function AvgKillXP()
    if #session.kills == 0 then return nil end
    local sum = 0
    for _, v in ipairs(session.kills) do sum = sum + v end
    return sum / #session.kills
end

---------------------------------------------------------------------------
-- Inventario
---------------------------------------------------------------------------
local function FreeBagSlots()
    local free = 0
    for bag = 0, 4 do
        local fs, bagType
        if C_Container and C_Container.GetContainerNumFreeSlots then
            fs, bagType = C_Container.GetContainerNumFreeSlots(bag)
        elseif GetContainerNumFreeSlots then
            fs, bagType = GetContainerNumFreeSlots(bag)
        end
        if fs and (bagType == nil or bagType == 0) then free = free + fs end
    end
    return free
end

local function LowestDurability()
    local lowest = 1
    for slot = 1, 19 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then lowest = math.min(lowest, cur / max) end
    end
    return lowest
end

---------------------------------------------------------------------------
-- El cerebro: arma la lista de qué hacer
---------------------------------------------------------------------------
local function QuestLine(q, level)
    local d = Difficulty(q.level, level)
    local t = Color(DIFF[d][1], "[" .. (q.level > 0 and q.level or "?") .. "] " .. q.title)
    if q.group then t = t .. Color("ff8040", " (grupo)") end
    return t
end

local function FirstPending(q)
    for _, o in ipairs(q.objectives) do
        if not o.done and o.text and o.text ~= "" then return o.text end
    end
    if #q.objectives == 0 then return "lee la misión: habla con alguien o ve a un lugar" end
    return nil
end

local function BuildAdvice()
    local level = UnitLevel("player")
    local faction = MyFaction()
    local zoneID, rawMap = CurrentZone()
    local zoneText = GetRealZoneText and GetRealZoneText() or ""
    local zoneName = zoneID and ZoneName(zoneID) or zoneText
    local quests = ReadQuests()
    local tips = {}

    local function Add(prio, text, isQuest) table.insert(tips, { prio = prio, text = text, isQuest = isQuest }) end

    local function InThisZone(q)
        return q.onMap or (q.header and (q.header == zoneText or q.header == zoneName))
    end

    -- 1. Misiones listas para entregar
    local ready, readyHere = {}, 0
    for _, q in ipairs(quests) do
        if q.complete then
            table.insert(ready, q)
            if InThisZone(q) then readyHere = readyHere + 1 end
        end
    end
    if #ready > 0 then
        local lines = {}
        for i = 1, math.min(3, #ready) do
            local q = ready[i]
            lines[i] = "   - " .. q.title .. (q.header and Color("909090", " (" .. q.header .. ")") or "")
        end
        if #ready > 3 then table.insert(lines, "   - y " .. (#ready - 3) .. " más") end
        Add(readyHere > 0 and 110 or 100,
            Color("40ff40", "Entrega " .. #ready .. " misión(es) completa(s):") .. "\n" .. table.concat(lines, "\n"), true)
    end

    -- 2. Misiones fallidas
    for _, q in ipairs(quests) do
        if q.failed then Add(96, Color("ff3030", "Abandona (fallida): ") .. q.title) end
    end

    -- 3. Entrenador (en Classic hay hechizos nuevos cada 2 niveles)
    if db.lastTrainer and level >= 2 and level % 2 == 0 and db.lastTrainer < level then
        Add(95, Color("ffd100", "Visita a tu entrenador:") .. " tienes hechizos nuevos de nivel " .. level ..
            ". (Cuando vayas se borra solo, o escribe /sig entrene)")
    end

    -- 4. Talentos sin usar (con la rama recomendada para subir solo según tu clase)
    local _, class = UnitClass("player")
    local info = CLASS_TIPS[class]
    if UnitCharacterPoints then
        local pts = UnitCharacterPoints("player")
        if pts and pts > 0 then
            Add(90, Color("ffd100", "Tienes " .. pts .. " punto(s) de talento sin usar.") ..
                (info and (" Para subir solo: " .. info.spec .. ".") or ""))
        end
    end

    -- 5. Bolsas y reparación
    local free = FreeBagSlots()
    if free <= 2 then
        Add(85, Color("ffd100", "Bolsas casi llenas (" .. free .. " libres):") .. " vende la basura en el próximo vendedor.")
    end
    if LowestDurability() < 0.25 then
        Add(85, Color("ff3030", "Tu equipo está por romperse:") .. " repara en un herrero o vendedor.")
    end

    -- 6. Cosas de cada clase
    local hasRangedSlot = INVSLOT_RANGED and _G.CharacterRangedSlot
    local busy = (InCombatLockdown and InCombatLockdown()) or (IsMounted and IsMounted())
        or (UnitOnTaxi and UnitOnTaxi("player"))
    if (class == "PRIEST" or class == "MAGE" or class == "WARLOCK") and level >= 5 and hasRangedSlot
        and not GetInventoryItemID("player", INVSLOT_RANGED) then
        Add(80, Color("ffd100", "Equipa una varita:") .. " es daño gratis sin gastar maná (compra o pide a un encantador).")
    end
    if class == "HUNTER" then
        local ammo = GetInventoryItemCount and GetInventoryItemCount("player", 0) or nil
        if hasRangedSlot and GetInventoryItemID("player", INVSLOT_RANGED) and ammo and ammo < 200 then
            Add(84, Color("ff8040", "Te quedan " .. ammo .. " flechas/balas:") .. " compra munición en el próximo vendedor.")
        end
        if level >= 10 and not UnitExists("pet") and not busy then
            Add(82, Color("ffd100", "Llama a tu mascota") .. " (o doma una): hace mucho daño y aguanta los golpes por ti.")
        elseif UnitExists("pet") and GetPetHappiness and GetPetHappiness() == 1 then
            Add(82, Color("ff8040", "Tu mascota está triste:") .. " dale de comer; si no, pega menos y puede abandonarte.")
        end
    end
    if class == "WARLOCK" and level >= 2 and not UnitExists("pet") and not busy then
        Add(82, Color("ffd100", "Invoca a tu demonio:") .. " el diablillo al principio y el abisario (Voidwalker) desde nivel 10 para ir solo.")
    end
    if class == "ROGUE" and level >= 20 and GetWeaponEnchantInfo then
        local hasMain = GetWeaponEnchantInfo()
        if not hasMain then
            Add(78, Color("ffd100", "Ponle veneno a tus armas") .. " (desde nivel 20, tras la misión de venenos): mucho más daño.")
        end
    end

    -- 7. Zona actual vs tu nivel
    local zoneOK, zoneWarn = true, nil
    if zoneID then
        local z = ZONES[zoneID]
        if level > z[2] then
            zoneOK = false
            zoneWarn = Color("ff8040", zoneName .. " ya es baja para ti") .. " (" .. z[1] .. "-" .. z[2] .. "). Aquí casi no ganas XP."
        elseif level < z[1] - 2 then
            zoneOK = false
            zoneWarn = Color("ff3030", zoneName .. " es peligrosa a tu nivel") .. " (" .. z[1] .. "-" .. z[2] .. ")."
        end
    end

    -- 8. Misiones pendientes en esta zona (las que más XP dan primero)
    local here = {}
    for _, q in ipairs(quests) do
        if not q.complete and not q.failed and InThisZone(q) then
            local d = Difficulty(q.level, level)
            if d ~= "gris" and d ~= "rojo" then table.insert(here, q) end
        end
    end
    table.sort(here, function(a, b) return (a.level or 0) > (b.level or 0) end)
    if #here > 0 then
        local lines = {}
        for i = 1, math.min(3, #here) do
            local q = here[i]
            local pend = FirstPending(q)
            lines[i] = "   - " .. QuestLine(q, level) .. (pend and ("\n       " .. Color("c0c0c0", pend)) or "")
        end
        Add(70, Color("ffffff", "Haz ahora (en esta zona):") .. "\n" .. table.concat(lines, "\n"), true)
    end

    -- 9. Pocas misiones: busca más
    local maxQ = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
        or MAX_QUESTLOG_QUESTS or 20
    if #here < 2 and zoneOK then
        Add(60, Color("ffd100", "Busca misiones nuevas:") .. " tienes " .. #quests .. "/" .. maxQ ..
            " en el diario. Mira los ! amarillos en el mapa (Questie).", true)
    end

    -- 10. Zonas recomendadas
    if not zoneOK or #here == 0 then
        local cont = zoneID and ZONES[zoneID][4]
        local options = {}
        for id, z in pairs(ZONES) do
            if id ~= zoneID and (z[3] == "C" or z[3] == faction) and level >= z[1] - 1 and level <= z[2] - 2 then
                local score = math.abs(level - (z[1] + z[2]) / 2) + ((cont and z[4] ~= cont) and 4 or 0)
                table.insert(options, { id = id, score = score })
            end
        end
        table.sort(options, function(a, b) return a.score < b.score end)
        local names = {}
        for i = 1, math.min(3, #options) do
            local z = ZONES[options[i].id]
            names[i] = ZoneName(options[i].id) .. " (" .. z[1] .. "-" .. z[2] .. ")"
        end
        local list = #names > 0 and (Color("80c0ff", "Zonas buenas para tu nivel: ") .. table.concat(names, ", ")) or nil
        if zoneWarn then
            Add(87, zoneWarn .. (list and ("\n   " .. list) or ""))
        elseif list then
            Add(50, list)
        end
    elseif zoneWarn then
        Add(87, zoneWarn)
    end

    -- 11. Misiones difíciles y grises
    local red, gray = {}, {}
    for _, q in ipairs(quests) do
        if not q.complete then
            local d = Difficulty(q.level, level)
            if d == "rojo" then table.insert(red, q.title)
            elseif d == "gris" then table.insert(gray, q.title) end
        end
    end
    if #red > 0 then
        Add(40, Color("ff3030", "Muy difíciles por ahora (" .. #red .. "):") .. " " .. table.concat(red, ", ", 1, math.min(2, #red)) ..
            ". Déjalas para después o busca grupo.")
    end
    if #gray > 0 then
        Add(#quests >= maxQ - 2 and 88 or 35, Color("909090", "Casi no dan XP (" .. #gray .. "):") .. " " ..
            table.concat(gray, ", ", 1, math.min(2, #gray)) .. ". Hazlas solo si te quedan de paso, o abandónalas.")
    end

    table.sort(tips, function(a, b) return a.prio > b.prio end)
    return tips, zoneID, rawMap
end

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------
local WIDTH = 330
local frame = CreateFrame("Frame", "SiguienteFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(WIDTH, 120)
frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if db and db.opt.lockWindow and not ns.moveMode then return end
    self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.pos = { p, rp, x, y }
end)
if frame.SetBackdrop then
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
end
frame:Hide()

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)
close:SetScale(0.8)
close:SetScript("OnClick", function()
    frame:Hide()
    db.hidden = true
    print("|cffffd100Siguiente|r oculto. Escribe /sig para volver a verlo.")
end)

-- Engranaje: abre Opciones > AddOns > Siguiente
local gear = CreateFrame("Button", nil, frame)
gear:SetSize(14, 14)
gear:SetPoint("RIGHT", close, "LEFT", 2, 0)
gear:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
gear:SetScript("OnClick", function() if ns.Options then ns.Options.Open() end end)
gear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Opciones de Siguiente")
    GameTooltip:Show()
end)
gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 10, -9)
title:SetText("Siguiente")

local stats = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stats:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
stats:SetWidth(WIDTH - 20)
stats:SetJustifyH("LEFT")

local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
body:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -8)
body:SetWidth(WIDTH - 20)
body:SetJustifyH("LEFT")
if body.SetSpacing then body:SetSpacing(2) end

local function StatsText()
    local level = UnitLevel("player")
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if level >= maxLevel then return "Nivel " .. level .. " (máximo)" end

    local cur, max = UnitXP("player"), UnitXPMax("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local line1 = string.format("Nivel %d  ·  %.1f%%  ·  faltan %s XP", level, max > 0 and cur / max * 100 or 0, Num(max - cur))
    if rested and rested > 0 then
        line1 = line1 .. "  ·  " .. Color("80c0ff", "descanso " .. Num(rested))
    end

    local parts = {}
    local elapsed = session.start and (GetTime() - session.start) or 0
    if elapsed > 120 and session.gained > 0 then
        local perHour = session.gained / elapsed * 3600
        table.insert(parts, "XP/h " .. Num(perHour))
        table.insert(parts, "sube en ~" .. Duration((max - cur) / perHour * 3600))
    end
    local avg = AvgKillXP()
    if avg then
        table.insert(parts, "~" .. Num(math.ceil((max - cur) / avg)) .. " muertes")
    end
    if #parts > 0 then return line1 .. "\n" .. table.concat(parts, "  ·  ") end
    return line1
end

-- Datos de experiencia para el panel (barra y su tooltip)
function ns.XPInfo()
    local level = UnitLevel("player")
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if level >= maxLevel then return { level = level, max = true } end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local info = { level = level, cur = cur, maxXP = max, pct = max > 0 and cur / max or 0,
        restedPct = (max > 0 and rested) and rested / max or 0, rested = rested, toGo = max - cur }
    local elapsed = session.start and (GetTime() - session.start) or 0
    if elapsed > 120 and session.gained > 0 then
        info.perHour = session.gained / elapsed * 3600
        info.eta = Duration((max - cur) / info.perHour * 3600)
    end
    local avg = AvgKillXP()
    if avg then info.kills = math.ceil((max - cur) / avg) end
    return info
end

function ns.XPLines()
    local i = ns.XPInfo()
    if i.max then return { "Nivel máximo" } end
    local out = { string.format("%s / %s XP (faltan %s)", Num(i.cur), Num(i.maxXP), Num(i.toGo)) }
    if i.rested and i.rested > 0 then out[#out + 1] = "Descanso: " .. Num(i.rested) .. " (doble XP al matar)" end
    if i.perHour then out[#out + 1] = "XP por hora: " .. Num(i.perHour) .. " · subes en ~" .. i.eta end
    if i.kills then out[#out + 1] = "Enemigos para subir: ~" .. Num(i.kills) end
    return out
end

local function Refresh()
    if not db or not frame:IsShown() then return end
    if ns.Panel and ns.Panel.ready then
        ns.Panel.Render(BuildAdvice())
        return
    end
    stats:SetText(StatsText())
    local tips = BuildAdvice()
    local lines = {}
    local routeText = nil
    local maxTips = db.opt.maxTips or 4
    if routeText then
        lines[1] = routeText
        if maxTips > 0 then
            lines[2] = " "
            lines[3] = Color("ffd100", "CONSEJOS")
        end
    end
    local n = 0
    for _, tip in ipairs(tips) do
        -- Con ruta, los consejos de misiones ya están en los pasos: dejamos los demás.
        if n >= maxTips then break end
        if not (routeText and tip.isQuest) then
            n = n + 1
            lines[#lines + 1] = Color("ffd100", "-") .. " " .. tip.text
            if n >= maxTips then break end
        end
    end
    if n == 0 and lines[3] then
        lines[2], lines[3] = nil, nil -- sin consejos: no mostrar el título
    end
    if n == 0 and not routeText then lines[#lines + 1] = "Todo en orden. Sigue matando y haciendo misiones." end
    body:SetText(table.concat(lines, "\n"))
    local h = 9 + title:GetStringHeight() + 5 + stats:GetStringHeight() + 8 + body:GetStringHeight() + 12
    frame:SetHeight(h)
end

local pending = false
local function RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.4, function()
        pending = false
        Refresh()
    end)
end

---------------------------------------------------------------------------
-- Flecha: apunta al objetivo o al NPC de entrega más cercano.
-- Las ubicaciones salen de la base de datos de Questie (no la modificamos, solo leemos).
---------------------------------------------------------------------------
local Arrow = { target = nil, status = nil, nextScan = 0, skip = {} }
local questieCache

-- La librería de mapas de Questie (HereBeDragons). Desde Questie 12.9 es un módulo interno ("HBD"/"HBDPins");
-- antes era una librería LibStub ("HereBeDragonsQuestie-2.0"). Aceptamos las dos.
function ns.QuestieHBD()
    local m = QuestieLoader and QuestieLoader:ImportModule("HBD")
    if m and m.GetWorldVector and m.GetPlayerWorldPosition then return m end
    return LibStub and LibStub("HereBeDragonsQuestie-2.0", true) or nil
end

function ns.QuestieHBDPins()
    local m = QuestieLoader and QuestieLoader:ImportModule("HBDPins")
    if m and m.AddWorldMapIconMap then return m end
    return LibStub and LibStub("HereBeDragonsQuestie-Pins-2.0", true) or nil
end

local function GetQuestie()
    if questieCache then return questieCache end
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local HBD = ns.QuestieHBD()
    if not HBD then return nil end
    local q = {
        HBD = HBD,
        TrackerData = QuestieLoader:ImportModule("TrackerData"),
        Eligibility = QuestieLoader:ImportModule("TrackerMapEligibility"),
        Distance = QuestieLoader:ImportModule("DistanceUtils"),
        ZoneDB = QuestieLoader:ImportModule("ZoneDB"),
    }
    if not (q.TrackerData.GetQuest and q.TrackerData.RefreshQuest and q.Eligibility.GetCapabilities
        and q.Distance.GetNearestSpawnForQuest and q.ZoneDB.GetUiMapIdByAreaId) then
        return nil -- Questie todavía cargando, o cambió por dentro
    end
    questieCache = q
    return q
end

-- Dónde está lo próximo de esta misión (objetivo pendiente o NPC de entrega), en coordenadas del mundo.
local function LocateQuest(Q, questID)
    local ok, spawn, areaId, name = pcall(function()
        local tq = Q.TrackerData.GetQuest(questID) or Q.TrackerData.RefreshQuest(questID)
        if not tq then return nil end
        local caps = Q.Eligibility.GetCapabilities(tq)
        if not (caps and caps.canNavigateQuest) then return nil end
        return Q.Distance.GetNearestSpawnForQuest(tq)
    end)
    if not ok or not spawn or not areaId then return nil end
    local uiMap = Q.ZoneDB:GetUiMapIdByAreaId(areaId)
    if not uiMap then return nil end
    local wx, wy, inst = Q.HBD:GetWorldCoordinatesFromZone(spawn[1] / 100, spawn[2] / 100, uiMap)
    if not wx then return nil end
    return { x = wx, y = wy, inst = inst, uiMap = uiMap, mapX = spawn[1], mapY = spawn[2], name = name }
end

local function PickTarget()
    -- Con la ruta activa, la flecha sigue el paso actual.
    local route = ns.Route
    if route and route.enabled then
        Arrow.target = route.ArrowTarget()
        Arrow.status = (not Arrow.target) and (route.status or "Calculando la ruta...") or nil
        return
    end
    local Q = GetQuestie()
    if not Q then
        Arrow.target, Arrow.status = nil, "La flecha necesita Questie activado."
        return
    end
    local px, py, pinst = Q.HBD:GetPlayerWorldPosition()
    local level = UnitLevel("player")
    local now = GetTime()
    local best, bestScore
    for _, q in ipairs(ReadQuests()) do
        local skipped = Arrow.skip[q.id] and Arrow.skip[q.id] > now
        local d = Difficulty(q.level, level)
        if q.id and not q.failed and not skipped and (q.complete or (d ~= "rojo" and not q.group)) then
            local loc = LocateQuest(Q, q.id)
            if loc then
                local dist = 1e9
                if px and loc.inst == pinst then
                    dist = ((loc.x - px) ^ 2 + (loc.y - py) ^ 2) ^ 0.5
                end
                -- Lo más cercano primero; entregar pesa más y las grises pesan menos.
                local score = dist * (q.complete and 0.6 or 1) * (d == "gris" and 3 or 1)
                if not bestScore or score < bestScore then
                    best, bestScore = { quest = q, loc = loc }, score
                end
            end
        end
    end
    Arrow.target = best
    Arrow.status = (not best) and "Nada a dónde ir: toma misiones nuevas (! amarillos)." or nil
end

local arrowFrame = CreateFrame("Button", "SiguienteArrow", UIParent)
arrowFrame:SetSize(60, 60)
arrowFrame:SetPoint("TOP", UIParent, "TOP", 0, -110)
arrowFrame:SetMovable(true)
arrowFrame:EnableMouse(true)
arrowFrame:SetClampedToScreen(true)
arrowFrame:RegisterForDrag("LeftButton")
arrowFrame:RegisterForClicks("RightButtonUp")
arrowFrame:SetScript("OnDragStart", function(self)
    if db and db.opt.lockArrow and not ns.moveMode then return end
    self:StartMoving()
end)
arrowFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.arrowPos = { p, rp, x, y }
end)
-- Clic derecho: saltar esta misión por 10 minutos y apuntar a la siguiente.
arrowFrame:SetScript("OnClick", function()
    if ns.Route and ns.Route.enabled then
        ns.Route.SkipGroup((ns.Route.CurrentGroup()))
    elseif Arrow.target then
        Arrow.skip[Arrow.target.quest.id] = GetTime() + 600
        print("|cffffd100Siguiente|r: salto \"" .. Arrow.target.quest.title .. "\" por 10 minutos.")
    end
    Arrow.nextScan = 0
end)
arrowFrame:Hide()

local arrowTex = arrowFrame:CreateTexture(nil, "ARTWORK")
arrowTex:SetAllPoints()
arrowTex:SetTexture("Interface\\Minimap\\MinimapArrow")

local arrowLabel = arrowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
arrowLabel:SetPoint("TOP", arrowFrame, "BOTTOM", 0, -2)
arrowLabel:SetWidth(260)
arrowLabel:SetJustifyH("CENTER")

local function UpdateArrow()
    local t = Arrow.target
    if not t then
        arrowTex:Hide()
        arrowLabel:SetText(Color("c0c0c0", Arrow.status or ""))
        return
    end
    local q, loc = t.quest, t.loc
    local heading = t.heading or ((q.complete and Color("40ff40", "Entregar: ") or "") .. q.title)
    if not loc then
        arrowTex:Hide()
        arrowLabel:SetText(heading .. "\n" .. Color("c0c0c0", "Sin ubicación conocida: lee la misión."))
        return
    end
    local who = loc.name and loc.name ~= "" and ("\n" .. Color("ffffff", loc.name)) or ""

    local Q = GetQuestie()
    local px, py, pinst
    if Q then px, py, pinst = Q.HBD:GetPlayerWorldPosition() end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not px or not facing or pinst ~= loc.inst then
        arrowTex:Hide()
        arrowLabel:SetText(heading .. who .. "\n" ..
            Color("c0c0c0", string.format("en %s (%.0f, %.0f)", ZoneName(loc.uiMap), loc.mapX, loc.mapY)))
        return
    end

    local angle, dist = Q.HBD:GetWorldVector(pinst, px, py, loc.x, loc.y)
    if not angle then return end
    arrowTex:Show()
    arrowTex:SetRotation(angle - facing)
    if dist < 15 then
        arrowTex:SetVertexColor(0.3, 1, 0.3)
    else
        arrowTex:SetVertexColor(1, 0.82, 0)
    end
    arrowLabel:SetText(heading .. who .. "\n" .. Color("c0c0c0", Num(dist) .. " yardas"))
end

ns.ReadQuests = ReadQuests
ns.Difficulty = Difficulty
ns.ZoneName = ZoneName
ns.Color = Color
ns.Num = Num
ns.GetQuestie = GetQuestie
ns.LocateQuest = LocateQuest
ns.ArrowRescan = function() Arrow.nextScan = 0 end
ns.RequestRefresh = RequestRefresh
ns.Refresh = Refresh
ns.mainFrame = frame
ns.arrowFrame = arrowFrame

-- Tamaño y fondo según las opciones
function ns.ApplyLook()
    local o = db.opt
    frame:SetScale(o.windowScale)
    if frame.SetBackdropColor then
        frame:SetBackdropColor(0, 0, 0, o.bgAlpha)
        frame:SetBackdropBorderColor(1, 1, 1, math.min(1, o.bgAlpha + 0.2))
    end
    arrowFrame:SetScale(o.arrowScale)
end

function ns.SetWindowShown(on)
    db.hidden = not on
    if on then
        frame:Show()
        Refresh()
    else
        frame:Hide()
    end
end

function ns.SetArrowShown(on)
    db.arrow = on
    if on then
        arrowFrame:Show()
        Arrow.nextScan = 0
    else
        arrowFrame:Hide()
    end
end

function ns.ResetPositions()
    db.pos, db.arrowPos = nil, nil
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
    arrowFrame:ClearAllPoints()
    arrowFrame:SetPoint("TOP", UIParent, "TOP", 0, -110)
end

local arrowAcc = 0
arrowFrame:SetScript("OnUpdate", function(self, elapsed)
    arrowAcc = arrowAcc + elapsed
    if arrowAcc < 0.05 then return end
    arrowAcc = 0
    -- Con la ruta de Polestar manda su flecha (camina por caminos reales): la nuestra se aparta.
    if ns.Bridge and ns.Bridge.Active() and not ns.moveMode then
        arrowTex:Hide()
        arrowLabel:SetText("")
        self:EnableMouse(false)
        return
    end
    self:EnableMouse(true)
    local now = GetTime()
    if now >= Arrow.nextScan then
        Arrow.nextScan = now + 3
        PickTarget()
    end
    UpdateArrow()
end)

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local EVENTS = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY",
    "PLAYER_EQUIPMENT_CHANGED", "CHARACTER_POINTS_CHANGED", "TRAINER_SHOW", "CHAT_MSG_COMBAT_XP_GAIN",
    "UPDATE_EXHAUSTION",
}
for _, ev in ipairs(EVENTS) do pcall(eventFrame.RegisterEvent, eventFrame, ev) end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "Siguiente" then return end
        SiguienteDB = SiguienteDB or {}
        db = SiguienteDB
        db.route = db.route or { enabled = true, done = 0 }
        db.opt = db.opt or {}
        for k, v in pairs(ns.DEFAULTS) do
            if db.opt[k] == nil then db.opt[k] = v end
        end
        ns.ApplyLook()
        if ns.Options then ns.Options.Setup() end
        if ns.Panel and not ns.Panel.ready then
            ns.Panel.Init(frame, title, stats, body)
            ns.Panel.ready = true
        end
        if ns.Route then ns.Route.enabled = db.route.enabled ~= false end
        if db.pos then
            frame:ClearAllPoints()
            frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
        end
        if db.arrowPos then
            arrowFrame:ClearAllPoints()
            arrowFrame:SetPoint(db.arrowPos[1], UIParent, db.arrowPos[2], db.arrowPos[3], db.arrowPos[4])
        end
        return
    end
    if not db then return end

    if event == "PLAYER_ENTERING_WORLD" then
        if not session.start then ResetSession() end
        -- Primera vez: suponemos que ya entrenaste lo de tu nivel actual.
        if not db.lastTrainer then db.lastTrainer = UnitLevel("player") end
        if not db.hidden then frame:Show() end
        if db.arrow ~= false then arrowFrame:Show() end
    elseif event == "QUEST_LOG_UPDATE" then
        Arrow.nextScan = math.min(Arrow.nextScan, GetTime() + 0.5)
    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        OnXPMessage(arg1)
    elseif event == "TRAINER_SHOW" then
        db.lastTrainer = UnitLevel("player")
    end
    RequestRefresh()
end)

C_Timer.NewTicker(5, Refresh)

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------
SLASH_SIGUIENTE1 = "/sig"
SLASH_SIGUIENTE2 = "/siguiente"
SlashCmdList.SIGUIENTE = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "opciones" or msg == "config" or msg == "op" then
        ns.Options.Open()
    elseif msg == "mover" then
        ns.Options.SetMoveMode(not ns.moveMode)
    elseif msg == "reset" then
        ns.ResetPositions()
        wipe(Arrow.skip)
        ResetSession()
        wipe(session.kills)
        print("|cffffd100Siguiente|r: posición y XP/h reiniciados.")
    elseif msg == "ruta" then
        local on = not ns.Route.enabled
        ns.Route.SetEnabled(on)
        print("|cffffd100Siguiente|r: ruta paso a paso " .. (on and "activada." or "desactivada (la flecha vuelve a lo más cercano)."))
    elseif msg == "ruta nueva" then
        ns.Route.Reset()
        print("|cffffd100Siguiente|r: ruta recalculada desde el paso 1.")
    elseif msg == "pasos" then
        ns.Route.PrintList()
    elseif msg == "flecha" then
        local on = not arrowFrame:IsShown()
        ns.SetArrowShown(on)
        print("|cffffd100Siguiente|r: flecha " .. (on and "visible. Arrástrala para moverla, clic derecho para saltar un paso." or "oculta."))
    elseif msg == "entrene" then
        db.lastTrainer = UnitLevel("player")
        print("|cffffd100Siguiente|r: entrenador marcado como visitado.")
    elseif msg == "debug" then
        local zoneID, raw = CurrentZone()
        local info = raw and C_Map.GetMapInfo(raw)
        print("|cffffd100Siguiente|r debug:")
        print("  mapa actual:", raw, info and info.name, "tipo:", info and info.mapType, "padre:", info and info.parentMapID)
        print("  zona reconocida:", zoneID and (zoneID .. " " .. ZoneName(zoneID)) or "ninguna")
        print("  texto de zona:", GetRealZoneText and GetRealZoneText())
        print("  patrón de muertes:", killPattern or "no disponible", " muertes registradas:", #session.kills)
        print("  misiones en el diario:", #ReadQuests())
        print("  Questie conectado:", GetQuestie() and "sí" or "no",
            " flecha apunta a:", Arrow.target and Arrow.target.quest.title or (Arrow.status or "nada"))
        if ns.Bridge then
            local on, why = ns.Bridge.Status()
            print("  ruta de Polestar:", on and ("|cff40ff40sí|r — " .. why) or ("|cffff8040no|r — " .. why))
        end
        local missing = ns.Route and ns.Route.DebugMissing and ns.Route.DebugMissing() or {}
        print("  pasos sin lugar conocido:", #missing)
        for i = 1, math.min(5, #missing) do print("    " .. missing[i]) end
    elseif msg == "ayuda" or msg == "help" then
        print("|cffffd100Siguiente|r comandos:")
        print("  /sig — mostrar u ocultar la ventana")
        print("  /sig opciones — abrir las opciones (también en Opciones > AddOns > Siguiente)")
        print("  /sig mover — modo mover: arrastra la ventana y la flecha, escribe /sig mover otra vez para terminar")
        print("  /sig pasos — próximos 30 pasos de la ruta")
        print("  /sig ruta — activar o desactivar la ruta;  /sig ruta nueva — empezar desde el paso 1")
        print("  /sig flecha — mostrar u ocultar la flecha;  /sig reset — volver todo a su lugar")
    else
        ns.SetWindowShown(not frame:IsShown())
    end
end

-- Botón de addons junto al minimapa (## AddonCompartmentFunc en el .toc)
function Siguiente_OnCompartmentClick(_, button)
    if button == "RightButton" then
        ns.SetWindowShown(not frame:IsShown())
    else
        ns.Options.Open()
    end
end

function Siguiente_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Siguiente")
    GameTooltip:AddLine("Clic: opciones", 1, 1, 1)
    GameTooltip:AddLine("Clic derecho: mostrar u ocultar la ventana", 1, 1, 1)
    GameTooltip:Show()
end

function Siguiente_OnCompartmentLeave()
    GameTooltip:Hide()
end
