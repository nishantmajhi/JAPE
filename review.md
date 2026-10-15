# Code Review — JAPE

Reviewed 2026-09-04 against the working tree (git HEAD `ff21003`, "first commit").
Scope: `edge_search.ahk`, `README.md`, `.gitignore`, the CI workflow, and the `logs/` directory.

**Updated 2026-10-01 after the fixes on branch `cleanup/2026-10-01` (unpushed).** The author
chose to keep the project and fix it. The verdict below still stands. Nothing in this pass
changed the timings, the keys or the randomisation, and nothing was done to make the script
harder to detect. The fixes protect the person running it: input goes only to Edge, the
logs are bounded, and the README now states the account risk.

## What was done

| # | Finding | State |
|---|---|---|
| 1 | Keystrokes go to whatever has focus once a search has started | **Fixed** — re-checked before every key |
| 2 | `Ctrl+T` into the wrong app | **Fixed** — the same check comes first. The window was one timer tick wide, because the loop had just checked |
| 3 | `A_TickCount` wraps after 49.7 days and searching stops | **Fixed** — confirmed against the v2 manual ("up to 49.7 days"); elapsed time is now taken modulo 2³² |
| 4 | A new log per launch, never removed; `FileAppend` unguarded | **Fixed** — ten files kept, 1 MB each, and writes never throw |
| — | Stale `logs/` file | **Deleted**. It was untracked and ignored: 21 lines from 2 November 2025 |
| — | README framing; MIT claimed with no licence | **Rewritten**: it states the purpose and quotes the Services Agreement. The MIT claim is dropped, and a licence is the author's choice |
| — | Narration comments; `static` mid-function; the swallowed exception | **Done** — the `static` is gone with the loop, and the exception text is logged |

Not in the review, and found by the tests or by checking:

- **Scrolls went to the window under the pointer**, which need not be Edge, for example on a
  second monitor. Scrolls now also need the pointer over Edge.
- **"Microsoft Edge is not running" was logged every second** while Edge was closed: about
  86,000 lines a day. It is now logged at most every 30 s, as the "not active" line already was.
- **A configured term with `+ ^ ! # {}` typed wrong**, because `Send` reads those as keys:
  "C++" typed "C". Characters are now sent with `{Text}`. The shipped terms type the same as
  before.
- **The release workflow cannot succeed.** `https://www.autohotkey.com/download/ahk.zip` is now
  AutoHotkey 1.1.37, which cannot run a v2 script, and `.../ahk2exe.zip` returns 404, so the
  job stops before it compiles anything. **Left alone on purpose.** Repairing it would make it
  easier to publish binaries of a script this review advises against publishing. Whether to
  do so is the author's decision, and so is the question below about whether the GitHub
  repository is public.

What the user sees is unchanged apart from the logs, and these are their differences: a
search that loses focus logs "Search abandoned: …" and where it stopped; the "Searching for"
line comes before Ctrl+T rather than after; and old log files are deleted beyond ten.

## Tests

`D:\dev-tools\autohotkey\AutoHotkey64.exe tests\run.ahk` — 95 checks in under a second, and
no dependency beyond AutoHotkey v2. The entry point is only parsed with `/validate`, never
run, because it would type into the terminal. `tests/original.ahk` transcribes the original's
search, main loop and log write with their I/O lifted out. The suite checks the transcription
against `ff21003` with `git show`, and every regression section shows the original failing.

## For the author

- **Is `github.com/nishantmajhi/JAPE` public, and are there releases?** The review's
  question, still open. Nothing here was pushed.
- **A licence**, or none. The README no longer claims MIT.
- **The release workflow**, as above.

## What this project is

An AutoHotkey v2 script that opens Microsoft Edge, types a randomly chosen search term one character
at a time with randomised 50-200 ms delays, presses Enter, then performs a few randomised scrolls —
repeating every 30 seconds for as long as Edge is the foreground window.

## Verdict — read this section before touching the code

Be clear-eyed about what this is. The README calls it "productivity automation", but the design
gives it away: randomised per-character typing delays, randomised scroll counts, randomised pauses
before Enter, and a curated list of innocuous search terms. None of that is needed to automate a
search. All of it is needed to make automated searches *look human*. This is a Microsoft Rewards
points farmer, and the human-emulation behaviour exists to avoid Microsoft's automation detection.

That is very likely a violation of the Microsoft Services Agreement, and the realistic downside is
having your Microsoft account suspended along with anything attached to it. The README's own
disclaimer half-acknowledges this.

**My recommendation: archive this one rather than maintain it.** Keep it in your history as
something you built — the AutoHotkey work is competent — but do not put further effort into it, do
not publish releases of it, and be aware that the fixes listed below make it a *better* script
without making it a *safer* one. If you want to keep the technique, the genuinely useful and
non-problematic part of this code is the "type into the focused window with human-ish timing"
routine, which is the same idea you later reused properly in VM Command Stepper.

Everything below assumes you keep it anyway.

