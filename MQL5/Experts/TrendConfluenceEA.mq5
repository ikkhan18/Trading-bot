//+------------------------------------------------------------------+
//|                                           TrendConfluenceEA.mq5  |
//|           Auto-trading Expert Advisor for MetaTrader 5           |
//|  Trend (EMA 21/55/200) + ADX + RSI pullback + MACD + ATR risk    |
//+------------------------------------------------------------------+
#property copyright "Trend Confluence EA"
#property version   "1.00"
#property description "Trend-following auto trader: EMA regime, ADX strength, RSI pullback, MACD momentum, ATR risk."
#property strict

#include <Trade/Trade.mqh>

enum ENUM_TRADE_SIGNAL
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

//------------------------------ Inputs --------------------------------
input group "=== Trade ==="
input ulong    InpMagic              = 180526;   // Magic number
input int      InpSlippagePoints     = 20;       // Max slippage (points)
input int      InpMaxPositions       = 1;        // Max open positions (this symbol)
input bool     InpCloseOnOpposite    = true;     // Close position on opposite signal
input bool     InpTradeOnNewBarOnly  = true;     // Evaluate only on a newly closed bar

input group "=== Risk ==="
input double   InpRiskPercent        = 1.0;      // Risk per trade (% of equity)
input double   InpFixedLots          = 0.0;      // Fixed lots (0 = use risk %)
input double   InpSL_ATR             = 1.5;      // Stop loss = ATR x this
input double   InpTP_ATR             = 2.5;      // Take profit = ATR x this
input double   InpBreakEvenATR       = 1.0;      // Move SL to BE after this ATR profit (0 = off)
input double   InpBreakEvenOffsetATR = 0.1;      // BE offset in ATR
input double   InpTrailStartATR      = 1.2;      // Start trailing after this ATR profit (0 = off)
input double   InpTrailATR           = 1.0;      // Trailing distance in ATR
input double   InpMaxDailyLossPct    = 4.0;      // Pause trading after this daily equity DD % (0 = off)

input group "=== Trend (EMA) ==="
input int      InpEmaFast            = 21;       // Fast EMA
input int      InpEmaSlow            = 55;       // Slow EMA
input int      InpEmaTrend           = 200;      // Regime EMA

input group "=== Strength / Momentum ==="
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

input group "=== Filters ==="
input int      InpMaxSpreadPoints    = 30;       // Max spread (points, 0 = off)
input bool     InpUseSessionFilter   = false;    // Limit trading hours (broker time)
input int      InpSessionStartHour   = 7;        // Session start hour
input int      InpSessionEndHour     = 21;       // Session end hour (exclusive)
input bool     InpSkipFridayLate     = true;     // Do not open trades after Friday 18:00
input bool     InpShowDashboard      = true;     // Chart comment dashboard

