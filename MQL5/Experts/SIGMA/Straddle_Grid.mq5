//+------------------------------------------------------------------+
//|                                                Straddle_Grid.mq5 |
//|                              SIGMA Suite — Hydra                 |
//|                 https://github.com/wolfbomb/Straddle_Grid        |
//+------------------------------------------------------------------+
//| Bidirectional stop-order grid (straddle) with pyramiding lot     |
//| progression. Spec: CLAUDE.md (repo root). Build plan:            |
//| PHASE_PROMPTS.md. Tests: docs/CHECKLIST.md.                      |
//|                                                                  |
//| Phase 5 — Whipsaw Guard (on Phases 1–4).                         |
//| Places orders ONLY when all five gates pass, which requires      |
//| AUTO_TRADING_ENABLED=true (default false).                       |
//|                                                                  |
//| Section order (SIGMA convention, CLAUDE.md §9):                  |
//|   Inputs → Globals/State → OnInit (state recovery) →             |
//|   OnTick (state dispatch) → Gates → GridDeploy → WhipsawGuard →  |
//|   BasketManager → Dashboard → Utils                              |
//+------------------------------------------------------------------+
#property copyright "SIGMA"
#property link      "https://github.com/wolfbomb/Straddle_Grid"

//+------------------------------------------------------------------+
//| ======================== INPUTS ================================ |
//| Canonical names per CLAUDE.md §8 — do not rename.                |
//+------------------------------------------------------------------+
input group "── Master ──"
input bool    AUTO_TRADING_ENABLED = false;    // SIGMA rule: defaults false, never flip in code
input long    MagicNumber          = 20260713;

input group "── Grid ──"
input int     GridLevels           = 9;        // per side
input double  GridSpacingUSD       = 0.70;     // $ between levels (VT XAUUSD-VIP: stops 20 + max spread 35 + buffer 10 pts)
input double  FirstLevelOffsetUSD  = 0.50;     // $ from anchor to level 1
input string  LotProgressionCSV    = "0.01,0.01,0.02,0.02,0.02,0.03,0.04,0.04,0.05";
input bool    OCO_Mode             = true;
input int     GridTTLMin           = 45;

input group "── Basket Exit ──"
input double  BasketTP_USD         = 15.0;
input double  BasketSL_USD         = 10.0;
input double  TrailActivate_USD    = 8.0;
input double  TrailDistance_USD    = 4.0;

input group "── Gates ──"
input string  Session1             = "07:00-10:00";  // GMT
input string  Session2             = "12:00-15:00";
input double  ATR_Min_USD          = 1.5;
input double  ATR_Max_USD          = 8.0;
input int     MaxSpreadPoints      = 35;
input double  MinMarginLevelPct    = 500.0;
input double  MaxDailyLossPct     = 3.0;

input group "── Whipsaw Guard ──"
input int     WhipsawWindowSec     = 300;
input int     WhipsawCooldownMin   = 60;
input int     MaxWhipsawsPerDay    = 2;

//+------------------------------------------------------------------+
//| ===================== GLOBALS / STATE =========================== |
//+------------------------------------------------------------------+
#define HYDRA_VERSION        "v1.7"          // single source of truth — dashboard header reads this
#define HYDRA_COMMENT_PREFIX "SIGMA.Hydra"   // order comment prefix (SIGMA convention)

// Persistent global-variable keys (namespaced SIGMA.Hydra.<symbol>.<key>,
// built by GVKey()). Survive terminal restart.
#define GV_WHIPSAW_COUNT   "whipsaw_count"   // whipsaws fired today
#define GV_WHIPSAW_DAY     "whipsaw_day"     // server day-stamp the counter belongs to
#define GV_COOLDOWN_UNTIL  "cooldown_until"  // epoch time cooldown ends
#define GV_DAY_STAMP       "day_stamp"       // server day the daily anchors belong to
#define GV_DAY_BALANCE     "day_balance"     // balance snapshot at server-day start (gate 4)

enum EHydraState
  {
   STATE_IDLE     = 0,  // no grid, no positions; evaluating gates (throttled 1x/sec)
   STATE_ARMED    = 1,  // full pending grid placed, zero fills yet
   STATE_ACTIVE   = 2,  // >=1 fill, direction locked
   STATE_COOLDOWN = 3   // post-exit / post-whipsaw lockout, timer only
  };

EHydraState g_state        = STATE_IDLE;
double      g_lots[];                       // parsed LotProgressionCSV
datetime    g_lastGateEval = 0;             // 1 Hz throttle for IDLE gate checks

//--- Gates (CLAUDE.md §5): cached results for logging-on-change + dashboard (Phase 8)
#define GATE_COUNT             5
#define SPACING_BUFFER_POINTS  10           // safety buffer in gate-3 spacing validation
string g_gateNames[GATE_COUNT] = {"Session","Volatility","Spread","Exposure","MasterSwitch"};
bool   g_gatePass[GATE_COUNT];
bool   g_gateEvaluated[GATE_COUNT];         // false when short-circuited before this gate
string g_gateReason[GATE_COUNT];
string g_lastGateStatus = "";               // last logged composite status (log on change only)

int    g_atrHandle   = INVALID_HANDLE;      // ATR(14, M5) for gate 2
int    g_sess1Start = -1, g_sess1End = -1;  // session windows in minutes-of-day (GMT/server)
int    g_sess2Start = -1, g_sess2End = -1;
bool   g_sessionsValid = false;             // false = malformed input, gate 1 always fails

