import numpy as np

from trend_confluence.signals import Signal, StrategyParams, classify, evaluate


def _ohlc_from_close(close: np.ndarray, wick: float = 0.0004) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    open_ = np.roll(close, 1)
    open_[0] = close[0]
    high = np.maximum(open_, close) + wick
    low = np.minimum(open_, close) - wick
    return open_, high, low, close


def _buy_kwargs(**overrides):
    values = dict(
        open_px=1.1000,
        close=1.1015,
        ema_fast=1.1008,
        ema_slow=1.0990,
        ema_trend=1.0900,
        adx=28.0,
        plus_di=30.0,
        minus_di=18.0,
        rsi=42.0,
        rsi_prev=38.0,
        macd_main=0.0004,
        macd_main_prev=0.0002,
        macd_signal=0.0001,
    )
    values.update(overrides)
    return values


def _sell_kwargs(**overrides):
    values = dict(
        open_px=1.1015,
        close=1.1000,
        ema_fast=1.1008,
        ema_slow=1.1020,
        ema_trend=1.1100,
        adx=28.0,
        plus_di=18.0,
        minus_di=30.0,
        rsi=58.0,
        rsi_prev=62.0,
        macd_main=-0.0004,
        macd_main_prev=-0.0002,
        macd_signal=-0.0001,
    )
    values.update(overrides)
    return values


def test_classify_buy_when_all_confluence_aligns():
    assert classify(**_buy_kwargs()) == Signal.BUY


def test_classify_sell_when_all_confluence_aligns():
    assert classify(**_sell_kwargs()) == Signal.SELL


def test_classify_skips_low_adx_chop():
    assert classify(**_buy_kwargs(adx=12.0)) == Signal.NONE


def test_classify_skips_buy_when_rsi_already_overbought():
    assert classify(**_buy_kwargs(rsi=72.0, rsi_prev=40.0)) == Signal.NONE


def test_classify_skips_buy_without_rsi_pullback():
    assert classify(**_buy_kwargs(rsi=52.0, rsi_prev=50.0)) == Signal.NONE


def test_ranging_market_does_not_force_trades():
    x = np.arange(260)
    close = 1.20 + 0.002 * np.sin(x / 4.0)
    open_, high, low, close = _ohlc_from_close(close, wick=0.0002)
    snaps = evaluate(open_, high, low, close, StrategyParams(min_adx=25.0))
    trades = [s for s in snaps if s.signal != Signal.NONE]
    assert len(trades) == 0


def test_warmup_bars_have_no_signal():
    close = np.linspace(1.0, 1.05, 40)
    open_, high, low, close = _ohlc_from_close(close)
    snaps = evaluate(open_, high, low, close)
    assert all(s.signal == Signal.NONE for s in snaps)
