# PENDING_USER_ACTIONS.md — Your Test Queue

> Everything currently waiting on you (the user, at your MT5 PC/Mac).
> Current build: `Straddle_Grid.mq5` **v2.0** (Phases 1–6 complete + Phase 8 dashboard code).
> Phase 7 (validation campaign) closed 2026-07-15; its five deferred items were reduced to
> two on 2026-07-17 (see below).
>
> ✅ **Validated so far** (tester, real ticks, VTMarkets-Demo): compile clean · gates +
> short-circuit · grid deploy 9+9 with correct prices/lots · OCO cancel · sequential fills ·
> TTL expiry/redeploy (no partial grids) · whipsaw guard — **re-confirmed on the current
> v2.0 binary 2026-07-17** (4 firings, correct gap math/cooldowns, 2/2 daily lockout) ·
> Basket Manager: TP/SL scaling exact, trailing floor monotonic-only, 60 s post-exit
> cooldown · 3-month campaign (484 full cycles, zero partial grids/orphans/errors) ·
> spread stress (62/62 blocked by gate 3) · **stops-level rejection (NEW run 07,
> 2026-07-17):** 19,868 clean pre-send aborts, zero orders, zero broker errors ·
> **dashboard self-test PASS** (read-back guard, 0 DASH-FAIL across hydra_02/04/07 —
> verified UTF-16-aware after fixing an encoding blind spot in the scan itself).
> Full detail in `docs/TEST_REPORT_P7.md`.
>
> 🚀 Shortcut: `tools/strategy-tester/run_tests.sh [filter...]` — works from Windows Git Bash.

## ⚠ NEW FINDING you should read (2026-07-17): campaign P/L is negative

The deferred "pull P/L from the .htm reports" item is done, and it surfaced something the
mechanical pass criteria didn't: **the 3-month campaign lost money at production defaults**
— net **−$1,770.44** on $10,000 (−17.7%), profit factor 0.95, max equity drawdown 36.6%
(3,290 trades; 51% winners; exit mix 7% TP / 59% SL / 34% trail-floor). The code is doing
exactly what it was told; what it was told isn't (yet) an edge on this window. This needs a
parameter/strategy pass (session tightening, exit tuning, spacing/progression rework +
re-test) **before any live deployment**. Full table in `docs/TEST_REPORT_P7.md` §Run 05.

## Phase 8 — Dashboard: automated checks all PASS, only the 4 eyes-on items left

Done without you (2026-07-17): latest source synced to the MT5 data folder, recompiled
headlessly (**0 errors / 0 warnings**), and the automated dashboard self-test ran through
hydra_02 + hydra_04 + hydra_07 with **0 [DASH-FAIL] lines**. (Also fixed: the PASS/FAIL
scan in `run_tests.sh` couldn't decode MT5's UTF-16 tester logs and could have printed a
false PASS — it now decodes properly and reports INCONCLUSIVE if it can't.)

Still needs a human at a screen (`./run_tests.sh hydra_dash_visual`, or attach to a demo
chart with `AUTO_TRADING_ENABLED=false`):

- [ ] Header click actually collapses/expands the panel.
- [ ] Switch timeframe (M1→M5→M1) → panel still there, collapse state preserved.
- [ ] Panel doesn't overlap the chart's native OHLC/price label.
- [ ] General "does it look right" pass.

Report back what you see (screenshots help) — once it passes, v2.0 → v2.1 and
`Phase 8 complete` gets committed.

## Remaining deferred items (down from five)

- [ ] **Restart mid-`ACTIVE`** — needs a live/demo chart restart, not a backtest.
- [ ] **Foreign-orders-untouched check** — belongs to the live/demo pre-deploy checklist.
- [x] ~~Whipsaw guard re-run on v2.0~~ — done 2026-07-17 (run 04 re-run).
- [x] ~~Stops-level rejection forced test~~ — done 2026-07-17 (run 07, new permanent scenario).
- [x] ~~P/L summary from .htm reports~~ — done 2026-07-17 (and flagged the profitability problem above).

## Upcoming (for awareness)

| When | Task |
|---|---|
| Now | Phase 8 visual verification (4 items above) |
| Now-ish | Decide how to attack the negative-P/L finding (parameter pass vs strategy rework) |
| Before pre-live | Restart mid-ACTIVE + foreign-orders checks |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` (final checklist in `docs/CHECKLIST.md`) — **blocked on the P/L finding being resolved** |
