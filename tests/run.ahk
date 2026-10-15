#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\jape.ahk
#Include original.ahk

; run.ahk — the JAPE test suite.
;
;   D:\dev-tools\autohotkey\AutoHotkey64.exe tests\run.ahk
;
; Everything here calls lib/jape.ahk directly, with a fake in place of the
; keyboard, the mouse, the clock and the windows. There is no black-box half,
; and deliberately so: edge_search.ahk starts Edge and types into the window
; in front every 30 seconds, so running it from a test would type into the
; terminal running the suite. The entry point is only parsed (/validate).
;
; Sections marked "regression" run the same assertion against tests/original.ahk,
; the pre-cleanup code transcribed with its I/O lifted out, and require it to
; fail there. A regression test that passes against the unfixed code is
; testing nothing.

Passed := 0
Failed := 0
Skipped := 0

OnError(ReportUncaught)

Main()


; An uncaught error would otherwise raise a dialog nothing here can dismiss.
ReportUncaught(err, mode) {
    Say("")
    Say("UNCAUGHT " Type(err) ": " (err is Error ? err.Message : err))
    if (err is Error)
        Say("  " err.File ":" err.Line)
    ExitApp 3
}

Main() {
    global Passed, Failed, Skipped

    Say("JAPE test suite")
    Say("")

    TestTranscriptionFidelity()
    TestTickElapsed()
    TestRunSearchHappyPath()
    TestFocusLostWhileTyping()
    TestFocusLostBeforeEnter()
    TestFocusLostWhileScrolling()
    TestPointerOverAnotherWindow()
    TestFocusLostBeforeTheTab()
    TestSpecialCharacters()
    TestSchedulerBasics()
    TestSchedulerQuietLogging()
    TestSchedulerAcrossTheWrap()
    TestLogFiles()
    TestLogWriteFailure()
    TestEntryPoint()

    Say("")
    Say(Passed " passed, " Failed " failed" (Skipped ? ", " Skipped " skipped" : ""))
    ExitApp Failed ? 1 : 0
}


; ── Harness ───────────────────────────────────────────────────────────────────

Say(text) {
    try FileAppend text "`n", "*"
}

Section(name) {
    Say(name)
}

Check(condition, description) {
    global Passed, Failed
    if (condition) {
        Passed++
        return true
    }
    Failed++
    Say("  FAIL  " description)
    return false
}

Same(actual, expected, description) {
    global Passed, Failed
    if (Equal(actual, expected)) {
        Passed++
        return true
    }
    Failed++
    Say("  FAIL  " description)
    Say("          expected: " Show(expected))
    Say("          actual:   " Show(actual))
    return false
}

Skip(description) {
    global Skipped
    Skipped++
    Say("  SKIP  " description)
}

; == on two Arrays compares identity, so compare contents.
Equal(a, b) {
    if (a is Array && b is Array) {
        if (a.Length != b.Length)
            return false
        Loop a.Length {
            if (!Equal(a[A_Index], b[A_Index]))
                return false
        }
        return true
    }
    if (a is Array || b is Array)
        return false
    return a == b
}

; `1 == true` in AHK, so numbers and strings are shown before booleans are
; considered; otherwise every count of one prints as "true".
Show(value) {
    if (value is Array) {
        parts := ""
        for item in value
            parts .= (parts = "" ? "" : ", ") Show(item)
        return "[" parts "]"
    }
    return "<" value ">"
}

RepoDir() {
    return A_ScriptDir "\.."
}


