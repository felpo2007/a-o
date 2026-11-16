# VẠN TƯỜNG '65: monetização

Regra do prompt (Parte 11): **nada que dê vantagem**. Vendemos só cosméticos históricos, unidade
(clã), servidores privados, Premium e apoio. Armas, munição, tempo de spawn e atributos nunca ficam à
venda. O teste `tests/luau/f2.luau` garante que o catálogo só tem slots cosméticos e produtos de
apoio.

**Exceção decidida pelo dono (2026-11-11, D-72):** "quero usar robux" e "faça com a opção de
dinheiro do jogo também". Dois itens de jogo podem ser pagos em Robux **ou** com a moeda ganha
jogando:
- **equipamento melhor** (permanente): Game Pass em Robux, compra com a moeda do jogo ou de graça
  num rank alto, para não fechar o jogo a quem não paga;
- **renascer no mesmo lugar** (consumível): Developer Product em Robux ou moeda do jogo, com as
  mesmas regras de segurança do servidor (sem inimigo perto, fora de área travada) conferidas
  antes de cobrar; se o renascer ficar impossível na hora do recibo, a compra em Robux vira
  crédito para a próxima morte.

O `f2.luau` aceita só esses itens listados; qualquer outra vantagem continua proibida.

## Fontes de receita (o que foi implementado e o que você ativa)

| # | Fonte | Como gera dinheiro | No código | O que você faz no Creator Dashboard |
|---|---|---|---|---|
| 1 | **Game Passes cosméticos** (USMC 1965, Força Principal 1965) | compra única em Robux | `Shared/Commerce.luau` (Passes e Cosmetics), `CommerceService` (posse com `UserOwnsGamePassAsync`), loja na tecla **B**, armário | criar 2 passes, enviar os ícones de `assets/forgegui/marketing/`, colar os IDs em `Commerce.IDS` |
| 2 | **Passe de Unidade** | compra única: criar unidade/clã com tag | catálogo + atributo `UnitPass`; a tela de unidade entra com o relatório pós-ação | criar o passe e colar o ID |
| 3 | **Apoiador: Dossiê Starlite** | compra única: dossiê histórico + fita no relatório pós-ação | catálogo + atributo `Supporter` | criar o passe e colar o ID |
| 4 | **Apoio ao desenvolvimento** (Developer Products) | consumível, sem recompensa em jogo | `ProcessReceipt` **idempotente** (`PlayerData.applyReceipt`, gravação atômica com `UpdateAsync`) | criar 2 produtos e colar os IDs |
| 5 | **Servidores privados** | assinatura mensal vendida pelo próprio Roblox | `PrivateServer.luau`: o dono escolhe Warfare/Skirmish e horário (06:30/12:00/18:30) | ligar "Private Servers" e definir o preço |
| 6 | **Premium Payouts** | o Roblox paga pelo tempo de jogo de assinantes Premium | benefício visual (capa desbotada, lenço xadrez) + `PromptPremiumPurchase` na loja | nada (é automático) |
| 7 | **Assinatura "Reserva da Unidade"** (opcional) | mensal | `GetUserSubscriptionStatusAsync`, `PromptSubscriptionPurchase` e itens que só valem com a assinatura ativa | criar a assinatura, se a conta for elegível, e colar o ID em `SUBSCRIPTION_UNIT_RESERVE` |

**Preços não ficam no código.** A loja lê o preço com `GetProductInfoAsync`. Segundo a documentação do
Roblox, o Managed Pricing (preço regional e teste automático de preço) só funciona em itens com preço
dinâmico, nunca fixo no texto. Com os IDs em 0, os itens ficam ocultos e o jogo roda normalmente.

### Preços iniciais sugeridos (opinião, para o Managed Pricing ajustar)
- Uniformes USMC 1965 / Força Principal 1965: **R$ 149** cada.
- Passe de Unidade: **R$ 299**. É comprado por quem organiza um grupo, e o grupo inteiro joga mais.
- Apoiador: **R$ 99**.
- Apoio: **R$ 25** e **R$ 100**.
- Servidor privado: **R$ 100/mês**. Bem acima do mínimo, porque o público é de unidades e
  campeonatos.
- Assinatura: o menor nível de preço disponível.

## Quanto isso rende (sem número inventado)
- Receita em dólar ≈ Robux **ganhos** × taxa do DevEx.
- Robux ganhos ≈ preço × ~70%, porque o Roblox fica com cerca de 30% das vendas na experiência.
- A taxa do DevEx citada em 2026 é **US$ 0,0038 por Robux ganho**. O saque mínimo citado é de 30.000
  Robux.
- Esses três números vêm de fontes secundárias (abaixo). Confira no Creator Dashboard antes de
  planejar.
