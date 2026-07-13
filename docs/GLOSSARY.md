# GLOSSARY.md — Hydra Terms in Plain English

> Every technical term used in this project, explained for someone new to trading.
> No jargon in the explanations — where a term needs another term, that one is in here too.

---

## 1. Basic Trading Terms

| Term | Plain-English Meaning |
|---|---|
| **Lot** | The order size unit. For gold (XAUUSD), 1.0 lot = 100 ounces. Hydra trades micro sizes like 0.01 lot (= 1 ounce). With 0.01 lot, every $1 the gold price moves changes your profit/loss by about $1. |
| **Bid / Ask** | The two prices you always see. **Bid** = what buyers pay right now (you *sell* at this). **Ask** = what sellers want (you *buy* at this). The ask is always slightly higher. |
| **Spread** | The gap between bid and ask. It's the broker's built-in fee — the moment you open a trade you are "down by the spread." Wide spread = expensive to trade. Hydra refuses to trade when the spread is too wide (Gate 3). |
| **Point** | The smallest price step the platform counts. For gold quoted like 3341.52, one point = 0.01 (one cent). "35 points max spread" = 35 cents. |
| **Position** | A trade you currently have open. A **long** position profits when price rises; a **short** position profits when price falls. |
| **Pending order** | An instruction that sits at the broker waiting: "if price reaches X, open a trade for me." Nothing is bought or sold until price actually touches X. |
| **Stop order (Buy Stop / Sell Stop)** | A type of pending order placed *beyond* the current price. A **Buy Stop** above price says "if it breaks up to here, buy — it's probably going higher." A **Sell Stop** below says "if it breaks down to here, sell." These are Hydra's building blocks. |
| **Fill** | The moment a pending order actually triggers and becomes a real position. "3/9 fills" = 3 of the 9 orders on that side have triggered. |
| **Stop Loss (SL)** | A safety price where a losing trade closes automatically, capping the damage. |
| **Take Profit (TP)** | A target price where a winning trade closes automatically, banking the gain. |
| **P/L (Profit/Loss)** | How much you're up or down. **Floating** P/L = on trades still open (can still change). **Realized** P/L = on trades already closed (final). |
| **Drawdown** | How far your account has sunk below its high point. A measure of pain, not just loss. |
| **Equity vs Balance** | **Balance** = your money counting only closed trades. **Equity** = balance plus/minus the floating P/L of open trades. Equity is the "if I closed everything right now" number. |
| **Margin / Margin level** | **Margin** is the deposit the broker locks up while you have positions open. **Margin level %** = equity ÷ margin. High = safe. Low = close to the broker force-closing your trades ("margin call"). Hydra requires 500%+ before trading (Gate 4). |
| **Leverage** | Borrowed buying power. It multiplies both profits *and* losses — the reason small accounts can blow up fast. |
| **Slippage** | Getting filled at a slightly different price than requested, common during fast news moves. |
| **Hedging account** | An account type (which we use) where you can hold a long *and* a short on the same symbol at the same time. The opposite ("netting") merges them into one. |

## 2. Market & Strategy Terms

