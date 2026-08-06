#Requires AutoHotkey v2.0

; ---------- ESTADO GLOBAL ----------
TargetWindows := Map()
LiveRelay := false
Recording := false
RecordedEvents := []
LastEventTime := 0
Looping := false

; ---------- SCHEDULER DEL LOOP (keep-alive contra Target Manager) ----------
; TM desconecta la consola si una ventana enlazada pasa ~3s sin recibir NINGUN
; evento nuevo, incluso si el input esta "congelado" en su ultimo estado. Con
; hasta 8 ventanas enlazadas, visitarlas todas una vez por evento grabado no
; alcanza para garantizar eso - hace falta un scheduler que ademas de entregar
; los eventos reales, reenvie el estado actual a cualquier ventana que lleve
; demasiado tiempo sin ser visitada. Ver LoopSchedulerTick.
HeldKeys := Map()          ; que teclas de salida estan "abajo" ahora mismo segun la reproduccion
WindowQueues := Map()      ; hwnd -> array de transiciones {key, action} pendientes de entregar
LastVisited := Map()       ; hwnd -> A_TickCount de la ultima vez que se le mando algo
EventIndex := 1            ; indice del proximo evento grabado a disparar
EventDueTick := 0          ; A_TickCount en el que ese evento vence
LoopSafetyMarginMs := 1500 ; margen ajustable, bien por debajo de los ~3000ms de riesgo
WindowActivateTimeoutSec := 0.3
EstimatedWindowVisitMs := 250 ; medido en pruebas locales con 2 ventanas reales (~985ms de ciclo / ~4 visitas)

; ---------- PERSISTENCIA DE MACROS (3 slots con nombre) ----------
MacrosFile := A_ScriptDir . "\ps5_macros.ini"
MacroSlots := []
Loop 3
    MacroSlots.Push(CargarSlot(A_Index))
ActiveSlot := 1
RecordedEvents := MacroSlots[ActiveSlot].events.Clone()

; ---------- CONTROL FISICO (XINPUT) ----------
ControllerIndex := 0
ControllerConnected := ""  ; desconocido al inicio, se detecta en el primer poll

XINPUT_GAMEPAD_A             := 0x1000
XINPUT_GAMEPAD_B             := 0x2000
XINPUT_GAMEPAD_X             := 0x4000
XINPUT_GAMEPAD_Y             := 0x8000
XINPUT_GAMEPAD_LEFT_SHOULDER := 0x0100
XINPUT_STICK_DEADZONE        := 8000

PrevButtons := 0
PrevAxisState := Map("LX_pos", false, "LX_neg", false, "LY_pos", false, "LY_neg", false,
                      "RX_pos", false, "RX_neg", false, "RY_pos", false, "RY_neg", false)

; ---------- MAPA DE ACCIONES ----------
; "output" es la tecla que se envia a los Target Managers enlazados (equivalencia
; de teclado que ya usan). "button"/"axis" describen de donde viene el input real
; en el control fisico de Xbox.
; NOTA: el stick derecho usa flechas (Up/Down/Left/Right) como equivalencia por
; defecto (uso comun para camara) - ajustar "output" si el TM usa otras teclas.
; "Cross" confirmado contra TM real = "L". El resto (Circle/Square/Triangle/L1/
; movimiento) siguen siendo valores por defecto sin confirmar - ajustar cuando
; se verifiquen contra la configuracion real del TM.
ActionMap := [
    {name: "MoveUp",    axis: "LY", dir: 1,  output: "w"},
    {name: "MoveDown",  axis: "LY", dir: -1, output: "s"},
    {name: "MoveLeft",  axis: "LX", dir: -1, output: "a"},
    {name: "MoveRight", axis: "LX", dir: 1,  output: "d"},
    {name: "LookUp",    axis: "RY", dir: 1,  output: "Up"},
    {name: "LookDown",  axis: "RY", dir: -1, output: "Down"},
    {name: "LookLeft",  axis: "RX", dir: -1, output: "Left"},
    {name: "LookRight", axis: "RX", dir: 1,  output: "Right"},
    {name: "Cross",     button: XINPUT_GAMEPAD_A,             output: "L"},
    {name: "Circle",    button: XINPUT_GAMEPAD_B,             output: "LShift"},
    {name: "Square",    button: XINPUT_GAMEPAD_X,             output: "q"},
    {name: "Triangle",  button: XINPUT_GAMEPAD_Y,             output: "e"},
    {name: "L1",        button: XINPUT_GAMEPAD_LEFT_SHOULDER, output: "f"},
]

