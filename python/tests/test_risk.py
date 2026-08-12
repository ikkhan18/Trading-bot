from trend_confluence.risk import daily_loss_halted, lots_for_risk, normalize_volume, stop_and_target


def test_lots_for_risk_matches_manual_math():
    # $10,000, 1% risk = $100. 100-pip stop at $1/pip/lot => 1.00 lot
    lots = lots_for_risk(
        equity=10_000,
        risk_percent=1.0,
        stop_distance=0.0100,
        tick_size=0.0001,
        tick_value=1.0,
    )
    assert lots == 1.0


def test_lots_are_stepped_and_clamped():
    assert normalize_volume(0.1234) == 0.12
    assert normalize_volume(0.001) == 0.01
    assert normalize_volume(500) == 100.0


def test_daily_loss_halt():
    assert daily_loss_halted(10_000, 9_400, 5.0) is True
    assert daily_loss_halted(10_000, 9_600, 5.0) is False
    assert daily_loss_halted(10_000, 10_500, 5.0) is False


def test_stop_and_target_buy_and_sell():
    sl, tp = stop_and_target(1.2000, 0.0010, sl_mult=1.5, tp_mult=2.5, is_buy=True)
    assert abs(sl - 1.1985) < 1e-12
    assert abs(tp - 1.2025) < 1e-12
    sl, tp = stop_and_target(1.2000, 0.0010, sl_mult=1.5, tp_mult=2.5, is_buy=False)
    assert abs(sl - 1.2015) < 1e-12
    assert abs(tp - 1.1975) < 1e-12
