# PENDING_USER_ACTIONS.md — Your Test Queue

> Everything currently waiting on you (the user, at your MT5 PC/Mac).
> Current build: `Straddle_Grid.mq5` **v2.0** (Phases 1–6 complete: skeleton, gates, grid
> deploy/expiry, direction lock & OCO, Whipsaw Guard, **Basket Manager**). Phase 7
> (validation campaign) closed 2026-07-15 — no code change, still v2.0.
>
> ✅ **Validated so far** (tester, real ticks, VTMarkets-Demo): compile clean · gates +
> short-circuit · grid deploy 9+9 with correct prices/lots · OCO cancel · sequential fills ·
> TTL expiry/redeploy (no partial grids) · whipsaw guard (4 firings, reproducible, correct
> cooldowns, 2/2 daily lockout) · **Basket Manager**: TP/SL scaling exact across every
> observed volume, trailing floor monotonic-only with correct math, 60 s post-exit cooldown
> with zero exceptions, whipsaw still wins over basket logic · **3-month campaign** (484
> full deploy→exit cycles, zero partial grids, zero orphaned baskets, zero journal errors) ·
> **spread stress** (62/62 deployment attempts cleanly blocked by gate 3, zero orders, zero
> errors). Full detail in `docs/TEST_REPORT_P7.md`.
>
> 🚀 Shortcut: `tools/strategy-tester/run_tests.sh [filter...]` — works from Windows Git Bash.
> One-time setup: copy `.env.local.example` → `.env.local` (your MT5 data folder path) and
> `configs/common.local.ini.example` → `configs/common.local.ini` (your demo login), both
> gitignored. See its README. Pass a filename substring to run a subset, e.g.
> `./run_tests.sh hydra_05`.

## Phase 7 — CLOSED (2026-07-15)

Both required automated tests passed. Full evidence in `docs/TEST_REPORT_P7.md`; summary:

- **Run 05 (3-month campaign, `2026.04.01`–`2026.07.10`, full production defaults):** 484
  grid deployments, every one a full 9+9 grid, every one eventually filled, every one
  resolved to a basket exit (33 TP / 288 SL / 163 trail-floor-hit), every exit followed by
  the 60 s cooldown, zero journal errors, clean single init and clean deinit at the range
  boundary.
- **Run 06 (spread stress, `2026.06.01`–`2026.07.10`, `MaxSpreadPoints=1`):** zero orders
  for the entire ~6-week window — every one of 62 deployment attempts blocked cleanly by
  gate 3 against real historical spread (29–30 pts), zero errors. (Note: the original
  approach — MT5's tester-level `[Tester] Spread=` override — was found to be a no-op on
  this build and had to be replaced with the `MaxSpreadPoints` approach; see the test
  report for detail.)

**Explicitly deferred by user decision (2026-07-15), tracked, not forgotten:**
- [ ] Restart mid-`ACTIVE` — needs a live/demo chart restart, not a backtest.
- [ ] Whipsaw guard reconfirmed specifically on the v2.0 binary (last run on v1.9; Phase 6
      didn't touch whipsaw code, so low risk, but not formally re-verified).
- [ ] Stops-level rejection at deploy → clean abort — current defaults never naturally
      trigger this path; would need a dedicated too-tight-`GridSpacingUSD` preset (run 07)
      to force it.
- [ ] Foreign-orders-untouched check — not independently exercised in backtests (they start
      clean by construction); more relevant to the live/demo pre-deploy checklist.
- [ ] Pull the net-profit/profit-factor summary from the `.htm` reports into
      `docs/TEST_REPORT_P7.md`.

Revisit these before the pre-live demo soak (see `docs/CHECKLIST.md` Final Pre-Deploy
section) — none of them block moving on to Phase 8 now.

## Phase 8 — Dashboard Panel: code written, awaiting your visual check

Implemented per CLAUDE.md §10.1: collapsible read-only chart panel, header sources
`HYDRA_VERSION` (no hardcoding), expanded by default, click-to-collapse, dark panel with
per-state accent color (gray IDLE / blue ARMED / green ACTIVE-profit / red ACTIVE-drawdown /
orange COOLDOWN), and all ten §10.1 rows (state, auto-trading, 5 gate dots + failing-gate
name, session + server time, spread/ATR, grid status, basket P/L, targets, whipsaw counter +
cooldown countdown, TTL countdown). No trade buttons anywhere. **`HYDRA_VERSION` stays v2.0
for now** — per the same pattern as Phase 6, it only bumps once you've confirmed this
actually works (not preemptively at code-write time).

### 1. Recompile

`git pull`, open MetaEditor, compile `Straddle_Grid.mq5` → must be **0 errors / 0 warnings**.
The two Unicode symbol characters used in the panel (▲▼●) are embedded directly as UTF-8 in
the source; if MetaEditor's compiler complains specifically about those, tell me and I'll
swap them for plain-ASCII fallbacks.

### 2. Visual check — two ways to see it

**Fastest way to see every state (recommended, one command):**

```bash
cd /d/Straddle_Grid/tools/strategy-tester
./run_tests.sh hydra_dash_visual
```

This opens the interactive Tester chart (`Visual=1`) on the same 4-day window already known
to cycle the EA through every state — IDLE → ARMED → ACTIVE (both a TP win and an SL loss) →
COOLDOWN, several times — so you can eyeball every accent color and row in one sitting
without touching the Strategy Tester GUI settings by hand. `ShutdownTerminal=0` so the
window stays open; use the speed slider to run it faster, or Pause to freeze a frame and
take a screenshot. Close the window when you're done watching — the script will then finish.

**Or:** attach the EA to a live/demo XAUUSD-VIP M1 chart with `AUTO_TRADING_ENABLED=false`
(safe — places nothing) — you'll only ever see gray IDLE, but it's a quick sanity check that
the panel renders, updates the session/spread/ATR/gate rows in real time, and the click
collapse/expand works.

### 3. What to check off

Most of the old 12-item checklist is now automatic — every `run_tests.sh` run ends with a
`Dashboard self-test: PASS/FAIL` line covering header text, all 5 accent colors, gate dots,
every row's content, and leftover-object cleanup. Run the headless state-cycling config and
confirm it reports PASS:

```bash
cd tools/strategy-tester
./run_tests.sh hydra_02_deploy_fills
```

Only 3 items still need a screen (see `docs/CHECKLIST.md` §Phase 8) — use the existing Visual
mode command for these:

- [ ] Header click actually collapses/expands the panel.
- [ ] Panel doesn't overlap the chart's native OHLC/price label.
- [ ] General "does it look right" pass.

Report back what you see (screenshots help a lot here, this is a visual feature) — once it
passes, I'll bump to v2.1 and commit `Phase 8 complete`.

## Upcoming (for awareness)

| When | Task |
|---|---|
| Now | Phase 8 visual verification (above) |
| Before pre-live | Close the five deferred Phase 7 items (see above) |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` (final checklist in `docs/CHECKLIST.md`) |
