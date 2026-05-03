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

; Setup file paths for saving settings
global SettingsDir  := A_ScriptDir "\pve10x_user_settings"
global IniFile      := SettingsDir "\kys_settings.ini"

; ============================================================
;  GUI
; ============================================================
BuildGui() {
    global GuiObj, StatusTxt, GamesTxt, IniFile
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
    GuiObj.Add("Text", "x10 y100 w460", "Running on: " A_ComputerName "   |   v1.4")

    ; Read previous position from INI file, default to Center
    savedX := IniRead(IniFile, "Window", "X", "Center")
    savedY := IniRead(IniFile, "Window", "Y", "Center")
    
    showOpts := "w440 h120"
    if (savedX != "Center")
        showOpts .= " x" savedX " y" savedY

    GuiObj.Show(showOpts) 
    GuiObj.OnEvent("Close", (*) => SaveAndExit())
}

SaveAndExit() {
    global GuiObj, SettingsDir, IniFile
    
    ; Create the directory if it doesn't exist yet
    if !DirExist(SettingsDir) {
        DirCreate(SettingsDir)
    }

    ; Get window coords right before closing and save them
    GuiObj.GetPos(&gX, &gY)
    IniWrite(gX, IniFile, "Window", "X")
    IniWrite(gY, IniFile, "Window", "Y")
    ExitApp()
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
        
    ; Check and resolve overlap automatically before starting
    ResolveGuiOverlap()

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
;  OVERLAP RESOLVER (Shortest Path Auto-Move with Padding)
;  Calculates optimal non-overlapping coordinates and snaps the GUI there.
; ============================================================
ResolveGuiOverlap() {
    global GuiObj
    GuiObj.GetPos(&gX, &gY, &gW, &gH)
    
    padding := 50 ; <--- The 50 pixel gap requirement
    
    ; Master list of every coordinate the script cares about
    checkPoints := [
        [1825, 930], [1670, 870], [700, 35],    ; Lobby
        [260, 1035],                            ; Queue Wait
        [1750, 945], [320, 765], [1185, 635],   ; Surrender
        [1850, 1040],                           ; Post-Game Summary
        [1000, 640], [1224, 528], [1000, 655]   ; Survey
    ]
    
    ; Step 1: Detect if an overlap currently exists (including padding)
    overlapFound := false
    for _, pt in checkPoints {
        if (pt[1] >= gX - padding && pt[1] <= gX + gW + padding && pt[2] >= gY - padding && pt[2] <= gY + gH + padding) {
            overlapFound := true
            break
        }
    }
    
    ; If perfectly safe (even with padding), no need to do math
    if (!overlapFound)
        return 

    ; Step 2: Generate candidate coordinates that clear the bounds of the points + padding
    xCands := [gX]
    yCands := [gY]
    for _, pt in checkPoints {
        px := pt[1], py := pt[2]
        xCands.Push(px + padding + 1)           ; Right side of the point, pushed out 50px
        xCands.Push(px - gW - padding - 1)      ; Left side of the point, pushed out 50px
        yCands.Push(py + padding + 1)           ; Bottom side of the point, pushed out 50px
        yCands.Push(py - gH - padding - 1)      ; Top side of the point, pushed out 50px
    }

    bestX := gX, bestY := gY
    minDist := 999999999 ; Start with an impossibly large distance

    ; Step 3: Test every candidate combination to find the shortest safe move
    for _, cx in xCands {
        for _, cy in yCands {
            
            isSafe := true
            for _, pt in checkPoints {
                ; Check if the candidate overlaps any point's padded "danger zone"
                if (pt[1] >= cx - padding && pt[1] <= cx + gW + padding && pt[2] >= cy - padding && pt[2] <= cy + gH + padding) {
                    isSafe := false
                    break
                }
            }

            if (isSafe) {
                ; Calculate the squared distance (Pythagorean theorem without the root for speed)
                dist := (cx - gX)**2 + (cy - gY)**2
                if (dist < minDist) {
                    minDist := dist
                    bestX := cx
                    bestY := cy
                }
            }
        }
    }

    ; Step 4: Move window and warn the user
    GuiObj.Move(bestX, bestY)
    SetStatus("WARNING: Auto-moved GUI!", "Yellow")
    Sleep 1500 ; Brief pause so the user can see the warning
}

; ============================================================
;  ERROR helper
; ============================================================
ScriptError(stage, x, y, expectedHex) {
    global Running, StatusTxt
    Running := false
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
; ============================================================
WaitForColorGone(x, y, hex, statusMsg, interval := 2000, timeout := 0) {
    global Running
    start := A_TickCount
    loop {
        if !Running
            return false
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

        SetStatus("Lobby: selecting destination…", "Lime")
        Click 1670, 870
        Sleep 500

        SetStatus("Lobby: selecting Free Loadout…", "Lime")
        Click 700, 35
        Sleep 500

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