TodosLosOutputs := []
for accion in ActionMap
    TodosLosOutputs.Push(accion.output)
; Lista plana de todas las teclas de salida posibles, usada por
; ReenviarEstadoCompleto para saber que soltar cuando no hay nada sostenido.

; ---------- INTERFAZ ----------
MainGui := Gui(, "PS5 Input Relay")
MainGui.Add("Text", , "Marca la casilla de una ventana para enlazarla / desenlazarla:")

LV := MainGui.Add("ListView", "r10 w500 Checked", ["Ventana", "Handle"])
LV.ModifyCol(1, 480)
LV.ModifyCol(2, 0)  ; oculta el handle - el usuario no lo necesita, pero el codigo si lo sigue usando
LV.OnEvent("ItemCheck", ToggleLink)

BtnRefresh := MainGui.Add("Button", , "🔄 Actualizar lista")
BtnRefresh.OnEvent("Click", RefreshWindowList)

; ---------- CONTROLES DE REPRODUCCION ----------
MainGui.Add("Text", "xm y+15", "Atajos: Ctrl+Espacio Relay | Ctrl+R Grabar | Ctrl+L Loop | Ctrl+P Detener loop")

BtnRelay := MainGui.Add("Button", "xm y+10 w120", "📡 Relay")
BtnRelay.OnEvent("Click", ToggleRelay)

BtnRecord := MainGui.Add("Button", "x+10 w120", "⏺ Grabar")
BtnRecord.OnEvent("Click", ToggleRecording)

BtnPlay := MainGui.Add("Button", "x+10 w120", "▶ Play Loop")
BtnPlay.OnEvent("Click", ReproducirLoop)

BtnStop := MainGui.Add("Button", "x+10 w120", "⏹ Stop Loop")
BtnStop.OnEvent("Click", DetenerLoop)

MainGui.Add("Text", "xm y+15", "Margen de seguridad del Loop (ms):")
EdMargen := MainGui.Add("Edit", "x+5 yp-4 w70", String(LoopSafetyMarginMs))
EdMargen.OnEvent("Change", ActualizarMargen)

ControllerStatusText := MainGui.Add("Text", "xm y+10 w500", "🎮 Control: buscando...")

MargenWarningText := MainGui.Add("Text", "xm y+5 w500 cRed", "")

; ---------- SELECTOR DE MACRO (desplegable, 3 slots persistentes) ----------
; Linea divisoria simple (estilo 0x10 = SS_ETCHEDHORZ) para separar
; visualmente esta seccion de los controles de reproduccion de arriba.
MainGui.Add("Text", "xm y+15 w500 h2 0x10")

; Fila siempre visible: flecha para desplegar, el slot elegido, reproducir
; ese slot, y si el Loop esta corriendo. Fila de detalle (nombre editable +
; renombrar + guardar + cantidad de eventos) solo se muestra al desplegar.
; Las posiciones de esta fila se calculan explicitamente desde la posicion
; real de BtnToggleMacros (en vez de encadenar offsets yp+/-N entre controles
; de distinta altura) para que no se amontonen entre si.
BtnToggleMacros := MainGui.Add("Button", "xm y+10 w30", "▼")
BtnToggleMacros.OnEvent("Click", ToggleMacroPanel)
BtnToggleMacros.GetPos(&filaMacroX, &filaMacroY, &filaMacroW, &filaMacroH)

MainGui.Add("Text", "x" . (filaMacroX + filaMacroW + 8) . " y" . (filaMacroY + 6), "Macro:")
SlotDropdown := MainGui.Add("DropDownList", "x+5 y" . filaMacroY . " w150 Choose1", NombresDeSlots())
SlotDropdown.OnEvent("Change", CambiarSlotActivo)

BtnReproducirMacro := MainGui.Add("Button", "x+10 y" . filaMacroY . " w110", "▶ Reproducir")
BtnReproducirMacro.OnEvent("Click", ReproducirMacroGuardado)

ReproducirEstadoText := MainGui.Add("Text", "x+15 y" . (filaMacroY + 6) . " w150", "Reproducir: OFF")

filaColapsableY := filaMacroY + filaMacroH + 10
EditSlotName := MainGui.Add("Edit", "xm y" . filaColapsableY . " w150", MacroSlots[1].name)

