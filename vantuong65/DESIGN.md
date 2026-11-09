# VẠN TƯỜNG '65 — Decisões de design (DESIGN.md)

Formato: **ID — decisão**, seguida de motivo, evidência e status. Status possíveis: *firme* (decidido),
*provisória* (vale até alguém mexer) e *pendente* (espera resposta do usuário; a pergunta está em
PROGRESS.md).

## D-01 — Onde o projeto mora (provisória)
O jogo fica em `vantuong65/`, dentro do repositório `felpo2007/a-o`, na branch
`claude/bold-albattani-67hga9`.
- Motivo: é o único repositório liberado nesta sessão, e o resto dele é outro projeto (estratégias de
  trade, ver `../CLAUDE.md`). A subpasta isolada, com `pyproject.toml` e `uv.lock` próprios, não
  interfere nos testes nem nas dependências desse projeto.
- Recomendação: mover para um repositório próprio (por exemplo `vantuong65`) antes da F1, quando
  entrarem Rojo, Wally e o código Luau. O histórico desta pasta pode ser levado junto com
  `git subtree split`.

## D-02 — Unidades e quadro local (firme)
- 1 stud = 0,28 m (doc oficial de unidades do Roblox). Conversões em `tools/geo.py` (`STUD_M`).
- Origem (0, 0, 0) no centro da área jogável. **+X = leste, +Z = sul** (no Roblox, −Z = norte),
  +Y = altura. A altura 0 é o nível médio do mar (EGM2008).
- Referência espacial oficial: WGS 84 / UTM 49N (EPSG:32649). As grades de 1965 ("BS xxxyyy") são
  convertidas por `geo.ing_to_wgs_utm`; nunca use uma grade de 1965 direto como WGS 84, porque o
  erro chega a cerca de 600 m.

## D-03 — Tamanho da área jogável (PENDENTE, pergunta P1)
Proposta: **4,0 km (leste–oeste) × 2,4 km (norte–sul) em 1:1**, com limites em grade de 1965 de
E 268,2–272,2 km e N 1691,2–1693,6 km (`geo.PLAY_ING`).
- Motivo: medido na carta, a Colina 43 fica a **3.255 m** da Green Beach no eixo leste–oeste, e a
  LZ Blue a **2.950 m**. O quadrado de 2 × 2 km do prompt não comporta as duas bordas sem violar a
  escala 1:1 (princípio 1). A Colina 30 fica a cerca de 600 m de An Cường (2), e não a 400 m, por
  isso o norte–sul precisa de 2,4 km.
- Custos: 9,6 km² em vez de 4. A densidade fica em 6,25 jogadores/km², cerca de 25% da referência de
  100 jogadores em 4 km². Uma travessia leste–oeste a pé com corrida leve (~3 m/s) leva cerca de
  22 min, então o critério "8–12 min" da F1 deixa de valer. Compensação: UH-34D como táxi, LVTP,
  pontos de reunião avançados e pontos fortes compactos.
- Alternativas: (B) 2,2 × 2,2 km no oeste (Colina 43 → An Cường 2 / Colina 30), com a praia fora
  e os EUA entrando pela borda leste; (C) 2 × 2 km no leste (praia → An Cường 2), sem Colina 43 nem
  LZ Blue. Comprimir a escala leste–oeste está descartado, porque viola o princípio 1.

## D-04 — Georreferenciamento (firme até a pergunta P4)
Carta L7014 6739 I ed. 3 (GeoPDF) → LGIDict → ING-A/UTM 49 → TR8350.2 (198, 881, 317) → correção
empírica de dE −18,2 m e dN +5,3 m → WGS 84/UTM 49. Resultados e limites em
`research/F0_GEORREF.md`.

## D-05 — Green Beach e as trincheiras (provisória)
- A **Green Beach** fica na praia de **An Cường (1)**. É o que dizem H1 (PDF p. 21: a vila poupada do
  bombardeio e a Hill 22 logo depois dela) e a carta (△22). A frase "Green Beach at An Cuong (2)" de
  H1 (PDF p. 18) contradiz a p. 21 e foi tratada como erro. A extensão norte–sul da praia fica
  pendente do AAR (H4).
