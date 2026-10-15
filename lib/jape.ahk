#Requires AutoHotkey v2.0

; lib/jape.ahk — the decisions edge_search.ahk makes. Nothing here sends a key,
; reads a window or sleeps on its own account: RunSearch is handed an object
; that does those things, and the script passes the real one while
; tests/run.ahk passes a fake. LogFiles is the exception and touches the logs
; directory it is given, which the tests point at a temporary one.


; Milliseconds from `since` to `now`, both A_TickCount values. A_TickCount
; counts up to 49.7 days of uptime and then starts again from 0, so a plain
; subtraction across that point is negative: the original's "has the interval
; passed" test then stayed false, and searching stopped for good.
TickElapsed(now, since) {
    return Mod(now - since + 0x100000000, 0x100000000)
}


; Opens a new tab, types the term one character at a time, presses Enter, then
; scrolls a few times: one search, as the script has always done it.
;
; Before every key it sends, it checks that Edge is still the active window,
; and before every scroll that Edge is also the window under the pointer,
; because the wheel goes to whichever window the pointer is over. If a check
; fails, the rest of the search is abandoned. Before this, a search that lost
; focus part way through typed its remaining characters and its Enter into
; whatever window had focus instead, and scrolled whatever was under the
; pointer.
;
; io must provide: EdgeActive(), EdgeUnderMouse(), Send(keys), Sleep(ms),
; Random(low, high), Scroll(clicks) and Log(text). intervalSeconds is only
; for the log line.
;
; Returns "" when the whole search ran, otherwise why it stopped.
RunSearch(term, io, intervalSeconds := 30) {
    if (!io.EdgeActive())
        return SearchStopped(io, "Edge lost focus before opening a tab")
    io.Send("^t")
    io.Sleep(500)

    io.Log("Typing: " term)
    Loop Parse term {
        if (!io.EdgeActive())
            return SearchStopped(io, "Edge lost focus after typing " (A_Index - 1) " of " StrLen(term) " characters")
        ; {Text} types the character itself. Without it a configured term such
        ; as "C++" sent "+", which Send reads as the Shift key, and typed "C".
        io.Send("{Text}" A_LoopField)
        io.Sleep(io.Random(50, 200))
    }
    io.Sleep(io.Random(300, 800))
    if (!io.EdgeActive())
        return SearchStopped(io, "Edge lost focus before pressing Enter")
    io.Send("{Enter}")
    io.Log("Search completed. Next search in " intervalSeconds " seconds")

    io.Sleep(3000)

    scrolls := io.Random(3, 6)
    Loop scrolls {
        if (!io.EdgeActive())
            return SearchStopped(io, "Edge lost focus before scroll " A_Index " of " scrolls)
        if (!io.EdgeUnderMouse())
            return SearchStopped(io, "the pointer was not over Edge before scroll " A_Index " of " scrolls)
        amount := io.Random(3, 10)
        io.Scroll(amount)
        io.Log("Scrolled " amount " clicks")
        io.Sleep(io.Random(500, 1500))
    }
    return ""
}

SearchStopped(io, reason) {
    io.Log("Search abandoned: " reason)
    return reason
}


; What the main loop does on each one-second tick. Tick() answers "first",
; "search" or "" and leaves a line worth logging in .logLine, or "". After a
; search, Searched() records it.
class SearchScheduler {
    __New(intervalSeconds, quietSeconds := 30) {
        this.intervalMs := intervalSeconds * 1000
        this.quietMs := quietSeconds * 1000
        this.firstSearchDone := false
        this.lastSearch := 0
        this.lastSaid := Map()
        this.logLine := ""
    }

    Tick(now, edgeRunning, edgeActive) {
        this.logLine := ""
        if (!edgeRunning) {
            ; Once a tick, this filled the log at a line a second, about
            ; 86,000 lines a day, for as long as Edge was closed.
            this.SayEvery("not-running", now, "Microsoft Edge is not running. Waiting...")
            return ""
        }
        if (!this.firstSearchDone)
            return edgeActive ? "first" : ""
        if (!edgeActive) {
            this.SayEvery("inactive", now, "Edge is running but not active. Waiting for Edge to be focused...")
            return ""
        }
        return TickElapsed(now, this.lastSearch) > this.intervalMs ? "search" : ""
    }

    ; `startedAt` is when the search began. The first search is counted from
    ; when it ended, as it always was.
    Searched(kind, startedAt, endedAt) {
        this.firstSearchDone := true
        this.lastSearch := kind = "first" ? endedAt : startedAt
    }

    SayEvery(key, now, text) {
        if (this.lastSaid.Has(key) && TickElapsed(now, this.lastSaid[key]) <= this.quietMs)
            return
        this.lastSaid[key] := now
        this.logLine := text
    }
}


; The logs directory: one file per launch, named for the launch time, as
; before. A file that grows past maxBytes is followed by a new one, and only
; the newest `keep` files are kept, so the directory no longer grows by one
; file a run for ever. Writing never throws: a log that cannot be written
; must not stop the script, and an error raised inside the timer used to put
; up a dialog every second.
class LogFiles {
    static Prefix := "edge_script_log_"

    __New(dir, keep := 10, maxBytes := 1048576) {
        this.dir := dir
        this.keep := keep
        this.maxBytes := maxBytes
        this.path := ""
        try DirCreate(dir)
        this.Start()
    }

    Start() {
        stamp := FormatTime(, "yyyyMMdd_HHmmss")
        path := this.dir "\" LogFiles.Prefix stamp ".txt"
        n := 1
        while FileExist(path)
            path := this.dir "\" LogFiles.Prefix stamp Format("_{:03}", ++n) ".txt"
        this.path := path
        this.Prune()
    }

    ; Oldest first by name, which is by time: the names are timestamps.
    Files() {
        names := []
        try {
            Loop Files this.dir "\" LogFiles.Prefix "*.txt"
                names.Push(A_LoopFileName)
        }
        sorted := ""
        for name in names
            sorted .= (sorted = "" ? "" : "`n") name
        return sorted = "" ? [] : StrSplit(Sort(sorted), "`n")
    }

    ; Leaves room for the file about to be written.
    Prune() {
        files := this.Files()
        excess := files.Length - (this.keep - 1)
        Loop excess
            try FileDelete(this.dir "\" files[A_Index])
    }

    Write(message) {
        try {
            if (FileExist(this.path) && FileGetSize(this.path) >= this.maxBytes)
                this.Start()
            FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " - INFO - " message "`n", this.path)
            return true
        }
        return false
    }
}