BtnRenombrar := MainGui.Add("Button", "x+5 y" . filaColapsableY . " w110", "✏ Renombrar")
BtnRenombrar.OnEvent("Click", RenombrarSlotActivo)

BtnGuardarMacro := MainGui.Add("Button", "x+5 y" . filaColapsableY . " w150", "💾 Guardar como macro")
BtnGuardarMacro.OnEvent("Click", GuardarComoMacro)

SlotInfoText := MainGui.Add("Text", "x+10 y" . (filaColapsableY + 6) . " w250", "")

MacroPanelExpandido := true

MainGui.Show()
RefreshWindowList()
ActualizarSlotInfoText()
SetTimer(PollController, 15)
SetTimer(ParpadeoLoop, 400)

; ---------- HOTKEYS GLOBALES (funcionan en cualquier ventana) ----------
^Space:: ToggleRelay()
^r:: ToggleRecording()
^l:: ReproducirLoop()
^p:: DetenerLoop()

; ---------- FUNCIONES ----------

ToggleRelay(*) {
    global LiveRelay, BtnRelay
    LiveRelay := !LiveRelay
    BtnRelay.Text := LiveRelay ? "📡 Relay: ON" : "📡 Relay"
    ToolTip("Relay: " . (LiveRelay ? "ON" : "OFF"))
    SetTimer(() => ToolTip(), -800)
}
; Prende/apaga el Relay en vivo (manda el input del control en tiempo real a
; las ventanas enlazadas via EnviarATodasLasVentanas, sin robar el foco).

ToggleRecording(*) {
    global Recording, RecordedEvents, LastEventTime, BtnRecord
    Recording := !Recording
    if (Recording) {
        RecordedEvents := []
        LastEventTime := A_TickCount
        BtnRecord.Text := "⏺ Grabando..."
        ToolTip("Grabando: SI")
    } else {
        BtnRecord.Text := "⏺ Grabar"
        ActualizarSlotInfoText()
        ToolTip("Grabacion detenida: " . RecordedEvents.Length . " eventos. Usa 'Guardar como macro' para no perderla.")
    }
    SetTimer(() => ToolTip(), -1200)
}
; Al detener la grabacion, la deja lista en memoria (para "Play Loop"
; inmediato) pero NO la guarda a disco sola - hay que usar el boton "Guardar
; como macro" a proposito. Asi no cualquier grabacion de prueba pisa un slot
; guardado sin querer.

SerializarEventos(eventos) {
    texto := ""
    for evt in eventos {
        if (texto != "")
            texto .= ";"
        texto .= evt.key . "|" . evt.action . "|" . evt.delay
    }
    return texto
}
; Convierte el array de eventos grabados a un texto delimitado (";" entre
; eventos, "|" entre campos) para poder guardarlo en una linea de INI.
; Asume que ninguna tecla de salida del ActionMap contiene esos caracteres.

ParsearEventos(texto) {
    eventos := []
    if (texto = "")
        return eventos
    for parte in StrSplit(texto, ";") {
        campos := StrSplit(parte, "|")
        if (campos.Length != 3)
            continue
        eventos.Push({key: campos[1], action: campos[2], delay: Integer(campos[3])})
    }
    return eventos
}
; Proceso inverso a SerializarEventos - reconstruye el array de eventos a
; partir del texto guardado en el INI.

GuardarSlot(n, nombre, eventos) {
    global MacrosFile
    seccion := "Slot" . n
    IniWrite(nombre, MacrosFile, seccion, "Name")
    IniWrite(SerializarEventos(eventos), MacrosFile, seccion, "Events")
}
; Escribe el nombre y los eventos de un slot en ps5_macros.ini.

CargarSlot(n) {
    global MacrosFile
    seccion := "Slot" . n
    nombre := IniRead(MacrosFile, seccion, "Name", "Slot " . n)
    eventosTexto := IniRead(MacrosFile, seccion, "Events", "")
    return {name: nombre, events: ParsearEventos(eventosTexto)}
}
; Lee un slot desde ps5_macros.ini. Si el archivo/seccion no existe todavia
; (primera vez que corre el programa), IniRead devuelve los valores por
; defecto ("Slot N", sin eventos) sin necesidad de chequear existencia.

NombresDeSlots() {
    global MacroSlots
    nombres := []
    for slot in MacroSlots
        nombres.Push(slot.name)
    return nombres
}
; Devuelve los 3 nombres de slot actuales, usado para poblar el dropdown.