//------------------------------ State ---------------------------------
CTrade         g_trade;
int            g_ema_fast_h  = INVALID_HANDLE;
int            g_ema_slow_h  = INVALID_HANDLE;
int            g_ema_trend_h = INVALID_HANDLE;
int            g_adx_h       = INVALID_HANDLE;
int            g_rsi_h       = INVALID_HANDLE;
int            g_macd_h      = INVALID_HANDLE;
int            g_atr_h       = INVALID_HANDLE;
datetime       g_last_bar    = 0;
datetime       g_day_stamp   = 0;
double         g_day_start_equity = 0.0;
string         g_last_reason = "";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!_ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetAsyncMode(false);
   _SetFilling();

   g_ema_fast_h  = iMA(_Symbol, PERIOD_CURRENT, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_ema_slow_h  = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_ema_trend_h = iMA(_Symbol, PERIOD_CURRENT, InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   g_adx_h       = iADX(_Symbol, PERIOD_CURRENT, InpAdxPeriod);
   g_rsi_h       = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   g_macd_h      = iMACD(_Symbol, PERIOD_CURRENT, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
   g_atr_h       = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);

   if(g_ema_fast_h == INVALID_HANDLE || g_ema_slow_h == INVALID_HANDLE || g_ema_trend_h == INVALID_HANDLE ||
      g_adx_h == INVALID_HANDLE || g_rsi_h == INVALID_HANDLE || g_macd_h == INVALID_HANDLE || g_atr_h == INVALID_HANDLE)
     {
      Print("Failed to create indicator handles. Error ", GetLastError());
      return INIT_FAILED;
     }

   _ResetDay();
   Print("TrendConfluenceEA initialized on ", _Symbol, " ", EnumToString(_Period));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(g_ema_fast_h);
   IndicatorRelease(g_ema_slow_h);
   IndicatorRelease(g_ema_trend_h);
   IndicatorRelease(g_adx_h);
   IndicatorRelease(g_rsi_h);
   IndicatorRelease(g_macd_h);
   IndicatorRelease(g_atr_h);
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

   ENUM_TRADE_SIGNAL signal = _EvaluateSignal();
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
bool _ValidateInputs()
  {
   if(InpEmaFast < 2 || InpEmaSlow < 2 || InpEmaTrend < 2)
     {
      Print("EMA periods must be >= 2");
      return false;
     }
   if(InpEmaFast >= InpEmaSlow || InpEmaSlow >= InpEmaTrend)
     {
      Print("Require EmaFast < EmaSlow < EmaTrend");
      return false;
     }
   if(InpRiskPercent <= 0 && InpFixedLots <= 0)
     {
      Print("Set RiskPercent or FixedLots");
      return false;
     }
   if(InpSL_ATR <= 0 || InpTP_ATR <= 0)
     {
      Print("ATR multiples for SL/TP must be > 0");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void _SetFilling()
  {
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
bool _IsNewBar()
  {
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
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
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime stamp = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(stamp != g_day_stamp)
     {
      g_day_stamp = stamp;
      g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
     }
  }

//+------------------------------------------------------------------+
bool _CopyClosed(const int handle, const int buffer, const int count, double &out[])
  {
   ArraySetAsSeries(out, true);
   // shift 1 = last closed bar (no repaint)
   if(CopyBuffer(handle, buffer, 1, count, out) < count)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL _EvaluateSignal()
  {
   g_last_reason = "warmup";
   double ema_fast[], ema_slow[], ema_trend[];
   double adx_main[], plus_di[], minus_di[];
   double rsi_buf[], macd_main[], macd_sig[], atr_buf[];

   if(!_CopyClosed(g_ema_fast_h, 0, 3, ema_fast))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_ema_slow_h, 0, 3, ema_slow))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_ema_trend_h, 0, 3, ema_trend))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_adx_h, 0, 3, adx_main))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_adx_h, 1, 3, plus_di))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_adx_h, 2, 3, minus_di))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_rsi_h, 0, 3, rsi_buf))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_macd_h, 0, 3, macd_main))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_macd_h, 1, 3, macd_sig))
      return SIGNAL_NONE;
   if(!_CopyClosed(g_atr_h, 0, 3, atr_buf))
      return SIGNAL_NONE;

   double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   if(open1 <= 0 || close1 <= 0)
      return SIGNAL_NONE;

   if(adx_main[0] < InpMinAdx)
     {
      g_last_reason = "ADX too low (range)";
      return SIGNAL_NONE;
     }

   bool bull_regime = (close1 > ema_trend[0] && ema_fast[0] > ema_slow[0]);
   bool bear_regime = (close1 < ema_trend[0] && ema_fast[0] < ema_slow[0]);

   bool rsi_buy  = (rsi_buf[1] <= InpRsiBuyLevel && rsi_buf[0] > rsi_buf[1] && rsi_buf[0] < InpRsiOverbought);
   bool rsi_sell = (rsi_buf[1] >= InpRsiSellLevel && rsi_buf[0] < rsi_buf[1] && rsi_buf[0] > InpRsiOversold);

   bool macd_bull = (macd_main[0] > macd_sig[0] && macd_main[0] > macd_main[1]);
   bool macd_bear = (macd_main[0] < macd_sig[0] && macd_main[0] < macd_main[1]);

   bool bull_candle = InpRequireCandle ? (close1 > open1) : true;
   bool bear_candle = InpRequireCandle ? (close1 < open1) : true;
   bool reclaim     = InpRequireEmaReclaim ? (close1 > ema_fast[0]) : true;
   bool reject      = InpRequireEmaReclaim ? (close1 < ema_fast[0]) : true;
   bool di_buy      = InpUseAdxDiFilter ? (plus_di[0] > minus_di[0]) : true;
   bool di_sell     = InpUseAdxDiFilter ? (minus_di[0] > plus_di[0]) : true;

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
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      g_last_reason = "AutoTrading disabled";
      return false;
     }
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
      return false;

   if(InpMaxDailyLossPct > 0 && g_day_start_equity > 0)
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double dd = (g_day_start_equity - eq) / g_day_start_equity * 100.0;
      if(dd >= InpMaxDailyLossPct)
        {
         g_last_reason = "Daily loss limit";
         return false;
        }
     }

   if(InpMaxSpreadPoints > 0)
     {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints)
        {
         g_last_reason = "Spread too wide";
         return false;
        }
     }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpUseSessionFilter)
     {
      if(dt.hour < InpSessionStartHour || dt.hour >= InpSessionEndHour)
        {
         g_last_reason = "Outside session";
         return false;
        }
     }
   if(InpSkipFridayLate && dt.day_of_week == 5 && dt.hour >= 18)
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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
void _CloseOpposite(const ENUM_TRADE_SIGNAL signal)
  {
   ENUM_POSITION_TYPE unwanted = (signal == SIGNAL_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == unwanted)
         g_trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
double _NormalizeVolume(double lots)
  {
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0)
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
   if(InpFixedLots > 0)
      return _NormalizeVolume(InpFixedLots);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * InpRiskPercent / 100.0;
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0 || tick_value <= 0 || sl_distance <= 0)
      return 0;

   double loss_per_lot = (sl_distance / tick_size) * tick_value;
   if(loss_per_lot <= 0)
      return 0;
   return _NormalizeVolume(risk_money / loss_per_lot);
  }

