"""Trend confluence auto-trading engine for MetaTrader 4/5."""

from trend_confluence.risk import daily_loss_halted, lots_for_risk, stop_and_target
from trend_confluence.signals import Signal, StrategyParams, classify, evaluate

__all__ = [
    "Signal",
    "StrategyParams",
    "classify",
    "daily_loss_halted",
    "evaluate",
    "lots_for_risk",
    "stop_and_target",
]