CambiarSlotActivo(ctrl, *) {
    global ActiveSlot, MacroSlots, EditSlotName, SlotDropdown
    ActiveSlot := SlotDropdown.Value
    EditSlotName.Text := MacroSlots[ActiveSlot].name
    ActualizarSlotInfoText()
}
; Se ejecuta al elegir otro slot en el dropdown. Solo cambia cual es el slot
; "activo" (a donde apunta Guardar/Renombrar) y refresca la info mostrada -
; NO toca RecordedEvents, para no pisar una grabacion en curso solo por
; mirar otro slot. Para cargar y reproducir ese slot, usar "Reproducir".

ReproducirMacroGuardado(*) {
    global RecordedEvents, MacroSlots, ActiveSlot
    RecordedEvents := MacroSlots[ActiveSlot].events.Clone()
    ActualizarSlotInfoText()
    ReproducirLoop()
}
; Carga los eventos guardados del slot activo como la grabacion de trabajo y
; arranca el Loop de inmediato - la via explicita para reproducir un macro
; guardado, separada de "Play Loop" (que reproduce lo ultimo grabado/cargado).

GuardarComoMacro(*) {
    global RecordedEvents, MacroSlots, ActiveSlot
    if (RecordedEvents.Length = 0) {
        MsgBox("No hay ninguna grabacion todavia para guardar. Usa Grabar primero.")
        return
    }
    MacroSlots[ActiveSlot].events := RecordedEvents.Clone()
    GuardarSlot(ActiveSlot, MacroSlots[ActiveSlot].name, RecordedEvents)
    ActualizarSlotInfoText()
    ToolTip("Guardado en: " . MacroSlots[ActiveSlot].name)
    SetTimer(() => ToolTip(), -1200)
}
; Guarda la grabacion actual (RecordedEvents) en el slot activo y persiste a
; disco. Es el unico lugar donde una grabacion pasa de "en memoria" a
; "guardada" - grabar solo (ToggleRecording) ya no guarda automaticamente.

RenombrarSlotActivo(*) {
    global ActiveSlot, MacroSlots, EditSlotName, SlotDropdown
    nuevoNombre := Trim(EditSlotName.Text)
    if (nuevoNombre = "")
        nuevoNombre := "Slot " . ActiveSlot
    MacroSlots[ActiveSlot].name := nuevoNombre
    GuardarSlot(ActiveSlot, nuevoNombre, MacroSlots[ActiveSlot].events)
    SlotDropdown.Delete()
    SlotDropdown.Add(NombresDeSlots())
    SlotDropdown.Choose(ActiveSlot)
    ToolTip("Renombrado a: " . nuevoNombre)
    SetTimer(() => ToolTip(), -1000)
}
; Renombra el slot activo (con un nombre por defecto si se deja vacio),
; persiste el cambio a disco, y refresca el dropdown ya que un DropDownList
; no permite renombrar un item existente in-place.

ActualizarSlotInfoText() {
    global SlotInfoText, MacroSlots, ActiveSlot, RecordedEvents
    guardados := MacroSlots[ActiveSlot].events.Length
    texto := MacroSlots[ActiveSlot].name . ": " . guardados . " eventos guardados"
    if (RecordedEvents.Length != guardados)
        texto .= " (grabación actual sin guardar: " . RecordedEvents.Length . " eventos)"
    SlotInfoText.Text := texto
}
; Refresca el texto informativo: cuantos eventos tiene realmente guardados el
; slot activo, y si la grabacion actual en memoria (RecordedEvents) difiere
; de eso, lo aclara aparte - para que quede claro que grabar solo no guarda.

ToggleMacroPanel(*) {
    global MacroPanelExpandido, BtnToggleMacros, EditSlotName, BtnRenombrar, BtnGuardarMacro, SlotInfoText

    MacroPanelExpandido := !MacroPanelExpandido
    EditSlotName.Visible := MacroPanelExpandido
    BtnRenombrar.Visible := MacroPanelExpandido
    BtnGuardarMacro.Visible := MacroPanelExpandido
    SlotInfoText.Visible := MacroPanelExpandido
    BtnToggleMacros.Text := MacroPanelExpandido ? "▼" : "▶"
}
; Despliega/colapsa la fila de detalle del slot (nombre editable, renombrar,
; guardar como macro, cantidad de eventos). Colapsado solo queda visible la
; flecha, el dropdown de slot, "Reproducir" y el indicador "Reproducir:
; ON/OFF". Es la ultima fila del panel, asi que no hay nada debajo que
; reacomodar al ocultar/mostrar - solo deja un espacio en blanco cuando esta
; colapsado.

