"""Trend-confluence signal engine (mirrors the MT4/MT5 Expert Advisors)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum

import numpy as np

from trend_confluence.indicators import adx, atr, ema, macd, rsi


class Signal(IntEnum):
    SELL = -1
    NONE = 0
    BUY = 1


@dataclass(frozen=True)
class StrategyParams:
    ema_fast: int = 21
    ema_slow: int = 55
    ema_trend: int = 200
    adx_period: int = 14
    min_adx: float = 22.0
    rsi_period: int = 14
    rsi_buy_level: float = 45.0
    rsi_sell_level: float = 55.0
    rsi_overbought: float = 70.0
    rsi_oversold: float = 30.0
    macd_fast: int = 12
    macd_slow: int = 26
    macd_signal: int = 9
    atr_period: int = 14
    use_adx_di_filter: bool = True
    require_bullish_candle: bool = True
    require_ema_reclaim: bool = True


@dataclass(frozen=True)
class BarSnapshot:
    signal: Signal
    close: float
    ema_fast: float
    ema_slow: float
    ema_trend: float
    adx: float
    plus_di: float
    minus_di: float
    rsi: float
    macd_main: float
    macd_signal: float
    atr: float


def evaluate(open_: np.ndarray, high: np.ndarray, low: np.ndarray, close: np.ndarray, params: StrategyParams | None = None) -> list[BarSnapshot]:
    """Evaluate the strategy on chronological OHLC arrays (oldest first)."""
    params = params or StrategyParams()
    close = np.asarray(close, dtype=float)
    open_ = np.asarray(open_, dtype=float)
    high = np.asarray(high, dtype=float)
    low = np.asarray(low, dtype=float)
    n = close.size

    ema_fast = ema(close, params.ema_fast)
    ema_slow = ema(close, params.ema_slow)
    ema_trend = ema(close, params.ema_trend)
    adx_line, plus_di, minus_di = adx(high, low, close, params.adx_period)
    rsi_line = rsi(close, params.rsi_period)
    macd_main, macd_sig, _ = macd(close, params.macd_fast, params.macd_slow, params.macd_signal)
    atr_line = atr(high, low, close, params.atr_period)

    snapshots: list[BarSnapshot] = []
    for i in range(n):
        signal = Signal.NONE
        if i >= 1 and _ready(i, ema_fast, ema_slow, ema_trend, adx_line, rsi_line, macd_main, macd_sig, atr_line):
            signal = _signal_at(
                i,
                open_,
                close,
                ema_fast,
                ema_slow,
                ema_trend,
                adx_line,
                plus_di,
                minus_di,
                rsi_line,
                macd_main,
                macd_sig,
                params,
            )
        snapshots.append(
            BarSnapshot(
                signal=signal,
                close=float(close[i]),
                ema_fast=float(ema_fast[i]),
                ema_slow=float(ema_slow[i]),
                ema_trend=float(ema_trend[i]),
                adx=float(adx_line[i]),
                plus_di=float(plus_di[i]),
                minus_di=float(minus_di[i]),
                rsi=float(rsi_line[i]),
                macd_main=float(macd_main[i]),
                macd_signal=float(macd_sig[i]),
                atr=float(atr_line[i]),
            )
        )
    return snapshots


def _ready(i: int, *series: np.ndarray) -> bool:
    return all(not np.isnan(s[i]) and not np.isnan(s[i - 1]) for s in series)


def classify(
    *,
    open_px: float,
    close: float,
    ema_fast: float,
    ema_slow: float,
    ema_trend: float,
    adx: float,
    plus_di: float,
    minus_di: float,
    rsi: float,
    rsi_prev: float,
    macd_main: float,
    macd_main_prev: float,
    macd_signal: float,
    params: StrategyParams | None = None,
) -> Signal:
    """Apply confluence rules to a single closed bar (same logic as the EAs)."""
    params = params or StrategyParams()
    if adx < params.min_adx:
        return Signal.NONE

    bull_regime = close > ema_trend and ema_fast > ema_slow
    bear_regime = close < ema_trend and ema_fast < ema_slow

    rsi_buy_pullback = rsi_prev <= params.rsi_buy_level and rsi > rsi_prev and rsi < params.rsi_overbought
    rsi_sell_pullback = rsi_prev >= params.rsi_sell_level and rsi < rsi_prev and rsi > params.rsi_oversold

    macd_bull = macd_main > macd_signal and macd_main > macd_main_prev
    macd_bear = macd_main < macd_signal and macd_main < macd_main_prev

    bull_candle = close > open_px if params.require_bullish_candle else True
    bear_candle = close < open_px if params.require_bullish_candle else True
    reclaim_fast = close > ema_fast if params.require_ema_reclaim else True
    reject_fast = close < ema_fast if params.require_ema_reclaim else True

    di_buy = plus_di > minus_di if params.use_adx_di_filter else True
    di_sell = minus_di > plus_di if params.use_adx_di_filter else True

    if bull_regime and rsi_buy_pullback and macd_bull and bull_candle and reclaim_fast and di_buy:
        return Signal.BUY
    if bear_regime and rsi_sell_pullback and macd_bear and bear_candle and reject_fast and di_sell:
        return Signal.SELL
    return Signal.NONE


def _signal_at(
    i: int,
    open_: np.ndarray,
    close: np.ndarray,
    ema_fast: np.ndarray,
    ema_slow: np.ndarray,
    ema_trend: np.ndarray,
    adx_line: np.ndarray,
    plus_di: np.ndarray,
    minus_di: np.ndarray,
    rsi_line: np.ndarray,
    macd_main: np.ndarray,
    macd_sig: np.ndarray,
    params: StrategyParams,
) -> Signal:
    return classify(
        open_px=float(open_[i]),
        close=float(close[i]),
        ema_fast=float(ema_fast[i]),
        ema_slow=float(ema_slow[i]),
        ema_trend=float(ema_trend[i]),
        adx=float(adx_line[i]),
        plus_di=float(plus_di[i]),
        minus_di=float(minus_di[i]),
        rsi=float(rsi_line[i]),
        rsi_prev=float(rsi_line[i - 1]),
        macd_main=float(macd_main[i]),
        macd_main_prev=float(macd_main[i - 1]),
        macd_signal=float(macd_sig[i]),
        params=params,
    )