//--- Grid (CLAUDE.md §7)
datetime g_armedAt         = 0;             // deployment time = TTL anchor; recovered on restart
datetime g_lastArmedCheck  = 0;             // 1 Hz throttle for ARMED management
string   g_lastDeployAbort = "";            // last deploy-abort reason (log on change only)

//--- Direction lock & fill records (Phase 4; consumed by Whipsaw Guard in Phase 5)
int      g_lockedDir         = 0;           // 0 = none, +1 = buy side, -1 = sell side
int      g_fillCount         = 0;           // entry fills in the current grid cycle
datetime g_lastBuyFill       = 0;           // most recent buy-side entry fill time
datetime g_lastSellFill      = 0;           // most recent sell-side entry fill time
bool     g_ocoCleanupPending = false;       // opposite-side deletion outstanding (retried each tick)

//+------------------------------------------------------------------+
//| ================== ONINIT (STATE RECOVERY) ====================== |
//+------------------------------------------------------------------+
int OnInit()
  {
   HydraLog(StringFormat("SIGMA Hydra %s initializing on %s (magic %I64d)",
                         HYDRA_VERSION, _Symbol, MagicNumber));

   if(GridLevels <= 0)
     {
      HydraLog(StringFormat("INIT FAIL: GridLevels must be > 0 (got %d)", GridLevels));
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(!ParseLotProgression(LotProgressionCSV, g_lots))
      return(INIT_PARAMETERS_INCORRECT);     // reason already logged

   double total = 0.0;
   for(int i = 0; i < ArraySize(g_lots); i++)
      total += g_lots[i];
   HydraLog(StringFormat("lot progression OK: %d levels/side, %.2f lots/side if fully filled",
                         ArraySize(g_lots), total));

   // Contract context (informational in Phase 1; Phase 3 validates against it)
   HydraLog(StringFormat("symbol spec: minLot=%.2f lotStep=%.2f stopsLevel=%d pts, tickSize=%.5f tickValue=%.2f",
                         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
                         (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)));

   if(!AUTO_TRADING_ENABLED)
      HydraLog("AUTO_TRADING_ENABLED is false — EA will never place orders until enabled (gate 5)");

   // Gate 1: parse session windows once (malformed input -> gate fails, EA still runs)
   g_sessionsValid = ParseSessionWindow(Session1, g_sess1Start, g_sess1End) &&
                     ParseSessionWindow(Session2, g_sess2Start, g_sess2End);
   if(!g_sessionsValid)
      HydraLog(StringFormat("WARNING: malformed session window ('%s' / '%s') — gate 1 will always fail", Session1, Session2));

   // Gate 2: ATR(14, M5) indicator handle
   g_atrHandle = iATR(_Symbol, PERIOD_M5, 14);
   if(g_atrHandle == INVALID_HANDLE)
      HydraLog("WARNING: iATR(14,M5) handle creation failed — gate 2 will fail until available");

   RecoverState();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Reconstruct state from existing orders/positions (CLAUDE.md §4). |
//| Never assume a clean slate.                                      |
//+------------------------------------------------------------------+
void RecoverState()
  {
   int      positions     = CountHydraPositions();
   int      pendings      = CountHydraOrders();
   datetime cooldownUntil = (datetime)(long)GVGet(GV_COOLDOWN_UNTIL, 0.0);

   if(positions > 0)
     {
      // Reconstruct the direction lock and fill records (Phase 4):
      // lock from open positions, fill history from deals since the
      // earliest open position, OCO cleanup flag from leftover pendings.
      g_lockedDir = DeriveDirectionFromPositions();
      RecoverFillHistory(EarliestHydraPositionTime() - 60);
      if(OCO_Mode && CountOppositePendings() > 0)
         g_ocoCleanupPending = true;
      SetState(STATE_ACTIVE, StringFormat("recovery: %d open position(s), %d pending(s); direction %s, %d fill(s)%s",
                                          positions, pendings,
                                          g_lockedDir > 0 ? "BUY" : (g_lockedDir < 0 ? "SELL" : "UNKNOWN"),
                                          g_fillCount,
                                          g_ocoCleanupPending ? ", OCO cleanup pending" : ""));
     }
   else if(pendings > 0)
     {
      g_armedAt = EarliestHydraOrderSetup();   // restore the TTL anchor from order timestamps
      SetState(STATE_ARMED, StringFormat("recovery: %d pending order(s) found, zero fills; TTL anchor %s",
                                         pendings, TimeToString(g_armedAt, TIME_DATE|TIME_SECONDS)));
     }
   else if(cooldownUntil > TimeCurrent())
      SetState(STATE_COOLDOWN, StringFormat("recovery: cooldown active until %s",
                                            TimeToString(cooldownUntil, TIME_DATE|TIME_SECONDS)));
   else
      SetState(STATE_IDLE, "recovery: clean slate");
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
     }
   HydraLog(StringFormat("deinit (reason %d), state=%s", reason, StateName(g_state)));
  }

//+------------------------------------------------------------------+
//| ================== ONTICK (STATE DISPATCH) ====================== |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateDayAnchor();   // roll daily-loss anchor (gate 4) on server-day change

   switch(g_state)
     {
      case STATE_IDLE:
        {
         // Gate evaluation throttled to at most once per second
         if(TimeCurrent() == g_lastGateEval)
            break;
         g_lastGateEval = TimeCurrent();

         string failReason = "";
         bool   pass = EvaluateGates(failReason);
         LogGateStatusOnChange(pass, failReason);
         if(pass)
            DeployGrid();   // aborts cleanly (logged) on any invalid level; ARMED on success
         break;
        }

      case STATE_ARMED:
        {
         if(TimeCurrent() == g_lastArmedCheck)
            break;
         g_lastArmedCheck = TimeCurrent();

         // OnTradeTransaction owns the ARMED->ACTIVE transition; this polling
         // fallback only catches a missed transaction event (e.g. terminal hiccup).
         if(CountHydraPositions() > 0)
           {
            if(g_lockedDir == 0)
              {
               g_lockedDir = DeriveDirectionFromPositions();
               if(OCO_Mode)
                  g_ocoCleanupPending = true;
              }
            SetState(STATE_ACTIVE, StringFormat("fill detected via polling fallback — direction %s",
                                                g_lockedDir > 0 ? "BUY" : "SELL"));
            break;
           }

         // TTL expiry with zero fills -> cancel grid, back to IDLE (CLAUDE.md §7)
         if(g_armedAt > 0 && TimeCurrent() - g_armedAt >= (long)GridTTLMin * 60)
           {
            DeleteAllHydraPendings();
            SetState(STATE_IDLE, StringFormat("grid TTL %d min expired with zero fills", GridTTLMin));
            break;
           }

         // Broker-side ORDER_TIME_SPECIFIED expiry may have removed the orders already
         if(CountHydraOrders() == 0)
           {
            SetState(STATE_IDLE, "pendings no longer present (broker-side expiry)");
            break;
           }

         // Re-check gates 1 (session), 3 (spread), 5 (master switch) while ARMED
         string r = "";
         if(!GateSession(r) || !GateSpread(r) || !GateMasterSwitch(r))
           {
            DeleteAllHydraPendings();
            SetState(STATE_IDLE, "grid cancelled — gate failed while ARMED: " + r);
            break;
           }
         break;
        }

      case STATE_ACTIVE:
        {
         // MANDATORY ordering (CLAUDE.md §6): whipsaw guard runs FIRST,
         // before any other management logic. Never reorder.
         if(CheckWhipsawGuard())
            break;                            // guard fired — state already moved to COOLDOWN
         if(g_ocoCleanupPending)
            CancelOppositeSide();             // OCO: retry until the opposite side is clear
         ManageBasket();                      // Phase 6
         break;
        }

      case STATE_COOLDOWN:
        {
         // Sweep any straggler exposure that slipped past the kill switch
         if(CountHydraPositions() > 0)
           {
            HydraLog("straggler position found during COOLDOWN — closing");
            CloseAllHydraPositions();
           }
         if(CountHydraOrders() > 0)
            DeleteAllHydraPendings();

         datetime until = (datetime)(long)GVGet(GV_COOLDOWN_UNTIL, 0.0);
         if(TimeCurrent() >= until)
            SetState(STATE_IDLE, "cooldown expired");
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| ============ FILL DETECTION (OnTradeTransaction) ================ |
//| Phase 4: entry fills lock the direction (ARMED -> ACTIVE) and    |
//| are recorded per side for the Whipsaw Guard (Phase 5).           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.symbol != _Symbol)
      return;
   if(!HistoryDealSelect(trans.deal))
     {
      HydraLog(StringFormat("WARNING: deal #%I64u not selectable yet — polling fallback will catch the fill", trans.deal));
      return;
     }
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return;   // exits/adjustments don't lock direction and aren't whipsaw fills

   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      return;

   RegisterFill(dealType == DEAL_TYPE_BUY,
                (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME),
                HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                HistoryDealGetDouble(trans.deal, DEAL_PRICE));
  }

//--- Record an entry fill; first fill locks the direction and (in OCO
//    mode) schedules deletion of the entire opposite side
void RegisterFill(const bool isBuy, const datetime fillTime, const double volume, const double price)
  {
   g_fillCount++;
   if(isBuy)
      g_lastBuyFill = fillTime;
   else
      g_lastSellFill = fillTime;

   // Max possible fills: one side with OCO, both sides without
   HydraLog(StringFormat("fill %d/%d: %s %.2f @ %.2f", g_fillCount,
                         OCO_Mode ? GridLevels : GridLevels * 2,
                         isBuy ? "BUY" : "SELL", volume, price));

   if(g_lockedDir == 0)
     {
      g_lockedDir = isBuy ? 1 : -1;
      if(OCO_Mode)
        {
         g_ocoCleanupPending = true;
         CancelOppositeSide();   // immediate attempt; ACTIVE loop retries any failures
        }
      if(g_state == STATE_ARMED)
         SetState(STATE_ACTIVE, StringFormat("first fill — direction locked %s%s",
                                             isBuy ? "BUY" : "SELL",
                                             OCO_Mode ? ", OCO cancel issued" : ", reversal hedge kept (OCO off)"));
      else
         HydraLog(StringFormat("WARNING: first fill arrived in state %s", StateName(g_state)));
     }

   // Guard check straight from the fill event: a same-tick double fill
   // (possible with OCO_Mode=false, or before OCO cleanup lands) must
   // trigger the kill switch immediately, not on the next tick.
   CheckWhipsawGuard();

   // Straggler: a stop order can execute in the same instant the guard
   // fires — anything filled after the kill gets closed on the spot.
   if(g_state == STATE_COOLDOWN && CountHydraPositions() > 0)
     {
      HydraLog("straggler fill during COOLDOWN — closing immediately");
      CloseAllHydraPositions();
     }
  }

//--- OCO: delete every pending on the side opposite the locked direction.
//    Failures leave g_ocoCleanupPending set so the ACTIVE loop retries.
void CancelOppositeSide()
  {
   if(g_lockedDir == 0)
     {
      g_ocoCleanupPending = false;
      return;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsHydraOrder())
         continue;
      long type = OrderGetInteger(ORDER_TYPE);
      bool opposite = (g_lockedDir > 0) ? (type == ORDER_TYPE_SELL_STOP)
                                        : (type == ORDER_TYPE_BUY_STOP);
      if(!opposite)
         continue;
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;
      if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
         HydraLog(StringFormat("OCO delete #%I64u failed — retcode %d (will retry)", ticket, res.retcode));
     }
   int left = CountOppositePendings();
   g_ocoCleanupPending = (left > 0);
   if(left == 0)
      HydraLog("OCO: opposite side clear");
  }

//--- Pendings remaining on the side opposite the locked direction
int CountOppositePendings()
  {
   if(g_lockedDir == 0)
      return(0);
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0 || !IsHydraOrder())
         continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if((g_lockedDir > 0 && type == ORDER_TYPE_SELL_STOP) ||
         (g_lockedDir < 0 && type == ORDER_TYPE_BUY_STOP))
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| ========================= GATES ================================ |
//| Five ordered safety gates (CLAUDE.md §5), evaluated sequentially |
//| with short-circuit: a failure stops evaluation — later gates are |
//| NOT evaluated. Results cached for the dashboard (Phase 8).       |
//| Status is logged on change only (no 1 Hz spam).                  |
//+------------------------------------------------------------------+
bool EvaluateGates(string &failReason)
  {
   for(int i = 0; i < GATE_COUNT; i++)
     {
      g_gateEvaluated[i] = false;
      g_gatePass[i]      = false;
      g_gateReason[i]    = "not evaluated";
     }

   string r = "";

   // Gate 1 — Session / Killzone
   bool ok = GateSession(r);
   SetGateResult(0, ok, r);
   if(!ok) { failReason = GateFailText(0, r); return(false); }

   // Gate 2 — Volatility context
   ok = GateVolatility(r);
   SetGateResult(1, ok, r);
   if(!ok) { failReason = GateFailText(1, r); return(false); }

   // Gate 3 — Spread + spacing validity
   ok = GateSpread(r);
   SetGateResult(2, ok, r);
   if(!ok) { failReason = GateFailText(2, r); return(false); }

   // Gate 4 — Exposure / margin / daily loss
   ok = GateExposure(r);
   SetGateResult(3, ok, r);
   if(!ok) { failReason = GateFailText(3, r); return(false); }

   // Gate 5 — Master switch (SIGMA rule: never weaken or remove)
   ok = GateMasterSwitch(r);
   SetGateResult(4, ok, r);
   if(!ok) { failReason = GateFailText(4, r); return(false); }

   failReason = "";
   return(true);
  }

void SetGateResult(const int idx, const bool pass, const string reason)
  {
   g_gateEvaluated[idx] = true;
   g_gatePass[idx]      = pass;
   g_gateReason[idx]    = reason;
  }

string GateFailText(const int idx, const string reason)
  {
   return(StringFormat("gate %d (%s): %s", idx + 1, g_gateNames[idx], reason));
  }

//--- Log gate status only when it changes. The change key is pass/fail +
//    WHICH gate failed — not the full reason text, which oscillates every
//    second with live spread/ATR readings and would spam the journal.
void LogGateStatusOnChange(const bool pass, const string failReason)
  {
   string status = "PASS";
   if(!pass)
     {
      for(int i = 0; i < GATE_COUNT; i++)
         if(g_gateEvaluated[i] && !g_gatePass[i])
           {
            status = StringFormat("FAIL:gate%d", i + 1);
            break;
           }
     }
   if(status == g_lastGateStatus)
      return;
   g_lastGateStatus = status;
   if(pass)
      HydraLog("gates PASS — deploying grid");
   else
      HydraLog("gates FAIL — " + failReason);
  }

//--- Gate 1: server time inside Session1 or Session2 (windows treated as GMT per spec)
bool GateSession(string &reason)
  {
   if(!g_sessionsValid)
     {
      reason = StringFormat("malformed session input ('%s' / '%s')", Session1, Session2);
      return(false);
     }
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;
   if(nowMin >= g_sess1Start && nowMin < g_sess1End) { reason = "in " + Session1; return(true); }
   if(nowMin >= g_sess2Start && nowMin < g_sess2End) { reason = "in " + Session2; return(true); }
   reason = StringFormat("server %02d:%02d outside %s and %s", dt.hour, dt.min, Session1, Session2);
   return(false);
  }

//--- Gate 2: ATR(14, M5) within [ATR_Min_USD, ATR_Max_USD].
//    For XAUUSD the price unit is USD, so ATR in price terms IS the USD range.
bool GateVolatility(string &reason)
  {
   double atr = GetATRUSD();
   if(atr < 0.0)             { reason = "ATR(14,M5) unavailable (handle/data not ready)";                   return(false); }
   if(atr < ATR_Min_USD)     { reason = StringFormat("ATR %.2f < min %.2f (chop risk)", atr, ATR_Min_USD);  return(false); }
   if(atr > ATR_Max_USD)     { reason = StringFormat("ATR %.2f > max %.2f (move already ran)", atr, ATR_Max_USD); return(false); }
   reason = StringFormat("ATR %.2f in [%.2f, %.2f]", atr, ATR_Min_USD, ATR_Max_USD);
   return(true);
  }

//--- Last CLOSED M5 bar's ATR, in price units (USD for XAUUSD); -1.0 on failure
double GetATRUSD()
  {
   if(g_atrHandle == INVALID_HANDLE)
      return(-1.0);
   double buf[1];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) != 1)
      return(-1.0);
   return(buf[0]);
  }