- Há **duas trincheiras** nas fontes:
  1. a "wide, deep trench south of [An Cường 2]" e as trincheiras cobertas da vila (H1, PDF p. 23 e
     25), **dentro** da área proposta. É esta que o jogo usa como ponto forte "Trincheira VC";
  2. a "trench line" que parou a Cia K cerca de 2 km ao **norte** da praia (H1, PDF p. 21), perto de
     Vạn Tường (4)/(5), **fora** da área de 2,4 km norte–sul.

## D-06 — Relevo (provisória)
Heightmap v0 feito do Copernicus GLO-30 (DSM), com abertura de 70 m e suavização gaussiana de 15 m,
a 8 studs/px. Serve para o greybox. O definitivo será um DTM interpolado das curvas e cotas da carta
(passo 6 de F0_GEORREF), com diques, sebes e túmulos esculpidos à mão.

## D-07 — Altura das sebes (PENDENTE, conferência por fotos)
O prompt pede "sebe de bambu de 3–8 m" em volta das vilas. H1 (PDF p. 10) diz que os arrozais eram
divididos por "hedgerows six to eight feet high" (1,8–2,4 m) de bambu e madeira dura.
- Proposta: **sebes de arrozal com 1,8–2,4 m** (fonte H1) e **touceiras de bambu das vilas com
  3–8 m** (valor do prompt, a confirmar no dossiê de fotos de 1965).
- O impacto é grande: isso muda as linhas de visão e a ocultação nos arrozais.

## D-08 — Setores (PENDENTE, depende de D-03)
Com a área de D-03, as 5 faixas norte–sul ficam com fronteiras ajustadas para nenhum local real ser
cortado (grade de 1965, E em km):

| Setor | E (km) | Largura | Locais inteiros |
|---|---|---|---|
| S1 (oeste, início do VC) | 268,2–269,3 | 1,10 km | Colina 43, Lạc Sơn (1), Athletic field, LZ Blue, Nam Yên (3) |
| S2 (início do VC) | 269,3–269,85 | 0,55 km | Nam Yên (4), An Thới (2) |
| S3 (centro, neutro) | 269,85–270,5 | 0,65 km | An Cường (2), trincheira, riacho, Colina 30 |
| S4 (início dos EUA) | 270,5–271,3 | 0,80 km | An Phước (1), arrozais abertos |
| S5 (leste, QG dos EUA) | 271,3–272,2 | 0,90 km | An Cường (1), △22, Green Beach, mar |

As larguras ficam desiguais (0,55–1,10 km). A alternativa é aceitar a fronteira atravessando Nam Yên
(3), que vai de E 268,85 a 269,26.

## D-09 — Referências visuais enviadas pelo usuário (firme)
As 10 capturas de tela de um FPS comercial sobre o Vietnã servem **só** como referência de luz
(contraluz dourado, névoa úmida, densidade de folhagem) e de enquadramento da arma em primeira
pessoa. Elas **não** entram no repositório, que é público e onde elas seriam material protegido.
Nenhuma UI, HUD, menu de papéis, ícone ou layout delas será reproduzido (Parte 1, propriedade
intelectual). Não tenho como assistir a vídeos, então a análise se limitou a essas imagens.

## D-10 — Prioridade do ForgeGUI quando houver crédito (firme)
Saldo atual de 100 créditos. Um modelo 3D custa ~4.000, e um som ~1.600 (valor medido na recusa de
hoje). Ordem do que é mais necessário para a F3 (fatia vertical):
1. retry dos 6 modelos com falha do Lote 1, todos com checkpoint: **M14, Type 56, bunker VC, bambu,
   coqueiro, UH-34D** (~24.000);
2. sons: tiros de M14 e Type 56. Os jobs antigos estão em `outcome_unknown` e **não podem** ser
   regerados com o mesmo id; é preciso ver o resultado ou pedir um novo id. Depois, a ambiência de
   arrozal e o loop do UH-34D (~6.400);
3. o resto do Lote 4 (vila) e do Lote 5 (vegetação), que define o visual do setor central.
Os assets já prontos (casa de palha e ícone) estão listados em `ASSETS.csv`. O host de
armazenamento do ForgeGUI está bloqueado pela rede desta sessão, por isso ainda não baixei nem contei
triângulos.

## D-11 — Escopo do jogador (firme)
A run do Lote 1 descreve "50v50", mas o projeto atual é 30v30 (prompt mestre). Vale o 30v30, e a
nota foi registrada na run.
