# JAPE

An AutoHotkey v2 script that makes Microsoft Edge search the web on its own.
Every 30 seconds, while Edge is the active window, it opens a new tab, types a
term from a fixed list one character at a time, presses Enter, and scrolls the
results a few times.

## Read this first: what it is for, and the risk

Nothing about searching needs the typing to be slow, the pauses to be random,
or the scrolling to vary. Those choices make the searches look as if a person
made them, and the obvious use is earning Microsoft Rewards search points.

The Microsoft Services Agreement says such searches do not count. Section
14.m.vi says a Rewards "Search" does not include "a query entered by a bot,
macro, or other automated or fraudulent means of any kind". Section 14.m.xii
lets Microsoft "immediately cancel your Rewards Account, disqualify you from
future participation in the Rewards Program, forfeit all of your earned
Points" when it believes the program has been abused. The account at risk is
whichever Microsoft account Edge is signed in to.

Earlier versions of this README called the script "safe" and listed "safety
features". Those described its manners, not this risk.

## What it does to your computer

It sends real keystrokes and mouse-wheel scrolls, so it only acts while Edge
is the active window. Before every key it checks again that Edge is still in
front, and before every scroll that the pointer is over Edge, since the wheel
scrolls whatever window is under the pointer. If either check fails, the rest
of that search is abandoned and the log says where. Switching away from Edge
mid-search therefore stops it instead of typing into your other window.

On startup it opens Edge if it is not running and does one search straight
away, so you can see it working.

Press **Ctrl+Alt+Q** to stop it, or exit it from its tray icon.

## Running it

1. Install AutoHotkey v2 (`winget install AutoHotkey.AutoHotkey`).
2. Double-click `edge_search.ahk`. It needs the `lib` folder beside it.

To change the interval or the terms, edit `searchInterval` and `searchItems`
near the top of `edge_search.ahk`. Terms are typed exactly as written,
symbols included.

## Logs

Each launch writes a log in `logs\` beside the script, named for the launch
time (`edge_script_log_YYYYMMDD_HHMMSS.txt`). It records every term searched
and when. A file that passes 1 MB is followed by a new one, and only the ten
newest files are kept. If the folder cannot be written, the script runs
without a log.

## Layout

- `edge_search.ahk` — starts Edge, runs the one-second timer, and supplies
  the real keyboard, mouse and windows.
- `lib\jape.ahk` — the decisions: one search and when it stops (`RunSearch`),
  when to search and what to log (`SearchScheduler`), the logs folder
  (`LogFiles`), and elapsed time that survives the system timer wrapping after
  49.7 days of uptime (`TickElapsed`).
- `tests\` — the test suite.

## Tests

```
D:\dev-tools\autohotkey\AutoHotkey64.exe tests\run.ahk
```

Use any AutoHotkey v2 path. The suite prints each section and a pass/fail
count, and exits non-zero on failure. It never runs the script itself, because
that would type into the terminal. It calls `lib\jape.ahk` with a stand-in
keyboard, mouse and clock, and only parses `edge_search.ahk` (`/validate`).

Sections named "regression" also run against `tests\original.ahk`, which is the
first commit's search and timer code transcribed with its input and output
taken out, and show that the original fails them. The suite checks the
transcription against that commit with `git show`, so it needs the
repository's history.

## Releases

`.github/workflows/build-release.yml` compiles `JAPE.exe` on a version tag and
publishes it as a GitHub release. As of 2026-10-01 it cannot succeed, for two
reasons. The AutoHotkey it downloads (`ahk.zip`) is now version 1.1, which
cannot run this v2 script, and the compiler download (`ahk2exe.zip`) returns
404. It has been left as it is; see `review.md`.

## Licence

Free for personal, non-commercial use. You may use, study and modify this
software for yourself, but you may not use it commercially, and you may not
share or publish it, in its original form or modified. See [LICENSE](LICENSE)
for the full terms.