DetenerLoop(*) {
    global Looping
    Looping := false
    ToolTip("Loop detenido")
    SetTimer(() => ToolTip(), -800)
}
; Corta el bucle del scheduler (ReproducirLoop revisa Looping en cada
; iteracion y sale limpiamente al verlo en false).

ParpadeoLoop(*) {
    global Looping, BtnPlay, ReproducirEstadoText
    static visible := true
    if (Looping) {
        visible := !visible
        BtnPlay.Text := visible ? "🔴 Loop corriendo" : "⚫ Loop corriendo"
        ReproducirEstadoText.Text := "Reproducir: ON"
    } else {
        visible := true
        BtnPlay.Text := "▶ Play Loop"
        ReproducirEstadoText.Text := "Reproducir: OFF"
    }
}
; Hace parpadear el punto de color dentro del boton de Play Loop mientras
; Looping este activo, y mantiene sincronizado el indicador "Reproducir:
; ON/OFF" de la fila colapsable de macros. Al detenerse, el boton vuelve a
; su texto normal.

PollController() {
    global ControllerIndex, PrevButtons, ControllerConnected, ControllerStatusText

    buf := Buffer(16, 0)
    result := DllCall("xinput1_4.dll\XInputGetState", "UInt", ControllerIndex, "Ptr", buf)
    conectadoAhora := (result = 0)
    if (conectadoAhora != ControllerConnected) {
        ControllerConnected := conectadoAhora
        if (conectadoAhora) {
            ControllerStatusText.Text := "🎮 Control: Conectado"
            ControllerStatusText.SetFont("cGreen")
        } else {
            ControllerStatusText.Text := "🎮 Control: No detectado"
            ControllerStatusText.SetFont("cRed")
        }
    }
    if !conectadoAhora
        return

    wButtons := NumGet(buf, 4, "UShort")
    sThumbLX := NumGet(buf, 8, "Short")
    sThumbLY := NumGet(buf, 10, "Short")
    sThumbRX := NumGet(buf, 12, "Short")
    sThumbRY := NumGet(buf, 14, "Short")

    for accion in ActionMap {
        if !accion.HasOwnProp("button")
            continue
        estaPresionado := (wButtons & accion.button) != 0
        estabaPresionado := (PrevButtons & accion.button) != 0
        if (estaPresionado && !estabaPresionado)
            ProcesarEvento(accion.name, "down")
        else if (!estaPresionado && estabaPresionado)
            ProcesarEvento(accion.name, "up")
    }
    PrevButtons := wButtons

    ChequearEje("LX", sThumbLX)
    ChequearEje("LY", sThumbLY)
    ChequearEje("RX", sThumbRX)
    ChequearEje("RY", sThumbRY)
}
; Sondea el control fisico (XInput) cada 15ms. Compara el estado actual contra
; el anterior para detectar transiciones down/up de botones y direcciones de
; stick, y las despacha a ProcesarEvento. Tambien mantiene el indicador de
; conexion del control en la UI.

ChequearEje(eje, valor) {
    global ActionMap, PrevAxisState, XINPUT_STICK_DEADZONE

    dirActual := 0
    if (valor > XINPUT_STICK_DEADZONE)
        dirActual := 1
    else if (valor < -XINPUT_STICK_DEADZONE)
        dirActual := -1

    for accion in ActionMap {
        if !accion.HasOwnProp("axis") || accion.axis != eje
            continue
        claveEstado := eje . "_" . (accion.dir = 1 ? "pos" : "neg")
        activoAhora := (dirActual = accion.dir)
        activoAntes := PrevAxisState[claveEstado]
        if (activoAhora && !activoAntes)
            ProcesarEvento(accion.name, "down")
        else if (!activoAhora && activoAntes)
            ProcesarEvento(accion.name, "up")
        PrevAxisState[claveEstado] := activoAhora
    }
}
; Convierte el valor analogico de un eje del stick en dos direcciones digitales
; (positiva/negativa) usando una zona muerta, y dispara ProcesarEvento en cada
; transicion, igual que con los botones.