| Term | Plain-English Meaning |
|---|---|
| **XAUUSD** | The gold price in US dollars. "XAU" is gold's currency code. Our symbol is `XAUUSD-VIP` (VT Markets' version of it). |
| **Timeframe (M1 / M5)** | How much time each candle on the chart represents. M1 = 1 minute, M5 = 5 minutes. Hydra acts on M1 and reads market conditions from M5. |
| **Breakout** | Price escaping a quiet range with force. Hydra's whole bet is catching breakouts. |
| **Straddle** | Placing orders on *both* sides of the current price — buy orders above, sell orders below — because you expect a big move but don't know which direction. Whichever way it breaks, you're on board. |
| **Grid** | A ladder of orders at evenly spaced prices (e.g. every $0.70). Hydra uses two ladders: 9 buy stops going up, 9 sell stops going down. |
| **Anchor** | The price at the middle of the grid at the moment it's placed — the current price when Hydra deploys. |
| **Pyramiding** | Adding *bigger* positions as the move goes your way (Hydra's lots go 0.01 → 0.05 up the ladder). Powerful in a real breakout, dangerous in a fake one — which is why the Whipsaw Guard exists. |
| **Martingale** | Doubling your bet after losses hoping to win it back — a famous way to destroy accounts. Hydra explicitly bans anything like it (Hard Rule §12). Pyramiding into a *winning* move is not martingale. |
| **Whipsaw / Chop** | Price snapping violently up AND down with no real direction (a "sideways chop" market). For a straddle grid it's the nightmare scenario: both sides trigger and both lose. See Whipsaw Guard below. |
| **Session / Killzone** | The hours when a market is most active. **London open** and **New York open** are gold's high-energy windows — the times a breakout is most likely to be real. Hydra only trades inside these windows (Gate 1). |
| **ATR (Average True Range)** | A number that answers "how much does price *typically* move per candle lately?" It's Hydra's volatility thermometer: too low = market asleep (fake breakouts likely), too high = the explosion already happened (too late). Gate 2 requires ATR in a healthy middle band. |
| **Liquidity run / Displacement** | Trader-speak for a fast, forceful push through a price area (often around news or session opens) — the $15–30 gold moves Hydra is built to catch. |
| **NFP / FOMC** | The two most violent scheduled news events for gold. **NFP** = US jobs report (monthly). **FOMC** = US central-bank interest-rate announcement. Backtests must include at least one of each because they produce the wildest candles. |
| **Backtest** | Replaying the EA against historical price data in the Strategy Tester to see how it *would have* behaved. "Real ticks" mode replays the genuine price feed, the most honest simulation available. |

## 3. Hydra-Specific Machinery

| Term | Plain-English Meaning |
|---|---|
| **EA (Expert Advisor)** | A robot program that runs inside the MetaTrader 5 platform and trades by itself. Hydra is an EA written in the MQL5 language. |
| **State machine (IDLE / ARMED / ACTIVE / COOLDOWN)** | Hydra is always in exactly one "mode": **IDLE** = watching, no orders. **ARMED** = grid placed, waiting for a touch. **ACTIVE** = at least one fill, riding the move. **COOLDOWN** = timeout after an exit or a whipsaw; deliberately doing nothing. |
| **Safety gates** | Five checks that ALL must pass before a grid is placed: right time of day, healthy volatility, acceptable spread, account safe, and the master switch on. One failure = no trade. |
| **Master switch (`AUTO_TRADING_ENABLED`)** | The main safety: an input that ships as `false`. Until you personally flip it to `true` (and enable the platform's AutoTrading button), Hydra can never place a real order. |
| **Direction lock** | The first fill decides the trade's direction. From then on Hydra only rides that side for the rest of the cycle. |
| **OCO ("One Cancels the Other")** | The instant one side of the straddle triggers, all orders on the *opposite* side are deleted — so a later reversal can't drag you into a two-sided mess. On by default. |
| **TTL ("Time To Live")** | The pending grid's shelf life (45 min default). No fills in that time = the setup went stale, delete everything, go back to watching. |
| **Whipsaw Guard** | The emergency kill switch. If a buy AND a sell both fill within 5 minutes (the whipsaw signature), Hydra instantly closes everything, deletes all orders, and locks itself out for an hour. Two whipsaws in a day = done until tomorrow. The single most important safety in the EA. |
| **Basket** | All of Hydra's open positions treated as ONE trade. Profit targets and stops apply to the basket's *combined* P/L, not to individual positions. |
| **Basket TP / Basket SL** | Close-everything targets for the combined P/L: take profit at +$15, cut losses at −$10 (both scaled by how much volume actually filled). |
| **Trailing (trail floor)** | Once the basket is nicely in profit (+$8), a "floor" starts following the profit upward, staying $4 behind its best level. Profit retreats to the floor → everything closes. Lets winners run while protecting most of the gain. The floor only ever moves up, never down. |
| **Cooldown** | A deliberate self-imposed timeout. After any basket exit (and especially after a whipsaw), Hydra refuses to trade for a while — re-entering the same conditions immediately is how robots bleed. |
| **Magic number** | An ID (20260713) stamped invisibly on every order Hydra creates, so it can tell its own trades apart from yours or another robot's. Hydra never touches anything without its magic number. |
| **State recovery** | If the platform restarts mid-trade, Hydra re-reads its own orders/positions on startup and figures out what state it was in. It never assumes a blank slate. |
| **Global variable (terminal)** | A tiny value MetaTrader stores on disk that survives restarts. Hydra uses these to remember the whipsaw count and cooldown timer even through a crash. |

## 4. Platform / Broker Plumbing

| Term | Plain-English Meaning |
|---|---|
| **MQL5 / MetaEditor** | MQL5 is the programming language for MT5 robots; MetaEditor is the editor/compiler that turns our `.mq5` source file into a runnable `.ex5` program. |
| **Strategy Tester** | MT5's built-in backtesting simulator. Our checklists run in it before anything touches a live chart. |
| **Compile warning/error** | The compiler complaining about the code. Errors = won't build at all. Warnings = builds but something smells. SIGMA rule: we ship only at **zero** of both. |
| **Tick** | One single price update from the broker. Prices move tick by tick; `OnTick` is the EA function that runs on every one. |
| **Tick size / Tick value** | The smallest price increment the broker allows and how much money one increment is worth per lot. Hydra snaps all its order prices to the tick size so the broker can't reject them. |
| **Stops level** | A broker rule: "pending orders must be at least this many points away from the current price." Orders placed closer get rejected — that's why Hydra validates every grid level against it before sending anything. |
| **Freeze level** | A broker rule: orders too close to the current price are temporarily "frozen" and can't be modified/deleted. Hydra respects it during placement. |
| **IOC ("Immediate Or Cancel")** | An order-filling rule: execute what you can right now, cancel the rest. Prevents orders lingering half-executed. SIGMA convention for all orders. |
| **GTC ("Good Till Cancelled")** | A pending order that stays alive until deleted — used as fallback when the broker doesn't support server-side expiry times. |
| **Retcode** | The broker's numeric answer to any order request ("done", "rejected — market closed", "invalid price"…). Hydra logs the retcode whenever something fails. |
| **Journal / Experts log** | MT5's diary tabs. Everything important Hydra does is written there with a `[HYDRA]` prefix — the first place to look when checking behavior. |
| **Demo account / Demo soak** | A practice account with fake money but real prices. The "soak" is our rule: Hydra must run a full week on demo before it ever touches real funds. |

---

*Related docs: `CLAUDE.md` (full spec) · `PHASE_PROMPTS.md` (build plan) · `docs/CHECKLIST.md` (tests) · `docs/PENDING_USER_ACTIONS.md` (your current test queue).*
