"""Caminhos do repositório, resolvidos a partir da localização deste arquivo."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

CONFIG_DIR = ROOT / "config"
DEFAULT_CONFIG = CONFIG_DIR / "default.toml"

DATA_DIR = ROOT / "data"
CACHE_DIR = DATA_DIR / "cache"          # Parquet baixado (não versionado)
REFERENCE_DIR = DATA_DIR / "reference"  # listas de universo com data de referência
REPORTS_DIR = DATA_DIR / "reports"      # relatórios de qualidade dos dados

MODELS_DIR = ROOT / "models"
GOOGL_MODEL_DIR = MODELS_DIR / "googl"

SITE_DIR = ROOT / "site"                # saída do site estático gerado
LIVE_DIR = ROOT / "live"                # logs e estado da operação

WRITABLE_DIRS = (CACHE_DIR, REFERENCE_DIR, REPORTS_DIR, GOOGL_MODEL_DIR, SITE_DIR, LIVE_DIR)


def ensure_dirs() -> None:
    """Cria os diretórios de dados/saída, se ainda não existirem."""
    for d in WRITABLE_DIRS:
        d.mkdir(parents=True, exist_ok=True)
