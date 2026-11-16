-- Opciones: panel en Opciones > AddOns > Siguiente, y el modo mover.

local _, ns = ...
local Options = {}
ns.Options = Options

local panel, content
local widgets = {}

local function Say(msg) print("|cffffd100Siguiente|r: " .. msg) end

local function GetVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get("Siguiente", "Version") or ""
end

---------------------------------------------------------------------------
-- Controles
---------------------------------------------------------------------------
local function Tooltip(widget, title, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Header(y, text)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    line:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    line:SetColorTexture(1, 0.82, 0, 0.35)
    return y - 34
end

local function Check(y, label, tip, get, set)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 20, y)
    local text = cb.Text or cb.text
    if type(text) ~= "table" then
        text = _G[(cb:GetName() or "") .. "Text"]
    end
    if type(text) ~= "table" then
        text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    text:SetFontObject("GameFontHighlight")
    text:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    Tooltip(cb, label, tip)
    cb.Refresh = function() cb:SetChecked(get() and true or false) end
    widgets[#widgets + 1] = cb
    return y - 30
end

local sliderCount = 0
local function Slider(y, label, tip, minV, maxV, step, format, get, set)
    sliderCount = sliderCount + 1
    local s = CreateFrame("Slider", "SiguienteOptionsSlider" .. sliderCount, content, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 26, y - 14)
    s:SetWidth(260)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local name = s:GetName()
    local function Region(key)
        local r = s[key]
        if type(r) == "table" then return r end
        r = _G[name .. key]
        return type(r) == "table" and r or nil
    end
    local text, low, high = Region("Text"), Region("Low"), Region("High")
    if low then low:SetText(format(minV)) end
    if high then high:SetText(format(maxV)) end
    local function Label(v)
        if text then text:SetText(label .. ": " .. format(v)) end
    end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        Label(v)
        if not self.loading then set(v) end
    end)
    Tooltip(s, label, tip)
    s.Refresh = function()
        s.loading = true
        s:SetValue(get())
        s.loading = false
        Label(get())
    end
    widgets[#widgets + 1] = s
    return y - 56
end

local function Button(x, y, width, label, tip, onClick)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(width, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    Tooltip(b, label, tip)
    return b
end

local function Percent(v) return math.floor(v * 100 + 0.5) .. "%" end
local function Int(v) return tostring(math.floor(v + 0.5)) end
local function Yards(v) return math.floor(v + 0.5) .. " yd" end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function Build()
    local db = ns.GetDB()
    local opt = db.opt

    panel = CreateFrame("Frame", "SiguienteOptionsPanel")
    panel.name = "Siguiente"

    local scroll = CreateFrame("ScrollFrame", "SiguienteOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 900)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then content:SetWidth(w) end end)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Siguiente")
    local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 3)
    version:SetText("v" .. GetVersion())
    local about = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    about:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    about:SetJustifyH("LEFT")
    about:SetText("Te dice qué hacer para subir más rápido: una ruta paso a paso, una flecha y consejos. " ..
        "Usa los datos de Questie. Escribe /sig ayuda para ver los comandos.")

    local y = -76

    -- Posición
    y = Header(y, "Posición en la pantalla")
    local moveBtn
    moveBtn = Button(20, y, 200, "Mover ventana y flecha",
        "Muestra la ventana y la flecha en verde para que las arrastres a donde quieras. " ..
        "Vuelve a pulsar (o escribe /sig mover) para terminar.",
        function()
            Options.SetMoveMode(not ns.moveMode)
            moveBtn:SetText(ns.moveMode and "Terminar de mover" or "Mover ventana y flecha")
        end)
    Options.moveButton = moveBtn
    Button(230, y, 200, "Volver a su lugar", "Pone la ventana y la flecha en su posición original.",
        function()
            ns.ResetPositions()
            Say("ventana y flecha en su posición original.")
        end)
    y = y - 34

    -- Ventana
    y = Header(y, "Ventana de consejos")
    y = Check(y, "Mostrar la ventana", "También con /sig.",
        function() return not db.hidden end,
        function(v) ns.SetWindowShown(v) end)
    y = Check(y, "Bloquear la ventana", "Así no la mueves sin querer al hacer clic. El modo mover funciona igual.",
        function() return opt.lockWindow end,
        function(v) opt.lockWindow = v end)
    y = Slider(y, "Tamaño", "Escala de la ventana.", 0.5, 1.5, 0.05, Percent,
        function() return opt.windowScale end,
        function(v) opt.windowScale = v; ns.ApplyLook() end)
    y = Slider(y, "Opacidad del fondo", "0% = fondo transparente.", 0, 1, 0.05, Percent,
        function() return opt.bgAlpha end,
        function(v) opt.bgAlpha = v; ns.ApplyLook() end)
    y = Slider(y, "Consejos a mostrar", "Consejos debajo de la ruta (bolsas, reparar, talentos, zona...). 0 = solo la ruta.",
        0, 8, 1, Int,
        function() return opt.maxTips end,
        function(v) opt.maxTips = v; ns.Refresh() end)

    -- Flecha
    y = Header(y, "Flecha")
    y = Check(y, "Mostrar la flecha", "También con /sig flecha.",
        function() return db.arrow ~= false end,
        function(v) ns.SetArrowShown(v) end)
    y = Check(y, "Bloquear la flecha", "El clic derecho para saltar un paso sigue funcionando.",
        function() return opt.lockArrow end,
        function(v) opt.lockArrow = v end)
    y = Slider(y, "Tamaño de la flecha", nil, 0.5, 2, 0.05, Percent,
        function() return opt.arrowScale end,
        function(v) opt.arrowScale = v; ns.ApplyLook() end)

    -- Rutas incluidas
    y = Header(y, "Rutas de leveo (incluidas en Siguiente)")
    y = Check(y, "Seguir las rutas paso a paso",
        "Rutas del 1 al 60 para tu raza, clase y facción, optimizadas para WoW Forever (vienen de Polestar, "
        .. "código abierto GPL-3.0). No hace falta tener Polestar instalado. Si las apagas, Siguiente calcula su propia ruta.",
        function() return opt.useGuides ~= false end,
        function(v)
            opt.useGuides = v
            if ns.Guide then ns.Guide.Tick() ns.Guide.DrawPins() end
            ns.Route.MarkDirty(0)
            ns.Route.DrawPins()
            ns.Refresh()
        end)
    Button(20, y, 140, "Elegir ruta", "Lista de rutas para tu personaje: clic en una para seguirla.",
        function() if ns.Panel then ns.Panel.ShowPicker() end end)
    Button(166, y, 140, "Ruta siguiente", "Pasa a la ruta que sigue a la actual.",
        function()
            local id = ns.Guide and ns.Guide.NextGuide()
            Say(id and "pasas a la ruta siguiente." or "no hay una ruta siguiente.")
        end)
    Button(312, y, 150, "Recuperar saltados", "Vuelve a mostrar los pasos que saltaste en esta ruta.",
        function()
            if ns.Guide then ns.Guide.ResetSkips() end
            Say("pasos saltados recuperados.")
        end)
    y = y - 40

    -- Polestar
    y = Header(y, "Polestar en vivo (solo si lo tienes activado)")
    y = Check(y, "Usar la ventana de Polestar en vivo (si está activado)",
        "Muestra en esta ventana la ruta de Polestar, optimizada para WoW Forever según tu raza, clase y facción. "
        .. "Polestar sigue llevando la cuenta de los pasos y su flecha camina por caminos reales. "
        .. "Sin Polestar, Siguiente usa su propia ruta.",
        function() return opt.usePolestar ~= false end,
        function(v)
            opt.usePolestar = v
            ns.Route.MarkDirty(0)
            ns.Route.DrawPins()
            ns.Refresh()
        end)
    local psBtn
    psBtn = Button(20, y, 260, "Ocultar la ventana de Polestar",
        "Deja solo la ventana de Siguiente. La flecha y las marcas del mapa de Polestar siguen. Vuelve a pulsar para mostrarla.",
        function()
            if not (ns.Bridge and ns.Bridge.Installed()) then
                Say("Polestar no está instalado.")
                return
            end
            local show = not ns.Bridge.PolestarWindowShown()
            ns.Bridge.ShowPolestarWindow(show)
            psBtn:SetText(show and "Ocultar la ventana de Polestar" or "Mostrar la ventana de Polestar")
        end)
    Options.psButton = psBtn
    y = y - 34

    -- Ruta
    y = Header(y, "Ruta propia de Siguiente (sin Polestar)")
    y = Check(y, "Activar la ruta", "Si la apagas, la flecha apunta a la misión más cercana.",
        function() return ns.Route.enabled end,
        function(v) ns.Route.SetEnabled(v) end)
    y = Check(y, "Números en el mapa del mundo", "Círculos numerados: amarillo aceptar, naranja hacer, verde entregar, celeste viajar.",
        function() return opt.mapPins end,
        function(v) opt.mapPins = v; ns.Route.DrawPins() end)
    y = Check(y, "Números en el minimapa", "Los próximos 3 pasos.",
        function() return opt.miniPins end,
        function(v) opt.miniPins = v; ns.Route.DrawPins() end)
    y = Check(y, "Llevarme a otra zona cuando rinda más",
        "Compara la XP por hora de cada zona (contando el viaje) y te manda a la mejor, con barco, zepelín o vuelo si hace falta.",
        function() return opt.autoTravel ~= false end,
        function(v) opt.autoTravel = v; ns.Route.MarkDirty(0) end)
    y = Check(y, "Incluir misiones naranjas", "Dan más XP pero son más difíciles yendo solo.",
        function() return opt.allowOrange end,
        function(v) opt.allowOrange = v; ns.Route.MarkDirty(0) end)
    y = Check(y, "Incluir misiones de grupo (élite)", "Actívalo cuando juegues en grupo con amigos.",
        function() return opt.allowGroup end,
        function(v) opt.allowGroup = v; ns.Route.MarkDirty(0) end)
    y = Check(y, "Incluir misiones de mazmorra", "Las que se hacen dentro de una mazmorra, para cuando vayas en grupo.",
        function() return opt.allowDungeon end,
        function(v) opt.allowDungeon = v; ns.Route.MarkDirty(0) end)
    y = y - 6
    Button(20, y, 200, "Empezar desde el paso 1", "Borra el contador y vuelve a calcular la ruta.",
        function()
            ns.Route.Reset()
            Say("ruta recalculada desde el paso 1.")
        end)
    Button(230, y, 200, "Ver pasos en el chat", "Escribe los próximos 30 pasos en el chat (igual que /sig pasos).",
        function() ns.Route.PrintList() end)
    y = y - 40

    content:SetHeight(-y + 20)

    panel:SetScript("OnShow", function()
        for _, w in ipairs(widgets) do w.Refresh() end
        moveBtn:SetText(ns.moveMode and "Terminar de mover" or "Mover ventana y flecha")
        if ns.Bridge and ns.Bridge.Installed() then
            psBtn:SetText(ns.Bridge.PolestarWindowShown() and "Ocultar la ventana de Polestar" or "Mostrar la ventana de Polestar")
        end
    end)
end

function Options.Setup()
    if panel then return end
    local ok, err = pcall(function()
        Build()
        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, "Siguiente")
            Settings.RegisterAddOnCategory(category)
            Options.category = category
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end
    end)
    if not ok then Say("no se pudo crear el panel de opciones: " .. tostring(err)) end
