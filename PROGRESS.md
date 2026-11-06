# PROGRESS

## Etapa atual
- **Concluída: Etapa 0 — Setup** (sessão de 2026-11-06).
- **Próxima: Etapa 1 — Fatia vertical (MVP).**

Critério "Pronto quando" da Etapa 0: `pytest` roda e o README explica como instalar → **cumprido**
(55 testes passando; instalação do zero a partir de um clone limpo seguindo o README também passou).

---

## Etapa 0 — Setup (2026-11-06)

### O que foi feito
- Repositório git (branch `main`), publicado em https://github.com/felpo2007/a-o, com a estrutura da SPEC. Código em `src/quantbr/`
  com os módulos `data`, `strategies`, `backtest`, `validation`, `models/googl`, `site`, `live`;
  diretórios de topo `data/`, `models/googl/`, `site/`, `live/` para dados e saídas
  (motivo em ASSUMPTIONS.md, D1).
- Ambiente com **uv**: Python 3.12 fixado, 97 pacotes travados em `uv.lock`. Principais versões:
  numpy 2.5.4, pandas 3.1.1, pyarrow 26.0.1, scipy 1.18.1, yfinance 1.8.0,
  pandas-market-calendars 5.6.0, vectorbt 1.2.0 (numba 0.68.1), jinja2 3.1.6; dev: pytest 9.2.0,
  ruff 0.17.4.
- `config/default.toml`: todos os parâmetros numéricos da SPEC (custos, walk-forward, capacidade,
  limiares de validação, holdout) + MEU CONTEXTO assumido. Testes travam esses valores.
- `run.py` (comando único): `--check-env` (Python, dependências, pastas), `--check-env --network`
  (fontes de dados) e `--universe mvp|full` (por enquanto sai com código 2 e mensagem explícita;
  o pipeline entra na Etapa 1).
- Segredos: `.env.example` sem valores, `.env` no `.gitignore` (confirmado por teste com
  `git check-ignore`) e teste que procura chaves escritas no código.
- README com instalação (macOS/Linux/Windows), testes, uso e mapa da estrutura.
- ASSUMPTIONS.md com os 6 campos de MEU CONTEXTO e 8 decisões técnicas.

### Resultados-chave
| Verificação | Resultado |
|---|---|
| `uv run pytest` (offline) | **55 passed, 1 skipped** (o teste de rede é opcional) |
| `RUN_NETWORK_TESTS=1 uv run pytest` | **56 passed** |
| `uv run ruff check .` | sem erros |
| Instalação do zero (clone limpo → `uv sync --locked` → `run.py --check-env` → `pytest`) | **OK**: ambiente criado só com o `uv.lock`, "Ambiente OK.", 55 passed, 1 skipped |
| Smoke test vectorbt com pandas 3.1.1 | OK (backtest de cruzamento de médias em dados sintéticos rodou) |

Fontes de dados testadas em 2026-11-06 a partir do ambiente de execução:
| Fonte | Status |
|---|---|
| yfinance GOOGL / PETR4.SA / QQQ | OK. GOOGL tem histórico de 2004-08-19 a 2026-11-06 (5.591 pregões) |
| B3 — carteira do dia do IBOV (API `GetPortfolioDay`) | HTTP 200, **76 ativos**, data 06/11/26 |
| B3 — COTAHIST anual (2024) | HTTP 200, arquivo de 79,3 MB (zip); download observado ~1 MB/s |
| Wikipedia — lista do S&P 500 | HTTP 200 |
| Stooq (candidato a fallback de preços) | conexão recusada (reset) — não serve de fallback neste ambiente |

Dado de contexto para o kill switch (código executado, yfinance, fechamento ajustado): o buy & hold
de GOOGL teve drawdown máximo de **−65,3%** (nov/2008), **−43,6%** em 2022–23 e **−30,9%** em 2020,
e ficou mais de 20% abaixo do pico em algum momento de 14 dos 23 anos-calendário desde 2004.

### Suposições (detalhes em ASSUMPTIONS.md)
- MEU CONTEXTO estava vazio → assumido: capital R$ 10.000; via de operação "ainda não sei"; kill
  switch em drawdown de 20%; no máximo 1 mudança de posição por semana no modelo GOOGL; 10 min/dia;
  horizonte de 2 anos.
- Métricas na moeda nativa de cada ativo; câmbio só na comparação das vias de operação (Etapa 7).
- Nenhuma regra de IR codificada ainda (verificação em fonte oficial fica para a Etapa 3).

### Problemas e riscos
1. ~~O repositório não tinha remoto no GitHub~~ → **resolvido (2026-11-06):** código publicado em
   **https://github.com/felpo2007/a-o** (público, escolha do usuário), branch `main`, mesmos 2+ commits.
   O app Claude do GitHub foi instalado na conta com acesso **só** a esse repositório. Sobrou um
   repositório vazio e privado `felpo2007/acoes-quant`, criado durante o processo e não usado: pode
   ser apagado pelo usuário em Settings → Danger zone. Por ser público, nunca versionar `.env`
   (já garantido por `.gitignore` e teste).
2. yfinance recebeu HTTP 429 (limite de requisições) ao buscar o "crumb", mas os downloads
   funcionaram. No universo completo (~76 + ~500 tickers) vai precisar de pausa entre requisições,
   retry com backoff e cache Parquet (Etapa 2).
3. pandas 3.x é recente. vectorbt 1.2.0 passou no smoke test; se aparecer incompatibilidade na
   Etapa 3, fixar `pandas<3`.
4. Viés de sobrevivência: as listas atuais de IBOV e S&P 500 não incluem empresas que saíram dos
   índices. Tratar ou documentar na Etapa 2.
5. Todo o MEU CONTEXTO foi assumido. O limite de drawdown de 20% é bem mais apertado que o
   histórico da GOOGL; vale revisar antes da Etapa 6.

### Próximos passos (Etapa 1 — MVP)
0. Antes de começar: abrir o Claude Code no repositório `felpo2007/a-o` (o zip da Etapa 0 não é mais necessário).
1. Universo MVP: 10 ações do IBOV (maiores pesos na carteira do dia da B3) + 10 do S&P 500 (maiores
   valores de mercado) + GOOGL; salvar em `data/reference/` com data de referência.
2. Download via yfinance com cache Parquet e calendário de pregões (pandas_market_calendars).
3. 3 estratégias da biblioteca fixa + buy & hold (proposta: cruzamento de médias, momentum de série
   temporal e filtro MM200), sinal no fechamento de t e execução na abertura de t+1, custos da
   config, teste automatizado de ausência de look-ahead.
4. Walk-forward 5 anos de otimização / 1 ano de teste, métricas só fora da amostra.
5. Site mínimo (tabela + uma página por ação) com os tokens visuais da Etapa 5 (claro/escuro).
6. Pronto quando: `python run.py --universe mvp` baixa dados, roda backtests e gera o site do zero.
