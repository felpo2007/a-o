# VẠN TƯỜNG '65 — Progresso

## Fase atual (2026-11-11, sessão 7: teste fase a fase no Studio, D-75)
| Fase | Estado |
|---|---|
| F0 Pesquisa | parcial: critério de 25 m atingido no setor oeste; setor leste depende da CORONA (`research/F0_CORONA.md`) |
| F1 Greybox | **testado no Studio**: terreno em 14 s, arte no chão (3.770 de 3.772 a até 2 m) |
| Monetização | implementada (`MONETIZATION.md`); os 2 Game Passes de kit e o renascer em Robux **esperam a permissão** (TODO_USUARIO) |
| F2 Loop central | **testado no Studio** com bots (14 x 15): nascimento, espera, raia e balística, dano de explosão |
| F3 Fatia vertical | **testado no Studio**: deitado, rádio (antena corrigida na D-75), tutorial |
| F4 Sistemas pesados | **testado no Studio**: 6 veículos parados com assento, túneis e spawn do VC, pá, medevac, morteiro. Critério 30v30 com 6 veículos **só no Roblox** |
| Parte 12 Controle | 19 regras no Lune; **não testado num controle real** (o Studio do MCP injeta o botão como teclado) |
| F5 Arte total e otimização | arte nos 5 setores a 100% do plano; 57,1 fps girando a câmera na célula mais densa da mata (D-76) e 59,6 fps no arrozal (D-74). Critério de 60 jogadores **só no Roblox** |
| F6 Offensive e lançamento | **testado no Studio**: Offensive com relatório pós-ação, progressão. Beta fechado **só você pode rodar** |

## v42: caixa de munição à vista no capim e rodas do UH-34D (2026-11-13, D-110)
- **Publicada** como versão 42 do place (build do commit 704c3c2).
- **Feito:**
  - a caixa de munição abre uma clareira de terra pisada no capim do terreno (cerca de 1,2 m);
  - as rodas principais do UH-34D v2 passam a se chamar Roda_E e Roda_D (antes, as duas eram Roda_E).
- **Conferido no Studio:**
  - Ground sob a caixa e a 0,8 m; capim a 2,5 m; na foto, a caixa aparece numa clareira;
  - rodas Roda_E (x = −7,6), Roda_D (x = +7,6) e Roda_Cauda nos dois helicópteros;
  - 0 erros de script.
- **Pendente:** o soldado com 2,08 m (a meta da D-98 é 2,00 m). Mexe na escala do corpo e nas pegadas;
  fica para quando o dono pedir.

## v41: bots do Front 44, sem fogo amigo, corrida, celular e carregamento (2026-11-13, D-109)
- **Publicada** como versão 41 do place (build do commit 8013574).
- **Feito** (14 pedidos do dono de 13/11, sozinho, sem agentes):
  - celular sem nada por cima (caído, avisos, faixa no alto) e objetivos A–E;
  - sem a parede vermelha (disco do evento) e sem fogo amigo;
  - corrida com a arma de lado (1ª pessoa), retícula do quadril e bots com o combate do Front 44;
  - som da metralhadora do tanque para quem atira, barracas 1,5x e nomes curtos das armas;
  - mais leve e o mapa carregado na tela de início.
- **Conferido no Studio (Play, 1 jogador, 100 bots):**
  - letras A–E na faixa e nos nomes; barracas maiores na base;
  - corrida em 1ª pessoa com a arma atravessada no peito;
  - retícula do quadril ligada em 1ª pessoa (pelo estado: a captura do MCP troca a câmera e ela some
    da foto);
  - tiro de M14 num aliado a 10 m: vida 100 → 100; no inimigo: 100 → 62,6;
  - som do canhão de 90 mm carregado e tocando (5,0 s); nenhum disco de evento no mundo;
  - caído no modo toque: cartão no canto de baixo à esquerda, DESISTIR livre, "Segure DESISTIR"
    legível, avisos pequenos à esquerda, captura escondida;
  - tela de carregamento com as etapas novas; avisos de tipo de asset de 511 para 7; 0 erros de
    script;
  - primeiro tiroteio dos bots aos 46 s, a 29 m;
  - servidor a 60 Hz. Cliente a 15 fps no Studio deste PC (render de 66,8 ms na qualidade 1; script
    2,2 ms).
- **Medido no Lune:** bot do Front 44 contra jogador parado em 3 s: 10 m 100%; 25 m 81% / 50%; 40 m
  34% / 16% (automática / semi).
- **Não testado:** celular de verdade (fps e carregamento), a metralhadora do tanque atirada por um
  jogador, investigar e granada dos bots vistos de perto, 2 jogadores.
- **Pendente** (os dois primeiros feitos na v42): a caixa de munição no capim alto; as duas rodas
  "Roda_E" do uh34d_v2; o soldado com 2,08 m.

## v40: classes simples, Suporte com caixa, espingarda, armas maiores e nada flutuando (2026-11-13, D-108)
- **Publicada** como versão 40 do place (build do commit 1ef8480).
- **Conferido no Studio (Play, 1 jogador):**
  - 50 contra 50 bots, servidor a 56 Hz, primeiro tiroteio aos 51 s;
  - gancho `VT65DevFlutua`: 0 bases e 0 casas no ar, mata e objetos com 1 canto cada (≤ 0,23 m),
    veículos parados a ≤ 0,10 m do chão (UH-34D a −0,01 m);
  - Winchester 12 em 1ª pessoa maior; a 8 m um tiro somou 108 de dano (9 bagos) e derrubou o bot;
  - caixa de munição do Suporte posta pelo gancho `VT65DevCaixa`, no chão;
  - nenhum erro de script no cliente nem no servidor.
- **Achado:** a caixa (0,54 m) some em parte no capim alto do terreno. Fica para a v41.
- **Não testado:** prévia de colocação pela tecla 0, pegar da caixa, mira de cada arma com a escala
  1,4, troca de arma no cartão, migração de perfil antigo, celular de verdade, 2 jogadores, sons.

## v39: lista do dono de 12–13/11 (2026-11-13, D-107)
- **Publicada** como versão 39 do place (build do commit d1288ae).
- Oito frentes em paralelo: combate, morte e feridos, telas, movimento e 3ª pessoa, itens e
  fumaça, bots, veículos e som, celular. Mais o vento tirado.
- **Causa do "tiro não acerta":** o servidor recusava todo tiro de jogador desde 2026-11-09
  (relógio e semente fora de um limite de 1e7).
