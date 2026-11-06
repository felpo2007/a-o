# SPEC — Estratégias de trade IBOV + S&P 500 e modelo dedicado para GOOGL

## MEU CONTEXTO (preencher antes de começar)
- Capital inicial para operar GOOGL: [R$ ___]
- Onde vou operar: [corretora americana ___ / BDR na B3 / ainda não sei]
- Drawdown máximo que eu aguento sem desligar o modelo: [___ %]
- Frequência máxima de operação aceitável: [diária / semanal / mensal]
- Tempo que posso dedicar a acompanhar: [ex.: 10 min por dia após o fechamento]
- Horizonte: [ex.: manter o modelo rodando por 2+ anos]
Se algum campo estiver vazio, assuma um valor conservador e registre em ASSUMPTIONS.md.

## PAPEL
Você é um engenheiro quantitativo sênior (pesquisa + engenharia de software). Seu maior inimigo é o overfitting, não a falta de retorno. Um "não funcionou" honesto vale mais que um backtest bonito.

## OBJETIVO
1. Um site que mostre, para cada ação do Ibovespa e do S&P 500, qual estratégia teve o melhor desempenho FORA DA AMOSTRA, e se essa escolha tem valor preditivo.
2. Um modelo dedicado para GOOGL que supere a melhor estratégia da parte 1 para GOOGL, o buy & hold de GOOGL e o QQQ, com validação honesta, pronto para operar: primeiro em paper trading, depois real.

## COMO TRABALHAR
- Este arquivo é a especificação. Mantenha um PROGRESS.md com: etapa atual, o que foi feito, resultados-chave (com números), problemas e próximos passos.
- Uma etapa por sessão. Ao terminar, rode os testes, faça commit no git e atualize o PROGRESS.md.
- Avance sem pedir confirmação a cada passo. Pergunte só se faltar algo que mude o resultado de forma relevante; caso contrário, assuma o razoável e registre em ASSUMPTIONS.md.
- Nunca invente dados ou resultados. Todo número do site e dos relatórios sai de código executado. Se uma fonte falhar, diga qual e use o fallback.
- Stack: Python 3.11+, dependências fixadas (uv ou poetry), pytest. Chaves de API só em .env (no .gitignore), nunca no código.

## ETAPAS

### Etapa 0 — Setup
Estrutura do repositório, ambiente, git, esqueleto de testes, PROGRESS.md, ASSUMPTIONS.md.
**Pronto quando:** `pytest` roda (mesmo com poucos testes) e o README explica como instalar.

### Etapa 1 — Fatia vertical (MVP)
Antes de escalar, faça o pipeline inteiro com um universo pequeno: 10 ações do IBOV, 10 do S&P 500 e GOOGL; 3 estratégias + buy & hold; backtest walk-forward; site mínimo com tabela e uma página por ação, já usando os tokens visuais (cores, fontes, temas claro/escuro) da Etapa 5.
**Pronto quando:** um único comando (`python run.py --universe mvp`) baixa dados, roda backtests e gera o site do zero.

### Etapa 2 — Dados completos
- Universo: composição atual da carteira teórica do Ibovespa (B3) e lista atual do S&P 500, salvas com data de referência.
- Viés de sobrevivência: use constituintes históricos se conseguir; senão, documente o viés no site.
- Dados diários OHLCV ajustados por splits e proventos, de 2010 até hoje (GOOGL: todo o histórico disponível).
- Fontes: yfinance (sufixo .SA para B3). Para B3, faça checagem cruzada com a Série Histórica oficial da B3 (COTAHIST) e reporte divergências relevantes.
- Limpeza: dias faltando, preços zerados, saltos absurdos, ajustes errados. Use calendário oficial de pregões (ex.: pandas_market_calendars).
- Filtro de liquidez: exclua ativos com volume financeiro médio abaixo de um mínimo documentado e marque como "dados insuficientes" quem tiver menos de 3 anos de dados fora da amostra.
- Cache local em Parquet.
**Pronto quando:** relatório de qualidade dos dados por ativo (cobertura, falhas, divergências) gerado automaticamente.

