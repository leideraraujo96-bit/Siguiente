-- Panel: la ventana de Siguiente como guía. Paso actual grande, los siguientes debajo,
-- lista completa con un clic y consejos como iconos chicos.

local _, ns = ...
local Panel = {}
ns.Panel = Panel

local WIDTH = 330          -- ancho de la ventana
local INNER = WIDTH - 20   -- ancho del contenido
local COMPACT_ROWS = 3     -- pasos que se ven debajo del actual
local LIST_ROWS = 12       -- pasos visibles con la lista abierta (con rueda del mouse)
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local GLYPH = { accept = "!", turnin = "?", ["do"] = "*", travel = "»" }

-- Icono de cada consejo (se reconoce por el texto). "ruta" = consejos que ya cubre la ruta.
local TIP_ICONS = {
    { "entrenador", "Interface\\Icons\\INV_Misc_Book_11" },
    { "talento", "Interface\\Icons\\Ability_Marksmanship" },
    { "Bolsas", "Interface\\Icons\\INV_Misc_Bag_08" },
    { "romperse", "Interface\\Icons\\Trade_BlackSmithing" },
    { "varita", "Interface\\Icons\\INV_Wand_01" },
    { "flechas", "Interface\\Icons\\INV_Ammo_Arrow_02" },
    { "mascota", "Interface\\Icons\\Ability_Hunter_BeastCall" },
    { "demonio", "Interface\\Icons\\Spell_Shadow_SummonImp" },
    { "veneno", "Interface\\Icons\\Ability_Poisons" },
    { "fallida", "Interface\\Icons\\INV_Misc_QuestionMark" },
    { "es baja para ti", "ruta" },
    { "es peligrosa", "ruta" },
    { "Zonas buenas", "ruta" },
    { "Muy difíciles", "ruta" },
    { "Casi no dan XP", "ruta" },
}

local function TipIcon(tip)
    if tip.isQuest then return "ruta" end
    for _, pair in ipairs(TIP_ICONS) do
        if tip.text:find(pair[1], 1, true) then return pair[2] end
    end
    return "Interface\\Icons\\INV_Misc_Note_01"
end

local function Hex(h) return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 end

local P = {}          -- piezas de la ventana
local rows, tipButtons = {}, {}
local scroll = 0

---------------------------------------------------------------------------
-- Piezas
---------------------------------------------------------------------------
local function Circle(parent, size)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(size, size)
    c.edge = c:CreateTexture(nil, "BACKGROUND")
    c.edge:SetPoint("TOPLEFT", -1, 1)
    c.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    c.edge:SetTexture(CIRCLE)
    c.edge:SetVertexColor(0, 0, 0, 0.9)
    c.bg = c:CreateTexture(nil, "ARTWORK")
    c.bg:SetAllPoints()
    c.bg:SetTexture(CIRCLE)
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:SetPoint("CENTER", 0, 0)
    c.text:SetTextColor(0, 0, 0)
    if c.text.SetShadowOffset then c.text:SetShadowOffset(0, 0) end
    c.check = c:CreateTexture(nil, "OVERLAY")
    c.check:SetAllPoints()
    c.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    c.check:Hide()
    return c
end

local function StyleCircle(c, kind, label, done)
    local rgb = ns.Route.KIND_RGB[kind] or { 0.6, 0.6, 0.6 }
    if done then
        c.bg:SetVertexColor(0.25, 0.25, 0.25)
        c.text:SetText("")
        c.check:Show()
    else
        c.bg:SetVertexColor(rgb[1], rgb[2], rgb[3])
        c.text:SetText(label)
        c.check:Hide()
    end
end