- **Conferido no Studio (Play, 1 jogador):**
  - carregamento antigo de volta;
  - 50 contra 50 bots, servidor a 44–52 Hz, teto em 50;
  - primeiro tiroteio de bots aos 48 s de partida (meta: 3 min);
  - JOGAR AGORA põe no squad e no ponto;
  - tiro de jogador aceito (carregador desconta, sem recusa);
  - acerto num bot a ~17 m confirmado pelo servidor (tronco, 36 de dano) e o bot caiu ferido;
  - 21 caídos deitados de costas a ~1 cm do chão;
  - arma em 3ª pessoa nos bots, com capacete encaixado;
  - tela de baixa com o soldado no chão e os botões coloridos;
  - HUD de celular forçado só com MAPA, MENU, COMUNICAR, RÁDIO, MIRA, ITEM, FOGO, AGACHAR, PULAR,
    analógico e cartão, sem dica de tecla.
- **Corrigido no teste:**
  - o cartão de idioma da primeira vez ficava por cima do jogo ao entrar direto pelo JOGAR AGORA;
  - erro antigo "ColorSequence: color value out of range" na loja.
- **Achado de ferramenta, não do jogo:** a captura de tela do MCP deixa a câmera do Studio em
  Scriptable (presa); antes de atirar no teste, volte a câmera para Custom.
- **Não testado:** som (ninguém ouve no teste), celular de verdade, 2 jogadores, voz, pilotar o
  helicóptero e a compra de veículo na tela de baixa. O desempenho com 100 bots num servidor do
  Roblox e no celular também não foi medido.

## v38 testada no Studio e publicada (2026-11-13, D-106)
- **Publicada** como versão 38 do place (build do commit 95e45b5).
- **Conferido no Studio:**
  - servidor sem erro de script; terreno em 15 s; 1.382 modelos de arte;
  - os 9 veículos nas vagas das bases;
  - base dos EUA, acampamento do VC e casas novas da vila no lugar;
  - boneco de bloco do Front 44 no menu.
- **Blindados de bot (D-106):** antes empacavam na baia. Agora saem, passam pelo portão, chegam ao
  objetivo (M48 em apoio; LVTP-5 desembarca o squad) e voltam. Testado em dois objetivos.
- **Avisos que ficam:**
  - soldado com 2,07 m (meta 2,00 m);
  - 15 construções mais de 0,6 m fora do patamar;
  - o Studio avisa malhas sem representação alternativa (ruído do Studio).
- **Não testado:** compra de veículo, pilotar, celular real, voz.

## Veículos do Blender na medida real, em peças (2026-11-12, D-104)
- Os 7 modelos novos (m48a3_v2, ontos_v2, lvtp5_v2, uh34d_v2, m151, m35, peugeot403)
  com a tabela ART nova; torre, cano, rotores, rodas, escotilhas e portas em Motor6D; rodas,
  rotores, volante e torre (pela mira do atirador) animados no VehicleFx.
- Tropa do UH-34D dentro do porão; olho do Peugeot 8 cm mais baixo (cabeça sob o teto).
- **Não testado no Studio.**

## Veículo ao nascer (2026-11-12, D-103)
- Na carta de inserção, "Levar veículo": EUA M151 ou M35, VC Peugeot 403, em CI ou Robux (3
  Developer Products a criar, ID 0 em Commerce.IDS). Sai a 4-10 m, virado para o objetivo; só
  cobra depois de achar o lugar.
- Regras no Lune (	ests/luau/compraveiculo.luau, 10 testes). **Não testado no Studio.**

## Soldados no formato do Front 44 (2026-11-12, D-102)
- Boneco de bloco do R15 com as quatro escalas iguais (as proporções do Front 44) na altura de 2 m
  (2,04 m, 0,8 m de ombro), pele lisa, farda de tecido, capacete na cabeça de bloco.
- 24 rostos de época em `assets/rostos` (a subir; ids em `Corpo.ROSTOS`).
- **Não testado no Studio.**

## Inclinar do Front 44, curativo que estanca, itens animados e mãos de 1ª pessoa (2026-11-12, D-99)
- **Inclinar:** Q/E a qualquer hora a pé (controle: L3/R3 mirando), como no Front 44: 8/s, câmera
  0,35 m de lado e 14° de giro, arma de 1ª pessoa junto, tronco replicado (19,6°) e colisão com a
  parede (não espia através dela). Antes só existia na camada de mira e era zerado fora dela.
- **Passo do Front 44:** arrancada e parada mais secas, agachado 1,4 m/s e rastejar 0,5 m/s, deitar
  e levantar mais curtos.
- **Sangramento ~5x mais lento** (pistola no tronco ~3 min até cair) e **o curativo estanca**; a
  bandagem rápida põe o torniquete na artéria junto.
- **Itens animados** em 1ª e 3ª pessoa (todos veem): curativo, torniquete, curativo no companheiro,
  tratar, reanimar, rádio, binóculo, pá e cantil; 9 clipes novos (`tools/anim`, a subir).
- **Mãos de 1ª pessoa** com dedos, palma e manga (peças); malhas do Blender em
  `assets/blender/maos_1p` (a subir).
- **Vantagens do corpo** aplicadas no servidor: velocidade (trote e corrida), vida máxima, tempo de
  curativo e sangramento.
- **Não testado no Studio.**

## Soldado de 2 m, capacetes e carta na mão (2026-11-12, D-98)
- **Soldado de 2,0 m** (decisão do dono): o corpo de 1,75 m ampliado por igual (K = 1,1429).
  Postura, câmera, água, degraus, câmera do ombro, olhos nos veículos e equipamento acompanham.
  Os clipes tocam sem regravar; armas e facas ficam no tamanho real.
- **Capacetes** com no mínimo o tamanho real do casco (M1: 27 × 30 cm × K).
- **Carta na mão:** abrir o mapa põe a carta nas duas mãos e o fuzil a tiracolo; todos veem
  (atributo "Carta" do servidor). Em 1ª pessoa, as mãos com a carta ficam embaixo da carta grande.
- **Túneis:** o soldado de 2 m passa deitado; o poço ficou com 1,0 m e a escada na parede.
  Precisa assar o place de novo.
- **Não testado no Studio.**

## Corpo a corpo, braços e bots animados (2026-11-11, D-94)
- **Facas de 1965 no Blender** (`tools/faca`): Ka-Bar USMC, baioneta M6, espigão do Tipo 56 e
  facão do VC, com bainha, atlas PBR de 1024 e prévia no Cycles. GLB e sons no `upload_plan`
  (chaves em 0 em `AssetIds`); sem eles, faca de peças.
