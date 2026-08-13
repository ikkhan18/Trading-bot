//+------------------------------------------------------------------+
//|                                           TrendConfluenceEA.mq4  |
//|           Auto-trading Expert Advisor for MetaTrader 4           |
//|  Trend (EMA 21/55/200) + ADX + RSI pullback + MACD + ATR risk    |
//+------------------------------------------------------------------+
#property copyright "Trend Confluence EA"
#property version   "1.00"
#property description "Trend-following auto trader: EMA regime, ADX strength, RSI pullback, MACD momentum, ATR risk."
#property strict

#define SIGNAL_NONE  0
#define SIGNAL_BUY   1
#define SIGNAL_SELL -1

//------------------------------ Inputs --------------------------------
input int      InpMagic              = 180526;   // Magic number
input int      InpSlippagePoints     = 20;       // Max slippage (points)
input int      InpMaxPositions       = 1;        // Max open positions (this symbol)
input bool     InpCloseOnOpposite    = true;     // Close position on opposite signal
input bool     InpTradeOnNewBarOnly  = true;     // Evaluate only on a newly closed bar

input double   InpRiskPercent        = 1.0;      // Risk per trade (% of equity)
input double   InpFixedLots          = 0.0;      // Fixed lots (0 = use risk %)
input double   InpSL_ATR             = 1.5;      // Stop loss = ATR x this
input double   InpTP_ATR             = 2.5;      // Take profit = ATR x this
input double   InpBreakEvenATR       = 1.0;      // Move SL to BE after this ATR profit (0 = off)
input double   InpBreakEvenOffsetATR = 0.1;      // BE offset in ATR
input double   InpTrailStartATR      = 1.2;      // Start trailing after this ATR profit (0 = off)
input double   InpTrailATR           = 1.0;      // Trailing distance in ATR
input double   InpMaxDailyLossPct    = 4.0;      // Pause trading after this daily equity DD % (0 = off)

input int      InpEmaFast            = 21;       // Fast EMA
input int      InpEmaSlow            = 55;       // Slow EMA
input int      InpEmaTrend           = 200;      // Regime EMA

input int      InpAdxPeriod          = 14;       // ADX period
input double   InpMinAdx             = 22.0;     // Minimum ADX to allow entries
input bool     InpUseAdxDiFilter     = true;     // Require +DI/-DI to agree with direction
input int      InpRsiPeriod          = 14;       // RSI period
input double   InpRsiBuyLevel        = 45.0;     // RSI must have dipped to/below this for BUY
input double   InpRsiSellLevel       = 55.0;     // RSI must have rallied to/above this for SELL
input double   InpRsiOverbought      = 70.0;     // Skip BUY if RSI is already overbought
input double   InpRsiOversold        = 30.0;     // Skip SELL if RSI is already oversold
input int      InpMacdFast           = 12;       // MACD fast EMA
input int      InpMacdSlow           = 26;       // MACD slow EMA
input int      InpMacdSignal         = 9;        // MACD signal EMA
input int      InpAtrPeriod          = 14;       // ATR period
input bool     InpRequireCandle      = true;     // Signal bar must be in trade direction
input bool     InpRequireEmaReclaim  = true;     // Close must reclaim/reject the fast EMA

input int      InpMaxSpreadPoints    = 30;       // Max spread (points, 0 = off)
input bool     InpUseSessionFilter   = false;    // Limit trading hours (broker time)
input int      InpSessionStartHour   = 7;        // Session start hour
input int      InpSessionEndHour     = 21;       // Session end hour (exclusive)
input bool     InpSkipFridayLate     = true;     // Do not open trades after Friday 18:00
input bool     InpShowDashboard      = true;     // Chart comment dashboard