//--- Gate 3: spread cap + validate GridSpacingUSD against
//    SYMBOL_TRADE_STOPS_LEVEL + spread + buffer (CLAUDE.md §5 gate 3)
bool GateSpread(string &reason)
  {
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPts > MaxSpreadPoints)
     {
      reason = StringFormat("spread %d pts > max %d", (int)spreadPts, MaxSpreadPoints);
      return(false);
     }
   long   stopsLvl      = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minSpacingUSD = (stopsLvl + spreadPts + SPACING_BUFFER_POINTS) * _Point;
   if(GridSpacingUSD < minSpacingUSD)
     {
      reason = StringFormat("GridSpacingUSD %.2f < required %.2f (stops %d + spread %d + buffer %d pts)",
                            GridSpacingUSD, minSpacingUSD, (int)stopsLvl, (int)spreadPts, SPACING_BUFFER_POINTS);
      return(false);
     }
   reason = StringFormat("spread %d pts, spacing OK", (int)spreadPts);
   return(true);
  }

//--- Gate 4: no existing Hydra exposure; margin level above floor; daily loss under cap
bool GateExposure(string &reason)
  {
   int pos = CountHydraPositions();
   int ord = CountHydraOrders();
   if(pos > 0 || ord > 0)
     {
      reason = StringFormat("existing Hydra exposure (%d position(s), %d order(s))", pos, ord);
      return(false);
     }

   // Margin level is only meaningful when margin is in use
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   if(margin > 0.0)
     {
      double lvl = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(lvl <= MinMarginLevelPct)
        {
         reason = StringFormat("margin level %.0f%% <= min %.0f%%", lvl, MinMarginLevelPct);
         return(false);
        }
     }

   double dayStart = GVGet(GV_DAY_BALANCE, AccountInfoDouble(ACCOUNT_BALANCE));
   if(dayStart > 0.0)
     {
      double lossPct = (dayStart - AccountInfoDouble(ACCOUNT_EQUITY)) / dayStart * 100.0;
      if(lossPct >= MaxDailyLossPct)
        {
         reason = StringFormat("daily loss %.2f%% >= limit %.2f%%", lossPct, MaxDailyLossPct);
         return(false);
        }
     }

   reason = "no exposure, margin OK, daily loss OK";
   return(true);
  }

