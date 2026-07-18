# PENDING_USER_ACTIONS.md — Your Test Queue

> Everything currently waiting on you (the user).
> Current build: `Straddle_Grid.mq5` **v2.2** — **Phases 1–8 all complete + FOMC-Only
> Mode (CLAUDE.md §5.1).**
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

## ⚠ THE one open problem before live: negative campaign P/L — best lead found, but backward-looking testing is now exhausted

Run 05 baseline: **−$1,770 on $10k (−17.7%), PF 0.95, eqDD 36.6%** at production defaults.
Five independent real-tick attacks so far (full detail in `docs/OPT_REPORT.md`):

- **Exit sweep** (625 OHLC combos, top 2 re-validated on real ticks): **REJECTED**.
- **Entry-side sweep** (9 combos, session windows × spacing): **every combo lost money.**
- **NFP-day pilot** (n=4): looked mixed — small-sample illusion, see next line.
- **Multi-year NFP+FOMC probe** (n=37): NFP reversed to 36% win rate, **rejected**. FOMC
  near-breakeven but fragile to one outlier day.
- **FOMC-only exit sweep** (16 exit combos × 15 real FOMC days, real ticks throughout):
  **best result of the whole campaign** — `BasketTP_USD=20, BasketSL_USD=10`: **+$880
  over 15 days, combined PF 1.256**, sitting inside a coherent positive neighborhood
  (`TP∈{20,25}×SL∈{8,10}`, 4 adjacent winners), not an isolated fluke like Sweep 01's
  winner was.

**Why this still isn't a green light:** every FOMC day this account's history contains
was already used to find this combination — there's no held-out data left to confirm it
against. The only real test remaining is **prospective**, and that's now running.

## ✅ FOMC-Only Mode built and forward-tracking is live (2026-07-19)

Built the calendar-aware gate (`FOMCOnlyMode`, `FOMCDatesCSV`, `FOMCWindowDays` —
CLAUDE.md §5.1), additive-only (zero effect when off), verified end-to-end on a
headless test: correctly blocks outside the FOMC window, falls through to normal
session gating inside it, deployed/filled/exited cleanly, no errors. `HYDRA_VERSION`
bumped to **v2.2**.

Real 2026 FOMC decision dates verified against federalreserve.gov: **Jan 28, Mar 18,
Apr 29, Jun 17, Jul 29, Sep 16, Oct 28, Dec 9**. The remaining four are ahead of us —
**next one: July 29, ten days out.**

Given how heavily contended the shared terminal has been all session (multiple
sibling-project collisions, one genuinely stuck process), the EA is **not** attached
continuously through December — that would block sibling test runs for 5 months. Instead
`tools/fomc-live/` holds **8 Windows Scheduled Tasks** (`Hydra_FOMC_Attach_<date>` /
`Hydra_FOMC_Detach_<date>`) that attach the EA (demo, `AUTO_TRADING_ENABLED=true`,
`BasketTP_USD=20`/`BasketSL_USD=10`) ~1 day before each remaining FOMC date and detach
~1 day after — verified registered and `Ready` with correct next-run times. Everything
logs to `tools/fomc-live/tracking.log`.

**What's actually needed from you:**
- Nothing right now — the next task fires automatically 2026-07-28 06:00 local.
- If you change `Straddle_Grid.mq5` before then, **recompile the data-folder copy
  manually** — the scheduled tasks don't recompile.
- Worth a glance at `tools/fomc-live/tracking.log` after July 28 to confirm the attach
  actually succeeded (unattended launches can fail silently if the terminal is stuck).
- CLAUDE.md §5.1's forward-tracking table gets filled in as each date resolves.

## Upcoming

| When | Task |
|---|---|
| 2026-07-28 06:00 | Scheduled: attach for the Jul 29 FOMC meeting |
| 2026-07-30 06:00 | Scheduled: detach, log the outcome |
| Ongoing | Repeat for Sep 16 / Oct 28 / Dec 9 automatically |
| Optional, next time at a screen | One physical header click on the dashboard |
| Pre-live | 1-week demo soak — blocked until forward-tracking confirms a real edge |