ProcesarEvento(nombreAccion, downOrUp) {
    global LiveRelay, ActionMap, Recording, RecordedEvents, LastEventTime

    accion := ""
    for a in ActionMap {
        if (a.name = nombreAccion)
            accion := a
    }
    if (accion = "")
        return

    if (LiveRelay || Recording) {
        ToolTip(nombreAccion . " " . downOrUp)
        SetTimer(() => ToolTip(), -400)
    }

    if (LiveRelay)
        EnviarATodasLasVentanas(accion.output, downOrUp)

    if (Recording) {
        ahora := A_TickCount
        RecordedEvents.Push({key: accion.output, action: downOrUp, delay: ahora - LastEventTime})
        LastEventTime := ahora
    }
}
; Se ejecuta cada vez que el control fisico genera un evento (boton o stick).
; Busca la accion correspondiente, la envia en vivo si el Relay esta activo,
; y la guarda en RecordedEvents si se esta grabando.

EnviarATodasLasVentanas(outputKey, downOrUp) {
    global TargetWindows
    for hwnd, title in TargetWindows {
        try {
            if !WinExist("ahk_id " . hwnd)
                continue
            if (downOrUp = "down")
                ControlSend("{" . outputKey . " down}", , "ahk_id " . hwnd)
            else
                ControlSend("{" . outputKey . " up}", , "ahk_id " . hwnd)
        }
    }
}
; Manda la tecla equivalente a cada ventana enlazada (TargetWindows) usando
; ControlSend, sin activar ni robar el foco. Usado por el Relay en vivo -
; funciona bien contra ventanas normales (navegador, apps de prueba), pero NO
; contra el Target Manager de PS5, que ignora esto (ver el scheduler del Loop,
; empezando en ActivarVentana/VisitarVentana mas abajo).

ActivarVentana(hwnd) {
    global WindowActivateTimeoutSec
    if !WinExist("ahk_id " . hwnd)
        return false
    WinActivate("ahk_id " . hwnd)
    return WinWaitActive("ahk_id " . hwnd, , WindowActivateTimeoutSec) ? true : false
}
; Activa una ventana y espera a que realmente tenga el foco (con timeout).
; Devuelve false si la ventana ya no existe o no llego a activarse a tiempo,
; para que quien la llame la reintente en el siguiente ciclo sin romperse.

ReenviarEstadoCompleto(hwnd) {
    global HeldKeys, TodosLosOutputs
    if (HeldKeys.Count > 0) {
        for outputKey, valor in HeldKeys
            Send("{" . outputKey . " down}")
    } else {
        for outputKey in TodosLosOutputs
            Send("{" . outputKey . " up}")
    }
}
; Keep-alive: reenvia el estado actual a una ventana que no le debe ningun
; evento real, para que TM no la vea "muda" por mucho tiempo. Si hay teclas
; sostenidas, las vuelve a mandar "down" (igual al autorepeat de un teclado
; real); si no hay nada sostenido, manda "up" de todas las teclas conocidas -
; genera un evento real sin introducir una pulsacion fantasma.

VisitarVentana(hwnd) {
    global WindowQueues, LastVisited
    if !ActivarVentana(hwnd)
        return

    if (WindowQueues.Has(hwnd) && WindowQueues[hwnd].Length > 0) {
        evt := WindowQueues[hwnd].RemoveAt(1)
        Send("{" . evt.key . " " . evt.action . "}")
    } else {
        ReenviarEstadoCompleto(hwnd)
    }

    LastVisited[hwnd] := A_TickCount
}
; Visita una ventana enlazada: si tiene una transicion real pendiente en su
; cola, la entrega (en orden, aunque el momento exacto se desfase un poco por
; el tiempo de activar la ventana); si no, hace un keep-alive.

AvanzarRelojDeReproduccion() {
    global RecordedEvents, EventIndex, EventDueTick, HeldKeys, WindowQueues, TargetWindows
    while (A_TickCount >= EventDueTick) {
        evt := RecordedEvents[EventIndex]

        if (evt.action = "down")
            HeldKeys[evt.key] := true
        else
            HeldKeys.Delete(evt.key)

        for hwnd, title in TargetWindows {
            if !WindowQueues.Has(hwnd)
                WindowQueues[hwnd] := []
            WindowQueues[hwnd].Push({key: evt.key, action: evt.action})
        }

        EventIndex += 1
        if (EventIndex > RecordedEvents.Length)
            EventIndex := 1
        EventDueTick := A_TickCount + RecordedEvents[EventIndex].delay
    }
}
; Avanza el reloj de reproduccion: mientras el proximo evento grabado ya este
; vencido, lo aplica (actualiza HeldKeys y encola la transicion para todas las
; ventanas enlazadas), y calcula cuando vence el siguiente. Usa "while" en vez
; de "if" para no perder eventos simultaneos (delay 0). El reloj es relativo -
; si el scheduler se atrasa sirviendo muchas ventanas, no intenta "ponerse al
; dia" de golpe, solo acepta el desfase.