- **Facadas:** estocada (certeira no tronco derruba), golpe de lado, baioneta e coronhada
  (`Shared/Melee`); acerto resolvido no servidor no instante do impacto (alcance 1,4–2,1 m, cone e
  linha livre); bots golpeiam a ≤ 1,5 m. 1ª pessoa com saque, antecipação, follow-through, balanço
  e tranco no impacto (`KnifeView`); 3ª pessoa com 5 clipes novos (`tools/anim`, a subir).
- **Braços:** na simulação do Lune o antebraço entrava 13 cm no peito e a coronha 20 cm; com polo
  de cotovelo, tronco de lado e pega nova, 0 cm nos fuzis e metralhadoras e 1 cm na pistola
  (`tests/luau/faca`).
- **Câmera agachada** na cabeça da animação: `DROP.crouch` 2,2 → 1,03 stud.
- **Bots animados** no cliente com nível de detalhe (`SoldierAnims.BOTS = true`); custo com 58 bots
  **não medido**.
- **Não testado no Studio.** Subir: 4 GLB, 4 sons e 9 clipes (TODO na D-94).

## v36 publicada (2026-11-11, D-91 a D-97)
- **Espera e som:** nascer em 10 s; som mais baixo, com música no menu; 50 x 50 jogadores.
- **Mapa:** de 1 x 1 km (terreno em 7 s, arte de 3.775 para 1.510 modelos), com carta nova.
- **Bots:** usam o mapa, os veículos e os túneis.
- **Movimento:** água sem nadar no raso, VC ×1,12, veículos sobem dique.
- **Facas e braços:** facas e facadas; braços fora do corpo.
- **Menus:** revisados (pilha de voltar, loja com abas, câmera nivelada na chegada).
- **Modelos do Blender:** 13 refeitos publicados.
- **Testado no Studio:** lobby, inserção EUA e VC, câmera de chegada, menus, loja, carta, faca e
  marcadores.
- **Não testado:** fps real, água andando (o teclado simulado do Studio não move o soldado) e
  controle físico.

## Sessão 7 (2026-11-11): vida no mapa e teste fase a fase (D-74, D-75)
- **Arrozal vivo:** arroz em cartões nos 989 tabuleiros plantados (perto: ladrilho de 384
  triângulos; longe: dossel verde). Muda nova e pousio em parte dos tabuleiros. 59,6 fps no meio
  dos arrozais.
- **Animais:** búfalo e galinha reduzidos (4.999 e 3.000 triângulos), 138 animais (eram 79) e
  manadas com bezerro no arrozal das vilas.
- **Túneis:** escoras, 44 lamparinas, câmaras de comando/enfermaria, depósito e cozinha; sem capim
  dentro das galerias.
- **Vilas:** fumaça de cozinha, potes d'água, medas de palha e lenha; canteiros de muda nas 5
  vilas.
- **Autoteste:** 17 verificações (eram 12), **17 ok**. Corrigidos: antena do operador de rádio e
  ponto do teste da pá.
- **Garças (D-76):**
  - bandos nos tabuleiros em pousio e de muda, e uma garça junto de cada búfalo;
  - levantam voo com tiro (120 m) ou explosão (300 m) e voltam em 1–2 min.
- **Partida longa (D-76):** 6 min de bots, servidor a 60 quadros por segundo, memória estável e
  nenhum erro de script.
- **Aviso falso de altura do soldado removido:** todos medem 1,68 m.
- **D-77:**
  - animais em partes, andando de verdade: passo do búfalo em quatro tempos, trote na fuga;
    pastam e ciscam parados;
  - granadas com modelo, voo na gravidade real, arremesso em 1ª pessoa, braço visto por todos e
    explosão com efeitos;
  - soldado de 1,75 m;
  - bots de nível médio que usam abrigo e postura;
  - pop-ups novos e tutorial no canto.
- **D-78:** pente-fino fase a fase com tudo junto. 1 erro corrigido (braço do arremesso em junta
  `AnimationConstraint`); autoteste 17 ok; 0 erros de script em ~18 min de partida com bots.

## F6: o que foi feito (sessão 6)
- **Modo Offensive** (`Shared/Offensive.luau`, D-46):
  - EUA desembarcam em S5 e atacam para oeste; o VC defende S4→S1;
  - só a frente fica ativa, e setor tomado fica travado;
  - relógio de 20 min, +15 min por captura (PLACEHOLDER);
  - bots, spawn e logística funcionam sem mudança;
  - 7 testes em `f6.luau`.
- **Partida:** `MatchService` roda o Offensive. O servidor público alterna Warfare e Offensive.
  No mapa, o status mostra a frente e, no fim, o vencedor.
- **Servidor privado:** a aba "Servidor" no menu do jogo deixa o dono escolher modo e horário.
  Antes não havia tela para isso.
- **Tutorial por papel e campo de tiro** (D-47):
  - um passo por vez, avançando quando o jogador faz a ação;
  - funciona no controle, no teclado e no mouse;
  - alvos a 100/200/300 m ao lado de cada QG, com o desvio do centro em cm;
  - progresso salvo por papel;
  - os textos são testados contra o InputMap e a logística, para não prometer o que o jogo não
    faz.
- **Bug corrigido:** as configurações de controle sumiam a cada login, porque o `migrate` do
  perfil as descartava. Agora há um teste de regressão.
- **Página do jogo** (`LANCAMENTO.md`):
  - descrição em português e inglês;
  - ícone 512×512 e miniatura 16:9 (`tools/make_store_images.py`);
  - guia do questionário de maturidade conferido no código;
  - roteiro do beta.

## Features de lançamento da Parte 11 (sessão 6, D-48)
Todas as 13 features marcadas "Lançamento" estão no código:
- acessibilidade (daltonismo medido por simulação, FOV, legendas);
- relatório pós-ação;
- marcação imperfeita;
- arma do inimigo;
- equipamento por peso;
- operador de rádio;
- pá de trincheira;
- medevac;
- animais da vila;
- além das que já existiam: bots, monetização, campo de tiro e tutorial.

Cada regra tem teste em `f6.luau`. Búfalo e galinha vieram do ForgeGUI e foram reduzidos
localmente para 3.999 e 2.000 triângulos. Nada disso rodou no Roblox.

