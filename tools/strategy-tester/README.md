# Strategy Tester Automation — Hydra Test Runs Without the Clicking

MT5 can run backtests headlessly from a config file. This folder turns the
`docs/CHECKLIST.md` scenarios into one-click runs: each `.ini` launches the
terminal, runs one scenario with a fixed `.set` input preset, writes an HTML
report, and exits.

```
tools/strategy-tester/
├── README.md            ← this file
├── run_tests.bat        ← Windows runner (edit 2 paths first)
├── run_tests.sh         ← macOS runner (official Mac MT5 / Wine wrapper)
├── presets/             ← EA input presets (copied to MQL5\Presets)
│   ├── hydra_01_defaults_smoke.set
│   ├── hydra_02_deploy_fills.set
│   ├── hydra_03_ttl_expiry.set
│   ├── hydra_04_whipsaw_guard.set
│   ├── hydra_05_phase7_campaign.set
│   └── hydra_06_spread_stress.set
└── configs/             ← tester launch configs (one per scenario)
    ├── common.local.ini.example  ← template for your login (copy → common.local.ini)
    ├── hydra_01_defaults_smoke.ini
    ├── hydra_02_deploy_fills.ini
    ├── hydra_03_ttl_expiry.ini
    ├── hydra_04_whipsaw_guard.ini
    ├── hydra_05_phase7_campaign.ini
    ├── hydra_06_spread_stress.ini
    └── hydra_dash_visual.ini     ← Visual=1 dashboard eyeball check (not a pass/fail test)
```

## Which runner?

