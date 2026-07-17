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

## ⚠ THE one open problem before live: negative campaign P/L

Run 05 (3 months, production defaults): **−$1,770 on $10k (−17.7%), PF 0.95, max equity
DD 36.6%**. Mechanics are proven; the edge isn't. An automated parameter sweep over the
basket-exit space (TP/SL/trail — 625 combinations, same 3-month window) has been
prepared/launched via `tools/strategy-tester/run_opt.sh hydra_opt_01_exits`; results land
in `docs/OPT_REPORT.md` when summarized. Sweep passes run on M1-OHLC for speed — any
promising candidate must be re-validated on real ticks (Model=4) before trusting it.

**Your decision when results are in:** pick a re-validated parameter set, or direct a
deeper strategy rework (sessions, spacing/progression, entry filter). Nothing goes live
until this is resolved — the 1-week demo soak (`docs/CHECKLIST.md` §Final Pre-Deploy)
stays blocked on it.

## Upcoming

| When | Task |
|---|---|
| When opt results are in | Review sweep summary, pick candidates for real-tick re-validation |
| Optional, next time at a screen | One physical header click on the dashboard |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` — blocked on the P/L fix |
