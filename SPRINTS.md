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
- [ ] Confirmar que el workflow corregido compila bien en Actions (revisar
      pestaña Actions tras este push)
- [ ] Probar `ControlSend` contra un Target Manager real (no Friv)
- [ ] Confirmar/ajustar las equivalencias de teclado configuradas en el TM
      contra las de `ActionMap` en el script (especialmente stick derecho)
- [ ] Ajustar deadzone/sensibilidad del stick según comportamiento real
- [ ] Distribuir el `.exe` compilado a otros PCs de la empresa
- [ ] Invitar colaboradores al repo (Settings → Collaborators)
- [ ] Generar token/acceso para pruebas desde otro dispositivo

---

## Backlog / ideas sin sprint asignado

- Configuración de `ActionMap` editable desde la UI (sin tocar el script)
- Guardar/cargar múltiples grabaciones (no solo la última)
- Selección de índice de control si hay más de uno conectado