datetime g_last_bar = 0;
datetime g_day_stamp = 0;
double   g_day_start_equity = 0.0;
string   g_last_reason = "";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpEmaFast < 2 || InpEmaSlow < 2 || InpEmaTrend < 2)
     {
      Print("EMA periods must be >= 2");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpEmaFast >= InpEmaSlow || InpEmaSlow >= InpEmaTrend)
     {
      Print("Require EmaFast < EmaSlow < EmaTrend");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskPercent <= 0.0 && InpFixedLots <= 0.0)
     {
      Print("Set RiskPercent or FixedLots");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpSL_ATR <= 0.0 || InpTP_ATR <= 0.0)
     {
      Print("ATR multiples for SL/TP must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   _ResetDay();
   Print("TrendConfluenceEA initialized on ", Symbol(), " ", Period());
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   _ResetDay();
   _ManageOpenPositions();

   bool new_bar = _IsNewBar();
   if(InpTradeOnNewBarOnly && !new_bar)
     {
      if(InpShowDashboard)
         _Dashboard(SIGNAL_NONE);
      return;
     }

   int signal = _EvaluateSignal();
   if(InpShowDashboard)
      _Dashboard(signal);

   if(signal == SIGNAL_NONE)
      return;
   if(!_TradingAllowed())
      return;

   if(InpCloseOnOpposite)
      _CloseOpposite(signal);

   if(_CountPositions() >= InpMaxPositions)
      return;

   _OpenTrade(signal);
  }

//+------------------------------------------------------------------+
bool _IsNewBar()
  {
   datetime t = iTime(Symbol(), Period(), 0);
   if(t == 0)
      return false;
   if(t == g_last_bar)
      return false;
   g_last_bar = t;
   return true;
  }

//+------------------------------------------------------------------+
void _ResetDay()
  {
   datetime stamp = iTime(Symbol(), PERIOD_D1, 0);
   if(stamp <= 0)
      stamp = TimeCurrent() - (TimeCurrent() % 86400);
   if(stamp != g_day_stamp)
     {
      g_day_stamp = stamp;
      g_day_start_equity = AccountEquity();
     }
  }

//+------------------------------------------------------------------+
int _EvaluateSignal()
  {
   g_last_reason = "warmup";

   double ema_fast0  = iMA(Symbol(), Period(), InpEmaFast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema_slow0  = iMA(Symbol(), Period(), InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema_trend0 = iMA(Symbol(), Period(), InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE, 1);
   double adx0       = iADX(Symbol(), Period(), InpAdxPeriod, PRICE_CLOSE, MODE_MAIN, 1);
   double plus_di0   = iADX(Symbol(), Period(), InpAdxPeriod, PRICE_CLOSE, MODE_PLUSDI, 1);
   double minus_di0  = iADX(Symbol(), Period(), InpAdxPeriod, PRICE_CLOSE, MODE_MINUSDI, 1);
   double rsi0       = iRSI(Symbol(), Period(), InpRsiPeriod, PRICE_CLOSE, 1);
   double rsi1       = iRSI(Symbol(), Period(), InpRsiPeriod, PRICE_CLOSE, 2);
   double macd0      = iMACD(Symbol(), Period(), InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE, MODE_MAIN, 1);
   double macd1      = iMACD(Symbol(), Period(), InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE, MODE_MAIN, 2);
   double macd_sig0  = iMACD(Symbol(), Period(), InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE, MODE_SIGNAL, 1);
   double atr0       = iATR(Symbol(), Period(), InpAtrPeriod, 1);
   double open1      = iOpen(Symbol(), Period(), 1);
   double close1     = iClose(Symbol(), Period(), 1);

   if(ema_fast0 == 0.0 || ema_slow0 == 0.0 || ema_trend0 == 0.0 || atr0 <= 0.0)
      return SIGNAL_NONE;

   if(adx0 < InpMinAdx)
     {
      g_last_reason = "ADX too low (range)";
      return SIGNAL_NONE;
     }

   bool bull_regime = (close1 > ema_trend0 && ema_fast0 > ema_slow0);
   bool bear_regime = (close1 < ema_trend0 && ema_fast0 < ema_slow0);

   bool rsi_buy  = (rsi1 <= InpRsiBuyLevel && rsi0 > rsi1 && rsi0 < InpRsiOverbought);
   bool rsi_sell = (rsi1 >= InpRsiSellLevel && rsi0 < rsi1 && rsi0 > InpRsiOversold);

   bool macd_bull = (macd0 > macd_sig0 && macd0 > macd1);
   bool macd_bear = (macd0 < macd_sig0 && macd0 < macd1);

   bool bull_candle = InpRequireCandle ? (close1 > open1) : true;
   bool bear_candle = InpRequireCandle ? (close1 < open1) : true;
   bool reclaim     = InpRequireEmaReclaim ? (close1 > ema_fast0) : true;
   bool reject      = InpRequireEmaReclaim ? (close1 < ema_fast0) : true;
   bool di_buy      = InpUseAdxDiFilter ? (plus_di0 > minus_di0) : true;
   bool di_sell     = InpUseAdxDiFilter ? (minus_di0 > plus_di0) : true;

   if(bull_regime && rsi_buy && macd_bull && bull_candle && reclaim && di_buy)
     {
      g_last_reason = "BUY confluence";
      return SIGNAL_BUY;
     }
   if(bear_regime && rsi_sell && macd_bear && bear_candle && reject && di_sell)
     {
      g_last_reason = "SELL confluence";
      return SIGNAL_SELL;
     }

   if(!bull_regime && !bear_regime)
      g_last_reason = "No EMA regime";
   else if(bull_regime)
      g_last_reason = "Bull trend, waiting for pullback";
   else
      g_last_reason = "Bear trend, waiting for pullback";
   return SIGNAL_NONE;
  }

//+------------------------------------------------------------------+
bool _TradingAllowed()
  {
   if(!IsTradeAllowed())
     {
      g_last_reason = "AutoTrading disabled";
      return false;
     }

   if(InpMaxDailyLossPct > 0.0 && g_day_start_equity > 0.0)
     {
      double dd = (g_day_start_equity - AccountEquity()) / g_day_start_equity * 100.0;
      if(dd >= InpMaxDailyLossPct)
        {
         g_last_reason = "Daily loss limit";
         return false;
        }
     }

   if(InpMaxSpreadPoints > 0)
     {
      int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
      if(spread > InpMaxSpreadPoints)
        {
         g_last_reason = "Spread too wide";
         return false;
        }
     }

   int hour = TimeHour(TimeCurrent());
   int dow  = TimeDayOfWeek(TimeCurrent());
   if(InpUseSessionFilter)
     {
      if(hour < InpSessionStartHour || hour >= InpSessionEndHour)
        {
         g_last_reason = "Outside session";
         return false;
        }
     }
   if(InpSkipFridayLate && dow == 5 && hour >= 18)
     {
      g_last_reason = "Friday late";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
int _CountPositions()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
         continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
void _CloseOpposite(const int signal)
  {
   int unwanted = (signal == SIGNAL_BUY) ? OP_SELL : OP_BUY;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
         continue;
      if(OrderType() != unwanted)
         continue;
      double price = (OrderType() == OP_BUY) ? MarketInfo(Symbol(), MODE_BID) : MarketInfo(Symbol(), MODE_ASK);
      if(!OrderClose(OrderTicket(), OrderLots(), price, InpSlippagePoints, clrOrange))
         Print("OrderClose failed: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
double _NormalizeVolume(double lots)
  {
   double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
   double max_lot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step    = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      step = 0.01;
   lots = MathFloor(lots / step + 1e-12) * step;
   lots = MathMax(min_lot, MathMin(max_lot, lots));
   int digits = 0;
   double s = step;
   while(s < 1.0 && digits < 8)
     {
      s *= 10.0;
      digits++;
     }
   return NormalizeDouble(lots, digits);
  }

//+------------------------------------------------------------------+
double _LotsFromAtrStop(const double sl_distance)
  {
   if(InpFixedLots > 0.0)
      return _NormalizeVolume(InpFixedLots);

   double risk_money = AccountEquity() * InpRiskPercent / 100.0;
   double tick_size  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tick_value = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0 || sl_distance <= 0.0)
      return 0.0;

   double loss_per_lot = (sl_distance / tick_size) * tick_value;
   if(loss_per_lot <= 0.0)
      return 0.0;
   return _NormalizeVolume(risk_money / loss_per_lot);
  }

//+------------------------------------------------------------------+
double _StopsLevelDistance()
  {
   int level = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   int freeze = (int)MarketInfo(Symbol(), MODE_FREEZELEVEL);
   int pts = MathMax(level, freeze);
   return pts * Point;
  }

//+------------------------------------------------------------------+
void _OpenTrade(const int signal)
  {
   RefreshRates();
   double atr0 = iATR(Symbol(), Period(), InpAtrPeriod, 1);
   if(atr0 <= 0.0)
     {
      Print("ATR unavailable, skip order");
      return;
     }

   double sl_dist = atr0 * InpSL_ATR;
   double tp_dist = atr0 * InpTP_ATR;
   double min_dist = _StopsLevelDistance();
   if(sl_dist < min_dist)
      sl_dist = min_dist;
   if(tp_dist < min_dist)
      tp_dist = min_dist;

   double lots = _LotsFromAtrStop(sl_dist);
   if(lots <= 0.0)
     {
      Print("Lot size is 0, skip order");
      return;
     }

   string comment = "TrendConfluence";
   int ticket = -1;
   if(signal == SIGNAL_BUY)
     {
      double sl = NormalizeDouble(Ask - sl_dist, Digits);
      double tp = NormalizeDouble(Ask + tp_dist, Digits);
      ticket = OrderSend(Symbol(), OP_BUY, lots, Ask, InpSlippagePoints, sl, tp, comment, InpMagic, 0, clrDodgerBlue);
     }
   else if(signal == SIGNAL_SELL)
     {
      double sl = NormalizeDouble(Bid + sl_dist, Digits);
      double tp = NormalizeDouble(Bid - tp_dist, Digits);
      ticket = OrderSend(Symbol(), OP_SELL, lots, Bid, InpSlippagePoints, sl, tp, comment, InpMagic, 0, clrOrangeRed);
     }

   if(ticket < 0)
      Print("OrderSend failed: ", GetLastError());
  }

//+------------------------------------------------------------------+
void _ManageOpenPositions()
  {
   double atr0 = iATR(Symbol(), Period(), InpAtrPeriod, 1);
   if(atr0 <= 0.0)
      return;
   RefreshRates();
   double min_dist = _StopsLevelDistance();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      double entry = OrderOpenPrice();
      double sl    = OrderStopLoss();
      double tp    = OrderTakeProfit();
      double new_sl = sl;

      if(OrderType() == OP_BUY)
        {
         double profit = Bid - entry;
         if(InpBreakEvenATR > 0.0 && profit >= InpBreakEvenATR * atr0)
           {
            double be = entry + InpBreakEvenOffsetATR * atr0;
            if(be > sl + Point)
               new_sl = be;
           }
         if(InpTrailStartATR > 0.0 && profit >= InpTrailStartATR * atr0)
           {
            double trail = Bid - InpTrailATR * atr0;
            if(trail > new_sl + Point)
               new_sl = trail;
           }
         if(new_sl > 0.0 && Bid - new_sl < min_dist)
            continue;
        }
      else
        {
         double profit = entry - Ask;
         if(InpBreakEvenATR > 0.0 && profit >= InpBreakEvenATR * atr0)
           {
            double be = entry - InpBreakEvenOffsetATR * atr0;
            if(sl == 0.0 || be < sl - Point)
               new_sl = be;
           }
         if(InpTrailStartATR > 0.0 && profit >= InpTrailStartATR * atr0)
           {
            double trail = Ask + InpTrailATR * atr0;
            if(sl == 0.0 || trail < new_sl - Point)
               new_sl = trail;
           }
         if(new_sl > 0.0 && new_sl - Ask < min_dist)
            continue;
        }

      new_sl = NormalizeDouble(new_sl, Digits);
      if(new_sl > 0.0 && MathAbs(new_sl - sl) > Point)
        {
         if(!OrderModify(OrderTicket(), entry, new_sl, tp, 0, clrYellow))
            Print("OrderModify failed: ", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
void _Dashboard(const int signal)
  {
   double ema_fast0  = iMA(Symbol(), Period(), InpEmaFast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema_slow0  = iMA(Symbol(), Period(), InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema_trend0 = iMA(Symbol(), Period(), InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE, 1);
   double adx0       = iADX(Symbol(), Period(), InpAdxPeriod, PRICE_CLOSE, MODE_MAIN, 1);
   double rsi0       = iRSI(Symbol(), Period(), InpRsiPeriod, PRICE_CLOSE, 1);
   double atr0       = iATR(Symbol(), Period(), InpAtrPeriod, 1);
   double close1     = iClose(Symbol(), Period(), 1);

   string dir = "FLAT";
   if(close1 > ema_trend0 && ema_fast0 > ema_slow0)
      dir = "BULL";
   else if(close1 < ema_trend0 && ema_fast0 < ema_slow0)
      dir = "BEAR";

   double dd = 0.0;
   if(g_day_start_equity > 0.0)
      dd = (g_day_start_equity - AccountEquity()) / g_day_start_equity * 100.0;

   string sig = "none";
   if(signal == SIGNAL_BUY)
      sig = "BUY";
   if(signal == SIGNAL_SELL)
      sig = "SELL";

   Comment(
      "TrendConfluenceEA  |  ", Symbol(), " M", Period(), "\n",
      "Regime: ", dir, "   Signal: ", sig, "\n",
      "ADX: ", DoubleToString(adx0, 1),
      "   RSI: ", DoubleToString(rsi0, 1),
      "   ATR: ", DoubleToString(atr0, Digits), "\n",
      "Positions: ", IntegerToString(_CountPositions()), "/", IntegerToString(InpMaxPositions),
      "   Daily DD: ", DoubleToString(dd, 2), "%\n",
      "Status: ", g_last_reason
   );
  }
//+------------------------------------------------------------------+
