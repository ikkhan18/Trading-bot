import numpy as np

from trend_confluence.indicators import adx, atr, ema, macd, rsi


def test_ema_of_constant_series_is_constant():
    values = np.full(50, 1.2345)
    result = ema(values, 21)
    assert np.allclose(result, 1.2345)


def test_rsi_of_strict_uptrend_approaches_100():
    close = np.linspace(1.0, 2.0, 80)
    values = rsi(close, 14)
    assert values[-1] > 90


def test_rsi_of_strict_downtrend_approaches_0():
    close = np.linspace(2.0, 1.0, 80)
    values = rsi(close, 14)
    assert values[-1] < 10


def test_atr_positive_on_volatile_series():
    rng = np.random.default_rng(0)
    close = 1.10 + np.cumsum(rng.normal(0, 0.001, 100))
    high = close + 0.0008
    low = close - 0.0008
    values = atr(high, low, close, 14)
    assert np.nanmin(values[20:]) > 0


def test_macd_zero_on_flat_market():
    close = np.full(80, 1.25)
    main, signal, hist = macd(close)
    assert np.allclose(main[40:], 0.0, atol=1e-12)
    assert np.allclose(signal[40:], 0.0, atol=1e-12)
    assert np.allclose(hist[40:], 0.0, atol=1e-12)


def test_adx_high_in_persistent_trend():
    n = 120
    close = np.linspace(1.0, 1.4, n)
    high = close + 0.002
    low = close - 0.001
    adx_line, plus_di, minus_di = adx(high, low, close, 14)
    assert adx_line[-1] > 40
    assert plus_di[-1] > minus_di[-1]
