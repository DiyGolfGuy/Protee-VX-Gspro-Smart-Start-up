;@Ahk2Exe-SetMainIcon ProTeeAutoStart.ico
; ============================================================================
;  ProTee Auto-Start Sequencer  v2.0   (OCR / reads the screen)
;  BA Custom Products
; ----------------------------------------------------------------------------
;  Runs at sim-PC startup. Reads on-screen TEXT with the Windows built-in OCR
;  engine and clicks through the startup, recovering a failed launch-monitor
;  connection on the way. Every click is SCOPED to the correct window by title
;  (or by a menu's text fingerprint), so a stray matching word elsewhere on the
;  desktop can never be clicked.
;
;  SEQUENCE:
;    0. If a ProTee "Download Update" prompt is up -> click it, wait it out
;       (overall timer paused; if it stalls long past ~5 min, assume a UAC
;       prompt and alert someone to click Yes once).
;    1. GSPro Configuration window  -> click Play!
;    2. GSPro main menu             -> click the PRACTICE tile
;    3. GSPro practice screen       -> click the PRACTICE RANGE tile
;                                      (the lower tile, NOT the big heading,
;                                       NOT ON COURSE PRACTICE)
;    4. ProTee window: if the "Connection Troubleshooting / failed to connect"
;       popup is up -> power-cycle the VX via Shelly (off 10s, on, wait 5s) ->
;       click TRY CONNECTION -> wait until the status reads FINDING BALL or
;       READY FOR SHOT -> click the popup CLOSE -> close the Settings panel via
;       its small top-right X. (The X is the ONLY thing that closes the panel;
;       the visible "CLOSE SETTINGS" button belongs to the see-through menu
;       behind it and is never touched. The X is found by the ProTee window's
;       top-right corner, cross-checked against the "Settings" title row, and
;       only clicked once an icon glyph is confirmed at that spot.)
;    5. When the status is FINDING BALL / READY FOR SHOT and the range is up ->
;       click the profile tab (e.g. JOHN), then make the GSPro range the active
;       window with a click, park the cursor in the corner, and press A to reset
;       the aim -> exit.
;    - The "ProTee United VX" window (General/Debug, "Not Ready") is NEVER
;      touched; it is left to fall behind.
;    - ESC at any time during the sequence kills it instantly.
;    - 3 failed reconnects or an overall timeout -> alert + stop.
;
;  Because it reads rendered text and gets back real coordinates, it is
;  independent of resolution, scale, and window position.
;
;  UAC NOTE: on PCs where clicking Download Update raises the dimmed Windows
;  "allow changes?" prompt, NO automation can click it - that prompt lives on a
;  secure desktop. The clean one-time fix is to launch ProTee Labs from a Task
;  Scheduler task set to "Run with highest privileges" at logon, so its updater
;  is already elevated and never prompts. On PCs that don't prompt, this tool
;  sails through.
;
;  REQUIRES: AutoHotkey 1.1 (v1). The OCR engine is part of Windows 10/11 -
;  nothing to install (English language pack present by default). Run the .ahk
;  directly, or compile with Ahk2Exe (Compression = None to avoid Defender
;  false positives; any .ico must use BMP-format entries).
;
;  OCR core (HBitmapFromScreen / stream / WinRT plumbing) is malcev's proven
;  AHK v1 Windows.Media.Ocr code; word-position extraction added using the
;  interface offsets from the maintained Descolada OCR library.
;
;  SHELLY IS OPTIONAL: if no Shelly IP is set, a failed-connect popup is handled
;  by just clicking TRY CONNECTION (no power-cycle); if that doesn't connect, the
;  tool stops quietly. With a Shelly IP set, it power-cycles and retries.
;
;  LAUNCH MODEL:
;    - First run on a PC (nothing configured yet) -> opens the Setup window.
;    - After you Save once, launching normally (e.g. from the Windows Startup
;      folder, just the bare .exe) shows a short countdown then auto-runs the
;      sequence. Press S during the countdown to open Setup, or Esc to cancel.
;    - /setup argument -> always opens Setup.
;    - /run argument -> runs immediately with no countdown.
;    Put the bare .exe (or a /run shortcut) in the Startup folder for unattended
;    boot, exactly like the timed tool.
;
;  Settings + log:
;    Documents\BA Custom Products\ProTee Auto-Start\settings.ini
;    Documents\BA Custom Products\ProTee Auto-Start\events.log
; ============================================================================

#NoEnv
#SingleInstance Force
#Persistent
SetBatchLines, -1
CoordMode, Mouse, Screen
CoordMode, Pixel, Screen

global SettingsDir := A_MyDocuments "\BA Custom Products\ProTee Auto-Start"
global IniFile     := SettingsDir "\settings.ini"
global LogFile     := SettingsDir "\events.log"
global AssetDir    := SettingsDir "\assets"
global LogoWhite   := AssetDir "\ba_logo_white.png"   ; light logo for the dark banner
global LogoBlack   := AssetDir "\ba_logo_black.png"   ; dark logo for the setup window
global QrImg       := AssetDir "\ba_qr.png"
global hBanner     := 0

; --- settings (defaults; overwritten by INI) ---
global ShellyIP          := ""
global ShellyGen         := ""
global ProfileName       := ""        ; profile tab text to click in ProTee (e.g. John)
global ProTeeTitle       := ""        ; optional: title of the ProTee tab window, to anchor it
global AlertURL          := ""
global OffSec            := 10
global OnSec             := 5
global ReconnectWaitSec  := 45
global OverallTimeoutSec := 600
global MaxTries          := 3
global ScanGapMs         := 900
global ClickDelayMs      := 1000      ; pause after moving the cursor, before clicking
global BannerMon         := "Auto"    ; banner monitor: Auto (follow GSPro), a number (1,2,...), or Off

; --- sequence state ---
global playClicked := false, practiceClicked := false, rangeClicked := false
global johnClicked := false, tries := 0, startTick := 0, pausedMs := 0
global dbgRangeLogged := false
global bannerShown := false
global gBannerMon := ""

FileCreateDir, %SettingsDir%
LoadSettings()
InstallAssets()

firstParam =
firstParam = %1%

IniRead, Configured, %IniFile%, State, Configured, 0

if (firstParam = "/setup") {
    Gosub, ShowGUI                 ; explicitly open Setup
} else if (firstParam = "/run") {
    RunSequence()                  ; explicit unattended run, no countdown
} else if (Configured != 1) {
    Gosub, ShowGUI                 ; first time on this PC -> configure
} else {
    Gosub, ShowLaunchCountdown     ; configured -> brief bail-to-Setup window, then run
}
return


; ===========================================================================
;  ESC = instant kill (enabled only while the sequence is running)
; ===========================================================================
KillNow:
    Log("ESC pressed - sequence aborted by user.")
    ExitApp
return


; ===========================================================================
;  LAUNCH COUNTDOWN  (shown when already configured: auto-runs after a few
;  seconds, but lets you bail into Setup with S, or cancel with Esc)
; ===========================================================================
ShowLaunchCountdown:
    cdRemaining := 5
    Gui, CD:New, +AlwaysOnTop +ToolWindow, ProTee Auto-Start
    Gui, CD:Margin, 16, 14
    Gui, CD:Font, s11
    Gui, CD:Add, Text, w380 vCDText, % "Starting the ProTee startup sequence in " cdRemaining " seconds..."
    Gui, CD:Add, Text, w380, Press S for Setup, or Esc to cancel.
    Gui, CD:Add, Button, w110 gCDRun Default, Run now
    Gui, CD:Add, Button, x+8 w110 gCDSetup, Setup
    Gui, CD:Add, Button, x+8 w110 gCDCancel, Cancel
    Gui, CD:Show
    Hotkey, s, CDSetup, On
    Hotkey, Escape, CDCancel, On
    SetTimer, CDTick, 1000
return

CDTick:
    cdRemaining--
    if (cdRemaining <= 0) {
        Gosub, CDRun
        return
    }
    GuiControl, CD:, CDText, % "Starting the ProTee startup sequence in " cdRemaining " seconds..."
return

CDRun:
    SetTimer, CDTick, Off
    Hotkey, s, Off
    Hotkey, Escape, Off
    Gui, CD:Destroy
    RunSequence()
return

CDSetup:
    SetTimer, CDTick, Off
    Hotkey, s, Off
    Hotkey, Escape, Off
    Gui, CD:Destroy
    Gosub, ShowGUI
return

CDCancel:
    SetTimer, CDTick, Off
    Log("Launch cancelled by user at countdown.")
    ExitApp
return


; ===========================================================================
;  BA Custom Products: embedded assets + the bottom banner.
;  The banner shows for the whole startup sequence and is removed
;  automatically when the app exits (every end-of-sequence path calls ExitApp,
;  which destroys all GUIs). It is pinned to the bottom strip of the primary
;  monitor - clear of every button the tool reads or clicks - and is set
;  click-through so it can never interfere with the sequence.
; ===========================================================================
InstallAssets() {
    global AssetDir, LogoWhite, LogoBlack, QrImg
    FileCreateDir, %AssetDir%
    FileInstall, ba_logo_white.png, %LogoWhite%, 1
    FileInstall, ba_logo_black.png, %LogoBlack%, 1
    FileInstall, ba_qr.png, %QrImg%, 1
}

; Decide which monitor the banner belongs on, then show it once. Called every
; loop pass until the banner is up, so it can wait for GSPro to come on screen.
MaybeShowBanner() {
    global bannerShown, BannerMon, startTick
    if (bannerShown)
        return
    if (BannerMon = "off") {                              ; banner disabled
        bannerShown := true
        return
    }
    mon := ""
    if (RegExMatch(BannerMon, "^\s*\d+\s*$"))             ; forced monitor number
        mon := MonitorByIndex(BannerMon + 0)
    if (!IsObject(mon)) {                                 ; Auto: follow the GSPro window
        gw := WinRectByTitle("gspro")
        if (gw.found)
            mon := MonitorOf(gw.x + gw.w // 2, gw.y + gw.h // 2)
        else if ((A_TickCount - startTick) < 8000)
            return                                        ; give GSPro a few seconds to appear
        else {
            SysGet, p, MonitorPrimary                     ; last resort if GSPro never shows
            mon := MonitorByIndex(p)
        }
    }
    if (IsObject(mon))
        ShowBannerOn(mon)
    bannerShown := true
}

MonitorByIndex(n) {
    SysGet, cnt, MonitorCount
    if (n < 1 || n > cnt)
        return ""
    SysGet, m, Monitor, %n%
    return {left: mLeft, top: mTop, right: mRight, bottom: mBottom}
}

ShowBannerOn(mon) {
    global LogoWhite, QrImg, hBanner, gBannerMon
    gBannerMon := mon                                   ; remember the GSPro monitor for FinishUp
    dpi := A_ScreenDPI / 96
    sw := mon.right - mon.left
    bh := Round(132 * dpi)
    by := mon.bottom - bh

    logoH := Round(82 * dpi)
    logoW := Round(logoH * 1.988)
    qrS   := Round(98 * dpi)
    padX  := Round(34 * dpi)
    gap   := Round(36 * dpi)
    logoY := (bh - logoH) // 2                          ; vertically centered
    qrY   := (bh - qrS) // 2
    qrX   := sw - qrS - padX
    txtX  := padX + logoW + gap
    blockH := Round(58 * dpi)
    ty1 := (bh - blockH) // 2
    ty2 := ty1 + Round(34 * dpi)
    capY := (bh - Round(28 * dpi)) // 2

    haveLogo := FileExist(LogoWhite)
    haveQR   := FileExist(QrImg)

    ; -DPIScale: this window does its own scaling, so AHK must not scale it again
    Gui, Banner:New, +HwndhBanner +AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale
    Gui, Banner:Color, 0E2238
    Gui, Banner:Margin, 0, 0

    if (haveLogo) {
        Gui, Banner:Add, Picture, % "x" padX " y" logoY " w" logoW " h" logoH, %LogoWhite%
    } else {
        Gui, Banner:Font, s18 cFFFFFF Bold, Segoe UI
        Gui, Banner:Add, Text, % "x" padX " y" ((bh - Round(30 * dpi)) // 2) " BackgroundTrans", BA Custom Products
    }

    Gui, Banner:Font, s15 cFFFFFF Bold, Segoe UI
    Gui, Banner:Add, Text, % "x" txtX " y" ty1 " BackgroundTrans", Booking systems   |   Sim control hardware   |   Automation
    Gui, Banner:Font, s12 cC9DAEE Norm, Segoe UI
    Gui, Banner:Add, Text, % "x" txtX " y" ty2 " BackgroundTrans", www.bacustomproducts.com

    if (haveQR) {
        capW := Round(520 * dpi)
        capX := qrX - Round(22 * dpi) - capW
        Gui, Banner:Font, s11 cA6BAD2 Norm, Segoe UI
        Gui, Banner:Add, Text, % "x" capX " y" capY " w" capW " Right BackgroundTrans", Scan for our golf sim products
        Gui, Banner:Add, Picture, % "x" qrX " y" qrY " w" qrS " h" qrS, %QrImg%
    }

    Gui, Banner:Show, % "NoActivate x" mon.left " y" by " w" sw " h" bh
    WinSet, ExStyle, +0x20, ahk_id %hBanner%
}


; ===========================================================================
;  THE SEQUENCE
; ===========================================================================
RunSequence() {
    global
    startTick := A_TickCount
    pausedMs  := 0
    playClicked := false, practiceClicked := false, rangeClicked := false
    johnClicked := false, tries := 0, dbgRangeLogged := false
    bannerShown := false
    Hotkey, Esc, KillNow, On
    Log("=== Startup sequence started ===")

    Loop {
        MaybeShowBanner()
        if ((A_TickCount - startTick - pausedMs) > OverallTimeoutSec * 1000) {
            Log("Overall timeout reached.")
            Alert("ProTee startup sequence timed out - needs a look")
            ExitApp
        }

        full := ScanScreen()        ; one all-monitors read per loop

        ; --- 0) UPDATE PROMPT (earliest, highest priority) ---
        upd := FindLine(full, "download update")
        if (upd.found) {
            ClickLineObj(upd)
            Log("Clicked Download Update")
            WaitOutUpdate()
            continue
        }

        ; --- 1) GSPro nav first (anchored to the GSPro window) ---
        if (!rangeClicked) {
            if (!playClicked) {
                cfg := ScanWin("gspro configuration")
                if (cfg.found && IsGSProConfig(cfg)) {
                    pl := FindPlay(cfg)
                    if (pl.found) {
                        ClickLineObj(pl), playClicked := true
                        Log("Clicked Play!")
                        Sleep, 1800
                        continue
                    }
                }
            } else if (!practiceClicked) {
                menu := ScanWin("gspro", "configuration")
                if (menu.found && IsGSProMenu(menu)) {
                    pr := FindPracticeTile(menu)
                    if (pr.found) {
                        ClickLineObj(pr), practiceClicked := true
                        Log("Clicked PRACTICE")
                        Sleep, 1500
                        continue
                    }
                }
            } else {
                menu := ScanWin("gspro", "configuration")
                if (menu.found && IsPracticeRangeScreen(menu)) {
                    tile := FindPracticeRangeTile(menu)
                    if (tile.found) {
                        ClickLineObj(tile), rangeClicked := true
                        Log("Clicked PRACTICE RANGE tile")
                        Sleep, 1500
                        continue
                    }
                    if (!dbgRangeLogged) {
                        dbgRangeLogged := true
                        Log("On practice-range screen but tile not located. GSPro text read as:`n" SubStr(menu.text, 1, 1400))
                    }
                }
            }
        }

        ; --- 2) ProTee popup (handled after GSPro nav, per real behavior) ---
        pt := ScanProTee()
        if (IsTroubleshootPopup(pt)) {
            DoConnectionFix()
            Sleep, 500
            continue
        }

        ; --- 3) done: status good AND range up -> click profile tab -> exit ---
        if (rangeClicked && StatusGood(pt)) {
            if (ProfileName != "" && !johnClicked) {
                jl := FindTab(pt, ProfileName)
                if (jl.found) {
                    ClickLineObj(jl), johnClicked := true
                    Log("Clicked profile tab: " ProfileName)
                    Sleep, 800
                    continue
                }
            }
            if (johnClicked || ProfileName = "") {
                FinishUp()
                Log("=== Sequence complete ===")
                ExitApp
            }
        }

        Sleep, %ScanGapMs%
    }
}


