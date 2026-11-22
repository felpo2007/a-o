---
project: STARLITE
type: system
status: verified
source_paths:
  - src/ServerScriptService/Modules/ProfileSchema.luau
  - src/ServerScriptService/Modules/PlayerData.luau
  - src/ServerScriptService/Modules/ProgressionService.luau
  - src/ServerScriptService/Modules/CommerceService.luau
  - src/ServerScriptService/Modules/CaixaService.luau
  - src/ServerScriptService/Modules/CampanhaService.luau
  - src/ServerScriptService/Modules/DailyRewardService.luau
  - src/ReplicatedStorage/Shared/Commerce.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Progressao e Economia

## Resumo
O perfil do jogador vive num DataStore e é gravado por transações atômicas (UpdateAsync). XP e créditos entram por "delta da sessão"; compras em Robux, recompensa diária e caixas gravam direto no DataStore, com recibo por PurchaseId. Relacionado: [[Arquitetura]], [[Rede-e-Seguranca]], [[UI-Arquitetura]], [[Modos-e-Partida]].

## Responsabilidades
- Persistência: esquema, migração e saneamento do perfil (ProfileSchema), carga, salvamento e transações (PlayerData).
- Moeda "créditos de intendência" (símbolo $) e XP com posto; equipamento e skins comprados com créditos (ProgressionService).
- Recompensa diária (DailyRewardService), missões, passe de temporada, mercado do dia, reforços, medalhas, códigos e placar semanal (CampanhaService).
- Posse de Game Passes, Premium e assinatura, recibos de produtos (CommerceService).
- Caixas de suprimentos, gratuitas e pagas, com sorteio só no servidor (CaixaService, CaixaRegras, Shared/Caixas).
- Prestígio: não existe no código (busca sem resultado em src).

## Arquivos principais
- ProfileSchema.luau: tipos do perfil, migrate, applySession, afterWrite, mergeCampaign, mergeSkins, newerDaily. Puro, testável no Lune.
- PlayerData.luau: DataStore "VT65_Player_v1", chave "u_<UserId>"; load, save, bump, applyReceipt, transact, claimDaily, start.
- ProgressionService.luau: add e award (XP e créditos com teto), applyGear, buySkin, abate e assistência por Combatants.Added.
- Shared/Progression.luau: MAX_RANK 13, STEPS, REWARDS, CAP, PAIR_COOLDOWN, MAX_CREDITS, START_CREDITS. Números marcados no próprio arquivo como design (placeholder até o playtest).
- CommerceService.luau: ProcessReceipt (função processReceipt), refresh de posse, Commerce_Equip.
- Shared/Commerce.luau: IDS de passes e produtos, DailyTrack, dailyClaim, dayIndex.
- CaixaService.luau e CaixaRegras.luau: politica, bloqueioPaga, abrir, recibo, ganhar, darCaixa.
- CampanhaService.luau: onAction (reroll, claim_mission, claim_level, claim_all, market_buy, code_redeem, card_set); Shared/Missoes, Temporada, Mercado, Codigos.

## Fluxo
- Entrada: PlayerData.load faz GetAsync com 4 tentativas e migra o dado. Se falhar, marca o atributo DataReadOnly e a sessão não grava.
- Ganho: ProgressionService.award aplica a janela anti-farm (Progression.grant) e a espera por par; add soma XP e créditos, paga o soldo de promoção e guarda uma Caixa de Serviço por posto novo.
- Salvar: PlayerData.save (saída, BindToClose fora do Studio e autosave a cada 300 s) grava stored + (memória - base) para xp, créditos e renasceres guardados; a posse de skins e a campanha são união ou máximo.
- Recibo: MarketplaceService.ProcessReceipt = processReceipt. Resolve a chave do produto e despacha: caixa (crateReceipt), campanha, veículo, skin de arma, ou genérico (respawn guardado, tip). Os genéricos chamam PlayerData.applyReceipt.
- Diária: o cliente pede Daily_Claim; claimDaily carimba o dia UTC no DataStore; só depois ProgressionService.addCredits entrega os créditos.
- Caixa paga: Suprimento_Comprar chama bloqueioPaga e então PromptProductPurchase; o recibo cai em CaixaService.recibo.
- Código: op code_redeem valida em Shared/Codigos, marca campaign.owned["codigo:<CÓDIGO>"], paga via ProgressionService.bonus e dispara PlayerData.save.

