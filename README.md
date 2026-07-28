# PS5 Input Relay

Herramienta de AutoHotkey v2 para QA de videojuegos: graba el input que le das
a un personaje usando un control físico de Xbox (vía XInput) y lo reproduce en
loop, en simultáneo, sobre múltiples ventanas de Target Manager (PS5) enlazadas
en un panel — sin robar el foco de tu PC mientras corre.

## Por qué existe

En testing con múltiples devkits conectados por GDK, algunos modos de juego
necesitan una secuencia de inputs constante (moverse, girar, repetir) durante
partidas de ~10 minutos que hay que correr varias veces. Grabar la secuencia
una vez y loopearla contra todas las ventanas conectadas ahorra ese trabajo
manual repetitivo.

## Cómo funciona

1. **Grabar**: mientras "Grabar" está activo, el programa sondea tu control
   físico de Xbox (botones + stick izquierdo) y guarda cada evento con su
   tiempo real entre pulsaciones.
2. **Enlazar ventanas**: doble clic sobre cualquier ventana abierta en la
   lista para enlazarla/desenlazarla como destino.
3. **Relay en vivo / Loop**: el input (en vivo o grabado) se manda como
   teclas equivalentes a cada ventana enlazada usando `ControlSend`, que no
   activa la ventana ni te quita el foco — puedes seguir usando tu PC mientras
   corre.

## Atajos

| Acción | Atajo |
|---|---|
| Toggle Relay en vivo | `Ctrl+Espacio` |
| Toggle Grabar | `Ctrl+R` |
| Reproducir loop grabado | `Ctrl+L` |
| Detener loop | `Ctrl+P` |

También hay botones equivalentes en el panel.

## Requisitos

- Windows con [AutoHotkey v2](https://www.autohotkey.com/) (solo para correr
  el `.ahk` directamente; el `.exe` compilado no lo necesita).
- Un control de Xbox conectado (lectura vía XInput, sin drivers adicionales).
- Los Target Manager deben tener configurada la equivalencia de teclado que
  usa `ActionMap` dentro del script (ver `PS5-Controller.ahk`).

## Build / Releases

Cada push a `main` compila automáticamente un `.exe` standalone (no requiere
AutoHotkey instalado en la máquina destino) vía GitHub Actions, publicado en
la sección [Releases](../../releases).

## Estado

En validación: probado con ventanas de escritorio genéricas; pendiente de
confirmar el comportamiento de `ControlSend` contra un Target Manager real.