//--- Gate 5: master switch — input flag AND terminal AutoTrading AND EA trade permission
bool GateMasterSwitch(string &reason)
  {
   if(!AUTO_TRADING_ENABLED)                                { reason = "AUTO_TRADING_ENABLED=false";        return(false); }
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)     { reason = "terminal AutoTrading button OFF";   return(false); }
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)               { reason = "EA trading not allowed (program)";  return(false); }
   reason = "enabled";
   return(true);
  }

//+------------------------------------------------------------------+
//| ======================= GRID DEPLOY ============================= |
//| CLAUDE.md §7: symmetric stop-order grid around the current mid.  |
//| ALL levels are validated BEFORE the first send — any invalid     |
//| level aborts the entire deployment (no partial grids). A send    |
//| failure mid-deployment rolls back every order already placed.    |
//+------------------------------------------------------------------+
bool DeployGrid()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
     {
      LogDeployAbortOnChange("SymbolInfoTick failed");
      return(false);
     }

   double anchor    = NormalizePrice((tick.bid + tick.ask) / 2.0);
   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist   = MathMax(stopsLvl, freezeLvl) * _Point;
   double minBuy    = tick.ask + minDist;   // buy stops must sit at/above this
   double maxSell   = tick.bid - minDist;   // sell stops must sit at/below this

   // --- Pre-flight: compute and validate every level BEFORE sending anything
   int    n = ArraySize(g_lots);
   double buyPx[], sellPx[];
   ArrayResize(buyPx, n);
   ArrayResize(sellPx, n);
   for(int i = 0; i < n; i++)
     {
      buyPx[i]  = NormalizePrice(anchor + FirstLevelOffsetUSD + i * GridSpacingUSD);
      sellPx[i] = NormalizePrice(anchor - FirstLevelOffsetUSD - i * GridSpacingUSD);
      if(buyPx[i] < minBuy)
        {
         LogDeployAbortOnChange(StringFormat("buy level %d @ %.2f violates min distance (ask %.2f + stops/freeze %.2f)",
                                             i, buyPx[i], tick.ask, minDist));
         return(false);
        }
      if(sellPx[i] > maxSell || sellPx[i] <= 0.0)
        {
         LogDeployAbortOnChange(StringFormat("sell level %d @ %.2f violates min distance (bid %.2f - stops/freeze %.2f)",
                                             i, sellPx[i], tick.bid, minDist));
         return(false);
        }
     }

   // Broker-side expiry where supported; the code TTL in ARMED applies regardless
   bool     useSpecified = (SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) != 0;
   datetime expiration   = 0;
   if(useSpecified)
      expiration = (datetime)((long)TimeCurrent() + (long)GridTTLMin * 60);

   // --- Placement: any send failure rolls back the whole deployment
   for(int i = 0; i < n; i++)
     {
      if(!PlaceStopOrder(true, i, buyPx[i], g_lots[i], expiration, useSpecified))
        {
         RollbackDeployment();
         return(false);
        }
      if(!PlaceStopOrder(false, i, sellPx[i], g_lots[i], expiration, useSpecified))
        {
         RollbackDeployment();
         return(false);
        }
     }

   g_armedAt          = TimeCurrent();
   g_lastDeployAbort  = "";
   SetState(STATE_ARMED, StringFormat("grid deployed: %d+%d stops around %.2f, spacing %.2f, TTL %d min",
                                      n, n, anchor, GridSpacingUSD, GridTTLMin));
   return(true);
  }