ElegirVentanaAVisitar() {
    global TargetWindows, WindowQueues, LastVisited, LoopSafetyMarginMs

    masViejoConCola := ""
    tickMasViejoConCola := 0
    for hwnd, title in TargetWindows {
        if (WindowQueues.Has(hwnd) && WindowQueues[hwnd].Length > 0) {
            visitado := LastVisited.Has(hwnd) ? LastVisited[hwnd] : 0
            if (masViejoConCola = "" || visitado < tickMasViejoConCola) {
                tickMasViejoConCola := visitado
                masViejoConCola := hwnd
            }
        }
    }
    if (masViejoConCola != "")
        return masViejoConCola

    masViejoKeepAlive := ""
    tickMasViejoKeepAlive := 0
    for hwnd, title in TargetWindows {
        visitado := LastVisited.Has(hwnd) ? LastVisited[hwnd] : 0
        if (masViejoKeepAlive = "" || visitado < tickMasViejoKeepAlive) {
            tickMasViejoKeepAlive := visitado
            masViejoKeepAlive := hwnd
        }
    }
    if (masViejoKeepAlive != "" && (A_TickCount - tickMasViejoKeepAlive) >= (LoopSafetyMarginMs / 2))
        return masViejoKeepAlive

    return ""
}
; Decide que ventana visitar en este ciclo: prioriza cualquiera que le deba
; una transicion real (la mas atrasada primero), y si ninguna debe nada,
; revisa si alguna esta por vencer su margen de keep-alive (a la mitad del
; margen configurado, con colchon extra antes del limite real). Devuelve ""
; si no hace falta visitar nada todavia.

LoopSchedulerTick() {
    AvanzarRelojDeReproduccion()
    hwnd := ElegirVentanaAVisitar()
    if (hwnd = "") {
        EsperaInterrumpible(20)
        return
    }
    VisitarVentana(hwnd)
}
; Un paso del scheduler: avanza el reloj de reproduccion y visita la ventana
; mas urgente (evento real pendiente, o keep-alive por vencer). Si nada
; necesita atencion todavia, espera un poco en vez de girar en vacio.

VerificarMargenSeguridad() {
    global TargetWindows, LoopSafetyMarginMs, MargenWarningText, EstimatedWindowVisitMs
    presupuestoEstimado := TargetWindows.Count * EstimatedWindowVisitMs
    if (presupuestoEstimado > LoopSafetyMarginMs) {
        MargenWarningText.Text := "⚠ " . TargetWindows.Count . " ventanas ≈ " . presupuestoEstimado
            . "ms por ciclo completo, pero el margen es " . LoopSafetyMarginMs
            . "ms - sube el margen o enlaza menos ventanas."
    } else {
        MargenWarningText.Text := ""
    }
}
; Compara cuantas ventanas hay enlazadas contra el margen de seguridad
; configurado (con un estimado de tiempo por visita, no medido) y muestra un
; aviso no bloqueante si el margen podria quedar corto. Se llama al iniciar
; el Loop y cada vez que se enlaza/desenlaza una ventana mientras corre.

ActualizarMargen(ctrl, *) {
    global LoopSafetyMarginMs
    if !IsInteger(ctrl.Text)
        return
    valor := Integer(ctrl.Text)
    if (valor < 300 || valor > 2900)
        return
    LoopSafetyMarginMs := valor
    VerificarMargenSeguridad()
}
; Actualiza el margen de seguridad en vivo desde el campo de texto (valida
; que sea un numero entero razonable, entre 300 y 2900ms). Aplica de
; inmediato, incluso a mitad de un Loop corriendo.

