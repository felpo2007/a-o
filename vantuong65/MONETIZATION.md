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
- **Caixas aleatórias pagas:** exigem transparência de chances, são reguladas em vários países e vão
  contra o tom histórico.
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

Fontes consultadas em 2026-11-09:
- [Roblox Q2 2026: carta aos acionistas (SEC)](https://www.sec.gov/Archives/edgar/data/0001315098/000162828026051059/ex991-robloxq22026earnin.htm)
- [Managed Pricing (Creator Hub)](https://create.roblox.com/docs/production/monetization/managed-pricing)
- [Regional pricing (Creator Hub)](https://create.roblox.com/docs/en-us/production/monetization/regional-pricing)
- [DevForum: Introducing Regional Pricing for Passes](https://devforum.roblox.com/t/introducing-regional-pricing-for-passes/3621382)
- [DevEx: taxa de 2026, fonte secundária](https://generalistprogrammer.com/tutorials/roblox-devex-guide-how-to-cash-out-robux)
- [Guia de monetização 2026, fonte secundária](https://medium.com/@andy.a.g/the-complete-guide-to-monetizing-a-roblox-game-in-2026-c5e915a7c778)
