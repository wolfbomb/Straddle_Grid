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

## ⚠ THE one open problem before live: negative campaign P/L — 3 probes done, one shows a hint worth chasing

Run 05 baseline: **−$1,770 on $10k (−17.7%), PF 0.95, eqDD 36.6%** at production defaults.
Three independent real-tick attacks so far (full detail in `docs/OPT_REPORT.md`):

- **Exit sweep** (625 OHLC combos, top 2 re-validated on real ticks): **REJECTED** — both
  collapse to PF 0.84, ~70% drawdown. The OHLC "winners" were a model artifact.
- **Entry-side sweep** (9 combos, session windows × `GridSpacingUSD`, real ticks
  throughout, 2026-07-18): **every single combination lost money.** Narrowing the
  session window made results *worse*, not better.
- **NFP-day probe** (n=4, real ticks, 2026-07-18): **mixed** — 2 of 4 individual NFP days
  were genuinely profitable (PF 1.41, 1.16), a hit rate neither of the systematic sweeps
  ever produced. Aggregate is still net negative (−$528) and n=4 is far too small to
  trust either way — **inconclusive, not a finding.**

**Conclusion: 18 systematic configurations on the always-on trigger were uniformly
negative — that avenue looks exhausted.** The NFP probe hints the displacement thesis
might still have something to it, but needs a much bigger sample (2–3 years of NFP/FOMC
dates, not 4) before it's trustworthy either way. See `docs/OPT_REPORT.md`
§Recommended next steps for the full decision tree. Live deployment and the demo soak
stay **blocked** until something beats "don't trade" with real statistical confidence.

## Upcoming

| When | Task |
|---|---|
| Now | Decide: extend the NFP/FOMC probe to a multi-year sample (cheap, no code change) before committing to anything bigger |
| If that holds up | Build the news-calendar-gated rework (new gate, its own validation campaign) |
| If it doesn't | Reconsider whether this EA concept has edge here at all |
| Optional, next time at a screen | One physical header click on the dashboard |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` — blocked on the P/L fix |