ReproducirLoop(*) {
    global Looping, RecordedEvents, MainGui, TargetWindows
    global HeldKeys, WindowQueues, LastVisited, EventIndex, EventDueTick
    global SlotDropdown, EditSlotName, BtnRenombrar, BtnReproducirMacro, BtnGuardarMacro

    if (RecordedEvents.Length = 0) {
        MsgBox("No hay ninguna grabacion todavia. Usa Ctrl+R o el boton Grabar primero.")
        return
    }
    if (TargetWindows.Count = 0) {
        MsgBox("No hay ninguna ventana enlazada. Marca al menos una casilla de la lista.")
        return
    }

    HeldKeys := Map()
    WindowQueues := Map()
    LastVisited := Map()
    for hwnd, title in TargetWindows {
        WindowQueues[hwnd] := []
        LastVisited[hwnd] := 0
    }
    EventIndex := 1
    EventDueTick := A_TickCount + RecordedEvents[1].delay
    VerificarMargenSeguridad()

    SlotDropdown.Enabled := false
    EditSlotName.Enabled := false
    BtnRenombrar.Enabled := false
    BtnReproducirMacro.Enabled := false
    BtnGuardarMacro.Enabled := false

    Looping := true
    while (Looping)
        LoopSchedulerTick()

    SlotDropdown.Enabled := true
    EditSlotName.Enabled := true
    BtnRenombrar.Enabled := true
    BtnReproducirMacro.Enabled := true
    BtnGuardarMacro.Enabled := true

    try WinActivate("ahk_id " . MainGui.Hwnd)
}
; Arranca el scheduler del Loop: valida que haya grabacion y al menos una
; ventana enlazada, resetea el estado del scheduler (todas las ventanas
; quedan "maximamente atrasadas" para forzar una primera visita de resync a
; cada una antes de reproducir eventos reales), y corre LoopSchedulerTick en
; bucle hasta que Looping se ponga en false (Ctrl+P o boton Stop Loop). Al
; salir, reactiva el selector de macro y devuelve el foco al panel principal.

EsperaInterrumpible(ms) {
    global Looping
    restante := ms
    while (restante > 0 && Looping) {
        pedazo := Min(50, restante)
        Sleep(pedazo)
        restante -= pedazo
    }
}
; Espera "ms" milisegundos, pero revisando cada 50ms si Looping sigue
; activo, para poder cortar el loop rapido en vez de quedar sordo
; durante una espera larga.

RefreshWindowList(*) {
    global TargetWindows
    for hwnd in TargetWindows.Clone() {
        if !WinExist("ahk_id " . hwnd)
            TargetWindows.Delete(hwnd)
    }
    LV.Delete()
    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle("ahk_id " . hwnd)
        if (title = "")
            continue
        opciones := TargetWindows.Has(hwnd) ? "Check" : ""
        LV.Add(opciones, title, hwnd)
    }
}
; Vacia la tabla y la vuelve a llenar con todas las ventanas abiertas
; actualmente en Windows. Antes de eso, quita de TargetWindows cualquier
; ventana enlazada que ya se haya cerrado, y deja marcada la casilla de
; las que sigan vigentes.

ToggleLink(ctrl, row, checked) {
    global TargetWindows, Looping, WindowQueues, LastVisited
    if !row
        return
    title := LV.GetText(row, 1)
    hwnd := Integer(LV.GetText(row, 2))
    if (checked) {
        TargetWindows[hwnd] := title
        if (Looping) {
            WindowQueues[hwnd] := []
            LastVisited[hwnd] := 0
        }
    } else {
        TargetWindows.Delete(hwnd)
        if (Looping) {
            WindowQueues.Delete(hwnd)
            LastVisited.Delete(hwnd)
        }
    }
    if (Looping)
        VerificarMargenSeguridad()
}
; Se ejecuta al marcar/desmarcar la casilla de una fila. Si se marco, agrega
; la ventana a TargetWindows; si se desmarco, la quita. Si el Loop esta
; corriendo, tambien siembra/limpia sus entradas en el scheduler (para que
; una ventana enlazada a mitad de un Loop reciba su primera visita de
; inmediato) y refresca el aviso de margen de seguridad.
; NOTA: LV.GetText() devuelve el handle como string; se convierte a Integer
; explicitamente porque WinGetList() (usado en RefreshWindowList) devuelve
; enteros, y Map.Has()/Delete() distinguen clave int de clave string aunque
; representen el mismo numero - sin esta conversion, los checkboxes se veian
; desmarcados tras refrescar la lista aunque la ventana seguia enlazada.