WaitOutUpdate() {
    global pausedMs
    Log("Update running - waiting (overall timer paused).")
    t0 := A_TickCount
    alerted := false
    Loop {
        el := A_TickCount - t0
        if (el > 12 * 60000) {
            Log("Update wait exceeded 12 min - giving up.")
            Alert("ProTee update did not complete - needs a look")
            pausedMs += (A_TickCount - t0)
            ExitApp
        }
        Sleep, 3000
        s := ScanScreen()
        if (!FindLine(s, "download update").found) {
            if (WinRectByTitle("gspro", "configuration").found || WinRectByTitle("gspro configuration").found
                || StatusGood(s) || FindLine(s, "summary").found || IsTroubleshootPopup(s)) {
                Log("Update complete - apps are back.")
                pausedMs += (A_TickCount - t0)
                return
            }
        }
        if (!alerted && el > 90000 && !WinRectByTitle("gspro").found) {
            alerted := true
            Log("Update stalled ~90s - possible UAC prompt on the secure desktop.")
            Alert("Update may be waiting on a Windows permission box - click Yes on the sim PC")
        }
    }
}


DoConnectionFix() {
    global tries, MaxTries, OffSec, OnSec, ShellyIP

    ; --- No Shelly configured: try the connection once, no power-cycle, fail quietly ---
    if (ShellyIP = "") {
        Log("No Shelly configured - clicking TRY CONNECTION (no power-cycle).")
        ClickTryConnection()
        if (WaitForConnect()) {
            FinishConnect()
            return true
        }
        Log("Not connected and no Shelly to power-cycle - stopping quietly.")
        ExitApp        ; silent: no alert
    }

    ; --- Shelly configured: power-cycle first, then TRY CONNECTION, up to MaxTries ---
    tries++
    Log("--- Connection fix attempt " tries " of " MaxTries " ---")
    if (!ShellySet("off")) {
        Log("Shelly OFF failed - cannot reach plug.")
        Alert("Shelly plug unreachable - check IP / power")
        ExitApp
    }
    Sleep, % OffSec * 1000
    ShellySet("on")
    Sleep, % OnSec * 1000

    ClickTryConnection()
    if (WaitForConnect()) {
        FinishConnect()
        tries := 0
        return true
    }

    Log("Still not connected after attempt " tries ".")
    if (tries >= MaxTries) {
        Alert("VX failed to reconnect after " MaxTries " tries - needs manual help")
        ExitApp
    }
    return false
}