; A keyboard, mouse and clock that record what was done to them. Focus is lost
; after `focusFor` keys have been sent (the user alt-tabs part way through),
; and every key and scroll is recorded with whether Edge was in front at the
; moment it went out.
class FakeIO {
    __New(focusFor := 1000000, pointerOverEdge := true) {
        this.focusFor := focusFor
        this.pointerOverEdge := pointerOverEdge
        this.keys := []
        this.keysWhileAway := []
        this.scrolls := []
        this.scrollsElsewhere := []
        this.logs := []
        this.slept := 0
        this.activeRule := ""  ; a function of this FakeIO, to lose focus some other way
    }
    EdgeActive() => this.activeRule ? this.activeRule.Call(this) : this.keys.Length < this.focusFor
    EdgeUnderMouse() => this.pointerOverEdge
    Send(keys) {
        if (!this.EdgeActive())
            this.keysWhileAway.Push(keys)
        this.keys.Push(keys)
    }
    Scroll(clicks) {
        if (!this.EdgeActive() || !this.pointerOverEdge)
            this.scrollsElsewhere.Push(clicks)
        this.scrolls.Push(clicks)
    }
    Sleep(ms) {
        this.slept += ms
    }
    ; Always the low end, so a run is repeatable and the term is the first one.
    Random(low, high) => low
    Log(text) {
        this.logs.Push(text)
    }
}

; A FakeIO that also answers a single-term list for the original's own pick.
OriginalSearch(io, term) {
    Original_PerformSearch(io, [term], 30)
    return io
}

; `Send A_LoopField` in the original, `{Text}` + the character now: strip the
; prefix so the two can be compared key for key.
Typed(keys) {
    out := []
    for k in keys
        out.Push(SubStr(k, 1, 6) = "{Text}" ? SubStr(k, 7) : k)
    return out
}


; ── The transcription ─────────────────────────────────────────────────────────

TestTranscriptionFidelity() {
    Section("tests/original.ahk still matches " ORIGINAL_COMMIT)

    source := FetchOriginalSource(RepoDir(), ORIGINAL_COMMIT)
    if (source = "") {
        Skip("git or commit " ORIGINAL_COMMIT " unavailable; the transcription could not be verified")
        return
    }
    Check(InStr(source, "Edge Auto-Search Script"), "the fetched file is edge_search.ahk")
    for snippet in OriginalSnippets()
        Check(InStr(source, snippet), "the original still contains: " snippet)

    body := OriginalPerformSearchBody(source)
    Check(body != "", "PerformSearch() was found in the original")
    Check(!InStr(body, "IsEdgeActive"), "and it never re-checks focus once it has started")
    Check(!InStr(source, "MouseGetPos"), "and nothing in the original looks at what is under the pointer")
}


; ── Time ──────────────────────────────────────────────────────────────────────

TestTickElapsed() {
    Section("TickElapsed")
    Same(TickElapsed(5000, 2000), 3000, "an ordinary interval")
    Same(TickElapsed(2000, 2000), 0, "no time at all")
    Same(TickElapsed(1000, 0xFFFFFC18), 2000, "across the wrap at 2**32 ms")
    Same(TickElapsed(0, 0xFFFFFFFF), 1, "one millisecond either side of it")
}


; ── One search ────────────────────────────────────────────────────────────────

TestRunSearchHappyPath() {
    Section("RunSearch, nothing interrupting")
    io := FakeIO()
    result := RunSearch("Tokyo", io)
    Same(result, "", "the whole search ran")
    Same(io.keys, ["^t", "{Text}T", "{Text}o", "{Text}k", "{Text}y", "{Text}o", "{Enter}"]
       , "a new tab, the term a character at a time, then Enter")
    Same(io.scrolls, [3, 3, 3], "three scrolls of three, with the fake's low-end Random")
    ; 500 after the tab, 50 per character, 300 before Enter, 3000 before scrolling,
    ; 500 after each scroll: the timings the script has always used.
    Same(io.slept, 500 + 5 * 50 + 300 + 3000 + 3 * 500, "the same pauses as before")
    Check(io.logs.Length && io.logs[1] = "Typing: Tokyo", "the term is logged as it was")

    orig := OriginalSearch(FakeIO(), "Tokyo")
    Same(Typed(io.keys), orig.keys, "the keys are the original's, apart from {Text}")
    Same(io.scrolls, orig.scrolls, "and so are the scrolls")
    Same(io.slept, orig.slept, "and the pauses")
}