- Exemplo do cálculo: 100 vendas de um passe de R$ 149 dão ≈ 100 × 149 × 0,7 × 0,0038 ≈ **US$ 39,6**.
- Não há projeção de jogadores aqui: isso sai da telemetria depois do lançamento.

## Funil medido
`AnalyticsService:LogFunnelStepEvent("Store", …)` registra quatro passos: `store_open` → `item_view`
→ `prompt` → `purchase`. Cada compra de produto também gera `LogCustomEvent("robux_spent")`. O cliente
só envia passos de uma lista fechada; o servidor valida e registra. Os números aparecem em Creator
Dashboard → Analytics.

## O que mais traz receita (prioridade)
1. **Gente jogando.** Premium Payouts e conversão dependem de servidores cheios. Bots que completam o
   servidor (Parte 11) e o tutorial vêm antes de qualquer item novo.
2. **Página do jogo.** Ícone (pronto) e capa (em geração no ForgeGUI) bons fazem diferença. Use os
   testes de miniatura do próprio Roblox.
3. **Unidades e campeonatos.** Servidor privado mais Passe de Unidade é o modelo que sustenta jogos
   táticos por anos.
4. **Anúncios pagos (Ads Manager):** só depois de a retenção do dia 1 estar medida.

### Rejeitado de propósito
- **Caixas aleatórias pagas:** rejeitadas na D-20 e **revistas na D-173** a pedido do dono. As caixas
  existem (seção abaixo), mas a venda paga fica desligada até o dono reenviar o questionário de
  classificação.
- **Anúncios dentro do mundo (Immersive Ads):** um outdoor no Vietnã de 1965 quebra a imersão.
- **Acesso pago ao jogo:** um 30v30 precisa de volume de jogadores.

## Checklist para ligar (10 min no Creator Dashboard)
1. Monetization → Passes: crie os 4 passes com os ícones de `assets/forgegui/marketing/`. Atenção:
   `gamepass_usmc_1965.jpg` saiu estilizado e deve ser refeito.
2. Monetization → Developer Products: crie os 2 produtos de apoio.
3. Cole os IDs em `src/ReplicatedStorage/Shared/Commerce.luau` (`Commerce.IDS`) e publique.
4. Settings → Private Servers: ative e defina o preço.
5. Opcional: Subscriptions (se a conta for elegível).
6. Managed Pricing: opte por ele depois de ter vendas, porque itens abaixo do limite não entram nos
   testes.

## Caixas de suprimentos (D-173, 2026-11-15; D-174, D-178 a D-180, 2026-11-16)

Código: `Shared/Caixas.luau` (tabelas e chances), `Shared/Cosmeticos.luau` (itens), `Modules/CaixaRegras.luau`
(regras sobre o perfil), `Modules/CaixaService.luau` (servidor), `Controllers/CaixasTela.client.luau` (aba
CAIXAS da loja). Testes: `tests/luau/caixas.luau`. Relatórios: `testes/CAIXAS_2026-11-15.md` e
`testes/CAIXAS_D174_2026-11-16.md`.

| Caixa | Como se abre | Itens | Distribuição por raridade |
|---|---|---|---|
| Caixa de Recompensa | 1 Bilhete de Recompensa (ganho jogando) | 43 | 82 / 13 / 3 / 1 / 1% |
| Caixa de Recruta | grátis: treinamento ou primeira partida (uma vez) | 22 | 84 / 11 / 3 / 1,5 / 0,5% |
| Caixa de Serviço | grátis: cada posto novo | 49 | 39 / 43 / 16 / 1,5 / 0,5% |
| Caixa de Batalhão | grátis: cada missão da semana | 47 | 42 / 30 / 24 / 3 / 1% |
| Caixa de Campanha | grátis: níveis 10 a 50 da trilha grátis do passe | 72 | — / 55 / 30 / 13 / 2% |
| Caixa de Veterano | grátis: 10, 25, 50, 100 e 200 partidas | 80 | — / — / 44 / 46 / 10% |
| Caixa de Suprimentos | Robux, ref. R$ 49 (desligada) | 150 | 60 / 25 / 10 / 4 / 1% |
| Caixa de Equipamentos Especiais | Robux, ref. R$ 99 (desligada) | 133 | — / 45 / 36 / 16 / 3% |
| Caixa de Arsenal de Elite | Robux, ref. R$ 149 (desligada) | 111 | — / — / 40 / 48 / 12% |
| Caixa de Operações Históricas | Robux, ref. R$ 99, só na Temporada 1 (desligada) | 11 | — / 50 / 30 / 15 / 5% |

(comum / incomum / raro / épico / lendário). A chance de cada item está na tela, antes de comprar ou
abrir, em "VER ITENS E PROBABILIDADES".