## F5: o que foi feito (sessões 5 e 6)
- **Remesh:** 18 modelos de uso repetido reduzidos às metas da Parte 2 pelo ForgeGUI. Números
  medidos no GLB preparado, em D-45, `manifest.json` e `ASSETS.csv`.
  - Vegetação: 1.865 a 2.801 triângulos.
  - Casas: 3.054 a 3.135.
  - Props: 2.838 a 3.975.
- **10 remeshes terminaram em `outcome_unknown`** e não foram regenerados (regra do ForgeGUI).
  - **Redução local sem crédito** (`tools/decimate_glb.py`): preserva UV, texturas e pivô, mede o
    desvio e é refeita pelo fetch a partir do original conferido por hash.
  - Resultados:
    - capacete M1 14.646 → 3.000 (desvio máx. 0,8 cm);
    - colete 14.307 → 3.999 (0,6 cm);
    - capacete de fibra 13.793 → 2.999 (0,3 cm);
    - cozinha, poço, altar e túmulo → ~4.000 (2,5 a 16 cm);
    - celeiro → 4.900 (11 cm);
    - bambu 3.020 → 2.800.
  - Conferidos em render antes/depois.
  - A cozinha voltou ao sorteio das casas.
  - Cada fuzileiro americano caiu de ~29 mil para ~7 mil triângulos de equipamento.
- **`ArtBudget`:** tabela de tipos e triângulos medidos, metas e exceções. O teste falha se divergir
  do manifest ou se algo passar da meta sem motivo.
- **Arte nos 5 setores:**
  - `AssetLoader` com teto por setor e ordem de prioridade (casas → vila e túneis → colinas →
    sebes);
  - desbaste **uniforme** das sebes pelo que sobra do teto;
  - streaming atômico e impostor nos grandes.
- **Bug evitado:** a peça da sebe ficava invisível mesmo quando o teto barrava as touceiras. Isso
  deixaria cobertura invisível em boa parte do mapa. Agora ela só some se todas as touceiras
  entraram.
- **Estimativa offline** (`lune run tools/art_estimate.luau`):
  - ~1.000 modelos por setor (5,2 mil no total, 12,6 milhões de triângulos);
  - das touceiras de sebe, entram 20%, 38%, 24%, 21% e 55% nos setores 1–5 com o teto provisório
    de 2,5 milhões;
  - **é cálculo, não medição em jogo.**
- **Diques:** fusão de colineares, 18.926 → 18.095 (−4,4%), comprimento preservado. Uma versão
  que apagava trechos foi pega pelo teste e corrigida.
- **Próximo:**
  - medir fps no Studio e então ajustar `ArtBudget.SECTOR_MAX`;
  - malha única por bloco (EditableMesh) para diques e lâminas.

## Parte 12 (controle): o que foi feito (sessão 5)
- **Auditoria:** 14 pontos que não funcionavam só com controle (`CONTROLE.md`). O pior era o
  comandante, que exigia digitar a grade.
- **Base:**
  - `InputMap` puro;
  - `Input` (IAS + reserva no UIS, PreferredInput, ícones por controle, limiar dos gatilhos,
    desconexão, configurações salvas na conta, gravador);
  - `FieldService` no servidor.
- **Infantaria:** correr, corpo a corpo, inclinar, deitar, interagir segurando, rodas,
  marcações, mensagens, granadas, fumaça, baioneta, binóculo, alça de mira, canal de rádio.
- **Menus e mapa:**
  - foco visível de alto contraste e texto de 24 px na TV;
  - cursor com ímã, zoom e LB/RB entre spawns;
  - menu do jogo com abas e sub-abas, remapeamento por contexto e acessibilidade;
  - comandante escolhe o alvo no mapa.
- **Mira:** zona morta radial, 3 curvas, sensibilidade por modo e eixo, aceleração de giro
  (180° em 0,58 s), assistência mínima que respeita vegetação e fumaça.
- **Veículos:** motorista, atirador (coaxial, munição HE/HEAT), comandante (binóculo, marcar),
  piloto (cíclico, coletivo nos gatilhos, pedais, estabilizar), porta, trocar assento e sair
  segurando.
- **Vibração:** disparo, explosão, lado do impacto, batimento, motor e rotor.
- **Roupas:** os moldes do ForgeGUI falharam de novo (`outcome_unknown` aos 15 min, inclusive 3
  texturas novas). Molde por código v2, com trama e desgaste reais (D-30).
- **F4:** M29 81 mm preparado (1,2 m armado).

## F4: o que foi feito (sessão 4)
- **Lógica pura** (`Shared/`, testada em `tests/luau/f4.luau`):
  - `Mortar`: trajetória com arrasto. O arrasto é calibrado pelo alcance da fonte; ramo alto;
    cargas; mils.
  - `FireSupport`: grade BS da carta de 1965 ↔ jogo, correção "mais/menos, direita/esquerda" no
    eixo observador–alvo, dispersão por CEP e habilidades com recarga e custo.
  - `Explosive`: zonas letal e de ferimento, postura e cobertura, orçamento de crateras.
  - `Vehicles`: fichas com fonte, tração por potência e atrito por tipo de chão, anfíbio na água,
    blindagem efetiva por inclinação, zona do impacto.
  - `HeliModel` (UH-34D): calibrado pelos tetos de pairar, pela velocidade máxima e pela subida da
    ficha (D-38).
  - `Logistics`: renda, gasto, regras de construção.
- **Servidor:**
  - `ExplosionService`: dano validado no servidor e crateras com orçamento;
  - `LogisticsService`: caixotes, construções e pontos de reunião;
  - `CommanderService`: missões por grade, perigo próximo, tempo de voo calculado, naval, ataque
    aéreo, suprimento e reforço por túnel;
  - `VehicleService`: 6 veículos nos depósitos, assentos por papel, posse de rede ao motorista
    com validação de velocidade, projéteis, penetração por zona, motor e esteira atingíveis,
    destruição e respawn.
- **Cliente:**
  - `VehicleController`: direção, voo e HUD de potência e torque;
  - `CommanderController`: N fogo, J construir;
  - áudio de explosão, assobio, disparos e motores.
- **ForgeGUI:** UH-34D, M48A3, LVTP-5, Ontos, morteiro 82 mm e bunker VC preparados (escala na D-39); 9 sons da F4. Total: 40 GLBs no manifest e 79 itens no plano de upload.

## F3: o que foi feito (sessão 4)
- **Luz:**
  - `SolarPosition` (NOAA) + `LightingService`: sol real de 18/08/1965 ajustado ao Roblox a cada
    15 s; às 06:30 o sol está a −0,9° (D-27);
  - neblina matinal que se dissipa até 07:30.
