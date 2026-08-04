# PS5 Input Relay

Herramienta de AutoHotkey v2 para QA de videojuegos: graba el input que le das
a un personaje usando un control físico de Xbox (vía XInput) y lo reproduce en
loop sobre múltiples ventanas de Target Manager (PS5) enlazadas en un panel.

## Por qué existe

En testing con múltiples devkits conectados por GDK, algunos modos de juego
necesitan una secuencia de inputs constante (moverse, girar, repetir) durante
partidas de ~10 minutos que hay que correr varias veces. Grabar la secuencia
una vez y loopearla contra todas las ventanas conectadas ahorra ese trabajo
manual repetitivo.

## Cómo funciona

1. **Grabar**: mientras "Grabar" está activo, el programa sondea tu control
   físico de Xbox (botones + ambos sticks) y guarda cada evento con su
   tiempo real entre pulsaciones. El stick derecho usa flechas como
   equivalencia por defecto (uso común para cámara) — ajustable en
   `ActionMap` si tu Target Manager usa otras teclas.
2. **Enlazar ventanas**: marca la casilla de cualquier ventana abierta en la
   lista para enlazarla/desenlazarla como destino.
3. **Relay en vivo / Loop**: el input (en vivo o grabado) se manda como
   teclas equivalentes a cada ventana enlazada. El Target Manager de PS5 solo
   procesa input (control USB o teclado) cuando su ventana tiene el foco real
   de Windows — no hay forma de evitar esto, es como está diseñado TM, no una
   limitación del script. Por eso el programa activa brevemente cada ventana
   enlazada antes de mandarle cada tecla, y pasa a la siguiente. Como el
   input se "congela" en su último estado al perder el foco, el efecto se ve
   prácticamente simultáneo entre consolas aunque técnicamente se manden una
   por una. **Mientras el Relay/Loop están activos, el PC queda ocupado
   ciclando ventanas — no se puede usar para otra cosa en simultáneo.**
4. **Vista avanzada**: ventana aparte (botón "Ver vista avanzada") con el
   detalle en vivo de cada botón/stick — se oscurece mientras está
   presionado. Útil para depurar, no hace falta para el uso diario.

## Configuración necesaria en Target Manager

Cada sesión de TM que se vaya a usar con Grabar/Loop necesita tener activado
**Keyboard Mapping** (no "Use Host Controller") — de lo contrario TM no
procesa ninguna tecla, real o simulada. "Use Host Controller" sigue siendo
útil para jugar en vivo con el control físico directo (sin este programa),
pero no acepta input grabado/reproducido — solo el control físico en tiempo
real.

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

Lectura de control (ambos sticks + botones) confirmada. Probado contra un
Target Manager real (2026-08): "Use Host Controller" y "Keyboard Mapping"
solo procesan input cuando la ventana tiene el foco real — el envío ahora
activa cada ventana antes de mandar cada tecla. Pendiente confirmar en
Target Manager real con esta versión. Ver `SPRINTS.md` para el detalle de
avance.
