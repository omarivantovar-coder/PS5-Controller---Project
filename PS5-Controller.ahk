#Requires AutoHotkey v2.0

; ---------- ESTADO GLOBAL ----------
TargetWindows := Map()
LiveRelay := false
Recording := false
RecordedEvents := []
LastEventTime := 0
Looping := false

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
PrevAxisState := Map("LX_pos", false, "LX_neg", false, "LY_pos", false, "LY_neg", false)

; ---------- MAPA DE ACCIONES ----------
; "output" es la tecla que se envia a los Target Managers enlazados (equivalencia
; de teclado que ya usan). "button"/"axis" describen de donde viene el input real
; en el control fisico de Xbox.
ActionMap := [
    {name: "MoveUp",    axis: "LY", dir: 1,  output: "w"},
    {name: "MoveDown",  axis: "LY", dir: -1, output: "s"},
    {name: "MoveLeft",  axis: "LX", dir: -1, output: "a"},
    {name: "MoveRight", axis: "LX", dir: 1,  output: "d"},
    {name: "Cross",     button: XINPUT_GAMEPAD_A,             output: "Space"},
    {name: "Circle",    button: XINPUT_GAMEPAD_B,             output: "LShift"},
    {name: "Square",    button: XINPUT_GAMEPAD_X,             output: "q"},
    {name: "Triangle",  button: XINPUT_GAMEPAD_Y,             output: "e"},
    {name: "L1",        button: XINPUT_GAMEPAD_LEFT_SHOULDER, output: "f"},
]

; ---------- INTERFAZ ----------
MainGui := Gui(, "PS5 Input Relay")
MainGui.Add("Text", , "Doble clic sobre una ventana para enlazar / desenlazar:")

LV := MainGui.Add("ListView", "r10 w500", ["Ventana", "Handle", "Estado"])
LV.ModifyCol(1, 300)
LV.OnEvent("DoubleClick", ToggleLink)

BtnRefresh := MainGui.Add("Button", , "Actualizar lista")
BtnRefresh.OnEvent("Click", RefreshWindowList)

MainGui.Add("Text", "xm y+15", "Atajos: Ctrl+Espacio Relay | Ctrl+R Grabar | Ctrl+L Loop | Ctrl+P Detener loop")

BtnRelay := MainGui.Add("Button", "xm y+10 w120", "Relay")
BtnRelay.OnEvent("Click", ToggleRelay)

BtnRecord := MainGui.Add("Button", "x+10 w120", "Grabar")
BtnRecord.OnEvent("Click", ToggleRecording)

BtnPlay := MainGui.Add("Button", "x+10 w120", "Play Loop")
BtnPlay.OnEvent("Click", ReproducirLoop)

BtnStop := MainGui.Add("Button", "x+10 w120", "Stop Loop")
BtnStop.OnEvent("Click", DetenerLoop)

StatusText := MainGui.Add("Text", "xm y+15 w500", "🔴 Relay | 🔴 Grabando | 🔴 Loop")
ControllerStatusText := MainGui.Add("Text", "xm y+5 w500", "🎮 Control: buscando...")

MainGui.Show()
RefreshWindowList()
SetTimer(PollController, 15)

; ---------- HOTKEYS GLOBALES (funcionan en cualquier ventana) ----------
^Space:: ToggleRelay()
^r:: ToggleRecording()
^l:: ReproducirLoop()
^p:: DetenerLoop()

; ---------- FUNCIONES ----------

ToggleRelay(*) {
    global LiveRelay
    LiveRelay := !LiveRelay
    ToolTip("Relay: " . (LiveRelay ? "ON" : "OFF"))
    SetTimer(() => ToolTip(), -800)
    ActualizarStatus()
}

ToggleRecording(*) {
    global Recording, RecordedEvents, LastEventTime
    Recording := !Recording
    if (Recording) {
        RecordedEvents := []
        LastEventTime := A_TickCount
        ToolTip("Grabando: SI")
    } else {
        ToolTip("Grabacion detenida: " . RecordedEvents.Length . " eventos guardados")
    }
    SetTimer(() => ToolTip(), -1200)
    ActualizarStatus()
}

DetenerLoop(*) {
    global Looping
    Looping := false
    ToolTip("Loop detenido")
    SetTimer(() => ToolTip(), -800)
    ActualizarStatus()
}

PollController() {
    global ControllerIndex, PrevButtons, ControllerConnected, ControllerStatusText

    buf := Buffer(16, 0)
    result := DllCall("xinput1_4.dll\XInputGetState", "UInt", ControllerIndex, "Ptr", buf)
    conectadoAhora := (result = 0)
    if (conectadoAhora != ControllerConnected) {
        ControllerConnected := conectadoAhora
        ControllerStatusText.Text := conectadoAhora ? "🎮 Control: Conectado" : "🎮 Control: No detectado"
    }
    if !conectadoAhora
        return

    wButtons := NumGet(buf, 4, "UShort")
    sThumbLX := NumGet(buf, 8, "Short")
    sThumbLY := NumGet(buf, 10, "Short")

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
; ControlSend, que entrega el mensaje directo a la ventana destino sin
; activarla ni robar el foco/mouse del usuario.

ReproducirLoop(*) {
    global Looping, RecordedEvents
    if (RecordedEvents.Length = 0) {
        MsgBox("No hay ninguna grabacion todavia. Usa Ctrl+R o el boton Grabar primero.")
        return
    }
    Looping := true
    ActualizarStatus()
    while (Looping) {
        for evt in RecordedEvents {
            if (!Looping)
                break
            EsperaInterrumpible(evt.delay)
            if (!Looping)
                break
            EnviarATodasLasVentanas(evt.key, evt.action)
        }
    }
    ActualizarStatus()
}
; Reproduce la secuencia grabada (RecordedEvents) en loop indefinido,
; respetando los tiempos originales entre teclas, hasta que Looping
; se ponga en false (Ctrl+P o boton Stop Loop).

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
        estado := TargetWindows.Has(hwnd) ? "Enlazado" : "Desenlazado"
        LV.Add(, title, hwnd, estado)
    }
}
; Vacia la tabla y la vuelve a llenar con todas las ventanas abiertas
; actualmente en Windows. Antes de eso, quita de TargetWindows cualquier
; ventana enlazada que ya se haya cerrado, y marca en la tabla como
; "Enlazado" las que sigan vigentes.

ToggleLink(ctrl, row) {
    if !row
        return
    title := LV.GetText(row, 1)
    hwnd := LV.GetText(row, 2)
    if TargetWindows.Has(hwnd) {
        TargetWindows.Delete(hwnd)
        LV.Modify(row, , , , "Desenlazado")
    } else {
        TargetWindows[hwnd] := title
        LV.Modify(row, , , , "Enlazado")
    }
}
; Se ejecuta al hacer doble clic en una fila de la tabla. Si la ventana
; ya estaba enlazada, la quita de TargetWindows; si no, la agrega.

ActualizarStatus() {
    global StatusText, LiveRelay, Recording, Looping
    relayIcono := LiveRelay ? "🟢" : "🔴"
    grabandoIcono := Recording ? "🟢" : "🔴"
    loopIcono := Looping ? "🟢" : "🔴"
    StatusText.Text := relayIcono . " Relay | " . grabandoIcono . " Grabando | " . loopIcono . " Loop"
}
; Actualiza el texto del panel con los 3 indicadores (Relay, Grabando,
; Loop) segun el estado actual de esas 3 variables globales.