//--- Single pending stop order, SIGMA-tagged (IOC, magic, comment prefix)
bool PlaceStopOrder(const bool isBuy, const int level, const double price, const double lot,
                    const datetime expiration, const bool useSpecified)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.type         = isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
   req.price        = price;
   req.magic        = (ulong)MagicNumber;
   req.comment      = StringFormat("%s.%s%d", HYDRA_COMMENT_PREFIX, isBuy ? "B" : "S", level);
   req.type_filling = ORDER_FILLING_IOC;                                  // SIGMA convention #2
   req.type_time    = useSpecified ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
   req.expiration   = expiration;

   bool sent = OrderSend(req, res);
   if(!sent || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
     {
      HydraLog(StringFormat("OrderSend FAIL: %s level %d @ %.2f lot %.2f — retcode %d (%s)",
                            isBuy ? "BUY_STOP" : "SELL_STOP", level, price, lot, res.retcode, res.comment));
      return(false);
     }
   return(true);
  }

//--- Mid-deployment failure: remove every Hydra pending placed so far.
//    Gate 4 guarantees zero pre-existing Hydra orders, so a full sweep
//    deletes exactly this deployment's orders.
void RollbackDeployment()
  {
   HydraLog("deployment FAILED mid-placement — rolling back all Hydra pendings");
   int left = DeleteAllHydraPendings();
   HydraLog(StringFormat("rollback done, %d Hydra pending(s) remaining", left));
  }