ClickTryConnection() {
    s := ScanProTee()
    tc := FindLine(s, "try connection")
    if (!tc.found)
        tc := FindLine(s, "try conn")
    if (tc.found) {
        ClickLineObj(tc)
        Log("Clicked TRY CONNECTION")
    } else {
        Log("TRY CONNECTION not found; will keep watching.")
    }
}

WaitForConnect() {
    global ReconnectWaitSec
    waited := 0
    Loop {
        Sleep, 1500
        waited += 1500
        if (StatusGood(ScanProTee()))
            return true
        if (waited >= ReconnectWaitSec * 1000)
            return false
    }
}

; Status is good: close the troubleshooting popup, then close the Settings panel.
FinishConnect() {
    Log("Status reached FINDING BALL / READY FOR SHOT.")
    s := ScanProTee()
    cl := FindCloseButton(s)
    if (cl.found) {
        ClickLineObj(cl)
        Log("Clicked popup CLOSE")
        Sleep, 700
    }
    CloseSettingsPage(ScanProTee())
}


; Close the ProTee Settings panel. The ONLY control that closes it is the small
; X at the panel's top-right. (The visible "CLOSE SETTINGS" button belongs to the
; see-through menu BEHIND the panel, so it is never touched.) Layered checks:
;   1) confirm the Settings panel is actually open (text fingerprint)
;   2) locate the X by the ProTee window's top-right corner (~1% in),
;      cross-checked against the "Settings" title row for the vertical position
;   3) verify an icon glyph is actually drawn at that spot before clicking
CloseSettingsPage(scan) {
    global ProTeeTitle

    if (!IsSettingsPanel(scan)) {
        Log("Settings panel not detected; nothing to close.")
        return false
    }

    wr := (ProTeeTitle != "") ? FindProTeeWindow() : {found: false}
    st := FindLineExact(scan, "settings")
    xPos := ComputeXPos(wr, st)
    if (!xPos.ok) {
        Log("Could not determine the Settings X position; leaving panel open.")
        return false
    }
    if (!SeesGlyph(xPos.x, xPos.y)) {
        Log("No X glyph detected at " xPos.x "," xPos.y " - not clicking (panel may have closed).")
        return false
    }
    ClickAt(xPos.x, xPos.y)
    Log("Clicked Settings X at " xPos.x "," xPos.y " (" xPos.src ").")
    return true
}

