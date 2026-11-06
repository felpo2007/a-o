# ASSUMPTIONS

Suposições e decisões tomadas sem confirmação explícita. Cada uma pode ser revista; ao mudar,
atualize esta página e `config/default.toml`.

## MEU CONTEXTO (todos os campos estavam vazios na SPEC → valores conservadores)

Registrado em 2026-11-06 (Etapa 0). Valores em `config/default.toml`, seção `[context]`.

| Campo | Valor assumido | Por quê | Onde impacta |
|---|---|---|---|
| Capital inicial (GOOGL) | **R$ 10.000** | Valor baixo limita o dano de um erro na transição paper → real. | Etapa 7 (tamanho de posição). Com esse capital, o limite de 1% do volume médio diário nunca restringe GOOGL; tarifas fixas por ordem, se houver na corretora, pesam mais. |
| Onde operar | **ainda não sei** | Nenhuma via escolhida; as duas serão comparadas. | Backtest de GOOGL em USD (série original, histórico longo). Comparação corretora americana vs BDR (ticker, liquidez, spread, câmbio, IR) fica para a Etapa 7. |
| Drawdown máximo (kill switch) | **20%** | Limite conservador para alguém que está começando. | Etapa 7. Atenção: medido com dados reais nesta sessão, o buy & hold de GOOGL caiu **65,3%** do pico (nov/2008), **43,6%** em 2022–23 e **30,9%** em 2020, e ficou mais de 20% abaixo do pico em algum momento de 14 dos 23 anos-calendário desde 2004. Um modelo que fique muito exposto vai bater esse limite; isso é uma restrição real, não detalhe. |
| Frequência máxima | **semanal** (no máximo 1 mudança de posição por semana; sinal calculado todo dia) | Menos giro = menos custo, menos IR e menos tempo. | Só o modelo GOOGL (Etapas 6–7). O estudo do universo (Etapas 1–5) testa as estratégias como definidas na SPEC. Se preferir mais giro, mude para `"diaria"`: custos e IR vão aparecer nos resultados. |
| Tempo de acompanhamento | **10 min por dia após o fechamento** | Exemplo da própria SPEC. | Operação 100% automatizada, com alertas; nada intraday. |
| Horizonte | **2 anos** | Exemplo da própria SPEC. | Critério de desligamento e relatório mensal (Etapa 7). |

## Decisões técnicas

**D1 — Código em `src/quantbr/`, com os mesmos nomes de módulo da SPEC.**
A SPEC lista `/data`, `/strategies`, `/backtest`, `/validation`, `/models/googl`, `/site`, `/live`.
`site` é um módulo da biblioteca padrão do Python (importado na inicialização), então um pacote de
topo chamado `site` não pode ser importado; `data` e `models` também são nomes genéricos sujeitos a
colisão. Por isso o código fica em `src/quantbr/<módulo>` e os diretórios de topo `data/`,
`models/googl/`, `site/` e `live/` guardam dados, artefatos e saídas. O mapeamento está no README.

**D2 — Python 3.12 fixado em `.python-version`; `requires-python >=3.11,<3.14`.**
Testado nesta sessão: Python 3.12.3 + numpy 2.5.4 + pandas 3.1.1 + numba 0.68.1 + vectorbt 1.2.0
(smoke test de backtest OK). Não testado em 3.11 nem 3.13.

**D3 — uv como gerenciador; `uv.lock` é a fonte das versões fixadas.** Instalação reprodutível com
`uv sync --locked`. As dependências do backtest (vectorbt) já entram agora para detectar
incompatibilidades cedo.

**D4 — Parâmetros da SPEC centralizados em `config/default.toml` e protegidos por testes.**
Custos (B3 0,05% + 0,05%; EUA 0,01% + 0,02%; estresse 2x), walk-forward 5 anos/1 ano, capacidade 1%
do volume médio diário, grade ≤ 20 combinações, limiares de validação (≥ 30 trades, DSR > 0,95,
percentil > 95% contra 1.000 aleatórias) e holdout de 24 meses. Mudar qualquer um deles quebra um
teste de propósito: mudança de regra precisa ser explícita e registrada aqui.

**D5 — Testes de rede são opcionais** (`RUN_NETWORK_TESTS=1`), para que `pytest` seja determinístico
e rode sem internet.

**D6 — Dados baixados (`data/cache/`), site gerado (`site/`) e logs (`live/`) não são versionados**,
pois são reproduzíveis com `run.py`. Listas do universo com data de referência (`data/reference/`)
serão versionadas.

**D7 — Moeda (proposta para a Etapa 1):** métricas de cada ativo na moeda nativa (BRL para B3, USD
para EUA), comparadas com o buy & hold do próprio ativo. Câmbio só entra na comparação das vias de
operação de GOOGL (Etapa 7).

**D8 — IR:** nenhuma alíquota ou isenção foi codificada ainda. Pela SPEC, as regras (ações B3, BDR,
ações no exterior) serão verificadas em fonte oficial da Receita Federal na data da execução da
Etapa 3.
