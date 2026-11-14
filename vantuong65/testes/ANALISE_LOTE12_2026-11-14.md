# Análise do jogo: bots, gráficos, armas, tiros e veículos (lote 12, 2026-11-14)

Pedido do dono: "analise tudo do principal do jogo: bots, gráficos, armas, tiros, veículos" (junto do
lote 6: análise com ideias em imagens).

**Como foi medido:** Studio pelo MCP, place da v56 (commit 43f7266) e depois com as correções da v57.
Play solo, o jogador como fuzileiro dos EUA no QG; bots enchendo os dois lados. Toda medida abaixo
saiu de código rodado no Studio (servidor ou cliente) ou do autoteste (`VT65SelfTest`). As capturas
estão em `testes/lote12/`.

**Limite do teste:** o PC do dono roda o Studio a 7–15 fps no cliente, e o servidor a 34–35 Hz
(cliente e servidor na mesma máquina, GPU de 2 GB). Os números de desempenho valem para comparar,
não para dizer como o jogo roda num servidor do Roblox. Um controle ligado ao PC, com o analógico
esquerdo marcando (−0,76; 0,83) parado, abria menus sozinho; os testes desligaram o controle.

## Resumo
| Área | Resultado | Ação |
|---|---|---|
| Autoteste | 14 ok e 4 falhas antes; **17 ok e 1 falha** depois | 3 falhas eram do próprio teste; corrigido |
| Bots | andam, tomam pontos, primeiro tiroteio aos 86 s; **embarque em loop no LVTP-5** | **corrigido** |
| Lotação | teto caiu para 22–24 por lado (meta 30) com o servidor a 34 Hz | ideia: desempenho |
| Armas e tiros | 10 armas com alça e massa a 0,1 px do centro; o tiro vai onde se mira | ok |
| Cadência | abaixo da ficha só com menos de ~12 fps (um tiro por quadro) | ideia |
| M14 | a alça de anel tapa ~70% da tela mirando | pergunta ao dono |
| Pistolas | no quadril, a mão de apoio fica solta sob a arma | ideia |
| Type 54 | escura em 1ª pessoa (a "cinza-clara" é a cor de base sem a textura) | conferir em 3ª pessoa |
| Veículos | M151: 0 → 34 km/h em ~3 s, 41 km/h aos ~5,5 s | ok |
| Gráficos | capim escuro e chapado; base do VC num campo aberto | pergunta e ideia |

## Autoteste
Rodado com o jogador em campo. Antes (v56):
```
[VT65 TESTE] FALHA vida no mapa: dossel 37, ladrilho com recorte true, lamparinas 42, fumaças 13, medas 0, potes 0, bezerros 2
[VT65 TESTE] FALHA chuva: Rain=1: false; névoa 0.26 → 0.26
[VT65 TESTE] FALHA pá de trincheira: chão à frente desceu 0.02 m (esperado ~1,2 m; ...)
[VT65 TESTE] FALHA Offensive + relatório pós-ação: frente S3, prazo 35 min, fim=true, relatório SEM a captura
[VT65 TESTE] resumo: 14 ok, 4 falhas, 0 pulados
```
Causas (todas do teste, não do jogo):
- **vida no mapa:** procurava os nomes antigos das medas e potes (`MedaDePalha`, `PoteDagua`); hoje são
  modelos do Blender (`straw_stack`, `water_jar`: 18 e 53 no mapa). E pedia mais de 500 tabuleiros de
  arroz; desde a D-114 são 37;
- **chuva:** o teste rodava na contagem do começo (D-122), e na contagem a chuva não muda;
- **Offensive:** o relatório escreve a letra do setor ("USMC toma B (...)"); o teste procurava "toma S2";
- **pá:** em três sessões, falhou na 1ª rodada (0,01 a 0,04 m) e passou na 2ª (0,76 m). Na 1ª, o
  aviso do jogador foi só "Cavando… fique parado 8 s", sem "cancelado": a pá cavou, mas a sonda do
  teste não viu o buraco. Pedir o streaming do lugar antes do teletransporte não resolveu (testado e
  tirado). **Fica aberto:** saber onde o buraco da 1ª rodada foi parar.

Depois (v57): o teste fecha a contagem ao começar, conta os nomes novos e procura a letra. Resultado,
numa sessão nova: `[VT65 TESTE] resumo: 17 ok, 1 falhas, 0 pulados`
- o Offensive passou: "frente B, prazo 35 min, fim=true, relatório com a captura";
- a falha que restou foi a pá na 1ª rodada.