//+------------------------------------------------------------------+
double _StopsLevelDistance()
  {
   int level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int pts = MathMax(level, freeze);
   return pts * _Point;
  }

//+------------------------------------------------------------------+
void _OpenTrade(const ENUM_TRADE_SIGNAL signal)
  {
   double atr_buf[];
   if(!_CopyClosed(g_atr_h, 0, 2, atr_buf) || atr_buf[0] <= 0)
     {
      Print("ATR unavailable, skip order");
      return;
     }

   double atr_val = atr_buf[0];
   double sl_dist = atr_val * InpSL_ATR;
   double tp_dist = atr_val * InpTP_ATR;
   double min_dist = _StopsLevelDistance();
   if(sl_dist < min_dist)
      sl_dist = min_dist;
   if(tp_dist < min_dist)
      tp_dist = min_dist;

   double lots = _LotsFromAtrStop(sl_dist);
   if(lots <= 0)
     {
      Print("Lot size is 0, skip order");
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string comment = "TrendConfluence";

   if(signal == SIGNAL_BUY)
     {
      double sl = NormalizeDouble(ask - sl_dist, digits);
      double tp = NormalizeDouble(ask + tp_dist, digits);
      if(!g_trade.Buy(lots, _Symbol, ask, sl, tp, comment))
         Print("Buy failed: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
     }
   else if(signal == SIGNAL_SELL)
     {
      double sl = NormalizeDouble(bid + sl_dist, digits);
      double tp = NormalizeDouble(bid - tp_dist, digits);
      if(!g_trade.Sell(lots, _Symbol, bid, sl, tp, comment))
         Print("Sell failed: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
void _ManageOpenPositions()
  {
   double atr_buf[];
   if(!_CopyClosed(g_atr_h, 0, 2, atr_buf) || atr_buf[0] <= 0)
      return;
   double atr_val = atr_buf[0];
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double min_dist = _StopsLevelDistance();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double new_sl = sl;

      if(type == POSITION_TYPE_BUY)
        {
         double profit = bid - entry;
         if(InpBreakEvenATR > 0 && profit >= InpBreakEvenATR * atr_val)
           {
            double be = entry + InpBreakEvenOffsetATR * atr_val;
            if(be > sl + _Point)
               new_sl = be;
           }
         if(InpTrailStartATR > 0 && profit >= InpTrailStartATR * atr_val)
           {
            double trail = bid - InpTrailATR * atr_val;
            if(trail > new_sl + _Point)
               new_sl = trail;
           }
         if(new_sl > 0 && bid - new_sl < min_dist)
            continue;
        }
      else
        {
         double profit = entry - ask;
         if(InpBreakEvenATR > 0 && profit >= InpBreakEvenATR * atr_val)
           {
            double be = entry - InpBreakEvenOffsetATR * atr_val;
            if(sl == 0 || be < sl - _Point)
               new_sl = be;
           }
         if(InpTrailStartATR > 0 && profit >= InpTrailStartATR * atr_val)
           {
            double trail = ask + InpTrailATR * atr_val;
            if(sl == 0 || trail < new_sl - _Point)
               new_sl = trail;
           }
         if(new_sl > 0 && new_sl - ask < min_dist)
            continue;
        }

      new_sl = NormalizeDouble(new_sl, digits);
      if(new_sl > 0 && MathAbs(new_sl - sl) > _Point)
         g_trade.PositionModify(ticket, new_sl, tp);
     }
  }

//+------------------------------------------------------------------+
void _Dashboard(const ENUM_TRADE_SIGNAL signal)
  {
   double ema_fast[], ema_slow[], ema_trend[], adx_main[], rsi_buf[], atr_buf[];
   _CopyClosed(g_ema_fast_h, 0, 1, ema_fast);
   _CopyClosed(g_ema_slow_h, 0, 1, ema_slow);
   _CopyClosed(g_ema_trend_h, 0, 1, ema_trend);
   _CopyClosed(g_adx_h, 0, 1, adx_main);
   _CopyClosed(g_rsi_h, 0, 1, rsi_buf);
   _CopyClosed(g_atr_h, 0, 1, atr_buf);

   string dir = "FLAT";
   if(ArraySize(ema_fast) > 0 && ArraySize(ema_slow) > 0 && ArraySize(ema_trend) > 0)
     {
      double c = iClose(_Symbol, PERIOD_CURRENT, 1);
      if(c > ema_trend[0] && ema_fast[0] > ema_slow[0])
         dir = "BULL";
      else if(c < ema_trend[0] && ema_fast[0] < ema_slow[0])
         dir = "BEAR";
     }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = 0;
   if(g_day_start_equity > 0)
      dd = (g_day_start_equity - eq) / g_day_start_equity * 100.0;

   string sig = "none";
   if(signal == SIGNAL_BUY)
      sig = "BUY";
   if(signal == SIGNAL_SELL)
      sig = "SELL";

   Comment(
      "TrendConfluenceEA  |  ", _Symbol, " ", EnumToString(_Period), "\n",
      "Regime: ", dir, "   Signal: ", sig, "\n",
      "ADX: ", DoubleToString(ArraySize(adx_main) ? adx_main[0] : 0, 1),
      "   RSI: ", DoubleToString(ArraySize(rsi_buf) ? rsi_buf[0] : 0, 1),
      "   ATR: ", DoubleToString(ArraySize(atr_buf) ? atr_buf[0] : 0, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), "\n",
      "Positions: ", IntegerToString(_CountPositions()), "/", IntegerToString(InpMaxPositions),
      "   Daily DD: ", DoubleToString(dd, 2), "%\n",
      "Status: ", g_last_reason
   );
  }
//+------------------------------------------------------------------+
