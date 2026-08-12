"""Wilder / MetaTrader-style technical indicators."""

from __future__ import annotations

import numpy as np


def ema(values: np.ndarray, period: int) -> np.ndarray:
    """Exponential moving average, alpha = 2 / (period + 1)."""
    if period < 1:
        raise ValueError("period must be >= 1")
    values = np.asarray(values, dtype=float)
    out = np.full_like(values, np.nan, dtype=float)
    if values.size == 0:
        return out
    alpha = 2.0 / (period + 1.0)
    start = 0
    while start < values.size and np.isnan(values[start]):
        start += 1
    if start >= values.size:
        return out
    out[start] = values[start]
    for i in range(start + 1, values.size):
        if np.isnan(values[i]):
            out[i] = out[i - 1]
        else:
            out[i] = alpha * values[i] + (1.0 - alpha) * out[i - 1]
    return out


def _rma(values: np.ndarray, period: int) -> np.ndarray:
    """Wilder moving average (SMMA / RMA) used by RSI, ATR, and ADX."""
    values = np.asarray(values, dtype=float)
    out = np.full_like(values, np.nan, dtype=float)
    if values.size < period:
        return out
    seed = np.nanmean(values[:period])
    out[period - 1] = seed
    for i in range(period, values.size):
        out[i] = (out[i - 1] * (period - 1) + values[i]) / period
    return out


def rsi(close: np.ndarray, period: int = 14) -> np.ndarray:
    close = np.asarray(close, dtype=float)
    out = np.full_like(close, np.nan, dtype=float)
    if close.size < period + 1:
        return out
    delta = np.diff(close, prepend=np.nan)
    gain = np.where(delta > 0, delta, 0.0)
    loss = np.where(delta < 0, -delta, 0.0)
    gain[0] = np.nan
    loss[0] = np.nan
    avg_gain = _rma(gain[1:], period)
    avg_loss = _rma(loss[1:], period)
    avg_gain = np.concatenate(([np.nan], avg_gain))
    avg_loss = np.concatenate(([np.nan], avg_loss))
    rs = np.divide(avg_gain, avg_loss, out=np.full_like(avg_gain, np.nan), where=avg_loss > 0)
    out = 100.0 - (100.0 / (1.0 + rs))
    out = np.where(avg_loss == 0, np.where(avg_gain > 0, 100.0, 50.0), out)
    return out


def true_range(high: np.ndarray, low: np.ndarray, close: np.ndarray) -> np.ndarray:
    high = np.asarray(high, dtype=float)
    low = np.asarray(low, dtype=float)
    close = np.asarray(close, dtype=float)
    prev_close = np.roll(close, 1)
    prev_close[0] = close[0]
    tr = np.maximum(high - low, np.maximum(np.abs(high - prev_close), np.abs(low - prev_close)))
    tr[0] = high[0] - low[0]
    return tr


def atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> np.ndarray:
    return _rma(true_range(high, low, close), period)


def macd(
    close: np.ndarray,
    fast: int = 12,
    slow: int = 26,
    signal: int = 9,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    close = np.asarray(close, dtype=float)
    macd_main = ema(close, fast) - ema(close, slow)
    macd_signal = ema(macd_main, signal)
    hist = macd_main - macd_signal
    return macd_main, macd_signal, hist


def adx(
    high: np.ndarray,
    low: np.ndarray,
    close: np.ndarray,
    period: int = 14,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Returns (adx, plus_di, minus_di)."""
    high = np.asarray(high, dtype=float)
    low = np.asarray(low, dtype=float)
    close = np.asarray(close, dtype=float)
    n = close.size
    plus_dm = np.zeros(n)
    minus_dm = np.zeros(n)
    for i in range(1, n):
        up = high[i] - high[i - 1]
        down = low[i - 1] - low[i]
        plus_dm[i] = up if up > down and up > 0 else 0.0
        minus_dm[i] = down if down > up and down > 0 else 0.0
    tr = true_range(high, low, close)
    atr_w = _rma(tr, period)
    plus_di = 100.0 * _rma(plus_dm, period) / atr_w
    minus_di = 100.0 * _rma(minus_dm, period) / atr_w
    dx = 100.0 * np.abs(plus_di - minus_di) / (plus_di + minus_di)
    dx = np.where((plus_di + minus_di) == 0, 0.0, dx)
    adx_line = _rma(dx, period)
    return adx_line, plus_di, minus_di
