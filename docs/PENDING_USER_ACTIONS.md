# PENDING_USER_ACTIONS.md — Your Test Queue

> Everything currently waiting on you (the user).
> Current build: `Straddle_Grid.mq5` **v2.1** — **Phases 1–8 all complete.**
>
> ✅ **Validated** (full detail in `docs/TEST_REPORT_P7.md` + `docs/CHECKLIST.md`):
> compile clean · all 5 gates + short-circuit · grid deploy 9+9 · OCO · sequential fills ·
> TTL expiry · whipsaw guard (re-confirmed on the shipping binary) · Basket Manager
> (scaling exact, trailing monotonic, post-exit cooldown) · 3-month campaign (484 clean
> cycles) · spread stress (62/62 blocked) · stops-level rejection (19,868 clean pre-send
> aborts, zero orders) · **restart mid-`ACTIVE` on a live demo chart** (hard-kill with 2
> positions + 7 pendings → recovered, zero duplicates) · **foreign orders untouched**
> (verified through a full live cycle incl. crash) · dashboard fully verified (read-back
> guard + 27-check synthetic battery + live-chart pixel review; the empty-gates-row
> "Label" artifact found in review is fixed in v2.1).
>
> The only dashboard check no code can make: one physical mouse click on the header
> (MT5's own pixel hit-testing). Entirely optional — try it whenever you're next at a
> chart; the click handler itself is proven.

## ⚠ THE one open problem before live: negative campaign P/L — two full sweeps done, both negative

Run 05 baseline: **−$1,770 on $10k (−17.7%), PF 0.95, eqDD 36.6%** at production defaults.
Two independent real-tick attacks (full detail in `docs/OPT_REPORT.md`):

- **Exit sweep** (625 OHLC combos, top 2 re-validated on real ticks): **REJECTED** — both
  collapse to PF 0.84, ~70% drawdown. The OHLC "winners" were a model artifact.
- **Entry-side sweep** (9 combos, session windows × `GridSpacingUSD`, **real ticks from
  the start**, 2026-07-18): **every single combination lost money.** Narrowing the
  session window made results *worse*, not better — evidence the loss isn't concentrated
  in a chop-heavy sub-window, it's present throughout.

**Conclusion: this isn't a tuning-knob problem anymore.** Eighteen real-tick-valid
configurations across both exits and entries, zero profitable. Your direction is needed
(see `docs/OPT_REPORT.md` §Recommended next steps) — most likely a genuine
**strategy-concept rethink**: gate deployment on scheduled news events instead of blanket
session windows (the original CLAUDE.md §2 displacement thesis), which is a fundamentally
different trigger than anything tested so far. Live deployment and the demo soak stay
**blocked** until something beats "don't trade" on real ticks.

## Upcoming

| When | Task |
|---|---|
| Now | Decide: news-calendar-gated rework, explore remaining knobs (lot progression/GridLevels/ATR band), or pause |
| Optional, next time at a screen | One physical header click on the dashboard |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` — blocked on the P/L fix |
