---
project: STARLITE
type: system
status: verified
source_paths:
  - src/ServerScriptService/Modules/MatchService.luau
  - src/ServerScriptService/Modules/RodadaService.luau
  - src/ReplicatedStorage/Shared/Rodada.luau
  - src/ServerScriptService/Modules/ModoComboio.luau
  - src/ServerScriptService/Modules/ModoFrente.luau
  - src/ServerScriptService/Modules/SpawnService.luau
  - src/ServerScriptService/Modules/NascerRetService.luau
  - src/ReplicatedStorage/Shared/MapaAtivo.luau
  - src/ServerScriptService/Modules/MapaBoot.luau
  - src/ReplicatedStorage/Shared/MapasRet.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Modos e Partida

## Resumo
O MatchService mantém uma partida por vez no servidor: modo, estado de captura, relógio, vitória e publicação (Match_State). Ao fim, o RodadaService conduz o ciclo fim, comemoração, votação, restauração e partida nova. O mapa é escolhido uma vez, quando o servidor sobe (MapaBoot), e o modo dos mapas retangulares vem do mapa. Os mapas retangulares só abrem no Studio enquanto MapasRet.LIBERADOS for false. Ver [[Arquitetura]], [[Map-Index]].

## Responsabilidades
- MatchService: newMatch (sorteia pontos fortes, cria estado do modo), loop de 1 s em start (captura, eventos, chuva, vitória), endMatch, placar da partida (pontuar, linhas), preparo de PREP_S = 10 s.
- RodadaService: fases, pódio congelado, votação de mapa e horário, restauração, viagem a outro mapa.
- ModoFrente e ModoComboio: tradução das regras puras (Shared/LinhaFrente, Shared/Comboio) para o jogo.
- SpawnService: pedido de nascer (Spawn_Request), pontos, esperas por onda, nascer com o squad, renascer no lugar. NascerRetService liga os conjuntos de nascer dos mapas retangulares.
- MapaAtivo/MapaBoot/MapasRet: qual mapa e as medidas dele.

## Arquivos principais
- Modules/MatchService: newMatch, requestMode, endMatch, start, limitSeconds.
- Modules/RodadaService: fim, start, aoRestaurar, registrar (lista de restaurações).
- Shared/Rodada: FASES, DUR, MAPAS, podio, apurar, mapasDaVotacao, vale, presa, contagem (módulo puro, testável no Lune).
- Modules/FrontService: reunião avançada, ponto de reunião do squad, Squad_Positions, Spawn_Points; remotes criados ali.
- Shared/MapaAtivo: id, retangular, projeto, mundo, planta, configPara, aplicar.

