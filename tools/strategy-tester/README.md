# Strategy Tester Automation — Hydra Test Runs Without the Clicking

MT5 can run backtests headlessly from a config file. This folder turns the
`docs/CHECKLIST.md` scenarios into one-click runs: each `.ini` launches the
terminal, runs one scenario with a fixed `.set` input preset, writes an HTML
report, and exits.

```
tools/strategy-tester/
├── README.md            ← this file
├── run_tests.bat        ← double-click runner (edit 2 paths first)
├── presets/             ← EA input presets (copied to MQL5\Presets)
│   ├── hydra_01_defaults_smoke.set
│   ├── hydra_02_deploy_fills.set
│   ├── hydra_03_ttl_expiry.set
│   └── hydra_04_whipsaw_guard.set
└── configs/             ← tester launch configs (one per scenario)
    ├── hydra_01_defaults_smoke.ini
    ├── hydra_02_deploy_fills.ini
    ├── hydra_03_ttl_expiry.ini
    └── hydra_04_whipsaw_guard.ini
```

## One-time setup

1. **Compile the EA first** in MetaEditor (the tester runs the compiled `.ex5`).
2. Find your **data folder**: in MT5 → `File → Open Data Folder`. Note the full path
   (looks like `C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<long-hex-id>`).
3. Edit the two `set` lines at the top of `run_tests.bat`:
   - `TERMINAL` = full path to your `terminal64.exe`
   - `DATADIR`  = the data folder path from step 2
4. Make sure your **demo login is saved** in the terminal (the tester downloads
   XAUUSD-VIP tick history through it) and then **close MT5** — the runner starts
   its own instances and a already-running terminal blocks them.
5. First run of each date range is slow: the terminal downloads real tick data.
   Subsequent runs on the same range are fast (data is cached).

## Running

Double-click `run_tests.bat`. It copies the presets into `MQL5\Presets`, then runs
the four configs one after another (each terminal instance closes itself when done).

**Results to send back:**
- The HTML reports `Hydra_0*.htm` in the data folder root.
- The tester journal: newest files in `<DATADIR>\Tester\<agent>\logs\` — this is where
  the `[HYDRA]` lines land. For the whipsaw run, the lines to look for are
  `WHIPSAW DETECTED`, the close/delete storm, and `state ACTIVE -> COOLDOWN`.

## The four scenarios

| Run | Preset highlights | Date range (edit in the .ini if needed) | Pass looks like |
|---|---|---|---|
| **01 defaults smoke** | Pure defaults, `AUTO_TRADING_ENABLED=false` | any recent quiet week | Init lines, gate logs, **zero orders** in the whole run |
| **02 deploy & fills** | Defaults + auto-trading ON | a trending session week | `grid deployed: 9+9`, direction lock on first fill, OCO cancel, sequential `fill n/9` |
| **03 TTL expiry** | Auto ON, `GridTTLMin=2`, wide first-level offset so nothing fills, ATR floor lowered so it deploys in quiet | any recent quiet week | Deploy → 2 min → `grid TTL 2 min expired with zero fills` → all 18 deleted → re-deploy |
| **04 whipsaw guard** | Auto ON, `OCO_Mode=false`, ATR ceiling + spread cap raised so the gates don't block the news candle | **a violent news day** — default is set to an NFP-style first-Friday; adjust to any big-range day you can see on the chart | `WHIPSAW DETECTED … gap N s` → all positions closed, all pendings deleted → `COOLDOWN (1/2 today)` |

⚠ Run 04's preset **deliberately weakens gates 2–3** (ATR/spread caps) so the test can
reach the whipsaw — those values are for this test only, never for live/demo charts.

⚠ Runs 02–04 have no basket exits yet (Phase 6 pending): positions ride to the end of
the range or until the guard/TTL acts. Expected at this stage — judge the mechanics,
not the P/L.

## Adjusting dates

Date ranges live in each `.ini` (`FromDate` / `ToDate`, format `YYYY.MM.DD`). For run 04
pick a day you can *see* had a huge two-sided M1 candle inside 12:00–15:00 GMT (NFP is
usually the first Friday of the month, ~12:30 GMT). If the guard doesn't trigger because
the candle only reached one side, shrink `FirstLevelOffsetUSD` in
`presets/hydra_04_whipsaw_guard.set` and rerun.

## Troubleshooting

- **Terminal opens but no test runs:** MT5 was already running, or the `Expert=` path
  doesn't match where the EA compiled (`MQL5\Experts\SIGMA\Straddle_Grid.ex5`).
- **"history not synchronized" / short report:** let the run repeat once (tick download),
  or open an XAUUSD-VIP chart in MT5 first and scroll back through the range.
- **Whipsaw never fires:** wrong day (one-sided move), or offsets too wide — see above.
- **Everything blocked by gate 1:** your chosen range has no bars inside the session
  windows (weekend/holiday) — pick different dates.