## Dependências
DataStoreService, MarketplaceService, PolicyService, AnalyticsService; Shared/Net (remotes Daily_*, Commerce_*, Suprimento_*, Campanha_*); MatchService.pontuar e CampanhaEventos para missões. ProgressionService.start inicia o CampanhaService (require tardio, para evitar ciclo). Ver [[Modos-e-Partida]] e [[Combate]].

## Invariantes
- Recibo idempotente: applyReceipt devolve nil se purchases[PurchaseId] existe e a memória só copia o gravado; processReceipt responde PurchaseGranted em repetição. MAX_RECEIPTS é 200 (os mais antigos saem por prune).
- Falha de gravação ou perfil ausente devolve NotProcessedYet, então o Roblox repete o recibo.
- Caixa paga só é oferecida com Caixas.PAGAS_LIGADAS (hoje false), produto criado e PolicyService sem ArePaidRandomItemsRestricted. Consulta que falha conta como restrito (cache de 600 s só para resposta boa). Recibo de restrito, sem resposta ou com venda desligada vira Fragmentos fixos, sem sorteio.
- Os quatro produtos de caixa têm ID 0 em Commerce.IDS: nada é vendido ainda.
- Caixas só mudam por PlayerData.transact; applySession mantém sempre o gravado (rec.caixas = stored.caixas).
- Créditos limitados por Progression.MAX_CREDITS; PlayerData.save e transact usam lock por jogador (espera até 15 s e segue).
- Códigos: 8 erros por minuto e depois espera (Codigos.TENTATIVAS); pedidos de campanha com intervalo mínimo de 0,25 s; diária com 1,5 s e trava busy.
- Não alterar valores de economia sem decisão registrada.

## Riscos conhecidos
- DailyRewardService.claim: o selo do dia é gravado de forma atômica, mas os créditos entram depois, só em memória (ProgressionService.addCredits). Queda do servidor antes do próximo save perde os créditos do dia já carimbado.
- CampanhaService.onAction (code_redeem, claim_level, claim_mission, market_buy): validação em memória e gravação depois (task.spawn de PlayerData.save), sem transação. Dois servidores simultâneos podem aceitar o mesmo código antes de um ver o outro; o mergeCampaign só une depois. Não verificado se ocorre na prática.
- Shared/Codigos.LISTA fica em ReplicatedStorage, legível pelo cliente; só o limite de tentativas protege o código.
- Main.server.luau: se CaixaService.start falhar (pcall), crateReceipt fica nil e todo recibo de caixa devolve NotProcessedYet. É seguro para a cobrança, mas deixa o recibo pendente.
- Comentário defasado em DailyRewardService (diz 30 CI + 10 por dia); o valor real vem de Commerce.DailyTrack.

## Testes
tests/luau: f2, progressao, caixas, campanha, passe, skins, loja, conjuntos, arquivo, roleta, compraveiculo. Rodar com lune run tests/luau/<nome>.luau. Nesta nota nenhum foi executado; os nomes vêm da listagem da pasta.

## Pendências
- Ligar Caixas.PAGAS_LIGADAS e preencher os IDs das caixas depende do dono (questionário de classificação). Não verificado fora do código.
- Sem prestígio planejado em código; confirmar com o dono antes de qualquer proposta.
- Medir os números de equilíbrio (marcados como placeholder em Shared/Progression e Shared/Caixas).