## Fluxo
1. Subida: todo script de servidor chama MapaBoot.iniciar() primeiro. No Studio vale o atributo VT65DevMapa (frente ou comboio); fora dele, só com MapasRet.LIBERADOS true, servidor reservado e TeleportData.mapa. Senão o mapa padrão "vantuong". O resultado vai ao atributo VT65Mapa do workspace; nos retangulares a pasta Data_<id> vira Data e Build.features refaz o mapa.
2. MapaAtivo.id lê o atributo (o cliente espera até 20 s) e MapaAtivo.aplicar sobrepõe setores, QGs e limites no MapConfig.
3. Modos que existem no código: Warfare, Offensive e Skirmish (mapa padrão); LinhaFrente (mapa frente, Vale das Cinco Passagens); Comboio (mapa comboio, Estrada do Bambu). Não achei outros.
4. Warfare: 75 min (Capture.C.warfareMinutes), reforços 300 por lado, cada morte gasta um, sangria por setor de vantagem. Offensive: EUA atacam de leste, 20 min mais 15 por setor tomado (Offensive.C). Skirmish: 20 min, só o setor do meio ativo. Servidor público alterna Warfare e Offensive (MatchService.rotation); o privado fixa o modo (PrivateServer chama requestMode).
5. LinhaFrente: Shared/LinhaFrente.passo move a barra do setor ativo (A a E); ModoFrente.sincroniza espelha no estado de captura que HUD e bots leem; duração 20 min, final de 90 s (MapasRet.FRENTE.regras).
6. Comboio: duas rodadas de até 9 min, lados trocados (EUA escoltam na 1ª, VC na 2ª), intervalo de 12 s; ModoComboio.passo roda a 10 Hz; Comboio.resultado decide; a 1ª rodada chama as restaurações do RodadaService.
7. Fim: endMatch grava LastWinner, publica e chama MatchService.afterEnd (RodadaService.fim). Fases e durações (Rodada.DUR): fim 8 s, comemoração 12 s, votação 15 s, restauração 3 s; total 38 s vira NEXT_MATCH_S.
8. Votação: remote Rodada_Votar, um voto por jogador (e voto de horário); Rodada.apurar escolhe o mais votado, empate ou sem voto fica o primeiro (o mapa atual). Opções: só o mapa atual, a menos que liberado (LIBERADOS e não privado) ou VT65DevVotoMapas no Studio.
9. Outro mapa escolhido: MapaViagem.levar; se falhar, a partida segue aqui. Mesmo mapa: restaurações (corpos, soltos, armadilhas, buracos, crateras, logística, caixas, comandante, veículos, bots, jogadores) e MatchService.newMatch.
10. Nascer: Spawn_Request(id, método, rodada) recusa com fim, rodada velha, sem lado, posto abaixo do papel, terreno em geração; só no próprio lado, espera por ondas (SpawnRules). Nos retangulares o NascerRetService fornece os pontos (addProvider) e bloqueios por inimigo (addBlocker), com o QG como reserva.

## Dependências
Shared: Capture, Offensive, LinhaFrente, Comboio, Front, Rodada, MapConfig, SpawnRules, NascerRet. Server: Combatants, BotService e BotSquads (leem estado e setores; ver [[Bots-e-Veiculos]]), ProgressionService (ganchos onEvent e onEnd; [[Progressao-e-Economia]]), VehicleService, CartaService, PrivateServer, LightingService. Interface: [[UI-Arquitetura]].

## Invariantes
- Um MatchService.rodada que sobe a cada newMatch; tarefa atrasada confere com Rodada.vale ou MatchService.presa.
- Entre o fim e a partida nova ninguém nasce (Spawn_Request responde "fim").
- Nos mapas retangulares o modo é o do mapa, ignorando rotação e pedido.
- Oeste é o VC e Leste os EUA nos mapas retangulares (MapaAtivo.configPara).
- Durante PREP_S não há captura, sangria nem relógio; sem jogador em campo a contagem espera cheia.

## Riscos conhecidos
- MatchService.start (devMode): o gancho VT65DevMode só aceita Warfare, Offensive e Skirmish, e nos mapas retangulares newMatch sobrescreve o modo; trocar de modo pelo gancho ali não tem efeito. Só Studio, risco baixo.
- ModoComboio.trocaRodada chama RodadaService.restaurar sem passar por newMatch; não verificado se todos os restauradores aceitam rodada sem troca de MatchService.rodada.

## Testes
Lune: tests/luau/modo.luau, rodada.luau, modos_mapas.luau, nascer.luau, f3.luau; tools/mapas_check.luau para os mapas retangulares. Studio: ver [[Studio-Ganchos]] (VT65DevMode, VT65DevEnd, VT65DevMapa, VT65DevComboio, VT65DevVotoMapas).

## Pendências
- LIBERADOS = false: os mapas retangulares não estão publicados; PROVISÓRIO em vários valores de MapasRet (retorno da barra, largura de captura, reparo, altura de presença).
- Seção 15 do prompt dos mapas deixa escolhas em aberto, marcadas no próprio MapasRet. Ver [[Licoes]].
