# Sprints — PS5 Input Relay

Registro del avance del proyecto. Cada sprint tiene un objetivo central y una
lista de tareas; se marcan al completarse y se agregan notas si algo cambió
de rumbo sobre la marcha.

---

## Sprint 0 — Prototipo base
**Estado:** ✅ Completado *(previo a este repo, sesión con Claude en la web)*

- [x] Panel GUI con lista de ventanas abiertas
- [x] Enlazar/desenlazar ventanas por doble clic
- [x] Relay de teclado en vivo (WASD + equivalencias PS mapeadas a teclado)
- [x] Grabación y loop básicos de una secuencia de teclas
- [x] Envío de input vía `WinActivate` + `Send`

**Nota:** este enfoque robaba el foco de la ventana activa en cada tecla
enviada — quedó identificado como problema a resolver en el siguiente sprint.

---

## Sprint 1 — Control físico + no bloqueo de foco
**Estado:** ✅ Completado — 2026-07-27/28

- [x] Definir requisitos reales del flujo de QA (multi Target Manager, control
      físico de Xbox como fuente, sin permisos de admin disponibles)
- [x] Descartar controles Xbox virtuales (ViGEmBus) por falta de permisos de
      admin y el límite de 4 slots de XInput
- [x] Grabación vía lectura de XInput del control físico (sin drivers)
- [x] Envío vía `ControlSend` en vez de `WinActivate`+`Send` (no roba el foco)
- [x] Botones Play / Grabar / Stop / Relay en la UI (antes solo atajos)
- [x] Indicador de conexión del control en la UI
- [x] Fix: `RefreshWindowList` desincronizaba `TargetWindows` tras refrescar
- [x] Validación local con ventanas de Friv (funcionando)

---

## Sprint 2 — Infraestructura de proyecto
**Estado:** ✅ Completado — 2026-07-28

- [x] Repo Git local
- [x] Repo privado en GitHub (`PS5-Controller---Project`)
- [x] README.md documentando propósito, funcionamiento y atajos
- [x] `.gitignore`
- [x] Workflow de GitHub Actions: compila el `.exe` en cada push a `main` y
      lo publica en Releases

---

## Sprint 3 — UI: checkboxes, vista avanzada y stick derecho
**Estado:** ✅ Completado — 2026-08-03

- [x] Enlazar/desenlazar ventanas por checkbox en vez de doble clic
- [x] Lectura del stick derecho (XInput RX/RY) con equivalencia por defecto
      a flechas (Up/Down/Left/Right)
- [x] Indicador visual de botón/stick presionado (se oscurece al presionar)
- [x] Ventana secundaria "Vista avanzada" para no agrandar el panel principal
- [x] Indicador parpadeante en el botón Play Loop mientras corre
- [x] Diagnóstico de lectura XInput (confirmado: hardware y lectura
      funcionan correctamente; el stick derecho llega a valores extremos
      sin problema)

---

## Sprint 4 — Validación real y distribución
**Estado:** 🔲 En curso

- [x] Reporte de pruebas QA externo (2026-08-03) — ver `REPORTE_PRUEBAS_2026-08-03.md`
- [x] Fix: bug de Map (int vs string) causaba que los checkboxes se vieran
      desmarcados tras refrescar la lista, aunque la ventana seguia enlazada
      (`ToggleLink` ahora normaliza el handle a `Integer`)
- [x] Fix: workflow de Actions fallaba siempre — la URL de autohotkey.com
      esta protegida por Cloudflare (bloquea IPs de datacenter) y el zip
      portable no trae `Ahk2Exe.exe` de todos modos. Ahora descarga el
      interprete y el compilador (repo separado `AutoHotkey/Ahk2Exe`) desde
      GitHub Releases. Verificado localmente: compila y corre correctamente.
- [x] Confirmar que el workflow corregido compila bien en Actions (tag
      `latest` publicado correctamente tras el push)