//--- Delete all Hydra pendings (this symbol + magic), up to 3 sweeps.
//    Returns the number still present afterwards (0 = clean).
int DeleteAllHydraPendings()
  {
   for(int attempt = 0; attempt < 3; attempt++)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0 || !IsHydraOrder())
            continue;
         MqlTradeRequest req;
         MqlTradeResult  res;
         ZeroMemory(req);
         ZeroMemory(res);
         req.action = TRADE_ACTION_REMOVE;
         req.order  = ticket;
         if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
            HydraLog(StringFormat("delete pending #%I64u failed — retcode %d (sweep %d)", ticket, res.retcode, attempt + 1));
        }
      if(CountHydraOrders() == 0)
         return(0);
     }
   int left = CountHydraOrders();
   HydraLog(StringFormat("WARNING: %d Hydra pending(s) still present after delete sweeps", left));
   return(left);
  }

//--- Deploy-abort reasons repeat at 1 Hz while gates stay green: log on change only
void LogDeployAbortOnChange(const string reason)
  {
   if(reason == g_lastDeployAbort)
      return;
   g_lastDeployAbort = reason;
   HydraLog("deployment ABORTED — " + reason);
  }

//+------------------------------------------------------------------+
//| ====================== WHIPSAW GUARD ============================ |
//| MANDATORY kill switch (CLAUDE.md §6). Called at the top of       |
//| OnTick in ACTIVE state BEFORE any other management logic, and    |
//| again straight from RegisterFill so a same-tick double fill      |
//| (OCO_Mode=false edge case) is caught without waiting a tick.     |
//| Returns true when the guard fired. NEVER weaken or remove.       |
//+------------------------------------------------------------------+
bool CheckWhipsawGuard()
  {
   if(g_state == STATE_COOLDOWN)
      return(false);                      // already fired / locked out
   if(g_lastBuyFill == 0 || g_lastSellFill == 0)
      return(false);                      // need one fill on EACH side

   long gap = (long)g_lastBuyFill - (long)g_lastSellFill;
   if(gap < 0)
      gap = -gap;
   if(gap > WhipsawWindowSec)
      return(false);                      // opposite fills, but too far apart

   // --- WHIPSAW: both sides filled within the window. Kill everything.
   HydraLog(StringFormat("WHIPSAW DETECTED — buy fill %s / sell fill %s, gap %d s <= window %d s",
                         TimeToString(g_lastBuyFill, TIME_DATE|TIME_SECONDS),
                         TimeToString(g_lastSellFill, TIME_DATE|TIME_SECONDS),
                         (int)gap, WhipsawWindowSec));

   // 1) close all Hydra positions at market
   CloseAllHydraPositions();
   // 2) delete all remaining Hydra pendings
   DeleteAllHydraPendings();
   // 3+4) persistent counter (survives restart), then cooldown
   int count = IncrementWhipsawCounter();

   datetime until;
   if(count >= MaxWhipsawsPerDay)
     {
      until = NextServerDayStart();
      HydraLog(StringFormat("whipsaw count %d/%d — locked out until next trading day", count, MaxWhipsawsPerDay));
     }
   else
      until = (datetime)((long)TimeCurrent() + (long)WhipsawCooldownMin * 60);

   GVSet(GV_COOLDOWN_UNTIL, (double)(long)until);
   SetState(STATE_COOLDOWN, StringFormat("whipsaw guard fired (%d/%d today), cooldown until %s",
                                         count, MaxWhipsawsPerDay, TimeToString(until, TIME_DATE|TIME_SECONDS)));
   return(true);
  }