local function GetRow(i, parent)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent)
    r:SetWidth(INNER)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.82, 0, 0.12)
    r.hl:Hide()
    r.line = r:CreateTexture(nil, "BORDER")
    r.line:SetPoint("TOPLEFT", 0, 0)
    r.line:SetPoint("TOPRIGHT", 0, 0)
    r.line:SetHeight(1)
    r.line:SetColorTexture(1, 1, 1, 0.08)
    r.circle = Circle(r, 18)
    r.circle:SetPoint("TOPLEFT", 4, -4)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.title:SetPoint("TOPLEFT", 28, -5)
    r.title:SetWidth(INNER - 32)
    r.title:SetJustifyH("LEFT")
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -1)
    r.sub:SetWidth(INNER - 32)
    r.sub:SetJustifyH("LEFT")
    r:SetScript("OnClick", function(self, button)
        local d = self.data
        if not d then return end
        if d.index then -- paso de Polestar
            if button == "RightButton" then ns.Bridge.Skip(d.index) else ns.Bridge.Goto(d.index) end
            if ns.RequestRefresh then ns.RequestRefresh() end
            return
        end
        if button == "RightButton" then
            ns.Route.SkipGroup(d.group)
        elseif not d.done then
            ns.Route.Focus(d.num)
        end
    end)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Paso " .. tostring(d.num) .. ": " .. (d.title or ""), 1, 1, 1, 1, true)
        if d.group then
            local _, detail, where = ns.Route.GroupText(d.group)
            if detail then GameTooltip:AddLine(detail, 0.8, 0.8, 0.8, true) end
            if where then GameTooltip:AddLine(where, 0.6, 0.6, 0.6, true) end
        elseif d.sub and d.sub ~= "" then
            GameTooltip:AddLine(d.sub, 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Clic: la flecha apunta a este paso", 1, 0.82, 0)
        GameTooltip:AddLine("Clic derecho: saltar este paso", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function GetTipButton(i, parent)
    local b = tipButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 3, -2)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tip or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tipButtons[i] = b
    return b
end

function Panel.Init(frame, title, stats, body)
    P.frame = frame
    frame:SetWidth(WIDTH)
    stats:Hide()
    body:Hide()

    P.level = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    P.eta = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

    -- Barra de XP (al pasar el mouse: XP/hora, descanso, enemigos que faltan)
    P.bar = CreateFrame("Frame", nil, frame)
    P.bar:SetSize(INNER, 6)
    P.bar.bg = P.bar:CreateTexture(nil, "BACKGROUND")
    P.bar.bg:SetAllPoints()
    P.bar.bg:SetColorTexture(1, 1, 1, 0.1)
    P.bar.rested = P.bar:CreateTexture(nil, "BORDER")
    P.bar.rested:SetPoint("TOPLEFT")
    P.bar.rested:SetPoint("BOTTOMLEFT")
    P.bar.rested:SetColorTexture(0.25, 0.5, 1, 0.45)
    P.bar.fill = P.bar:CreateTexture(nil, "ARTWORK")
    P.bar.fill:SetPoint("TOPLEFT")
    P.bar.fill:SetPoint("BOTTOMLEFT")
    P.bar.fill:SetColorTexture(0.58, 0.36, 0.85, 1)
    P.bar:EnableMouse(true)
    P.bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Experiencia", 1, 1, 1)
        for _, line in ipairs(ns.XPLines and ns.XPLines() or {}) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85) end
        GameTooltip:Show()
    end)
    P.bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Tarjeta del paso actual
    P.card = CreateFrame("Button", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    P.card:SetWidth(INNER)
    P.card:RegisterForClicks("RightButtonUp")
    if P.card.SetBackdrop then
        P.card:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        P.card:SetBackdropColor(0.18, 0.14, 0.05, 0.9)
        P.card:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    P.card.head = P.card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    P.card.head:SetPoint("TOPLEFT", 10, -8)
    P.card.circle = Circle(P.card, 26)
    P.card.circle:SetPoint("TOPLEFT", 10, -24)
    P.card.circle.text:SetFontObject("GameFontNormalLarge")
    P.card.circle.text:SetTextColor(0, 0, 0)
    P.card.title = P.card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    P.card.title:SetPoint("TOPLEFT", 44, -26)
    P.card.title:SetWidth(INNER - 54)
    P.card.title:SetJustifyH("LEFT")
    P.card.title:SetTextColor(1, 1, 1)
    P.card.detail = P.card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    P.card.detail:SetPoint("TOPLEFT", P.card.title, "BOTTOMLEFT", 0, -4)
    P.card.detail:SetWidth(INNER - 54)
    P.card.detail:SetJustifyH("LEFT")
    P.card.where = P.card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    P.card.where:SetPoint("TOPLEFT", P.card.detail, "BOTTOMLEFT", 0, -4)
    P.card.where:SetWidth(INNER - 54)
    P.card.where:SetJustifyH("LEFT")
    P.card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    P.card:SetScript("OnClick", function(_, button)
        local polestar = ns.Bridge and ns.Bridge.Active()
        if button == "RightButton" then
            if polestar then ns.Bridge.Skip() else ns.Route.SkipGroup((ns.Route.CurrentGroup())) end
        else
            -- Clic: volver al paso actual si estabas mirando otro
            if polestar then ns.Bridge.BackToLive() else ns.Route.Focus(nil) end
        end
        if ns.RequestRefresh then ns.RequestRefresh() end
    end)
    P.card:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Paso actual", 1, 1, 1)
        GameTooltip:AddLine("La flecha te lleva aquí. Se marca solo al hacerlo.", 0.85, 0.85, 0.85, true)
        if ns.Bridge and ns.Bridge.Active() then
            GameTooltip:AddLine("Ruta de Polestar (optimizada para WoW Forever).", 0.6, 0.8, 1, true)
        end
        GameTooltip:AddLine("Clic: volver al paso actual", 1, 0.82, 0)
        GameTooltip:AddLine("Clic derecho: saltar este paso", 1, 0.82, 0)
        GameTooltip:Show()
    end)

    -- Pregunta de misión de grupo (élite): Omitir / En grupo
    P.card.groupText = P.card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    P.card.groupText:SetWidth(INNER - 20)
    P.card.groupText:SetJustifyH("LEFT")
    P.card.groupText:Hide()
    local function GroupButton(label, answer)
        local b = CreateFrame("Button", nil, P.card, "UIPanelButtonTemplate")
        b:SetSize(110, 20)
        b:SetText(label)
        b:SetScript("OnClick", function(self)
            if self.quest then ns.Bridge.AnswerGroup(self.quest, answer) end
            if ns.RequestRefresh then ns.RequestRefresh() end
        end)
        b:Hide()
        return b
    end
    P.card.skipBtn = GroupButton("Omitir", "skip")
    P.card.doBtn = GroupButton("En grupo", "do")
    P.card:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Botón de la lista completa
    P.toggle = CreateFrame("Button", nil, frame)
    P.toggle:SetSize(150, 16)
    P.toggle.text = P.toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    P.toggle.text:SetPoint("RIGHT", 0, 0)
    P.toggle:SetScript("OnClick", function()
        local db = ns.GetDB()
        db.opt.listOpen = not db.opt.listOpen
        scroll = 0
        if ns.Refresh then ns.Refresh() end
    end)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local db = ns.GetDB()
        if not (db and db.opt.listOpen) then return end
        scroll = math.max(0, scroll - delta)
        if ns.Refresh then ns.Refresh() end
    end)
