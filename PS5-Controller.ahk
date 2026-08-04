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
PrevAxisState := Map("LX_pos", false, "LX_neg", false, "LY_pos", false, "LY_neg", false,
                      "RX_pos", false, "RX_neg", false, "RY_pos", false, "RY_neg", false)

; ---------- MAPA DE ACCIONES ----------
; "output" es la tecla que se envia a los Target Managers enlazados (equivalencia
; de teclado que ya usan). "button"/"axis" describen de donde viene el input real
; en el control fisico de Xbox.
; NOTA: el stick derecho usa flechas (Up/Down/Left/Right) como equivalencia por
; defecto (uso comun para camara) - ajustar "output" si el TM usa otras teclas.
ActionMap := [
    {name: "MoveUp",    axis: "LY", dir: 1,  output: "w"},
    {name: "MoveDown",  axis: "LY", dir: -1, output: "s"},
    {name: "MoveLeft",  axis: "LX", dir: -1, output: "a"},
    {name: "MoveRight", axis: "LX", dir: 1,  output: "d"},
    {name: "LookUp",    axis: "RY", dir: 1,  output: "Up"},
    {name: "LookDown",  axis: "RY", dir: -1, output: "Down"},
    {name: "LookLeft",  axis: "RX", dir: -1, output: "Left"},
    {name: "LookRight", axis: "RX", dir: 1,  output: "Right"},
    {name: "Cross",     button: XINPUT_GAMEPAD_A,             output: "Space"},
    {name: "Circle",    button: XINPUT_GAMEPAD_B,             output: "LShift"},
    {name: "Square",    button: XINPUT_GAMEPAD_X,             output: "q"},
    {name: "Triangle",  button: XINPUT_GAMEPAD_Y,             output: "e"},
    {name: "L1",        button: XINPUT_GAMEPAD_LEFT_SHOULDER, output: "f"},
]

; ---------- INTERFAZ ----------
MainGui := Gui(, "PS5 Input Relay")
MainGui.Add("Text", , "Marca la casilla de una ventana para enlazarla / desenlazarla:")

LV := MainGui.Add("ListView", "r10 w500 Checked", ["Ventana", "Handle"])
LV.ModifyCol(1, 350)
LV.OnEvent("ItemCheck", ToggleLink)

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

ControllerStatusText := MainGui.Add("Text", "xm y+15 w500", "🎮 Control: buscando...")

BtnAdvanced := MainGui.Add("Button", "xm y+10 w200", "Ver vista avanzada")
BtnAdvanced.OnEvent("Click", ToggleAdvancedView)
AdvancedVisible := false

; ---------- VENTANA SECUNDARIA: VISTA AVANZADA ----------
; Vive aparte para no agrandar el panel principal. Muestra el detalle en vivo
; de cada boton/stick (mas oscuro = presionado) - util para depurar, no para
; el uso diario.
AdvancedGui := Gui(, "PS5 Input Relay - Vista avanzada")
AdvancedGui.OnEvent("Close", CerrarVistaAvanzada)

RecIndicator := AdvancedGui.Add("Text", "xm w500 cRed", "")
RecIndicator.SetFont("s14 Bold")

AccionText := AdvancedGui.Add("Text", "xm y+5 w500", "Ultima accion: -")

AdvancedGui.Add("Text", "xm y+15", "Estado en vivo (mas oscuro = presionado):")
BotonControls := Map()

AdvancedGui.Add("Text", "xm y+8", "Stick izquierdo:")
primero := true
for accion in ActionMap {
    if !accion.HasOwnProp("axis") || (accion.axis != "LX" && accion.axis != "LY")
        continue
    BotonControls[accion.name] := CrearIndicador(accion.name, primero)
    primero := false
}

AdvancedGui.Add("Text", "xm y+8", "Stick derecho:")
primero := true
for accion in ActionMap {
    if !accion.HasOwnProp("axis") || (accion.axis != "RX" && accion.axis != "RY")
        continue
    BotonControls[accion.name] := CrearIndicador(accion.name, primero)
    primero := false
}

AdvancedGui.Add("Text", "xm y+8", "Botones:")
primero := true
for accion in ActionMap {
    if !accion.HasOwnProp("button")
        continue
    BotonControls[accion.name] := CrearIndicador(accion.name, primero)
    primero := false
}

MainGui.Show()
RefreshWindowList()
SetTimer(PollController, 15)
SetTimer(ParpadeoRec, 500)
SetTimer(ParpadeoLoop, 400)

; ---------- HOTKEYS GLOBALES (funcionan en cualquier ventana) ----------
^Space:: ToggleRelay()
^r:: ToggleRecording()
^l:: ReproducirLoop()
^p:: DetenerLoop()