- **Áudio** (`AudioController`):
  - ambiências com crossfade (arrozal, vila, praia, túnel);
  - passos 3D por material;
  - tiros em camadas por distância com atraso d/349 m/s;
  - estalo supersônico;
  - impacto re-simulado com a semente do tiro.
- **Túneis** (D-29): 474 m de galeria escavada no terreno, 5 entradas e a trincheira sul. O
  engenheiro dos EUA desmonta entradas.
- **Personagens** (D-30):
  - `Characters`: altura 1,2×, uniformes por facção (moldes procedurais), capacetes, colete e
    chapéu;
  - agachar (C);
  - bots (D-28).
- **Arte do Lote 1 no setor 3:** `AssetLoader` troca as casas do greybox por 5 variantes e põe
  bambu, arbustos e capim nas sebes, bananeira e coqueiro nos quintais, altar, poço, túmulos, ponte,
  entradas de túnel e trincheira. Tudo no chão real, com semente fixa.
- **ForgeGUI:**
  - 34 GLBs em escala real (`assets/forgegui/manifest.json`, com `dim_studs_xyz` medido);
  - 24 sons;
  - ícone USMC v2.
- **Publicação sem Studio** (D-31, D-32):
  - terreno gerado no servidor se o place vier sem ele;
  - `tools/roblox_cloud.py` sobe 64 assets, cria a loja e publica o place pelo Open Cloud.

## Monetização: o que foi feito
- Catálogo sem vantagem (`Shared/Commerce.luau`):
  - 4 Game Passes: Uniformes USMC 1965, Uniformes da Força Principal 1965, Unidade, Apoiador;
  - 2 produtos de apoio;
  - assinatura opcional;
  - benefício Premium;
  - 18 cosméticos com regra de neutralidade visual.
- Servidor:
  - `PlayerData`: DataStore com versão de esquema, repetição em falha, autosave e recibos atômicos;
  - `CommerceService`: posse, `ProcessReceipt` idempotente, Premium, assinatura, equipar e funil de
    análise;
  - `PrivateServer`: o dono escolhe modo e horário.
- Cliente: loja na tecla **B**, com preços lidos ao vivo (exigência do Managed Pricing) e armário.
- ForgeGUI:
  - ícones dos 4 passes (o do USMC saiu fora do estilo; refazer);
  - capa do jogo (`assets/forgegui/marketing/`).

## F2: o que foi feito
- **Lógica pura** (`Shared/`, testada no Lune):
  - `Rng` determinístico;
  - `Weapons`: 9 armas com fonte por número; PLACEHOLDER onde não há fonte;
  - `Ballistics`: arrasto G1, dispersão e variação de velocidade por semente;
  - `Medical`: sangramento leve, grave e arterial, curativo, torniquete, tratamento, janela de 60 s,
    reanimação;
  - `SpawnRules`: espera de 60 s, ondas de 20 s, extras e bloqueios;
  - `Capture`: Warfare/Skirmish, vizinhança, neutralização, vitória;
  - `Roles`: unidades, vagas e armas por papel;
  - `Squads`.
- **Servidor** (`ServerScriptService/Modules`):
  - `MatchService`: sorteio de 1 de 3 pontos fortes por setor, captura a cada 1 s, fim e reinício;
  - `TeamService`: 30 por time, equilíbrio, squads e papéis;
  - `SpawnService`: mapa de spawn, regras e posicionamento no chão;
  - `CombatService`: validação de tiro e re-simulação no servidor;
  - `MedicalService`: ações com tempo, cancelamento por movimento ou dano.
- **Cliente:**
  - `GameUI`: facção → squad → papel → mapa de spawn; tecla M abre o mapa tático, sem inimigos;
  - `WeaponController`: disparo com semente, mira por FOV, recuo, recarga (R), seletor (V),
    traçantes de metralhadora;
  - `MedicalController`: sem barra de vida; visão perde cor e borra. Teclas G, T, F e H.
- **ForgeGUI:**
  - modelos M14, Type 56, casa de palha, coqueiro e bambu;
  - sons de tiro da M14 e da Type 56;
  - ambiência de arrozal.
  Os modelos e sons estão em `assets/forgegui/`. Os modelos foram preparados em escala real, com a
  M14 em 1,126 m e a Type 56 em 0,882 m.

## Atualizações (features "Depois" da Parte 11)
- **Armadilhas VC** (D-50): punji e granada com fio, armadas pelo sapador; o engenheiro inimigo
  detecta e desarma. 5 testes em `atualizacoes.luau`.
- **Chuva tropical súbita** (D-51): 1 partida em 4; névoa, visão dos bots pela metade, passos
  abafados. 2 testes.

## Primeiro teste no Studio (2026-11-10, D-49)
Feito pelo MCP do Studio, em Play solo com 29 bots, no greybox. Relatório em
`testes/TESTE_STUDIO_2026-11-10.md`.
- Nenhum erro de script.
- 60 fps nos 5 setores, com p99 de 18,4–18,8 ms.
- Heartbeat de 0,12–0,30 ms.
- Terreno gerado em 26 s.

Os 8 bugs encontrados foram corrigidos. **Reteste no Studio** (mesmo dia, relatório em
`testes/RETESTE_STUDIO_2026-11-10.md`):
- **corrigidos:** mouse preso nas telas, M e P fechando o que abriam, mira, comandos de teste, mapa
  que ficava na tela e Output poluído;
- **deitado:** não escorrega mais (0,00 m em 7 s numa encosta de 14°). O corpo não deitava porque
  as juntas do avatar agora vêm como `AnimationConstraint`. **Corrigido (D-52):** deitado com o
  tronco a 86° no servidor; agachar e inclinar também voltaram;
- **deitado em encosta, de novo:** com o corpo deitando de verdade, o tronco empurrava o soldado
  (70 m em 5 s). Corrigido com grupos de colisão (D-52): 0,02 m em 7 s;
- **raia:** o servidor escolhe uma direção com visada livre e põe os alvos lado a lado (D-53);
- **pá:** o buraco agora tem ~1,2 m de fundo (antes 0,48 m); a pegada é de 2,2 a 3,4 m (D-53);
- **autoteste:** **10 ok, 0 falhas, 1 pulado** (animais, IDs de arte em 0). Na primeira rodada
  eram 6 ok e 4 falhas.

