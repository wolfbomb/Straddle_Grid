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

## Next: Phase 8 — Dashboard Panel

Per CLAUDE.md §10.1: a collapsible, read-only chart panel — header `SIGMA Hydra v2.0`
(sourced from `HYDRA_VERSION`, never hardcoded twice), expanded by default, click-to-collapse
persisted across timeframe switches, dark translucent styling with per-state accent color
(gray IDLE / blue ARMED / green ACTIVE-profit / red ACTIVE-drawdown / orange COOLDOWN), and
the rows specified in §10.1 (state, auto-trading, 5 gate dots, session/spread/ATR, grid
status, basket P/L, targets, whipsaw counter, TTL countdown). No trade buttons — the only
master switch stays the `AUTO_TRADING_ENABLED` input + terminal button.

This is a code phase (implementation, then a compile + visual check on a live chart), not a
tester-run phase — I'll build it next and let you know what to eyeball once it compiles
clean.

## Upcoming (for awareness)

| When | Task |
|---|---|
| Phase 8 | Dashboard panel implementation, then visual checks on a live/demo chart (collapse, colors, rows, timeframe-switch persistence) |
| Before pre-live | Close the five deferred Phase 7 items above |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` (final checklist in `docs/CHECKLIST.md`) |
