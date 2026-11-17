# Siguiente

Addon para **World of Warcraft: Forever** que te dice qué hacer para subir de nivel más rápido:

- **Ruta paso a paso**: acepta, haz, entrega. Avanza sola y se marca con números en el mapa y el minimapa.
- **Elige la mejor zona** por XP por hora (contando el viaje) y te lleva: maestro de vuelo, barco o zepelín. Descarta misiones que rinden poco.
- **Todas las clases, Alianza y Horda, cualquier nivel** (1 a 60). Opciones para incluir misiones naranjas, de grupo o de mazmorra.
- **Flecha** que te lleva al paso actual.
- **Consejos**: entrenador, talentos, bolsas, reparar, varita, zona adecuada para tu nivel.
- **Opciones** en Opciones → AddOns → Siguiente (posición, tamaño, bloqueo, ruta).

Necesita **Questie**, porque de ahí saca dónde están las misiones.

## Instalar

**Con WowUp (recomendado, se actualiza solo):**

1. En WowUp elige tu instalación de **WoW Forever**.
2. **Get Addons** → **Install from URL**.
3. Pega `https://github.com/leideraraujo96-bit/Siguiente` e instala.
4. Entra al juego (o escribe `/reload`). La ventana aparece sola; `/sig` la muestra u oculta.

WowUp te avisará de cada versión nueva.

**A mano:** baja el `.zip` de la última versión en [Releases](https://github.com/leideraraujo96-bit/Siguiente/releases)
y descomprímelo en `World of Warcraft\_forever_\Interface\AddOns`, de modo que quede la carpeta `AddOns\Siguiente`.
Así no se actualiza solo.

Los textos de los pasos están en español. Funciona con el juego en cualquier idioma, porque reconoce las misiones por su número.

## Rutas de leveo (de Polestar, incluidas)

Siguiente trae **68 rutas de leveo del 1 al 60** para todas las razas, clases y facciones de WoW Forever,
con sus textos en español. Vienen de [Polestar](https://github.com/fitzforge/polestar) (GPL-3.0) y se siguen
**sin necesitar Polestar instalado**: Siguiente elige tu ruta por raza, facción y nivel, filtra los pasos por clase,
detecta lo que haces y pasa sola a la ruta siguiente. Botón del mapa en la ventana: elegir otra ruta.

Para actualizar las rutas desde una versión nueva de Polestar (instalado en tu PC):

```
cd tools
npm install
node importar-polestar.js "<carpeta de WoW>/_forever_/Interface/AddOns"
```

Después de importar, revisa las coordenadas contra Questie (las de Polestar a veces quedan con las del mapa clásico):

```
node tools/questie-a-json.js "<AddOns>/QuestieDB" questie.json
node tools/auditar-coords.js Guias/Guias.lua questie.json "<AddOns>/QuestieDB/support/Forever/Zones/areaIdToUiMapId.lua" sospechosos.json
```

Revisa cada sospechoso a mano y apunta los errores reales en `Guias/Correcciones.lua`.

Si apagas las rutas (Opciones → AddOns → Siguiente), Siguiente calcula su propia ruta con los datos de Questie.

## Licencia

GPL-3.0 (ver `LICENSE` y `CREDITOS.md`).

## Comandos

| Comando | Qué hace |
|---|---|
| `/sig` | Mostrar u ocultar la ventana |
| `/sig opciones` | Abrir las opciones |
| `/sig mover` | Modo mover: arrastrar ventana y flecha |
| `/sig pasos` | Próximos 30 pasos en el chat |
| `/sig ruta` / `/sig ruta nueva` | Activar o desactivar la ruta / empezar desde el paso 1 |
| `/sig flecha` | Mostrar u ocultar la flecha |
| `/sig ayuda` | Lista de comandos |

## Publicar una versión nueva

1. Sube `## Version` en `Siguiente.toc`.
2. `powershell -ExecutionPolicy Bypass -File tools\empaquetar.ps1` arma `dist\Siguiente-v<versión>-forever.zip` y `dist\release.json`.
3. Crea una release en GitHub con el tag `v<versión>` y sube esos dos archivos. WowUp la detecta como actualización.
