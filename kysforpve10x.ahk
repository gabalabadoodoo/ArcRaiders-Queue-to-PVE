#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

; ============================================================
;  ARC RAIDERS - Auto Queue & Surrender
;  F1 = Start    F2 = Stop
; ============================================================

; ---------- colour tolerance helper ----------
ColorMatch(x, y, targetHex, tolerance := 10) {
    pixel := PixelGetColor(x, y, "RGB")
    tR := (targetHex >> 16) & 0xFF
    tG := (targetHex >>  8) & 0xFF
    tB :=  targetHex        & 0xFF
    pR := (pixel    >> 16) & 0xFF
    pG := (pixel    >>  8) & 0xFF
    pB :=  pixel            & 0xFF
    return (Abs(pR - tR) <= tolerance
         && Abs(pG - tG) <= tolerance
         && Abs(pB - tB) <= tolerance)
}

; ---------- colours ----------
GOLD   := 0xFEBC13   ; play / ready / confirm
WHITE  := 0xFEFEFE   ; check in queue is done / surrender button visible
CREAM  := 0xF9EEDF   ; post-game continue button

; ---------- globals ----------
global Running      := false
global GamesQueued  := 0
global GuiObj       := ""
global StatusTxt    := ""
global GamesTxt     := ""

; ============================================================
;  GUI
; ============================================================
BuildGui() {
    global GuiObj, StatusTxt, GamesTxt
    GuiObj := Gui("+AlwaysOnTop", "kysforpve10x")
    GuiObj.BackColor := "1a1a2e"
    GuiObj.SetFont("s10 cWhite", "Segoe UI")

    GuiObj.Add("Text", "x10 y10 w460", "Queue and Surrender - where you do other stuffs while this kys ingame.")
    GuiObj.SetFont("s9 cSilver", "Segoe UI")
    GuiObj.Add("Text", "x10 y28 w460", "F1 = Start        F2 = Stop")

    GuiObj.Add("Text", "x10 y50 w60 cSilver", "State:")
    StatusTxt := GuiObj.Add("Text", "x70 y50 w390 cLime", "Idle – press F1 to start")

    GuiObj.Add("Text", "x10 y72 w120 cSilver", "Games queued:")
    GamesTxt  := GuiObj.Add("Text", "x135 y72 w80 cAqua", "0")

    GuiObj.Add("Text", "x10 y94 w460 h1 Background808080")   

    GuiObj.SetFont("s8 c808080", "Segoe UI")
    GuiObj.Add("Text", "x10 y100 w460", "Running on: " A_ComputerName "   |   v1.2")

    GuiObj.Show("w440 h120") ; overall GUI size
    GuiObj.OnEvent("Close", (*) => ExitApp())
}

SetStatus(msg, colour := "Lime") {
    global StatusTxt
    StatusTxt.SetFont("c" colour)
    StatusTxt.Value := msg
}

SetGames(n) {
    global GamesTxt
    GamesTxt.Value := n
}

; ============================================================
;  HOTKEYS
; ============================================================
F1:: StartScript()
F2:: StopScript()

StartScript() {
    global Running
    if Running
        return
    Running := true
    SetStatus("Starting…", "Yellow")
    SetTimer(MainLoop, -1)
}

StopScript() {
    global Running
    Running := false
    SetStatus("Stopped – press F1 to restart", "Red")
}

; ============================================================
;  ERROR helper  (stops the loop and reports where it failed)
; ============================================================
ScriptError(stage, x, y, expectedHex) {
    global Running, StatusTxt
    Running := false
    
    ; Grab the last status message that was displayed
    lastStatus := StatusTxt.Value 
    
    msg := "ERROR at stage: [" stage "]`n"
        . "Last Status: " lastStatus "`n`n"
        . "Expected colour 0x" Format("{:06X}", expectedHex)
        . " at (" x ", " y ")`n"
        . "Actual colour: 0x" Format("{:06X}", PixelGetColor(x, y, "RGB")) "`n`n"
        . "Script stopped. Fix the issue then press F1."
        
    SetStatus("ERROR – see popup", "Red")
    MsgBox msg, "Arc Raiders – Error", 0x10
}

; ============================================================
;  PERSISTENT COLOUR POLL
;  Keeps checking every [interval]ms until colour matches or
;  [timeout]ms elapses (0 = no timeout).
;  Returns true on match, false on timeout / stop.
; ============================================================
WaitForColor(x, y, hex, statusMsg, interval := 2000, timeout := 0) {
    global Running
    start := A_TickCount
    loop {
        if !Running
            return false
        if ColorMatch(x, y, hex)
            return true
        if timeout && (A_TickCount - start >= timeout)
            return false
        SetStatus(statusMsg " [" Round((A_TickCount - start) / 1000, 1) "s]", "Yellow")
        Sleep interval
    }
}

