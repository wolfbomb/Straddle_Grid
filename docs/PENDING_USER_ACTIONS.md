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

## ⚠ THE one open problem before live: negative campaign P/L — 4 real-tick attacks done, no validated edge

Run 05 baseline: **−$1,770 on $10k (−17.7%), PF 0.95, eqDD 36.6%** at production defaults.
Four independent real-tick attacks so far (full detail in `docs/OPT_REPORT.md`):

- **Exit sweep** (625 OHLC combos, top 2 re-validated on real ticks): **REJECTED** — both
  collapse to PF 0.84, ~70% drawdown. The OHLC "winners" were a model artifact.
- **Entry-side sweep** (9 combos, session windows × `GridSpacingUSD`): **every single
  combination lost money.**
- **NFP-day pilot** (n=4): looked mixed (2/4 profitable) — but this was a small-sample
  illusion (see next line).
- **Multi-year NFP+FOMC probe** (n=37, 2024.03–2025.12, the full real-tick history this
  account has): **NFP reversed to 36% win rate, −$1,752 total — rejected.** **FOMC is
  near-breakeven** (53% win rate, mean −$3/day) but that flips positive or negative
  depending on whether you keep a single outlier day — **fragile, not a validated edge.**

**Conclusion: no configuration or trigger tested across any of these four attacks has a
validated profitable edge.** FOMC-only deployment is the one thread left with any signal,
but it needs a narrow, skeptical follow-up (exit-tuning restricted to FOMC days only),
not blind confidence — the NFP result flipping between n=4 and n=22 is a live lesson in
why. See `docs/OPT_REPORT.md` §Recommended next steps for the decision tree. Live
deployment and the demo soak stay **blocked**.

## Upcoming

| When | Task |
|---|---|
| Now | Decide: one more narrow test (exit-tune on FOMC days only), or stop the search and reconsider the strategy itself |
| Optional, next time at a screen | One physical header click on the dashboard |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` — blocked on the P/L fix |