TestFocusLostWhileTyping() {
    Section("regression: focus lost while typing")
    ; Ctrl+T and "Tok" go out, then the user switches windows.
    io := FakeIO(4)
    result := RunSearch("Tokyo", io)
    Same(io.keysWhileAway, [], "no key goes to the window the user switched to")
    Same(io.keys.Length, 4, "the search stops where focus was lost")
    Same(io.scrolls, [], "and does not go on to scroll")
    Check(InStr(result, "after typing 3 of 5 characters"), "and says where it stopped: " result)
    Check(io.logs.Length && InStr(io.logs[io.logs.Length], "Search abandoned"), "in the log too")

    orig := OriginalSearch(FakeIO(4), "Tokyo")
    Same(orig.keysWhileAway, ["y", "o", "{Enter}"]
       , "original: the rest of the term and Enter went to the other window")
    Check(orig.keysWhileAway.Length > 0, "original fails this test")
}

TestFocusLostBeforeEnter() {
    Section("regression: focus lost just before Enter")
    io := FakeIO(6)  ; Ctrl+T and all five characters
    RunSearch("Tokyo", io)
    Same(io.keysWhileAway, [], "Enter is not pressed in another window")
    Check(io.keys[io.keys.Length] != "{Enter}", "the search stops before Enter")

    orig := OriginalSearch(FakeIO(6), "Tokyo")
    Same(orig.keysWhileAway, ["{Enter}"], "original: Enter went to the other window")
}

TestFocusLostWhileScrolling() {
    Section("regression: focus lost while scrolling")
    ; Focus holds for the whole search and the first scroll, then goes.
    io := FakeIO()
    io.activeRule := (self) => self.keys.Length < 7 || self.scrolls.Length < 1
    RunSearch("Tokyo", io)
    Same(io.scrollsElsewhere, [], "no scroll after focus has gone")
    Same(io.scrolls.Length, 1, "the scrolling stops at the first one after focus is lost")

    orig := FakeIO()
    orig.activeRule := io.activeRule
    OriginalSearch(orig, "Tokyo")
    Same(orig.scrollsElsewhere.Length, 2, "original: the other two scrolls went on regardless")
}

TestPointerOverAnotherWindow() {
    Section("regression: Edge in front, but the pointer over another window")
    ; The wheel goes to the window under the pointer, not the active one: on a
    ; second monitor, for instance.
    io := FakeIO(, false)
    result := RunSearch("Tokyo", io)
    Same(io.scrolls, [], "nothing is scrolled")
    Check(InStr(result, "pointer was not over Edge"), "and the reason is given: " result)
    Same(io.keys[io.keys.Length], "{Enter}", "the search itself still ran")

    orig := OriginalSearch(FakeIO(, false), "Tokyo")
    Same(orig.scrollsElsewhere, [3, 3, 3], "original: three scrolls went to the window under the pointer")
}

TestFocusLostBeforeTheTab() {
    Section("focus already gone when the search starts")
    io := FakeIO(0)
    result := RunSearch("Tokyo", io)
    Same(io.keys, [], "not even Ctrl+T is sent")
    Check(InStr(result, "before opening a tab"), "and it says so: " result)
}

TestSpecialCharacters() {
    Section("regression: a configured term with characters Send treats as keys")
    io := FakeIO()
    RunSearch("C++", io)
    Same(io.keys, ["^t", "{Text}C", "{Text}+", "{Text}+", "{Enter}"], "each + is typed as a +")

    ; Send "+" on its own is the Shift modifier with nothing to modify, so the
    ; original typed "C" and nothing else (AutoHotkey docs, Send: "+" = Shift).
    orig := OriginalSearch(FakeIO(), "C++")
    Same(orig.keys, ["^t", "C", "+", "+", "{Enter}"], "original: bare + sent as a modifier")
    Check(orig.keys[3] != "{Text}+", "original fails this test")
}


; ── The main loop ─────────────────────────────────────────────────────────────

; Runs a scheduler over a list of ticks, performing searches as it asks, and
; returns what happened: "first@t", "search@t" and logged lines.
Drive(sched, ticks, searchMs := 12000) {
    out := []
    for t in ticks {
        action := sched.Tick(t[1], t[2], t[3])
        if (sched.logLine != "")
            out.Push("log:" sched.logLine)
        if (action != "") {
            out.Push(action "@" t[1])
            sched.Searched(action, t[1], t[1] + searchMs)
        }
    }
    return out
}

