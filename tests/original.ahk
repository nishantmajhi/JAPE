#Requires AutoHotkey v2.0

; original.ahk — the pre-cleanup decision code, transcribed with its I/O lifted
; out, so the suite can show that each regression test fails against it.
;
; The original cannot be run from a test: edge_search.ahk at commit ff21003
; starts Edge, sends Ctrl+T and types into whatever window is in front, every
; 30 seconds. So the two functions whose decisions changed are copied here
; with Send, Sleep, Random, Click and WriteLog turned into calls on `io`, and
; A_TickCount turned into the `nowMs` argument. TestTranscriptionFidelity()
; in run.ahk asserts that the lines copied are still in that commit, so a
; transcription that has drifted fails loudly instead of proving nothing.
;
; Nothing in this file is used by the program. It exists only to be wrong.

ORIGINAL_COMMIT := "ff21003"


; PerformSearch(), lines 118-157, verbatim apart from the I/O. The caller has
; already checked IsEdgeActive(); nothing in here checks it again.
Original_PerformSearch(io, searchItems, searchInterval) {
    io.Log("Edge is active, performing search...")

    ; Open new tab
    io.Send("^t")
    io.Sleep(500)

    ; Pick random search term
    index := io.Random(1, searchItems.Length)
    searchTerm := searchItems[index]
    io.Log("Searching for: " . searchTerm)

    ; Type search term slowly with random delays (simulating human typing)
    io.Log("Typing: " . searchTerm)
    Loop Parse searchTerm {
        io.Send(A_LoopField)
        ; Random delay between 50-200ms per character (human-like typing)
        io.Sleep(io.Random(50, 200))
    }
    ; Random pause after typing before pressing Enter
    io.Sleep(io.Random(300, 800))
    io.Send("{Enter}")

    io.Log("Search completed. Next search in " . searchInterval . " seconds")

    ; Wait before scrolling
    io.Sleep(3000)

    ; Random scrolling
    numScrolls := io.Random(3, 6)
    Loop numScrolls {
        scrollAmount := io.Random(3, 10)  ; Number of scroll clicks
        io.Scroll(scrollAmount)
        io.Log("Scrolled " . scrollAmount . " clicks")
        waitTime := io.Random(500, 1500)
        io.Sleep(waitTime)
    }
}


; MainLoop(), lines 73-116: one tick. The globals and the function's static
; are fields of `st`, the caller's PerformSearch() calls become a returned
; "first" or "search", and WriteLog becomes a pushed line. For "first" the
; caller sets st.lastSearchTime after the search, as lines 86-87 did.
Original_MainLoopTick(st, nowMs, edgeRunning, edgeActive) {
    lines := []

    ; Check if Edge is running
    if (!edgeRunning) {
        lines.Push("Microsoft Edge is not running. Waiting...")
        return { action: "", lines: lines }
    }

    ; If first search hasn't been done yet, check if Edge is active and do it
    if (!st.firstSearchDone && edgeActive) {
        lines.Push("Edge is now active! Performing initial search...")
        return { action: "first", lines: lines }
    }

    ; Only perform searches after initial search is done
    if (!st.firstSearchDone) {
        return { action: "", lines: lines }
    }

    ; Check if Edge is the active window
    if (edgeActive) {
        ; Check if enough time has passed since last search
        currentTime := nowMs / 1000
        timeSinceLastSearch := currentTime - st.lastSearchTime

        if (timeSinceLastSearch > st.searchInterval) {
            st.lastSearchTime := currentTime
            return { action: "search", lines: lines }
        }
    } else {
        ; Log occasionally when Edge is not active (every 30 seconds)
        currentTime := nowMs / 1000
        if (currentTime - st.lastInactiveLog > 30) {
            lines.Push("Edge is running but not active. Waiting for Edge to be focused...")
            st.lastInactiveLog := currentTime
        }
    }
    return { action: "", lines: lines }
}


; WriteLog(), lines 173-178, with the log path passed in.
Original_WriteLog(message, LogFile) {
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    logEntry := timestamp . " - INFO - " . message . "`n"
    FileAppend logEntry, LogFile
}


; Lines that must still be in the original for the transcription above to be
; a transcription. Each is a whole line, trimmed.
OriginalSnippets() {
    return [
        'Send "^t"',
        "Send A_LoopField",
        "Sleep Random(50, 200)",
        "Sleep Random(300, 800)",
        'Send "{Enter}"',
        "numScrolls := Random(3, 6)",
        "scrollAmount := Random(3, 10)  `; Number of scroll clicks",
        'Click "WheelDown " . scrollAmount',
        "waitTime := Random(500, 1500)",
        'WriteLog("Microsoft Edge is not running. Waiting...")',
        "lastSearchTime := A_TickCount / 1000",
        "currentTime := A_TickCount / 1000",
        "timeSinceLastSearch := currentTime - lastSearchTime",
        "if (timeSinceLastSearch > searchInterval) {",
        "if (currentTime - lastInactiveLog > 30) {",
        "FileAppend logEntry, LogFile",
        'LogFile := LogDir . "\edge_script_log_" . TimeStamp . ".txt"',
    ]
}

; The text of PerformSearch() in the original, from its signature to the next
; function, so the suite can show it never re-checks focus.
OriginalPerformSearchBody(source) {
    start := InStr(source, "PerformSearch() {")
    stop := InStr(source, "IsEdgeRunning() {", , start)
    return start && stop ? SubStr(source, start, stop - start) : ""
}

FetchOriginalSource(repoDir, commit) {
    temp := A_Temp "\jape-original-" A_TickCount ".ahk"
    try {
        RunWait(A_ComSpec ' /c git show ' commit ':edge_search.ahk > "' temp '" 2>nul', repoDir, "Hide")
    } catch {
        return ""
    }
    if (!FileExist(temp))
        return ""
    text := ""
    try text := FileRead(temp, "UTF-8")
    try FileDelete(temp)
    return text
}
