"""Position sizing and daily-loss halt (mirrors the Expert Advisors)."""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass(frozen=True)
class VolumeSpec:
    min_lot: float = 0.01
    max_lot: float = 100.0
    lot_step: float = 0.01


def normalize_volume(lots: float, spec: VolumeSpec | None = None) -> float:
    spec = spec or VolumeSpec()
    if spec.lot_step <= 0:
        raise ValueError("lot_step must be > 0")
    lots = math.floor(lots / spec.lot_step + 1e-12) * spec.lot_step
    lots = max(spec.min_lot, min(spec.max_lot, lots))
    return round(lots, 8)


def lots_for_risk(
    equity: float,
    risk_percent: float,
    stop_distance: float,
    tick_size: float,
    tick_value: float,
    spec: VolumeSpec | None = None,
) -> float:
    """Lots such that a stop-out loses approximately risk_percent of equity."""
    if equity <= 0 or risk_percent <= 0 or stop_distance <= 0 or tick_size <= 0 or tick_value <= 0:
        return 0.0
    risk_money = equity * (risk_percent / 100.0)
    loss_per_lot = (stop_distance / tick_size) * tick_value
    if loss_per_lot <= 0:
        return 0.0
    return normalize_volume(risk_money / loss_per_lot, spec)


def daily_loss_halted(day_start_equity: float, current_equity: float, max_daily_loss_percent: float) -> bool:
    if day_start_equity <= 0 or max_daily_loss_percent <= 0:
        return False
    drawdown_pct = (day_start_equity - current_equity) / day_start_equity * 100.0
    return drawdown_pct >= max_daily_loss_percent


def stop_and_target(entry: float, atr_value: float, sl_mult: float, tp_mult: float, is_buy: bool) -> tuple[float, float]:
    if atr_value <= 0:
        raise ValueError("atr_value must be > 0")
    sl_dist = atr_value * sl_mult
    tp_dist = atr_value * tp_mult
    if is_buy:
        return entry - sl_dist, entry + tp_dist
    return entry + sl_dist, entry - tp_dist
