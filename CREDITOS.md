# Créditos

**Siguiente** es de El Grumperto y se publica bajo la licencia **GPL-3.0** (ver `LICENSE`).

## Rutas de leveo: Polestar

Las rutas de `Guias/Guias.lua` (68 rutas de leveo del 1 al 60, por raza, clase y facción, con sus textos en
español) vienen de **Polestar** — https://github.com/fitzforge/polestar — Copyright (c) 2026 The Polestar authors,
GPL-3.0-only. Se importan con `tools/importar-polestar.js` desde una instalación de Polestar; no se cambian a mano.

No se copian los "caminos" de Polestar (los `Legs.lua` de cada raza, derivados de mapas privados de Leffe),
ni su enrutador ni sus mapas de navegación: Siguiente usa su propia flecha.

## Nombres del juego

`Guias/Nombres.lua` tiene los nombres en español (misiones, PNJ, objetos, vuelos) que usan las rutas, tal como
los reúne Polestar: tablas del cliente (vía wago.tools), DingDB de Yendi (GPL-3.0, basado en Questie), y pfQuest de
Shagu (MIT). Los nombres y textos del juego son de Blizzard Entertainment. Detalle completo de fuentes y licencias:
`Guias/LICENSE-DATA.txt`.

## Questie

Siguiente usa Questie (GPL-3.0) mientras el juego corre, para ubicar NPC y objetivos y para su librería de mapas.
No incluye código ni datos de Questie.

Gracias a sus autores.