### Etapa 3 — Estratégias e backtest
Biblioteca fixa, definida ANTES de testar. Long/flat por padrão. Grade de no máximo ~20 combinações de parâmetros por estratégia:
1. Buy & hold (benchmark obrigatório)
2. Cruzamento de médias (SMA/EMA)
3. Rompimento de Donchian
4. Momentum de série temporal
5. MACD
6. RSI(2) reversão com filtro MM200
7. Bandas de Bollinger reversão
8. Keltner/ATR rompimento
9. Filtro de tendência MM200
10. Volatility targeting sobre buy & hold

Regras do backtest:
- Sinal no fechamento de t, execução na abertura de t+1. Teste automatizado que prova ausência de look-ahead.
- Custos parametrizáveis: padrão B3 0,05% por lado + 0,05% de slippage; EUA 0,01% + 0,02%. Rodar também com 2x custos.
- Capacidade: ordem limitada a 1% do volume médio diário do ativo.
- Impostos: modele o IR como parâmetro por tipo de ativo (ações B3, BDR, ações no exterior), com as regras vigentes verificadas em fonte oficial (Receita Federal) na data da execução. Mostre resultados antes e depois de IR. Estratégias de alto giro costumam morrer aqui.
- Walk-forward: otimiza em janela de 5 anos, testa no ano seguinte, rola anualmente. Só o fora da amostra (OOS) conta.
- Métricas OOS após custos: CAGR, volatilidade, Sharpe, Sortino, max drawdown, Calmar, nº de trades, taxa de acerto, profit factor, exposição, turnover, excesso vs buy & hold. Intervalos de confiança por bootstrap para Sharpe e CAGR.
- Use vectorbt (ou equivalente vetorizado) para escalar.
**Pronto quando:** backtest completo rodou para todo o universo, com resultados salvos em JSON/Parquet.

### Etapa 4 — Validação estatística
- Deflated Sharpe Ratio (Bailey & López de Prado) considerando o total de configurações testadas por ação.
- Probability of Backtest Overfitting (PBO) via CSCV.
- Teste contra o acaso: compare cada estratégia com 1.000 estratégias aleatórias de mesma exposição média e mesmo nº de trades. Reporte o percentil.
- Persistência da escolha (essencial): para cada ação, escolha a "melhor estratégia" usando só dados até o ano t e meça no ano t+1; repita para todos os anos. Se a melhor estratégia do passado não continua boa no futuro, o ranking do site não tem valor preditivo, e o site precisa dizer isso.
- Critério da "melhor estratégia" por ação: maior Sharpe OOS após custos, com ≥ 30 trades, DSR > 0,95 e percentil > 95% contra o acaso. Se nenhuma passar, a melhor é "buy & hold".
- Heatmap de sensibilidade de parâmetros (picos isolados = suspeito).
**Pronto quando:** cada ação tem veredito ("estratégia X validada" ou "buy & hold") e há um resumo agregado de persistência.

### Etapa 5 — Site
Estático (HTML/CSS/JS, sem backend), gerado a partir dos JSONs do pipeline. Gráficos com D3 ou Plotly, estilizados com os tokens abaixo (nada de tema padrão de biblioteca).

#### Identidade visual
Referência: seuimposto.com (apuração eleitoral da Pandora). Use o estilo como inspiração, sem copiar logo, marca ou conteúdo. É um visual de produto/app: minimalista e editorial, interativo, mobile-first, em que a cor só aparece nos dados.

Tokens (CSS custom properties, tema claro padrão + escuro):
| Token | Claro | Escuro |
|---|---|---|
| --bg | #F1F0EE | #0F0E0D |
| --panel / --panel-2 / --panel-3 | #F8F6F5 / #EEECEB / #E6E4E2 | #151412 / #1B1A17 / #22201D |
| --fg / --fg-2 / --fg-3 / --fg-4 | #111010 / #302E2D / #53514F / #6F6C69 | #FAFAF9 / #D6D4CF / #A6A39C / #85827C |
| --line / --line-2 / --line-3 | rgba(17,16,16,.08 / .16 / .25) | rgba(250,250,249,.08 / .16 / .25) |
| --glass | rgba(248,246,245,.93) | rgba(21,20,18,.93) |
| --live (verde "ao vivo") | #0C8A4C | #3DD68C |