end

-- Lo que se ve ahora en el panel, en texto (para /sig debug y pruebas).
function Panel.Snapshot()
    local out = {
        level = P.level and P.level.text or nil,
        head = P.card and P.card.head.text, title = P.card and P.card.title.text,
        detail = P.card and P.card.detail.text, where = P.card and P.card.where.text,
        toggle = P.toggle and P.toggle:IsShown() and P.toggle.text.text or nil,
        group = P.card and P.card.skipBtn:IsShown() and P.card.groupText.text or nil,
        rows = {}, tips = {},
    }
    for _, r in ipairs(rows) do
        if r:IsShown() then out.rows[#out.rows + 1] = { num = r.data and r.data.num, title = r.title.text, sub = r.sub.text } end
    end
    for _, b in ipairs(tipButtons) do
        if b:IsShown() then out.tips[#out.tips + 1] = b.tip end
    end
    return out
end

---------------------------------------------------------------------------
-- Dibujar
---------------------------------------------------------------------------
local function Distance(loc)
    local Q = ns.GetQuestie and ns.GetQuestie()
    if not (Q and loc and loc.wx) then return nil end
    local px, py, inst = Q.HBD:GetPlayerWorldPosition()
    if not px or inst ~= loc.inst then return nil end
    return math.sqrt((px - loc.wx) ^ 2 + (py - loc.wy) ^ 2)
end

local function FirstLoc(g)
    for _, s in ipairs(g.steps) do
        if not s.done and s.loc then return s.loc end
    end
    return g.steps[1] and g.steps[1].loc
end

-- Lo que la ventana muestra, armado desde la ruta propia de Siguiente (mismo formato que Bridge.Model).
function Panel.RouteModel(open, maxRows)
    local Route = ns.Route
    local m = { rows = {} }
    local cur, groups = Route.CurrentGroup()
    if not (Route.enabled and cur) then
        m.title = Route.enabled and "Calculando la ruta..." or "Ruta apagada"
        m.detail = Route.enabled and (Route.status or "") or "Actívala en Opciones > AddOns > Siguiente."
        return m
    end
    local title, detail, where = Route.GroupText(cur)
    local d = Distance(FirstLoc(cur))
    m.kind, m.num, m.total, m.title, m.detail = cur.kind, cur.num, Route.LastNum(), title, detail
    m.where = (where or "") .. (d and ((d < 15) and " · estás aquí" or (" · " .. ns.Num(d) .. " yd")) or "")
    m.focus = Route.focusNum ~= nil
    local list = {}
    if open then
        local doneShown = {}
        for _, g in ipairs(groups) do
            if g.done then doneShown[#doneShown + 1] = g end
        end
        for i = math.max(1, #doneShown - 1), #doneShown do list[#list + 1] = doneShown[i] end
        for _, g in ipairs(groups) do
            if not g.done then list[#list + 1] = g end
        end
        scroll = math.min(scroll, math.max(0, #list - maxRows))
    else
        for _, g in ipairs(groups) do
            if not g.done and g ~= cur then list[#list + 1] = g end
        end
        scroll = 0
    end
    for i = 1 + scroll, math.min(#list, scroll + maxRows) do
        local g = list[i]
        local t, dt, wh = Route.GroupText(g)
        m.rows[#m.rows + 1] = { group = g, num = g.num, kind = g.kind, title = t,
            sub = g.done and "hecho" or (wh or dt or ""), done = g.done, current = g == cur }
    end
    local remaining = 0
    for _, g in ipairs(groups) do if not g.done then remaining = remaining + 1 end end
    m.remaining = remaining
    return m
end

function Panel.Render(tips)
    local frame = P.frame
    local db = ns.GetDB()
    local Route = ns.Route
    local y = -30

    -- Nivel y barra de XP
    local info = ns.XPInfo and ns.XPInfo() or {}
    P.level:ClearAllPoints()
    P.level:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
    P.eta:ClearAllPoints()
    P.eta:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, y)
    if info.max then
        P.level:SetText("Nivel " .. info.level .. " (máximo)")
        P.eta:SetText("")
    else
        P.level:SetText(string.format("Nivel %d · %.0f%%", info.level or 0, (info.pct or 0) * 100))
        P.eta:SetText(info.eta and ("sube en ~" .. info.eta) or "")
    end
    y = y - 14
    P.bar:ClearAllPoints()
    P.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
    P.bar.fill:SetWidth(math.max(1, INNER * math.min(1, info.pct or 0)))
    P.bar.rested:SetWidth(math.max(1, INNER * math.min(1, (info.pct or 0) + (info.restedPct or 0))))
    y = y - 14

    -- Qué mostrar: la ruta de Polestar (si está) o la propia de Siguiente
    local open = db.opt.listOpen
    local maxRows = open and LIST_ROWS or COMPACT_ROWS
    local m = (ns.Bridge and ns.Bridge.Active() and ns.Bridge.Model(open, scroll, maxRows)) or Panel.RouteModel(open, maxRows)
    P.model = m

    -- Paso actual
    local card = P.card
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
    if m.num then
        local head = (m.viewing and "VIENDO PASO " or (m.focus and "PASO ELEGIDO " or "PASO ")) .. m.num
            .. (m.total and (" DE " .. m.total) or "")
        if m.guideTitle then head = head .. "  ·  " .. m.guideTitle end
        card.head:SetText(head)
        StyleCircle(card.circle, m.kind, GLYPH[m.kind] or "", false)
        card.circle:Show()
    else
        card.head:SetText(m.guideTitle or "RUTA")
        card.circle:Hide()
    end
    card.title:SetText(m.title or "")
    card.detail:SetText(m.detail or "")
    card.where:SetText(m.where or (m.viewing and "Clic: volver al paso actual" or ""))
    local cardH = 26 + 4 + card.title:GetStringHeight() + 4 + card.detail:GetStringHeight() + 4
        + card.where:GetStringHeight() + 10

    -- Misión de grupo (élite): Polestar pregunta si omitirla o hacerla en grupo
    if m.group then
        card.groupText:SetText("|cffff8040Misión de grupo:|r " .. (m.group.title or "") .. ". Necesita un grupo.")
        card.groupText:ClearAllPoints()
        card.groupText:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -cardH + 4)
        card.groupText:Show()
        local gh = card.groupText:GetStringHeight()
        card.skipBtn:ClearAllPoints()
        card.skipBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -cardH - gh - 2)
        card.doBtn:ClearAllPoints()
        card.doBtn:SetPoint("LEFT", card.skipBtn, "RIGHT", 8, 0)
        card.skipBtn.quest, card.doBtn.quest = m.group.quest, m.group.quest
        card.skipBtn:Show()
        card.doBtn:Show()
        cardH = cardH + gh + 30
    else
        card.groupText:Hide()
        card.skipBtn:Hide()
        card.doBtn:Hide()
    end
    cardH = math.max(56, cardH)
    card:SetHeight(cardH)
    y = y - cardH - 4

    -- Siguientes pasos (o la lista completa)
    local shown = 0
    for _, row in ipairs(m.rows) do
        shown = shown + 1
        local r = GetRow(shown, frame)
        r.data = row
        StyleCircle(r.circle, row.kind, tostring(row.num), row.done)
        r.title:SetText(row.title or "")
        r.title:SetTextColor(row.done and 0.5 or 1, row.done and 0.5 or 1, row.done and 0.5 or 1)
        r.sub:SetText(row.sub or "")
        r.hl:SetShown(row.current == true)
        local rowH = 8 + r.title:GetStringHeight() + 1 + r.sub:GetStringHeight()
        r:SetHeight(rowH)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
        r:Show()
        y = y - rowH
    end
    for i = shown + 1, #rows do rows[i]:Hide() end

    -- Consejos como iconos + botón de la lista
    y = y - 6
    local n = 0
    local maxTips = db.opt.maxTips or 4
    local routeOn = Route.enabled or (ns.Bridge and ns.Bridge.Active())
    for _, tip in ipairs(tips or {}) do
        local icon = TipIcon(tip)
        if n >= maxTips then break end
        if icon ~= "ruta" or not routeOn then
            n = n + 1
            local b = GetTipButton(n, frame)
            b.icon:SetTexture(icon == "ruta" and "Interface\\Icons\\INV_Misc_Map_01" or icon)
            b.tip = tip.text
            local count = tip.text:match("Tienes (%d+) punto") or tip.text:match("%((%d+) libres%)")
            b.count:SetText(count or "")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", 10 + (n - 1) * 24, y)
            b:Show()
        end
    end
    for i = n + 1, #tipButtons do tipButtons[i]:Hide() end

    P.toggle:ClearAllPoints()
    P.toggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, y - 1)
    local remaining = m.remaining or 0
    if m.num and remaining > 1 then
        P.toggle.text:SetText(open and "Ver menos" or ("Ver todos los pasos (" .. remaining .. ")"))
        P.toggle:Show()
    else
        P.toggle:Hide()
    end
    y = y - 24

    frame:SetHeight(-y + 4)
end