Ticks(fromMs, count, running := true, active := true, stepMs := 1000) {
    out := []
    Loop count
        out.Push([fromMs + (A_Index - 1) * stepMs, running, active])
    return out
}

TestSchedulerBasics() {
    Section("SearchScheduler")
    s := SearchScheduler(30)
    Same(s.Tick(1000, true, false), "", "no first search while Edge is in the background")
    Same(s.Tick(2000, true, true), "first", "the first search as soon as Edge is in front")
    s.Searched("first", 2000, 14000)
    Same(s.Tick(44000, true, true), "", "the interval counts from the end of the first search")
    Same(s.Tick(44001, true, true), "search", "and a search follows once it is exceeded")
    s.Searched("search", 44001, 56000)
    Same(s.Tick(74001, true, true), "", "later intervals count from the start of the search")
    Same(s.Tick(74002, true, true), "search", "as the original's did")

    ; The same ticks through the original.
    st := { firstSearchDone: true, lastSearchTime: 14, searchInterval: 30, lastInactiveLog: 0 }
    Same(Original_MainLoopTick(st, 44000, true, true).action, "", "original agrees at 44000")
    Same(Original_MainLoopTick(st, 44001, true, true).action, "search", "and at 44001")
}

TestSchedulerQuietLogging() {
    Section("regression: waiting for Edge is logged twice a minute, not every second")
    s := SearchScheduler(30)
    out := Drive(s, Ticks(1000, 60, false))
    Same(out.Length, 2, "a minute of Edge closed logs two lines")
    Same(out[1], "log:Microsoft Edge is not running. Waiting...", "the line is the original's")

    lines := 0
    st := { firstSearchDone: false, lastSearchTime: 0, searchInterval: 30, lastInactiveLog: 0 }
    for t in Ticks(1000, 60, false)
        lines += Original_MainLoopTick(st, t[1], t[2], t[3]).lines.Length
    Same(lines, 60, "original: sixty lines a minute, 86,400 a day")

    s := SearchScheduler(30)
    s.Searched("first", 0, 0)
    out := Drive(s, Ticks(1000, 60, true, false))
    Same(out.Length, 2, "Edge in the background is still logged every 30 s, as before")
}

TestSchedulerAcrossTheWrap() {
    Section("regression: A_TickCount passing 49.7 days")
    wrapAt := 0x100000000
    ; Two minutes of ticks starting just before the wrap. The ticks wrap, as
    ; A_TickCount does; the same two minutes anywhere else are the yardstick.
    CountSearches(base, wrap) {
        s := SearchScheduler(30)
        s.Searched("first", base - 20000, base - 8000)
        n := 0
        for t in Ticks(base - 7000, 120) {
            now := wrap ? Mod(t[1], wrapAt) : t[1]
            if (s.Tick(now, true, true) != "") {
                n++
                s.Searched("search", now, now + 12000)
            }
        }
        return n
    }
    Same(CountSearches(wrapAt, true), CountSearches(1000000, false), "the two minutes across the wrap hold as many searches as any other two")
    Check(CountSearches(1000000, false) = 3, "which is three")

    st := { firstSearchDone: true, lastSearchTime: (wrapAt - 8000) / 1000, searchInterval: 30, lastInactiveLog: 0 }
    origSearches := 0
    for t in Ticks(wrapAt - 7000, 120)
        if (Original_MainLoopTick(st, Mod(t[1], wrapAt), true, true).action != "")
            origSearches++
    Same(origSearches, 0, "original: none, and none would follow for another 49.7 days")
}


; ── Logs ──────────────────────────────────────────────────────────────────────

TempDir(name) {
    dir := A_Temp "\jape-test-" name "-" A_TickCount
    DirCreate(dir)
    return dir
}

