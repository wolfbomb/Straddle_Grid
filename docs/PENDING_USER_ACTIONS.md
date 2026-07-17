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

## ⚠ THE one open problem before live: negative campaign P/L — exit sweep DONE, answer is "not exits"

Run 05 baseline: **−$1,770 on $10k (−17.7%), PF 0.95, eqDD 36.6%** at production defaults.
The automated attack ran 2026-07-17 (full detail in `docs/OPT_REPORT.md`):

- **625-combination exit sweep** (TP/SL/trail, 3-month window): only 18/625 profitable,
  all at the tightest exits tested (TP10/SL6).
- **Real-tick validation of the two winners: REJECTED** — both collapse to PF 0.84,
  −$5.5k, ~70% drawdown. The OHLC model's profitable island was an artifact; tight
  dollar-stops live inside intrabar noise.

**Conclusion: exit tuning cannot fix this edge; the loss source is entry-side.** Your
direction is needed (see OPT_REPORT §Recommended next steps): a real-tick session/spacing
exploration, or a strategy-concept rethink (e.g. news-window-only deployment per the
original displacement thesis). Live deployment and the demo soak stay **blocked** until
something beats "don't trade" on real ticks.

## Upcoming

| When | Task |
|---|---|
| When opt results are in | Review sweep summary, pick candidates for real-tick re-validation |
| Optional, next time at a screen | One physical header click on the dashboard |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` — blocked on the P/L fix |