; ============================================================
;  WAIT FOR COLOUR TO DISAPPEAR
;  Keeps checking until the target colour is NO LONGER present.
; ============================================================
WaitForColorGone(x, y, hex, statusMsg, interval := 2000, timeout := 0) {
    global Running
    start := A_TickCount
    loop {
        if !Running
            return false
        
        ; Notice the "!" here: if the color does NOT match, we are done waiting
        if !ColorMatch(x, y, hex) 
            return true
            
        if timeout && (A_TickCount - start >= timeout)
            return false
            
        SetStatus(statusMsg " [" Round((A_TickCount - start) / 1000, 1) "s]", "Yellow")
        Sleep interval
    }
}

; ============================================================
;  MAIN LOOP
; ============================================================
MainLoop() {
    global Running, GamesQueued

    while Running {

        ; ── LOBBY SCREEN ────────────────────────────────────
        SetStatus("Lobby: checking Play button…", "Aqua")
        if !ColorMatch(1825, 930, GOLD) {
            if !Running
                return
            ScriptError("Lobby – Play button colour check", 1825, 930, GOLD)
            return
        }

        SetStatus("Lobby: clicking Play…", "Lime")
        Click 1825, 930
        Sleep 500

        ; Select destination  (second click)
        SetStatus("Lobby: selecting destination…", "Lime")
        Click 1670, 870
        Sleep 500

        ; Free loadout
        SetStatus("Lobby: selecting Free Loadout…", "Lime")
        Click 700, 35
        Sleep 500

        ; Ready up – verify gold colour again
        SetStatus("Lobby: checking Ready button…", "Aqua")
        if !ColorMatch(1825, 930, GOLD) {
            if !Running
                return
            ScriptError("Ready Up – colour check", 1825, 930, GOLD)
            return
        }
        SetStatus("Lobby: clicking Ready…", "Lime")
        Click 1825, 930
        Sleep 800

        ; ── QUEUE / DEPLOY WAIT ─────────────────────────────
        if !WaitForColorGone(260, 1035, CREAM, "Waiting for queue to pop…") {
            return
        }

        ; ── SURRENDER ───────────────────────────────────────
        SetStatus("Waiting for surrender opportunity…", "Yellow")
        if !WaitForColor(1750, 945, WHITE, "Waiting for surrender opportunity…") {
            return
        }

        SetStatus("Surrender: pressing ESC…", "Lime")
        Send "{Esc}"
        Sleep 500

        SetStatus("Surrender: clicking Surrender option…", "Lime")
        Click 320, 765
        Sleep 500

        ; Confirm surrender – gold button
        SetStatus("Surrender: checking confirm button…", "Aqua")
        if !ColorMatch(1185, 635, GOLD) {
            if !Running
                return
            ScriptError("Confirm Surrender – colour check", 1185, 635, GOLD)
            return
        }
        SetStatus("Surrender: confirming…", "Lime")
        Click 1185, 635

        ; ── POST-GAME SUMMARY ────────────────────────────────
        SetStatus("Post-game: waiting for summary screen…", "Yellow")
        Sleep 5000 
        if !WaitForColor(1850, 1040, CREAM, "Post-game: waiting for Continue button", 2000, 0) {
            return
        }

        SetStatus("Post-game: clicking Continue (×4)…", "Lime")
        Click 1850, 1040
        Sleep 1000
        Click 1850, 1040
        Sleep 1000
        Click 1850, 1040
        Sleep 1000
        Click 1850, 1040
        Sleep 1000
        

        ; ── POST-GAME SURVEY (OPTIONAL) ──────────────────────
        SetStatus("Post-game: Checking game survey…", "Yellow")
        if WaitForColor(1000, 640, 0xad8e45, "Post-game: checking for survey", 100, 1500) {
            SetStatus("Post-game: answering survey…", "Lime")
            Click 1224, 528
            Sleep 1000
            Click 1000, 655
            Sleep 1000
        }

        ; ── BACK AT LOBBY ────────────────────────────────────
        SetStatus("Lobby: confirming return (up to 20 s)…", "Yellow")
        if !WaitForColor(1825, 930, GOLD, "Lobby: waiting for Play button", 2000, 20000) {
            if !Running
                return
            ScriptError("Return to Lobby – Play button not found within 20 s", 1825, 930, GOLD)
            return
        }

        GamesQueued++
        SetGames(GamesQueued)
        SetStatus("Lobby ready! Games queued: " GamesQueued " – looping…", "Lime")
        Sleep 2000   ; brief pause before next cycle
    }
}

; ============================================================
;  ENTRY POINT
; ============================================================
BuildGui()