A granada de bot caiu a 2,7–2,9 m do alvo em três rodadas e a 5,4 m em uma (falha). É sorteio do
arremesso; o teste fica como está.

## Bots
**Lotação e carga** (`VT65DevBots = "carga"`, 2 min de partida):
```
[VT65 TESTE] bots: EUA 24 (24 em campo), VC 24 (24 em campo); teto 24 por lado (hold); Heartbeat 35 Hz; montando 0
[VT65 TESTE] bots: nível 1/2/3 = 12/10/26; 62 pensamentos/s; PathfindingService: fila 0, em curso 0, 211 feitos; rotas A* na fila 0
```
- o teto de bots desce sozinho quando o servidor fica lento (D-107). Com 34–35 Hz no Studio ele parou em
  22–24 por lado, abaixo dos 30. Num servidor do Roblox (60 Hz, sem o Studio junto) deve chegar a 30;
  não foi medido lá;
- o tempo de cada quadro do servidor foi 1,8 ms (`Stats.HeartbeatTimeMs`); o que pesa é a máquina.

**Movimento em 180 s** (posição de cada bot a cada 10 s, depois da contagem):
- 46 bots no começo: 9 morreram, 4 estavam em veículo no fim, 33 a pé;
- deslocamento a pé: mediana 38 m, p10 1 m, p90 156 m;
- parados a menos de 3 m em todas as janelas de 60 s: 2. Os dois estavam guardando objetivo
  (um VC a 18 m de Xóm Gò, um dos EUA a 53 m de An Cường (2));
- primeiro tiroteio da partida aos 86 s.

**Squads** (`VT65DevBots = "frente"`): os 8 squads atacavam o B logo depois da contagem, a 236–289 m
do ponto, todos em "move".

**Bug achado e corrigido: embarque em loop no LVTP-5.** O log mostrava o mesmo bot "embarcando"
várias vezes por segundo, ora no mesmo lugar, ora pulando de um assento para o outro
(Bot_US_22: 47 vezes no p1; Bot_US_06: 25; Bot_US_17: 31).
- Causa: o passageiro entrava com a tripulação ainda no estado "board", mas o `seatedThink` só o
  deixava sentado em "load" ou "go" e com o motorista sentado. Ele descia, e o `calm` o punha de
  volta, num ciclo sem fim (`BotVehicles.luau`).
- Agora o passageiro espera sentado em "board" e "load"; na marcha ("go") continua precisando do
  motorista.
- Depois: 18 embarques de 14 bots numa sessão de ~8 min (com partidas reiniciadas pelo autoteste),
  no máximo 2 por bot.

## Armas e tiros
**Onde o tiro vai:** mirando em 1ª pessoa, o tiro sai do olho (a câmera) na direção do centro da tela
(`WeaponController.shotRay`). Então ele vai onde a mira aponta se a alça e a massa estão no centro.
Medido arma por arma, mirando (`Sight` e `SightFront` projetados na tela):

| Arma | Alça | Massa | Linha × visada | Olho até a alça |
|---|---|---|---|---|
| M1911 | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,02° | 53,2 cm |
| M60 | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,02° | 16,8 cm |
| M79 | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,00° | 12,6 cm |
| Winchester 12 | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,00° | 16,8 cm |
| M70 | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,00° | 10,5 cm |
| Type 56 | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,02° | 26,9 cm |
| SKS | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,00° | 36,4 cm |
| RPD | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,00° | 16,8 cm |
| Type 54 | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,02° | 53,2 cm |
| Mosin | (−0,1; 0,1) px | (−0,1; 0,1) px | 0,00° | 10,1 cm |
| M14 | (−0,3; 0,1) px | (−0,1; 0,1) px | — | 6,3 cm |

Todas no centro. O servidor confere a origem do tiro (até 8 studs da cabeça). Nos testes, ele recusou
tiros por "origem" só porque a câmera do Studio ficou presa a 26,8 m do soldado depois do autoteste
(efeito do MCP, não do jogo).

**Cadência** (`VT65DevRajada`, 1 s de gatilho, com o Studio a ~10 fps):
- RPD 9 tiros (a ficha dá 11,7 por segundo);
- M60 8 (ficha 9,2);
- Type 56 10 (ficha 10,8).

