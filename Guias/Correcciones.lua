-- Siguiente — correcciones a mano sobre las rutas importadas de Polestar (GPL-3.0, ver LICENSE-DATA.txt).
-- Guias.lua se regenera con tools/importar-polestar.js; lo que haya que arreglar va aquí para no perderlo.
--
-- Cada corrección cambia x,y de un objetivo (misión + tipo) SOLO si todavía tiene la coordenada vieja ("era").
-- Si Polestar la arregla en una versión futura, la corrección deja de aplicarse sola.
--
-- Cómo se encuentran: tools/auditar-coords.js compara cada objetivo de las rutas con los datos de
-- QuestieDB para Forever (posiciones de NPC, objetos y zonas de misión) y lista los que no cuadran.
-- Cada caso se revisa a mano: NPC de evento, zonas de bichos y escoltas suelen estar bien en Polestar.
local _, ns = ...

ns.CORRECCIONES = {
    -- Mulgore es más grande en el mapa de Forever que en el clásico. Polestar convirtió los NPC, pero dejó
    -- los pozos con la coordenada clásica (el Pozo Ferocrín salía 10 unidades al norte; comprobado en el juego).
    ["forever/horde/tauren/01-mulgore"] = {
        { quest = 754, t = "use", map = 1412, era = { 53.7, 66.2 }, x = 51.76, y = 68.43 }, -- Pozo de Pezuña Invernal
        { quest = 758, t = "use", map = 1412, era = { 44.6, 45.4 }, x = 44.17, y = 51.11 }, -- Pozo de Tronacuerno
        { quest = 760, t = "use", map = 1412, era = { 42.8, 14.2 }, x = 42.70, y = 24.98 }, -- Pozo Ferocrín
    },
    -- El archimago Ansirem está junto a la cúpula de Dalaran (lo dice la propia nota del paso);
    -- Polestar le puso la coordenada del campamento del Kirin Tor.
    ["forever/alliance/30-40/05-arathi-highlands"] = {
        { quest = 602, t = "turnin", map = 1416, era = { 14.16, 59.73 }, x = 18.84, y = 78.49 },
        { quest = 603, t = "accept", map = 1416, era = { 14.16, 59.73 }, x = 18.84, y = 78.49 },
    },
    -- El Libro de recibos de Augustus está en la posada en ruinas de Terrorvale (objeto 177789).
    ["forever/horde/50-60/05-eastern-plaguelands"] = {
        { quest = 6164, t = "collect", map = 1423, era = { 17.4, 31.1 }, x = 14.04, y = 24.22 },
    },
}