**D-178:** entraram 100 itens só visuais (60 acabamentos de arma extravagantes e 40 itens de
cartão). A fatia de cada raridade em cada caixa é a mesma de antes (o teste cobra caixa por
caixa); só o peso de cada item dentro da raridade foi redividido. Todo item novo sai de pelo
menos uma caixa grátis, e os acabamentos novos não se compram com $ nem com Robux (só caixa e
troca de Fragmentos).

**D-179:** mais 12 acabamentos universais (valem em qualquer arma com arte), na mesma regra:
a fatia de cada raridade não mudou, cada um sai de uma caixa grátis (Batalhão, Campanha ou
Veterano) e da de Suprimentos, e não se compra com $ nem com Robux. **D-180:** mais 12
universais na mesma regra (24 no total).

**Economias separadas:**
- **Bilhetes de Recompensa:** só jogando. Valem 1 por missão do dia, 2 por missão da semana (até 4 por
  dia) e 2 de boas-vindas. Nunca à venda, nem por Robux, assinatura ou pacote.
- **Fragmentos de Arsenal:** vêm da repetida (Comum 5, Incomum 15, Raro 40, Épico 100, Lendário 250,
  D-174) e dos prêmios das caixas grátis. Trocam por item garantido (custo de 10× o valor da
  raridade). Não viram Robux nem dinheiro.
- **Créditos ($):** ganhos jogando e também vendidos por Robux (`PRODUCT_CREDITS_*`), por isso
  **não** abrem caixa. Compram direto (D-174, sem sorteio) emblemas, plaquetas e molduras:
  $ 1.500 / 3.000 / 7.500 / 15.000 / 30.000 por raridade.
- **Caixas de marco (D-174):** grátis, guardadas até o jogador abrir; cada marco dá uma vez.
  Podem dar $ 500 ou $ 1.500 em créditos e 100 ou 250 Fragmentos (nunca em caixa paga).

### ARQUIVO MILITAR STARLITE (D-175)
Álbum de todos os cosméticos (aba ARQUIVO da loja) e 9 coleções temáticas. Cada coleção completa
dá um cosmético **exclusivo** (fora das caixas, da troca e da compra direta), mais Fragmentos e
créditos, uma vez por conta. Nenhuma coleção exige caixa paga: o teste cobra um caminho grátis para
cada item. Tabela de coleções e prêmios: `DESIGN.md` (D-175).

### Conjuntos em Game Pass (D-176)
Compra única, permanente e só visual, com itens novos que não saem de caixa, troca nem compra
com $. A venda fica no ARQUIVO, página CONJUNTOS. Todos foram criados e estão à venda:

| Conjunto | Preço (referência) | ID |
|---|---|---|
| Identidade Militar | R$ 49 | 2088634972 |
| Uniformes Históricos | R$ 99 | 2088232933 |
| Personalização de Armas | R$ 149 | 2089588819 |
| Fundador STARLITE | R$ 499 | 2087975040 |

O preço real é o do Creator Hub; a tela lê com `GetProductInfoAsync`.

### Para ligar a venda paga (Creator Dashboard)
1. **Questionário de classificação:** responda que há itens aleatórios pagos e reenvie. A política
   manda reenviar quando uma atualização muda uma resposta.
2. **Produtos:** crie os 4 Developer Products, só pelo nome:
   `uv run --env-file .env python tools/roblox_cloud.py create-store PRODUCT_CRATE_SUPPLY PRODUCT_CRATE_SPECIAL PRODUCT_CRATE_ELITE PRODUCT_CRATE_HISTORIC`.
   O script grava os IDs em `Commerce.IDS`. Ou crie no Creator Hub (Monetization → Developer
   Products) e cole os IDs.
3. **Ligar a venda:** troque `Caixas.PAGAS_LIGADAS` para `true` e o teste que cobra `false`
   (`tests/luau/caixas.luau`). Registre no `DESIGN.md` e publique.
4. **Preço regional** (opcional): ligue o Regional Pricing dos produtos. A tela já lê o preço com
   `GetProductInfoAsync`. Não há trocas nem presentes, então o `GetUsersPriceLevelsAsync` não é
   necessário.

### Auditoria de conformidade (2026-11-15)
Fontes oficiais lidas nesse dia: Paid Random Items, PolicyService, Developer Products, Subscriptions,
Regional Pricing e Content Ratings (create.roblox.com/docs).