//--- Close every Hydra position at market (urgent — generous slippage
//    allowance, up to 5 sweeps). Returns positions still open afterwards.
int CloseAllHydraPositions()
  {
   for(int attempt = 0; attempt < 5; attempt++)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !IsHydraPosition())
            continue;
         bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         MqlTradeRequest req;
         MqlTradeResult  res;
         ZeroMemory(req);
         ZeroMemory(res);
         req.action       = TRADE_ACTION_DEAL;
         req.symbol       = _Symbol;
         req.position     = ticket;
         req.volume       = PositionGetDouble(POSITION_VOLUME);
         req.type         = isLong ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price        = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         req.deviation    = 50;                       // closing is urgent, accept slippage
         req.magic        = (ulong)MagicNumber;
         req.comment      = StringFormat("%s.kill", HYDRA_COMMENT_PREFIX);
         req.type_filling = ORDER_FILLING_IOC;        // SIGMA convention #2
         if(!OrderSend(req, res) ||
            (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_DONE_PARTIAL))
            HydraLog(StringFormat("close position #%I64u failed — retcode %d (sweep %d)",
                                  ticket, res.retcode, attempt + 1));
        }
      if(CountHydraPositions() == 0)
         return(0);
     }
   int left = CountHydraPositions();
   HydraLog(StringFormat("WARNING: %d Hydra position(s) still open after close sweeps", left));
   return(left);
  }

//--- Bump the persistent whipsaw counter (terminal global variable,
//    survives restart), auto-resetting when the server day changed
int IncrementWhipsawCounter()
  {
   long today = (long)(TimeCurrent() / 86400);
   int  count = (int)GVGet(GV_WHIPSAW_COUNT, 0.0);
   if((long)GVGet(GV_WHIPSAW_DAY, -1.0) != today)
      count = 0;
   count++;
   GVSet(GV_WHIPSAW_DAY, (double)today);
   GVSet(GV_WHIPSAW_COUNT, (double)count);
   return(count);
  }

//--- Next server-day midnight (the "come back tomorrow" lockout target)
datetime NextServerDayStart()
  {
   return((datetime)(((long)(TimeCurrent() / 86400) + 1) * 86400));
  }

//+------------------------------------------------------------------+
//| ====================== BASKET MANAGER =========================== |
//| Phase 6: basket TP / SL / trailing, pending cleanup on trail.    |
//+------------------------------------------------------------------+
void ManageBasket()
  {
   // Phase 6
  }

//+------------------------------------------------------------------+
//| ======================== DASHBOARD ============================== |
//| Phase 8: collapsible panel per CLAUDE.md §10.1. Header sources   |
//| its version from HYDRA_VERSION — never hardcode it twice.        |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   // Phase 8
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // Phase 8: header click collapse/expand, rebuild on timeframe switch
  }

//+------------------------------------------------------------------+
//| ========================== UTILS ================================ |
//+------------------------------------------------------------------+

//--- Logging: every log line carries the [HYDRA] prefix + timestamp (SIGMA convention #8)
void HydraLog(const string msg)
  {
   Print("[HYDRA] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " ", msg);
  }

string StateName(const EHydraState s)
  {
   switch(s)
     {
      case STATE_IDLE:     return("IDLE");
      case STATE_ARMED:    return("ARMED");
      case STATE_ACTIVE:   return("ACTIVE");
      case STATE_COOLDOWN: return("COOLDOWN");
     }
   return("UNKNOWN");
  }

//--- Single choke point for state transitions: every transition is logged.
//    Entering IDLE clears the per-grid-cycle runtime (lock, fills, TTL anchor).
void SetState(const EHydraState newState, const string reason)
  {
   HydraLog(StringFormat("state %s -> %s (%s)", StateName(g_state), StateName(newState), reason));
   g_state = newState;
   if(newState == STATE_IDLE)
      ResetGridRuntime();
  }

//--- Per-cycle runtime reset (fill records stay intact through ACTIVE and
//    COOLDOWN so the Whipsaw Guard can use them; cleared on return to IDLE)
void ResetGridRuntime()
  {
   g_lockedDir         = 0;
   g_fillCount         = 0;
   g_lastBuyFill       = 0;
   g_lastSellFill      = 0;
   g_ocoCleanupPending = false;
   g_armedAt           = 0;
  }

//--- Persistent global variables, namespaced per symbol
string GVKey(const string key)
  {
   return("SIGMA.Hydra." + _Symbol + "." + key);
  }

double GVGet(const string key, const double fallback)
  {
   string k = GVKey(key);
   if(!GlobalVariableCheck(k))
      return(fallback);
   return(GlobalVariableGet(k));
  }

void GVSet(const string key, const double value)
  {
   GlobalVariableSet(GVKey(key), value);
  }

//--- Ownership filter: Hydra manages ONLY this symbol + this magic (SIGMA convention #4)
bool IsHydraPosition()
  {
   return(PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == MagicNumber);
  }

bool IsHydraOrder()
  {
   return(OrderGetString(ORDER_SYMBOL) == _Symbol &&
          OrderGetInteger(ORDER_MAGIC) == MagicNumber);
  }

int CountHydraPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(IsHydraPosition())
         count++;
     }
   return(count);
  }

int CountHydraOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(IsHydraOrder())
         count++;
     }
   return(count);
  }

//--- Parse and validate LotProgressionCSV (CLAUDE.md §8):
//    element count must equal GridLevels; every lot >= symbol min lot
//    and aligned to the symbol lot step. Failure -> init aborts.
bool ParseLotProgression(const string csv, double &lots[])
  {
   string parts[];
   int n = StringSplit(csv, ',', parts);
   if(n != GridLevels)
     {
      HydraLog(StringFormat("INIT FAIL: LotProgressionCSV has %d entries but GridLevels=%d", n, GridLevels));
      return(false);
     }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   ArrayResize(lots, n);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      double lot = StringToDouble(s);

      if(lot < minLot || lot <= 0.0)
        {
         HydraLog(StringFormat("INIT FAIL: lot[%d]='%s' invalid (min lot %.2f)", i, s, minLot));
         return(false);
        }
      if(lotStep > 0.0 && MathAbs(MathRound(lot / lotStep) * lotStep - lot) > 0.0000001)
        {
         HydraLog(StringFormat("INIT FAIL: lot[%d]=%.4f not aligned to lot step %.4f", i, lot, lotStep));
         return(false);
        }
      lots[i] = lot;
     }
   return(true);
  }

//--- Roll the per-day anchors on server-day change: balance snapshot for
//    gate 4's daily-loss cap, and the whipsaw counter reset (CLAUDE.md §6)
void UpdateDayAnchor()
  {
   long today = (long)(TimeCurrent() / 86400);
   if((long)GVGet(GV_DAY_STAMP, -1.0) == today)
      return;
   GVSet(GV_DAY_STAMP, (double)today);
   GVSet(GV_DAY_BALANCE, AccountInfoDouble(ACCOUNT_BALANCE));
   if((long)GVGet(GV_WHIPSAW_DAY, -1.0) != today && (int)GVGet(GV_WHIPSAW_COUNT, 0.0) != 0)
     {
      GVSet(GV_WHIPSAW_DAY, (double)today);
      GVSet(GV_WHIPSAW_COUNT, 0.0);
      HydraLog("whipsaw counter reset for the new trading day");
     }
   HydraLog(StringFormat("new server day — daily-loss balance anchor %.2f", AccountInfoDouble(ACCOUNT_BALANCE)));
  }

//--- Parse "HH:MM-HH:MM" into minutes-of-day; false on any malformation
//    (missing dash, bad numbers, start >= end)
bool ParseSessionWindow(const string window, int &startMin, int &endMin)
  {
   string parts[];
   if(StringSplit(window, '-', parts) != 2)
      return(false);
   int s = ParseHHMM(parts[0]);
   int e = ParseHHMM(parts[1]);
   if(s < 0 || e < 0 || s >= e)
      return(false);
   startMin = s;
   endMin   = e;
   return(true);
  }

//--- Snap a price to the symbol tick size, then to digits
double NormalizePrice(const double price)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize > 0.0)
      return(NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits));
   return(NormalizeDouble(price, _Digits));
  }

//--- Oldest ORDER_TIME_SETUP among Hydra pendings — restores the TTL
//    anchor after a terminal restart while ARMED
datetime EarliestHydraOrderSetup()
  {
   datetime earliest = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0 || !IsHydraOrder())
         continue;
      datetime ts = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(earliest == 0 || ts < earliest)
         earliest = ts;
     }
   return(earliest);
  }

//--- Direction from open Hydra positions: side of the EARLIEST position
//    (that is the fill that locked the direction). Warns on mixed sides.
int DeriveDirectionFromPositions()
  {
   int      dir      = 0;
   datetime earliest = 0;
   bool     mixed    = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !IsHydraPosition())
         continue;
      int      d  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      datetime pt = (datetime)PositionGetInteger(POSITION_TIME);
      if(dir != 0 && d != dir)
         mixed = true;
      if(earliest == 0 || pt < earliest)
        {
         earliest = pt;
         dir      = d;
        }
     }
   if(mixed)
      HydraLog("WARNING: mixed-direction Hydra positions found (whipsaw exposure?)");
   return(dir);
  }

//--- Open time of the oldest Hydra position (start of the current basket)
datetime EarliestHydraPositionTime()
  {
   datetime earliest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !IsHydraPosition())
         continue;
      datetime pt = (datetime)PositionGetInteger(POSITION_TIME);
      if(earliest == 0 || pt < earliest)
         earliest = pt;
     }
   return(earliest);
  }

//--- Rebuild fill count + per-side fill times from deal history since
//    `from` (restart mid-ACTIVE must not lose the whipsaw records)
void RecoverFillHistory(const datetime from)
  {
   if(!HistorySelect(from, TimeCurrent() + 60))
     {
      HydraLog("WARNING: HistorySelect failed — fill history not recovered");
      return;
     }
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
         continue;
      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      g_fillCount++;
      if(dealType == DEAL_TYPE_BUY)
        {
         if(t > g_lastBuyFill)
            g_lastBuyFill = t;
        }
      else
        {
         if(t > g_lastSellFill)
            g_lastSellFill = t;
        }
     }
  }

//--- "HH:MM" -> minutes-of-day, or -1 if malformed
int ParseHHMM(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   string hm[];
   if(StringSplit(s, ':', hm) != 2)
      return(-1);
   long h = StringToInteger(hm[0]);
   long m = StringToInteger(hm[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return(-1);
   return((int)(h * 60 + m));
  }
//+------------------------------------------------------------------+