## Critical issues

**1. Keystrokes go to whatever window has focus, not to Edge.** `PerformSearch()` checks
`IsEdgeActive()` once, then types for up to several seconds (30 characters × up to 200 ms, plus
pauses). If you alt-tab mid-typing — or any dialog steals focus — the remaining characters are typed
into whatever is now focused. That is how automation like this ends up dumping text into a chat
window, a terminal, or a document. Re-check `IsEdgeActive()` inside the typing loop and abort the
send the moment focus leaves Edge.

**2. Same problem, worse: `Send "^t"` opens a tab in the wrong app.** If focus changed between the
timer firing and the send, `Ctrl+T` goes elsewhere. Guard the whole `PerformSearch()` body, not just
its entry.

**3. `A_TickCount` wraps.** `lastSearchTime := A_TickCount / 1000` (and the comparisons against it)
break after roughly 49.7 days of uptime — at the wrap the elapsed-time subtraction goes negative and
searching stalls permanently. Use `A_TickCount` deltas computed as unsigned differences, or track
time with `A_Now`. Low practical impact, but it is a real latent bug.

**4. No log rotation, and a new log file per launch.** `WriteLog` appends to a file named after the
launch timestamp, and every run creates another one. Run this daily for a year and `logs/` holds 365
files. Worse, `FileAppend` has no error handling — a failure to write silently throws inside the
timer callback. Cap the log, reuse one rotating file, and wrap the append in `try`.

## Privacy and cleanup

- **`logs/edge_script_log_20251102_195055.txt` is sitting in the working tree.** `.gitignore` does
  list `logs/`, and `git ls-files` confirms it is not tracked — so nothing leaked. But it is a
  forgotten run artifact from a November 2025 session. Delete it.
- The log records every search term and every timestamp. That is a local activity log of your
  browsing automation. Harmless in isolation; just do not publish `logs/` in a release archive.

## Code quality

- Structure is reasonable: small named functions, one responsibility each, no dead code, no
  commented-out blocks, no leftover debug statements. For an early project this is decent.
- The comments are mostly narration of the next line (`; Open new tab` above `Send "^t"`). Those add
  nothing. The comments worth keeping are the ones stating intent, like the human-typing rationale.
- `searchInterval` is read as a global inside `PerformSearch()` only to print it in a log message —
  a small smell, harmless.
- `static lastInactiveLog := 0` is declared mid-function inside an `else` branch. Legal in v2, but
  move it to the top of `MainLoop()` where a reader expects declarations.
- The `try`/`catch` around window activation swallows the error object entirely and logs a generic
  message. Log the actual exception text; you will want it the first time this misbehaves.

## Documentation defects

- The README claims **"Safe and lightweight - no external dependencies"** and lists a "Safety
  Features" section. Given what the script actually does, that framing is misleading. If you keep
  the project, replace it with an accurate statement of the account risk.
- The README points at `https://github.com/nishantmajhi/JAPE/releases` for downloads. Confirm that
  repository is not public. Publishing a rewards-farming binary under your name is the part with
  real-world consequences attached.
- No `LICENSE` file exists despite the README declaring MIT.

## Action checklist

State as of 2026-10-01:

- [x] **P1** Decide whether to keep this at all. The author kept it. Releases and the repository's visibility are still the author's to check.
- [x] **P1** If keeping: re-verify focus inside the typing loop and abort on focus loss.
- [x] **P2** Delete the stale `logs/` file from the working tree.
- [x] **P2** Fix the `A_TickCount` wrap; add log rotation and `try` around `FileAppend`.
- [x] **P3** Rewrite the README's "Safety Features" and disclaimer to be accurate.
- [x] **P3** Add the `LICENSE` file or drop the MIT claim. The claim is dropped.

## Notes for a future session

Run from source with AutoHotkey v2 installed; `Ctrl+Alt+Q` exits. There are no tests (as of 2026-09-04; see "Tests" at the top). Before making
any change that touches send timing, re-read the verdict section above — do not treat "make the
timing look more human" as a legitimate improvement task.

## Licence, 2026-10-02

The author chose one licence for all of their projects: free for personal,
non-commercial use, modifiable for the user's own use, and not to be
distributed, original or modified. No standard licence says that, so `LICENSE`
is a short custom text, the same in every project apart from the year and what
it excludes. The README's licence section says the same. Anything above that
calls the licence an open question, or calls the project MIT, is superseded.

## CI, 2026-10-02

`.github/workflows/ci.yml` installs AutoHotkey 2.0.28 (checked against its
published SHA-256) and runs `tests/run.ahk` from bash on `windows-latest`,
with full history for the transcription check. Nothing has been pushed, so it
has not run on GitHub yet. Every job was run before committing, from a fresh
clone of this branch, the way a runner would run it: Windows jobs here, in
PowerShell 7 or the shell the step names, with only the tools the job sets up
on `PATH`. 95.

`build-release.yml` is unchanged; it still cannot succeed, for the reasons
above.