- [x] Prueba real contra Target Manager (2026-08): `ControlSend` en segundo
      plano no funciona — **hallazgo clave**: TM (tanto "Use Host Controller"
      como "Keyboard Mapping") solo procesa input cuando su ventana tiene el
      foco real de Windows, sin excepción y sin atajo técnico posible
      (confirmado con tecla real a mano, con `Send` global, y comparado
      contra Shell Shockers en navegador, que sí funciona en segundo plano)
- [x] Fix: `EnviarATodasLasVentanas` ahora activa cada ventana enlazada antes
      de mandarle cada tecla (down/up), en vez de mandar en segundo plano.
      El input se "congela" en su último estado al perder el foco, asi que
      no hace falta mantenerlo activo continuamente — el efecto se ve casi
      simultaneo entre consolas. Costo: el PC queda ocupado ciclando
      ventanas mientras Relay/Loop estan activos.
- [ ] Confirmar/ajustar las equivalencias de teclado configuradas en el TM
      contra las de `ActionMap` en el script (confirmado: Cross real = `L`,
      no `Space` como estaba puesto — falta ajustar el resto de botones)
- [ ] Ajustar deadzone/sensibilidad del stick según comportamiento real
- [ ] Distribuir el `.exe` compilado a otros PCs de la empresa
- [ ] Invitar colaboradores al repo (Settings → Collaborators)
- [ ] Automatizar el toggle "Use Host Controller" ↔ "Keyboard Mapping" en TM
      via `ControlClick` al iniciar/detener el Loop (pendiente: obtener el
      identificador del checkbox con Window Spy, incluido con AutoHotkey)
- [ ] Generar token/acceso para pruebas desde otro dispositivo

---

## Sprint 5 — Scheduler con keep-alive (hasta 8 consolas) + 3 macros persistentes
**Estado:** ✅ Completado — 2026-08-05

- [x] **Hallazgo crítico confirmado con el usuario**: aunque el input quede
      "congelado" en TM al perder el foco, si una ventana pasa ~3s sin recibir
      NINGÚN evento nuevo (ni siquiera un reenvío del mismo estado), la
      consola arriesga desconectarse. El diseño anterior (un evento → visitar
      cada ventana) no alcanzaba a garantizar esto con grabaciones de huecos
      largos ni con varias consolas enlazadas.
- [x] Nuevo scheduler de Loop (`LoopSchedulerTick` + `AvanzarRelojDeReproduccion`
      + `ElegirVentanaAVisitar` + `VisitarVentana` + `ReenviarEstadoCompleto`):
      entrega los eventos reales grabados en orden (una cola por ventana, para
      no perder taps rápidos) y además hace keep-alive a cualquier ventana que
      lleve más de la mitad del margen configurado sin ser visitada. Soporta
      cualquier cantidad de ventanas enlazadas (probado hasta el punto que
      importa: sin límite duro de 8, el margen ajustable avisa si no alcanza).
      Probado con 2 ventanas reales (Notepad) durante 8s con una tecla
      sostenida 5s: keep-alive cada ~985ms por ventana, muy por debajo del
      margen de 1500ms, sin perder ningún evento.
- [x] Margen de seguridad ajustable en la UI (`EdMargen`, default 1500ms,
      aplica en vivo) + aviso no bloqueante si la cantidad de ventanas
      enlazadas supera lo que el margen puede sostener (`VerificarMargenSeguridad`,
      estimado de ~250ms por ventana calibrado con la prueba real).
- [x] 3 slots de macro con nombre, persistentes en `ps5_macros.ini` (formato
      delimitado simple, sin dependencias externas). Grabar siempre sobreescribe
      el slot activo, sin diálogos. Selector + campo de renombrar en el panel
      principal. Probado round-trip (guardar/cargar/cerrar/reabrir) de forma
      aislada, confirmado correcto.
- [x] Reordenamiento de UI: controles de reproducción arriba, selector de
      macro debajo (a pedido del usuario).
- [x] Documentación función por función en todo el archivo (pedido explícito
      del usuario para facilitar debugging futuro).

---

## Backlog / ideas sin sprint asignado

- Configuración de `ActionMap` editable desde la UI (sin tocar el script)
- Selección de índice de control si hay más de uno conectado
