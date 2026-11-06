# data/

- `cache/` — Parquet baixado (não versionado; recriado por `run.py`).
- `reference/` — listas do universo (IBOV, S&P 500) com data de referência (versionadas).
- `reports/` — relatórios de qualidade dos dados por ativo (Etapa 2).

O código que gera estes arquivos fica em `src/quantbr/data/`.