; Work out where the close X is. Primary anchor = ProTee window top-right corner,
; ~1% in from the right edge. Vertical = the "Settings" title row if we can read
; it (most precise), else a small fraction down from the window top.
ComputeXPos(wr, st) {
    res := {ok: false, x: 0, y: 0, src: ""}
    if (wr.found) {
        res.x := wr.x + wr.w - Round(0.01 * wr.w)
        if (st.found && st.y >= wr.y - 10 && st.y <= wr.y + 0.15 * wr.h) {
            res.y := st.y + st.h // 2
            res.src := "window top-right + Settings row"
        } else {
            res.y := wr.y + Round(0.028 * wr.h)
            res.src := "window top-right"
        }
        res.ok := true
        return res
    }
    if (st.found) {
        mon := MonitorOf(st.x + st.w // 2, st.y + st.h // 2)
        res.x := mon.right - Round(0.01 * mon.w)
        res.y := st.y + st.h // 2
        res.src := "Settings row + monitor edge"
        res.ok := true
        return res
    }
    return res
}

; Is there an icon glyph (light strokes on the dark title bar) at this point?
; Compares a small box around the point against the bar background sampled just
; to its left, so it is independent of the theme's exact colors.
SeesGlyph(cx, cy) {
    bg := (Lum(PixelColor(cx - 60, cy)) + Lum(PixelColor(cx - 45, cy + 6))) // 2
    bright := 0
    yy := cy - 9
    while (yy <= cy + 9) {
        xx := cx - 9
        while (xx <= cx + 9) {
            if (Lum(PixelColor(xx, yy)) > bg + 45)
                bright++
            xx += 3
        }
        yy += 3
    }
    return (bright >= 3)
}

PixelColor(x, y) {
    PixelGetColor, c, %x%, %y%, RGB
    return c
}

Lum(c) {
    R := (c >> 16) & 0xFF, G := (c >> 8) & 0xFF, B := c & 0xFF
    return (R * 299 + G * 587 + B * 114) // 1000
}

; Final step: make the GSPro range the active window, park the cursor in the
; corner out of the way, and press A to reset the aim (the focusing click throws
; the aim off, A snaps it back to default).
FinishUp() {
    global gBannerMon
    gw := WinRectByTitle("gspro", "configuration")
    if (!gw.found) {
        Log("GSPro window not found for final focus / aim-reset; skipping.")
        return
    }
    WinActivate, % "ahk_id " gw.hwnd
    ; Park on the monitor the banner confirmed as GSPro's; fall back to the window's own monitor.
    mon := IsObject(gBannerMon) ? gBannerMon : MonitorOf(gw.x + gw.w // 2, gw.y + gw.h // 2)
    cx := mon.left + (mon.right - mon.left) // 2
    cy := mon.top + (mon.bottom - mon.top) // 2
    ClickAt(cx, cy)
    Sleep, 300
    MouseMove, % mon.right - 2, % mon.bottom - 2, 0
    Sleep, 150
    Send, a
    Log("Final: focused GSPro, parked cursor in the GSPro-screen corner, pressed A to reset aim.")
}


; ===========================================================================
;  MENU FINGERPRINTS  (confirm we're on the right screen before clicking)
; ===========================================================================
IsGSProConfig(scan) {
    t := scan.lc
    return (InStr(t, "play") && (InStr(t, "quit") || InStr(t, "resolution") || InStr(t, "graphics")))
}
IsGSProMenu(scan) {
    t := scan.lc
    return (InStr(t, "practice") && (InStr(t, "local match") || InStr(t, "challenges") || InStr(t, "online match")))
}
IsPracticeRangeScreen(scan) {
    t := scan.lc
    ; Tolerant: OCR may split "PRACTICE RANGE" / "ON COURSE PRACTICE" across lines,
    ; so accept any signal unique to this screen.
    return ( InStr(t, "on course")
          || InStr(t, "endless bucket")
          || InStr(t, "head to the range")
          || (InStr(t, "practice") && InStr(t, "range")) )
}
IsTroubleshootPopup(scan) {
    t := scan.lc
    return (InStr(t, "failed to connect") || InStr(t, "connection troubleshooting"))
}
StatusGood(scan) {
    t := scan.lc
    return (InStr(t, "finding ball") || InStr(t, "ready for shot"))
}
IsSettingsPanel(scan) {
    t := scan.lc
    return (InStr(t, "settings") && (InStr(t, "calibrate system") || InStr(t, "troubleshoot") || InStr(t, "game options") || InStr(t, "exit application")))
}


; ===========================================================================
;  WINDOW-SCOPED + FULL-SCREEN OCR
; ===========================================================================
WinRectByTitle(include, exclude := "") {
    incL := LowerStr(include)
    excL := LowerStr(exclude)
    WinGet, idList, List
    Loop, %idList% {
        id := idList%A_Index%
        WinGetTitle, t, ahk_id %id%
        if (t = "")
            continue
        tl := LowerStr(t)
        if (!InStr(tl, incL))
            continue
        if (exclude != "" && InStr(tl, excL))
            continue
        WinGetPos, wx, wy, ww, wh, ahk_id %id%
        if (ww <= 0 || wh <= 0)
            continue
        return {found: true, x: wx, y: wy, w: ww, h: wh, hwnd: id, title: t}
    }
    return {found: false}
}

ScanWin(include, exclude := "") {
    r := {found: false, lines: [], text: "", lc: ""}
    wr := WinRectByTitle(include, exclude)
    if (!wr.found)
        return r
    o := OcrRegion(wr.x, wr.y, wr.w, wr.h)
    r.found := true
    r.lines := o.lines
    r.text  := o.text
    r.lc    := LowerStr(o.text)
    r.win   := wr
    return r
}

ScanScreen() {
    result := {lines: [], text: "", lc: ""}
    SysGet, monCount, MonitorCount
    Loop, %monCount% {
        SysGet, m, Monitor, %A_Index%
        w := mRight - mLeft, h := mBottom - mTop
        if (w <= 0 || h <= 0)
            continue
        o := OcrRegion(mLeft, mTop, w, h)
        for i, ln in o.lines
            result.lines.Push(ln)
        result.text .= o.text
    }
    result.lc := LowerStr(result.text)
    return result
}

ScanProTee() {
    global ProTeeTitle
    if (ProTeeTitle != "") {
        wr := FindProTeeWindow()
        if (wr.found) {
            o := OcrRegion(wr.x, wr.y, wr.w, wr.h)
            return {found: true, lines: o.lines, text: o.text, lc: LowerStr(o.text), win: wr}
        }
    }
    return ScanScreen()
}

; The tab/status window is titled exactly "ProTee" - but "ProTee United VX" also
; contains that text, and there can be more than one "ProTee" window. Exclude the
; VX window, then pick the largest remaining match (the full-screen tab/status
; window, not a small child), which is the one with SUMMARY/JOHN/RANGE.
FindProTeeWindow() {
    global ProTeeTitle
    incL := LowerStr(ProTeeTitle)
    best := {found: false}
    bestArea := -1
    WinGet, idList, List
    Loop, %idList% {
        id := idList%A_Index%
        WinGetTitle, t, ahk_id %id%
        if (t = "")
            continue
        tl := LowerStr(t)
        if (!InStr(tl, incL))
            continue
        if (InStr(tl, "united") || InStr(tl, "vx"))   ; skip the ProTee United VX window
            continue
        WinGetPos, wx, wy, ww, wh, ahk_id %id%
        if (ww <= 0 || wh <= 0)
            continue
        area := ww * wh
        if (area > bestArea) {
            bestArea := area
            best := {found: true, x: wx, y: wy, w: ww, h: wh, hwnd: id, title: t}
        }
    }
    return best
}

; OCR a screen rectangle; returned coordinates are absolute screen coords.
OcrRegion(x, y, w, h) {
    o := {lines: [], text: ""}
    if (w <= 0 || h <= 0)
        return o
    hbm := HBitmapFromScreen(x, y, w, h)
    stream := HBitmapToRandomAccessStream(hbm)
    DllCall("DeleteObject", "Ptr", hbm)
    res := ocr_words(stream)
    for i, ln in res.lines {
        ln.x += x
        ln.y += y
        o.lines.Push(ln)
    }
    o.text := res.text
    return o
}


; ===========================================================================
;  FIND / CLICK HELPERS
; ===========================================================================
FindLine(scan, needle) {
    nl := LowerStr(needle)
    for i, ln in scan.lines {
        if (InStr(LowerStr(ln.text), nl))
            return {found: true, x: ln.x, y: ln.y, w: ln.w, h: ln.h, text: ln.text}
    }
    return {found: false}
}

FindLineExact(scan, needle) {
    nl := LowerStr(needle)
    for i, ln in scan.lines {
        if (LowerStr(Trim(ln.text)) = nl)
            return {found: true, x: ln.x, y: ln.y, w: ln.w, h: ln.h, text: ln.text}
    }
    return {found: false}
}

FindPlay(scan) {
    for i, ln in scan.lines {
        lt := LowerStr(Trim(ln.text))
        if (InStr(lt, "play!") || lt = "play" || (InStr(lt, "play") && !InStr(lt, "player") && !InStr(lt, "display") && StrLen(lt) <= 6))
            return {found: true, x: ln.x, y: ln.y, w: ln.w, h: ln.h, text: ln.text}
    }
    return {found: false}
}

FindPracticeTile(scan) {
    r := FindLineExact(scan, "practice")
    if (r.found)
        return r
    for i, ln in scan.lines {
        lt := LowerStr(ln.text)
        if (InStr(lt, "practice") && !InStr(lt, "on course") && !InStr(lt, "range"))
            return {found: true, x: ln.x, y: ln.y, w: ln.w, h: ln.h, text: ln.text}
    }
    return {found: false}
}

; The PRACTICE RANGE tile (left), not the heading and not ON COURSE PRACTICE.
; The distinctive word is "range" - the other tile is "on course practice" with no
; "range". The heading and subtitle sit ABOVE the tile, so the lowest on-screen
; "range" that isn't part of "on course" is the tile (works whether OCR keeps
; "PRACTICE RANGE" as one line or splits it into PRACTICE / RANGE).
FindPracticeRangeTile(scan) {
    best := "", besty := -1
    for i, ln in scan.lines {
        lt := LowerStr(ln.text)
        if (!InStr(lt, "range"))
            continue
        if (InStr(lt, "on course"))
            continue
        if (ln.y > besty) {
            besty := ln.y
            best := ln
        }
    }
    if (best = "")
        return {found: false}
    return {found: true, x: best.x, y: best.y, w: best.w, h: best.h, text: best.text}
}

; The popup CLOSE button is exactly "CLOSE" (distinct from "CLOSE SETTINGS").
FindCloseButton(scan) {
    return FindLineExact(scan, "close")
}

FindTab(scan, name) {
    r := FindLineExact(scan, name)
    if (r.found)
        return r
    return FindLine(scan, name)
}

ClickLineObj(ln) {
    ClickAt(ln.x + ln.w // 2, ln.y + ln.h // 2)
}

; Move to the point, pause so the UI registers the cursor, THEN click. The pause
; is what stops fast misfires (cursor teleporting in and clicking before the
; control is ready). ClickDelayMs is adjustable in Setup.
ClickAt(x, y) {
    global ClickDelayMs
    MouseMove, %x%, %y%, 10
    Sleep, %ClickDelayMs%
    Click
    Sleep, 250
}

MonitorOf(x, y) {
    SysGet, cnt, MonitorCount
    Loop, %cnt% {
        SysGet, m, Monitor, %A_Index%
        if (x >= mLeft && x < mRight && y >= mTop && y < mBottom)
            return {left: mLeft, top: mTop, right: mRight, bottom: mBottom, w: mRight - mLeft, h: mBottom - mTop}
    }
    SysGet, pw, 0
    SysGet, ph, 1
    return {left: 0, top: 0, right: pw, bottom: ph, w: pw, h: ph}
}

LowerStr(s) {
    StringLower, o, s
    return o
}


; ===========================================================================
;  SHELLY  (Gen1 relay API + Gen2/Plus/Gen3 RPC, auto-detected)
; ===========================================================================
ShellySet(state) {
    global ShellyIP, ShellyGen
    if (ShellyIP = "")
        return false
    if (ShellyGen = "")
        DetectShellyGen()
    res := HttpGet(ShellyUrl(ShellyGen, state))
    if (!res.ok) {
        alt := (ShellyGen = 2) ? 1 : 2
        res := HttpGet(ShellyUrl(alt, state))
        if (res.ok)
            ShellyGen := alt
    }
    Log("Shelly " state " -> " (res.ok ? "OK (" res.status ")" : "FAILED (" res.err ")"))
    return res.ok
}

ShellyUrl(gen, state) {
    global ShellyIP
    if (gen = 2)
        return "http://" ShellyIP "/rpc/Switch.Set?id=0&on=" (state = "on" ? "true" : "false")
    return "http://" ShellyIP "/relay/0?turn=" state
}

DetectShellyGen() {
    global ShellyIP, ShellyGen
    res := HttpGet("http://" ShellyIP "/shelly")
    if (res.ok && InStr(res.text, """gen"":"))
        ShellyGen := 2
    else if (res.ok)
        ShellyGen := 1
    else
        ShellyGen := ""
    return ShellyGen
}

HttpGet(url) {
    obj := {ok: false, status: 0, text: "", err: ""}
    try {
        whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(4000, 4000, 4000, 4000)
        whr.Open("GET", url, false)
        whr.Send()
        obj.status := whr.Status
        obj.text   := whr.ResponseText
        obj.ok     := (whr.Status >= 200 && whr.Status < 300)
        if (!obj.ok)
            obj.err := "HTTP " whr.Status
    } catch e {
        obj.err := e.message
    }
    return obj
}


; ===========================================================================
;  ALERT + LOG
; ===========================================================================
Alert(msg) {
    global AlertURL
    Log("ALERT: " msg)
    TrayTip, ProTee Auto-Start, %msg%, 20, 3
    if (AlertURL != "") {
        u := AlertURL
        u .= (InStr(u, "?") ? "&" : "?") "source=ProTeeAutoStart&msg=" UriEncode(msg)
        HttpGet(u)
    }
}

Log(msg) {
    global LogFile
    FormatTime, ts, , yyyy-MM-dd HH:mm:ss
    FileAppend, % "[" ts "] " msg "`n", %LogFile%
}

UriEncode(str) {
    out := ""
    Loop, Parse, str
    {
        c := A_LoopField
        if (c ~= "[0-9A-Za-z\-_\.]")
            out .= c
        else
            out .= "%" Format("{:02X}", Asc(c))
    }
    return out
}


; ===========================================================================
;  SETUP / TEST GUI
; ===========================================================================
ShowGUI:
    Gui, Main:Destroy
    Gui, Main:New, +AlwaysOnTop, ProTee Auto-Start - Setup
    Gui, Main:Margin, 14, 12
    Gui, Main:Font, s9

    Gui, Main:Add, Text, , Shelly plug IP (the plug powering the VX):
    Gui, Main:Add, Edit, vShellyIP w240, %ShellyIP%
    Gui, Main:Add, Button, x+8 yp-1 gBtnTestShelly, Test Power-Cycle

    Gui, Main:Add, Text, xm y+12, Profile / player tab to click in ProTee (e.g. John). Blank = skip:
    Gui, Main:Add, Edit, xm y+4 vProfileName w240, %ProfileName%

    Gui, Main:Add, Text, xm y+12, ProTee window title (optional - anchors the tab/status window):
    Gui, Main:Add, Edit, xm y+4 vProTeeTitle w240, %ProTeeTitle%

    Gui, Main:Add, Text, xm y+12, Timing (seconds):
    Gui, Main:Add, Text, xm+10 y+6 w170, Plug OFF duration:
    Gui, Main:Add, Edit, x+6 yp-3 w60 vOffSec, %OffSec%
    Gui, Main:Add, Text, xm+10 y+6 w170, Wait after power ON:
    Gui, Main:Add, Edit, x+6 yp-3 w60 vOnSec, %OnSec%
    Gui, Main:Add, Text, xm+10 y+6 w170, Wait for reconnect:
    Gui, Main:Add, Edit, x+6 yp-3 w60 vReconnectWaitSec, %ReconnectWaitSec%
    Gui, Main:Add, Text, xm+10 y+6 w170, Overall timeout:
    Gui, Main:Add, Edit, x+6 yp-3 w60 vOverallTimeoutSec, %OverallTimeoutSec%
    Gui, Main:Add, Text, xm+10 y+6 w170, Pre-click pause (ms):
    Gui, Main:Add, Edit, x+6 yp-3 w60 vClickDelayMs, %ClickDelayMs%

    Gui, Main:Add, Text, xm y+14 w380, Alert webhook URL (optional - e.g. a Twilio or webhook relay):
    Gui, Main:Add, Edit, xm y+4 vAlertURL w380, %AlertURL%

    Gui, Main:Add, Text, xm y+12 w380, Banner display monitor (Auto follows GSPro; or a number like 1 or 2; or Off):
    Gui, Main:Add, Edit, xm y+4 vBannerMon w240, %BannerMon%

    Gui, Main:Add, Button, xm y+16 w160 gBtnTestRead, Test Screen Read
    Gui, Main:Add, Button, x+8 w130 gBtnStartNow, Start Sequence Now
    Gui, Main:Add, Button, x+8 w70 gBtnSave Default, Save

    Gui, Main:Add, Text, xm y+12 w380 cGray, Once saved, launching this normally (e.g. from the Startup folder) auto-runs after a short countdown; press S then for Setup. ESC aborts the sequence.

    ; --- BA Custom Products ---
    Gui, Main:Add, Text, xm y+16 w384 0x10                          ; etched separator
    if FileExist(LogoBlack) {
        Gui, Main:Add, Picture, xm y+12 w150 h75, %LogoBlack%
        if FileExist(QrImg)
            Gui, Main:Add, Picture, xm+300 yp w84 h84, %QrImg%
        Gui, Main:Font, s9 Norm cBlack
        Gui, Main:Add, Text, xm y+12 w280, Booking systems, sim control hardware, and automation for golf simulators.
        Gui, Main:Font, s9 Bold
        Gui, Main:Add, Text, xm y+10 w280, Enjoying this free tool?
        Gui, Main:Font, s9 Norm
        Gui, Main:Add, Text, xm y+4 w280, Support us by grabbing a control box or one of our other golf sim products.
        Gui, Main:Add, Text, xm y+6 w280 cGray, www.bacustomproducts.com
    } else {
        Gui, Main:Font, s13 Bold cBlack
        Gui, Main:Add, Text, xm y+14, BA Custom Products
        Gui, Main:Font, s9 Italic cGray
        Gui, Main:Add, Text, xm y+2, We Make Stuff Exist
        Gui, Main:Font, s9 Norm cBlack
        Gui, Main:Add, Text, xm y+10 w384, We build and share tools for golf simulator operators - this unattended startup tool is one of them, free to use and free to pass along.
        Gui, Main:Font, s9 Bold cBlack
        Gui, Main:Add, Text, xm y+12 w384, What we make:
        Gui, Main:Font, s9 Norm cBlack
        Gui, Main:Add, Text, xm y+5 w384, - Control boxes - physical button panels wired to drive your sim software
        Gui, Main:Add, Text, xm y+5 w384, - Booking systems - reservations and payments on your own branded site
        Gui, Main:Add, Text, xm y+5 w384, - Automation and shop tools - startup, screen control, and day-to-day helpers
        Gui, Main:Font, s9 Bold cBlack
        Gui, Main:Add, Text, xm y+12 w384, Enjoying this free tool?
        Gui, Main:Font, s9 Norm cBlack
        Gui, Main:Add, Text, xm y+4 w384, Support us by grabbing a control box or one of our other products at:
        Gui, Main:Font, s10 Bold cBlack
        Gui, Main:Add, Text, xm y+4 w384, www.bacustomproducts.com
        Gui, Main:Font, s9 Norm
    }

    Gui, Main:Show
return

BtnSave:
    Gui, Main:Submit, NoHide
    WriteAllSettings()
    Log("Settings saved.")
    MsgBox, 0x40, ProTee Auto-Start, Settings saved.
return

BtnTestShelly:
    Gui, Main:Submit, NoHide
    if (ShellyIP = "") {
        MsgBox, 48, ProTee Auto-Start, Enter the Shelly IP first.
        return
    }
    WriteAllSettings()
    ShellyGen := ""
    DetectShellyGen()
    genTxt := (ShellyGen = 2) ? "Gen2/Plus" : (ShellyGen = 1) ? "Gen1" : "unknown (will try both)"
    MsgBox, 0x40, Testing Shelly, % "Detected: " genTxt "`n`nThe plug will turn OFF for 3 seconds, then back ON. Watch the VX."
    ShellySet("off")
    Sleep, 3000
    ShellySet("on")
    MsgBox, 0x40, Test complete, Did the plug click OFF and back ON?`n`nIf unsure, check the log.
return

BtnTestRead:
    Gui, Main:Submit, NoHide
    Gui, Main:Hide
    Sleep, 400

    ; window titles (use these to fill in the ProTee window title, confirm GSPro)
    titles := ""
    WinGet, idList, List
    Loop, %idList% {
        id := idList%A_Index%
        WinGetTitle, tt, ahk_id %id%
        if (tt != "")
            titles .= "  " tt "`n"
    }

    scan := ScanScreen()
    Gui, Main:Show

    report := "OPEN WINDOW TITLES:`n" titles "`nTARGETS:`n"
    targets := ["play!", "practice", "practice range", "on course practice", "try connection", "close", "close settings", "finding ball", "ready for shot", "not connected", "failed to connect", "download update"]
    for i, tg in targets {
        r := FindLine(scan, tg)
        report .= "  " tg ": " (r.found ? "FOUND at " (r.x + r.w // 2) "," (r.y + r.h // 2) : "-") "`n"
    }
    if (ProfileName != "") {
        r := FindLine(scan, ProfileName)
        report .= "  [profile] " ProfileName ": " (r.found ? "FOUND at " (r.x + r.w // 2) "," (r.y + r.h // 2) : "-") "`n"
    }
    report .= "`nALL TEXT READ:`n" scan.text
    Log("=== Test Screen Read ===`n" report)

    show := report
    if (StrLen(show) > 1800)
        show := SubStr(show, 1, 1800) "`n...(full read saved to the log)"
    MsgBox, 0x40, Screen Read Result, %show%
return

BtnStartNow:
    Gui, Main:Submit
    WriteAllSettings()
    Gui, Main:Destroy
    RunSequence()
return

MainGuiClose:
MainGuiEscape:
    ExitApp
return


; ===========================================================================
;  INI LOAD / SAVE
; ===========================================================================
LoadSettings() {
    global
    IniRead, ShellyIP,          %IniFile%, Shelly, IP,          %A_Space%
    IniRead, ShellyGen,         %IniFile%, Shelly, Gen,         %A_Space%
    IniRead, ProfileName,       %IniFile%, Play,   ProfileName, %A_Space%
    IniRead, ProTeeTitle,       %IniFile%, Play,   ProTeeTitle, ProTee
    IniRead, AlertURL,          %IniFile%, Alerts, WebhookURL,  %A_Space%
    IniRead, OffSec,            %IniFile%, Timing, OffSec,             10
    IniRead, OnSec,             %IniFile%, Timing, OnSec,               5
    IniRead, ReconnectWaitSec,  %IniFile%, Timing, ReconnectWaitSec,   45
    IniRead, OverallTimeoutSec, %IniFile%, Timing, OverallTimeoutSec, 600
    IniRead, MaxTries,          %IniFile%, Recovery, MaxTries,          3
    IniRead, ScanGapMs,         %IniFile%, Timing, ScanGapMs,         900
    IniRead, ClickDelayMs,      %IniFile%, Timing, ClickDelayMs,     1000
    IniRead, BannerMon,         %IniFile%, Display, BannerMon,      Auto
    for i, v in ["ShellyIP", "ShellyGen", "ProfileName", "ProTeeTitle", "AlertURL"]
        if (%v% = "ERROR")
            %v% := ""
}

WriteAllSettings() {
    global
    IniWrite, %ShellyIP%,          %IniFile%, Shelly, IP
    IniWrite, %ShellyGen%,         %IniFile%, Shelly, Gen
    IniWrite, %ProfileName%,       %IniFile%, Play,   ProfileName
    IniWrite, %ProTeeTitle%,       %IniFile%, Play,   ProTeeTitle
    IniWrite, %AlertURL%,          %IniFile%, Alerts, WebhookURL
    IniWrite, %OffSec%,            %IniFile%, Timing, OffSec
    IniWrite, %OnSec%,             %IniFile%, Timing, OnSec
    IniWrite, %ReconnectWaitSec%,  %IniFile%, Timing, ReconnectWaitSec
    IniWrite, %OverallTimeoutSec%, %IniFile%, Timing, OverallTimeoutSec
    IniWrite, %MaxTries%,          %IniFile%, Recovery, MaxTries
    IniWrite, %ScanGapMs%,         %IniFile%, Timing, ScanGapMs
    IniWrite, %ClickDelayMs%,      %IniFile%, Timing, ClickDelayMs
    IniWrite, %BannerMon%,         %IniFile%, Display, BannerMon
    IniWrite, 1,                   %IniFile%, State, Configured
}


; ===========================================================================
;  WINDOWS OCR ENGINE  (malcev's proven AHK v1 core; word-rect extraction added)
; ===========================================================================
HBitmapFromScreen(X, Y, W, H) {
    HDC := DllCall("GetDC", "Ptr", 0, "UPtr")
    HBM := DllCall("CreateCompatibleBitmap", "Ptr", HDC, "Int", W, "Int", H, "UPtr")
    PDC := DllCall("CreateCompatibleDC", "Ptr", HDC, "UPtr")
    DllCall("SelectObject", "Ptr", PDC, "Ptr", HBM)
    DllCall("BitBlt", "Ptr", PDC, "Int", 0, "Int", 0, "Int", W, "Int", H
                    , "Ptr", HDC, "Int", X, "Int", Y, "UInt", 0x00CC0020)
    DllCall("DeleteDC", "Ptr", PDC)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", HDC)
    Return HBM
}

HBitmapToRandomAccessStream(hBitmap) {
    static IID_IRandomAccessStream := "{905A0FE1-BC53-11DF-8C49-001E4FC686DA}"
         , IID_IPicture            := "{7BF80980-BF32-101A-8BBB-00AA00300CAB}"
         , PICTYPE_BITMAP := 1
         , BSOS_DEFAULT   := 0
    DllCall("Ole32\CreateStreamOnHGlobal", "Ptr", 0, "UInt", true, "PtrP", pIStream, "UInt")
    VarSetCapacity(PICTDESC, sz := 8 + A_PtrSize * 2, 0)
    NumPut(sz, PICTDESC)
    NumPut(PICTYPE_BITMAP, PICTDESC, 4)
    NumPut(hBitmap, PICTDESC, 8)
    riid := CLSIDFromString(IID_IPicture, GUID1)
    DllCall("OleAut32\OleCreatePictureIndirect", "Ptr", &PICTDESC, "Ptr", riid, "UInt", false, "PtrP", pIPicture, "UInt")
    DllCall(NumGet(NumGet(pIPicture + 0) + A_PtrSize * 15), "Ptr", pIPicture, "Ptr", pIStream, "UInt", true, "UIntP", size, "UInt")
    riid := CLSIDFromString(IID_IRandomAccessStream, GUID2)
    DllCall("ShCore\CreateRandomAccessStreamOverStream", "Ptr", pIStream, "UInt", BSOS_DEFAULT, "Ptr", riid, "PtrP", pIRandomAccessStream, "UInt")
    ObjRelease(pIPicture)
    ObjRelease(pIStream)
    Return pIRandomAccessStream
}

CLSIDFromString(IID, ByRef CLSID) {
    VarSetCapacity(CLSID, 16, 0)
    if res := DllCall("ole32\CLSIDFromString", "WStr", IID, "Ptr", &CLSID, "UInt")
        throw Exception("CLSIDFromString failed. Error: " . Format("{:#x}", res))
    Return &CLSID
}

; Returns {lines: [ {text, x, y, w, h}, ... ], text: "<all lines>`n"}
; Coordinates are relative to the captured bitmap's top-left.
ocr_words(file) {
    static OcrEngineStatics, OcrEngine, MaxDimension, BitmapDecoderStatics
    if (OcrEngineStatics = "") {
        CreateClass("Windows.Graphics.Imaging.BitmapDecoder", IBitmapDecoderStatics := "{438CCB26-BCEF-4E95-BAD6-23A822E58D01}", BitmapDecoderStatics)
        CreateClass("Windows.Media.Ocr.OcrEngine", IOcrEngineStatics := "{5BFFA85A-3384-3540-9940-699120D428A8}", OcrEngineStatics)
        DllCall(NumGet(NumGet(OcrEngineStatics + 0) + 6 * A_PtrSize), "ptr", OcrEngineStatics, "uint*", MaxDimension)   ; MaxImageDimension
        DllCall(NumGet(NumGet(OcrEngineStatics + 0) + 10 * A_PtrSize), "ptr", OcrEngineStatics, "ptr*", OcrEngine)      ; TryCreateFromUserProfileLanguages
        if (OcrEngine = 0) {
            MsgBox, 48, ProTee Auto-Start, Windows OCR could not start. An English language pack may be missing.
            ExitApp
        }
    }

    out := {}
    out.lines := []
    out.text  := ""

    IRandomAccessStream := file
    DllCall(NumGet(NumGet(BitmapDecoderStatics + 0) + 14 * A_PtrSize), "ptr", BitmapDecoderStatics, "ptr", IRandomAccessStream, "ptr*", BitmapDecoder)   ; CreateAsync
    WaitForAsync(BitmapDecoder)
    BitmapFrame := ComObjQuery(BitmapDecoder, IBitmapFrame := "{72A49A1C-8081-438D-91BC-94ECFC8185C6}")
    DllCall(NumGet(NumGet(BitmapFrame + 0) + 12 * A_PtrSize), "ptr", BitmapFrame, "uint*", width)
    DllCall(NumGet(NumGet(BitmapFrame + 0) + 13 * A_PtrSize), "ptr", BitmapFrame, "uint*", height)
    if (width > MaxDimension) || (height > MaxDimension) {
        Log("OCR skipped a capture too large: " width "x" height " (max " MaxDimension ").")
        CleanupStream(IRandomAccessStream)
        ObjRelease(BitmapDecoder), ObjRelease(BitmapFrame)
        return out
    }
    BitmapFrameWithSoftwareBitmap := ComObjQuery(BitmapDecoder, IBitmapFrameWithSoftwareBitmap := "{FE287C9A-420C-4963-87AD-691436E08383}")
    DllCall(NumGet(NumGet(BitmapFrameWithSoftwareBitmap + 0) + 6 * A_PtrSize), "ptr", BitmapFrameWithSoftwareBitmap, "ptr*", SoftwareBitmap)   ; GetSoftwareBitmapAsync
    WaitForAsync(SoftwareBitmap)
    DllCall(NumGet(NumGet(OcrEngine + 0) + 6 * A_PtrSize), "ptr", OcrEngine, "ptr", SoftwareBitmap, "ptr*", OcrResult)   ; RecognizeAsync
    WaitForAsync(OcrResult)

    DllCall(NumGet(NumGet(OcrResult + 0) + 6 * A_PtrSize), "ptr", OcrResult, "ptr*", LinesList)   ; get_Lines
    DllCall(NumGet(NumGet(LinesList + 0) + 7 * A_PtrSize), "ptr", LinesList, "int*", lineCount)   ; Size
    loop % lineCount {
        DllCall(NumGet(NumGet(LinesList + 0) + 6 * A_PtrSize), "ptr", LinesList, "int", A_Index - 1, "ptr*", OcrLine)   ; GetAt
        DllCall(NumGet(NumGet(OcrLine + 0) + 7 * A_PtrSize), "ptr", OcrLine, "ptr*", hText)   ; get_Text
        buffer := DllCall("Combase.dll\WindowsGetStringRawBuffer", "ptr", hText, "uint*", length, "ptr")
        lineText := StrGet(buffer, length, "UTF-16")

        DllCall(NumGet(NumGet(OcrLine + 0) + 6 * A_PtrSize), "ptr", OcrLine, "ptr*", WordsList)   ; get_Words
        DllCall(NumGet(NumGet(WordsList + 0) + 7 * A_PtrSize), "ptr", WordsList, "int*", wordCount)   ; Size
        lx1 := 9999999, ly1 := 9999999, lx2 := -9999999, ly2 := -9999999
        loop % wordCount {
            DllCall(NumGet(NumGet(WordsList + 0) + 6 * A_PtrSize), "ptr", WordsList, "int", A_Index - 1, "ptr*", OcrWord)   ; GetAt
            VarSetCapacity(RECT, 16, 0)
            DllCall(NumGet(NumGet(OcrWord + 0) + 6 * A_PtrSize), "ptr", OcrWord, "ptr", &RECT)   ; get_BoundingRect (X,Y,W,H floats)
            wx := NumGet(RECT, 0, "Float"), wy := NumGet(RECT, 4, "Float"), ww := NumGet(RECT, 8, "Float"), wh := NumGet(RECT, 12, "Float")
            if (wx < lx1)
                lx1 := wx
            if (wy < ly1)
                ly1 := wy
            if (wx + ww > lx2)
                lx2 := wx + ww
            if (wy + wh > ly2)
                ly2 := wy + wh
            ObjRelease(OcrWord)
        }
        ObjRelease(WordsList)

        line := {}
        line.text := lineText
        if (wordCount > 0) {
            line.x := Round(lx1), line.y := Round(ly1), line.w := Round(lx2 - lx1), line.h := Round(ly2 - ly1)
        } else {
            line.x := 0, line.y := 0, line.w := 0, line.h := 0
        }
        out.lines.Push(line)
        out.text .= lineText "`n"
        ObjRelease(OcrLine)
    }

    CleanupStream(IRandomAccessStream)
    CleanupBitmap(SoftwareBitmap)
    ObjRelease(BitmapDecoder)
    ObjRelease(BitmapFrame)
    ObjRelease(BitmapFrameWithSoftwareBitmap)
    ObjRelease(OcrResult)
    ObjRelease(LinesList)
    return out
}

CleanupStream(IRandomAccessStream) {
    Close := ComObjQuery(IRandomAccessStream, IClosable := "{30D5A829-7FA4-4026-83BB-D75BAE4EA99E}")
    DllCall(NumGet(NumGet(Close + 0) + 6 * A_PtrSize), "ptr", Close)
    ObjRelease(Close)
    ObjRelease(IRandomAccessStream)
}

CleanupBitmap(SoftwareBitmap) {
    Close := ComObjQuery(SoftwareBitmap, IClosable := "{30D5A829-7FA4-4026-83BB-D75BAE4EA99E}")
    DllCall(NumGet(NumGet(Close + 0) + 6 * A_PtrSize), "ptr", Close)
    ObjRelease(Close)
    ObjRelease(SoftwareBitmap)
}

CreateClass(string, interface, ByRef Class) {
    CreateHString(string, hString)
    VarSetCapacity(GUID, 16)
    DllCall("ole32\CLSIDFromString", "wstr", interface, "ptr", &GUID)
    result := DllCall("Combase.dll\RoGetActivationFactory", "ptr", hString, "ptr", &GUID, "ptr*", Class)
    if (result != 0) {
        if (result = 0x80004002)
            MsgBox No such interface supported
        else if (result = 0x80040154)
            MsgBox Class not registered
        else
            MsgBox % "OCR init error: " result
        ExitApp
    }
    DeleteHString(hString)
}

CreateHString(string, ByRef hString) {
    DllCall("Combase.dll\WindowsCreateString", "wstr", string, "uint", StrLen(string), "ptr*", hString)
}

DeleteHString(hString) {
    DllCall("Combase.dll\WindowsDeleteString", "ptr", hString)
}

WaitForAsync(ByRef Object) {
    AsyncInfo := ComObjQuery(Object, IAsyncInfo := "{00000036-0000-0000-C000-000000000046}")
    loop {
        DllCall(NumGet(NumGet(AsyncInfo + 0) + 7 * A_PtrSize), "ptr", AsyncInfo, "uint*", status)   ; Status
        if (status != 0) {
            if (status != 1) {
                DllCall(NumGet(NumGet(AsyncInfo + 0) + 8 * A_PtrSize), "ptr", AsyncInfo, "uint*", ErrorCode)
                Log("OCR async error: " ErrorCode)
                ObjRelease(AsyncInfo)
                Object := 0
                return
            }
            ObjRelease(AsyncInfo)
            break
        }
        sleep 10
    }
    DllCall(NumGet(NumGet(Object + 0) + 8 * A_PtrSize), "ptr", Object, "ptr*", ObjectResult)   ; GetResults
    ObjRelease(Object)
    Object := ObjectResult
}