Cores dos dados (semânticas, só nos dados):
- Supera o buy & hold = verde; perde = vermelho; neutro/buy & hold = cinza quente.
- Intensidade em 4 degraus (ex.: excesso de retorno até 2%, 5%, 10%, acima), como num mapa coroplético.
- Contraste mínimo WCAG AA. Não depender só da cor: sempre há o número junto.

Tipografia:
- Geist (sans) para interface e números; Faustina (serif) para manchetes. Ambas gratuitas (licença OFL), auto-hospedadas em woff2 com preload.
- Números sempre com `font-variant-numeric: tabular-nums` e letter-spacing levemente negativo.
- Escala compacta: micro 11px, label 12px, corpo 13px, nome 14px, manchete 27px, número-destaque 42px (26px no celular).

Forma e movimento:
- Bordas finas (hairline) em vez de sombras pesadas; cantos 8–12px em cards e 999px em pílulas e botões.
- Cabeçalho fixo de vidro (--glass + backdrop-filter: blur).
- Easing: cubic-bezier(.16,1,.3,1) nas entradas e cubic-bezier(.4,0,.2,1) nos hovers (~120ms).
- Indicador "ao vivo" com bolinha pulsando (animação breathe de ~1,4s).
- Brilho sutil (text-shadow) só em rótulos sobre áreas coloridas.
- Respeitar prefers-reduced-motion.

Componentes inspirados na referência, adaptados ao projeto:
- Manchete em serif com a palavra-chave colorida. Ex.: "Momentum **supera** o buy & hold em 37% das ações do S&P 500" (número real, gerado pelo pipeline).
- Barra dividida de comparação, como a barra de votos: estratégia vencedora vs buy & hold, com o % de cada lado.
- Mapa de calor clicável por setor (treemap de todas as ações, tamanho = valor de mercado, cor = excesso vs B&H nos 4 degraus). É a tela principal, equivalente ao mapa do Brasil.
- Controle segmentado em pílula: IBOV | S&P 500 (e Sharpe | CAGR | Drawdown).
- Linha do tempo com arraste (scrubber) que "replaya" a curva de capital ano a ano, com marcos clicáveis ("Crash COVID 03/2020", "Bear market 2022", "Início do holdout").
- Botão pílula "Auditoria" no cabeçalho levando à página de metodologia + resultado da auditoria da Etapa 8.
- Card "Sinal de hoje" da GOOGL com o indicador ao vivo, posição alvo e horário da última atualização.
- No celular: barra de abas inferior com ícones de traço fino (Mapa | Explorar | GOOGL | Ranking). No desktop: as mesmas seções em layout de duas colunas.
- Rodapé discreto com fonte dos dados, data da última atualização e o aviso legal.

#### Páginas
a) Mapa (início): manchete, controle IBOV | S&P 500, treemap e resumo de quantas ações têm estratégia validada.
b) Explorar: tabela filtrável/ordenável (índice, setor, estratégia vencedora, Sharpe OOS com intervalo, CAGR, max DD, excesso vs B&H, DSR, percentil vs acaso) com busca por ticker.
c) Por ação: barra de comparação, curva de capital vs B&H com scrubber, drawdown, trades, parâmetros por janela, métricas por ano, heatmap de robustez, resultado com 2x custos e após IR.
d) Ranking: por tipo de estratégia, mercado e setor.
e) Persistência: a escolha da melhor estratégia funciona no futuro?
f) GOOGL: modelo dedicado, card do sinal de hoje, model card.
g) Auditoria e metodologia: limitações e o relatório da Etapa 8.
- Aviso visível: estudo educacional, não é recomendação de investimento; resultados passados não garantem resultados futuros.

**Pronto quando:** site abre localmente; testado em 375px (celular) e 1440px (desktop), nos temas claro e escuro; Lighthouse com acessibilidade ≥ 90; números batem com os arquivos de resultado (teste automatizado de consistência).

### Etapa 6 — Modelo dedicado para GOOGL
Pré-registro: antes de qualquer teste, grave em SUCCESS_CRITERIA.md o critério de sucesso, o orçamento máximo de variações a testar (ex.: 50) e o período de holdout.

