# a-o — estratégias IBOV + S&P 500 e modelo GOOGL

Estudo educacional de estratégias de trade para as ações do **Ibovespa** e do **S&P 500**, com
validação fora da amostra, e um **modelo dedicado para GOOGL** (paper trading antes de real).
A especificação completa está em [SPEC.md](SPEC.md); o andamento, em [PROGRESS.md](PROGRESS.md);
as suposições, em [ASSUMPTIONS.md](ASSUMPTIONS.md).

> Estudo educacional, não é recomendação de investimento. Resultados passados não garantem
> resultados futuros.

## Instalação

Requisitos: **Python 3.11+** (o projeto fixa 3.12 em `.python-version`), **git** e **uv**.

1. Instale o uv (gerenciador de ambiente e dependências):
   - macOS / Linux: `curl -LsSf https://astral.sh/uv/install.sh | sh`
   - Windows (PowerShell): `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`
2. Baixe o projeto e crie o ambiente com as versões exatas do `uv.lock`:
   ```bash
   git clone https://github.com/felpo2007/a-o.git
   cd a-o
   uv sync --locked
   ```
   O uv baixa o Python 3.12 sozinho se ele não estiver instalado.
3. Confira o ambiente:
   ```bash
   uv run python run.py --check-env            # Python, dependências e pastas
   uv run python run.py --check-env --network  # idem + yfinance, B3 e lista do S&P 500
   ```
4. Rode os testes:
   ```bash
   uv run pytest                          # testes offline
   RUN_NETWORK_TESTS=1 uv run pytest      # inclui testes que acessam a internet
   ```
   No Windows (PowerShell): `$env:RUN_NETWORK_TESTS=1; uv run pytest`.
5. Segredos (só a partir da Etapa 7 — alertas e paper trading): copie `.env.example` para `.env`
   e preencha. O `.env` está no `.gitignore`; nunca coloque chaves no código.

**Sem uv (alternativa):** `python -m venv .venv`, ative o ambiente e rode `pip install -e .` e
`pip install pytest ruff`. Funciona, mas não garante as mesmas versões do `uv.lock`.

## Continuar no Claude Code

Abra o Claude Code (claude.ai/code ou app), escolha o repositório `felpo2007/a-o` e envie:

> Execute a próxima etapa pendente do PROGRESS.md seguindo o CLAUDE.md.

O `CLAUDE.md` traz as regras de trabalho (uma etapa por sessão, testes, commit e push).

## Uso

```bash
uv run python run.py --universe mvp    # pipeline completo do MVP (disponível a partir da Etapa 1)
uv run python run.py --universe full   # universo completo (Etapa 2 em diante)
uv run ruff check .                    # lint
```

## Estrutura

| SPEC | Código | Dados / saídas |
|---|---|---|
| `/data` | `src/quantbr/data/` | `data/` (`cache/` Parquet, `reference/` universos, `reports/` qualidade) |
| `/strategies` | `src/quantbr/strategies/` | — |
| `/backtest` | `src/quantbr/backtest/` | — |
| `/validation` | `src/quantbr/validation/` | — |
| `/models/googl` | `src/quantbr/models/googl/` | `models/googl/` (artefatos) |
| `/site` | `src/quantbr/site/` (gerador) | `site/` (site estático gerado) |
| `/live` | `src/quantbr/live/` | `live/` (logs e estado) |
| `/tests` | `tests/` | — |

Configuração central (custos, janelas do walk-forward, limiares de validação e o seu contexto) em
`config/default.toml`. O código fica em `src/quantbr/` porque `site` é um módulo da biblioteca
padrão do Python e não pode ser um pacote de topo (detalhes em ASSUMPTIONS.md, D1).

## Fontes de dados

- Preços: [yfinance](https://github.com/ranaroussi/yfinance) (sufixo `.SA` para B3).
- Checagem cruzada B3: Série Histórica oficial (COTAHIST).
- Composição do Ibovespa: carteira do dia da B3. Lista do S&P 500: Wikipedia.
