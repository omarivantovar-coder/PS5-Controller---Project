# Reporte de Pruebas — PS5 Input Relay

**Proyecto:** `omarivantovar-coder/PS5-Controller---Project`
**Fecha:** 2026-08-03
**Tipo:** Pruebas de QA (estáticas + dinámicas) — sin modificaciones al código
**Commit evaluado:** `7ed2855` (Checkboxes para enlazar, stick derecho, vista avanzada e indicador de loop)

---

## 1. Resumen ejecutivo

| Área | Resultado |
|---|---|
| Arranque y estabilidad del script | ✅ PASA |
| Lectura de input (XInput) | ⚠️ No probable en este entorno (requiere Windows + control físico); revisión estática OK |
| Envío de teclas (ControlSend) | ⚠️ No probable (requiere Windows + Target Manager); lógica revisada OK |
| Enlace de ventanas (checkboxes) | ❌ FALLA PARCIAL — bug de tipos de clave en `TargetWindows` |
| Pipeline CI (GitHub Actions) | ❌ FALLA — build nunca ha compilado (2 causas confirmadas) |
| Generación de `.exe` | ❌ Nunca se ha producido (0 releases) |

**Bug crítico:** el CI no funciona y nunca ha producido un `.exe`.
**Bug medio:** el estado visual de los checkboxes se pierde al refrescar la lista de ventanas.

---

## 2. Metodología

1. **Análisis estático** completo del script (408 líneas de AutoHotkey v2), README, SPRINTS.md y workflow CI.
2. **Pruebas dinámicas con la runtime real** (AutoHotkey **v2.0.26** oficial bajo wine 11.8, display X11):
   - Ejecución del script completo → verificación de arranque sin errores.
   - Sondas empíricas aisladas (`probe.ahk`, `probe2.ahk`, `repro.ahk`) para validar/descartar hipótesis de bugs contra la runtime real.
3. **Verificación del CI:** descarga y análisis del log real del run fallido (run `30866672424`) + validación del contenido real de los paquetes que el workflow intenta usar.

**Limitaciones del entorno:** sin Windows, sin control Xbox y sin Target Manager no es posible probar dinámicamente XInput, ControlSend contra TM, ni la compilación (el instalador de AHK no corre bajo wine).

---

## 3. Hallazgos

### 3.1 🔴 CRÍTICO — El CI nunca compila (build.yml)

**Evidencia:** run `30866672424` (push del 2026-08-03 a `main`) → paso 3 "Descargar AutoHotkey v2 (portable)" falla, el resto se salta. Log real:

```
Invoke-WebRequest: ... 2 | Invoke-WebRequest -Uri "https://www.autohotkey.com/download/ahk-v2.zip" ...
Enable JavaScript and cookies to continue  (challenge de Cloudflare)
##[error]Process completed with exit code 1.
```

**Causa 1 — URL bloqueada:** `autohotkey.com/download/ahk-v2.zip` está protegido con un challenge de Cloudflare que exige JavaScript. PowerShell en runners de GitHub no puede resolverlo → la descarga falla siempre. (Verificado además desde este entorno: la misma URL responde con el challenge.)

**Causa 2 — el zip no contiene lo que el workflow espera:** incluso con la descarga funcionando, el zip portable de AHK v2 **no incluye `Ahk2Exe.exe`** ni archivos `.bin` base. Contenido real verificado del zip oficial v2.0.26:

```
AutoHotkey64.exe
AutoHotkey32.exe
UX/install-ahk2exe.ahk   ← solo un instalador auxiliar
```

El paso 4 lanzaría `throw "No se encontro Ahk2Exe.exe"`. Los base files (`AutoHotkeySC.bin`/`Unicode 64-bit.bin`) solo vienen en el zip de **AHK v1.1** (`Compiler/`) o en la instalación completa de v2 (instalador `setup.exe` → carpeta `Compiler/`).

**Consecuencia:** 0 releases publicados, el `.exe` nunca se generó.

**Sugerencia de corrección (no aplicada):** descargar desde GitHub Releases (sin Cloudflare) — el instalador oficial `AutoHotkey_2.0.26_setup.exe` con `/VERYSILENT` (instala `Compiler\Ahk2Exe.exe` + base files), o usar el zip v1.1 para los `.bin`; o reemplazar el paso por una acción comunitaria probada del marketplace.