Holdout: últimos 24 meses, intocados até o fim e rodados uma única vez. Atenção: 2 anos têm pouco poder estatístico (erro padrão do Sharpe ~0,7 ou mais), então o holdout serve para confirmar que não houve degradação, não para provar superioridade.

Critério de sucesso:
- Evidência principal: no walk-forward OOS (período anterior ao holdout), Sharpe superior à melhor estratégia da Etapa 4 para GOOGL (escolhida só com dados pré-holdout), ao buy & hold de GOOGL e ao QQQ, com diferença significativa por bootstrap e DSR > 0,95.
- Confirmação: no holdout, desempenho dentro do intervalo esperado pelo backtest e drawdown não pior que o do buy & hold.

Ideias a explorar (com critério, dentro do orçamento):
- Filtro de regime: tendência de QQQ/SPY, VIX, juros.
- Força relativa vs QQQ e vs pares (MSFT, META, AMZN).
- Volatility targeting e sizing dinâmico.
- Calendário de resultados (earnings), usando apenas datas conhecidas na época.
- Ensemble das melhores estratégias validadas.
- ML (ex.: gradient boosting) para retorno de 5–20 dias, só com purged k-fold + embargo e features defasadas.

Regras:
- Prefira o modelo mais simples que atinja o critério.
- Validação: walk-forward, bootstrap dos trades, sensibilidade de parâmetros, 2x custos, IR, regimes (2020, 2022, ralis) e, por último, o holdout.
- É PROIBIDO ajustar o modelo com base no holdout. Se falhar, reporte com clareza e entregue o melhor candidato marcado como "não validado".
- Gere um model card: regras, parâmetros, dados usados, número de variações testadas, resultados, limitações, quando o modelo deve ser desligado.
**Pronto quando:** SUCCESS_CRITERIA.md avaliado item por item com resultado aprovado/reprovado.

### Etapa 7 — Operação (paper primeiro)
- Job diário após o fechamento dos EUA, rodando fora do meu notebook (ex.: GitHub Actions agendado ou VPS), com calendário de pregões.
- Saída: posição alvo, tamanho, preço de referência, stop. Alerta por Telegram ou e-mail.
- Modos: (1) só sinal, (2) paper trading via API de corretora (ex.: Interactive Brokers ou Alpaca), (3) real. Padrão = paper. Real exige flag explícita e confirmação manual.
- Operação a partir do Brasil: compare GOOGL em corretora americana vs BDR na B3 (confirme ticker, liquidez, spread, horário, câmbio e IR).
- Robustez operacional: execução idempotente (rodar duas vezes não duplica ordem), reconciliação diária da posição com a corretora, alerta se a fonte de dados falhar ou vier atrasada, versão do modelo congelada (hash) e registrada em cada sinal.
- Risco: tamanho máximo de posição, perda máxima diária, kill switch se o drawdown passar do limite em MEU CONTEXTO ou se o desempenho ao vivo sair do intervalo esperado.
- Log de sinais e ordens; relatório mensal ao vivo vs backtest.
- Passagem para real: no mínimo 3 meses de paper com desempenho dentro do intervalo esperado.
**Pronto quando:** paper trading rodou sozinho por 5 pregões seguidos sem intervenção, com logs e alertas funcionando.

### Etapa 8 — Auditoria independente e relatório final
- Use um subagente que não participou do desenvolvimento para auditar: look-ahead, vazamento de dados, viés de sobrevivência, custos, IR, uso indevido do holdout e consistência site vs resultados. Corrija o que ele encontrar e reporte.
- Relatório final em português: resultados da Etapa 4 (com números), veredito do modelo GOOGL, limitações, riscos e o passo a passo do que eu preciso fazer para começar a operar.

## ENTREGÁVEIS
- Repositório: /data, /strategies, /backtest, /validation, /models/googl, /site, /live, /tests, README.md, SPEC.md, PROGRESS.md, ASSUMPTIONS.md, SUCCESS_CRITERIA.md, MODEL_CARD.md.
- Site estático gerado por um comando.
- Relatório final.
