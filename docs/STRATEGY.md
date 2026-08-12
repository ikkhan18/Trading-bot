# Trend Confluence strategy

This Expert Advisor trades **with** the prevailing trend and waits for a **pullback** before entering. It does not try to pick tops and bottoms in a range.

No indicator set is “best” in all markets. This combination is a standard professional confluence stack: trend regime, trend strength, momentum, and volatility-based risk.

## Indicators

| Indicator | Default | Role |
|-----------|---------|------|
| EMA fast | 21 | Short-term trend / reclaim line |
| EMA slow | 55 | Intermediate trend alignment |
| EMA trend | 200 | Higher-regime filter (bull vs bear) |
| ADX + DI | 14 | Skip chop; require a real trend |
| RSI | 14 | Detect pullback and turn |
| MACD | 12 / 26 / 9 | Momentum confirmation |
| ATR | 14 | Stop, target, trail, and position size |

All signals are evaluated on the **last closed bar** so they do not repaint.

## Buy rules (all must be true)

1. Close is above the 200 EMA (bullish regime).
2. 21 EMA is above the 55 EMA (short-term aligned with the regime).
3. ADX is at or above `MinADX` (default 22).
4. +DI is above −DI (buyers dominate).
5. RSI on the previous closed bar was at or below `RsiBuyLevel` (pullback).
6. RSI turned up on the signal bar and is still below overbought.
7. MACD main is above its signal line and rising.
8. Signal bar is bullish and closes back above the 21 EMA.
9. Spread, session, daily-loss, and position-limit filters pass.

Sell rules are the inverse.

## Risk

- Position size is computed from **percent of equity** and the ATR stop distance.
- Stop loss = `SL_ATR_Mult × ATR`.
- Take profit = `TP_ATR_Mult × ATR`.
- After price moves `BreakEvenATR × ATR` in profit, the stop is moved to break-even plus a small offset.
- After `TrailStartATR × ATR` in profit, a trailing stop of `TrailATR × ATR` is applied.
- Trading pauses for the rest of the day if equity drawdown from the day’s start reaches `MaxDailyLossPercent`.

## Suggested starting point

Backtest first on **H1 or H4** for liquid FX majors (EURUSD, GBPUSD, USDJPY) and gold (XAUUSD). Defaults are conservative; optimize only a few inputs at a time (ADX threshold, RSI levels, ATR multiples) and always run a walk-forward / out-of-sample check.

Past performance is not a guarantee of future results.