- **Windows, Git Bash / MINGW64**: `./run_tests.sh` — it detects Windows and drives the
  native `terminal64.exe` directly. Auto-detects the repo-as-data-folder layout
  (terminal64.exe + `MQL5\` in the repo root, e.g. `D:\Straddle_Grid`); override with
  `TERMINAL=/d/path/terminal64.exe DATADIR=/d/path ./run_tests.sh` if yours differs.
- **Windows, plain cmd/Explorer** (or MT5 inside a Parallels/VMware Windows VM):
  `run_tests.bat` — same auto-detection; edit the OVERRIDES block at the top if needed.
- **macOS with the official MT5 for Mac** (the MetaQuotes Wine wrapper):
  `./run_tests.sh` from Terminal. First time: `chmod +x run_tests.sh`.
  It auto-detects the standard install; override with env vars if yours differs:
  `MT5_APP="/Applications/MetaTrader 5.app" WINEPREFIX_DIR="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5" ./run_tests.sh`
- **If the script can't drive your Mac install** (Wine wrappers vary by version), the
  fallback is the GUI with the same presets: copy `presets/*.set` into the data folder's
  `MQL5/Presets`, open the Strategy Tester panel, pick the EA/symbol/M1/"Every tick based
  on real ticks", load the scenario's `.set` in the Inputs tab, set the dates from the
  matching `.ini`, and press Start. Same test, four clicks more.

## One-time setup

1. **Compile the EA first** in MetaEditor (the tester runs the compiled `.ex5`).
2. If auto-detection can't find your install: find your **data folder** in MT5 →
   `File → Open Data Folder` (standard installs look like
   `C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<long-hex-id>`) — this is *not*
   necessarily the git repo folder (the repo only holds source; the compiled `.ex5` and
   real tick history live in MT5's own data folder). Set it once and forget it: copy
   `.env.local.example` to `.env.local` in this folder and fill in `DATADIR` (and
   `TERMINAL` if needed). `.env.local` is gitignored. A `DATADIR`/`TERMINAL` env var
   passed on the command line still overrides it for a one-off run.
3. **Create your login file (required):** copy `configs/common.local.ini.example` to
   `configs/common.local.ini` and fill in your **DEMO account's** `Login` / `Password` /
   `Server`. This file is in `.gitignore` and never gets committed — do not paste its
   contents into chat, issues, or commit messages, and never put live-account
   credentials in it. **This step is not optional**: MT5's command-line tester needs an
   authenticated `[Common]` session to actually run automated tests. Without it,
   `terminal64.exe` silently opens your normal saved terminal session instead of
   testing — no error, no report (discovered 2026-07-14: a run with no
   `common.local.ini` just reopened the default chart profile and recovered whatever
   live/demo position and pending orders were already sitting on those charts). The
   runner now refuses to start if this file is missing.
4. Make sure that same **demo login is saved/valid** for the terminal (the tester
   downloads XAUUSD-VIP tick history through it) and then **close MT5** — the runner
   starts its own instances and an already-running terminal blocks them.
5. First run of each date range is slow: the terminal downloads real tick data.
   Subsequent runs on the same range are fast (data is cached).

## Running

Run `./run_tests.sh` from Git Bash (or double-click `run_tests.bat`). With no arguments it
copies the presets into `MQL5\Presets` (converting to the UTF-16 encoding MT5 requires),
then runs every config one after another (each terminal instance closes itself when done).

**Running a subset:** pass one or more substrings to filter which configs run, e.g.
`./run_tests.sh hydra_05` runs only the Phase 7 campaign, or
`./run_tests.sh hydra_05 hydra_06` runs both new Phase 7 scenarios without re-running the
already-passed 01–04 suite. `run_tests.bat` accepts one filter argument the same way
(`run_tests.bat hydra_05`). Useful since 05/06 cover months of data and take much longer
than the short 01–04 scenarios.

**Results to send back:**
- The HTML reports `Hydra_0*.htm` in the data folder root.
- The tester journal: newest files in `<DATADIR>\Tester\<agent>\logs\` — this is where
  the `[HYDRA]` lines land. For the whipsaw run, the lines to look for are
  `WHIPSAW DETECTED`, the close/delete storm, and `state ACTIVE -> COOLDOWN`.

## The scenarios

| Run | Preset highlights | Date range (edit in the .ini if needed) | Pass looks like |
|---|---|---|---|
| **01 defaults smoke** | Pure defaults, `AUTO_TRADING_ENABLED=false` | any recent quiet week | Init lines, gate logs, **zero orders** in the whole run |
| **02 deploy & fills** | Defaults + auto-trading ON | a trending session week | `grid deployed: 9+9`, direction lock on first fill, OCO cancel, sequential `fill n/9` |
| **03 TTL expiry** | Auto ON, `GridTTLMin=2`, wide first-level offset so nothing fills, ATR floor lowered so it deploys in quiet | any recent quiet week | Deploy → 2 min → `grid TTL 2 min expired with zero fills` → all 18 deleted → re-deploy |
| **04 whipsaw guard** | Auto ON, `OCO_Mode=false`, ATR ceiling + spread cap raised so the gates don't block the news candle | **a violent news day** — default is set to an NFP-style first-Friday; adjust to any big-range day you can see on the chart | `WHIPSAW DETECTED … gap N s` → all positions closed, all pendings deleted → `COOLDOWN (1/2 today)` |
| **05 Phase 7 campaign** | Full production defaults, nothing weakened | ~3 months (`2026.04.01`–`2026.07.10` by default), chosen to include multiple NFP days and at least one FOMC day | Runs clean end to end: no journal errors, zero partial grids, gates/deploy/fills/whipsaw/basket all interacting correctly over the long window |
| **06 spread stress** | Full production defaults + `MaxSpreadPoints=1` (below any real spread, so gate 3 blocks on real historical spread every time — not a tester-engine spread override, see note below) | ~6 weeks (`2026.06.01`–`2026.07.10` by default) | **Zero orders the entire run** — only clean `gates FAIL - gate 3 (Spread): N > max 1` lines, no "invalid stops" errors |
| **dash_visual** | Same inputs/date range as run 02 — that window is already known to cycle IDLE→ARMED→ACTIVE (TP win, SL loss)→COOLDOWN multiple times in 4 days | `2026.07.06`–`2026.07.10` | Not a pass/fail test — `Visual=1`, `ShutdownTerminal=0`: opens the interactive tester chart so you can eyeball the Phase 8 dashboard cycle through every state/color without babysitting the Strategy Tester GUI settings by hand. Use the speed slider / pause button once it opens. |

⚠ Run 04's preset **deliberately weakens gates 2–3** (ATR/spread caps) so the test can
reach the whipsaw — those values are for this test only, never for live/demo charts.

⚠ Runs 02–04 (and 05/06 pre-Phase-6) had no basket exits: as of Phase 6 (v2.0), basket
TP/SL/trailing exits are live and should appear in every run where a basket goes into
profit/loss/trail — see `docs/PENDING_USER_ACTIONS.md` for what "correct" looks like.

⚠ Run 06 originally tried MT5's tester-level `[Tester] Spread=` override to force a fixed
elevated spread. That override was silently ignored on this build (2026-07-15: the run
traded normally with real historical spread and zero gate-3 failures) — it now forces the
block from the EA-input side (`MaxSpreadPoints=1`) instead, which is reliable regardless of
tester-engine spread-override support.

## Adjusting dates

Date ranges live in each `.ini` (`FromDate` / `ToDate`, format `YYYY.MM.DD`). For run 04
pick a day you can *see* had a huge two-sided M1 candle inside 12:00–15:00 GMT (NFP is
usually the first Friday of the month, ~12:30 GMT). If the guard doesn't trigger because
the candle only reached one side, shrink `FirstLevelOffsetUSD` in
`presets/hydra_04_whipsaw_guard.set` and rerun.

## Troubleshooting

- **Every run logs `AUTO_TRADING_ENABLED is false` (even 02–04):** the input preset didn't
  load and the tester fell back to defaults. Cause seen in the field: `.set` files must be
  UTF-16 — the runner now converts them on copy, and each `.ini` also carries a
  `[TesterInputs]` section as a second channel, so this failure mode is doubly covered.
  Quick verification for any run: 02–04 must NOT show the "AUTO_TRADING_ENABLED is false"
  init line.

- **Terminal opens but no test runs:** MT5 was already running, or the `Expert=` path
  doesn't match where the EA compiled (`MQL5\Experts\Straddle\Straddle_Grid.ex5`).
- **"history not synchronized" / short report:** let the run repeat once (tick download),
  or open an XAUUSD-VIP chart in MT5 first and scroll back through the range.
- **Whipsaw never fires:** wrong day (one-sided move), or offsets too wide — see above.
- **Everything blocked by gate 1:** your chosen range has no bars inside the session
  windows (weekend/holiday) — pick different dates.