TestLogFiles() {
    Section("LogFiles")
    dir := TempDir("logs")
    Loop 12
        FileAppend("old`n", dir "\edge_script_log_20250101_0000" Format("{:02}", A_Index) ".txt")
    FileAppend("not a log`n", dir "\notes.txt")

    logs := LogFiles(dir, 10)
    Check(logs.Write("hello"), "a line is written")
    files := logs.Files()
    Same(files.Length, 10, "regression: launches no longer leave a file each for ever; ten are kept")
    Check(!FileExist(dir "\edge_script_log_20250101_000001.txt"), "the oldest went first")
    Check(FileExist(dir "\edge_script_log_20250101_000012.txt"), "the newest old one stayed")
    Check(FileExist(dir "\notes.txt"), "files that are not logs are left alone")
    Same(files[files.Length], StrSplit(logs.path, "\").Pop(), "the new file sorts last")
    line := FileRead(logs.path)
    Check(RegExMatch(line, "^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d - INFO - hello\n$"), "in the original's format: " line)

    ; A file past the limit is followed by another, and the total stays capped.
    small := LogFiles(TempDir("rotate"), 3, 200)
    first := small.path
    Loop 30
        small.Write("line " A_Index " of thirty, padded out to make the file grow")
    Check(small.path != first, "a full file is followed by a new one")
    Check(small.Files().Length <= 3, "and no more than three are kept: " small.Files().Length)
    Check(FileGetSize(small.path) < 400, "the current one is small")

    two := LogFiles(dir, 10)
    Check(two.path != logs.path, "two launches in the same second get two files")
    try DirDelete(dir, true)
    try DirDelete(small.dir, true)
}

TestLogWriteFailure() {
    Section("regression: a log that cannot be written does not raise an error")
    ; A path inside a file cannot be a directory, so nothing can be written there.
    blocker := A_Temp "\jape-test-blocker-" A_TickCount ".txt"
    FileAppend("x", blocker)
    bad := LogFiles(blocker "\logs")
    threw := false
    ok := true
    try ok := bad.Write("anything")
    catch
        threw := true
    Check(!threw, "Write does not throw")
    Same(ok, false, "it reports that the line was not written")

    origThrew := false
    try Original_WriteLog("anything", blocker "\logs\x.txt")
    catch
        origThrew := true
    Check(origThrew, "original: FileAppend threw, which inside the timer is an error dialog every second")
    try FileDelete(blocker)
}


; ── The entry point ───────────────────────────────────────────────────────────

TestEntryPoint() {
    Section("edge_search.ahk")
    path := RepoDir() "\edge_search.ahk"

    ; /validate parses and reports syntax errors on stderr without running the
    ; script. Its exit code is 2 either way, so the output is the signal.
    out := A_Temp "\jape-validate-" A_TickCount ".txt"
    RunWait(A_ComSpec ' /c ""' A_AhkPath '" /validate /ErrorStdOut=UTF-8 "' path '"" > "' out '" 2>&1', RepoDir(), "Hide")
    report := ""
    try report := FileRead(out, "UTF-8")
    try FileDelete(out)
    Same(Trim(report), "", "the entry point parses without error")

    source := FileRead(path, "UTF-8")
    Check(InStr(source, "#Include lib\jape.ahk"), "it includes the library")
    Check(InStr(source, "RunSearch("), "searches go through RunSearch")
    Check(InStr(source, "SearchScheduler("), "the loop's decisions go through SearchScheduler")
    Check(InStr(source, "LogFiles("), "and the log through LogFiles")
    ; The decisions are gone from the plumbing. If one comes back, a second
    ; copy has appeared, and the tests stop covering what runs.
    Check(!InStr(source, "Loop Parse"), "the typing loop is not in the entry point")
    Check(InStr(source, 'static Scroll(clicks) => Click("WheelDown " clicks)'), "the only scroll is EdgeIO.Scroll")
    StrReplace(source, "WheelDown", , , &wheel)
    Same(wheel, 1, "and there is no other")
    Check(!InStr(source, "A_TickCount / 1000"), "nor the wrapping time arithmetic")
    Check(!InStr(source, "FileAppend"), "nor an unguarded FileAppend")
    Check(InStr(source, "MouseGetPos("), "EdgeUnderMouse looks at the window under the pointer")
}
