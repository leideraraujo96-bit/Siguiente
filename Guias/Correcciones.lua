-- Siguiente — correcciones a mano sobre las rutas importadas de Polestar (GPL-3.0, ver LICENSE-DATA.txt).
-- Guias.lua se regenera con tools/importar-polestar.js; lo que haya que arreglar va aquí para no perderlo.
--
-- Cada corrección cambia x,y de un objetivo (misión + tipo) SOLO si todavía tiene la coordenada vieja ("era").
-- Si Polestar la arregla en una versión futura, la corrección deja de aplicarse sola.
local _, ns = ...

ns.CORRECCIONES = {
    -- Mulgore es más grande en el mapa de Forever que en el clásico. Polestar convirtió los NPC, pero dejó
    -- los pozos con la coordenada clásica. Valores nuevos calculados con las coordenadas de mundo de
    -- RXPGuides (Forever) y comprobados en el juego para el Pozo Ferocrín (2026-11-16).
    ["forever/horde/tauren/01-mulgore"] = {
        { quest = 754, t = "use", map = 1412, era = { 53.7, 66.2 }, x = 51.78, y = 68.51 }, -- Pozo de Pezuña Invernal
        { quest = 758, t = "use", map = 1412, era = { 44.6, 45.4 }, x = 44.15, y = 51.07 }, -- Pozo de Tronacuerno
        { quest = 760, t = "use", map = 1412, era = { 42.8, 14.2 }, x = 42.50, y = 24.76 }, -- Pozo Ferocrín
    },
}