| Item | Estado | Observação |
|---|---|---|
| Developer Products / ProcessReceipt | Conforme | grava antes de devolver `PurchaseGranted` (UpdateAsync); falha = `NotProcessedYet` |
| Concessão idempotente | Conforme | o mesmo PurchaseId devolve o resultado gravado, sem novo sorteio (teste e Studio) |
| Game Passes | Conforme | posse por `UserOwnsGamePassAsync`; os 4 conjuntos (D-176) são só visuais, permanentes e com o conteúdo listado antes da compra |
| Assinatura | Pendente de configuração | ID vazio; criar no Creator Hub (Robux, mínimo R$ 49) |
| Preço regional | Pendente de configuração | a leitura já é dinâmica; o opt-in dos produtos é do dono |
| Pacotes pagos | Conforme | o Pacote de Recruta tem conteúdo fixo, sem aleatório |
| Probabilidade de cada resultado | Conforme | lista completa, antes da compra, botão com texto (sem ícone solto) |
| Soma de 100% | Conforme | pesos inteiros na base 100.000; soma conferida no teste e na partida |
| PolicyService (ArePaidRandomItemsRestricted) | Conforme | no servidor, antes do prompt e no recibo; falha na consulta = bloqueio |
| Compra indireta (moeda comprável) | Conforme | só Bilhete abre caixa; créditos vendidos por Robux não abrem |
| Repetidas | Conforme | viram Fragmentos; a tela mostra o resultado final de cada item para o jogador |
| Modificador de sorte | Não aplicável | não existe |
| Garantia progressiva | Não aplicável | desligada; quando ligada, a tela mostra a chance efetiva do próximo sorteio |
| Benefício mínimo | Conforme | todo resultado dá item ou Fragmentos |
| Apostas e conversão em dinheiro | Conforme | nada de aposta, troca, saque ou resgate |
| Troca de itens pagos | Não aplicável | itens presos à conta (`IsPaidItemTradingAllowed` só se a troca existir) |
| Venda das caixas pagas | Pendente de configuração | `PAGAS_LIGADAS = false`, produtos não criados |
| Classificação de conteúdo | Pendente de validação externa | o questionário é do dono |
| Itens novos (emblemas, plaquetas, molduras) | Conforme | desenhos originais, sem insígnia real nem marca |
| Interface honesta, sem pressão | Conforme | sem contador, urgência ou desconto; preço vem do Roblox; a roleta (D-177) não fabrica quase vitória (enchimento com as chances reais, parada exata, teste) |
| Alternativa gratuita | Conforme | caixa de Bilhete, 5 caixas de marco, troca de Fragmentos, compra direta com créditos ganhos jogando e as coleções do Arquivo (nenhuma exige caixa paga; teste) |
| **Igualdade competitiva** | **Não conforme** | a loja antiga vende vantagem: vantagens até +12% (D-101), kits (D-72), renascer onde caiu, veículo ao nascer (D-103), camuflagem contra os bots (D-85), reforços de XP. O dono decidiu manter (2026-11-16, D-174) |
| Gasto de créditos ($) atômico | Parcial | a compra direta (D-174) é atômica e junta os créditos da sessão antes; as compras antigas com $ ainda descontam na memória |
| Mouse, toque e controle | Conforme no código | falta conferir num celular e num Xbox reais |

### Próximos lotes (plano de expansão)
- Game Passes novos do pedido: feitos (D-176), sem capacetes, gravações e animações de inspeção
  (não existem no jogo).
- Clube de Veteranos (assinatura): o dono cria no Creator Hub; o código já lê a assinatura.
- Passe de temporada de 8 semanas: hoje são 6 semanas e 50 níveis (Temporada).
- Pacotes de compra direta (Patrulha, Infantaria, Reconhecimento, Veterano) com conteúdo fixo. A
  compra direta item a item, com créditos, já existe (D-174).
- "ARQUIVO MILITAR STARLITE": feito (D-175).
- Roleta horizontal na abertura das caixas: feita (D-177). Só a apresentação mudou: o enchimento
  usa as chances reais da lista e a parada é exata no item gravado, sem "quase vitória".
- Painel de configuração dos produtos, chances e temporadas; relatório de analytics por categoria.
- Caixas 3D próprias (hoje são as caixas de munição do jogo) e som de abertura.

Fontes consultadas em 2026-11-09:
- [Roblox Q2 2026: carta aos acionistas (SEC)](https://www.sec.gov/Archives/edgar/data/0001315098/000162828026051059/ex991-robloxq22026earnin.htm)
- [Managed Pricing (Creator Hub)](https://create.roblox.com/docs/production/monetization/managed-pricing)
- [Regional pricing (Creator Hub)](https://create.roblox.com/docs/en-us/production/monetization/regional-pricing)
- [DevForum: Introducing Regional Pricing for Passes](https://devforum.roblox.com/t/introducing-regional-pricing-for-passes/3621382)
- [DevEx: taxa de 2026, fonte secundária](https://generalistprogrammer.com/tutorials/roblox-devex-guide-how-to-cash-out-robux)
- [Guia de monetização 2026, fonte secundária](https://medium.com/@andy.a.g/the-complete-guide-to-monetizing-a-roblox-game-in-2026-c5e915a7c778)
