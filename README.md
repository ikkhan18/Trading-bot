# Trading bot (MT4 / MT5)

Runs **only inside MetaTrader** on your computer. No GitHub account, no website login, and no online connection is required for the Expert Advisor itself.

Auto-trading **Expert Advisor** for MetaTrader 4 and MetaTrader 5. It trades **with the trend**, waits for a **pullback**, then enters with ATR-based stops and position sizing.

This is not financial advice. No indicator mix is profitable in every market. Always **backtest**, then run on a **demo account**, before any live money.

## Strategy (short)

Entries need several conditions at once on the **last closed bar** (no repainting):

1. **Regime** — price vs 200 EMA, and 21 EMA vs 55 EMA
2. **Strength** — ADX high enough to skip chop; +DI / −DI agree with direction
3. **Pullback** — RSI dipped (buy) or rallied (sell), then turned back with the trend
4. **Momentum** — MACD line vs signal, and rising/falling
5. **Trigger** — directional candle that reclaims (buy) or rejects (sell) the 21 EMA

Risk:

- Lot size from **% of equity** and ATR stop distance (or fixed lots)
- Stop / take-profit / break-even / trailing stop from ATR
- Daily loss pause, spread filter, optional session hours, Friday late-entry skip

Full rules: [docs/STRATEGY.md](docs/STRATEGY.md)

## Install on MetaTrader 5

1. Open MT5 → **File → Open Data Folder**
2. Copy `MQL5/Experts/TrendConfluenceEA.mq5` into `MQL5/Experts/`
3. In Navigator, right-click **Expert Advisors** → **Refresh**
4. Open `TrendConfluenceEA` in MetaEditor and press **Compile** (F7)
5. Attach it to a chart (H1 or H4 is a sensible start)
6. Enable **Algo Trading** and allow live trading in the EA inputs

## Install on MetaTrader 4

1. Open MT4 → **File → Open Data Folder**
2. Copy `MQL4/Experts/TrendConfluenceEA.mq4` into `MQL4/Experts/`
3. Compile in MetaEditor (F7)
4. Attach to a chart, enable **AutoTrading**

## Suggested first setup

| Input | Starting value | Notes |
|-------|----------------|-------|
| Symbol | EURUSD, GBPUSD, USDJPY, XAUUSD | Liquid names only |
| Timeframe | H1 or H4 | Lower TFs need a tighter spread cap |
| RiskPercent | 0.5–1.0 | Keep small until you have a long demo sample |
| MinADX | 22 | Raise to trade less often / skip ranges |
| MaxDailyLossPct | 4 | Bot stops opening trades for the rest of the day |
| MaxSpreadPoints | 30 | Raise for gold / JPY; 5-digit FX often uses 10–20 |

Use **Strategy Tester** (every tick or 1-minute OHLC) over several years, then a later out-of-sample window. If you optimize, change only a few inputs at a time.

## Python twin (logic tests)

The same signal and risk math lives in `python/trend_confluence` so the rules can be unit-tested without MetaTrader:

```bash
cd python
pip install -r requirements.txt
pytest
```

## Files

```
MQL5/Experts/TrendConfluenceEA.mq5   # MT5 Expert Advisor
MQL4/Experts/TrendConfluenceEA.mq4   # MT4 Expert Advisor
python/trend_confluence/             # Shared strategy engine
docs/STRATEGY.md                     # Indicator and rule detail
```