O gatilho solta no máximo um tiro por quadro (`Gatilho.step`). Abaixo de ~12 fps, a cadência fica presa
ao fps. A 20 fps ou mais (PC e celular comuns), a ficha se cumpre. Ideia: deixar sair mais de um tiro
no mesmo quadro quando o quadro é mais longo que o intervalo (o servidor já aceita 2 de crédito).

**M14 mirando** (`04_m14_mirando.jpg`): o olho fica a 6,3 cm da alça de anel
(`EYE_ANEL_M` = 4,5 cm vezes a escala da arma). O anel e a massa ficam no centro, mas as orelhas da alça
tapam ~70% da tela (estimado na imagem). Em 2026-11-11 o olho foi aproximado de propósito: com 6,5 cm
o anel ficava pequeno. **Pergunta ao dono:** afastar o olho (anel menor, mais tela livre) ou deixar como
está?

**Pistolas no quadril** (`02_type54_quadril.jpg`): a mão de apoio fica solta, abaixo e à esquerda da
pistola. Mirando, as duas mãos seguram o punho (`01_type54_mirando.jpg`). Pode ser a "mão
escorregando" que o dono citou.

**Type 54:** em 1ª pessoa ela aparece escura (a malha tem `SurfaceAppearance`). A cor de base da malha
é cinza-clara (163, 162, 165): é o que aparece se a textura não carrega. A 3ª pessoa e a arma caída
não foram conferidas.

**RPD mirando** (`03_rpd_mirando.jpg`): o entalhe e a massa no centro; a caixa da alça ocupa a parte de
baixo da tela, como numa metralhadora de verdade.

## Veículos
- 9 veículos nos depósitos, todos com assento e nenhum andando sem motorista (autoteste).
- M151 dirigido pelo jogador (`VT65DevDrive`, W segurado): 0 → 34 km/h em ~3 s e 41 km/h aos ~5,5 s;
  41,6 m andados.
- As tripulações de bots embarcaram e saíram da base: M48 a 12–14 km/h na grama, LVTP-5 a 5–14 km/h.
- Medevac: o UH-34D pousado levou o ferido.

## Gráficos
- **Capim escuro** (`05_capim_atual.jpg`): o terreno multiplica a textura pela cor. Com a cor do capim
  em (72, 92, 42), a mistura dá perto de (43, 47, 15): um verde-oliva quase preto e chapado, em que o
  relevo some. Com (100, 134, 74) ele fica verde natural e os diques aparecem (`06_capim_mais_claro.jpg`).
  O código diz "mais claro parecia gramado" (decisão antiga). **Pergunta ao dono:** clarear?
- **Base do VC num campo aberto** (`07_base_vc.jpg`): as barracas, as redes e a cozinha estão lá
  (43 modelos a menos de 80 m do QG), mas no capim, em fila. O desenho era o acampamento sob a mata;
  no mapa de 700 m o QG do VC caiu numa área de capim. Ideia: plantar a mata em volta do acampamento.
- **Mata do objetivo A** (`08_mata_objetivo_a.jpg`): fechada como o pedido (bambus, árvores e capim
  alto).
- **Peso da arte** (log do servidor): a mata planejada soma ~33,8 milhões de triângulos no setor A,
  ~26,9 no C e ~14,1 no B; o cliente carrega por distância (960 modelos perto do jogador). No Studio o
  cliente rodou a 7–15 fps. Ideia: um lote só de desempenho, medido num celular de verdade
  (níveis de detalhe da mata, sombra, distância de desenho).
- As capturas longe do soldado saem vazias se a arte não chegou ao cliente: é o streaming, não falta
  de arte.

## Ideias para os próximos lotes
1. Desempenho: medir num celular e num servidor do Roblox (fps, Hz, teto de bots) e aliviar a mata.
2. Gatilho: recuperar a cadência abaixo de 12 fps.
3. Pistolas: a mão de apoio no quadril.
4. Base do VC sob a mata.
5. Os nomes do equipamento da Intendência vêm do servidor sem tradução (com o jogo em inglês,
   apareceu "Bandoleira M2 de algodão").
6. Conferir a Type 54 em 3ª pessoa e caída no chão.

7. A pá do autoteste na 1ª rodada de cada sessão.

Perguntas: a M14 (afastar o olho?) e o capim (clarear?).