; ---------- FUNCIONES ----------

CrearIndicador(texto, primero) {
    global AdvancedGui
    opts := primero ? "xm y+6 w70 h26 Center Border cGray" : "x+6 yp w70 h26 Center Border cGray"
    return AdvancedGui.Add("Text", opts, texto)
}
; Crea una casilla de indicador para una accion del ActionMap, dentro de la
; ventana de vista avanzada. "primero" controla si arranca una fila nueva
; (xm) o continua la fila actual (x+6 yp).

ToggleAdvancedView(*) {
    global AdvancedGui, AdvancedVisible, BtnAdvanced
    AdvancedVisible := !AdvancedVisible
    if AdvancedVisible {
        AdvancedGui.Show()
        BtnAdvanced.Text := "Ocultar vista avanzada"
    } else {
        AdvancedGui.Hide()
        BtnAdvanced.Text := "Ver vista avanzada"
    }
}

CerrarVistaAvanzada(*) {
    global AdvancedGui, AdvancedVisible, BtnAdvanced
    AdvancedVisible := false
    BtnAdvanced.Text := "Ver vista avanzada"
    AdvancedGui.Hide()
}
; Se ejecuta al cerrar la ventana de vista avanzada con la X - la oculta en
; vez de destruirla, para poder reabrirla sin recrear los controles.

ToggleRelay(*) {
    global LiveRelay, BtnRelay
    LiveRelay := !LiveRelay
    BtnRelay.Text := LiveRelay ? "Relay: ON" : "Relay"
    ToolTip("Relay: " . (LiveRelay ? "ON" : "OFF"))
    SetTimer(() => ToolTip(), -800)
}

ToggleRecording(*) {
    global Recording, RecordedEvents, LastEventTime, BtnRecord
    Recording := !Recording
    if (Recording) {
        RecordedEvents := []
        LastEventTime := A_TickCount
        BtnRecord.Text := "Grabando..."
        ToolTip("Grabando: SI")
    } else {
        BtnRecord.Text := "Grabar"
        ToolTip("Grabacion detenida: " . RecordedEvents.Length . " eventos guardados")
    }
    SetTimer(() => ToolTip(), -1200)
}

DetenerLoop(*) {
    global Looping
    Looping := false
    ToolTip("Loop detenido")
    SetTimer(() => ToolTip(), -800)
}

ParpadeoRec(*) {
    global Recording, RecIndicator
    static visible := true
    if (Recording) {
        visible := !visible
        RecIndicator.Text := visible ? "● REC" : ""
    } else {
        visible := true
        RecIndicator.Text := ""
    }
}
; Hace parpadear el indicador "● REC" cada 500ms mientras Recording este
; activo, para que sea imposible no notar que se esta grabando.

ParpadeoLoop(*) {
    global Looping, BtnPlay
    static visible := true
    if (Looping) {
        visible := !visible
        BtnPlay.Text := visible ? "🔴 Loop corriendo" : "⚫ Loop corriendo"
    } else {
        visible := true
        BtnPlay.Text := "Play Loop"
    }
}
; Hace parpadear el punto de color dentro del boton de Play Loop mientras
; Looping este activo. Al detenerse, el boton vuelve a su texto normal.

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
    global LiveRelay, ActionMap, Recording, RecordedEvents, LastEventTime, AccionText, BotonControls

    accion := ""
    for a in ActionMap {
        if (a.name = nombreAccion)
            accion := a
    }
    if (accion = "")
        return

    AccionText.Text := "Ultima accion: " . nombreAccion . " (" . downOrUp . ")"

    if (LiveRelay || Recording) {
        ToolTip(nombreAccion . " " . downOrUp)
        SetTimer(() => ToolTip(), -400)
    }

    if BotonControls.Has(nombreAccion)
        BotonControls[nombreAccion].SetFont(downOrUp = "down" ? "cBlack Bold" : "cGray Norm")

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
        opciones := TargetWindows.Has(hwnd) ? "Check" : ""
        LV.Add(opciones, title, hwnd)
    }
}
; Vacia la tabla y la vuelve a llenar con todas las ventanas abiertas
; actualmente en Windows. Antes de eso, quita de TargetWindows cualquier
; ventana enlazada que ya se haya cerrado, y deja marcada la casilla de
; las que sigan vigentes.

ToggleLink(ctrl, row, checked) {
    if !row
        return
    title := LV.GetText(row, 1)
    hwnd := LV.GetText(row, 2)
    if (checked)
        TargetWindows[hwnd] := title
    else
        TargetWindows.Delete(hwnd)
}
; Se ejecuta al marcar/desmarcar la casilla de una fila. Si se marco, agrega
; la ventana a TargetWindows; si se desmarco, la quita.