---

### 3.2 🟠 MEDIO — Checkboxes pierden el estado al refrescar (TargetWindows)

**Síntoma:** al pulsar "Actualizar lista", las ventanas enlazadas aparecen **desmarcadas** aunque siguen enlazadas.

**Causa raíz (confirmada empíricamente con la runtime real):** los Maps de AHK v2 distinguen tipos de clave — `2220180` (int) ≠ `"2220180"` (string).

- `ToggleLink` guarda con clave **string** (`LV.GetText(row, 2)` devuelve texto: `"2220180"`).
- `RefreshWindowList` busca con clave **int** (`WinGetList()` devuelve enteros: `2220180`).

Sonda real:

```
TargetWindows["2220180"] := "titulo"   ; como ToggleLink
Has(2220180 int)      → 0   ; como RefreshWindowList → falso → casilla sin marcar
Has("2220180" string) → 1
```

**Impacto:** visual/UX (el usuario pierde la confianza de qué ventanas están enlazadas; riesgo de re-enlazar por error). El envío de teclas no se rompe porque `EnviarATodasLasVentanas` itera las claves del Map tal como están.

**Sugerencia (no aplicada):** normalizar el tipo de clave en un solo lugar (p. ej., convertir siempre a int con `Integer()` al leer de la ListView, o almacenar como string en ambos puntos).

---

### 3.3 ✅ Descartado — "Faltan declaraciones `global`"

Durante la revisión estática parecía que `RefreshWindowList` y `ToggleLink` usaban `LV` / `TargetWindows` sin declararlos `global` (error clásico v1). **Prueba dinámica demuestra que NO es un bug:** AHK v2 resuelve globales automáticamente para lecturas y escrituras indexadas dentro de funciones. Sondas reales:

- `LV.Delete()` dentro de función sin `global` → ejecutó sin error (objeto ListView real).
- `TargetWindows["clave"] := valor` dentro de función sin `global` → mutó el Map global (size=1 correcto).

**No "corregir" esto** — sería un cambio innecesario sin efecto.

---

### 3.4 ⚠️ No probable en este entorno (revisión estática)

| Componente | Revisión estática |
|---|---|
| `DllCall xinput1_4.dll\XInputGetState` | ✅ Firma correcta; offsets del struct `XINPUT_STATE` correctos (wButtons@4, sThumbLX@8, sThumbLY@10, sThumbRX@12, sThumbRY@14; buffer 16 bytes) |
| Deadzone | ✅ 8000 (razonable vs. 7849 por defecto de XInput) |
| `ControlSend("{" key " down}")` | ✅ Sintaxis válida para las teclas del ActionMap (incl. Up/Down/Left/Right, Space, LShift) |
| Manejo de desconexión del control | ✅ Transiciones `down/up` correctas; indicador de estado OK |
| Loop interrumpible | ✅ `EsperaInterrumpible` corta en ≤50ms; hotkeys pueden interrumpir durante `Sleep` |

---

## 4. Resultados de la prueba de arranque (dinámica)

El script completo se ejecutó con AutoHotkey v2.0.26 (wine): la GUI principal se crea, la lista de ventanas se llena, los timers de polling (15 ms), parpadeo de grabación y parpadeo de loop quedan activos, y no se registró ningún error en runtime durante la ejecución. ✅

---

## 5. Pendientes recomendados (fuera del alcance de esta prueba)

1. **Corregir el workflow CI** (3.1) y verificar que el push produce el `.exe` + release. Es el bloqueador #1: hoy no hay forma de distribuir el tool.
2. **Corregir el estado de checkboxes** (3.2) en una iteración futura.
3. Validación en Windows real: control Xbox (XInput), `ControlSend` contra un Target Manager real y confirmación de las equivalencias de `ActionMap` (especialmente stick derecho → flechas).
4. Confirmar la deadzone/sensibilidad del stick con hardware real.
5. Probar el `.exe` compilado (una vez el CI funcione) en una máquina sin AutoHotkey instalado.

---

*Reporte generado el 2026-08-03. Entorno: Linux (Terminus), AutoHotkey v2.0.26 oficial bajo wine 11.8, GitHub API para verificación del CI.*