end

function Options.Open()
    if not panel then Options.Setup() end
    if InCombatLockdown and InCombatLockdown() then
        Say("las opciones se abren fuera de combate.")
        return
    end
    if Options.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(Options.category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory and panel then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

---------------------------------------------------------------------------
-- Modo mover: ventana y flecha en verde para arrastrarlas
---------------------------------------------------------------------------
local function Overlay(f, label)
    if f.moveOverlay then return end
    local o = f:CreateTexture(nil, "OVERLAY")
    o:SetAllPoints()
    o:SetColorTexture(0.1, 0.8, 0.1, 0.35)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER")
    t:SetText(label)
    f.moveOverlay, f.moveText = o, t
end

function Options.SetMoveMode(on)
    local db = ns.GetDB()
    ns.moveMode = on
    Overlay(ns.mainFrame, "Arrástrame")
    Overlay(ns.arrowFrame, "Flecha")
    for _, f in ipairs({ ns.mainFrame, ns.arrowFrame }) do
        if on then
            f.moveOverlay:Show()
            f.moveText:Show()
            f:Show()
        else
            f.moveOverlay:Hide()
            f.moveText:Hide()
        end
    end
    if on then
        ns.Refresh()
        Say("modo mover: arrastra la ventana y la flecha. Escribe /sig mover para terminar.")
    else
        if db.hidden then ns.mainFrame:Hide() end
        if db.arrow == false then ns.arrowFrame:Hide() end
        Say("posiciones guardadas.")
    end
    if Options.moveButton then
        Options.moveButton:SetText(on and "Terminar de mover" or "Mover ventana y flecha")
    end
end