**Visual da arma e dos tiros (D-54):**
- todos aparecem armados (arma provisória até a arte ser publicada), com os braços à frente;
- arma em primeira pessoa, no quadril e no ombro ao mirar;
- clarão de boca, poeira no impacto e traçante que voa pela trajetória;
- arma caída com a forma da arma, e a arma na mão troca ao pegar a do inimigo;
- sem o cursor no meio da tela;
- corrigido também o acúmulo das rotações nas poses (agachar, inclinar, braços);
- a arma fica presa ao peito e as duas mãos a seguram por IK (D-55).

**F4 no Studio** (`testes/TESTE_F4_STUDIO_2026-11-10.md`):
- M48A3 anda (~19 km/h aos 5 s, na areia);
- UH-34D decola e voa. A subida tinha um corte de 8 m/s sem fonte; agora é calibrada na ficha
  (600 ft/min na vertical e 1.100 ft/min à frente, D-61). No Studio, só com o piloto, ele sobe a
  10,6 m/s;
- o RPG-2 não fura o M48A3 de frente e fura de lado;
- sem erros;
- tiro naval, morteiro de 81 mm e Ontos funcionam;
- o mar não existia no terreno (virava areia): corrigido (D-56). O LVTP-5 nada a 10,8 km/h;
- no solo do Studio os papéis pesados não aparecem no menu, porque o time não chega a 16.

**Testes no PC (2026-11-10):** com Rojo, Lune, StyLua e luau-lsp instalados:
- as 8 suítes passam (106 ok, 0 falhas);
- o StyLua está limpo;
- o luau-lsp dá 0 erros. Ele achou um defeito que quebraria o carregamento da arte (D-57). O `place/` voltou a ser a saída do pipeline (Rojo + bake), idêntico
ao `build/`: 113 scripts e 30.199 instâncias.

**Depois do teste:**
- **Autoteste no motor:** `workspace:SetAttribute("VT65SelfTest", true)`, só no Studio. Roda
  10 verificações no servidor de verdade e imprime OK ou FALHA.
- **Bots deixam a arma ao morrer:** antes só os jogadores deixavam, e numa partida com bots quase
  não havia arma do inimigo para pegar.

## Teste com a arte publicada (2026-11-10, D-58 e D-59)
São 82 assets publicados pelo Open Cloud. O place da nuvem foi aberto no Studio, e o relatório está
em `testes/TESTE_ARTE_REAL_2026-11-10.md`.
- **Autoteste: 11 ok, 0 falhas, 0 pulados.** É o primeiro sem pulados: 141 animais nas vilas.
- **fps no Studio, com a arte:** a medição de 59–60 fps **não vale**. A arte estava enterrada em
  y = 0, porque era posta antes de o terreno existir (corrigido na D-62). A medição com a arte
  visível segue pendente.
- **Corrigido:**
  - a arma real não aparecia;
  - as armas reais ganharam pontos de boca, mira e mãos, gerados dos GLB (`tools/weapon_landmarks.py`);
  - a mão esquerda não alcançava a arma (nova pega: 7 e 11 cm em pé, 8 e 10 cm deitado);
  - o búfalo e a galinha não tinham sido publicados;
  - animais e veículos andariam de ré, porque o importador gira o modelo 180°.
- **Teste do mapa (D-62, `testes/TESTE_MAPA_2026-11-10.md`):**
  - a arte era posta antes do terreno e ia toda para y = 0; agora ela espera o terreno, e o
    autoteste confere a arte no chão (5.046 de 5.048 modelos);
  - nas capturas, as casas estão boas;
  - continuam: a `hill_tree` quebrada pela redução, 89% das sebes ainda como caixas e o terreno
    com as cores padrão do Roblox;
  - o fps com a arte visível não foi medido, porque o PC estava ocupado.
- **Segunda rodada (D-60):** a mira das 9 armas foi conferida por captura. A massa fica no centro da
  tela, e as pistolas ficam com o braço estendido. A Type 54 e a RPD vieram tortas do gerador e
  agora são corrigidas. O autoteste continua 11/11. O place foi publicado de novo.

## Mapa de 2 × 2 km (2026-11-10, D-63)
O mapa encolheu de 4 × 2,4 km para **2 × 2 km em 1:1**, da Colina 43 a An Cường (2), a pedido
do usuário (opção A).
- **Ficaram de fora:** a praia, o mar, An Cường (1), a Colina 22 e An Phước (1).
- **O que mudou:**
  - setores, 15 pontos fortes e QGs novos;
  - os EUA começam na borda leste;
  - os depósitos de veículos ficam a oeste e ao norte do QG;
  - a raia dos EUA atira para oeste.
- **Como:** `tools/crop_world.py` recorta os dados já gerados, com 150 m de margem. A origem do
  quadro local não mudou.
- **Medido no Studio:**
  - terreno em 21–47 s;
  - 9.738 diques, 92 casas e 4.899 modelos de arte (4.896 no chão);
  - os 6 veículos, os QGs e os alvos estão dentro da área.
- **Autoteste: 12 ok, 0 falhas, 0 pulados** (com o jogador em campo pelos EUA).
- **Corrigido:** um bot morto enquanto a arte dele carregava ficava caído para sempre, sem largar a
  arma, e a vaga não voltava.

## Mata, chão, luz e lobby (2026-11-10, D-64)
- **Mata:** 17,4 mil plantas por uso do solo da carta.
  - Bosque fechado nas vilas e matas, moitas em manchas no capim e bambu nos riachos.
  - Fora da borda, uma cortina de árvores grandes esconde o fim do terreno.
  - O arrozal continua aberto, como na carta, agora com arroz verde (grama animada).
  - Sebes a 100% em todos os setores (eram 37–77%).
- **Todos os modelos do ForgeGUI em uso:** celeiro, cerca de bambu, toca de atirador e canteiro de
  arroz entraram. O QG dos EUA ganhou anel de sacos de areia.
- **Folhas que pareciam cromo:** 24 modelos sem metal republicados (`tools/matte_glb.py`).
- **Luz:** a partida começa às 07:00 com sol baixo e névoa dourada; tinta quente e nuvens.
- **Chão:** cores próprias, mata com folhas secas e água do arrozal mais escura.
- **Pontos fortes e QGs:** o disco amarelo virou mastro com bandeira, e a placa de plástico dos QGs
  sumiu.
- **Lobby novo:** dossiê de 1965 em 4 passos (lado, squad, papel, inserção), com o soldado em 3D e
  o mapa real desfocado ao fundo. Foi conferido no Studio passo a passo, até o spawn.
