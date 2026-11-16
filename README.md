# Siguiente

Addon para **World of Warcraft: Forever** que te dice qué hacer para subir de nivel más rápido:

- **Ruta paso a paso**: acepta, haz, entrega. Avanza sola y se marca con números en el mapa y el minimapa.
- **Elige la mejor zona** por XP por hora (contando el viaje) y te lleva: maestro de vuelo, barco o zepelín. Descarta misiones que rinden poco.
- **Todas las clases, Alianza y Horda, cualquier nivel** (1 a 60). Opciones para incluir misiones naranjas, de grupo o de mazmorra.
- **Flecha** que te lleva al paso actual.
- **Consejos**: entrenador, talentos, bolsas, reparar, varita, zona adecuada para tu nivel.
- **Opciones** en Opciones → AddOns → Siguiente (posición, tamaño, bloqueo, ruta).

Necesita **Questie**, porque de ahí saca dónde están las misiones.

## Rutas de leveo (de Polestar, incluidas)

Siguiente trae **68 rutas de leveo del 1 al 60** para todas las razas, clases y facciones de WoW Forever,
con sus textos en español. Vienen de [Polestar](https://github.com/fitzforge/polestar) (GPL-3.0) y se siguen
**sin necesitar Polestar instalado**: Siguiente elige tu ruta por raza, facción y nivel, filtra los pasos por clase,
detecta lo que haces y pasa sola a la ruta siguiente. Botón del mapa en la ventana: elegir otra ruta.

Para actualizar las rutas desde una versión nueva de Polestar (instalado en tu PC):

```
cd tools
npm install
node importar-polestar.js "A:/World of Warcraft/_forever_/Interface/AddOns"
```

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

## Instalar con WowUp (repositorio privado)

1. En GitHub crea un token: Settings → Developer settings → Fine-grained tokens. Dale acceso **solo a este repositorio** y el permiso **Contents: Read-only**.
2. En WowUp: Options → Addons → **GitHub Personal Access Token** → pega el token.
3. En WowUp: Get Addons → **Install from URL** → la dirección de este repositorio.

## Publicar una versión nueva

1. Sube `## Version` en `Siguiente.toc`.
2. `powershell -ExecutionPolicy Bypass -File tools\empaquetar.ps1` arma `dist\Siguiente-v<versión>-forever.zip` y `dist\release.json`.
3. Crea una release en GitHub con el tag `v<versión>` y sube esos dos archivos. WowUp la detecta como actualización.
