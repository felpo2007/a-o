"""Ponto de entrada único do pipeline.

Uso:
    python run.py --check-env              # checa Python, dependências e diretórios
    python run.py --check-env --network    # idem + testa as fontes de dados
    python run.py --universe mvp           # pipeline completo (implementado na Etapa 1)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Permite rodar `python run.py` sem instalar o pacote (fallback do `uv run`).
sys.path.insert(0, str(Path(__file__).resolve().parent / "src"))

from quantbr import __version__  # noqa: E402
from quantbr.config import load_config  # noqa: E402
from quantbr.envcheck import all_required_ok, format_checks, run_checks  # noqa: E402

IMPLEMENTED_UNIVERSES: set[str] = set()  # preenchido a partir da Etapa 1


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Estratégias IBOV + S&P 500 e modelo GOOGL")
    p.add_argument("--version", action="version", version=f"quantbr {__version__}")
    p.add_argument("--check-env", action="store_true", help="checa o ambiente e sai")
    p.add_argument("--network", action="store_true", help="com --check-env, testa também as fontes de dados")
    p.add_argument("--universe", choices=["mvp", "full"], help="roda o pipeline para o universo escolhido")
    p.add_argument("--config", default=None, help="caminho alternativo do TOML de configuração")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cfg = load_config(args.config)

    if args.check_env:
        checks = run_checks(network=args.network)
        print(format_checks(checks))
        ok = all_required_ok(checks)
        print("\nAmbiente OK." if ok else "\nAmbiente com falhas obrigatórias.")
        return 0 if ok else 1

    if args.universe:
        if args.universe not in IMPLEMENTED_UNIVERSES:
            print(f"Universo '{args.universe}' ainda não implementado (pipeline entra na Etapa 1). "
                  f"Capital assumido: R$ {cfg['context']['capital_inicial_brl']:,}.")
            return 2
        raise NotImplementedError  # substituído na Etapa 1

    build_parser().print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