- **Capacete visível:** antes ficava rente à cabeça do avatar.

## Mata fechada (2026-11-10, D-65)
- **Paisagem:** 71% do mapa virou mata fechada. A lavoura de arroz fica só em volta das vilas,
  com clareiras nos pontos fortes, na LZ Blue e nos QGs.
- **Plantas:** 48,4 mil, em três andares: emergentes, copas grandes e montes de cipó, e
  sub-bosque.
- **Modelos novos do ForgeGUI publicados:**
  - árvore emergente de 24 m;
  - bosque de tràm;
  - taioba com samambaia.
- **Não vieram:**
  - a copa de cipó (`outcome_unknown`, não regerar);
  - o monte de cipó (acabou o crédito: 3.693 de 4.000).
- **Texturas escuras corrigidas** no arbusto e na árvore de folha larga.
- **Studio:** dossel contínuo do alto da Colina 43 e mata fechada por dentro.
  - A GPU travou num teste com o FC 26 aberto. Depois disso as sombras caíram para 7,1 mil
    árvores.
  - **fps não medido.**

## Malha cheia, chão fotográfico e relevo (2026-11-11, D-66)
- **26 modelos na malha cheia** do gerador, sem gastar crédito: 9 de vegetação (8–13,6 mil
  triângulos) e 17 props (9,6–17 mil).
- **Chão:** 4 texturas fotográficas (Poly Haven, CC0) no terreno, para mata, capim e arrozal,
  riacho e terra.
- **Relevo:** do DEM real com menos suavização. Colina 43 = 43 m e Colina 30 = 30 m, como na
  carta.
- **fps (Studio, PC livre):** 45 no ponto mais denso, com o streaming descarregando o que está
  longe (eram 38).
- **Autoteste:** 10 ok, 0 falhas. Nenhum modelo ou textura falhou ao carregar.
- **fps:** 59,3 de média no ponto mais denso, antes dos modelos foscos e da grama. Com o EA FC 26
  aberto em primeiro plano, a medida não vale. **Medir de novo com o PC livre.**

## Árvores prontas, mira e aço das armas (2026-11-11, D-67)
- **Árvores:** 4 árvores CC0 do Poly Haven com folha em cartão recortado (12,5–13,7 mil
  triângulos cada, de 1–2 milhões no original), no lugar das 3 árvores do ForgeGUI. São 15.102
  das 47.818 plantas. No Studio: folhas recortadas, dupla face e tronco sólido conferidos no
  cliente.
- **Mira:** anel da M14 e entalhe da Type 56 e da SKS medidos na malha; no Studio o anel e a
  massa ficam no centro da tela.
- **Armas:** aço fosco (fosfatizado ou oxidado) e texturas de 1024 px com nitidez; as 9
  republicadas.
- **fps da mata nova (Studio em primeiro plano):** 53,2 de média girando 360° no ponto mais denso,
  99% dos quadros abaixo de 25 ms (eram 45 fps na D-66).

## Terceira pessoa, movimento, céu, recarga, uniformes e lobby (2026-11-11, D-68 a D-71)
- **D-68:** 3ª pessoa no ombro (O / direcional → segurado), mirar volta à 1ª pessoa; movimento
  com inércia, fôlego, peso, chão, transpor/escalar (Espaço/A), mergulho e anti-trapaça de corrida
  no servidor. Testes: `movimento.luau` 19 ok.
- **D-69:** céu de foto (HDRI CC0, conferido no Studio, sem emendas) e sem nuvens dinâmicas; recuo
  corrigido (bug de ~100° por tiro); inclinar mirando no L3/R3; recarga com braços e troca de
  carregador; mira limpa (anel/entalhe e massa em peças lisas).
- **D-70:** uniformes v3 (9 moldes publicados), corpo "Man" da Roblox, equipamento 3D por código
  e o giro de −90° do capacete e do colete; acessórios republicados foscos. Testes:
  `uniformes.luau` 14 ok, pytest 50.
- **D-71:** lobby na mesa (barraca dos Marines / abrigo VC), cursor virtual no controle,
  recompensa diária de 7 dias (perfil v2), tela de entrada no ReplicatedFirst e inserção que
  carrega a área antes de soltar o jogador. Testes: `f2.luau` 22 ok.
- **Studio (place com tudo, 2026-11-11):** 0 erros no servidor e no cliente; tela de entrada,
  lobby na mesa, carta de inserção, mira limpa, recarga, 3ª pessoa e avisos de XP conferidos.

## Progressão e mapa (2026-11-11, D-72 e D-73)
- **D-72:** 13 postos por lado, XP e créditos de intendência por ação (com teto), soldo de
  promoção com tela animada, equipamento por posto, créditos ou Game Pass, e o renascer onde caiu
  (créditos ou Robux). Testes: `progressao.luau` 12 ok. Os itens em Robux não foram criados: a
  chave não tem permissão (TODO_USUARIO).
- **D-73:** arrozal encaixado no terreno real (lâminas escondidas: 1.136 → 3), diques, sebes sem
  parede invisível, casas em patamar de terra, mata fora de construções e das raias. Autoteste
  10 ok, 0 falhas.

