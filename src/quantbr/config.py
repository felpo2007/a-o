"""Carrega a configuração (config/default.toml) e os segredos (.env)."""

from __future__ import annotations

import os
import tomllib
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

from quantbr.paths import DEFAULT_CONFIG, ROOT

VALID_VENUES = {"corretora_eua", "bdr_b3", "indefinido"}
VALID_FREQUENCIES = {"diaria", "semanal", "mensal"}


class ConfigError(ValueError):
    """Configuração inválida."""


def load_config(path: Path | str | None = None) -> dict[str, Any]:
    """Lê o TOML de configuração e valida os campos essenciais."""
    p = Path(path) if path else DEFAULT_CONFIG
    with p.open("rb") as f:
        cfg = tomllib.load(f)
    validate_config(cfg)
    return cfg


def validate_config(cfg: dict[str, Any]) -> None:
    ctx = cfg["context"]
    if ctx["capital_inicial_brl"] <= 0:
        raise ConfigError("capital_inicial_brl deve ser > 0")
    if ctx["venue"] not in VALID_VENUES:
        raise ConfigError(f"venue deve ser um de {sorted(VALID_VENUES)}")
    if not 0 < ctx["max_drawdown_pct"] < 100:
        raise ConfigError("max_drawdown_pct deve estar entre 0 e 100")
    if ctx["max_frequencia"] not in VALID_FREQUENCIES:
        raise ConfigError(f"max_frequencia deve ser um de {sorted(VALID_FREQUENCIES)}")

    for market in ("b3", "us"):
        c = cfg["costs"][market]
        if not (0 <= c["commission"] < 0.01 and 0 <= c["slippage"] < 0.01):
            raise ConfigError(f"custos de {market} fora de faixa plausível (< 1% por lado)")

    bt = cfg["backtest"]
    if bt["train_years"] < 1 or bt["test_years"] < 1:
        raise ConfigError("janelas do walk-forward devem ter >= 1 ano")
    if not 0 < bt["max_adv_participation"] <= 0.1:
        raise ConfigError("max_adv_participation deve estar em (0, 0.1]")
    if bt["max_param_combos"] > 20:
        raise ConfigError("a SPEC limita a grade a ~20 combinações por estratégia")


def round_trip_cost(cfg: dict[str, Any], market: str, stress: bool = False) -> float:
    """Custo total de ida e volta (2 lados x (corretagem + slippage))."""
    c = cfg["costs"][market]
    mult = cfg["costs"]["stress_multiplier"] if stress else 1.0
    return 2 * (c["commission"] + c["slippage"]) * mult


def load_secrets(env_file: Path | str | None = None) -> None:
    """Carrega variáveis do .env (se existir) sem sobrescrever o ambiente."""
    load_dotenv(Path(env_file) if env_file else ROOT / ".env", override=False)


def get_secret(name: str) -> str | None:
    """Lê um segredo do ambiente. Nunca guarde chaves no código."""
    value = os.environ.get(name)
    return value or None
