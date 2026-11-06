"""Checagem do ambiente: Python, dependências, diretórios e (opcional) fontes de dados."""

from __future__ import annotations

import importlib
import os
import sys
import tempfile
from dataclasses import dataclass

from quantbr import paths

MIN_PYTHON = (3, 11)

# módulo importável -> nome do pacote (para mensagens)
REQUIRED_MODULES = {
    "numpy": "numpy",
    "pandas": "pandas",
    "pyarrow": "pyarrow",
    "scipy": "scipy",
    "yfinance": "yfinance",
    "pandas_market_calendars": "pandas-market-calendars",
    "vectorbt": "vectorbt",
    "requests": "requests",
    "dotenv": "python-dotenv",
    "jinja2": "jinja2",
}

# Fontes de dados usadas nas próximas etapas.
B3_IBOV_PORTFOLIO_URL = (
    "https://sistemaswebb3-listados.b3.com.br/indexProxy/indexCall/GetPortfolioDay/"
    "eyJsYW5ndWFnZSI6InB0LWJyIiwicGFnZU51bWJlciI6MSwicGFnZVNpemUiOjEyMCwiaW5kZXgiOiJJQk9WIiwic2VnbWVudCI6IjEifQ=="
)
B3_COTAHIST_URL = "https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A2024.ZIP"
SP500_LIST_URL = "https://en.wikipedia.org/wiki/List_of_S%26P_500_companies"


@dataclass
class Check:
    name: str
    ok: bool
    detail: str
    required: bool = True


def check_python() -> Check:
    v = sys.version_info
    ok = (v.major, v.minor) >= MIN_PYTHON
    return Check("python", ok, f"{v.major}.{v.minor}.{v.micro} (mínimo {MIN_PYTHON[0]}.{MIN_PYTHON[1]})")


def check_modules() -> list[Check]:
    out = []
    for mod, pkg in REQUIRED_MODULES.items():
        try:
            m = importlib.import_module(mod)
            out.append(Check(pkg, True, getattr(m, "__version__", "ok")))
        except Exception as e:  # noqa: BLE001 — queremos reportar qualquer falha de import
            out.append(Check(pkg, False, f"{type(e).__name__}: {e}"))
    return out


def check_dirs() -> list[Check]:
    paths.ensure_dirs()
    out = []
    for d in paths.WRITABLE_DIRS:
        try:
            with tempfile.NamedTemporaryFile(dir=d, delete=True):
                pass
            out.append(Check(f"dir {d.relative_to(paths.ROOT)}", True, "gravável"))
        except OSError as e:
            out.append(Check(f"dir {d.relative_to(paths.ROOT)}", False, str(e)))
    return out


def check_env_file() -> Check:
    exists = (paths.ROOT / ".env").exists()
    detail = "encontrado" if exists else "ausente (só necessário a partir da Etapa 7; veja .env.example)"
    return Check(".env", exists, detail, required=False)


def _http_check(name: str, url: str, method: str = "GET", timeout: float = 20) -> Check:
    import requests

    try:
        headers = {"User-Agent": "quantbr-envcheck"}
        r = requests.request(method, url, timeout=timeout, stream=True, headers=headers)
        r.close()
        return Check(name, r.status_code < 400, f"HTTP {r.status_code}", required=False)
    except Exception as e:  # noqa: BLE001
        return Check(name, False, f"{type(e).__name__}: {e}", required=False)


def check_yfinance(ticker: str = "GOOGL") -> Check:
    try:
        import yfinance as yf

        df = yf.download(ticker, period="5d", auto_adjust=False, progress=False, threads=False)
        ok = not df.empty
        detail = f"{len(df)} pregões recebidos" if ok else "resposta vazia"
        return Check(f"yfinance {ticker}", ok, detail, required=False)
    except Exception as e:  # noqa: BLE001
        return Check(f"yfinance {ticker}", False, f"{type(e).__name__}: {e}", required=False)


def check_network() -> list[Check]:
    return [
        check_yfinance("GOOGL"),
        check_yfinance("PETR4.SA"),
        _http_check("B3 carteira IBOV", B3_IBOV_PORTFOLIO_URL),
        _http_check("B3 COTAHIST", B3_COTAHIST_URL, method="HEAD"),
        _http_check("Lista S&P 500 (Wikipedia)", SP500_LIST_URL),
    ]


def run_checks(network: bool = False) -> list[Check]:
    checks = [check_python(), *check_modules(), *check_dirs(), check_env_file()]
    if network:
        checks += check_network()
    return checks


def format_checks(checks: list[Check]) -> str:
    lines = []
    for c in checks:
        mark = "OK " if c.ok else ("FALHA" if c.required else "aviso")
        lines.append(f"[{mark:5}] {c.name:32} {c.detail}")
    return os.linesep.join(lines)


def all_required_ok(checks: list[Check]) -> bool:
    return all(c.ok for c in checks if c.required)