## Resultados-chave (medidos aqui)
| Medida | Valor |
|---|---|
| Testes Lune | `run.luau` **11 ok**; `f2.luau` **17 ok**; `f3.luau` **6 ok** |
| pytest | **19 passed** |
| Sol em 18/08/1965 (calculado, UTC+8) | 06:30 → −0,9°; 12:00 → 78,1°; 18:30 → 7,8° |
| Túneis (gerados) | 64 peças, 474 m de galeria |
| Testes Lune F4 | `f4.luau` **12 ok** |
| Testes Lune controle | `controle.luau` **18 ok** (inclui 10.000 eventos aleatórios sem estado preso e a troca de contexto do teste no Studio) |
| Giro de 180° no analógico (quadril) | **0,58 s** (calculado) |
| Testes Lune F5 | `f5.luau` **9 ok** |
| Testes Lune F6 | `f6.luau` **27 ok** |
| Arte estimada por setor (teto 2,5 mi) | ~1.000 modelos; touceiras de sebe 19/37/24/21/52% nos setores 1–5, com 104 galinhas e 33 búfalos (cálculo) |
| Daltonismo (ΔE76 simulado) | vermelho x verde histórico: 24 na deuteranopia; laranja x azul: 133–149 |
| Redução local (Hausdorff, máx.) | capacete 0,8 cm; colete 0,6 cm; fibra 0,3 cm; props da vila 2,5–16 cm |
| Diques após a fusão | 18.926 → **18.095** no mapa de 4 × 2,4 km; **9.738** no recorte de 2 × 2 km (D-63) |
| Morteiro 82 mm (calibrado) | k = 1,512e-4 1/m; a 300/800/1.500/2.500 m: voo de 18,4/14,9/26,9/27,5 s |
| M29 81 mm (v0 derivada) | **254 m/s** para 3.890 m com o arrasto do 82 mm |
| UH-34D no peso máx. a 35 °C | pairar fora do efeito solo 1.522 hp, dentro 1.375 hp, a 20 m/s 1.033 hp; disponível 1.453 hp |
| UH-34D: peso máx. para pairar a 35 °C | 5.784 kg fora do efeito solo; 6.355 kg dentro |
| 0–5 s na estrada (calculado) | Ontos 26,7 km/h; M48A3 26,5 km/h |
| luau-lsp (API do Roblox, `--!strict`) | **0 erros** em todo `src/` |
| StyLua / Ruff | limpos |
| Queda calculada com zeragem a 100 m | M14 0,16 m (200 m) e 0,52 m (300 m); Type 56 0,24 m e 0,80 m. **Não validada** contra tabela de tiro |
| M14 a 300 m | 640 m/s e 1.946 J (calculado) |

## O que NÃO foi verificado
- **Nada da F2, F3, F4 nem da monetização rodou dentro do Roblox.** Só a lógica (Lune) e os tipos
  (luau-lsp) foram verificados.
- A física dos veículos no Roblox (LinearVelocity/AlignOrientation) pode precisar de ajuste de
  força e responsividade no primeiro teste.
- O critério da F2 ("partida 15v15 de 60 min sem erro no servidor; todo dano validado no servidor")
  exige um teste com jogadores no Studio ou num servidor publicado.
- As compras só funcionam com os IDs criados no Creator Dashboard. Com IDs em 0, a loja esconde os
  itens.
- A mira das 9 armas foi conferida contra um alvo parado. Atirando em movimento e com recuo, só no
  teste com jogadores.
- D-93 (água, passo, VC mais rápido, dique do tanque): só Lune. No Studio, ver com
  `workspace:SetAttribute("VT65DevMov", "info")` e os ganchos `agua`, `fundo`, `arrozal`, `dique`
  e `veiculo`: estado Running vadeando até o peito, sem boiar; passada assistida no dique agachado;
  inclinação da câmera; tanque subindo o dique.
- D-100 (pilotar todos os veículos, painel de lugares, tiro de dentro, carros M151/M35/Peugeot,
  desvirar): só Lune e luau-lsp. No Studio: `VT65DevVeh = "todos"` e `"tombar"`, `VT65DevDrive`
  com cada ficha; ver o painel no controle, o lugar no olho, o voo do UH-34D e o tiro pela porta.
- D-103 (veículo ao nascer): só Lune e luau-lsp. No Studio: morto na carta, X / clique no cartão,
  escolher em CI; nascer no QG e ver o veículo a 4-10 m virado para o objetivo e o CI descontado;
  nascer num túnel (o pedido espera); VT65DevCompra = "m151" em campo em vários lugares (casa,
  arrozal, mata, ladeira) para ver onde acha e onde recusa; "abandono". Robux: só com os produtos.
- D-104 (modelos _v2 em peças): só Lune e luau-lsp. No Studio: VT65DevVeh = "todos" e depois
  "pecas" (as juntas que o importador deixou), "mira" (torre e cano), VT65DevDrive com cada
  ficha (rodas girando, rotores, volante, olho e cabeça no teto do Peugeot e do UH-34D).

## Como testar no Studio
1. Abra `vantuong65/place/VanTuong65.rbxl`.
2. Barra de comando: `require(game.ServerStorage.VT65Build.Build).terrain()`. Espere "terreno
   pronto" e salve.
3. Test → **Local Server com 2–4 jogadores** e escolha lados opostos. Em cada um: lado → criar squad
   → papel → clique num ponto do mapa (o primeiro spawn é imediato).
4. Teste:
   - tiro (clique esquerdo), mira (direito), recarga (R), seletor (V);
   - captura: fique 90 s no ponto forte central;
   - ferimentos: tiro no braço → G (curativo); médico reanima segurando F;
   - morte: espere 60 s e as ondas de 20 s;
   - loja (L), mapa (M), menu do jogo (P), HUD de medição (F3);
   - o Output mostra arte por setor ("[VT65] arte setor") e a fração de sebes.
   - tutorial: o painel aparece ao nascer com um papel novo; os alvos do campo de tiro ficam
     ao lado do QG (100/200/300 m) e cada acerto mostra o desvio em cm;
   - Offensive: no Studio não há servidor privado. Na barra de comando, no lado do servidor:
     `workspace:SetAttribute("VT65DevMode", "Offensive")`. Para ver o relatório pós-ação:
     `workspace:SetAttribute("VT65DevEnd", true)`. Esses ganchos só funcionam no Studio; o
     `require(...)` da barra de comando pega outra cópia do módulo e não muda a partida.
5. Me mande os erros do Output e os números do HUD.

## Problemas
1. Não há como rodar o Roblox aqui: todo o comportamento em jogo precisa do seu teste.
2. Desempenho do greybox: 30,6 mil peças (D-14).
3. A balística e o dano ainda não foram calibrados com fonte primária nem com playtest (D-21, D-22).
4. A carta é de 1983 e o uso do solo de 1965 depende da CORONA.
5. O repositório próprio depende de você criar um repositório vazio (D-18).

## Próximos passos
1. **Você:** item 2 de `TODO_USUARIO.md` (questionário de maturidade, servidores privados e
   preços). A experiência e a arte já estão publicadas.
2. Teste com 2 ou mais jogadores (Local Server) e com controle → correções.
3. Trocar os PLACEHOLDER que restam na D-36 por fichas técnicas. A D-61 já trocou blindagem,
   penetração, tiro naval, torre do M48 e subida do UH-34D. Faltam:
   - cargas dos morteiros;
   - teto do M48;
   - 90 mm HEAT;
   - raios dos explosivos;
   - distância do navio;
   - giro dos veículos.
4. F5: com o fps medido, ajustar `ArtBudget.SECTOR_MAX` e fazer a malha única por bloco (EditableMesh) para diques e lâminas.
