import copy

import pytest

from quantbr.config import ConfigError, get_secret, load_secrets, round_trip_cost, validate_config


def test_spec_costs(cfg):
    # SPEC: B3 0,05% por lado + 0,05% slippage; EUA 0,01% + 0,02%; também 2x custos.
    assert cfg["costs"]["b3"] == {"commission": 0.0005, "slippage": 0.0005}
    assert cfg["costs"]["us"] == {"commission": 0.0001, "slippage": 0.0002}
    assert cfg["costs"]["stress_multiplier"] == 2.0


def test_round_trip_cost(cfg):
    assert round_trip_cost(cfg, "b3") == pytest.approx(0.002)
    assert round_trip_cost(cfg, "us") == pytest.approx(0.0006)
    assert round_trip_cost(cfg, "b3", stress=True) == pytest.approx(0.004)


def test_spec_backtest_rules(cfg):
    bt = cfg["backtest"]
    assert bt["signal_at"] == "close_t" and bt["execute_at"] == "open_t+1"
    assert bt["long_flat"] is True
    assert (bt["train_years"], bt["test_years"]) == (5, 1)
    assert bt["max_adv_participation"] == 0.01
    assert bt["max_param_combos"] <= 20


def test_spec_validation_and_googl(cfg):
    v = cfg["validation"]
    assert v["min_trades"] == 30 and v["dsr_threshold"] == 0.95
    assert v["random_strategies"] == 1000 and v["random_percentile"] == 0.95
    assert cfg["googl"]["holdout_months"] == 24
    assert cfg["data"]["start"] == "2010-01-01"
    assert cfg["data"]["min_oos_years"] == 3


def test_context_assumptions_are_filled(cfg):
    ctx = cfg["context"]
    for key in ("capital_inicial_brl", "venue", "max_drawdown_pct", "max_frequencia",
                "tempo_diario_min", "horizonte_anos"):
        assert ctx[key] not in (None, ""), key


@pytest.mark.parametrize(
    "path, value",
    [
        (("context", "venue"), "nasdaq_direto"),
        (("context", "max_drawdown_pct"), 0),
        (("context", "max_frequencia"), "intraday"),
        (("costs", "b3", "commission"), 0.05),
        (("backtest", "max_param_combos"), 50),
    ],
)
def test_invalid_config_is_rejected(cfg, path, value):
    bad = copy.deepcopy(cfg)
    node = bad
    for k in path[:-1]:
        node = node[k]
    node[path[-1]] = value
    with pytest.raises(ConfigError):
        validate_config(bad)


def test_secrets_come_from_env_file(tmp_path, monkeypatch):
    monkeypatch.delenv("QUANTBR_TEST_KEY", raising=False)
    env = tmp_path / ".env"
    env.write_text("QUANTBR_TEST_KEY=abc123\n")
    load_secrets(env)
    assert get_secret("QUANTBR_TEST_KEY") == "abc123"
    assert get_secret("QUANTBR_MISSING_KEY") is None
