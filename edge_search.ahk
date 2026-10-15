; Edge Auto-Search Script for AutoHotkey v2.0
; Automatically performs searches in Microsoft Edge when it's the active window
; Press Ctrl+Alt+Q to exit the script
;
; The decisions are in lib\jape.ahk, where tests\run.ahk can reach them. This
; file is the plumbing: it starts Edge, owns the timer, and supplies EdgeIO,
; the real keyboard, mouse and windows that RunSearch works through.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\jape.ahk
Persistent

Logs := LogFiles(A_ScriptDir . "\logs")

WriteLog("Log file created at: " . Logs.path)
WriteLog("Script started from: " . A_ScriptDir)
WriteLog("Press Ctrl+Alt+Q to stop the script")

searchItems := ["Microsoft", "Apple", "Google", "Amazon", "Meta",
    "IBM", "Intel", "Tesla", "Nvidia", "Samsung",
    "Paris", "Tokyo", "New York", "London", "Rome",
    "Bali", "Sydney", "Dubai", "Santorini", "Kyoto",
    "Sushi", "Pizza", "Pasta", "Tacos", "Biryani",
    "Pad Thai", "Steak", "Ramen", "Dumplings", "Paella"]

; Configuration
searchInterval := 30  ; seconds between searches
Scheduler := SearchScheduler(searchInterval)

WriteLog("Script started. Initializing...")

if (!IsEdgeRunning()) {
    WriteLog("Microsoft Edge is not running. Opening Edge...")
    Run "msedge.exe"
    Sleep 3000  ; Wait for Edge to open
    WriteLog("Edge opened successfully")
} else {
    WriteLog("Microsoft Edge is already running")
}

WriteLog("Activating Microsoft Edge window...")
try {
    WinActivate "ahk_exe msedge.exe"
    WinWaitActive "ahk_exe msedge.exe", , 5
    Sleep 1000  ; Extra moment for Edge to be ready

    if (IsEdgeActive()) {
        WriteLog("Performing initial search to confirm script startup...")
        Search("first")
        WriteLog("Initial search complete! Script is now running.")
        WriteLog("Searches will continue every " . searchInterval . " seconds when Edge is active.")
    } else {
        WriteLog("Could not activate Edge window. Will wait for Edge to be active manually.")
        WriteLog("Please click on Edge window to start the first search.")
    }
} catch as err {
    WriteLog("Error activating Edge (" . err.Message . "). Will wait for Edge to be active manually.")
}

SetTimer MainLoop, 1000

MainLoop() {
    action := Scheduler.Tick(A_TickCount, IsEdgeRunning(), IsEdgeActive())
    if (Scheduler.logLine != "")
        WriteLog(Scheduler.logLine)
    if (action = "first") {
        WriteLog("Edge is now active! Performing initial search...")
        Search("first")
        WriteLog("Initial search complete! Continuing with timed searches.")
    } else if (action = "search") {
        Search("search")
    }
}

; kind is "first" or "search"; see SearchScheduler.Searched.
Search(kind) {
    global searchItems, searchInterval, Scheduler
    started := A_TickCount
    WriteLog("Edge is active, performing search...")
    searchTerm := searchItems[Random(1, searchItems.Length)]
    WriteLog("Searching for: " . searchTerm)
    RunSearch(searchTerm, EdgeIO, searchInterval)
    Scheduler.Searched(kind, started, A_TickCount)
}

; What RunSearch acts through: the real input and the real windows.
class EdgeIO {
    static EdgeActive() => IsEdgeActive()
    static EdgeUnderMouse() => IsEdgeUnderMouse()
    static Send(keys) => Send(keys)
    static Sleep(ms) => Sleep(ms)
    static Random(low, high) => Random(low, high)
    static Scroll(clicks) => Click("WheelDown " clicks)
    static Log(text) => WriteLog(text)
}

IsEdgeRunning() {
    return ProcessExist("msedge.exe")
}

IsEdgeActive() {
    try {
        activeProcess := WinGetProcessName("A")
        if (InStr(activeProcess, "msedge.exe")) {
            return true
        }
    }
    return false
}

; The mouse wheel scrolls the window under the pointer, which need not be the
; active one.
IsEdgeUnderMouse() {
    try {
        MouseGetPos(, , &window)
        return InStr(WinGetProcessName("ahk_id " window), "msedge.exe") > 0
    }
    return false
}

WriteLog(message) {
    Logs.Write(message)
}

^!q:: {
    WriteLog("Script stopped by user (Ctrl+Alt+Q)")
    WriteLog("Script terminated.")
    ExitApp
}

OnExit ExitFunc

ExitFunc(ExitReason, ExitCode) {
    WriteLog("Script terminated. Reason: " . ExitReason)
}
