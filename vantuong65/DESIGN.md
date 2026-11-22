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

## D-03 — Tamanho da área jogável (FIRME, aprovado pelo usuário em 2026-11-09)
**4,0 km (leste–oeste) × 2,4 km (norte–sul) em 1:1**, com limites em grade de 1965 de
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

## D-08 — Setores (firme na F1)
As 5 faixas norte–sul têm fronteiras em **polilinha**, não retas, para nenhum local real ser cortado.
Grade de 1965, E em km. Quando a fronteira dobra, o valor está como "sul / norte" (corte em N 1692,45 e
1692,40). Implementação em `tools/export_roblox.py` (FRONTEIRAS_ING); o teste Luau confere que
os setores cobrem a área sem buraco nem sobreposição:

| Setor | E (km) | Largura | Locais inteiros |
|---|---|---|---|
| S1 (oeste, início do VC) | 268,2–269,3 / 269,05 | 0,85–1,10 km | Colina 43, Lạc Sơn (1), Athletic field, LZ Blue, Nam Yên (3) |
| S2 (início do VC) | 269,3 / 269,05–269,8 | 0,50–0,75 km | Nam Yên (4), An Thới (2) |
| S3 (centro, neutro) | 269,8–270,42 / 270,5 | 0,62–0,70 km | An Cường (2), trincheira, riacho, Colina 30 |
| S4 (início dos EUA) | 270,42 / 270,5–271,25 | 0,75–0,83 km | An Phước (1), arrozais abertos |
| S5 (leste, QG dos EUA) | 271,25–272,2 | 0,95 km | An Cường (1), △22, Green Beach, mar |

Pontos fortes (3 por setor, um sorteado por partida, raio de 50 m), com posições em `MapConfig.luau`:
- S1: Colina 43, LZ Blue/Nam Yên (3), Athletic field;
- S2: Nam Yên (4), An Thới (2), Cemitério (símbolo da carta);
- S3: An Cường (2), Trincheira sul ("wide, deep trench south of the village"), Colina 30;
- S4: An Phước (1), Vau do riacho (o riacho é real, o ponto do vau é de design), Túmulos da várzea
  (**de design**, a confirmar em foto);
- S5: An Cường (1), Colina 22, Green Beach (dunas).

QGs: EUA na Green Beach sul (S5) e VC na retaguarda oeste (S1).

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

## D-12 — Critérios da F1 ajustados à área de 4 km (firme)
O critério "travessia leste–oeste a pé em 8–12 min" valia para 2 km. Com 4,0 km, a travessia em
corrida leve (3,1 m/s, a velocidade provisória da F1) leva cerca de **21,5 min**. O critério passa a
ser: **travessia medida entre 18 e 25 min em corrida leve**. O cronômetro automático do HUD de
medição (tecla F3) dispara a menos de 50 m da borda leste e para a menos de 50 m da oeste. O piso de
60 fps continua igual.

## D-13 — Relevo calibrado nas cotas da carta (provisória)
O DEM de 30 m suaviza os picos. Somamos bolhas gaussianas (sigma de 60 m) para o terreno passar pelas
cotas da carta de 1983:

| Cota | Correção |
|---|---|
| Colina 43 | +10,1 m (32,9 → 43) |
| △22 | +1,8 m |
| cota 22 em An Cường (1) | +11,4 m |
| △10 | +7,7 m |
| △45 | −4,6 m |

As duas correções grandes ficam nas dunas da costa. Ou as dunas mudaram desde 1983, ou o DEM não
captou cristas estreitas. Isso será conferido com a CORONA.

## D-14 — Orçamento de peças do greybox (risco)
O greybox tem **30.635 BaseParts**: 18.926 diques, 7.263 lâminas d'água, 3.832 sebes, 199 casas e
marcadores. É pesado para o piso de 60 fps. Sombras já estão desligadas em diques, água e sebes
baixas. Se a medição no Studio reprovar, a ordem de corte é:
1. fundir os diques colineares de cada linha da grade;
2. trocar diques e água por MeshParts agrupadas por bloco (F5);
3. reduzir o detalhe da faixa de 150 m fora da área.
O teste Python trava o total abaixo de 40 mil.

## D-15 — Streaming (provisória)
`StreamingEnabled` ligado, com raio-alvo de **2.560 studs (717 m)** para sustentar as linhas de visão
de 600 m nos arrozais, e raio mínimo de 512 studs. A memória ainda vai ser medida no Studio.

## D-16 — Movimento provisório (F1)
`CharacterWalkSpeed` = 11,07 studs/s (3,1 m/s, corrida leve), só para medir a travessia. O
movimento real (ControllerManager, fôlego, posturas, lama) e a escala do avatar para 6,25 studs
entram na F2.

## D-17 — Uso do solo e feições do greybox (provisória)
- Classes na grade de 4,48 m, derivadas da carta de 1983 (`tools/landcover.py`): mar 10,8%,
  arrozal 60,8%, capim/encosta 23,4%, areia 2,9%, vila/mata 2,0% e riachos.
- Os quadros de arrozal são **procedurais**: grade girada 9° com quadros de 20–60 m, jitter de 3 m e
  25% divididos ao meio. Cada quadro tem o terraço no percentil 30 da altura e lâmina de 12 cm, e
  15% das linhas da grade têm sebe (1,8–2,4 m).
- As casas são os símbolos detectados na carta: 199 na área + 150 m. Como a carta generaliza, há
  **menos casas que no real** (An Cường 2 tinha 25–30, segundo o prompt). A densidade será corrigida
  com fotos na F3.
- O bambu das vilas acompanha o contorno das manchas verdes da carta, com 4–7 m de altura e 15% de
  brechas (D-07 continua pendente).

## D-18 — Repositório próprio (aprovado; depende do usuário)
O usuário aprovou mover o jogo para um repositório próprio. Esta sessão **não tem permissão para
criar repositórios**. Assim que existir um repositório vazio (sugestão: `felpo2007/vantuong65`),
anexo e envio o histórico desta pasta com `git subtree split`.

## D-19 — A carta "AMS 6739-1" da UT e do Commons é a mesma de 1983 (fato)
O PDF "Binh Son 6739-1" hospedado pela PCL/UT e pelo Wikimedia Commons tem **9.527.168 bytes**, o
mesmo tamanho do GeoPDF da edição 3-DMA (1983). Não é a edição de 1965. A edição de 1965 continua sem
fonte acessível, e por isso a CORONA (`research/F0_CORONA.md`) passa a ser o caminho para o uso do
solo de 1965.

## D-20 — Monetização sem vantagem (firme)
Detalhes em `MONETIZATION.md`.
- **O que entra:** passes cosméticos, Passe de Unidade, Apoiador, produtos de apoio, servidores
  privados, benefício Premium e assinatura opcional.
- **Neutralidade visual:** nenhuma variação cosmética muda a silhueta ou a cor média em mais de 5% de
  luminância. Por isso a rede de camuflagem com folhas foi retirada do catálogo.
- **Preços:** nunca fixos no código, para o Managed Pricing funcionar.
- **Recibos:** gravados de forma atômica (`UpdateAsync`), para nunca entregar duas vezes.
- **Rejeitados:** caixas pagas, anúncios no mundo e acesso pago.

## D-21 — Modelo de dano inicial (provisório, calibrar em playtest)
Vida 100, sem regeneração. Os valores abaixo seguem o princípio de "um ou dois tiros de fuzil matam":
- **Cabeça:** com energia de 300 J ou mais, mata.
- **Tronco:** com 1.500 J ou mais, incapacita (dá para reanimar). Abaixo disso, tira 45 + E/50 de
  vida (máximo 90) e causa sangramento grave.
- **Membros:** tiram 20 + E/250 (máximo 45). Com 1.500 J ou mais há 20% de chance de sangramento
  arterial; o membro fica prejudicado.
- **Fogo amigo:** ligado.
- **Referência de energia:** a 300 m, a M14 chega com 1.946 J (calculado em `Ballistics.luau`).
  Portanto ainda incapacita com um tiro no tronco; a Type 56 à mesma distância, não.

## D-22 — Balística (provisória)
- **Ambiente:** ar a 30 °C, com ρ = 1,16 kg/m³ e som a 349 m/s. O prompt fala em 343 m/s, que é o
  valor a 20 °C; uso 349 m/s por ser agosto na planície costeira.
- **Arrasto:** tabela G1 aproximada, com integração em passos de 1/120 s e voo máximo de 2,5 s.
- **Queda com zeragem a 100 m (calculada, ainda NÃO validada contra tabela de tiro publicada):**
  - M14: 0,16 m a 200 m e 0,52 m a 300 m;
  - Type 56: 0,24 m a 200 m e 0,80 m a 300 m.
- **Valores provisórios:** coeficientes balísticos, massas de projétil e dispersões estão marcados
  como PLACEHOLDER em `Weapons.luau`. As velocidades de boca, cadências, pesos e carregadores vêm da
  Wikipedia (fonte secundária, `research/armas/`), ainda sem conferência no FM/TM.

## D-23 — Captura (provisória)
- **Ritmo:** 1 atacante leva 90 s de neutro a dono; a velocidade é 1 + 0,25 × (vantagem − 1), com
  máximo de 2×.
- **Disputa:** com os dois lados presentes, a captura congela.
- **Defesa:** defensores sozinhos devolvem o ponto ao dono em 120 s.
- **Setor inimigo:** primeiro é neutralizado, depois capturado.
- **Alcance:** só se ataca o setor vizinho a um setor próprio.
- **Modos:** Skirmish usa só o setor central por 20 min; Warfare dura 75 min.

## D-24 — Spawn (provisória)
- Segue as regras da Parte 10.1.
- O ponto de reunião fica 100 m atrás do ponto forte: a leste para os EUA, a oeste para o VC.
- O QG nunca é bloqueado.
- O primeiro spawn da partida é imediato.

## D-25 — Validação de tiro no servidor (firme)
- **Na chegada do tiro, o servidor recusa se:**
  - a defasagem passa de 250 ms (os 200 ms do prompt mais folga);
  - a origem está a mais de 8 studs da cabeça;
  - a cadência passa de 85% do mínimo da arma;
  - não há munição (a contagem é do servidor).
- **Depois:** o servidor refaz a trajetória com a mesma semente.
- **Atravessáveis provisórios:** bambu (mantém 85% da velocidade) e palha (80%).
- **Sem hitmarker:** o servidor não confirma acertos ao atirador.
- **Traçantes:** por enquanto só nas metralhadoras, 1 a cada 5. A proporção real das fitas ainda
  precisa ser confirmada.

## D-26 — Uso do crédito do ForgeGUI (registro)
Não existe consulta de saldo. Gastei em ordem de prioridade e parei antes de itens da F4.

| Tipo | Itens |
|---|---|
| Retries de modelo | M14 ✔, Type 56 (3 tentativas), bambu, coqueiro, bunker |
| Imagens | capa (2 perdidas por interrupção do servidor do ForgeGUI + 1 ✔), 4 ícones de passe ✔ |
| Sons | tiro de M14 ✔, tiro de Type 56 ✔, ambiência ✔ |
| Preparação | gratuita |

O UH-34D ficou para a F4.

## D-27 — Sol real de 18/08/1965 (firme no método; fuso a confirmar)
- `Shared/SolarPosition` implementa o algoritmo da NOAA (teste: Greenwich, 61,96° de elevação).
- O `LightingService` mede a direção real do sol a cada 15 s. Depois ajusta `ClockTime` e
  `GeographicLatitude` por busca em padrão até `Lighting:GetSunDirection()` coincidir com ela.
  Erro em graus no atributo `SunFitErrorDeg`.
- Fuso: **UTC+8**, a hora oficial do Vietnã do Sul em 1965. Isso é **suposição**: a confirmar em
  fonte primária.
- Resultado calculado às 06:30 do dia 18: sol a **−0,9°**, ou seja, o desembarque foi no nascer do
  sol. Às 12:00 o sol está a 78,1°; às 18:30, a 7,8°.
- Neblina matinal: densidade 0,45 → 0,35 entre 06:30 e 07:30.

## D-28 — Bots completam o servidor (provisório)
- `BotService`: o atributo `BotFill` define quantos combatentes cada time deve ter. O padrão é 15 no
  Studio e 10 no servidor público. Cada 6º bot é metralhador.
- Percepção por linha de visada: as sebes bloqueiam.
- O tiro passa pelo mesmo `CombatService.fire` dos jogadores, então todo dano continua validado no
  servidor.
- O erro de mira (`BotBrain.aimSigma`) cresce com a distância e com o movimento. Rajadas por arma.
- Os bots saem quando entram jogadores. Os números de mira e reação são de design: calibrar em
  playtest.

## D-29 — Túneis de An Cường (2) (traçado de design)
- As fontes confirmam túneis ligando trincheiras e tocas (First Fight p.25), mas não a planta.
- Galeria de 1,0 × 1,2 m, piso a 3 m de profundidade, 5 entradas com poço de 0,6 m, ~474 m no total.
- Trincheira sul com 1,0 m de largura e 1,5 m de profundidade (p.23).
- O terreno é escavado com `FillBlock(Air)`, com forro de peças.
- O engenheiro dos EUA desmonta uma entrada segurando a interação por 8 s.

## D-30 — Personagens e uniformes (placeholder honesto)
- Escala dos personagens: 1,2× a altura padrão do Roblox (`Characters.HEIGHT_SCALE`).
- Uniformes como Shirt/Pants clássicos de 585 × 559 px.
- **Por que as roupas do ForgeGUI não saíram:** os 6 moldes (09/11) e as 3 texturas de tecido
  pedidas depois (10/11) terminaram em `outcome_unknown` ("worker interruption") exatamente aos
  15 min. Nos mesmos dias, modelos 3D e sons saíram normalmente. A falha é do gerador de imagens
  do serviço, não do pedido.
- **Solução adotada:** molde 100% por código (`tools/make_clothing.py` v2):
  - sarja no OG-107 e tela nos uniformes VC;
  - tingimento irregular e desbotamento;
  - costuras pespontadas, bolsos com aba e botões;
  - vincos em cotovelos e joelhos, suor nas costas, sol nos ombros;
  - lama subindo da barra até o joelho.
- Os 6 moldes pedidos ao ForgeGUI terminaram em `outcome_unknown`, e a regra do serviço é não
  regenerar. Por isso `tools/make_clothing.py` os gera por código.
- Cores dos moldes (RGB):
  - OG-107 desbotado: (104, 108, 74);
  - cáqui da Força Principal: (170, 150, 108);
  - verde-escuro: (64, 76, 54);
  - cinto de lona marrom: (112, 84, 52).
  São estimativas de design: conferir com fotos coloridas de 1965 (Parte 9.1).
- Capacete M1, colete M1955, capacete de fibra e chapéu de selva: GLBs do ForgeGUI soldados à
  cabeça e ao tronco.

## D-31 — Terreno gerado no servidor (firme)
- Se o place chegar sem terreno, `TerrainRuntime` roda `Build.terrain()` no servidor.
- Enquanto `ReplicatedStorage.TerrainReady` for falso, ninguém nasce e os bots esperam.
- Motivo: assim o place pode ser publicado direto pelo Open Cloud, sem abrir o Studio. O custo é
  esperar alguns segundos no início de cada servidor.

## D-32 — Publicação automática pelo Open Cloud (firme)
`tools/roblox_cloud.py` faz quatro coisas:
1. Sobe os itens de `assets/upload_plan.json` (79 na sessão 4) pela Assets API.
2. Reescreve `AssetIds.luau`.
3. Cria os 4 passes e os 2 produtos e preenche `Commerce.IDS`.
4. Publica o place.

A chave nunca entra no repositório: o proxy da sessão injeta `x-api-key`, ou ela vem de
`ROBLOX_API_KEY` localmente. Imagens sobem como Decal, e o servidor converte o ID do Decal no da
imagem com `InsertService:LoadAsset` (`Characters.imageUrl`).

## D-33 — Escopo da fatia vertical (F3)
- Arte final só no setor 3 (An Cường 2 + Colina 30). Os demais setores continuam em greybox até a F5.
- Os GLBs preparados estão em escala real, conferida no `manifest.json` (`dim_studs_xyz`).
- Exceção: a casa de telha foi ajustada para 6 m de largura e 5 m de cumeeira. O comprimento ficou
  em 7 m, contra 9 m do projeto, porque o modelo gerado é mais curto.
- Agachar (C) usa uma pose procedural via `Motor6D.C0`, que é placeholder até haver animação.
- O critério da F3 (60 fps no setor e comparativo com fotos de 1965) **só pode ser medido no Studio
  ou no jogo publicado**.

## D-34 — Uso do crédito do ForgeGUI, sessão 4 (registro)
| Tipo | Itens |
|---|---|
| Modelos L2 | M60, RPD, SKS, M1911, Type 54, M79, RPG-2 ✔ |
| Modelos L3 | capacete M1, colete M1955 ✔; capacete de fibra e chapéu de selva ✔ (2ª tentativa) |
| Modelos L4 | casa com varanda, cozinha, casa de telha, altar, poço, celeiro, túmulo, cerca, trincheira, toca, sacos de areia ✔; ponte e entrada de túnel ✔ (2ª tentativa) |
| Modelos L5 | bananeira, arbusto, capim-elefante, canteiro de arroz, árvore de colina ✔ |
| Imagens | ícone USMC v2 ✔; 6 moldes de roupa: `outcome_unknown` (não regenerar) |
| Sons | 21 de tiro, passos, impacto, recarga e ambiência ✔; loop do UH-34D: `outcome_unknown` |
| Preparação | 34 GLBs em escala real (gratuita) |
| Bunker VC | falhou 2×; 3ª tentativa enviada |

## D-35 — F4: o que entra e o que não entra (firme)
- **Entra:**
  - comandante (EUA e VC);
  - logística: suprimento, caixotes, posto de reunião, ninho de MG, posição de morteiro, caixa
    de munição;
  - morteiros: M29 81 mm e 82 mm;
  - M48A3, M50 Ontos, LVTP-5 e UH-34D;
  - foguetes de infantaria: RPG-2 e bazuca de 3,5".
- **O VC não tem veículos.** Em Starlite o 1º Regimento VC não tinha blindados nem helicópteros. A
  força dele está em morteiros, túneis, emboscadas e RPG-2.
- **Sem marcador de inimigo** (Parte 9.5). Fogo indireto só por coordenada de grade da carta de
  1965 (quadrado BS) com correção do observador.
- Bots não dirigem veículos nem pedem fogo nesta fase.

## D-36 — Números da F4: com fonte, derivados e placeholders
| Número | Valor | Status |
|---|---|---|
| 82-BM-37: v0, alcance, granada | 211 m/s, 3.040 m, 3,05 kg | **fonte** (wiki:82-BM-37) |
| M29 81 mm + HE M43A1B1: alcance | 69–3.890 m | **fonte** (Hogg 1987, via wiki:M29_mortar) |
| M29: v0 | **254 m/s** | **derivado**: arrasto do 82 mm calibrado (k = 1,512e-4 1/m) e alcance de 3.890 m. Suposição: calibre e massa parecidos |
| Cargas incrementais | 45–100% da v0 | PLACEHOLDER |
| M48: massa, dimensões, blindagem frontal | 45,0 t; 9,3 × 3,65 × 3,1 m; glacis 110 mm a 60° (220 mm efetivos); torre 178 mm | **fonte** (wiki:M48_Patton) |
| M48A3: potência | 750 hp | **fonte** (D-61: diesel AVDS-1790-2; FAS DoD-101, afvdatabase) |
| M48: velocidade | 48 km/h | **fonte**, mas é o valor do M48A5 |
| M48: laterais e traseira | lado 76 mm (51 mm na metade de trás), traseira **44 mm** | **fonte** (D-61: FAS DoD-101). Antes 76/51/25 |
| M48: teto | 25 mm | PLACEHOLDER (25 mm é o piso, FAS) |
| M48: giro da torre | 24°/s | **fonte** (D-61: afvdatabase) |
| Ontos | 8.600 kg; 3,83 × 2,59 × 2,13 m; 145 hp; 48 km/h; 6 × M40A1C | **fonte** (wiki:M50_Ontos) |
| Ontos: blindagem | 13 mm (piso 6,5 mm) | **fonte** (D-61: tanks-encyclopedia M50) |
| M40: v0 do M344 HEAT | 503 m/s | **fonte** (wiki:M40_recoilless_rifle) |
| LVTP-5 | 37,4 t; 9,04 × 3,57 × 2,92 m; 704 hp; 48 km/h em terra e 11 km/h na água; 6–16 mm; 3+34 | **fonte** (wiki:LVTP-5) |
| H-34 | rotor de 56 ft (2.463 ft²); vazio 7.646 lb; bruto 11.867 lb; máx. 13.300 lb; 1.525 hp na decolagem; 122 mph; subida vertical de 600 ft/min; teto de pairar IGE 9.600 ft e OGE 5.500 ft (H-34A) | **fonte** (wiki:Sikorsky_H-34) |
| Penetração | PG-2 150, 3,5" **280**, 106 HEAT 400 mm | **fonte** (D-61). O 90 mm HEAT (280) segue PLACEHOLDER |
| H-34: razão de subida | 1.100 ft/min ao nível do mar | **fonte** (D-61: Sikorsky Archives, Army Aviation Magazine, Patriots Point) |
| Raios letal e de baixas dos explosivos | — | PLACEHOLDER |
| CEP, cadência e recargas das missões de fogo | — | design |
| v0 naval (5"/38 do USS Orleck) | **762 m/s** | **fonte** (D-61: navweaps, cano médio) |
| Navio a 3 km da praia | — | PLACEHOLDER |
| Resistência ao rolamento por chão (0,04–0,18) e eficiência de tração 0,6 | — | estimativa de engenharia |
| Giro dos veículos (30°/s) e da torre | — | PLACEHOLDER |

Toda linha PLACEHOLDER deve ser trocada por ficha técnica ou manual antes do lançamento
(Parte 9.11).

## D-37 — Assentos, depósitos e respawn (design)
- **Depósitos ao lado do QG dos EUA na praia:** 2 LVTP-5, 1 M48A3, 1 Ontos e 2 UH-34D, que são os 6
  veículos do critério da F4. Respawn em 180 s.
- **Assentos por papel:**
  - blindados: `tank_crew`;
  - helicóptero: `pilot` no comando e `door_gunner` na M60 da porta;
  - passageiros: qualquer papel da facção.
- **Lugares de passageiro reduzidos:** a ficha dá 34 para o LVTP-5 e 12 para o H-34A. No jogo são
  12 e 8, porque o squad tem 6.
- **Recarga do Ontos:** só com o veículo parado, 10 s por tubo. Na vida real os tubos eram
  recarregados por fora do veículo.

## D-38 — Modelo de voo do UH-34D (firme no método)
- **Base física:**
  - teoria do momento;
  - efeito solo de Cheeseman–Bennett;
  - velocidade induzida de Glauert, que dá a sustentação de translação;
  - potência de perfil (1 + 4,65 μ²);
  - arrasto parasita ½ρV³f;
  - perda de potência σⁿ.
- **Calibrado no código** (`HeliModel`) contra a ficha:
  - expoente de perda **n = 0,72** e potência de perfil **378 hp**, pelos dois tetos de pairar;
  - área plana equivalente **f = 5,08 m²**, pelos 122 mph;
  - fator de subida, pelos 600 ft/min.
- **Suposições:**
  - no efeito solo, o rotor fica a 5,9 m do chão (cubo a 4,36 m + 5 ft de roda);
  - κ = 1,15;
  - 15% de perdas de transmissão e do rotor de cauda;
  - ponta da pá a 200 m/s;
  - 400 kg de combustível;
  - 100 kg por ocupante.
- **Consequência medida** (teste `f4.luau`), no peso máximo a 35 °C:
  - pairar fora do efeito solo exige 1.522 hp, contra 1.453 hp disponíveis;
  - no efeito solo exige 1.375 hp;
  - a 20 m/s exige 1.033 hp.

  Ou seja, o piloto precisa de decolagem corrida no calor, como na vida real.
- **Peso máximo para pairar a 35 °C:** 5.784 kg fora do efeito solo e 6.355 kg dentro.
- **Torque:** acima de 92% do torque de decolagem, o nariz gira à direita se faltar pedal.

## D-39 — Escala dos veículos gerados (registro)
Os modelos do ForgeGUI saem com proporções diferentes das da ficha. Exemplo: o M48 escalado pelo
comprimento ficaria com 4,2 m de altura, contra 3,1 m reais.

Por isso cada veículo é escalado pela **média geométrica das três razões** ficha/modelo, o que
distribui o erro. Resultado (m):

| Veículo | Modelo no jogo | Ficha |
|---|---|---|
| M48A3 | 7,89 × 3,75 × 3,55 | 9,3 (com canhão) × 3,65 × 3,1 |
| LVTP-5 | 7,95 × 3,4 × 3,49 | 9,04 × 3,57 × 2,92 |
| Ontos | 3,39 × 2,17 × 2,87 | 3,83 × 2,59 × 2,13 (os tubos elevam a altura) |
| UH-34D | rotor 13,5, altura 5,5 | rotor 17,07, altura 4,36 (o mastro do modelo é alto demais) |

A colisão usa o chassi, dimensionado pela **ficha** (`Vehicles.SPECS`), não pela arte. Os modelos
devem ser refeitos antes do lançamento (F5), com prompt de proporções ou modelagem manual.

A frente dos GLBs dos veículos não é informada (`semantic_front: not_inferred`). A arte gira 90°
(`ART_YAW`); se no Studio o veículo andar de ré, troque por −90°.

## D-40 — Controle em primeiro lugar: arquitetura (firme)
Ver `CONTROLE.md`. Resumo:
- `InputMap` é puro e testado.
- `Input` usa o Input Action System, com reserva no UserInputService e deduplicação por botão.
- Os controllers só falam com a camada `Input`, nunca com o UserInputService.
- O olhar no analógico (`CameraLook`) tira o Thumbstick2 da câmera padrão e aplica a matemática do
  jogo. A rotação persiste porque o módulo de câmera relê a direção a cada quadro, como já acontece
  com o recuo.
- A partir da F2, todo critério de aceite inclui "jogável só com controle".

## D-41 — Números do controle (design, ajustáveis pelo jogador)
| Item | Padrão | Faixa |
|---|---|---|
| Segurar | 0,3 s | 0,2–0,6 s |
| Limiar do gatilho | 0,15 | 0,02–0,9 |
| Zona morta: mover | 0,15–0,95 | — |
| Zona morta: olhar | 0,12–0,95 | — |
| Curva | exponencial (m²) | também linear e dinâmica (0,5m + 0,5m³) |
| Giro máximo no quadril | 200°/s | +100% após 0,5 s no máximo |

- **Giro de 180°:** 0,58 s, medido no teste.
- **Sensibilidades:**

  | Modo | Horizontal | Vertical |
  |---|---|---|
  | Quadril | 1,0 | 0,85 |
  | Mira de ferro | 0,55 | 0,5 |
  | Luneta/binóculo | 0,3 | 0,28 |

- **Assistência (só controle):** desacelera até 30% sobre o alvo, só com mira de ferro ou luneta,
  até 150 m, com o alvo visível de verdade. Visível quer dizer: o raio da câmera chega ao inimigo e
  a fumaça não tapa. Nunca puxa nem gruda.
- **Iguais para controle e mouse:** recuo, balanço da mira (0,12°, ×0,2 prendendo a respiração por
  4 s), inércia e FOV.

## D-42 — Itens novos da infantaria (PLACEHOLDER até manual/playtest)
- 2 granadas e 1 fumaça por vida. Espoleta de 4,5 s; arremesso a 15 m/s.
- Fumaça: 60 s, raio útil de 6 m. Bloqueia visão de bots e da assistência, não bloqueia balas
  (teste geométrico em `Shared/Smoke`).
- Corpo a corpo: coronhada 250 J (alcance 1,8 m); baioneta 900 J (2,4 m). Baioneta só em M14, SKS e
  Type 56.
- Rastejar a 25% do andar. Deitar baixa o quadril 4,4 studs; agachar, 2,2.
- Inclinação: câmera 0,35 m para o lado e tronco 16°.
- Roda: 8 posições fixas por página, zona morta de 40%. A pá fica apagada, no lugar, até a F5.

## D-43 — Vibração (Parte 12.6)
- Disparo proporcional ao recuo calculado (M14 forte e seco, M60 contínuo, pistola leve).
- Explosão cai com a distância até 120 m. A partir de 40 m, usa `HapticEffect` (`GameplayExplosion`)
  quando disponível.
- Tiro recebido vibra do lado do impacto: motores das mãos, ou grande/pequeno como reserva.
- Batimento cardíaco com sangramento grave ou caído.
- Motor do veículo constante; rotor a ~4 Hz (PLACEHOLDER).
- Intensidade separada para disparo e dano: desligada, baixa ou normal.
- Gatilhos adaptativos do DualSense não existem no Roblox: não prometemos.

## D-44 — Testes do controle
- `tests/luau/controle.luau` (17 testes) cobre:
  - layout = tabela da Parte 12;
  - sem conflito; Start nunca usado; Select só onde a navegação automática fica desligada;
  - zona morta circular, curvas, giro, assistência, roda, ímã, tocar/segurar e configurações;
  - cada transição (morrer, renascer, veículo, assento, túnel, reanimado segurando, mapa durante a
    recarga);
  - um teste aleatório de 10 mil eventos em que nada "segurado" sobrevive a menu, mapa, morte ou
    desconexão.
- No jogo:
  - o vigia do `UiKit` avisa e refoca qualquer tela visível sem foco no controle;
  - F8/F9 gravam e reproduzem as entradas do controle pela mesma camada.
- **Não verificado aqui:** nada disso rodou num controle real nem num console (Parte 12.7, matriz em
  `TODO_USUARIO.md`).

## D-45 — F5: otimização antes de espalhar a arte (em andamento)
- **Metas da Parte 2:** vegetação ≤ 3 mil triângulos por instância; props ≤ 5 mil; herói (armas,
  veículos) ≤ 20 mil. Os GLBs gerados tinham de 8 a 16 mil.
- **Remesh com `generation_remesh_3d`:** o alvo informado não é a contagem final. Pedindo 2.800,
  saíram 4.957 triângulos (~1,77×). Por isso o alvo é 1.650 para vegetação e 2.800 para props e
  equipamento. Escalas e pivôs são os mesmos da preparação anterior; o manifest guarda o job de
  remesh e os triângulos medidos no GLB preparado.
- **Resultado (triângulos medidos):**

  | Grupo | Modelos |
  |---|---|
  | Vegetação | capim-elefante 1.865, coqueiro 1.988, bananeira 2.136, árvore de colina 2.189, arbusto 2.801, bambu 3.020 (depois 2.800, ver abaixo) |
  | Casas | casa de telha 3.054, palha 3.127, varanda 3.135 |
  | Props | sacos de areia 2.838, cerca 2.851, entrada de túnel 3.239, toca 3.467, ponte 3.676, trincheira 3.725, bunker 3.975 |
  | Equipamento e herói | chapéu de selva 2.447, morteiro M29 2.884 |

- **10 remeshes terminaram em `outcome_unknown`** ("worker interruption" aos 15 min), e a regra do
  ForgeGUI é não regenerar: cozinha, celeiro, poço, altar, túmulo, capacete M1, colete M1955,
  capacete de fibra, morteiro 82 mm e uma tentativa do bambu.
- **Redução local, sem crédito** (`tools/decimate_glb.py`, pymeshlab 2025.7):
  - colapso de arestas por quádricas preservando as costuras de UV;
  - mesmas texturas (cor, ORM, normal) e mesmo nó de escala/pivô;
  - mede o desvio de Hausdorff nos dois sentidos, em metros;
  - é determinística (mesmo sha256 em duas execuções). O `fetch_forgegui_assets.py` baixa o
    original, confere o hash e refaz a redução.

  | Modelo | Triângulos | Desvio máx. / médio |
  |---|---|---|
  | capacete M1 | 14.646 → 3.000 | 0,8 cm / 0,7 mm |
  | capacete de fibra | 13.793 → 2.999 | 0,3 cm / 0,4 mm |
  | colete M1955 | 14.307 → 3.999 | 0,6 cm / 0,9 mm |
  | altar | 13.489 → 3.999 | 2,5 cm / 2,0 mm |
  | poço | 13.615 → 3.999 | 2,9 cm / 3,3 mm |
  | túmulo | 14.278 → 4.000 | 6,1 cm / 4,3 mm |
  | celeiro | 14.106 → 4.900 | 10,8 cm / 7,3 mm |
  | cozinha | 13.483 → 3.999 | 16,3 cm / 11,5 mm |
  | bambu | 3.020 → 2.800 | 30,6 cm (ponta de folha) / 3,8 mm |

  - Conferi cada um em render antes/depois com a cor da textura por face.
  - Com 4.000 triângulos, as palafitas do celeiro viravam cones; com 4.900, ficaram certas.
  - O morteiro 82 mm (14.959) já cabe na meta de herói e ficou como estava.
  - **Equipamento vestido:** um fuzileiro com capacete e colete caiu de ~29 mil para ~7 mil
    triângulos, cerca de 660 mil a menos com 30 jogadores.
  - **Não verificado aqui:** a aparência no Roblox (sombreamento com o mapa de normais). Se algum
    ficar ruim no Studio, a redução é refeita com mais faces.
- **`ArtBudget` (módulo puro):** tipo, triângulos medidos e exceções por modelo. Sobrou uma
  exceção: o arrozal (13.066), que não é colocado. O teste da F5 falha em três casos:
  - um número diverge do manifest;
  - um modelo passa da meta sem exceção registrada;
  - uma exceção fica velha.
- **Arte nos 5 setores** (`AssetLoader`):
  - teto por setor de 2,5 milhões de triângulos de arte (PLACEHOLDER até a medição);
  - ordem de prioridade: casas e quintais → vila, túneis, cemitério e vau → bosques das colinas →
    sebes;
  - as sebes pediriam ~17 mil touceiras e ~41 milhões de triângulos nos 5 setores. O que sobra do
    teto vira um **desbaste uniforme por setor** (`ArtBudget.factor`), não um corte no meio do
    mapa. Estimativa offline (`lune run tools/art_estimate.luau`): 20%, 38%, 24%, 21% e 55% das
    touceiras nos setores 1–5;
  - **a peça da sebe só fica invisível se todas as touceiras dela entraram**. Antes ela sumia
    sempre, e o corte do teto deixaria cobertura invisível;
  - `ModelStreamingMode = Atomic` em todos os modelos;
  - `LevelOfDetail = StreamingMesh` (impostor à distância) nos grandes: casas, árvores, celeiro,
    bunker;
  - o log do servidor imprime modelos, triângulos e a fração de sebes por setor, para comparar com
    o HUD de fps.
- **O teto é conservador:** o cliente só recebe o que está no raio de streaming, uma fração
  pequena do setor. Se o fps sobrar no Studio, suba `ArtBudget.SECTOR_MAX` e as sebes ganham
  touceiras sozinhas.
- **Diques (D-14, corte 1):** fusão de segmentos colineares (±1°) com o mesmo topo (±11 cm), com a
  base esticada para baixo do terreno: 18.926 → **18.095** (−4,4%), comprimento preservado
  (teste `f5.luau`).
  - O ganho é pequeno porque os topos acompanham os terraços.
  - Uma primeira versão "absorvia" trechos sobrepostos e apagava 16.690 studs de dique. O teste pegou
    e a regra foi removida.
- **Próximo corte de verdade (D-14, item 2):** juntar diques e lâminas de cada bloco numa MeshPart
  via `EditableMesh`. Isso só pode ser validado no Studio (colisão e memória), por isso fica para
  depois do primeiro teste de fps.

## D-46 — F6: modo Offensive e rotação de modos
- **Regra (Parte 4):** os EUA começam só com a praia (S5) e atacam para oeste. O VC defende S4, S3,
  S2 e S1, um de cada vez. Só o setor da frente fica ativo.
  - **Setor tomado fica travado:** o VC não retoma.
  - **A frente pode voltar:** se os EUA neutralizam e saem, o VC sozinho no ponto a recupera.
  - A captura é a mesma do Warfare (`Capture`): 90 s com 1 atacante; com 5 ou mais, 2× mais
    rápida.
  - Disputado congela.
- **Relógio:** 20 min para o 1º setor e +15 min a cada setor tomado. Os EUA vencem ao tomar S1;
  o VC vence se o relógio zerar.
  - Os dois tempos são **PLACEHOLDER**: a Parte 4 só diz "tempo extra a cada captura". Calibrar
    no beta: a meta é que metade das partidas chegue a S2.
- **Peças reaproveitadas sem mudança:**
  - spawn: reunião nos setores próprios; o VC perde a reunião e os túneis de um setor tomado;
  - bots: `BotBrain.objective` já leva os EUA à frente e o VC a defendê-la (teste `f6.luau`);
  - logística e marcadores (o próximo ponto forte aparece quando a frente anda).
- **Rotação:** servidor público alterna Warfare e Offensive a cada partida. Servidor privado fica
  no modo que o dono escolheu.
- **Servidor privado:** antes não havia tela para o dono escolher modo e horário. Só existia o
  evento no servidor. Agora o menu do jogo tem a aba **Servidor**, visível só para o dono e
  navegável no controle; o servidor revalida dono, modo e horário.
- **Não verificado aqui:** partida real de Offensive no Roblox (spawn na praia, ritmo, tempo).

## D-47 — F6: tutorial por papel, campo de tiro e página do jogo
- **Tutorial curto por papel** (Parte 9, "Aprendizado"): `Shared/Tutorial.luau` (puro) e
  `TutorialController`.
  - Um painel discreto mostra um passo por vez; nada é bloqueado.
  - Passos comuns: mirar, atirar, recarregar, deitar e abrir a carta.
  - Quem usa fuzil passa pelo campo de tiro.
  - Cada papel tem 1 a 3 passos próprios. Veículos começam pelo "entrar".
  - De 3 a 12 passos por papel.
- **Texto sem tecla fixa:** "Ação: {botão}". O cliente põe o botão do dispositivo atual e acrescenta
  "(segurar)" só quando aquele dispositivo pede segurar. No controle aparece o ícone de Xbox ou
  PlayStation (`GetImageForKeyCode`).
- **O texto não promete o que o jogo não faz:**
  - o teste falha se uma ação citada não existe no InputMap;
  - o teste falha se o texto diz "Construir" para um papel sem construção na logística.

  Dois textos do primeiro rascunho estavam errados (comandante e sapador não constroem nada) e
  foram corrigidos por isso.
- **Campo de tiro** (`TrainingService`):
  - na retaguarda de cada QG, linha de tiro e silhuetas de 0,5 × 1,0 m a 100, 200 e 300 m, no
    chão real;
  - EUA: praia, para o sul. VC: retaguarda oeste, para o norte;
  - o acerto avisa **só o atirador**, com a distância do centro em cm (acima/abaixo,
    esquerda/direita). Ensina alça e queda;
  - é a única exceção ao "sem hitmarker" (Parte 9.5), e só no alvo de treino.
- **Progresso salvo na conta**, por papel. Refazer ou pular: menu do jogo → Squad e papel.
- **Bug corrigido no caminho:** `PlayerData.migrate` descartava `settings` desde a Parte 12. As
  configurações de controle eram salvas e sumiam no login seguinte, e o `applyReceipt` também as
  apagava ao gravar um recibo.
  - O esquema foi para `ProfileSchema.luau` (puro).
  - Um teste de regressão garante que `settings` e `tutorial` sobrevivem a duas migrações.
- **Página do jogo** (`LANCAMENTO.md`):
  - descrição em português e inglês (≤ 1.000 caracteres, sem citar outro jogo);
  - ícone 512×512, sem os cantos brancos que vieram embutidos na arte;
  - miniatura 16:9 exata, sem ampliar;
  - guia do questionário de maturidade com o que o código tem hoje (sem sangue visual; sem itens
    aleatórios pagos; sem símbolos políticos);
  - roteiro do beta fechado.
- **Não verificado aqui:** o tutorial e o campo de tiro dentro do Roblox (posição dos alvos no
  terreno, legibilidade do painel na TV).

## D-48 — Features de "Lançamento" da Parte 11 (fecham a F6)
A Parte 11 marca 13 features como "Lançamento", com entrada entre a F5 e a F6. Já existiam: bots,
monetização sem vantagem, campo de tiro e tutorial. Entraram agora as outras, cada uma com a
regra num módulo puro testado (`f6.luau`).

| Feature | Como ficou | Números (PLACEHOLDER onde indicado) |
|---|---|---|
| Acessibilidade | Modo daltônico dos traçantes, campo de visão, legendas de som | Paletas medidas: vermelho x verde cai a ΔE 24 na deuteranopia; laranja x azul fica em 133–149 (simulação Machado 2009 + CIELAB). FOV de 60 a 90°. Legenda com direção e distância, no tempo do som |
| Relatório pós-ação | Folha datilografada no fim da partida | Grupo data-hora de 1965 (fuso H = UTC+8), linha do tempo, mortos por lado e setor, resultado |
| Marcação imperfeita | Marcar com o binóculo vira uma área, no mundo e na carta | Erro de 10% da distância (10 a 100 m); o alvo real fica dentro do círculo; some em 60 s |
| Arma do inimigo | A arma de quem morre cai só com o carregador | Some em 2 min; quem pega deixa a sua no chão; a caixa de munição do seu lado não reabastece arma do outro lado |
| Equipamento por peso | Carregadores, granadas, fumaça e curativos no menu (Squad e papel) | Limite = kit padrão + 1 kg; pesos aproximados (carregador de fuzil 0,75 kg, granada 0,45, fumaça 0,54, curativo 0,1). O cantil fica de fora enquanto não houver sede ou fadiga |
| Operador de rádio | Novo papel na infantaria (1 por squad): só ele fala no canal do comando | Antena de 1,2 m nas costas; ao morrer, o rádio cai e qualquer aliado pode pegá-lo |
| Pá de trincheira | Buraco de 2 homens e parapeito de sacos de areia | 1,8 × 0,6 × 1,2 m; 8 s parado; só em setor próprio, fora da água; 1 por minuto; 80 por partida |
| Medevac | Ferido grave a até 15 m de um UH-34D pousado é evacuado em 5 s | +25 de suprimento para o time; não conta como morto no relatório; leva a própria arma |
| Animais da vila | Búfalos e galinhas pastam perto de casa e fogem de tiros e explosões | Fuga a 6 m/s (búfalo) e 4 m/s (galinha); ouvem a 150 e 60 m, explosões a 3×; 1 búfalo a cada 6 casas e galinhas em 1 de cada 4 quintais |

**Suposições:**
- O medevac devolve suprimento porque o jogo não tem recurso de "mão de obra".
- Medevac não exige carregar o ferido: o jogo não tem mecânica de carregar. O helicóptero pousa
  junto dele, como numa evacuação real.
- O líder de squad perdeu o canal do comando, como manda a Parte 11 ("só ele fala com o
  comandante"). O comandante e a equipe de morteiro mantêm a própria rede.
- Os animais são estáticos (sem esqueleto) e deslizam no chão; a fuga é a pista de detecção.
  Animar exigiria rigging, mais crédito.

**ForgeGUI** (2 modelos):
- **Búfalo** (job 4ff96eac): preparado em 2,6 m; reduzido de 14.459 para 3.999 triângulos
  (desvio máx. 3,2 cm). A cabeça fica para +X no GLB (medido pelos chifres).
- **Galinha** (job ea7ed3ae): a 1ª tentativa falhou como "retomável" (não `outcome_unknown`) e o
  próprio ForgeGUI retomou. Preparada em 0,45 m; reduzida de 16.688 para 2.000 triângulos
  (desvio máx. 1,9 cm). A frente fica para +Z (medido pela crista).
- Os dois foram conferidos em render antes/depois. `AnimalService.FACE_YAW` usa as frentes
  medidas; conferir no Studio.

**Não verificado aqui:** tudo isso dentro do Roblox. Escavação do terreno, antena, legendas, folha
do relatório e animais andando precisam do Studio.

## D-49 — Primeiro teste no Studio (2026-11-10) e correções
Teste feito pelo MCP do Studio numa sessão no seu PC: Play solo com 29 bots, ~30 min, place em
greybox (IDs de arte em 0). Relatório: `testes/TESTE_STUDIO_2026-11-10.md`.

**Medido:**
- nenhum erro de script do jogo;
- 60 fps nos 5 setores, mas p99 de 18,4–18,8 ms (meta ≤ 16,7) igual em todo lugar. Parece o ritmo
  do teto de 60 do Studio; falta medir no cliente fora do Studio;
- heartbeat do servidor de 0,12–0,30 ms;
- terreno gerado em 26 s no início (heartbeat a ~19 fps nesse tempo);
- captura solo do centro em ~180 s, como manda a regra;
- espera de spawn de 60 s.

**Corrigido:**
1. **Mouse preso no centro** no mapa de spawn, na loja e no menu: `LockFirstPerson` prendia o mouse e
   nenhuma tela soltava. Agora um botão `Modal` invisível aparece em menu, mapa ou morto.
2. **M abria e fechava o mapa no mesmo quadro**, e o P fazia o mesmo com o menu (bug 7). Na troca de
   contexto, a tecla apertada era esquecida e a IAS a entregava de novo. Agora ela fica consumida
   até soltar.
3. **Deitado = HipHeight negativo** (2,4 − 4,4): queda livre permanente, escorregando a 66 m/s em
   encosta.
   - HipHeight mínimo de 0,2.
   - O servidor deita o corpo (junta Root), para o acerto bater com o que se vê; antes o
     servidor só "enterrava" o corpo em pé.
   - A câmera desce por `CameraOffset`.
4. **Botão direito não mirava:** ao entrar na mira, a troca de contexto soltava o próprio botão e a
   mira desligava. Agora só é solta a tecla cuja ação não existe no contexto novo
   (`InputMap.survives`, com teste).
5. **Raia do campo de tiro:** o servidor limpa peças do greybox entre a linha de tiro e os alvos.
   - Ressalva: as sebes têm material "Bamboo", que a bala do jogo atravessa. A causa real dos
     tiros sem acerto pode ter sido outra.
   - No Studio, o Output agora diz por quanto o tiro errou o alvo.
6. **Comando de teste sem efeito:** o `require` da barra de comando pega outra cópia do módulo.
   Agora `workspace:SetAttribute("VT65DevMode", "Offensive")` e `("VT65DevEnd", true)` funcionam
   (só no Studio).
7. **Mapa de spawn ficava na tela depois de renascer:** o `CharacterAdded` chega antes do Humanoid.
   Agora refaz a tela quando ele aparece.
8. **Output:** progresso do terreno a cada 10% (eram 420 linhas).

**Ainda não testado no Studio:** Local Server com 2–4 jogadores, F4 (veículos), controle, D-48 e
arte real.

**Depois do teste (mesma sessão):**
- **Autoteste no motor:** `SelfTest.luau`, só no Studio, acionado por
  `workspace:SetAttribute("VT65SelfTest", true)`. Roda no mesmo servidor do jogo. Verifica:
  - terreno e bots;
  - a raia e a balística do campo de tiro, com o tiro de verdade com zeragem, atravessando
    sebe e palha como no jogo;
  - deitado: HipHeight ≥ 0,2, sem queda livre, sem deslizar e com o corpo deitado no servidor;
  - arma caída de bot e rádio;
  - pá: o chão desce;
  - medevac: evacuado e suprimento;
  - Offensive pelo laço real (90 s de captura simulada) e relatório pós-ação com a captura.

  Para simular quem está nos pontos fortes, o MatchService tem `countsOverride`, que só vale no
  Studio.
- **Bots deixam a arma ao morrer** (`CombatService.dropWeapon`), com o que tinham no carregador.

## D-50 — Atualizações ("Depois" da Parte 11): armadilhas VC
- **O que é:** o sapador VC arma estacas punji e granada com fio pela roda de equipamento, em
  Construir. Custam 10 e 15 de suprimento, com limite de 20 e 12, e não podem ficar a menos de
  40 m de inimigo.
- **Quem vê:**
  - a peça é invisível no servidor;
  - quem é do mesmo lado vê, para não pisar;
  - o engenheiro inimigo detecta a até 6 m andando devagar (≤ 1,2 m/s). Detectada, ela fica
    vermelha para todos e o prompt de desarmar (4 s segurando) liga, só para engenheiros.
- **Disparo:** uma rolagem por pisada (não a cada tique). Com cuidado (< 0,6 m/s), metade da
  chance. Detectada, não dispara.
  - Punji: 350 J na perna, que dá ferimento grave, perna prejudicada e sangramento, sem matar.
  - Fio: a granada de cabo explode 1 s depois.
- **Tutorial:** o sapador aprende a armar e o engenheiro aprende a detectar.
- **Números:** todos PLACEHOLDER de design até o playtest. Regras em `Shared/Traps.luau`, testes
  em `tests/luau/atualizacoes.luau`.

## D-51 — Atualizações: chuva tropical súbita
- **Sorteio:** 1 partida em 4 tem uma pancada (Warfare e Offensive; o Skirmish não tem). Ela nunca
  começa nos primeiros 10 min. Sobe em 60 s, segura de 6 a 15 min e desce em 90 s.
- **Efeitos** (`Shared/Weather.luau`):
  - névoa mais densa (servidor, LightingService);
  - bots enxergam até metade da distância;
  - passos até 60% mais baixos;
  - chuva visível em volta da câmera, com aviso na tela.
- **Lama reduzindo velocidade:** a regra existe (até −10%), mas não foi ligada. A velocidade só é
  recalculada em mudança de postura ou ferimento, e mexer nisso sem teste é arriscado.
- **Ressalva histórica:** a Starlite foi marcada por calor extremo (muitas baixas por exaustão).
  Em agosto, a costa de Quảng Ngãi ainda tem pancadas de tarde; por isso a chuva é evento, não
  regra. Os números são PLACEHOLDER.
- **No Studio:** `workspace:SetAttribute("VT65DevRain", 1)` força a chuva; o autoteste confere.

## D-52 — Juntas do avatar como AnimationConstraint (reteste no Studio, 2026-11-10)
- **Problema:** no Studio 0.746, as 15 juntas R15 de jogadores e bots vêm como
  `AnimationConstraint` (atualização de juntas do avatar do Roblox), não como `Motor6D`. O
  `PostureService` e o `PostureController` só mexiam em `Motor6D`. Por isso ninguém deitava,
  agachava nem inclinava: o "deitado" era o corpo em pé, afundado até a cintura (cabeça a 0,90 m e
  pés 0,59 m abaixo do chão).
- **Regra:** a junta `Root` é cinemática (`IsKinematic = true`). O `CFrame` do `Attachment0` faz o
  papel do `C0` (C0 · Transform · C1⁻¹ ≡ A0 · Transform · A1⁻¹). O módulo `Shared/Joints` trata os
  dois tipos (`find`, `getC0`, `setC0`), e postura e autoteste passam a usá-lo. O cliente só grava
  a junta quando o valor muda.
- **Medido no Studio, depois da correção:**

  | Pose | Antes | Depois |
  |---|---|---|
  | Deitado (servidor) | tronco a 2° da vertical | **86°** |
  | Deitado (cliente) | 2° | **101°** (a mira inclina o tronco) |
  | Agachado (cliente) | sem pose | coxa a **87°** do quadril, joelho a **131°** |
  | Inclinado (cliente, E na mira) | sem pose | tronco rolado **17°** (alvo 16°) |

- **Autoteste:** o "deitado" agora mede a inclinação do tronco (passa com ≥ 60°), em vez de
  comparar o `C0`. A linha da raia virou "US 100 m, 5 de 5": o Output do Roblox apagava o trecho
  `m: N/` do formato antigo. Resultado: **7 ok, 3 falhas** (raia, pá e medevac), 1 pulado.
- **Place salvo pelo Studio:** este PC não tem Rojo nem Lune. Os 4 scripts foram aplicados no place
  aberto pelo MCP, conferidos byte a byte contra os arquivos, e o Studio salvou o `.rbxl`. Comparei
  com a versão anterior do Git aberta em outra janela: mesmas instâncias por classe (+1
  `ModuleScript`), mesma geometria, mesmos 11.808 atributos e os outros 107 scripts idênticos. O
  arquivo caiu de 2,82 para 1,86 MB, porque o Studio comprime de outro jeito.
- **Grupos de colisão (mesmo dia):** com o corpo deitando de verdade, o tronco encostava no chão e
  empurrava o soldado. Numa encosta de 14° ele escorregou **70 m em 5 s** (23 m/s), em queda livre.
  O escorregão do D-49 só tinha sumido porque a pose não era aplicada. Tirar o `CanCollide` não
  adianta, porque o Humanoid o religa no tronco. Solução: o terreno vai para o grupo `Ground`, e o
  corpo deitado (tudo menos o `HumanoidRootPart`) vai para `ProneBody`, que não colide com `Ground`.
  Os dois continuam colidindo com o grupo `Default`, então os raycasts dos tiros (grupo padrão)
  acertam o corpo deitado. Medido: 0,02 m em 7 s na mesma encosta, estado `Running`, tronco a 87°;
  ao levantar, as 16 peças voltam ao `Default`. O corpo deitado ainda colide com as peças do mapa
  (diques, casas).
- **Não verificado:** o que outro jogador vê (o MCP só roda Play solo). As poses de agachar e
  inclinar continuam só no cliente, como antes: o acerto no servidor usa as pernas em pé.

## D-53 — Raia, pá e medevac (autoteste com 10 ok, 2026-11-10)
- **Raia com visada livre** (`TrainingService.chooseLane`):
  - a direção e a distância fixas de `Tutorial.RANGE_LANE` passaram a ser a primeira tentativa;
  - se o terreno tapar um alvo, o servidor testa a cada 10° (até 90° para cada lado), a 40, 80 e
    120 m do QG, com atirador ajoelhado (1,0 m) e em pé (1,5 m), fora d'água e dentro do mapa;
  - no Studio: EUA a +0° e 120 m do QG; VC a −10° e 40 m;
  - os alvos ficam lado a lado, 3 m entre um e outro. Em fila, o de 100 m tapava o de 200 m.
- **Autoteste da raia com sementes como as do jogo:** com sementes de 1 a 5, o primeiro sorteio do
  xorshift32 (`Rng`) sai quase zero, e o Box-Muller vira ~4σ sempre para o mesmo lado: todos os
  tiros iam 17 a 25 cm para a direita a 100 m. O jogo usa sementes de 32 bits
  (`seedRng:nextU32()`), então o tiro real não tinha esse viés. **Fica o alerta:** `Rng.new` com
  semente pequena dá um primeiro sorteio ruim. Mudar o `Rng` mudaria todas as sequências fixas
  (arte, eventos), então não mexi sem os testes do Lune.
- **Pá:** o `FillBlock` de 1,8 × 0,6 × 1,2 m afundava só 0,2 a 0,5 m, porque o voxel tem 1,12 m e a
  superfície é suavizada. Agora as colunas de voxels sob a pegada ficam vazias até o fundo, com
  ocupação proporcional no voxel do fundo (`WriteVoxels`). Mesmo assim a suavização ergue o fundo
  ~0,6 m, então o fundo é pedido a 1,8 m. Medido: 1,19 m de mediana (42 medidas, 0,63–1,24). A
  pegada virou múltiplo do voxel: **2,2 a 3,4 m de lado**, não 1,8 × 0,6 m (D-48).
- **Medevac:** o autoteste criava um UH-34D no depósito 1, que é do LVTP-5, e os dois se
  sobrepunham. Agora usa um UH-34D já pousado. A regra do jogo não mudou e passou: evacuado, +25 de
  suprimento.
- **Autoteste no Studio:** **10 ok, 0 falhas, 1 pulado** (animais: IDs de arte em 0).

## D-54 — Visual da arma e dos tiros (2026-11-10)
O que o Studio mostrava, com os IDs de arte em 0:
- ninguém segurava arma;
- a arma caída era uma tábua de 1,0 × 0,08 × 0,25 m;
- os tiros não tinham clarão nem marca de impacto;
- o traçante era uma linha reta do olho até o impacto, acesa por 0,08 s;
- o cursor do sistema (a "mãozinha") ficava no meio da tela durante o jogo.

O que mudou:
- **Arma provisória** (`Shared/GunModel`): montada com peças, no comprimento real de cada arma
  (M14 1,126 m, Type 56 0,882 m etc.). Tem os pontos `Muzzle` (boca do cano) e `Sight` (alça).
  Some quando o modelo do ForgeGUI for publicado: o `AssetLoader` usa o asset se existir.
  - Na mão de todos: `AssetLoader.attachWeapon`. Ao pegar a arma do inimigo, o modelo na mão
    troca junto. No Studio, 29 de 29 bots e o jogador aparecem armados.
  - No chão: a arma caída é a própria arma, deitada de lado (antes, a tábua).
- **Braços segurando a arma** (`PostureController`): ombros à frente, o esquerdo vindo para o meio.
  Medido num bot: a arma aponta (0,00; 0,00; −1,00), reto para a frente. PLACEHOLDER até as
  animações: a mão esquerda não chega ao guarda-mão.
- **Arma em primeira pessoa** (`WeaponVisuals`): só quem joga vê. No quadril; mirando, vai ao ombro
  com a alça no centro da tela. Recua a cada tiro e balança ao andar. Some no menu, no mapa, no
  binóculo, sentado, caído ou morto. A arma do próprio corpo continua escondida pela câmera.
- **Tiros:** clarão de boca (luz e chama por 0,05 s) no próprio tiro e no dos outros, saindo da arma
  de quem atirou (o pacote do servidor agora diz quem foi, `by`). Também há poeira, terra ou
  respingo onde a bala para, até 150 m; em corpo não há nada, porque o jogo não tem hitmarker. O
  traçante virou um risco de ~3 m que voa pela trajetória real a partir da boca do cano.
- **Cursor:** `MouseIconEnabled` só fica ligado nas telas.
- **Bug de base achado no caminho:** o `PostureController` guardava a pose de repouso das juntas
  numa tabela com chave fraca. Quando o coletor de lixo levava a entrada, a pose seguinte era lida
  já posada, e as rotações acumulavam: o cotovelo de um bot foi de −134° a −112° em 3 s. O defeito
  já existia com `Motor6D`. Agora a pose de repouso fica num atributo da instância
  (`Joints.rest`), e o valor fica estável.

Medido no Studio:
- 3 tiros para o chão: 3 clarões e 3 nuvens de impacto, e tudo some em 1 s;
- nenhum erro no cliente nem no servidor;
- autoteste: 10 ok, 0 falhas.

**Não verificado (o traçante foi conferido depois, na D-55):**
- a pose vista por outro jogador (o MCP só roda Play solo);
- a "mãozinha" que aparece nas capturas: o jogo informa `MouseIconEnabled = false`, então
  provavelmente é o indicador do mouse virtual do MCP.

## D-55 — Arma presa ao peito, mãos por IK (2026-11-10)
- **Problema:** com a arma presa à mão (como o servidor a cria), ela seguia a rotação do pulso. O
  `IKControl` acerta a posição da mão, mas não a rotação: ficavam 20° de erro, e a arma apontava
  para onde o pulso parava.
- **Regra:** em cada cliente, a solda da arma passa de mão → arma para peito → arma, e as duas mãos
  vão até a arma por IK: a direita no punho (`Grip`) e a esquerda no apoio (`Support`).
  - Em pé e agachado: posição pronta-baixa, com o cano 20° para baixo e cruzando o corpo.
  - Deitado: à frente do peito, com o cano na horizontal.
  - A pose fixa dos braços (D-54) saiu.
- **Alcance:** o braço esquerdo alcança ~2,07 studs (0,58 m). Por isso o apoio da mão esquerda
  fica a 22% do comprimento da arma, logo à frente do carregador, e não no meio do guarda-mão.
- **Medido no Studio:**
  - em pé (3 bots): mão direita a 0,00 stud do punho e esquerda a 0,32 stud do apoio;
  - deitado: arma a 0,21 m do chão, mão esquerda a 8 cm e direita a 23 cm.
- **Traçante conferido:** numa rajada de M60 houve 26 clarões e 2 traçantes de 3,4 m, voando pela
  trajetória.
- **Não verificado:** a arma do ForgeGUI, quando publicada, precisa ter os pontos `Grip` e
  `Support`; sem eles o IK fica desligado.
- O teste da F4 está em `testes/TESTE_F4_STUDIO_2026-11-10.md`.

## D-56 — Mar no terreno e LVTP-5 na água (2026-11-10)
- **Mar:** o DEM dá 0 m no mar, e o `TerrainBuilder` só põe água onde o fundo fica abaixo de 0.
  Resultado: o mar a leste virava uma planície de areia, com 1 ponto de água de terreno no mapa
  todo. Agora, em cada linha da grade, a costa é o início do mar contínuo vindo do leste, e o fundo
  desce dali numa rampa de 1:40, de 0,4 a 8 m (PLACEHOLDER até haver batimetria). Medido: água a y = 0
  a leste da praia; o terreno ficou pronto em 39 s.
- **LVTP-5:** flutuando, o centro do chassi fica abaixo da superfície (y −1,2), e o raio que
  detecta o piso saía do centro e acertava a areia do fundo, dando velocidade de terra (21 km/h)
  na água. O raio agora sai do topo do chassi. Medido: 10,8 km/h na água (ficha: 11).
- **Comandante, morteiro e Ontos:** funcionam no Studio (ver o relatório da F4).

## D-57 — Checagem de tipos (luau-lsp 1.70.1) e o impostor dos modelos grandes
- **Defeito escondido:** o `AssetLoader` ligava `Model.LevelOfDetail = StreamingMesh` (impostor à
  distância) nas peças grandes durante o jogo. Script do jogo não tem permissão para isso: no Studio,
  um Script comum recebeu "The current thread cannot write 'LevelOfDetail' (lacking capability
  PluginOrOpenCloud)". O trecho só roda com a arte publicada. No dia em que os IDs saíssem do 0, o
  carregamento da arte quebraria. O luau-lsp acusou, porque a propriedade não existe nas definições
  para scripts do jogo.
- **Regra:** o script só põe `ModelStreamingMode = Atomic`.
- **O que a documentação do Roblox diz** (páginas Model, Streaming e SLIM, lidas em 2026-11-10):
  - o detalhe à distância agora é o SLIM (`LevelOfDetail = SLIM`; o `StreamingMesh` é o valor
    antigo), ligado modelo a modelo;
  - os dados são gerados "on first publish or play", num place publicado, com StreamingEnabled;
  - "Static models only": não vale para modelos mudados em tempo de jogo;
  - não diz nada sobre modelos inseridos com `InsertService:LoadAsset`.
- **Consequência:** marcar o SLIM no upload pelo `tools/roblox_cloud.py` não resolve, porque a
  arte é inserida e posicionada em tempo de jogo. Para ter SLIM nas peças grandes (hut_thatch,
  hut_veranda, hut_kitchen, house_tile, hill_tree, coconut_palm, granary, vc_bunker), elas teriam
  de estar fixas no place publicado. O caminho seria uma etapa de "assar a arte" no Studio, que
  tem a permissão de plugin, antes de publicar.
  - **Decisão pendente:** essa etapa muda o fluxo de publicação. Ela só pode ser testada com os
    IDs de arte publicados.
- **Também corrigido:** o `PostureController` podia passar `nil` ao `IKControl`; o
  `WeaponController` tinha uma variável sem uso e o `Bus` declarado duas vezes.
- **Resultado:** luau-lsp com 0 erros e 0 avisos em `src/`.

## D-58 — Arte publicada: o importador gira 180° e a arma ganha pontos (2026-11-10)
- **Fato medido no Studio:** o importador do Roblox gira cada GLB 180° em Y. No MeshPart, x e z
  trocam de sinal. O tamanho é o mesmo (M14: 0,316 × 1,165 × 4,021 studs no Studio e
  0,32 × 1,16 × 4,02 no GLB).
  - Conferido em três casos: o punho das pistolas, a ogiva do RPG-2 e a cabeça dos animais.
  - Todo ângulo medido no GLB precisa desse giro.
- **Regra para frente de modelo:** conferir no Studio, com captura e uma marca em −Z, e não no GLB.
  - Veículos: `ART_YAW` = −90° (a frente está em −X).
  - Animais: búfalo −90°, galinha 0.
  - Os palpites antigos (+90° e 180°) punham todos andando de ré.
- **Armas:** o modelo publicado chega centrado na caixa, aninhado e sem pontos.
  - `tools/weapon_landmarks.py` lê os GLB e gera `Shared/WeaponArt.luau` com:
    - a frente;
    - a boca: mediana dos vértices em 1,5% do comprimento;
    - a linha de visada: topo da massa de mira;
    - o punho e o apoio: frações do comprimento medidas nas capturas, abaixo da linha do cano.
  - Estatística de vértices não serve para as mãos: a bandoleira, o bipé e o tambor puxam a média,
    e o meio de um tubo reto nem tem vértice.
  - `GunModel.fit` põe o pivô no punho, a boca em −Z e os 4 Attachments: a mesma convenção da arma
    provisória. Por isso o resto do código (IK, clarão, traçante, mira e arma caída) não mudou.
  - O servidor publica uma cópia preparada em `ReplicatedStorage.VT65WeaponArt` para a arma em
    primeira pessoa.
- **Animais:** o búfalo e a galinha estavam fora do plano de upload. Agora estão em
  `assets/upload_plan.json` e no `AssetIds`: 82 assets publicados.
- Relatório: `testes/TESTE_ARTE_REAL_2026-11-10.md`.

## D-59 — Alcance do braço e pega da arma (2026-11-10)
- **Medido:** o IK do braço (avatar com juntas `AnimationConstraint`) alcança ~2,05 studs a partir
  do ombro.
  - Erro de 2–3 cm até 2,05 studs, 10 cm a 2,31 e 17 cm a 2,57.
  - O alcance de 2,07 da D-55 confere. Mas a pega antiga deixava o apoio da M14 a 2,57 studs do
    ombro esquerdo.
- **Em pé e agachado:** a pega foi de (0,5; 0; −1,2) para **(0,2; 0,2; −0,7)** no tronco, com os
  mesmos ângulos (15° de giro e 20° para baixo).
  - É a pose alcançável mais próxima da antiga: o pior caso entre as 9 armas ficou em 1,96 studs.
  - Medido com a M14 real: mãos a 7 e 11 cm.
- **Deitado:** o erro do IK depende da pose, não só da distância (até 43 cm com o alvo ao alcance).
  - A pega foi para **(−0,2; 1,3; 1,1)**: 0,5 stud à frente e 0,4 para a esquerda.
  - Medido: 8 e 10 cm (antes 27 e 24).
- **Piso:** sobram ~6 a 10 cm mesmo com o alvo ao alcance. O IK põe a mão perto do alvo, não nele.

## D-60 — Mira com a arte real: linha alça → massa no centro da tela (2026-11-10)
- **Regra:** o tiro sai do centro da tela. Mirando, a arma em primeira pessoa gira (até 3,6°, na
  M60) para que a linha do ponto `Sight` (perto do olho) ao `SightFront` (topo da massa) caia no
  centro. Nas malhas geradas a alça traseira não é zerada com a massa, então alinhar ao cano
  deixava a massa fora do centro ou tapada.
- **Topo da massa:** é o ponto mais alto a até 2 mm do plano do cano, na frente da arma.
  - O topo geral pegava as orelhas que protegem a massa (na M14 ficam mais altas que ela).
  - Com esse topo, a massa aparecia ~2° abaixo do centro, e o jogador que a pusesse no alvo
    erraria alto.
- **Olho:** o ponto `Sight` fica 9 cm à frente da mão direita, e o olho 9 cm atrás dele: o olho
  fica sobre o punho, com o rosto na coronha.
  - Com o olho 7 cm mais à frente, a caixa da culatra tomava a metade de baixo da tela.
  - Pistolas: o olho fica a 45 cm (braço estendido; `EyeM`).
- **Ajustes por arma, escolhidos olhando a captura da mira** (`tools/weapon_landmarks.py`):
  - M14: olho 8 mm acima, para a massa ficar no meio da janela da alça de dioptro;
  - M60: 30 mm à direita, 32 mm acima e 10 cm atrás. A alça de transporte do modelo está
    levantada no meio da linha;
  - M79: a escada de mira levantada fica na frente da massa. A referência é o meio da janela da
    escada, 105 mm acima do cano (é por ela que se mira longe);
  - pistolas: olho 2 mm acima, para a massa aparecer por cima da alça;
  - Type 56, SKS, RPD e RPG-2: sem ajuste.
- **Guinada dos modelos:** a Type 54 veio girada 27° e a RPD 7,2° (a M60, 1°).
  - O giro é o do eixo principal dos vértices (PCA no plano XZ). Na RPD, a reta do cano dá o mesmo.
  - É corrigido acima de 0,5°: `WeaponArt.yaw`, aplicado em `GunModel.fit`.
  - Sem isso, a pistola aparecia de perfil e a RPD de lado.
- **Medido no Studio, nas 9 armas:**
  - massa a 0,1 px do centro;
  - mão direita a 7 cm e esquerda a 3–11 cm;
  - autoteste 11/11 depois.

## D-61 — Fontes para os PLACEHOLDER da F4 e subida do UH-34D (2026-11-10)
Pesquisa na web em 2026-11-10. Cada número está no código com a fonte ao lado.
- **UH-34D:** razão de subida de **1.100 ft/min** ao nível do mar (Sikorsky Archives, "S-58";
  Army Aviation Magazine, "CH-34 Choctaw"; Patriots Point, "UH-34D Seahorse").
  - Uma fonte (globalmilitary) dá 7,6 m/s. Ela destoa das outras três e não foi usada.
  - Com a potência máxima contínua (1.275 hp), esse número dá um fator de subida de **1,03**:
    quase todo o excesso de potência vira subida, como manda a conservação de energia. Com a de
    decolagem daria 0,62, que não fecha. Por isso a calibração usa a contínua.
  - **Regra:** a subida usa o fator do pairado (600 ft/min na vertical, D-38) parado e o do voo à
    frente (1.100 ft/min) a partir da velocidade de potência mínima (51 nós), com transição linear
    entre os dois.
  - O corte de 8 m/s, sem fonte, virou uma rede de segurança de 20 m/s.
  - **Resultado (teste `f4.luau`):** no peso bruto ao nível do mar, 600 e 1.100 ft/min. Sem
    carga, na decolagem, o modelo chega a 15,5 m/s à frente.
  - **Na vertical sem carga, 11,7 m/s:** a teoria do momento dá 11,4 m/s para a mesma carga
    (conta à mão).
  - **No Studio:** só o piloto, 30 °C e coletivo cheio: **10,6 m/s**. A velocidade real do
    helicóptero foi 10,7 m/s, sem instabilidade.
- **M48A3:** motor diesel AVDS-1790-2 de 750 hp (FAS DoD-101; afvdatabase).
  - Blindagem do lado: 76 mm na frente e 51 mm atrás. O jogo tem uma zona só e usa 76 mm.
  - Traseira: **44 mm**. Antes era 51 mm, sem fonte.
  - Giro da torre: 24°/s (afvdatabase).
  - O teto (25 mm) segue PLACEHOLDER: a fonte dá 25 mm para o piso.
- **Ontos:** 13 mm no casco e na superestrutura, 6,5 mm no piso (tanks-encyclopedia).
- **Penetração** (mm RHA):
  - PG-2: 150–180 mm (wiki:RPG-2). Ficou o piso, 150 mm, e ele segue sem furar o glacis do M48;
  - M28A2 3,5": ~11 pol., 280 mm (koreanwaronline; weaponsystems.net). Antes eram 250 mm;
  - M344 106 mm: "mais de 400 mm" (wiki:M40_recoilless_rifle).
- **Tiro naval:** na Starlite, o contratorpedeiro USS Orleck (5"/38) e o cruzador USS Galveston
  (6"/47) cobriram o desembarque (história do USMC "The Landing and the Buildup"). O jogo usa o
  5"/38: 2.500 ft/s, **762 m/s**, com o cano médio (navweaps; 2.600 com o cano novo). A distância
  do navio segue PLACEHOLDER.
- **Ainda sem fonte (D-61):**
  - cargas incrementais dos morteiros;
  - teto do M48;
  - 90 mm HEAT;
  - raios dos explosivos;
  - distância do navio;
  - giro dos veículos e da torre do Ontos.

## D-62 — A arte espera o terreno (teste do mapa, 2026-11-10)
- **Defeito:** o servidor dispara a geração do terreno (~50 s) e a colocação da arte ao mesmo
  tempo. A arte fazia o raio até o chão antes de o terreno existir e ia toda para y = 0.
  - As vilas ficavam enterradas, até 20 m em An Cường (2).
  - Os placeholders das casas eram apagados mesmo assim.
  - Os animais andavam debaixo da terra.
  - O fps medido "com arte" (59–60) foi na verdade sem arte visível, então não vale.
- **Regra:**
  - o `AssetLoader` só põe a arte depois de `TerrainReady`;
  - um modelo sem chão embaixo gera aviso no Output;
  - a pasta `Map.Art` ganha o atributo `Placed` ao terminar;
  - o autoteste "arte no chão" exige que 97% das bases estejam a até 2 m do terreno.
- **Medido:** a arte fica pronta 17 s depois do terreno; 5.046 de 5.048 modelos a até 2 m do chão.
- **Pendente (decisão de arte, com o usuário):**
  - 89% das sebes continuam como caixas, por causa do teto de triângulos;
  - a `hill_tree` foi destruída pela redução local;
  - o terreno usa as cores padrão;
  - o fps com a arte visível precisa ser medido com o PC livre e o Studio em primeiro plano.

## D-63 — Mapa de 2 × 2 km no oeste (FIRME, aprovado pelo usuário em 2026-11-10)
**Substitui** a área de D-03, os setores, pontos fortes e QGs de D-08, o critério de travessia de
D-12, os depósitos "na praia" de D-37 e o mar de D-56 (o código do mar continua, mas o mapa não tem
mais mar).
- **Pedido:** "o mapa está muito grande". Das 4 janelas de 2 × 2 km em 1:1, o usuário escolheu a
  **A**: Colina 43 → An Cường (2), que é a alternativa B de D-03. A escala 1:1 não mudou.
- **Área:** E 268,35–270,35 km × N 1691,5–1693,5 km, em grade de 1965 (`geo.PLAY_ING`).
  - O terreno é gerado com 150 m de margem (2,3 × 2,3 km, grade de 515 × 514).
  - Uma travessia leste–oeste em corrida leve (3,1 m/s) leva ~10,8 min, o que devolve o critério
    "8–12 min" do prompt.
- **O que ficou de fora:** Green Beach e o mar, An Cường (1), Colina 22, An Phước (1), o vau do
  riacho e os túmulos da várzea. A partida começa depois do desembarque: os EUA entram pela borda
  leste, ao sul de An Cường (2).
- **Origem:** o quadro local continua com a origem em E 270,2 / N 1692,4, o centro do mundo gerado
  antes. Por isso nenhuma coordenada já gravada mudou. A área nova vai de X −6607,2 a 535,7 e de
  Z −3928,6 a 3214,3 (studs).
- **Como foi feito:**
  - `geo.WORLD_ING` (a extensão de 4 × 2,4 km usada na geração) ficou separado de `geo.PLAY_ING`
    (a área jogável).
  - `tools/crop_world.py` recorta `Grid`, `Heights_*` e `Features` já gerados e escreve o
    `MapConfig.luau`.
  - Os rasters de origem (DEM, carta, satélite) não estão no repositório, então recortar foi mais
    seguro que regerar.
- **Setores** (E em km; "sul / norte" quando a fronteira dobra em N 1693,0):

  | Setor | E (km) | Pontos fortes (★ = local real) |
  |---|---|---|
  | S1 (oeste, início do VC) | 268,35–268,75 | Colina 43 ★, Athletic field ★, Lugarejo da Colina 43 ★ (5 casas da carta) |
  | S2 (início do VC) | 268,75–269,15 | LZ Blue ★, Nam Yên (3) ★, Encosta norte (design) |
  | S3 (centro, neutro) | 269,15–269,60 / 269,45 | Nam Yên (4) ★, Cemitério ★, Bosque ao sul de Nam Yên (4) ★ |
  | S4 (início dos EUA) | 269,60 / 269,45–269,85 | An Thới (2) ★, Morrote do arrozal (design), Arrozal central (design) |
  | S5 (leste, QG dos EUA) | 269,85–270,35 | An Cường (2) ★, Trincheira sul ★, Colina 30 ★ |

  A fronteira S3/S4 dobra a oeste ao norte de N 1693,0. Sem a dobra, An Thới (2) caía no S3 e o S4
  ficava sem nenhum local real (o teste Luau exige ≥ 1 por setor).
- **QGs:**
  - EUA em E 270,30 / N 1691,75, a 50 m da borda leste e 250 m da sul;
  - VC em E 268,42 / N 1692,90, na retaguarda oeste.
- **Depósitos e campo de tiro:**
  - os 6 veículos ficam a oeste e ao norte do QG dos EUA, a 63–136 m dele;
  - o LVTP-5 agora anda em terra;
  - a raia dos EUA atira para oeste, porque ao sul a borda fica a 250 m.
- **Medido no Studio (2026-11-10):**
  - terreno em 1.089 blocos, pronto em 21–47 s;
  - 9.738 diques, 2.353 sebes e 92 casas no place;
  - 4.899 modelos de arte, 4.896 com a base a até 2 m do chão;
  - Colina 43 a 43,6 m;
  - autoteste com 12 ok, 0 falhas.
- **Defeito achado no teste:** o bot entrava em `Combatants` (já alvo) antes de `attachWeapon` e
  `dress`, que esperam o `LoadAsset`, e só depois ligava o `Died`. Morto nessa janela, ficava caído
  para sempre: não largava a arma e a vaga nunca voltava. Agora o `Died` é ligado antes de qualquer
  espera, e o modelo não volta à IA se morrer enquanto se veste.
- **Efeitos colaterais:**
  - o som "praia" não toca mais, porque o local não existe;
  - o modo Offensive se chama "EUA atacam do leste";
  - o navio do tiro naval continua 3 km a leste da praia real, fora do mapa;
  - a borda do terreno aparece como horizonte plano a 150 m da área jogável.

## D-64 — Mata, chão, luz e lobby (2026-11-10)
**Pedido do usuário:** "está horrível assim sem nada". Ele quer:
- mata densa, com as capturas de Hell Let Loose: Vietnam como referência;
- chão menos genérico;
- todos os modelos do ForgeGUI em uso;
- lobby e gráficos novos;
- "4K".

**Diagnóstico:**
- A arte só ia para vilas, sebes e colinas. Mata e capim ficavam em terreno pelado.
- Quatro modelos publicados nunca eram usados.
- O chão tinha as cores padrão do Roblox.
- As folhas refletiam o céu como cromo, porque todo GLB do gerador vem com mapa de metal.
- A partida começava às 06:30, com o sol a −0,9°, ou seja, no escuro.

**Decisões:**
- **Mata segue a carta** (`Modules/Vegetation.luau`, módulo puro):
  - a carta manda no "onde": 78% da área é arrozal e continua aberta;
  - **vila/mata** (3,6%): bosque fechado de árvore, coqueiro, bambu, bananeira, arbusto e capim
    alto, com 0,75 planta por célula de 20 m²;
  - **capim** (18%): moitas em manchas de ~70 m (ruído) e capim alto solto no resto;
  - **riacho**: barranco de bambu;
  - **cortina fora da área** (40 a 100 m da borda): árvores grandes que escondem o fim do terreno.
    É moldura de arte, não é a carta.
  - Zonas livres:
    - QG dos EUA 150 m e do VC 100 m (depósitos e pouso);
    - casas 6,5 m;
    - mastros 8 m;
    - bocas de túnel 5 m;
    - trincheira;
    - raias do campo de tiro.
  - **Plano:** 17,4 mil plantas, com 25,4 mil modelos no mapa ao todo (61 milhões de triângulos
    sem LOD). `SECTOR_MAX` passou para 16 milhões; `ArtBudget.JUNGLE_DENSITY` é o botão de ajuste.
  - Se o usuário quiser mata no lugar do arrozal, é só mudar a classe 2 em `Vegetation.plan`. Isso
    contraria a carta de 1965 (princípio 1), por isso não é o padrão.
- **Todos os modelos em uso:**
  - celeiro e cerca de bambu nos quintais e no QG do VC;
  - tocas de atirador em volta dos pontos fortes dos setores 1 a 3;
  - 3 canteiros de arroz perto das vilas;
  - anel de sacos de areia no QG dos EUA.
- **Modelos foscos:**
  - `tools/matte_glb.py` zera o metal e tira a textura de metal/rugosidade (rugosidade fixa 0,9) dos
    24 modelos que não são de metal: vegetação, casas, estruturas e animais;
  - os 24 foram republicados com IDs novos;
  - armas e veículos continuam com metal.
- **Luz:**
  - a partida começa às **07:00**, com o sol a 6,2° no leste-nordeste;
  - quem olha para o leste tem contraluz dourada;
  - o servidor privado ainda pode escolher 06:30;
  - Atmosphere quente: cor (232, 196, 142), decaimento (150, 112, 74), névoa 2,5 que cai até 08:00;
  - ColorCorrection com tinta quente;
  - Bloom e SunRays mais fortes;
  - nuvens dinâmicas.
- **Chão:**
  - arrozal = Grass, com a grama animada do Roblox fazendo o arroz verde sob a lâmina d'água;
  - mata = LeafyGrass;
  - cores próprias por material;
  - a lâmina d'água ficou mais escura e menos espelhada (antes refletia o céu azul);
  - diques cobertos de capim.
  - Passos e veículos continuam "arrozal", porque o raio acerta a lâmina antes do terreno.
- **Grama animada:** `Terrain.Decoration` e `GrassLength` não podem ser escritos por script do jogo
  ("lacking capability PluginOrOpenCloud"). Eles vêm ligados no arquivo do place:
  `tools/bake_place` cria o Terrain.
- **Marcadores:**
  - o disco amarelo do ponto forte ativo virou mastro com bandeira (EUA, Frente ou só o mastro
    quando neutro), que troca com o dono;
  - as placas dos QGs ficaram invisíveis e sem colisão.
- **"4K":** o Roblox desenha na resolução do monitor de quem joga, e a qualidade gráfica é escolha
  do jogador. O que dá para fazer é arte e luz boas na qualidade alta, e foi isso que foi feito.
- **Lobby (tela de deslocamento), identidade própria:** dossiê de operações de 1965. As capturas de
  HLL foram só referência de clima; o layout delas não foi copiado (D-09).
  - Fichas de arquivo creme com carimbos ("USMC", "QUÂN GIẢI PHÓNG"), pastas pardas e fundo oliva.
  - Fontes: `SpecialElite` (máquina de escrever) e `Oswald` (títulos).
  - Quatro passos: lado → squad → papel → inserção (a carta de spawn).
  - Prévia 3D do soldado (ViewportFrame) com o uniforme e a arma do papel. Os manequins são montados
    no servidor (`PreviewService`).
  - Fundo: a câmera sobre o mapa real, perto do QG do lado escolhido, com profundidade de campo e
    vinheta. Tudo volta ao normal ao nascer.
  - Arquivos: `DeployScreen`, `LobbyScene`, `SoldierPreview` e o `GameUI` reestilizado.
  - Controle: foco em todo passo; B volta.
  - Os remotes não mudaram.
- **Corrigidos no teste do lobby:**
  - a prévia do VC saía só com um braço e o fuzil: o cliente clonava antes de o modelo replicar
    inteiro; agora espera o atributo `Parts`;
  - o capacete (tamanho real) ficava rente à cabeça do avatar, que é maior que a real; agora sai
    15% maior em jogadores, bots e prévia;
  - o chat padrão do Roblox escrevia sobre o cabeçalho; agora fica escondido enquanto o lobby está
    aberto;
  - o "QG PRONTO" saía cortado na borda da carta;
  - o laço das sebes e o plano da mata passavam do limite de 10 s de script num servidor lento.
- **Pendente:** a fonte de máquina de escrever não tem algumas letras do vietnamita, e
  "An Cường" mistura glifos.

## D-65 — Mata fechada no lugar do arrozal (pedido do usuário, 2026-11-10)
**Pedido:** "mata assim, com alta densidade", com fotos de floresta tropical do Vietnã:
- dossel contínuo e nebuloso;
- floresta de tràm do Mekong, com vilas de palha e roça na beira e um canal.

O usuário pediu o máximo de triângulos, com modelos novos se preciso, "mantendo os outros
requisitos".

**Decisão (`VT65Build/Landscape.luau`, módulo puro):**
- **Mata** (2,85 km², 71%): arrozal longe das vilas e capim.
- **Lavoura** (0,84 km²): o arrozal a até 110 m das casas, e 130 m em volta dos pontos fortes de
  arrozal. Diques, lâmina d'água e sebes de arrozal ficam só nela e nas clareiras: o bake caiu de
  9.738 para 3.261 diques.
- **Bosque de vila** (0,15 km²): a classe 3 da carta, como na D-64.
- **Clareiras** (0,15 km²):
  - 30 m em todo ponto forte (o mastro e a briga);
  - LZ Blue com 90 m (pouso de helicóptero);
  - Athletic field com 70 m;
  - QGs.
- Continuam os da carta: vilas, casas, relevo, riachos, setores, pontos fortes e escala 1:1.
- Isto contraria o uso do solo de 1965 (78% de arrozal); é escolha do dono do projeto.

**Mata em três andares (`Vegetation.FOREST`)**, por hectare:
- ~4 emergentes de 24 m;
- ~17 copas tomadas de cipó;
- ~25 árvores de folha larga a 1,4–2,3x (copas de 13–21 m);
- montes de cipó (o arbusto a 1,8–3x);
- tràm e bambu em manchas de baixada (ruído de 120 m);
- sub-bosque de taioba, arbusto e capim alto.
- **Total:** 48,4 mil plantas no plano.
- **Primeira captura:** com copas de 9–16 m a mata parecia um parque; as copas maiores fecharam o
  dossel sem mais instâncias.

**Modelos novos no ForgeGUI:**
- **Prontos:** emergente de 24 m, bosque de tràm e taioba com samambaia. Os três foram preparados
  em studs, reduzidos localmente, ficaram foscos e foram publicados.
- **Copa de cipó:** ficou em `outcome_unknown` (não regerar); usa a `hill_tree` a 1,6x.
- **Monte de cipó:** foi recusado por falta de crédito (3.693 de 4.000).
- A redução local para nas costuras de UV:
  - a emergente fica com 6 mil (com 3 mil perde 2,8 m de copa);
  - o tràm, com 4.496, e a taioba, com 4.595, com a borda solta (`decimate_glb --soltar-bordas`).
  - As três são exceções registradas à meta de 3 mil. A taioba ficou com metade da densidade
    prevista.
- O arbusto e a árvore de folha larga tinham textura quase preta (média dos pixels pintados
  (48, 45, 20) e (72, 76, 59)). Ganharam ganho de cor no `matte_glb` e foram republicados.

**Desempenho:**
- **Streaming:** o raio caiu de 717 m para 430 m. Na mata fechada e com névoa ninguém vê mais
  longe, e o cliente só carrega o que está perto.
- **Teto por setor:** 40 milhões de triângulos. O setor 5 pede 35,6 milhões sem LOD.
- **Sombra:** só nas emergentes e nas árvores de folha larga a partir de 1,7x (7,1 mil de 48,4
  mil).
- **Travamento no teste:** com sombra em todas as árvores, a GPU de 2 GB do PC de teste travou no
  Studio (`DXGI_ERROR_DEVICE_HUNG`) com o EA FC 26 aberto ao lado.
- **Sem cortar arbusto em qualidade baixa:** quem joga em gráfico baixo veria através da
  cobertura, o que seria vantagem injusta. O próprio Roblox reduz sombra e detalhe na qualidade
  baixa.
- **fps:** não medido, porque o FC 26 estava em primeiro plano o tempo todo. Ajuste:
  `ArtBudget.JUNGLE_DENSITY`.

**Capturas no Studio:**
- de dentro: troncos grossos com sapopemas, cipós, camadas sumindo na névoa;
- do alto da Colina 43: dossel contínuo até o horizonte, com névoa;
- antes do ganho de cor, o arbusto aparecia preto na sombra.

**Pendentes:**
- a textura dos sacos de areia (republicados na D-64) não carregou num dos testes ("Unable to
  load ... ColorMap"); conferir;
- o fps com o PC livre.

## D-66 — Malha cheia (8 mil+ triângulos), chão fotográfico e relevo da carta (2026-11-11)
**Pedido do usuário:**
- árvores com no mínimo 8 mil triângulos;
- chão melhor;
- relevo igual ao real;
- pesquisar vegetação e "outras coisas" de 8 mil+ para o mapa.

**Modelos (sem gastar crédito):**
- O gerador do ForgeGUI entrega a malha cheia (8–17 mil triângulos); os 2–5 mil vinham do remesh.
- Os 26 modelos do mapa voltaram à malha cheia, preparados no mesmo tamanho real:
  - **9 de vegetação:** de 7.978 (capim elefante) a 13.636 (emergente);
  - **17 props:** casas, celeiro, poço, altar, túmulo, cerca, ponte, entrada de túnel, trincheira,
    toca, sacos de areia, bunker, búfalo e galinha, de 9.602 a 17.067.
- Todos ficaram foscos e foram republicados.
- O capim elefante fica com 7.978 (a malha cheia; registrado em `ArtBudget.BELOW_MIN`).
- **Metas:** `ArtBudget.MAX` passa a 20 mil para vegetação e props (o limite do Roblox por
  malha), e `MIN_VEG` = 8 mil. Antes as metas eram 3 mil e 5 mil.
- **Ganho de cor** (`matte_glb`) nas texturas escuras da malha cheia: arbusto, folha larga,
  bananeira, emergente e tràm.

**Chão:**
- Quatro texturas PBR fotográficas do Poly Haven (CC0; cor, normal e rugosidade em 1k) entram
  como `MaterialVariant` do terreno, no bake (`tools/bake_place`), com troca do material base:
  - mata (LeafyGrass): `forrest_ground_01`;
  - capim e arrozal (Grass): `leafy_grass`;
  - riacho (Mud): `brown_mud_leaves_01`;
  - terra (Ground): `forest_ground_06`.
- Tamanho real da foto (2 m) e padrão "Organic".
- `tools/fetch_textures.py` baixa as texturas.
- O Open Cloud devolve ID de decal; os IDs de imagem foram resolvidos no Studio
  (`AssetIds.GroundImages`).

**Relevo (`tools/relevo_dem.py`):**
- O relevo já era real: o DEM de satélite Copernicus GLO-30, calibrado nas cotas da carta.
- O que mudou:
  - a suavização gaussiana caiu de 15 para 5 m, com a mesma abertura de 70 m que tira copas e
    casas, e volta o detalhe real de encostas e grotas;
  - não mexe na lavoura das vilas (diques e lâminas têm altura fixa);
  - os cumes são calibrados na carta: **Colina 43 = 43,0 m** e **Colina 30 = 30,0 m** (estava a
    35,1 m).
- **Medido:** o detalhe somado é de 0,09 m em média, e só 3% das células mudam mais de 0,5 m.
  A planície de Vạn Tường é plana de verdade; o "relevo igual ao real" já estava lá.

**Desempenho (Studio, PC sem outro jogo):**
- **Antes do ajuste:** 38 fps no ponto mais denso da mata. O CPU de render gastava 25 ms porque
  o cliente tinha as 48 mil plantas carregadas: o streaming padrão só descarrega sob pressão de
  memória.
- **Depois do ajuste:** com `StreamOutBehavior = Opportunistic`, o cliente fica só com o raio de
  430 m (12 mil plantas) e chegou a **45 fps** (pior quadro 38 ms). Isso com o Roblox Player do
  usuário aberto ao lado; num cliente sem o Studio o número tende a subir.
- **Pendente:** medir no jogo publicado. `ArtBudget.JUNGLE_DENSITY` segue como ajuste.
- O plano inteiro soma ~617 milhões de triângulos sem LOD; o LOD automático do Roblox reduz os
  modelos distantes.

**Autoteste:** 10 ok, 0 falhas. Nenhuma textura ou modelo falhou ao carregar; os sacos de areia
estão resolvidos.

**Medido no Studio:**
- **fps:** 59,3 de média (pior quadro 26 ms), com 25,4 mil peças de arte no cliente, no ponto
  mais denso do setor 2.
  - A medida foi antes dos modelos foscos e da grama animada, com qualidade "Automática".
  - Depois mediu 14 fps, mas com o EA FC 26 em primeiro plano no mesmo PC. Desligar a grama não
    mudou o número, então essa medida não vale.
  - **Medir de novo com o PC livre.**
- **Capturas:** mata fechada com folhas verdes e foscas, arrozal com arroz, vilas como ilhas de
  árvores no arrozal, bandeiras e sacos de areia.

## D-67 — Árvores prontas com folha em cartão, mira centrada e aço das armas (2026-11-11)
**Pedido do usuário:**
- árvores prontas de qualidade, como as do Front44, "para o jogo não ficar tão pesado";
- "concerte as miras": anel e risco da mira centralizados;
- miras e armas com mais textura e detalhe.

**Árvores (Poly Haven, CC0):**
- **Por que não o Creator Store:** `InsertService:LoadAsset` só carrega, no jogo publicado, asset
  do dono do jogo, compartilhado com ele ou da Roblox. Árvore grátis de terceiro não carrega.
- **Fonte:** quatro árvores CC0 do Poly Haven (`tools/fetch_trees.py`, sem login): `island_tree_01`,
  `_02`, `_03` e `tree_small_02`. O jacarandá (24 m) ficou de fora: a redução dos 1,2 milhão de
  triângulos de galho parava em 167 mil.
- **O modelo original** tem cada folha modelada: ~30 a 59 mil folhas de 24 triângulos, de 1 a
  2 milhões de triângulos por árvore.
- **Preparo (`tools/prep_trees.py`):**
  - cada folha vira um cartão (2 triângulos) no plano dela, com a mesma região da textura. A
    transparência é o contorno das folhas, desenhado a partir das UVs originais (a textura é JPEG,
    sem alfa), e também exige cor acima do fundo preto;
  - ficam 4,8 a 5,2 mil folhas, cada uma 2,4 a 3,5 vezes maior, para a copa cobrir o mesmo
    volume;
  - a normal da folha fica meio voltada para fora da copa (volume na luz);
  - tronco e galhos: galho fino demais (escondido na copa) sai, e o resto é reduzido por
    quádricas a ~3 mil triângulos; a escala da textura (`KHR_texture_transform`) vai para as UVs;
  - base do tronco na origem, em studs; peças de até 19 mil triângulos; sem metal.
- **Resultado:** 12.554 a 13.736 triângulos por árvore, e 2,6 a 2,8 MB por GLB.
- **No Roblox:**
  - o importador do Open Cloud traz a folha com `AlphaMode = Overlay` e face única;
  - script do jogo pode trocar (conferido no Studio): o `AssetLoader.template` liga
    `AlphaMode = Transparency` e `DoubleSided` em toda peça `Folhas*`. O cliente recebe as duas
    propriedades replicadas;
  - o tronco (`Madeira0`) é sólido e para a bala (`Material = "Wood"`); copa e galhos continuam
    folhagem (escondem, não param bala);
  - o tronco fica no grupo de colisão `VT65Tronco`, que não colide com o chassi dos veículos
    (`VT65Veiculo`): sem isso, um M48 pararia em cada árvore da mata. Os bots já pulam e mudam o
    desvio quando ficam 3 s sem avançar.
- **Na mata (`Vegetation`):**
  - emergente de 17–21 m: `ph_tree_small_02` (escala 3,6–4,6);
  - dossel de 8–17 m: `ph_island_tree_01` e `_02` (2,2–3,6);
  - árvore torta baixa nas manchas de cipó: `ph_island_tree_03` (1,6–2,6);
  - bosque das vilas, capinzal, cortina da borda e colinas trocam a árvore do ForgeGUI pelas
    novas. Bambu, bananeira, coqueiro, tràm, taioba, capim e o monte de cipó continuam;
  - a folha cresce com a escala (25 a 65 cm), como a das árvores de folha larga da região.
- Sombra: emergente sempre; dossel só a partir da escala 3,0–3,2 (`Vegetation.SHADOW`, agora a
  escala mínima por espécie).
- **Captura no Studio:** folhas recortadas uma a uma, tronco retorcido com casca de foto.
  - Na primeira versão cada folha tinha contorno preto: era o fundo da textura vazando pela
    borda. Corrigido com o alfa pela cor.
- **Peso:**
  - por árvore, igual ao da D-66: 12,5–13,7 mil triângulos contra 13,2–13,6 mil;
  - o plano tem 47.818 plantas, das quais 15.102 são árvores novas;
  - **fps (Studio em primeiro plano, Roblox Player do usuário aberto ao fundo):** 53,2 fps de média
    girando 360° na célula de 60 m mais densa (133 plantas; 320 a 80 m; 5.500 no cliente), 99% dos
    quadros abaixo de 25 ms, pior quadro 32 ms. Na D-66 eram 45 fps no ponto mais denso.

**Mira (`tools/sight_align.py`):**
- **Causa:** até a D-66 o ponto `Sight` era de conta (9 cm à frente da mão, na altura da massa).
  - A linha ia dele ao topo da massa, e a alça de verdade ficava onde caísse.
  - Na M14, o olho ficava 5 mm acima do centro do anel, e o anel aparecia abaixo do centro.
- **Agora:** a malha é fatiada na alça e na massa, e vista de frente a 0,2 mm por pixel:
  - **anel** (M14): o furo fechado mais perto do plano do cano; o centro do furo é o ponto `Sight`
    (furo de 5,5 mm, 37,4 mm acima do cano);
  - **entalhe** (Type 56, SKS): o meio do vale do topo, na altura dos ombros;
  - **massa:** o ponto mais alto a até 3 mm da coluna da alça. Na massa com capuz (Type 56, SKS)
    pula o arco do capuz e pega a ponta da massa.
- **Olho:** M14 a 4,5 cm do anel. Type 56 (19 cm) e SKS (32 cm) com o olho sobre o punho, rosto
  na coronha.
- **Studio:** na M14 o anel fica no centro da tela, com a massa dentro dele; na Type 56 a massa
  fica no entalhe, no centro.
  - Com o olho a 6,5 cm, o anel ficava pequeno e a base da alça tomava o meio da tela.
- **Ficam com a linha da D-60:** M60 (a fatia da alça não mostrou furo fechado), RPD, M79,
  pistolas e RPG-2.
- O `tools/weapon_landmarks.py` usa as medidas automaticamente.

**Aço das armas (`tools/armas_parker.py`):**
- Os GLB do gerador vêm com textura de 4096 px, metal médio (~0,4) e rugosidade ~0,5. O Roblox
  reduz a textura para 1024, e o aço da M14 parecia prata polida.
- **Agora:**
  - as três texturas vão a 1024 px com Lanczos, e a cor ganha nitidez;
  - onde o mapa diz metal, a cor vai ao aço fosfatizado cinza-esverdeado (EUA) ou oxidado
    azulado (armas chinesas e soviéticas). A rugosidade sobe a 0,62 no mínimo e o metal cai 30%;
  - madeira, lona e plástico ficam como estão;
  - a malha não muda: os pontos do `WeaponArt` continuam valendo.
- As 9 armas foram republicadas com IDs novos.
- **Limite:** o detalhe da malha é o do gerador. Mais detalhe pede modelo novo: do Sketchfab, como
  no Front44 (download com a conta do dono), ou crédito no ForgeGUI.

## D-68 — Terceira pessoa e movimentação (2026-11-11)
**Pedido do usuário:** "permita jogar em terceira pessoa" e "coloque a melhor movimentação
possível para o personagem".

**Terceira pessoa** (`Controllers/ThirdPerson.client`, `ViewMode`):
- **Teclas:** O alterna 1ª/3ª pessoa e I troca o ombro. No controle: direcional → segurado e
  ↑ segurado.
  - No controle, o binóculo (↑) e o canal de rádio (→) passaram de "apertar" para "tocar":
    disparam ao soltar, com menos de 0,3 s.
- **Menu:** Configurações › Mira ganhou "Câmera" e "Ombro da 3ª pessoa", salvos na conta.
- **Câmera:**
  - fica até 0,55 m para o lado e 2,1 m atrás do olho (agachado 1,9 m, deitado 1,7 m);
  - a transição leva 0,28 s;
  - parede e terreno puxam a câmera na hora, e ela nunca atravessa;
  - a folhagem a aproxima de forma suave, até 1 m do ombro (`FOLIAGE_MIN_M`).
- **Mira:** mirar ou usar o binóculo volta à 1ª pessoa em 0,1 s, porque a mira de ferro é em
  1ª pessoa; ao soltar, volta ao ombro em 0,2 s.
- **Onde fica em 1ª pessoa:** veículos, caído, morto e lobby, como antes.
- **Por modo:** com `workspace:SetAttribute("ThirdPersonAllowed", false)` no servidor, a 3ª
  pessoa fica desligada. Sem o atributo, é permitida.
- **Contrato:** o atributo local `ThirdPersonView` é `true` só com a câmera de fato no ombro.
  - O `WeaponVisuals` esconde a arma de 1ª pessoa e tira o clarão da arma do personagem.
  - O corpo e a arma "Weapon" aparecem: a câmera do Roblox os escondia.
- **Tiro em 3ª pessoa:**
  - a bala sai do olho do personagem rumo ao ponto da retícula;
  - do quadril há dispersão: 1,2° parado, mais 0,5° por m/s e mais 1,2° cansado. Sem isso a
    retícula viraria mira de ferro grátis;
  - **servidor:** além da regra de 8 studs da cabeça, se a origem está a mais de 1 m da cabeça e
    há algo sólido no meio, o tiro sai da cabeça. Isso impede atirar da câmera através da parede.

**Movimentação** (`Shared/Movement`, `Controllers/Movement.client`, testes em `movimento.luau`):
- **Inércia:** aceleração de 7 m/s² e frenagem de 10 m/s². Do parado ao trote em 0,45 s, da
  corrida à parada em 0,55 s e meia-volta em 0,75 s. Na lama e no arrozal acelera mais devagar,
  e no ar quase não há controle.
  - Nunca passa do teto do servidor (5.000 sorteios no teste).
- **Fôlego:**
  - corrida contínua até zerar: 24 s com até 15 kg, 20,5 s para o fuzileiro (21,2 kg) e 16,5 s
    para o operador de rádio. Subida e arrozal cansam mais;
  - depois de zerar, só volta a correr acima de 35%;
  - recupera após uma pausa de 1,2 s e enche em 15,5 s, mais rápido deitado;
  - cansado, a mira de ferro balança até 3,5 vezes mais.
- **Peso:** 11 kg de base, mais a arma, os carregadores, as granadas e os curativos do `Kit`, mais
  um extra por papel.
- **Chão:**
  - velocidade: arrozal 62%, lama 72%, areia 85% e mata 93%;
  - a água pesa pela fundura: ~75% no joelho e ~40% na cintura;
  - rampa: 20% de subida deixa a 78%;
  - a chuva enlameia o chão mole (até −10%).
- **Pulo:** 0,45 m descansado e 0,2 m cansado, menos com peso. Custa 7% de fôlego e tem 0,8 s de
  intervalo.
- **Queda:** pulo comum só balança a câmera; uma queda de 3 m freia o soldado e cansa.
- **Transpor e escalar** (Espaço ou A):
  - obstáculo de 0,35 a 1,25 m, a até 0,9 m;
  - transpor leva ~0,6 s (dique) a 0,72 s (sacos de areia), e escalar ~1,28 s;
  - não se atira durante o movimento, e os outros veem as pernas pelo atributo `Vaulting`.
- **Mergulho:** segurar "deitar" correndo acima de 3,5 m/s dá um deslize de 0,5 s e chega ao chão
  em 0,45 s.
- **Postura:** transição suave de câmera, pernas e inclinar: agachar 0,28 s, deitar 0,8 s e
  levantar 1,0 s. Deitando ou levantando não se corre nem se atira.
- **Câmera e som:**
  - balanço do passo de até ~2 cm;
  - respiração mais funda quando cansado;
  - passos com volume por postura, e som de aterrissagem e de transpor.
- **Servidor (`PostureService`):** não havia anti-trapaça de movimento. Agora há um orçamento de
  corrida bem mais folgado que o do cliente (36 s, recupera mais rápido e zera no renascimento).
  Em 10.000 passos aleatórios ele nunca corta a corrida antes do cliente.
  - A fórmula de velocidade do servidor (`MedicalService`) está espelhada em
    `Movement.serverSpeed`; se mudar lá, mude aqui.
- **Não testado no motor:** os números são de projeto.

## D-69 — Céu de foto, recuo normal, inclinar no L3/R3, recarga real e mira nítida (2026-11-11)
**Pedido do usuário:**
- "o céu está bugado pixelando muito e trocando conforme eu olho";
- "diminua recoil das armas faça eles normais";
- "faça poder se inclinar quando mirar com os botões no controle R e L dos analógicos";
- "faça um recarregamento real, detalhe melhor a mira está muito pixelado".

**Céu:**
- **Causa:** as nuvens dinâmicas do Roblox (`Clouds`, D-64) são desenhadas em baixa resolução,
  com ruído que muda com o giro da câmera; com a névoa forte da D-64 ficava pior.
- **Agora:**
  - sem `Clouds` (`TerrainLook` apaga as que houver);
  - céu de foto no `Sky`: HDRI "pure sky" `kloofendal_48d_partly_cloudy_puresky` do Poly Haven
    (CC0), cortado em 6 faces de 1024 px por `tools/fetch_sky.py`, com o disco do sol tirado da foto
    (o Roblox desenha o próprio sol);
  - a convenção das faces foi conferida no Studio com faces rotuladas: `Ft` é visto olhando para
    −Z, `Lf` fica em +X e `Rt` em −X, e na `Up` a direita da imagem aponta para −Z e o topo para +X.
    Sem emenda nos cantos;
  - névoa (Atmosphere) mais leve: às 07:00, Density 0,31, Haze 1,2 e Glare 0,43 (eram 0,38, 2,5 e
    0,85). Com a névoa antiga a foto sumia num laranja chapado.

**Recuo:**
- **Causa (bug):** a conta fazia `math.deg` da velocidade de recuo, dando ~100° de subida por tiro
  na M14.
- **Agora:** 0,9° por m/s de recuo livre (impulso do projétil e dos gases contra a massa da arma):
  M14 ~2,3°, Type 56 ~1,8°, M60 ~1,0° e M1911 ~4,7°, × 0,8 mirando. Sobe rápido e 60% volta
  sozinho em ~0,25 s; o resto o jogador corrige.

**Inclinar:** mirando, L3 inclina à esquerda e R3 à direita (afundar os analógicos); LB prende a
respiração e RB segue marcando. Teclado sem mudança (Q/E e Shift).

**Recarga real:**
- O cliente só anima se o servidor vai aceitar (há carregador e não está recarregando), no tempo do
  servidor (`CombatService.RELOAD`: fuzil 3 s, metralhadora 7 s, pistola 2,5 s); não atira
  recarregando.
- **Mãos e antebraços em 1ª pessoa:** mão direita no punho, esquerda no guarda-mão e antebraço
  de 27 cm com a manga do uniforme, rumo a um cotovelo fora da tela. Antes a arma flutuava
  sozinha. A pedido do usuário, a arma no quadril veio para junto do corpo: (0,12; −0,15; −0,23) m
  da câmera, eram (0,17; −0,19; −0,34) m; assim só antebraço e mãos aparecem.
- A malha da arma é uma peça só (o carregador não sai dela), então a troca é encenada:
  - a arma sai do ombro e inclina para mostrar o encaixe;
  - a mão esquerda puxa um carregador (peça à parte), que cai no chão;
  - busca outro na cartucheira, encaixa, dá o tapa e puxa o ferrolho.

**Mira nítida:**
- A alça e a massa ocupam poucos texels da textura de 1024 px da arma inteira.
- Por cima delas vão peças lisas de aço no ponto medido na malha (D-67): anel de 16 segmentos na
  M14, entalhe na Type 56 e na SKS, e a lâmina da massa. Ficam 0,4–0,6 mm à frente da malha.
- `WeaponArt` ganhou `sightKind` e `sightMm` (gerados pelo `weapon_landmarks.py`).

**Não testado no motor:** recarga, braços e mira nítida. O céu foi conferido no Studio.

## D-70 — Uniformes v3, corpo "Man" e equipamento 3D por código (2026-11-11)
**Pedido do usuário:** "uniformes bem feitos".

**Moldes v3** (`tools/make_clothing_v3.py`, `assets/clothing/v3/`, 9 moldes publicados):
- **Marines (agosto de 1965):**
  - utilitário OG-107 de sateen: 2 bolsos de peito com aba de cantos cortados, águia-globo-âncora
    com "USMC" em estêncil no bolso esquerdo, camiseta verde no decote, camisa por dentro;
  - calça de 4 bolsos, **sem bolso de carga** (a de carga é do uniforme de selva, posterior);
    presa por cima da bota preta de couro (a bota de selva também é posterior);
  - mangas abaixadas; arregaçadas só com o cosmético `us_utility_rolled`.
- **VC:** cáqui (padrão) e verde (cosmético), gola virada, camisa por fora, calça arregaçada e
  sandália Ho Chi Minh. Pijama preto (áo bà ba) da guerrilha local em 20% dos bots
  (`Gear.GUERRILLA_SHARE`); para jogador, só com o cosmético `vc_black` (ainda não existe no
  Commerce).
- Com ID 0, o código cai no molde v2.

**Corpo:** pacote "Man" (bundle 238, o mesmo do avatar padrão "Neoclassic Male"), peças da Roblox
(criador 1), configurável em `Characters.BODY` ("bloco" volta ao corpo antigo). Proporção clássica:
a caixa de acerto fica perto da atual e a roupa clássica veste melhor. Rthro recusado (cabeça menor,
roupa esticada).

**Equipamento 3D por código** (`Modules/Gear.luau`):
- **Marines:** cinto M1961 com 4 porta-carregadores de M14 (o M1956 é do Exército), mochila M1941
  com a pá M1943, 2 cantis, estojo de curativo e alças sobre o colete. Por papel: rádio PRC-10 com
  antena, coldre, bolsa médica, estojo de binóculo, kit mínimo para tripulação.
- **VC:** cinto de lona, cantil de alumínio, granadas de cabo, porta-carregador de peito conforme a
  arma (10 células no SKS, 3+2 no Type 56), bolsa de tambor do RPD, coldre do Type 54; tubo de
  arroz só com cosmético pago.
- **Correção antiga:** capacete e colete do ForgeGUI estavam soldados sem o giro de −90° da D-58 (o
  colete ficava de lado). Agora `Gear.ART_YAW = −90°`, com tamanho ajustado à cabeça e ao tronco.
- Capacete, colete, capacete de fibra e chapéu da selva republicados foscos (tinham metal = 1).

**Cores (o dono deixou a decisão comigo, 2026-11-11):** ficam as cores históricas do cáqui e do
verde, conferidas nas fotos de 1965, mesmo passando dos ±5% de luminância da regra de neutralidade
do Commerce. Motivo: a fidelidade às fotos é critério do projeto (Parte 9.1), e o dono passou a
aceitar vender vantagem em Robux (D-72).

**Não testado no motor:** altura com o corpo "Man" (atributo `AlturaM`), frente do colete,
capacete na cabeça dinâmica e posição das peças 3D.

## D-71 — Lobby na mesa, cursor no controle, recompensa diária e telas de carregamento (2026-11-11)
**Pedido do usuário:** lobby interativo como a "segunda foto" (mesa de briefing), escolhido no
controle "como se o analógico fosse o mouse", com cara da guerra do Vietnã; telas animadas de
carregamento; "carregar o mapa e a pessoa não entrar toda travada"; "daily reward". Layout original
(regra de não copiar outro jogo).

**Lobby diegético** (`LobbyScene`, `DeployScreen`, `SoldierPreview`):
- **Antes do lado:** sala de arquivo com os dois dossiês e os dois soldados.
- **EUA:** barraca de comando dos Marines. **VC:** abrigo de terra com teto de toras.
- **Objetos da mesa são os botões:** rádio PRC-10 / telefone de campanha (squad), dossiê /
  documentos e o próprio soldado (papel), carta / croqui (inserção; desenhada com o `MapConfig`),
  calendário / caderneta (recompensa diária), lata / caixote de munição (loja), capacete (trocar de
  lado). Realce e etiqueta ao apontar; ao escolher, a câmera vai ao objeto, ele "abre" e o painel
  entra deslizando. Abas no alto repetem os objetos.
- **Controle** (`VirtualCursor`): analógico esquerdo move o cursor (zona morta, curva, aceleração e
  ímã leve), A clica em 2D e 3D, B volta, LB/RB pulam entre objetos ou abas, direcional salta ao
  alvo mais próximo, analógico direito rola listas. Mouse e toque também.

**Recompensa diária** (`Modules/DailyRewardService.luau`): um resgate por dia UTC (relógio do
servidor), trilha de 7 dias (18 a 24 de agosto); dia perdido volta ao dia 1, mas o total e os itens
ficam. Dias 3 e 7 dão cosméticos só daqui (Zippo gravado e cigarros no capacete; sandálias de pneu e
marmita cà mèn). Gravação atômica (`UpdateAsync`); perfil v2 com migração da v1.

**Telas de carregamento:**
- **Entrada** (`ReplicatedFirst/LoadingScreen`): filme granulado e carta sendo traçada, com
  progresso real (jogo, remotes, `PreloadAsync`, `TerrainReady`); "ENTRAR" só com o essencial
  pronto. O `default.project.json` ganhou o ReplicatedFirst, e a tela aparece desde o 1º quadro.
- **Inserção** (`SpawnTransition`): escurece, mostra a ordem datilografada com a grade, faz
  `RequestStreamAroundAsync` antes de pedir o spawn e segura o corpo até haver chão embaixo.

**Não testado no motor:** luz da barraca, orientação dos textos da mesa, animações de abrir,
enquadramento em 16:9 e 4:3, cursor no controle, inserção com streaming, resgate com DataStore real.

## D-73 — Defeitos do mapa corrigidos no terreno real (2026-11-11)
**Pedido do usuário:** "comece a corrigir defeitos no mapa em todos os aspectos".

**Como achei:** verificação automática no Studio (base de cada modelo contra o chão nos cantos,
peças do arrozal contra o chão, plantas perto de construções), passada de câmera por vilas,
arrozal e borda, e o autoteste.

| Defeito (medido no Studio) | Antes | Depois |
|---|---|---|
| Lâmina d'água do arrozal com o topo abaixo do chão (arrozal parecia capim seco) | 1.136 de 1.155 | 3 |
| Dique enterrado | 594 de 3.261 | 7 |
| Sebe flutuando (até 0,9 m) | 134 | 0 |
| Sebe com colisão (parede invisível de 2,3 m na lavoura) | 1.754 | 0 |
| Construção, cerca ou túmulo com a base no ar em ladeira (até 1,2 m) | ~120 | 0 |
| Planta da mata dentro de celeiro, poço ou altar | sim | só casas e props com folga |

**Causas e correções (`AssetLoader`):**
- **Arrozal:** o terreno é gerado em tempo de jogo (voxel de 4 studs) e a superfície sai ~0,44 m
  acima da altura usada no bake. Agora `fitFeatures` encaixa as peças no terreno real logo depois
  do `TerrainReady`:
  - lâmina 6 cm acima da mediana do chão sob ela;
  - crista do dique 35 cm acima do ponto mais alto do chão ao longo dele;
  - pé da sebe no chão, e sem colisão.
- **Ladeira:** a base ia para o ponto mais alto de 5 raios.
  - Construções e montes ficam na cota mais alta da planta (o chão não entra na casa), e o
    terreno embaixo é aterrado até a base: o patamar de terra batida das casas da região.
  - Árvores e cercas vão ao ponto mais baixo sob o pé (a raiz entra na encosta).
- **Mata dentro de construção:** a mata só desviava das casas. Agora desvia de todo prop já posto
  (celeiro, poço, altar, túmulo, cerca, bunker, sacos de areia), com raio = meia caixa + 1,5 m.
- **Raia do campo de tiro:** com o tronco sólido (D-67), a árvore pronta precisa de folga pelo
  tronco inteiro, que tem 9–11 m de largura com os galhos grossos e o centro fora do pé. O plano
  tira 41 árvores das raias e da trincheira.
  - No autoteste, o tiro de 300 m que erra o alvo pela dispersão agora para numa árvore atrás dele
    (antes seguia sem registrar). Continua 4 de 5, e é erro de tiro, não árvore na raia.

**Autoteste depois das correções:** 10 ok, 0 falhas, 2 pulados (pedem o jogador em campo).

## D-72 — Postos, créditos de intendência, equipamento e renascer onde caiu (2026-11-11)
**Pedido do usuário:** "ranks para subir", "telas animadas", "comprar itens da melhor qualidade ao
invés de começar pelado", "pagar e renascer no mesmo lugar". O dono decidiu: **Robux e também a
moeda do jogo** para equipamento e renascer (exceção à Parte 11, ver `MONETIZATION.md`).

**Regras** (`Shared/Progression.luau`, puro; testes em `progressao.luau`, 12 ok):
- **Postos:** 13 por lado, um só XP (o servidor troca o jogador de lado para equilibrar).
  - EUA: escala do USMC, de Private a Colonel (o Lance Corporal existe desde 1958).
  - VC: designações por função, de Tân binh (recruta) a Trung đoàn trưởng; a Frente não usava
    postos com insígnia.
  - Curva: 600, 900, 1.500… XP por degrau (o 2º posto em ~1 partida; o 13º com 75.700 XP).
  - Promoção paga o soldo: 25 CI × o posto novo. Tela de promoção animada no cliente.
  - Papéis de especialista pedem posto: comandante, atirador de elite e piloto 3; observador,
    tripulante de blindado e metralhador de porta 2. Infantaria e líder ficam livres.
- **XP e créditos de intendência (CI)** por ação: abate 100/10, assistência 50/5, captura 200/20,
  neutralização 100/10, reanimação 75/8, tratamento 40/4, curativo num companheiro 15/1, minuto
  em campo 10/2. Fim de partida: vitória 500/60, empate 300/40, derrota 200/25, proporcional ao
  tempo no time (menos de 3 min não conta).
  - Teto anti-farm: 800 XP e 60 CI por minuto de ações. Cuidar do mesmo companheiro só rende de
    novo depois de 1–5 min.
  - Recompensa diária: 30 CI no 1º dia, +10 por dia da sequência, até 100.
  - Verba inicial: 300 CI (dá para o 1º item já no começo).
- **Equipamento** (soma ao kit padrão de 1965 e pesa no corpo): libera para sempre por qualquer
  caminho:
  - **posto:** Kit Veterano no 5 (Sergeant), Kit de Elite no 7 (Gunnery Sergeant);
  - **CI:** item a item (150 a 900 CI);
  - **Game Pass em Robux:** o nível inteiro (Elite inclui o Veterano); R$ 149 e R$ 299.
  - Itens EUA: bandoleira M2 (+2 carregadores), 3º cantil (fôlego volta 15% mais rápido),
    estojo de socorro reforçado (+2 curativos, +1 torniquete), colete M1955 (estilhaço no tronco
    −40%, não para bala; 4,5 kg), fumaça M18 extra.
  - Itens VC: peitoral Tipo 56, cantil extra, bolsa de socorro, granada de cabo extra, fumaça
    extra (o VC não usava colete).
  - O jogador escolhe levar ou deixar cada item no painel da Intendência.
- **Renascer onde caiu:** ponto "Onde caiu" na carta de inserção, só para quem caiu na partida.
  - Paga-se o lugar, nunca o tempo: a espera é a mesma de um ponto de reunião, no mínimo 60 s.
  - Bloqueado com inimigo a menos de 100 m, a menos de 250 m do QG inimigo, em área inimiga
    travada, em setor em disputa, na água, fora do mapa, ou depois de 3 usos na partida.
  - Pagamento: renascer guardado (Robux), ou 60/100/160 CI (sobe a cada uso), ou a compra em
    Robux (R$ 25, Developer Product). O recibo sempre vira "renascer guardado" no perfil
    (idempotente): se o renascer ficar impossível na hora, ele espera a próxima queda.
  - As regras são conferidas no servidor antes de cobrar.

**Servidor:** `ProgressionService` (XP, posto, CI, compra e escolha do equipamento, abate e
assistência pelo registro de acertos do `MedicalService`, ganchos de captura e fim de partida do
`MatchService`, recibo do `CommerceService`); `SpawnService` (equipamento ao nascer e o renascer
onde caiu). Perfil v3 (`ProfileSchema`): XP, CI e renasceres guardados gravados como delta da
sessão, que nunca apaga o ganho de outro servidor.

**Studio (2026-11-11):** compra da bandoleira com 300 CI, nascimento com +2 carregadores, aviso
"+10 XP · +2 CI Tempo em campo", ponto "Onde caiu" na carta com a espera certa.
- **Não criados no Roblox:** os 2 Game Passes e o produto. A chave Open Cloud não tem a
  permissão (TODO_USUARIO). Com ID 0, só o botão de Robux some.

## D-74 — Vida no mapa: arrozal, manadas, túneis por dentro e vilas (2026-11-11)
**Pedido do usuário:** "dar vida ao mapa colocando detalhes como os animais q baixamos, as
plantações de arroz q baixamos, os túneis, tudo q falamos em colocar".

**Arrozal** (`Shared/RiceField.luau`, `MapLife.rice`, `RiceField.client.luau`):
- O arrozal ocupa 78% das células do mapa e tem 1.155 tabuleiros d'água. O canteiro do ForgeGUI
  (13 mil triângulos para 2 x 1,45 m) não cobre isso: daria mais de 10 bilhões de triângulos.
- Ladrilho próprio de arroz em cartões (`tools/make_rice.py`):
  - 16 x 16 studs (4,5 m);
  - textura desenhada com as cores do canteiro do ForgeGUI, sem costura;
  - perto: 96 cartões (384 triângulos); longe: 24 cartões (96 triângulos);
  - cartão de duas faces com normal para cima, 74 cm de altura, pé abaixo da água.
- **Servidor:** em cada tabuleiro plantado põe o dossel, uma placa verde na altura do arroz (é o
  que se vê de longe), e publica os 2 ladrilhos em `ReplicatedStorage.VT65RiceArt`.
- **Cliente:** esconde o dossel dos tabuleiros a menos de 65 m e cobre o tabuleiro inteiro de
  ladrilhos.
  - Ladrilho alto até 30 m, baixo até 65 m.
  - Reserva de peças: o ladrilho só muda de lugar, sem criar e destruir.
  - Grade e giro saem da posição do tabuleiro: todos veem o mesmo arroz.
  - Quem está deitado no arrozal fica escondido.
- **Estado de cada tabuleiro** (proporção de projeto, sem fonte): 60% arroz em pé, 25% muda nova
  (55% da altura) e 15% em pousio, só água.
- MeshPart com cor em `TextureID` só recorta pelo alfa com `Transparency` acima de 0. Os
  ladrilhos usam 0,02; com 0 os cartões saíam como triângulos verdes opacos.
- **Studio:** 989 tabuleiros com arroz; 59,6 fps com 1.259 ladrilhos em volta, no meio do setor 4
  (o limite do Studio é 60).
- Os canteiros de muda do ForgeGUI (rice_patch) agora estão nas 5 vilas da carta (eram 3).

**Animais:**
- Búfalo e galinha reduzidos para 4.999 e 3.000 triângulos (eram 14,5 e 16,7 mil) e republicados.
  A redução está no manifest, refeita pelo fetch.
- Galinhas em bando de 3 em 2 de cada 5 quintais; 1 búfalo para cada 5 casas.
- Uma manada no arrozal alagado perto de cada vila, a 50–110 m: 2 búfalos e 1 bezerro.
- **Studio:** 138 animais (eram 79), 4 manadas; uma vila não tem tabuleiro alagado nessa faixa.

**Túneis por dentro** (`MapLife.tunnels`):
- Escora de madeira a cada 4 m (2 esteios e a travessa).
- Lamparina de barro com chama a cada 12 m, em nicho na parede.
- Câmaras mobiliadas fora da boca das galerias:
  - J1: posto de comando e enfermaria (esteiras, mesa baixa com carta, padiola e ataduras);
  - J2: depósito (caixotes e sacos de arroz);
  - J3: cozinha (fogão de barro com brasa, sacos e esteiras).
- Uma lamparina pendurada no meio de cada câmara.
- Ao todo: 44 lamparinas, sem sombra (`Shadows` desligado). A chama treme só perto da câmera.
- **Correção:** a coluna do terreno é toda do material da superfície, e o capim animado nascia
  dentro das galerias. Em volta de cada escavação o capim vira terra (`TerrainBuilder.carve`).

**Vilas** (`MapLife.village`):
- Fumaça de cozinha em toda casa-cozinha e em 22% das outras.
- Pote d'água de barro (chum) ao lado de 55% das casas.
- Meda de palha no terreiro, a 5–9 m de 30% das casas. A bala passa como em telhado de palha.
- Lenha empilhada junto da cozinha.
- Tudo é peça simples, fora do teto de triângulos.
- Pote, meda e lenha entram nas zonas livres da mata.
- **Studio:** 36 fumaças, 21 potes, 7 medas, 32 lenhas.

## D-75 — Teste fase a fase no Studio e o que ele corrigiu (2026-11-11)
**Pedido do usuário:** "teste e corrija cada fase que fizemos, uma a uma, passo a passo".

**O autoteste (`SelfTest`) ganhou 5 verificações:**
- vida no mapa (D-74);
- explosão de morteiro: dano validado no servidor (F4);
- veículos no depósito: no chão, com assento, parados (F4);
- túneis: as 5 entradas com prompt; o VC só nasce no túnel do setor que é dele (F4);
- progressão nos atributos (F6), só leitura: não mexe no perfil.

Resultado final no Studio: **17 ok, 0 falhas, 0 pulados**; nenhum erro de script no log.

**Corrigido pelo teste:**
- **Operador de rádio sem antena** (Parte 11). Depois do `CharacterAdded`, a descrição do corpo
  "Man" (D-70) troca o tronco; a solda ia junto e a antena caía do mapa. Agora a antena é refeita
  a cada tronco novo, com `Weld` de deslocamento fixo.
- **Pá de trincheira recusava no autoteste.** O ponto fixo 60 m a oeste do QG virou arrozal
  alagado quando a lâmina d'água foi para o terreno real (D-73). O teste agora procura chão seco
  perto do QG. Não era defeito do jogo.
- Arroz opaco, capim nos túneis e meda em degraus: corrigidos durante a D-74.

**Fase a fase:**
| Fase | Coberto por | Resultado |
|---|---|---|
| F1 Greybox | autoteste (terreno, arte no chão: 3.770 de 3.772 a até 2 m) | ok |
| F2 Laço | autoteste (bots 14 x 15, raia e balística, explosão), nascimento e espera no Studio | ok |
| F3 Fatia | autoteste (deitado, rádio), agachar no teclado | ok depois da correção da antena |
| F4 Sistemas pesados | autoteste (veículos, túneis, pá, medevac, morteiro) | ok |
| F5 Arte | arte nos 5 setores a 100% do plano; 59,6 fps no arrozal | ok no Studio |
| F6 Offensive | autoteste (Offensive e relatório, progressão) | ok |
| Parte 11 | autoteste (animais, arma caída, chuva, pá, medevac, rádio) | ok |
| Parte 12 Controle | Lune `controle` (19 regras); no Studio, só o teclado | sem controle real |

**Limites:**
- O Studio do MCP não simula controle: o botão injetado chega como teclado.
- Só um jogador: ferimento entre jogadores e 60 jogadores a 60 fps continuam para o teste real.
- Avisos `ContentId ... No asset content representation` e `Wrap-deformer` vêm do corpo e das
  roupas do personagem e dos modelos recém-publicados; não quebram nada.

## D-76 — Garças no arrozal, partida longa e medidas (2026-11-11)
**Pedido do usuário:** "continue melhorando e testando".

**Garças** (`Shared/Egrets.luau`, `Egrets.client.luau`):
- Bandos de 2 a 5 garças nos tabuleiros alagados: 50% dos tabuleiros em pousio e 20% dos de muda
  nova. No arroz alto não há bando, porque ali a garça some.
- Uma garça-vaqueira junto de cada búfalo, andando com ele (a cena clássica da lavoura).
- 2 em cada 5 são garças-brancas-grandes (~0,95 m em pé); as outras são garças-vaqueiras
  (~0,65 m).
- Corpo, pescoço e asas são esferas esticadas. Com placas retas, a garça parada parecia uma caixa
  e a asa recolhida uma barbatana.
- **Susto:**
  - tiro a até 120 m: os dos outros chegam pelo `Combat_Tracer`, o seu pelo `Bus`;
  - explosão a até 300 m.
  - A garça decola escalonada, sobe a 14 m e voa ~130 m para longe do barulho, batendo as asas
    e com as pernas para trás; depois some.
  - O bando volta ao tabuleiro em 1–2 min.
  - Como os búfalos, o voo mostra de onde veio o barulho.
- Só no cliente, 8 peças por garça, sem rede. Aparecem até 150 m da câmera.
- Os números de alcance e voo são de projeto: a garça-vaqueira voa a ~30–40 km/h, e o alcance do
  susto não tem fonte.
- **Studio:** bando no pousio, a explosão a 60 m levantou todos e o voo saiu como previsto.

**Partida longa no Studio** (6 min, 14 x 15 bots):
- os bots se acharam e lutaram: 8 fora de combate;
- servidor a 60 quadros por segundo e memória estável;
- nenhum erro de script.

**Medidas:**
- **Mata mais densa:** célula de 40 m com 70 plantas, câmera girando 360°: 57,1 fps. Sem a sombra
  da folhagem, 58,0. A sombra não é o gargalo e ficou ligada.
- **Altura do soldado:** todos os bots e o jogador medem 1,68 m. O aviso de 1,45 m no início do
  servidor vinha do manequim da prévia, montado fora do Workspace (juntas não resolvidas). Agora
  só se mede no Workspace.
  - O aviso que sobra é verdadeiro: 1,68 m contra a meta de 1,75 m (D-30).
  - Não mudei o `heightScale`: muda postura, câmera e a passagem no túnel de 1,2 m. Decisão
    em aberto.
- **Autoteste da pá intermitente** (falhou 1 vez em 4). O `PivotTo` não zera a velocidade: depois
  de 1 s caindo de 400 studs o soldado chegava ao chão rápido, quicava e a pá cancelava ("você se
  moveu"). Agora o teste zera a velocidade e espera o soldado parar. Era defeito do teste, não do
  jogo.
- **Itens em Robux:** tentei de novo; a chave segue sem a permissão (HTTP 403).

**Autoteste final:** 17 ok, 0 falhas, 0 pulados, também com a câmera seguindo o soldado (a
condição em que a pá tinha falhado).

## D-77 — Animais andando de verdade, granadas, soldado de 1,75 m (2026-11-11)
**Pedidos do usuário:**
- "faça o movimento [dos animais] ser realista e perfeito graficamente e visualmente";
- "granadas com qualidade de movimento de arremesso e gráficos";
- "aumente a altura do personagem para ter melhor visão pois a grama está bem alta".

**Animais** (`tools/rig_animals.py`, `AnimalVisuals.client.luau`, `Shared/Animals`):
- **Antes:** o modelo era uma malha só, empurrada pelo chão a 1 Hz. Andava sem parar e dava saltos
  de 0,4 m por segundo.
- **Modelo em partes:** búfalo e galinha divididos em corpo, cabeça e pernas, e republicados.
  - A divisão é pelo centro de cada triângulo. O lugar de cada perna vem das canelas (os 15% de
    baixo).
  - Pela mediana da faixa baixa, o tufo do rabo puxava o corte e a barriga ia junto com as pernas
    (visto na prévia).
- **Servidor** (`AnimalService`):
  - o búfalo calmo para e pasta 65% das vezes, por 8–22 s, e anda em trechos de 3–9 s a 0,8 m/s;
  - a galinha para e cisca 50% das vezes, por 2–7 s;
  - o andar vai no atributo `Gait` (idle, walk, run), gravado só quando muda;
  - parado, o modelo não se mexe (menos rede).
- **Cliente:** cópia local de cada animal até 250 m; pernas e cabeça animadas até 120 m.
  - Anda suave até a posição do servidor, na velocidade da espécie, sem os saltos de 1 Hz.
  - Vira para onde anda: o búfalo a ~70°/s, a galinha a ~320°/s.
  - O búfalo acompanha a ladeira.
  - **Pernas:** o búfalo anda em quatro tempos (trás-esquerda, frente-esquerda, trás-direita,
    frente-direita) e trota em diagonal fugindo; a galinha alterna as patas.
  - O corpo sobe a cada passo e balança de lado.
  - Parado, o búfalo pasta de cabeça baixa mastigando; a galinha bica de tempos em tempos.
  - Andando, a cabeça acompanha o passo.
  - O modelo do servidor some só neste cliente.
  - Números de animação (passada, amplitude) são de projeto.

**Granadas** (`FieldService`, `WeaponVisuals`, `ExplosionFx.client.luau`):
- **Modelos em peças:**
  - M26 dos EUA: corpo de limão verde-oliva, espoleta e alavanca;
  - granada de cabo do VC: cabeça de ferro e cabo de madeira; gira de ponta no ar;
  - fumaça M18: lata.
- **Física:** a gravidade do Roblox (196,2 studs/s² = 55 m/s²) fazia a granada cair a 3–4 m. Uma
  força para cima deixa 9,81 m/s².
  - 17 m/s de arremesso: ~30 m a 45°, perto do arremesso real.
  - Quica e rola no chão; gira no ar.
  - Espoleta: 4,5 s (EUA) e 4,0 s (VC), PLACEHOLDER.
- **Arremesso em 1ª pessoa** (0,8 s):
  - a arma desce;
  - a mão direita pega a granada no cinto;
  - a esquerda puxa o pino, que cai girando;
  - o braço arma ao lado da cabeça e lança.
  - A granada sai da mão em 0,4 s, junto com a do servidor.
- **Os outros jogadores** veem o braço do ombro direito armar atrás da cabeça e lançar
  (`RightShoulder.C0`).
- **Bots:** `FieldService.throwFrom` calcula o arco de 40° que cai no alvo.
- **Explosão** (antes: só som e cratera):
  - clarão e bola de fogo curta;
  - nuvem de terra marrom que sobe, poeira rasteira, torrões caindo e faíscas;
  - fumaça cinza que fica;
  - na água (arrozal, riacho), coluna de água branca;
  - a câmera treme perto, até ~45 m da granada.
  - O tamanho vem do tipo: granada, foguete, canhão, morteiro, tiro naval, bomba.

**Soldado de 1,75 m:** `heightScale` de 1,2 para 1,25. Com 1,2 todos mediam 1,68 m (D-76). O
túnel de 1,2 m continua pedindo agachar ou deitar, como antes.
- **Studio:** 1,73 m (meta 1,75, dentro da tolerância de 5 cm).

**Granadas, o que o Studio mostrou e foi corrigido:**
- **Atravessava o chão.** Bola menor que ~0,5 stud passa pelo terreno do Roblox: a de 0,25 caiu a
  -166, a de 0,5 afundou 25 studs, a de 1 parou.
  - O servidor agora simula um núcleo invisível de 1 stud.
  - A granada desenhada (`Shared/GrenadeArt`) é posta pelo cliente sobre o núcleo, girando com
    ele, e encosta no chão quando para.
- **Rolava longe:** 6 m/s por mais 10 m depois de cair; a bola do Roblox não tem atrito de
  rolamento. No chão a velocidade cai 28% a cada 0,1 s.
- **Voo medido:** a 38°, sobe 5,7 m e cai a ~32 m.
- **Braço do arremesso:** o corpo "Man" tem juntas `AnimationConstraint`, sem C0. O 1º teste dava
  "Unable to assign property C0" e deixava a marca `Throwing` presa: aquele soldado nunca mais
  arremessava. Agora o giro é no encaixe do ombro do lado do tronco (Attachment0), que vale para
  Motor6D e AnimationConstraint.
- **Explosão:** na água, a 1ª versão virou uma nuvem branca do tamanho de um prédio (agora é uma
  coluna estreita, de 3–5 m para granada). Em terra, a textura `explosion01_smoke` do Roblox é
  quase preta e a nuvem saía uma bola escura (agora é poeira marrom clara).

**Bots de nível médio** (pedido: "bots de nível médio que se adaptam ao ambiente";
`Shared/BotBrain`, `BotService`, `tests/luau/bots.luau` com 24 testes):
- **Uma tabela de dificuldade** (`BotBrain.DIFFICULTY.medium`):
  - reação de 0,4–0,8 s;
  - erro de mira de 2,2 mrad que dobra a cada 500 m e piora andando, sob supressão ou ferido;
  - rajadas curtas: fuzil 2–3 tiros, metralhadora 4–8;
  - coice que soma erro na rajada.
  - Pela conta, acerta o tronco em 92% a 50 m, 43% a 100 m e 10% a 200 m.
- **Abrigo:** ao avistar o inimigo ou com bala passando perto, 8 raios até 15 m acham dique,
  sebe, moita, capim, tronco, parede, sacos, trincheira, bunker e barranco. O bot vai para o lado
  protegido.
- **Postura conforme o lugar:**
  - em pé atrás de parede e tronco;
  - agachado atrás de sebe, sacos e dique;
  - deitado no arrozal e no capim quando preso pelo fogo.
- **Supressão** (0 a 1, cai em ~4 s): acima de 0,45 o bot não levanta a cabeça.
- **Combate do abrigo:** espia, dá a rajada, volta; troca de abrigo depois de 2–4 rajadas. Ferido
  (vida abaixo de 55) recua.
- **Granada:** no inimigo a 15–35 m fora da visada, no máximo 2 por vida, nunca com companheiro
  perto. Usa `FieldService.throwFrom`.
- **Lados:** o VC espera escondido mais tempo e segura o fogo até 80 m; os EUA avançam mais.
- **Custo:** cada bot pensa a cada 0,3 s, com orçamento de raios (no máximo ~360/s para 30 bots).
- **Studio:** antes os 29 bots lutavam em pé. Agora, em combate, chegaram a 6 agachados e 4
  deitados ao mesmo tempo.
- O `BotService.start()` envolve `CombatService.fire` para os bots sentirem a bala passando
  (dentro de `pcall`; o tiro sai antes).

**Pop-ups** (pedido: "melhore a qualidade visual dos pop ups"; `Controllers/Toast.luau`):
- **Um sistema só** para todos os avisos curtos. Cartão oliva escuro com filete cáqui, barra
  lateral e selo na cor do tipo:
  - info: azul-aço;
  - confirmado: verde;
  - recompensa: latão;
  - atenção: âmbar;
  - erro: vermelho de carimbo.
- Título em Oswald (o do lobby) e barra de tempo.
- No máximo 4, numa faixa abaixo do topo, longe da mira; entram deslizando.
- **Recompensa:** chips "+10 XP" e "+2 CI"; o mesmo motivo soma no aviso aberto.
- **Promoção:** ficha de papel com carimbo "SOLDO".
- **Tutorial:** saiu do meio da tela (tapava a mira). Agora é um cartão compacto no canto de baixo
  à esquerda, com "1/9", barra de progresso e a tecla ou o botão do controle num chip.
- Só no Studio: `workspace:SetAttribute("VT65DevToast", "todos")` mostra os tipos.

## D-78 — Pente-fino fase a fase com tudo junto (2026-11-11)
**Pedido do usuário:** "corrija erros de todas as fases, uma por uma, passo a passo".

O place com tudo da D-77 rodou no Studio:
- duas partidas de ~9 min com 29 bots;
- o caminho real do jogador pela rede;
- o autoteste.

| Fase | O que foi testado | Resultado |
|---|---|---|
| F1 Mapa | terreno em 10 s, arte no chão (3.770 de 3.772), vida no mapa | ok |
| F2 Laço | escolher time, squad e papel, esperar e nascer, atirar e recarregar (`Combat_Fire`, `Combat_Reload`), bots lutando | ok |
| F3 Soldado | deitado, rádio, altura de 1,73 m, marcação, mensagem e postura pela rede | ok |
| F4 Pesados | M48 dirigido no W (12,7 m em 4 s, para ao soltar), veículos, túneis, pá, medevac, morteiro, granada | **1 erro corrigido** |
| F5 Arte | sem erro de script com animais, garças, arroz e explosões | ok |
| F6 Lançamento | Offensive e relatório, recompensa diária, progressão, loja (`Daily_Get`, `Progress_Get`, `Commerce_GetState`) | ok |
| Parte 11 | animais fugindo da granada, garças, chuva, arma caída, pá, medevac | ok |
| Parte 12 | regras no Lune (19); no Studio o botão do controle chega como teclado | sem controle real |

**Erro achado e corrigido:** o braço do arremesso (D-77) tentava mudar o C0 de uma junta
`AnimationConstraint`. Cada arremesso dava erro e deixava o soldado marcado como "arremessando"
para sempre. Ver D-77.

**Não é defeito do jogo:**
- **Câmera presa no QG nos testes:** o assistente do Studio reverte a troca de câmera feita pelo
  `execute_luau`.
- **Morte nos testes:** uma das mortes foi a própria granada de teste, jogada com a câmera olhando
  para o chão.
- **Avisos `StyleRule ... RoundedCorner8`:** vêm da interface interna do Roblox.

**Autoteste com tudo junto:** 17 ok, 0 falhas, 0 pulados. Log das sessões: 0 erros de script.

## D-79 — Blender na linha de produção; animais com esqueleto e pele (2026-11-11)
**Pedido do usuário:**
- fazer os assets no Blender (os novos e os antigos refeitos) e comparar: mais bonito, mais
  gráfico, mais funcional, menos pesado;
- tudo realista; animações ultra realistas;
- telas mais fluidas;
- resolver o que faltava e seguir para a próxima fase.

**Blender 5.3** roda sem janela pelo Python (`blender -b --factory-startup -P script.py -- args`),
com importador e exportador glTF/FBX, BVH e Cycles. Os scripts ficam em `tools/` e rodam de novo
do zero.

**Animais com esqueleto e pele** (`tools/animais/esqueleto.py`, `tools/animais/previa_pose.py`):
- Na D-77 o animal era peças que giram nas juntas: dá passo, mas a perna gira dura e abre fresta.
- Agora é uma malha só presa a um esqueleto:
  - búfalo: 16 ossos (raiz, quadril, coluna, peito, pescoço, cabeça, rabo em 2, coxa e canela
    nas 4 pernas);
  - galinha: 9 ossos.
- **Pesos:** o "heat" automático do Blender falha em malha de gerador. O peso vem da distância
  aos ossos da região de cada vértice (perna, corpo, pescoço, rabo), com mistura nas juntas.
- **Prévia no Blender:** passada e cabeça baixa com a pele contínua, sem fresta.
- **Roblox:** importou uma MeshPart com os 16 ossos (`Bone`).
- **No cliente** (`AnimalVisuals`), cada osso gira no eixo lateral do animal, calculado no
  repouso:
  - a canela dobra só no balanço (o casco sobe e vai para trás);
  - a coluna verga a cada passo e respira parada;
  - a cabeça pasta;
  - o rabo espanta mosca.
- O modelo em peças (D-77) fica de reserva se o com esqueleto não carregar.

**Granada de bot:** nova verificação no autoteste. Um bot de verdade arremessa num alvo a 25 m:
- o braço gira;
- a granada caiu a 3,2 m do alvo (com quique e rolagem);
- ela é desarmada antes de explodir.

Autoteste: 18 ok.
Os bots não jogaram granada nas duas partidas: os encontros foram a mais de 35 m (a regra pede
15–35 m fora da visada).

## D-80 — Vento, poeira e folhas; tutorial estável no controle (2026-11-11)
**Pedido do usuário:**
- "coloque poeira, vento etc.";
- "as vilas devem fazer parte do ambiente de guerra";
- "o tutorial, quando está no controle, deve aparecer os botões do controle".

**Ambiente** (`Ambiente.client`, tudo local e barato):
- **Vento:** brisa do mar vindo do leste (a costa fica a leste), 3 m/s com rajadas até ~7 m/s
  (PLACEHOLDER), e o dobro na chuva. Vai em `workspace.GlobalWind`, que já mexe o capim do
  terreno, a fumaça e as partículas.
- **Arroz** (`RiceField.client`): os ladrilhos de perto balançam a 15 Hz, girando no pé para longe
  do vento, numa onda que corre pelo campo na direção da rajada.
- **Poeira no ar:** cisco claro em volta da câmera, só de dia e sem chuva.
- **Folhas caindo** quando a câmera está debaixo da copa da mata (raio para cima, 1 vez por
  segundo); mais na chuva.
- **Fumaça de guerra no horizonte:** 5 colunas escuras fora do mapa de 2 x 2 km, inclinadas pelo
  vento (vilas e plantações queimando; a área foi bombardeada antes do desembarque).

**Tutorial no controle:** o tutorial já trocava a tecla pelo botão do controle, mas piscava. Causa:
o mouse parado gera eventos de movimento mínimo e o jogo voltava para "teclado". Agora:
- controle → teclado só com tecla, clique ou mouse andando mais de 40 px em 0,5 s;
- teclado → controle em qualquer entrada do controle, na hora.

## D-81 — O tiro sai exatamente no centro da mira (2026-11-11)
**Pedido do usuário:** "a bala tem que sair exatamente no centro da mira, em cima do risquinho";
em terceira pessoa também.

**Primeira pessoa:**
- A bala já saía do centro da câmera, e o balanço e o recuo giram a própria câmera, então o ponto
  de impacto andava junto com a mira.
- O defeito era só visual: o coice do modelo da arma girava a arma para cima. Com a arma apontada,
  a massa de mira saía do ponto onde a bala ia.
- Agora o giro do coice é proporcional a (1 − mirando): apontando, o coice só empurra a arma para
  trás e a massa fica sobre o ponto de impacto; no quadril o coice gira como antes.

**Terceira pessoa:**
- A bala sai do olho do soldado para o ponto da mira (câmera por cima do ombro), com a dispersão
  do quadril.
- A retícula fecha quando aponta.
- Se uma parede ou o terreno estão entre o soldado e o ponto da mira (raio do olho até o alvo, 10
  vezes por segundo), os riscos da retícula ficam vermelhos: o tiro vai bater no obstáculo, não no
  ponto mirado.

## D-82 — Opções: gráficos, mouse e teclado, cursor virtual (2026-11-11)
**Pedido do usuário:** "coloque opções no jogo para ajeitar os gráficos, a sensibilidade, os
botões, poder trocar os botões"; "pode colocar o mouse no controle sendo analógico, com uma
sensibilidade normal".

O menu do jogo (segurar View / P) já tinha controle, mira no analógico, vibração, acessibilidade
e troca de botões do controle (Parte 12.8). Entraram duas sub-abas e uma opção:

**Mouse/teclado:**
- Sensibilidade do mouse (0,1–3, padrão 1), que multiplica a do Roblox.
- Frações ao apontar (padrão 0,7) e na luneta ou no binóculo (padrão 0,45). Valores de projeto
  (PLACEHOLDER).
- Troca de tecla de cada ação (infantaria, mirando, geral, veículo, helicóptero, mapa): a próxima
  tecla ou botão do mouse vira a tecla da ação.
  - Backspace cancela.
  - Recusadas: Esc, W/A/S/D, Tab, /, F9, F11, F12 (são do Roblox ou do movimento).
  - Conflito no mesmo contexto é recusado, com a mesma regra dos botões do controle.
  - As teclas do menu e da roda não se trocam: o jogador não pode se trancar fora do menu.

**Gráficos** (no cliente de quem escolheu, salvo na conta):

| Opção | Valores | O que faz |
|---|---|---|
| Detalhe | alto / médio / baixo | arroz em cartões até 65 / 45 / 29 m, o alto até 30 / 18 / 10 m; poeira, folhas e fumaça a 100 / 60 / 30 %; no baixo o arroz não balança e a poeira some |
| Sombras do sol | ligadas / desligadas | a que mais pesa em máquina fraca |
| Efeitos de tela | completos / leves / desligados | o leve tira o bloom (o mais caro) e mantém raios de sol e correção de cor |
| Brilho | −0,2 a +0,2 | exposição de −1 a +1 EV em volta da do jogo |

A qualidade gráfica geral continua no menu do Roblox.

**Cursor virtual** (sub-aba Controle, desligado no padrão):
- No menu do jogo entra o mesmo cursor do lobby (`VirtualCursor`):
  - o analógico esquerdo move, com ímã leve sobre os botões;
  - o A clica;
  - o direcional pula entre os botões;
  - o analógico direito rola a lista.
- Desligado, o menu segue pela seleção do Roblox (direcional, LB/RB).
- O lobby já usa o cursor sempre. O mapa tem cursor próprio.

## D-83 — Telas fluidas: carregamento, mesa, escolha e chegada ao campo (2026-11-11)
**Pedido do usuário:** "melhore a qualidade gráfica das animações e das telas de escolha,
carregamento etc.; mais fluido e com qualidade gráfica melhor".

Módulo novo `ReplicatedFirst/Acabamento` (grão de filme, vinheta, papel, carimbo, máquina de
escrever), usado por todas as telas.

**Carregamento** (`LoadingScreen`):
- Cartão de briefing datilografado com fatos da operação.
- Carta com os eixos a lápis que se desenham.
- Carimbo SECRET.
- A barra nunca volta.
- Saída em fade sobre o lobby, sem tela preta.

**Mesa do lobby** (`LobbyScene`):
- A câmera chega devagar enquanto a tela de entrada some e anda entre os objetos sem tranco.
- A troca de cena passa por um escuro quente.
- Contorno e etiqueta entram animados; vinheta e grão leves.

**Escolha de lado, squad, papel, diária e inserção** (`DeployScreen`):
- A pasta que sai esmaece enquanto a nova entra.
- Os cartões entram um a um e os carimbos "caem".
- Realce animado no mouse, no foco do Roblox e no cursor virtual.
- Dicas de botão em chip: imagem do botão do controle ou tecla em relevo.
- A ficha do papel mostra as armas que mudam (►) e barras de velocidade inicial, cadência,
  carregador e peso, comparadas com o papel atual.

**Chegada ao campo** (`SpawnTransition`):
- Ordem datilografada com a carta.
- Eixo vermelho do QG até o ponto.
- Carimbo "EM CAMPO" ou "RECUSADA".
- A câmera desce do alto até o soldado em ~1,3 s; qualquer botão pula a descida.

Só no Studio: `workspace:SetAttribute("VT65DevTela", ...)` com `"carregamento"`, `"escolha"`,
`"lado"`, `"squad"`, `"papel"`, `"diaria"`, `"insercao"` ou `"transicao"`.

**Defeito achado no Studio e corrigido:**
- Com as telas novas, o `DeployScreen` ficou com 251 variáveis locais no nível de cima. O limite do
  Luau é 200, e o lobby não abria ("Out of local registers").
- O luau-lsp não acusa esse limite. Agora o `tests/luau/run.luau` compila todo o `src/` com o
  compilador do Luau e acusa.

## D-84 — Idiomas: português, inglês, espanhol e vietnamita (2026-11-11)
**Pedido do usuário:** "faça o jogo no mínimo em 3 línguas: inglês, português, espanhol e outras".

**Como funciona:** o jogo continua escrito em português. A tradução acontece no texto que vai para
a tela (`Controllers/Traducao.client`), sem mexer em cada tela:
- rótulos e botões do PlayerGui e as folhas 3D do lobby;
- o português de cada rótulo fica guardado, e trocar o idioma retraduz o que está aberto;
- caixas de texto (o que o jogador digita) nunca são traduzidas.

**Dicionários:** `Shared/LangData/{en,es,vi}.json` (português → tradução). `Shared/Lang` procura, nesta
ordem:
1. a frase exata;
2. a mesma em caixa alta (a tela usa `UiKit.upper`);
3. modelos com `%d`, `%s`, `%.1f` e o `{a}` do tutorial; o que entra no `%s` também é traduzido;
4. "Rótulo: valor";
5. linha a linha;
6. RichText: o nome vietnamita marcado na fonte Arimo volta marcado.

Sem tradução, fica o português.

**Textos:** `tools/i18n/extrai.py` junta os textos de tela do código (~1.670) e mede quanto de cada
idioma está traduzido. Texto novo entra rodando o extrator e traduzindo o que falta.

**Idioma:**
- Opção "Idioma / Language" no menu (sub-aba Acessib.).
- No padrão, "automático" usa o idioma da conta Roblox. Idioma sem dicionário cai no inglês.

**Cobertura completa** (2026-11-11, depois do pedido "o jogo completamente na língua que foi
selecionada"):
- **Dicionários:** cobrem 100% dos textos de tela nos três idiomas (`tools/i18n/telas.json`;
  identificadores e nomes próprios ficam em `tools/i18n/ignorar.json`). O teste `idiomas` cobra a
  cobertura.
- **Mensagens do servidor e telas:** saem como frase inteira (`string.format`), sem pedaços colados.
- **O `Traducao.client` também cobre:**
  - ProximityPrompt (ActionText e ObjectText), que o próprio Roblox desenha;
  - placas e folhas em SurfaceGui e BillboardGui no workspace, numa leitura única em fatias mais o
    DescendantAdded;
  - o PlaceholderText das caixas de texto.
- **Vietnamita:** o texto com letras vietnamitas troca a fonte de época pela Arimo.
- **Ainda em português:** mensagens do chat do sistema do Roblox (o próprio Roblox traduz pela conta).

## D-85 — Skins de arma, de uniforme e camuflagem de mato (2026-11-11)
**Pedido do usuário:**
- skins de arma e de personagem, compráveis com o dinheiro do jogo e com Robux;
- muito mais caras no dinheiro do jogo e proporcionalmente mais baratas em Robux;
- camuflagem "como se fosse parte do mato, com várias folhas que sobrepõem o personagem";
- "pode fazer virar vantagem comprada";
- dinheiro do jogo com o símbolo "$".

**Dinheiro:** `Progression.CUR` passou de "CI" para "$" e `Progression.money(n)` dá "$ 1.250".

**Preços** (PLACEHOLDER): o preço em $ parte de ~$ 300 por partida de Warfare (75 min). O Robux é
~1,6 R$ por partida equivalente, na mesma proporção entre os itens.

| Grupo | Partidas | $ | R$ (sugestão) |
|---|---|---|---|
| Skin de arma comum (madeira, aço gasto) | 25 | 7.500 | 39 |
| Skin de arma rara (verde-oliva, fita, aço azulado) | 35 | 10.500 | 55 |
| Uniforme (OG-107 desbotado, tiger stripe, duck hunter; pijama preto do VC) | 50 | 15.000 | 79 |
| Camuflagem de mato (arrozal, selva, bambu) | 100 | 30.000 | 159 |

Skin de arma é Developer Product; uniforme e camuflagem são Game Pass. Com ID 0, o botão de Robux
não aparece.

**Camuflagem de mato** (`tools/ghillie.py`):
- Touceiras de folhas (1.900 triângulos) soldadas em cada parte do corpo, com o rosto livre.
- Balançam ao vento no cliente, até 70 m.
- É **vantagem comprada**, por decisão do dono: na vegetação do mesmo tipo, o bot enxerga a 60% da
  distância; deitado, a ~23% (PLACEHOLDER, `BotBrain`).
- Contra jogadores, a vantagem é só visual.

**Onde vale:** uniforme e camuflagem no próximo spawn; a skin de arma troca na hora.

**Itens de Robux criados** (2026-11-11, depois que o dono liberou `game-pass:write` e
`developer-product:write` na chave):
- **Skins:** 17 Developer Products e 7 Game Passes (`tools/roblox_cloud.py create-skins`, catálogo
  exportado por `tools/skins_loja.luau`, ícones gerados), com IDs em `Skins.IDS`.
- **Loja:** os 6 Game Passes (uniformes USMC e VC, Passe de Unidade, Apoiador, Kit Veterano, Kit de
  Elite) e os 3 Developer Products (duas gorjetas e "Renascer onde caiu"), com IDs em `Commerce.IDS`.

**Falta:** refazer as armas no Blender com as peças `Madeira`, `GuardaMao` e `Metal`. Hoje cada arma é
uma malha só, e a skin de arma só aparece na arma provisória.

## D-86 — Veículos com movimento realista (2026-11-11)
**Pedido do usuário:** "faça a movimentação dos veículos realista e visualmente agradável, com bons
gráficos".

A lógica pura fica em `Shared/VehicleDrive` (testada no Lune, `tests/luau/veiculos`), o servidor em
`VehicleService` e o motorista em `VehicleController`. Os efeitos ficam em `VehicleFx.client` e
`VehicleLive`.

**Lagarta** (M48A3, Ontos, LVTP-5):
- O motor demora a encher; duas marchas, com queda de rotação audível na troca.
- Freio forte e freio-motor brando; a ré funciona como num carro.
- Gira no lugar e faz curva aberta em movimento, que gasta velocidade.
- Na ladeira sobe mais devagar; escorrega na lama íngreme.
- Patina, afunda e derrapa na lama e no arrozal.
- Para contra parede ou barranco em vez de empurrar.
- Sobe dique de até 0,6 m.

**Por veículo:**
- M48A3: passa riacho de até 1,2 m.
- Ontos: mais leve, gira 40°/s no lugar.
- LVTP-5: boia e chega a 11 km/h na água (ficha); deriva de lado e desliza antes de parar.
- UH-34D:
  - o rotor leva 9 s para pegar rotação;
  - atitude e subida têm inércia;
  - perto do chão, a descida é amortecida até 1,2 m/s no toque (ajuda de pouso de projeto);
  - em velocidade, o nariz acompanha a curva.

**Números medidos no teste:**

| Medida | Valor |
|---|---|
| M48 de 0 a 10 / 0 a 30 km/h na estrada | 2,4 s / 12,7 s |
| Máxima do M48: estrada, terra, capim, mata, areia, lama, arrozal | 48, 36, 31, 24, 19, 16, 13 km/h |
| Freada no capim a 31 km/h | 2,2 s |
| Ré | 12 km/h |
| Giro no lugar: M48 / Ontos | 20 / 40°/s |

Os tetos fora de estrada, as marchas, o giro, o freio, as molas, o calado e o escapamento são
PLACEHOLDER.

**Visual e som:**
- **Carroceria:** levanta o nariz na arrancada, mergulha na freada e rola na curva. Acompanha o chão
  pelas 4 pontas e treme com o motor.
- **Lagartas:** faixas correm no laço, cada lado na sua velocidade.
- **Rotores:** disco de desfoque e pás girando.
- **Partículas, levadas pelo vento, só perto da câmera e reduzidas pela opção de detalhe:**
  - poeira, capim e folhas;
  - barro, respingo do arrozal, esteira e espuma na água;
  - escapamento que engrossa na aceleração;
  - downwash do helicóptero.
- **Motor:** tom e volume pela rotação e pela carga, ouvidos pelos outros jogadores. O laço antigo
  do `AudioController` saiu.
- **Câmera e controle:** a câmera balança com a carroceria e treme com o chão. No analógico, a
  direção é mais fina perto do centro; o motor pequeno de vibração sente o chão.

Só no Studio: `workspace:SetAttribute("VT65DevDrive", "m48a3")` (também `"ontos"`, `"lvtp5"`,
`"uh34d"` e `"sair"`) põe o jogador no assento do motorista.

**Vista sentado** (teste no Studio):
- **Problema:** com o olho na cabeça do personagem, dentro da malha, que só tem faces externas, o
  casco sumia e o fuzil continuava na mão.
- **Agora cada assento tem um olho fora da malha:**
  - motorista com a cabeça fora da escotilha;
  - atirador no periscópio, com moldura de ótica;
  - comandante fora da cúpula;
  - tropa do LVTP-5 sentada no teto, como os fuzileiros andavam no Vietnã por causa das minas;
  - pilotos na cabine alta do UH-34D;
  - atirador debruçado na porta.
- **Arma de 1ª pessoa:** é a do assento. O motorista não tem nenhuma; as portas e as cúpulas têm a
  M60.
- **Corpo:** o do próprio personagem some sentado.
- **3ª pessoa:** câmera de perseguição atrás do veículo.
- **Ajuste à vista no Studio:** o olho do motorista do M48 recuou para cima do convés (em x = −7
  ficava na quina da frente e o casco não aparecia). Agora a frente do casco aparece embaixo e o tubo
  do canhão em cima.

## D-88 — Animações do soldado por captura de movimento (2026-11-11)
**Pedido do usuário:** "as animações ultra realistas".

**Fonte:**
- Captura de movimento da CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), com licença
  livre para qualquer uso, sem revender os dados.
- Crédito pedido: "mocap.cs.cmu.edu / NSF EIA-0196217" (está na descrição dos assets; pôr também nos
  créditos do jogo).
- Os sujeitos 141 e 143 estão a 60 quadros por segundo, não a 120 como diz o site (a pelve cairia a
  −44 m/s²).

**Clipes** (`tools/anim`: retarget para o R15 em Python/Blender, `.rbxm` gravado no Lune; enviados
pelo Open Cloud):

| Clipe | Fonte | Velocidade natural |
|---|---|---|
| parado | 77_02 | — |
| andar | 35_01 | 1,08 m/s (×1,30 no jogo) |
| trote | 35_17 | 2,66 m/s |
| correr | 127_06 | 3,90 m/s (×1,41 a 5,5 m/s) |
| agachado | pose montada sobre a 77_02 | — |
| agachado andando | 136_09 | 0,76 m/s |
| deitado | 77_16 | — |
| rastejar | procedural sobre a 77_16 | 0,35 m/s |
| recarregar | procedural (tronco e braços) | — |
| granada | 143_22 espelhada | sai em 0,4 s |

**Qualidade medida:**
- os laços fecham sem emenda;
- o pé escorrega no máximo 0,01 cm;
- as mãos ficam na pega do fuzil;
- no jogo (`SoldierAnimations.client`) a passada mistura andar, trote e correr pela velocidade.

**No Studio:** a animação de andar carregou (69 quadros, todas as juntas do R15) e tocou com o
soldado andando a 1,36 m/s.

**Ajustes:**
- **Fuzil deitado:** a pega nova foi medida na pose (`PostureController.HOLD_PRONE`); com a antiga, o
  fuzil ficava acima das costas.

**Falta:**
- **Câmera agachado:** fica ~30 cm abaixo da cabeça da animação. Sugestão: `DROP.crouch` de 2,2 para
  ~1,0 stud e regravar os dois clipes agachados.
- **Bots:** ainda deslizam sem animação. `SoldierAnims.BOTS = true` anima os bots perto de cada
  cliente; falta medir o custo com 58 bots.

## D-89 — Correr sem gastar fôlego (2026-11-11)
**Pedido do usuário:** "permita correr sem perder a stamina".

**Regra nova** (`Movement.SPRINT_FREE = true`):
- Correndo, o fôlego segue a regra do trote, mas nunca cai: nem com peso, no arrozal ou na subida.
  O que o pulo, a transposição e o mergulho gastaram volta devagar.
- O servidor não corta mais a corrida pelo orçamento de fôlego.
- O fôlego continua mexendo no balanço da mira e na altura do pulo.

O modelo antigo (24 s de corrida até zerar) fica atrás da chave e continua testado no Lune.

## D-90 — Interfaces de época, caveira de abate, pular o tutorial e idioma na entrada (2026-11-11)
**Pedido do usuário:**
- "melhore ainda mais todas as interfaces do jogo";
- "faça uma caveira bem feita quando você mata alguém";
- "dê a opção de pular o tutorial";
- "faça o jogo completamente na língua que foi selecionada".

**Caveira de abate** (`Caveira.client`):
- Aparece no centro quando chega o crédito de abate (aviso "Abate" do `Progress_State`; também
  com o teto de XP do minuto).
- Entra como carimbo, um anel de tinta abre e ela some em ~1,2 s.
- 11% da altura da tela, translúcida para não tapar a mira; sem número e sem som.
- Arte: estêncil de spray de 1024 px (`tools/make_caveira.py`), enviada (`Images.caveira_abate`); o
  servidor converte o decal em imagem (`ImagensUi`).

**Pular o tutorial** (`TutorialController`), com confirmação para não pular sem querer:
- **Teclado:** segurar Backspace 1 s.
- **Toque e mouse:** tocar duas vezes.
- **Controle:** os 15 botões já têm ação na infantaria, e um a mais quebraria a regra de conflito.
  Então segurar View abre o menu já com "Pular" focado; lá, segura-se Y ou aperta-se A duas vezes.

**Idioma na entrada:**
- Chip "IDIOMA · LANGUAGE" na tela de carregamento e no lobby (Y no controle).
- O cartão traz as 5 opções, cada uma escrita no próprio idioma.
- Uma conta nova com idioma automático vê o cartão uma vez.

**Telas novas ou refeitas:**
- **HUD de campo** (`HudCampo`, novo):
  - bússola com o objetivo marcado;
  - cartão da arma e da postura, com carregadores desenhados como pentes, sem contar balas (Parte
    1), que esmaece depois de 5 s.
- **Menu do jogo:** dossiê com abas de arquivo e valores ajustados com ◄ ►; mantém o foco e a rolagem
  ao redesenhar.
- **Relatório pós-ação:** folha datilografada com seções e carimbo. Só abre depois da ficha de fim.
- **Loja:** formulário de requisição; não cobre mais a Intendência.
- **Roda:** mostrador oliva com ponteiro de latão.
- **Controle desconectado:** ficha com carimbo PAUSADO.
- **Painel de veículo** (`VehicleHudView`): de época, no lugar do texto em fonte de código.
- **Escala:** faixa de setores, ficha de fim, telas de ferido e de baixa e avisos encolhem em janela
  estreita.
- **Tradução:** todo texto composto virou `string.format` com o modelo inteiro em português, para a
  tradução casar (D-84). As folhas do lobby estão em português e são traduzidas pelo dicionário.

Ganchos só no Studio: `workspace:SetAttribute("VT65DevTela", X)` com X igual a `caveira`,
`caveira_desenho`, `menu`, `loja`, `relatorio`, `controle`, `roda`, `idioma`, `hud`, `tutorial`,
`veiculo` ou `helicoptero`.

**Falta:**
- o som do UH-34D (`uh34d_loop` em 0) e o chocalho da lagarta;
- separar as pás do UH-34D no Blender: a malha publicada tem pás paradas.

## D-87 — Modo de jogo com ritmo e clareza; carta de verdade; tela de baixa (2026-11-11)
**Pedido do usuário:** "melhorar o modo de jogo, além da tela de morte, mapa do jogo"; "o mapa que
você abre no jogo está simplório, faça um mapa de verdade".

**Problemas vistos no Studio (D-78):**
- o primeiro contato demorava ~5 min;
- os bots lutavam espalhados;
- não ficava claro o que estava em disputa.

**Regras novas** (PLACEHOLDER, `Shared/Capture`, `Shared/Front`, `FrontService`):
- **Atrito no Warfare:**
  - 300 reforços por lado, menos 1 por morte (medevac não conta);
  - quem tem mais setores sangra o outro em 3 por minuto por setor de vantagem; reforço zerado
    perde;
  - no fim do tempo, empate em setores vai para quem tem mais reforços.
- **Sorteio dos pontos fortes:** continua um por setor (D-08/D-63), mas agora em cadeia, com peso
  1/d², a partir do S3 (Warfare) ou do S5 (Offensive). A distância média de S2 e S4 até o S3 caiu de
  1.414 para 1.165 m.
- **Reunião avançada:** a 250 m ou mais do ponto atacado, 30 m para dentro do setor próprio. Marcha
  até o S3 de 240 s para 92 s em média; pior caso de 398 s para 119 s.
- **Reunião do squad:**
  - só o líder planta (Y na carta, R no teclado), uma por squad, a cada 90 s;
  - precisa de ≥ 100 m de inimigo, ≥ 150 m de ponto forte ativo do outro lado e ≥ 300 m do QG
    inimigo;
  - some com inimigo a menos de 15 m.

**Faixa no alto** (`FrontHud`):
- os 5 setores com dono, quem está tomando e o progresso;
- reforços, ou a frente no Offensive;
- o objetivo, com rumo e distância.

Avisos pelo `Toast`: sob ataque, em disputa, tomado, perdido, reforços em 25% e 5 minutos.

**Fim de partida:** ficha com carimbo VITÓRIA, DERROTA ou EMPATE, o motivo e o placar (setores,
reforços, baixas, duração), por cima do relatório.

**Carta de verdade** (`tools/carta_dados.luau` + `tools/make_carta.py`; `CartaView`):
- Gerada dos mesmos dados do terreno, no estilo das cartas L7014 de 1965:
  - relevo sombreado e curvas de 5 m com cota;
  - mata, bosque de vila e sebe de bambu;
  - arrozal com lâminas e diques, casas, riacho e trincheira;
  - grade BS de 1 km com números;
  - nomes vietnamitas, rosa dos ventos e escala.
- Imagem de 2048 px em 4 blocos (enviados, `AssetIds.Carta`).
- **Na carta do jogo:**
  - setores por dono e linha de contato;
  - objetivos com anel de 50 m, progresso e o carimbo ATACAR ou DEFENDER;
  - pontos de inserção, o squad e as marcações a lápis;
  - você com a seta do rumo, legenda e resumo.
- **Controle:**
  - analógico esquerdo: cursor com ímã;
  - direito: arrastar;
  - gatilhos: zoom;
  - L3: você;
  - R3: a carta inteira.
- Nunca mostra inimigo (Parte 9.5).
- As trilhas são traçado de design e não existem no chão.

**Tela de baixa** (`CasualtyScreen`), sem killcam e sem o nome do atirador, como no Hell Let Loose:
- **Caído:**
  - a visão escurece e pulsa no ritmo do coração (110–150 bpm, de projeto);
  - contagem da janela de 60 s;
  - "Segure B para desistir", com anel enchendo;
  - aviso de médico a até 80 m.
- **Morto:** "Relatório de baixa" datilografado, com:
  - carimbo;
  - a causa só com o que o soldado perceberia ("Abatido por fuzil, ~120 m a nordeste");
  - a grade, a hora em data-hora de 1965 e o tempo em campo.
  Depois desce para a carta de inserção.

**Teste no Studio:** carta, caído, morto e fim de partida aparecem sem erro de script. Ajustes:
- o carimbo saiu de cima da causa;
- o motivo saiu de baixo do carimbo;
- o tutorial some quando caído ou morto.

Ganchos só no Studio:
- `VT65DevCarta`: "abrir", "zoom", "fechar";
- `VT65DevQueda`: "caido", "morto", "fim";
- `VT65DevEnd`: true.

**Falta:** o relatório pós-ação antigo (cinza, sem acentos) aparece por trás da ficha de fim e ainda
não tem o estilo novo.

## D-91 — Espera de 10 s, som mais baixo, música no menu e 50 x 50 jogadores (2026-11-11)

O dono jogou a v35 publicada e reclamou da espera, do barulho e de não conseguir nascer no VC.

**Espera para nascer** (`SpawnRules.C`, `Progression.INPLACE`):
- Causa do "não consigo nascer no VC": todo ponto mostrava cerca de 75 s de espera (60 s de mínimo
  mais a onda de 20 s). O jogador clicava e nada acontecia.
- Agora (todos de projeto, PLACEHOLDER):
  - mínimo de **10 s** depois da queda (era 60);
  - ondas de 5 s (eram 20);
  - reunião capturada +5 s;
  - guarnição +8 s;
  - passo de sequência 4 s, até 12 s;
  - troca de papel 4 s;
  - renascer onde caiu: mínimo de 10 s.

**Som** (`AudioController`):
- Três SoundGroups no SoundService:
  - `VT65Efeitos`: 0,5;
  - `VT65Ambiente`: 0,6;
  - `VT65Musica`: 0,35.
- Todo som solto no mundo sem grupo entra em Efeitos.
- **Fora do campo** (menu, lobby, morto):
  - o ambiente se cala;
  - toca a música do menu, baixa: "Ancient Grounds underscore", da APM Music, biblioteca
    licenciada pela Roblox.
- O ambiente do arrozal tocava no menu porque a zona era calculada pela câmera do lobby, que fica no
  mundo. **No campo**, o ambiente fica em 0,2 e a música some.
- **Passos:**
  - só os 4 soldados mais próximos fazem som;
  - volume mais baixo: deitado 0,1, agachado 0,16, andando 0,35, correndo 0,5;
  - passo na água em 55%. Era a água "repetindo" com 30 soldados no arrozal.

**Jogadores:** o dono pediu 60 x 60, mas o servidor do Roblox aceita até 100 jogadores (200 e 700
só num programa fechado). Ficou:
- 50 por lado (`Roles.TEAM_MAX`);
- máximo do place em 100 no Creator Hub, em Access;
- EUA com 7 squads (Alfa a Golf), VC com 8 tiểu đội;
- os bots continuam preenchendo até `BotFill` (10 no Roblox).

## D-92 — Aliados na tela, cursor do controle, telas mais leves e volume (2026-11-11)

Pedido do dono depois de jogar: ver sempre os aliados, o squad e os objetivos; o cursor do controle
"às vezes está em cima e não vai"; telas mais lisas; menos texto.

**Marcadores** (`Marcadores.luau`, ligado pelo `HudCampo`):
- **Aliado à vista:**
  - chevron azul discreto, com o nome curto a até 40 m;
  - a parede tapa;
  - some a 150 m.
- **Squad:**
  - sempre na tela, mesmo atrás de parede, com nome e distância;
  - líder com ★, caído em vermelho com ✚;
  - longe demais para o streaming, usa a posição que o servidor manda a cada 2 s;
  - também aparece como pontos na fita da bússola.
- **Objetivo:** ATACAR ou DEFENDER, com setor e distância. Os outros setores ativos aparecem num selo
  pequeno.
- Atualiza a 12 Hz e reaproveita os marcadores (até 24 aliados mais o squad).
- Nunca marca inimigo (Parte 9.5): o teste `interface` confere que não há ramo para isso.

**Cursor virtual** (`VirtualCursor`):
- O A não acionava quando:
  - o botão tinha por cima uma peça solta (as setas ◄ ► da linha do menu);
  - o centro do cursor caía no vão de 2 px entre linhas ou na borda arredondada.
- Agora:
  - o alvo é o que o anel cobre, num raio de 13 px;
  - realce e clique usam a mesma função;
  - véus e sombras não contam.

**Fluidez:**
- **Menu:** troca só o valor no lugar, sem refazer o menu inteiro.
- **Loja:** abre com o que já sabe; os preços em Robux chegam em segundo plano.
- **Intendência:** abre na hora, com aviso de espera.
- **Imagens:** os botões do controle, a vinheta e as sombras são pré-carregados no início.
- **Correção vista no Studio:** o menu criado desligado guardava a escala da janela do início e abria
  cortado numa janela estreita (671 px). O `UiKit.fit` agora mede a câmera na hora de abrir.

**Menos texto:**
- **Tutorial:** a ordem em uma frase e a dica numa linha.
- **Loja:** a descrição só aparece no item com foco.
- **Relatório:** resultado e baixas em cima; a linha do tempo fica dobrada.
- **Carregamento:** dica de uma linha.

**Volume:**
- Aba "Som" no menu: efeitos, ambiente e música, em porcentagem.
- Salvo na conta: `volEffects` 0,5, `volAmbient` 0,6, `volMusic` 0,35.
- Aplicado nos SoundGroups da D-91.

**Fontes:**
- Nome de lugar vietnamita ("AN CƯỜNG") passa para a Arimo em qualquer idioma. A SpecialElite não
  tem Ư e Ờ.
- "✕" e "▾" viraram "×" e "▼", que as fontes de época desenham (apareciam como quadradinho).

**Studio:** menu na aba Som, cabendo em 671 px; o volume de efeitos foi de 50% para 55% no
SoundGroup; a música do menu toca e carrega.

## D-93 — Água sem bug, passo com peso, VC mais rápido e veículos mais vivos (2026-11-11)
**Pedido do dono, depois de jogar:** "a movimentação na água está toda bugada"; "como o mapa é
grande, faça a movimentação do personagem e dos veículos muito boa"; "faça que os do Vietnã sejam
mais rápidos também". Referência de sensação (sem copiar jogo): peso ao arrancar e parar, curva com
inclinação, balanço preso à passada, degrau e aterrissagem amortecidos, corrida firme.

**Causas do bug da água** (`Movement.client`):
- **Nadar no raso:** o Humanoid entra em Swimming com a água no HumanoidRootPart (em pé ~0,65 m;
  agachado ou deitado, poucos centímetros). O riacho tem 0,6 m no projeto e varia de 0 a ~1,1 m com
  os voxels de 4 studs (`TerrainBuilder`). O soldado alternava nadar e andar:
  - velocidade aos trancos (0,9 m/s nadando);
  - corpo deitando, e a câmera (presa à HumanoidRootPart) girando junto;
  - aderência de "no ar" (0,1) enquanto nadava.
- **Boiar e tremer:** a fundura era medida até o pé. Boiando, o pé subia, a "fundura" caía e o modo
  trocava de novo.
- **Arrozal aos trancos:** a lâmina (peça sem colisão) fica 6 cm acima da mediana do chão do
  tabuleiro, e o capim do terreno fura a lâmina em metade dos pontos. O raio pegava "a primeira
  coisa": o fator do chão alternava 0,62 e 1 a cada passo.

**Água agora:**
- Modo pela fundura do LEITO (superfície − fundo), com histerese: seco abaixo de 5 cm; vadeia até
  1,3 m (peito); nada acima; volta a vadear abaixo de 1,1 m.
- Vadeando, o estado Swimming fica desligado. Medido no teste: canela 3,10, joelho 2,33, cintura 1,24
  e peito 0,93 m/s; arranca e vira mais pesado; passada da câmera mais pesada.
- Nadando: 0,9 m/s, aderência 0,5 e câmera em pé (corrige a inclinação da HumanoidRootPart).
- Deitado só até 0,3 m d'água e agachado até 0,8 m; nadando, de pé. Mergulho só no seco.
- Arrozal: lâmina na coluna até 0,3 m abaixo do chão achado = arrozal. A superfície só troca depois
  de lida igual por 0,3 s, e o fator do chão é suavizado (0,25 s).

**Passo** (`Movement.moveStep`; os bots seguem com `accelStep`):
- Arrancada de 11 m/s² caindo a 5 m/s² perto da corrida; parada a 12 m/s².
- Curva: a direção gira até 16 m/s² de aceleração lateral, sem perder velocidade. O modelo vetorial
  cortava pela corda: numa curva de 90° a velocidade caía a 71%.
- Medido: parado → andar 0,15 s, → trote 0,35 s; trote → corrida 0,38 s; corrida → parado 0,47 s;
  meia-volta 0,60 s; 90° no trote 0,32 s e na corrida 0,55 s, mantendo 100% da velocidade.
- Corrida cheia até ~45° do rumo (W+D), caindo suave até o trote em ~60° (antes, degrau em 53°). Com
  a corrida ligada, o analógico acima de 70% vale o fim.
- Parede: a velocidade guardada só cai para a real depois de 0,15 s (antes, todo dique engasgava).
- Agachado ou deitado parado na face de um degrau baixo: passada assistida sem botão (0,46 s para
  0,45 m agachado; 0,84 s para 0,35 m deitado).

**Câmera:**
- Balanço preso à passada das animações da D-88: a cabeça desce no apoio do pé.
- Cabeça com inércia (mola de 2,2 Hz, até 3,5 cm): para trás ao arrancar, à frente na parada.
- Inclinação lateral para o lado do passo e para dentro da curva, até 1,4°, aplicada depois do
  módulo de câmera, só em volta da linha de visada. Mirando e deitado, nada.
- Degrau (dique, soleira) suavizado em ~0,2 s; numa ladeira, sem atraso.
- **Opção "movimento da câmera"** (0 a 1) multiplica balanço, respiração, afundada, inércia e
  inclinação. Lida de `Input.settings.cameraBob`; até o menu ganhar a opção, do atributo local
  `CameraBob` do jogador.

**Lado** (`Movement.FACTION`, PLACEHOLDER):
- VC: velocidade ×1,12 em andar, trote, corrida e agachado (trote 3,47, corrida 6,16 m/s);
  transpor ÷1,1 (dique em 0,54 s contra 0,60 s); base do equipamento de 7 kg contra 11 kg.
- Mira de ferro, rastejar e nado iguais nos dois lados.
- Servidor: `MedicalService.apply` usa `Movement.serverSpeed(..., faction)`. Em 10.000 sorteios o
  cliente nunca passa do teto.
- Bots: chamam `serverSpeed` sem o lado e ficam na velocidade-base.

**Veículos** (`VehicleDrive`, `VehicleController`; os números da tabela da D-86 não mudaram):
- **Dique:** a quina segurava o chassi e o comando caía para a velocidade medida: o tanque parava em
  cima do dique. Com um degrau de até 0,65 m à frente, a lagarta segue empurrando a 1,5 m/s por até 3 s.
- **Direção:** inércia do giro menor (M48 0,6 → 0,45 s): 90% do giro no lugar em 1,05 s (antes
  1,38 s). Andando, curva de raio fixo do câmbio cross-drive (M48 12 m, Ontos 7 m, LVTP-5 13 m;
  PLACEHOLDER): 90° a 31 km/h no capim em 4,5 s (antes 5,5 s). Arrasto da curva menor (M48 0,06 → 0,045).
- **Comando:** teclado mais rápido (acelerador 0,22 s, volante 0,17 s); no controle, volante 12/s.
  Encostado em árvore ou casa, o giro comandado fica a 12° do real (antes o AlignOrientation
  torcia o chassi de uma vez ao soltar).
- **Travessia de 1 km (M48, modelo):** terra 109 s, capim 123 s, mata 156 s, arrozal 277 s.

**Ganchos só no Studio:** `workspace:SetAttribute("VT65DevMov", X)` com X igual a `agua`, `fundo`,
`mar`, `arrozal`, `dique` (no assento do motorista, leva o veículo), `info`, `veiculo`, `vc`, `eua`
ou `nada`.

**Não testado no motor:** tudo acima foi medido no Lune. Falta ver no Studio o empuxo vadeando até o
peito, a passada assistida no dique, a inclinação da câmera e a subida do tanque no dique.

## D-94 — Facas de 1965, facadas, braços fora do corpo, câmera agachada e bots animados (2026-11-11)
**Pedido do dono:** "faça facas e animações de facadas ultra-realistas com gráficos absurdos";
"corrija e melhore a movimentação dos braços do personagem, que ficam atravessando o seu corpo".

**Facas** (`tools/faca`, Blender 5.3; saída em `assets/facas`):

| Chave | O quê | Triângulos (faca + bainha) |
|---|---|---|
| `kabar` | faca de combate USMC, bainha de couro com costura e rebites | 5.564 + 6.346 |
| `m6` | baioneta M6 da M14 (anel de boca), bainha M8A1 | 2.372 + 4.802 |
| `type56` | espigão rebatível do Tipo 56 (fica no fuzil) | 1.622 |
| `dao` | facão do VC, bainha de madeira com anéis de rotim | 4.360 + 5.420 |

- Malha procedural com chanfro, sulco, guarda, cabo de arruelas de couro em anéis e pomo; atlas
  1024 (cor, normal, metal/rugosidade) assado no Cycles a partir de materiais procedurais (aço
  fosfatizado gasto com riscos e fio claro, couro com grão e escurecido nos sulcos), com a oclusão
  multiplicada na cor. Prévias renderizadas em `assets/facas/<chave>_previa.png` e `_close.png`.
- GLB com os nós `Faca` e `Bainha` (a bainha já traz o cabo). Pontos medidos no GLB relido
  (`pontos.json`) vão para `Shared/Weapons.knives` (o teste `faca` confere).
- Medidas de memória, PLACEHOLDER até conferir: Ka-Bar 302/178 mm (total/lâmina), M6 292/171,
  espigão 289/223, facão 509/330.
- Sons sintetizados (`tools/faca/sons.py`, MP3 pelo FFmpeg do Blender): saque, corte, impacto e
  encaixe da baioneta.
- Chaves novas em 0: `AssetIds.Models.faca_kabar|m6|type56|dao` e `AssetIds.Sounds.faca_saque|
  faca_corte|faca_impacto|baioneta_encaixe`. Sem elas: faca de peças (`Shared/KnifeModel`) e sons
  substitutos (curativo e impacto na terra, mais graves).

**Golpes** (`Shared/Melee`, puro; números de projeto, PLACEHOLDER até playtest):

| Golpe | Antecipação / impacto / fim (s) | Alcance | Cone (certeiro) | Tronco | Cabeça | Membro |
|---|---|---|---|---|---|---|
| estocada (faca) | 0,10 / 0,20 / 0,55 | 1,8 m | 24° (12°) | 1.600 J: caído | 260: caído | 1.500: 20% arterial |
| golpe de lado (faca) | 0,12 / 0,24 / 0,60 | 1,5 m | 55° | 700: −59 de vida, sangra | 260: caído | 900 |
| baioneta | 0,18 / 0,32 / 0,90 | 2,1 m | 20° (10°) | 1.800: caído | 280: caído | 1.600 |
| coronhada | 0,16 / 0,30 / 0,85 | 1,4 m | 35° | 250 | 250: caído | 250 |

- Energia equivalente para o `Medical` (tronco ≥ 1.500 derruba; cabeça < 300 derruba sem matar).
  Fora do cone certeiro vale o golpe de raspão (estocada → lado; baioneta → coronhada). Caído:
  golpe ≥ 300 mata (a coronhada não). Facão do VC: estocada ×0,9, golpe de lado ×1,4.
- Alcance medido do peito de quem golpeia ao ponto mais próximo do corpo do outro.
- Entrada: "Corpo a corpo" (R3 / botão do meio), sem ação nova. 1º toque = estocada (com o saque de
  0,28 s se a faca está na bainha); 2º toque até 1,0 s depois = golpe de lado. Com a baioneta armada
  (Y segurado / K) o toque é a estocada de baioneta. Sem golpe por 1,3 s a faca volta à bainha
  (0,35 s); atirar ou recarregar com a faca na mão a guarda.
- **Servidor** (`Modules/MeleeService`, chamado pelo `FieldService`): o cliente só manda a direção.
  O servidor escolhe o golpe pelo próprio estado, confere vivo, sem assento, transpor ou
  arremesso, direção finita a ≤ 75° da frente do corpo e ≤ 70° de arfagem, o intervalo do golpe
  (90% do fim, mais o saque) e no máximo 8 pedidos por segundo. O acerto é resolvido NO IMPACTO com
  a geometria do servidor: 15 peças do corpo, folga de 0,3 m e linha livre (o que tem colisão
  bloqueia). Quem sai do alcance na antecipação escapa.
- **Bots:** reflexo no servidor a 4 Hz: inimigo a ≤ 1,5 m e ≤ 50° da frente, 70% de chance,
  1,1 s de intervalo; o fuzileiro estoca, o VC corta com o facão. Bots também são golpeados.
- **Impacto:** pó escuro de pano (5 partículas de 2–7 cm, 0,3 s), nada de sangue; som do golpe e
  do impacto em 3D até 40 m; quem leva sente um tranco na câmera.
- **3ª pessoa:** a faca é soldada na mão direita pelo servidor (todos veem) enquanto está fora; o
  cabo provisório do cinto some. A baioneta vai na boca do fuzil (M6 com o anel no quebra-chamas; o
  espigão por baixo do cano). Clipes procedurais novos no `tools/anim`: `faca_saque`,
  `faca_estocada`, `faca_lado`, `faca_guardar` e `baioneta` (camada de cima; a faca solta o IK da
  mão direita). Bots tocam pelo atributo `MeleeT`.
- **1ª pessoa** (`Controllers/KnifeView`, chamado pelo `WeaponVisuals`): o fuzil desce para a mão
  esquerda, a mão direita vai à bainha e volta com a faca; estocada com antecipação (o braço recua e
  a ponta sobe), golpe rápido com follow-through e volta; golpe de lado com o pulso armado e o fio à
  frente; baioneta (recua, avança com o passo) e coronhada. A câmera balança com o golpe e, no
  impacto previsto, dá um tranco de 1,6° com uma pausa de 60 ms (a lâmina "prende").
- **Cinto:** todo soldado leva a faca (`Gear`, peças "knife_*" no primeiro lugar livre do cinto);
  com a arte publicada, a bainha do GLB entra no lugar (`Characters`).

**Braços que atravessavam o corpo** (`Shared/ArmIK`, `PostureController`, simulação no Lune):
- Medida na simulação do R15 (IK de dois ossos com polo, caixas do corpo "Man" aproximadas,
  PLACEHOLDER até medir no Studio), com cada arma publicada, torções de pelve até 100° e flexões do
  peito de ±29°. **Antes:** antebraço direito 13,4 cm dentro do peito e a coronha 19–20 cm (fuzis e
  metralhadoras); pistola 13,4 cm e 5–7 cm. Causa: punho a 0,2 stud da frente do peito, sem polo de
  cotovelo, e a coronha voltada para dentro do tronco.
- **Correção:** polo nos dois cotovelos (`IKControl.Pole`: para fora e para baixo); tronco de lado
  25° (o ombro esquerdo à frente; a cabeça gira de volta; sai no arremesso, com a faca e deitado);
  pega nova `HOLD_STAND` (0,25; 0,8; −1,5; 55°; −20°): punho na altura do peito, ~27 cm à frente,
  boca para baixo cruzando 30° à esquerda; pistola com os braços à frente (0; 0,9; −1,85; 20°; −35°);
  pegas de recarga (o fuzil sobe ao peito), de faca (fuzil baixo na esquerda), de guarda e de
  estocada de baioneta; a arma presa por uma `Weld` local de C0 mutável.
- **Depois:** fuzis e metralhadoras 0 cm (braços e arma), pistola 1,0 cm. Clipes gravados (quadro a
  quadro): passada, parado e agachados 0,1 cm; estocada 0,3; golpe de lado 1,2; saque 2,0; guarda
  2,2; recarga 2,5; granada 2,4 (captura da CMU); deitado e rastejar 6,3/6,1 (a mão do punho junto
  do rosto: a cabeça entra como cubo). O teste `faca` imprime a tabela.
- **Continua:** o corpo não segue a arfagem da mira, e quem olha não vê o fuzil no ombro quando você
  aponta (já era assim; precisaria replicar a mira).

**Câmera agachada:** `PostureService.DROP.crouch` 2,2 → 1,03 stud, o quanto a cabeça desce nos
clipes (1,506 m de pé; 1,218 m de joelho; 1,219 m andando agachado, com o quadril 0,22 stud mais
baixo que antes). A câmera fica a ≤ 1 cm da cabeça (teste `faca`). A dobra de reserva do
`PostureController` (sem o clipe) foi para coxa 75° e joelho −115°.

**Bots animados** (`SoldierAnims.BOTS = true`): até 100 studs tudo a cada quadro; até 300 studs e
na tela (margem de 15%, 1 s de folga), a mistura a 10 Hz e as correções a 15 Hz; fora da vista ou
além do raio, os clipes param. A velocidade é a real (o maior entre a da posição replicada e a do
corpo) e a postura, os atributos do servidor. **Custo com 58 bots não medido.**

**Regravados** (`tools/anim`): todos os clipes (pega e polos novos). Precisam subir de novo (fora
do `ids.json`, id 0 no `SoldierAnims` até subir): `agachado`, `agachado_andar`, `recarregar`,
`granada` e os 5 novos. Os de passada e deitado seguem com os IDs antigos: o IK cobre os braços.

**Ganchos só no Studio** (`workspace:SetAttribute("VT65DevFaca", X)`):
- 1ª pessoa (qualquer barra): `estocada`, `lado`, `baioneta`, `coronhada`, `laco` (em laço até
  `parar`).
- Servidor: `boneco` (inimigo a 1,6 m à frente), `boneco:estocada|lado|baioneta|coronhada` (golpeia
  em laço, sem dano), `bracos:stand|crouch|prone|sprint|girar`, `arma:m14|m60|m1911|type56|sks|rpd|
  type54`, `limpar`.

**Falta:** a tela de baixa mostra "origem não identificada" para golpe de faca (precisa de uma
causa "arma branca" no `Casualty`, arquivo de interface). Nada disto foi testado no Studio.

**Studio (2026-11-11):** o boneco do VC golpeia em laço, com o fuzil na mão esquerda e o facão na
direita; os clipes publicados tocam.

## D-95 — Mapa de 1 x 1 km e jogo mais leve (2026-11-11)

O dono jogou e pediu: "acho que temos que diminuir ainda mais o mapa e fazer ele 1 km x 1 km"; "o
jogo está bem pesado, as coisas demoram para acontecer". Substitui o tamanho da D-63.

**Recorte:** E 269,35–270,35 x N 1692,5–1693,5 (grade BS), a ponta nordeste do mapa anterior. Reúne:
- An Cường (2), com os túneis e a trincheira sul;
- o casario leste de Nam Yên (4) e An Thới (2);
- o morrote de 34 m, os arrozais com diques e sebes e a Colina 30;
- o vale do riacho a leste de An Cường (2), o chão mais plano, onde fica a base dos EUA.
- Nam Yên (3) não cabe junto com An Cường (2) em 1 km.
- É um recorte, não uma deformação: fora da área sobra só a margem do terreno (150 m de horizonte).

**Riacho:** leito aberto no talvegue do vale, "the streambed just east of An Cuong (2)" (First Fight,
p. 29). O canal tem 1,1 m e a água 0,6 m em todo o leito, descendo em 7 degraus de 1,12 m.

**Setores (oeste → leste):**
- S1 Nam Yên (4): Nam Yên (4) ★, Cemitério ★, Capinzal oeste;
- S2 An Thới (2): An Thới (2) ★, Arrozal central, Encosta norte;
- S3 Morrote do arrozal: Morrote, Lugarejo a sudoeste de An Cường (2) ★, Arrozal norte;
- S4 An Cường (2): An Cường (2) ★, Trincheira sul ★, Arrozal ao norte de An Cường (2);
- S5 Riacho: Colina 30 ★, Riacho a leste de An Cường (2) ★, Encosta sul da Colina 30.
(★ = local real; o resto é nome de design.)

**QGs:**
- EUA: E 270,30 / N 1692,95, a 50 m da borda leste, com 140 m sem dique, lâmina nem sebe (espaço
  para a base). A raia de tiro desce o vale para o sul.
- VC: E 269,41 / N 1693,43, no morro do noroeste. A raia corre para leste ao longo da borda norte.

**Números que mudaram (de projeto, PLACEHOLDER):**
- `Front`:
  - reunião avançada a 125 m (era 250);
  - passo de 10 m (era 20);
  - 20 m para dentro do setor (era 30);
  - busca até a distância do ponto forte próprio + 200 m (era + 400).
- Reunião do squad:
  - mínimo de 100 m do ponto forte inimigo (era 150);
  - 150 m do QG inimigo (era 300).
- Reunião atrás do ponto forte: 60 m (era 100), a pelo menos 30 m da borda.
- Renascer onde caiu: bloqueado a menos de 125 m do QG inimigo (era 250).
- Marcha até o S3: média de 51 s, pior caso 63 s (eram 92 e 119 s).
- Clareira de nascimento: 15 m sem planta e visada de 35 x 8 m para o objetivo, em 104 pontos.
- Arrozal: o chão fica 10 cm abaixo da lâmina; o dique, pelo menos 25 cm acima.
- Streaming: alvo 1280 studs (358 m), mínimo 384 (108 m). Eram 1536 e 512.

**O que pesava (antes → depois):**
| Item | 2 x 2 km | 1 x 1 km |
|---|---|---|
| Blocos de terreno | 1.089 | 361 |
| Peças do bake (diques, lâminas, sebes, casas) | 6.529 | 2.329 |
| Plantas da mata | 45.328 + 2.777 de cortina | 8.219 + 620 |
| Plantas com sombra | 6.133 | 1.239 |
| Arte (modelos / triângulos somados) | 56.117 / 614,6 mi | 11.131 / 120,5 mi |
| Raios para assentar planta | ~240 mil | ~9 mil |

Também:
- a cortina de fora da área ficou sem colisão nem sombra;
- o `Ambiente` passou a rodar a 15 Hz;
- animais além de 120 m atualizam a 10 Hz;
- casas e objetos refeitos no Blender têm 1/3 dos triângulos.

**Studio (2026-11-11):** terreno pronto em 7 s (eram 10–20 s), 1.510 modelos de arte carregados (eram
3.775), nenhum erro de script, a casa do Blender com textura certa. A carta de 1 x 1 km foi gerada e
publicada (4 blocos). Fps não medido.

**Ainda pesa (fora deste trabalho):**
- uns 40 laços por quadro no cliente (HudCampo, VehicleFx, SoldierAnimations, Weather, GameUI);
- o `BotLocomotion` roda a cada quadro por bot;
- `Lighting.Technology = Future`.

## D-96 — Bots que usam o mapa, veículos, túneis e granadas (2026-11-11)

Pedido do dono: "faça os bots entenderem como utilizar os veículos, os locais do jogo, os túneis, as
granadas; nível médio"; "movimentação linear como se fossem jogadores reais".

- **Pernas de jogador** (`BotLocomotion`, `BotMove`): caminho suave, inércia, corpo que vira e passo
  pela situação.
  - O VC anda ×1,12, como o jogador (D-93).
  - Vadeando, o estado de nado fica desligado.
- **Mapa entendido** (`BotWorld`, `BotNav`):
  - rota que foge do arrozal alagado e usa dique, sebe e mata;
  - 1.265 abrigos fixos conhecidos no mapa novo.
- **Squads** (`BotSquads`): seguem o líder em coluna ou cunha, avisam o contato e avançam em lances.
- **Combate** (`BotBrain`, puro e testado no Lune):
  - notar leva tempo (cone de visão);
  - a mira firma no alvo novo;
  - disciplina de fogo e supressão na última posição vista;
  - granada atrás do dique sem acertar o próprio squad;
  - golpe de faca a até 1,5 m (D-94).
- **Túneis só do VC** (`BotTunnels`, `TunnelLinks`): o EUA que desce mais de 6,5 studs na galeria é
  expulso.
- **Blindados com tripulação de bots dos EUA** (`BotVehicles`, `BotDriver`; API de bot no
  `VehicleService`):
  - embarcar, sair, dirigir e atirar do assento;
  - no Studio, o M48 e o LVTP-5 saíram tripulados por 2 bots cada.
- **Ganchos no Studio:** `VT65DevBots` com "depurar", "m48", "ontos", "lvtp", "tunel", "cobertura" e
  "parar".
- **Falta medir:** o custo com 58 bots; o comportamento numa partida longa.

## D-97 — Revisão de todos os menus: fluidez e bugs (2026-11-11)

Pedido do dono: "melhore todos os menus do jogo, inclusive os recém-criados; quero eles bem fluidos e
sem bugs". Varredura de cada tela no Studio numa janela de 671 x 565 e correção:
- **Voltar (B, Esc, Backspace):**
  - fecha só a tela de cima, numa pilha na ordem de desenho;
  - o lobby não age com outra tela por cima;
  - a ficha de baixa não desconta mais o contador de menus em dobro.
- **Loja e intendência:**
  - eram duas telas que abriam uma por cima da outra; agora são uma pasta só, com abas, que cabe na
    janela;
  - a aba Loja do menu mostra saldo, posto e renasceres guardados.
- **Câmera depois da inserção:**
  - chegava olhando −77° para o chão (o capim do terreno enchia a tela e parecia que o soldado nascia
    no mato);
  - agora nivela em 0,35 s para −3°, virada para o objetivo, antes do voo de descida.
  - Studio: `LookVector.Y` = −0,052.
- **Fim de partida e relatório:**
  - o motivo cabe em duas linhas;
  - o tutorial some;
  - as seções foram renumeradas 1, 2, 3, com o singular certo;
  - a faixa da frente atualiza a 10 Hz.
- **Roda:** fichas em elipse, sem se sobrepor (teste no PC e na TV).
- **Chat do Roblox:** um dono só (`JanelaChat`); some com o lobby, os menus e o mapa.
- **Carta de inserção:**
  - o nome do ponto só aparece em foco;
  - o estado do ponto vai na cor do símbolo;
  - as dicas ficam numa faixa escura.
- **Lobby:**
  - rótulos 3D abaixo do cabeçalho;
  - o manequim do VC ganhou o capacete de medula;
  - a recompensa diária ficou numa linha, com o carimbo maior.
- **Cartão da arma:** maior e com mais contraste.
- **Avisos:** esperam a ficha de baixa sair e somam ganhos iguais.
- **Opção nova:** "Movimento da câmera" (`cameraBob`, 0–100%) em Acessibilidade.
- **Falta:** o aviso de captura ainda aparece por cima da loja aberta.

## D-98 — Soldado de 2,0 m, capacetes no tamanho real e carta na mão (2026-11-12)
**Pedido do dono:** "os personagens estão muito pequenos em relação ao mapa; coloque eles com 2 m de
altura"; "os capacetes estão bugados, estão pequenos"; "coloque o mapa como um item que ele pega e
abre, e isso aparece para todos"; "coloque um botão no controle para ativar a 3ª pessoa e a 1ª pessoa".

**Soldado de 2,0 m** (decisão do dono, não medida histórica; `Shared/Corpo`):
- O corpo de 1,75 m ampliado por igual por K = 2,0 / 1,75 = 1,1429 (`Characters`): HeightScale
  1,25 → 1,4286; largura, profundidade e cabeça 1 → 1,1429. Conferir no Studio: atributo `AlturaM`
  ~2,00 m (a conta 1,68 × 1,4286 / 1,2 não foi medida).
- O que foi gravado ou medido no corpo de 1,75 m continua nesses números e vai vezes K no jogo:
  - `PostureService`: DROP agachado 1,03 → 1,1771 e deitado 4,4 → 5,0286; MIN_HIP 0,2 → 0,2286;
    descida do PRONE_ROOT −0,6 → −0,6857. O HipHeight de cada postura cresce K;
  - **clipes sem regravar**: o Animator escala a Root por HipHeight / AuthoredHipHeight (K) e as
    rotações valem igual. A passada fica K vezes mais longa: a velocidade sem escorregar é a do clipe
    × K (`SoldierAnims.SCALE`, `cycleRate`). O `tools/anim/retarget.py` lê o PostureService e divide
    por K (grava sempre no corpo de 1,75 m);
  - `PostureController`: pegas da arma e da carta e polos dos cotovelos × K (o `ArmIK` segue no corpo
    da gravação). **Armas e facas ficam no tamanho real** (a M14 segue com 1,126 m). Medido de novo
    com a arma 1/K menor em relação ao corpo: fuzis e metralhadoras 0 cm, pistola 1,0 cm, guarda da
    baioneta do Tipo 56 0,6 cm;
  - `Gear`: equipamento em medidas reais × K (`BODY_K`);
  - `Movement`: água no peito 1,3 → 1,49 m (nada), volta a dar pé em 1,26 m; agachado até 0,91 m e
    deitado até 0,34 m de água; transpor com 0,86 m livres, alcance de 1,03 m, de pé em cima com
    2,06 m; degrau agachado até 0,74 m e deitado até 0,51 m (espaço acima 1,14 / 0,51 m); câmera do
    ombro × K. As alturas de obstáculo de transpor (0,35–1,25 m) e as velocidades não mudaram;
  - `Movement.client`: olho deitado −1,6 → −1,83 stud, inclinar 0,35 → 0,40 m, e +0,07 stud em
    todas as posturas (a câmera do Roblox põe o olho 0,5 stud acima da HRP, número que não cresce).
    Olho estimado (HipHeight 2,857 e HRP de 2,857 studs, não medidos): de pé ~1,76 m, agachado
    ~1,43 m, deitado ~0,51 m. O raio da sonda de escalar foi a 2,26 m (antes 2 m: com 2,06 m de
    espaço pedido, escalar nunca passaria);
  - `VehicleDrive`: olho da tripulação +0,6 m × (K − 1) = +8,6 cm e da tropa sentada +12,9 cm;
  - faca na mão (`MeleeService`): o punho desce `HAND_GRIP_Y` × K na mão maior.
- **Túneis** (`TunnelGeometry`, `TunnelService`): o túnel (1,0 × 1,2 m) não muda; o soldado de 2 m
  passa nele **deitado, rastejando** (a HRP agachada chega a 1,27 m e bateria no teto).
  - Poço com no mínimo 1,0 m por dentro (era 0,6 m: a HRP de 0,64 m não cabia ao lado da escada).
  - Escada (TrussPart de 2 studs) encostada na parede norte, não no meio.
  - Quem do VC está no túnel fora do poço e não está deitado é deitado (0,3 s). O PostureService
    não deixa levantar sob o teto.
  - Precisa assar o place de novo (forro do túnel).
- **Portas** (agente do mapa): de pé, no mínimo **2,1 m** (7,5 studs; a cabeça colide a 2,0 m);
  agachado, **1,6 m** (5,7 studs).

**Capacetes** (`Gear.headgearFit`):
- Só pela cabeça, a copa abraçava a cabeça do "Man" (menor que a do bloco) e o casco ficava do
  tamanho de um boné.
- Agora o casco tem no mínimo o tamanho real × K:
  - M1: 27 × 30 cm (pedido do dono, PLACEHOLDER) → 30,9 × 34,3 cm no jogo;
  - capacete de medula: 29 × 34 cm → 33,1 × 38,9 cm;
  - chapéu de mato: 32 × 34 cm → 36,6 × 38,9 cm (os dois PLACEHOLDER).
- A cabeça também cresceu K. A peça da cabeça da camuflagem de mato cresce até cobrir o capacete.

**Carta na mão** (`Controllers/CartaMao`, `Shared/CartaModel`, `PostureController`, `PostureService`):
- Abrir o mapa tático pede ao servidor a carta na mão (`Posture_Set { carta }`). O servidor confere
  vivo, a pé e sem estar caído, aceita no máximo 4 trocas por segundo e grava o atributo `Carta`; caído, sentado ou morto, ela sai.
- **3ª pessoa** (todos veem): folha de 50 × 36 cm (PLACEHOLDER) dobrada ao meio, cor de papel e a
  imagem da carta do jogo (`CartaImage_*`), diante do peito e inclinada 50° para os olhos. As duas
  mãos nas bordas (IK) e o fuzil a tiracolo no ombro direito, boca para cima. Medido: braços 0 cm,
  fuzil a tiracolo 0 cm dentro do corpo.
- **1ª pessoa:** o fuzil some, as mãos sobem com a folha em 0,35 s e ficam na parte de baixo da tela,
  embaixo da `CartaView`.
- Com a carta aberta não se atira (o contexto do mapa já bloqueia; o `WeaponController` confere).

**1ª/3ª pessoa no controle:** já existe (D-68): **segurar → no direcional** no controle, **O** no
teclado (e no menu: Configurações › Mira). Não há botão livre no contexto de infantaria (todos os
botões do controle já têm toque e segurar). Por isso não criei uma ação repetida.

**Ganchos só no Studio:** `VT65DevFaca = "boneco"` e depois `"bracos:carta"` (o boneco abre e fecha a
carta); os de postura da D-94 continuam.

**Fora dos meus arquivos (precisam do dono de cada um):**
- `BotLocomotion`: AgentHeight 6,5 studs (1,82 m) para 7,3 (2,05 m);
- `BotBrain`: altura dos olhos para abrigo, que ainda é a do soldado de 1,75 m;
- `BotTunnels`: leva o bot agachado no túnel; com 2 m a cabeça passa do teto (fica dentro da terra);
- `Units.SOLDIER_HEIGHT` e o `DebugHud` ("meta 1,75");
- o enquadramento do manequim do lobby (`SoldierPreview`/`LobbyScene`).

**Não testado no Studio.**

## D-99 — Inclinar e passo do Front 44, sangramento que demora, curativo que estanca, itens animados e mãos de 1ª pessoa (2026-11-12)
**Pedido do dono:** "os botões de se inclinar não estão funcionando"; "utilize o mesmo modelo de
movimentação e inclinação que uso no Front 44"; "o sangramento tem que demorar mais para matar, e
quando eu utilizar a bandagem ele deve parar"; "faça as animações perfeitas para bandagens etc." e
"para todos os itens ao utilizá-los"; foto: em 1ª pessoa as mãos da pistola eram "duas bolas laranjas".

**Por que o inclinar não funcionava:** Q/E e L3/R3 existiam só na camada de mira (sem mirar a tecla
nem chegava); a máquina de estados zerava o inclinar fora da mira; a câmera só andava 0,4 m de lado,
sem giro; soltar a mira mandava `lean = 0` ao servidor; nada impedia de espiar através da parede.

**Inclinar (modelo do Front 44, `Controllers/Inclinar`, `Movement.LEAN`):**
- **Q/E** seguram o inclinar a qualquer hora a pé (contexto de infantaria); no **controle, L3/R3
  mirando** (fora da mira não há botão livre: L3 corre, R3 é o corpo a corpo, o direcional já tem
  tocar e segurar). As duas teclas contam juntas;
- o valor anda para o alvo a **8/s** (Front 44); correndo, deitado, nadando, transpondo, sentado ou
  caído o alvo é 0; a câmera vai **0,35 m** de lado (1,1 stud do Front 44 × K) e gira **14°**; a arma,
  as mãos, a faca e a carta de 1ª pessoa giram junto (WeaponVisuals); o tronco que os outros veem
  gira **19,6°** (14 × 1,4);
- **colisão:** um raio e uma esfera de 12 cm do olho para o lado medem o espaço; a parede limita a
  câmera, a arma e o tronco (o servidor recebe o inclinar em quartos, arredondado para dentro);
- o próprio cliente reenvia o inclinar se algo o zerar (soltar a mira); o servidor zera correndo,
  deitado e caído.

**Passo e posturas (Front 44, que chega à velocidade quase na hora):** arrancada 16 → 8 m/s² (antes
11 → 5), parada 16 m/s² (antes 12), curva 22 m/s² (antes 16): parado → trote 0,23 s, trote → corrida
0,25 s, trote → parado 0,2 s. **Agachado 1,4 m/s** (antes 0,84; o Front 44 usa 2,0) e **rastejar
0,5 m/s** (antes 0,35; Front 44 1,1), no meio-termo com a passada das animações. Deitar 0,6 s e
levantar 0,75 s (antes 0,8 e 1,0); agachar 0,22 s. Água, VC × 1,12, 2 m e passada assistida ficam.
PLACEHOLDER.

**Sangramento e curativo (`Shared/Medical`, `MedicalService`):**
- sangra **~5x mais devagar**: leve 0,1, grave 0,25, arterial 0,8 vida/s (antes 0,5 / 1,5 / 4,0). Até
  cair: pistola no tronco ~3 min, artéria da perna ~1,5 min, braço ~5 min (hemorragia de membro mata
  em minutos, não em segundos). PLACEHOLDER;
- **o curativo estanca:** um curativo fecha todo ferimento que não é arterial (antes o grave virava
  leve e continuava sangrando). Artéria pede torniquete; sem torniquete, compressão (vira leve);
- **bandagem rápida (G / ↓)** faz tudo de uma vez: torniquete na artéria (se houver um) e curativo no
  resto. O `Medical_State` manda `arterial` (o `MedicalController` ainda decide pela taxa antiga, ≥ 4,
  mas o servidor já aplica o torniquete; o `Haptics` usa ≥ 1,5 para o coração: dono de cada um).

**Itens animados (`Shared/ItemAnim`, `Controllers/ItemView`, `PostureController`):** curativo em si
(tira da bolsa, rasga, enrola no braço, amarra), torniquete na coxa (passa a tira, gira a haste,
prende), curativo no companheiro, tratamento e reanimação do médico (compressões), rádio (fone no
ouvido, só a esquerda), binóculo, pá de trincheira (crava, alavanca, joga a terra) e cantil (abre,
bebe com a cabeça para trás, guarda).
- **Todos veem:** o servidor grava `VT65Acao` (ações médicas, com `VT65AcaoT`/`VT65AcaoS` no relógio do
  servidor) e `VT65Item` (rádio, binóculo, pá, cantil, que o `ItemView` pede pelo `Posture_Set`); o
  `PostureController` de cada cliente leva as mãos por IK ao caminho do `ItemAnim`, põe o fuzil a
  tiracolo e o objeto na mão (curativo, haste, fone, binóculo, pá, cantil, nas medidas reais);
- **1ª pessoa:** o fuzil sai da frente e as mãos novas fazem o mesmo caminho com o objeto; no rádio só
  a esquerda larga o guarda-mão;
- **clipes de 3ª pessoa** (`tools/anim`, procedurais com as mesmas chaves: tronco curvado sobre o
  companheiro, cabeça olhando a ferida, cabeça para trás ao beber): `item_curativo`, `item_torniquete`,
  `item_curativo_outro`, `item_tratar`, `item_reanimar`, `item_radio`, `item_binoculo`, `item_pa`,
  `item_cantil`, id 0 até subir; o `SoldierAnimations` os toca parados no instante do servidor;
- os alvos das mãos foram tirados de dentro do corpo no simulador do `ArmIK`
  (`tools/anim/itens_fora.luau`, ≤ 1,5 cm por chave) e ficam no alcance do braço (`ItemAnim.reach`);
- a pá é reconhecida por **chave**, nunca pelo texto da tela (que pode chegar traduzido): o
  `ItemView` aceita `{ key = "dig_start" | "dig_cancel" }` no `Logistics_State` ou o atributo
  `VT65Item = "shovel"` posto pelo servidor. **O `FieldWorkService` (não é meu) ainda manda só o
  texto: até ele mandar a chave, a pá não anima.** Cantil: o jogo não tem a ação de beber; a animação
  existe e toca pelo gancho do Studio. Granada, fumaça, carta e recarga seguem com as suas (D-77,
  D-98, D-69).

**Vantagens compradas do corpo (`Shared/Vantagens`, conferidas no servidor pelos atributos `Vant_*`):**
- `speed` (1,06): trote e corrida no `Movement.serverSpeed` (teto do `WalkSpeed` no `MedicalService`)
  e no `Movement.targetSpeed` do cliente (o mesmo número; o cliente nunca passa do teto). Agachado,
  rastejar, mira e perna ferida não mudam;
- `health` (1,12): vida máxima (`Medical.new`, `Humanoid.MaxHealth`), acompanha o passe se ele chegar
  depois do nascimento;
- `bandage` (0,74): tempo do curativo (em si e no companheiro) e do torniquete;
- `bleed` (0,8): taxa de sangramento (pistola no tronco: 182 s → 287 s até cair).
- Testado no Lune com e sem passe (`f2`, `movimento`).

**Mãos de 1ª pessoa (`Shared/MaosPose`, `Controllers/Maos1P`, `tools/maos`):** cada pega tem a forma de
uma mão (palma, quatro dedos, polegar e pulso, com medidas de mão adulta): a direita fecha o punho com
o indicador no gatilho; a esquerda apoia o guarda-mão, abraça a direita na pistola ou segura o
carregador; a mão aberta segura a carta. Antebraço com pulso de pele e manga do uniforme (EUA: OG-107
arregaçada; VC: manga lisa). Sem a arte publicada são cápsulas de peças (bola + cilindro); com
`AssetIds.Models.maos_us_1p` / `maos_vc_1p` (`assets/blender/maos_1p/*.glb`, feitos no Blender pelas
mesmas cápsulas fundidas por voxel) o `Characters` põe a cópia em `ReplicatedStorage.VT65MaosArt` e
entram as malhas; a cor é a da pele da cabeça do soldado.

**Sobras da D-98:** `Units.SOLDIER_HEIGHT` = 2,0 m e a meta do `DebugHud` 2,00 (com as traduções).

**Ganchos só no Studio:** `workspace:SetAttribute("VT65DevLean", -1 | 0 | 1)` (inclina sem tecla, para
testar a quina); `workspace:SetAttribute("VT65DevItemAnim", "bandage" | "tourniquet" |
"bandage_other" | "treat" | "revive" | "radio" | "shovel" | "canteen")` (toca a animação de 1ª pessoa).

**Não testado no Studio.**

## D-100 — Pilotar todos os veículos, painel de lugares, tiro de dentro e carros (2026-11-12)
**Pedido do dono, depois de jogar:**
- "por que não consigo pilotar tanques, carros e helicópteros?";
- "coloque a interface do botão para eu entrar neles ou pilotar quando chegar perto";
- "faça poder atirar de dentro dos veículos";
- "os veículos conseguem andar em todo o mapa sem bugar? Eu quero isso".

**Por que não dava para pilotar:**
- todo lugar de blindado pedia `tank_crew` e o UH-34D pedia `pilot` e `door_gunner`. Esses papéis
  exigem posto 2 ou 3 e um squad pesado, que só abre com 16 jogadores no time (`HEAVY_UNLOCK`);
- o assento sentava pelo toque: no M48 o jogador caía no lugar que encostasse ("MUNICIADOR ·
  Passageiro") e não havia como escolher;
- passageiro não atirava, e a M60 da cúpula do M48 não tinha botão.

**Regra de papel** (`Roles.vehicleSeatRole`, aplicada no servidor):
- carro e caminhão: qualquer um do lado;
- blindado e anfíbio: motorista e atirador pedem tripulante; comandante, municiador e tropa não;
- helicóptero: só o lugar do piloto pede piloto.
- Faltou o papel e há vaga (mais lugares que pedem o papel do que gente com ele), o painel oferece
  "Trocar para Tripulante/Piloto e entrar". Vale até morrer (atributo `VehicleCrew`), sem mexer no
  squad, na arma nem no posto.

**Painel** (`Controllers/VehiclePrompt`, ProximityPrompt `VT65Embarcar` em estilo próprio):
- perto do veículo do próprio lado: cartão com o nome e os lugares livres; segurar X (F) por 0,4 s
  ou clicar/tocar abre o painel;
- lugares em ordem (Motorista ou Piloto, Atirador, Comandante, Municiador, Carona, Tropa), livre,
  ocupado ou "trocar p/ tripulante"; direcional + A, B fecha;
- dentro, segurar Y (C) abre o mesmo painel: trocar de lugar, sair e, tombado ou preso, desvirar;
- o assento não senta mais pelo toque (`CanTouch` false); o servidor valida tudo (`Vehicle_Board`)
  e explica a recusa (`Vehicle_Notice`).
- O lugar fica embaixo do olho medido na malha: a cabeça de quem está sentado é a da câmera, e quem
  sai é posto ao lado do veículo, fora do chassi.

**Atirar de dentro:**
- lugar aberto (caçamba do M35, M151, teto do LVTP-5, escotilha do comandante do LVTP-5, portas do
  UH-34D, aba de trás da Peugeot) usa a própria arma, só em 1ª pessoa e no ângulo do lugar
  (`Vehicles.inArc`): portas ±70° do lado, caçamba ±95°, teto para qualquer lado;
- fechado (motorista, municiador, cabines) não atira; a M60 da cúpula do M48 ganhou o gatilho (RT).
- `WeaponController` só recebe o gatilho e a recarga pelo Bus e confere o atributo local
  `SeatFire`. O servidor (`CombatService`) aceita o tiro sentado como a pé: o ângulo é conferido
  só no cliente.

**UH-34D:** o voo já existia; o que impedia era o papel. Estabilizador ligado por padrão (nivela,
segura o pairado; A segurado ou R desliga); no chão, sem coletivo pedido, fica logo abaixo do
pairado e só decola com Espaço/RT.

**Carros** (medidas dos scripts do Blender, rodas pelo nome das peças, substituto em peças até o
modelo subir; massa, potência e velocidade "a conferir"):

| Carro | Lugares | Estrada / terra batida / capim / arrozal (km/h, medido no teste) | Raio |
|---|---|---|---|
| M151 (EUA) | motorista, carona e 2 atrás | 105 / 84 / 53 / 14 | 5,4 m |
| M35 (EUA) | motorista, carona e 12 na caçamba | 90 / 72 / 45 / 9 | 10,9 m |
| Peugeot 403 (VC) | motorista, carona e 6 sob a lona | 114 / 92 / 57 / 15 | 5,2 m |

- Rodas: sem giro parado; curva pelo raio mínimo até a aderência lateral; tração só atrás na
  Peugeot. Tudo PLACEHOLDER de engenharia (`VehicleDrive.GROUND_WHEELED`, `DRIVE`).
- Estrada de terra do mapa (terreno `Ground`): chão novo `dirt`; o M48 vai a 43 km/h nela. Os outros
  números da D-86 não mudaram.
- Bots não dirigem os carros ainda (`VehicleService.seat` esconde o motorista): o `BotDriver` foi
  feito para lagarta.

**Não prender:** veículo tombado ou preso (motor acelerando e parado por 3 s, atributo `Stuck`)
mostra "PRESO: segure Y e escolha Desvirar"; o servidor levanta 1,5 m e põe em pé, um a cada 8 s.

**Ganchos só no Studio:**
- `VT65DevDrive = "m151"` (ou qualquer ficha) senta no motorista; sem veículo livre, faz um à frente;
- `VT65DevVeh = "m35"` faz o veículo à frente; `"todos"` faz um de cada; `"tombar"` deita o mais perto;
- `VT65DevMov = "veiculo"` liga a leitura do motorista no Output.

**Não testado no Studio:** painel, assento sem toque, lugar no olho medido, voo, tiro de dentro,
rodas girando, desvirar.

## D-101 — v37: STARLITE: Vietnã 1965 (2026-11-12)

O dono jogou a v36 e mandou uma lista longa; liberou testar e publicar e escolheu o nome
**STARLITE: Vietnã 1965**. Esta entrada junta o que não tem decisão própria (números e fontes nos
relatórios de cada parte, no código e nos testes).

- **Armas** (`Shared/Gatilho`, `CombatService`, `tests/luau/armas`):
  - **Por que não atiravam:**
    - SKS e pistolas: a cadência do semi contava a recarga;
    - granadeiro: o servidor só municiava a 1ª arma;
    - automáticas: o servidor media a cadência pela chegada do pacote e recusava 26% da rajada da M60.
  - **Seletor:** M60, RPD e Tipo 56 com automático; M14 no semi, com o automático só no papel novo
    **Fuzileiro automático** (EUA, 1 por squad, bipé M2; FM 23-8).
  - **Mira:** a mira fica mais perto do olho.
  - **Snipers:** M70 com Unertl 8x (EUA) e Mosin 91/30 com PU 3,5x (VC).
  - **Explosivos:** M79 voltou; napalm.
- **Carregamento e telas:** novo estilo escuro, baseado na primeira tela de carregamento. Em resumo:
  - bandeiras na escolha de idioma;
  - tela de baixa com renascer aqui (créditos ou Robux) e atalho para a loja;
  - VC sempre vermelho e EUA sempre azul;
  - barra de captura;
  - marcas na carta (a do líder vale para o squad);
  - coluna de comandos;
  - a roda do LB/RB não fecha mais sozinha.
- **Nascimento:**
  - espera de exatamente 10 s;
  - nascer ao lado de um companheiro do squad (regras em `SpawnRules.MATE`);
  - bots completam o squad do jogador até 4;
  - túnel avançado fixo do VC (Offensive: contato em 30 s).
- **Comunicação:**
  - texto por proximidade (40 m), squad e time (TextChatService);
  - voz por proximidade e rádio do squad (API de áudio);
  - o dono precisa ligar a voz nas configurações da experiência.
- **Eventos da partida** (`EventosService`):
  - apoio naval, ataque aéreo, inserção de UH-34D no minuto 1, morteiro do VC, medevac, depósito e
    contra-ataque, a cada 2–3 min;
  - métrica do primeiro contato (`ContatoService`).
- **Bots:** nível médio de verdade (a 100 m acertam 4% em 3 s, eram 51%), visão curta na vegetação,
  avançam em lances e não mostram mais o nome.
- **Mapa:**
  - diques viraram cômoros de até 0,5 m;
  - arrozal −87%;
  - objetivos e o QG do VC mais ao centro;
  - o morro de 34 m foi deslocado 76 m a leste e 27 m a norte, com a vila nova Xóm Gò (48 casas)
    em cima: deformação pedida pelo dono;
  - 2,8 km de estrada principal;
  - iluminação ShadowMap (era Future), mais leve.
- **Volta diária e Robux** (`CampanhaService`, `Shared/Missoes`, `Temporada`, `Mercado`, `Reforcos`,
  `Medalhas`, `Vantagens`):
  - missões diárias e semanais;
  - Passe de Campanha de 50 níveis;
  - mercado do dia;
  - reforços de XP;
  - Pacote de Recruta;
  - medalhas e cartão do jogador;
  - 7 vantagens compradas com teto de +12% (decisão do dono).
  - Sem caixa-surpresa paga.
  - 17 itens criados no Roblox (`Commerce.IDS`).
- **Testado no Studio:**
  - o servidor sobe sem erro de script;
  - terreno em 29 s;
  - 1.319 modelos de arte;
  - lobby, idioma com bandeiras, carta e inserção;
  - nascer em campo com 1,98 m e três bots no squad.
- **Não testado:** tiro de cada arma em jogo, veículos pilotados, voz, eventos ao vivo.
- **Falta:**
  - o terreno ficou mais lento (29 s, eram 7 s);
  - 18 construções acusam o chão a mais de 0,6 m do patamar;
  - com um controle ligado, um clique de mouse pode valer como o A do cursor virtual (trocou o
    idioma no teste).

## D-102 — Soldados no formato do Front 44: boneco de bloco (2026-11-12)
**Pedido do dono:** "faça os personagens do mesmo formato do Front 44".

**O formato do Front 44 hoje** (`ServerScriptService/F44/Main.server` e `Characters`, `Config.Bodies`):
desde a 0.28.0 (a D-102 de lá, "voltar com os bonecos do roblox") `Blocky = true` e `Realistic = false`.
O soldado é o **boneco de bloco clássico do R15**: tronco, braços, pernas e cabeça padrão (0), as
escalas de altura, largura, profundidade e cabeça **iguais** (1 lá; tipo de corpo e proporção 0),
cabeça de bloco com o rosto em decalque (o do avatar do jogador; o bot fica com o rosto padrão), pele
lisa na cabeça e nas mãos (tons do claro ao escuro), farda em Shirt/Pants clássicos com as peças em
tecido, botas escuras, capacete de malha própria ajustado à cabeça e equipamento em peças por cima. O
boneco tem 5 studs (~1,4 m na escala da arma; lá a arma em 3ª pessoa é reduzida). Os soldados
realistas (malha do Sketchfab cortada nas 15 partes, Avatar Setup com FACS e os rostos pintados do
`tools/make_faces.py`) estão **desligados** lá.

**O que mudou aqui (`Shared/Corpo`, `Characters`):**
- corpo padrão = **"bloco"** (`Corpo.FORMATO`): peças e cabeça padrão, as quatro escalas iguais a
  **1,25 × K = 1,4286** (as proporções do boneco do Front 44 na escala do soldado de 2 m). Altura
  **2,04 m** (a cabeça de bloco é 4 cm mais alta que a do "Man"); dá para ficar nos 2,0 m, então a
  altura da D-98 ficou;
- **0,80 m de ombro a ombro** (antes 0,64 m): o tronco de bloco tem 2 studs de largura por 5 de altura.
  Tudo que se ajusta à caixa das peças acompanha (equipamento do `Gear`, colete, capacete, ghillie); o
  fuzil a tiracolo vai para fora junto (`Corpo.KX`, `PostureController`);
- **cabeça de bloco** (1,5 × K de lado, 0,48 m): o capacete cresce com ela, como no Front 44;
- **pele lisa** na cabeça e nas mãos, **tecido** nas peças da farda; tons por lado (`Corpo.PELE`: 5
  nos EUA, do claro ao escuro; 4 no VC);
- **rostos de época** em decalque (`tools/rostos/make_rostos.py` → `assets/rostos`, 12 por lado):
  olhos, sobrancelhas, nariz e boca sérios; barba por fazer, bigode, olheira, sujeira ou cicatriz em
  alguns; a mesma geometria para os dois lados (sem caricatura). Ids em `Corpo.ROSTOS` (0 até subir;
  sem eles fica o rosto padrão do Roblox, como nos bots do Front 44);
- jogador, bots e prévias (lobby e loja) passam todos pelo `Characters.describe`/`dress`; o
  `SoldierPreview` enquadra pela caixa do modelo. O "man" fica de reserva (`Corpo.FORMATO = "man"`).
- Fica tudo o que é nosso: fardas de 1965 (moldes v3), capacetes, kits, skins, ghillie, carta, pegas
  e animações (gravadas no esqueleto do bloco do R15, o `tools/anim/r15.py`; agora o corpo é o mesmo).

**O que olhar no Studio:** altura (`AlturaM` ~2,04), largura nas portas e nas entradas dos túneis
(0,8 m de ombro), capacete na cabeça de bloco, fuzil a tiracolo e mãos na carta, caixa de acerto da
cabeça (maior que a do "Man"), o rosto padrão até subir os decalques.

**Não testado no Studio.**

## D-103 — Veículo ao nascer: comprar na carta e ele sai ao seu lado (2026-11-12)
**Pedido do dono:** "coloque a opção de comprar um veículo quando nascer e ele spawnar do seu lado".

**O que se compra** (`Shared/CompraVeiculo`): só viaturas sem arma montada. EUA: M151 e M35; VC:
Peugeot 403. **Blindado e helicóptero ficam fora**: os EUA já têm 6 nos depósitos (renascem em
180 s) e o VC de 1965 não tinha nenhum; vender mais seria comprar vantagem contra um lado sem resposta.

**Preços (PLACEHOLDER, a ajustar no teste):**

| viatura | CI | Robux sugerido | produto (`Commerce.IDS`) |
|---|---|---|---|
| M151 MUTT | 150 | 15 | `PRODUCT_VEH_M151` = 0 |
| caminhão M35 | 250 | 25 | `PRODUCT_VEH_M35` = 0 |
| Peugeot 403 | 150 | 15 | `PRODUCT_VEH_PEUGEOT403` = 0 |

ID 0 = o botão de Robux não aparece (o de CI funciona). Catálogo próprio `Commerce.VehicleProducts`,
fora do `Commerce.GAMEPLAY` (a lista da D-72 continua com 3). Pela taxa do pacote de 500 CI = 5 R$,
15 R$ valem 1.500 CI: o Robux aqui é conveniência e sai mais caro que o CI (decisão de preço do dono).

**Regras (PLACEHOLDER, testadas no Lune, `tests/luau/compraveiculo.luau`):**
- um comprado vivo por jogador; **6** comprados vivos por lado ao mesmo tempo; **120 s** entre duas
  entregas do mesmo jogador;
- abandonado **90 s** (ninguém dentro e nenhum jogador vivo a 30 m) some; destruído não volta e não
  tem reembolso; não renasce em depósito;
- só sai no **QG, reunião de setor ou reunião avançada**; em túnel, no companheiro, no ponto do squad
  ou onde caiu o pedido fica para a próxima inserção (nada é cobrado);
- bots não compram (o remote é só de jogador).

**Entrega e cobrança (`CompraVeiculoService`):** o pedido é armado na carta (morto) e nada é
cobrado. Ao nascer, o servidor procura o lugar a **4-10 m** do soldado (centro da caixa; folga de
1,5 m até ele), ao lado primeiro: raios no chão sob a caixa inteira (terreno ou estrada, sem água,
lama nem arrozal alagado; desnível ≤ 0,6 m e no nível do pé ±2 m), caixa livre de casa, árvore,
veículo e gente, dentro do mapa, sem teto em cima do soldado. O veículo fica **virado para o
objetivo** do lado (`Front.objective`; sem partida, o QG inimigo). Achou: em CI cobra
(`spendCredits`) e entrega; em **Robux o prompt só abre com o lugar achado e reservado** (90 s). Sem
lugar: avisa e não cobra.

**Recibo (`CommerceService.vehicleReceipt`):** uma vez por PurchaseId (`applyReceipt`). Reserva
ainda valendo: o recibo vira o veículo. Senão (morreu, reserva venceu, recibo repetido noutro
servidor): vira CI no perfil na mesma gravação, `max(preço em CI, Robux gastos × 100)`. Recibo
repetido não entrega nada.

**Tela (`Controllers/CompraVeiculo.client`):** cartão escuro na margem direita da carta de inserção
("A PÉ" ou a viatura, título Oswald, faixa da cor do lado); o painel lista as viaturas do lado em CI
e em Robux com o motivo quando não dá (falta CI, espera, já tem um, lado no teto). Controle: **X**
na carta abre (o X não marcava nada na inserção; a dica do rodapé virou "Levar veículo"),
direcional + A escolhe, B fecha; mouse e toque: clique no cartão. Gancho único na `DeployScreen`:
`Bus.fire("insercao_painel", …)` no desenho da pasta.

**Ganchos de Studio:** `workspace:SetAttribute("VT65DevCompra", "m151")` (em campo: procura o lugar
e entrega sem cobrar, e escreve a distância ou o motivo; morto: arma o pedido sem cobrança),
`"m151:ci"` (pedido de verdade em CI), `"abandono"` (os comprados somem em 5 s), `"estado"`.

**Não testado no Studio** (nem a compra em Robux, que precisa dos produtos criados).

## D-104 — Veículos do Blender na medida real, em peças (lote dos _v2, 2026-11-12)
Os 7 modelos novos do Blender estão publicados (`AssetIds.Models`): `m48a3_v2`, `ontos_v2`,
`lvtp5_v2`, `uh34d_v2`, `m151`, `m35`, `peugeot403`. Os antigos estavam 10 a 35% fora da medida.
- **Modelo:** `Vehicles.MODEL`/`modelKey` (as chaves antigas ficam com os modelos velhos). O
  substituto em peças dos carros só sobra se o modelo não carregar (atributo `ArtPlaceholder`).
- **`VehicleDrive.ART` nova** (tabela do `assets/blender/RELATORIO.md`): caixa, lagarta (laço:
  M48 49,15, Ontos 28,81, LVTP-5 65,84 studs), escapamentos, olhos, tropa, rotores e as juntas
  (`pivots`) de cada peça móvel. Frente +X do GLB, esquerda −Z, pivô no centro da caixa no chão;
  depois do importador, nariz em −X: giro do chassi −90° nos 7.
- **Peças móveis em Motor6D** (`VehicleService.artJoints`): Torre (giro em Y) e Cano (elevação, preso
  na Torre); RotorPrincipal com as pás `Pa_1…Pa_4` soldadas no cubo; RotorCauda; `Roda_*` (também as
  da lagarta) na ArtRoot; escotilhas, portas, tampa traseira, para-brisa e volante na junta do
  relatório (paradas). O `VehicleFx` gira as rodas (cada uma no raio dela e na velocidade do lado),
  os rotores (as pás de peça somem; fica o disco de desfoque), o volante na coluna e a torre e o cano
  para a mira do atirador (`AimYaw`/`AimPitch` no veículo, do tiro e do `Vehicle_Aim` ~8/s; giro na
  velocidade da ficha). Elevação: M48 −9°/+19°, Ontos −10°/+20°, cúpula do LVTP-5 −15°/+45°
  (PLACEHOLDER). As faixas animadas da lagarta continuam por cima da `Esteira_E/D` parada.
- **Assentos:** os carros agora sentam no olho medido (como os blindados). UH-34D: os 8 da tropa
  dentro do porão (antes fora da fuselagem). Peugeot: o olho desce 0,30 stud (8 cm): com o do
  Blender a cabeça do soldado de 2,0 m batia 9 cm no teto; fica ~2 cm abaixo e o corpo se encolhe no
  banco. M35 (19 cm) e UH-34D (4 cm) como estão.
- **ArtBudget:** os 7 como "hero", triângulos do `metricas.json` (14.358, 9.938, 14.009, 4.794,
  3.362, 8.012, 4.526).
- **Atenção (D-102):** a folga do teto acima é do corpo "Man" de 2,0 m; o boneco de bloco tem a
  cabeça maior. Conferir no Studio a cabeça no teto do UH-34D e do Peugeot.

**Ganchos de Studio:** `VT65DevVeh = "todos"` (um de cada), `"pecas"` (por veículo: modelo, juntas
criadas e peças móveis que o importador não trouxe), `"mira"` (torre e cano de todos a 40° e 10°),
`VT65DevDrive` com cada ficha.

**Não testado no Studio** (importador com nós em várias peças, pivôs e sentidos de giro).

## D-105 — Celular e tablet, bases dos dois lados e vila de casas únicas (v38, 2026-11-13)

**Celular e tablet** (Parte 13 do dono; `ToqueHud`, `Shared/Toque`, testes `toque`, `toque_telas` e
`toque_veiculo`):
- **Base técnica:**
  - tela na horizontal (`LandscapeSensor`);
  - `DevTouchMovementMode = Scriptable`, sem o analógico e o pulo do Roblox;
  - o controle conectado vira a entrada principal;
  - cada toque pertence ao botão onde começou;
  - perder o foco solta tudo.
- **HUD de dois polegares:**
  - analógico flutuante e proporcional; a borda corre e o cadeado trava a corrida;
  - tiro grande que gira a câmera; agachar tocando, deitar segurando;
  - botões em tamanho físico (mínimo de 9 mm, tiro de 16 mm). O DPI é estimado: PLACEHOLDER até
    medir em aparelho real.
- **Mira:** giroscópio (desligado, só mirando, sempre) e sensibilidades separadas. A volta ao ponto de
  mira é 25% mais rápida no toque; o chute de cada tiro é o mesmo.
- **Ações e telas:**
  - rodas em volta do polegar e botão contextual com anel de progresso;
  - seletor e alça pelo cartão da arma;
  - mapa com pinça e INSERIR;
  - nas fichas, o primeiro toque mostra e o segundo confirma.
- **Veículos:** motorista, atirador, piloto (coletivo e pedais, estabilizador ligado) e atirador de
  porta, com LUGAR e SAIR.
- **Editor de HUD:** mover, 60–150% e transparência; layouts de 2 polegares, 3 e 4 dedos, canhoto e 3
  espaços próprios na conta.
- **Desempenho e outros:**
  - perfil de celular sem mexer na vegetação que esconde nem nos soldados;
  - "economia de bateria" (o script não trava o fps; só reduz o gráfico);
  - vibração por `HapticEffect`;
  - reconexão.
- **Não testado em aparelho real:** tamanho físico, giroscópio, foco em ligação e notificação, fps,
  calor e memória.

**Bases** (`tools/bases_dados.py` gera `Data/Bases.luau` dos layouts do Blender, relativos ao QG):
- **EUA:** 85 objetos em ~91 x 122 m (barracas GP, comando, refeitório, garagem, torre, portão,
  concertina, helipontos AM-2, baias, estande de tiro, depósito de combustível).
- **VC:** 34 objetos em ~47 x 39 m sob a mata (abrigos, cozinha Hoàng Cầm, rede, armeiro, estande e
  abrigo do carro).
- **Colisão:** nós `Colisao_*` com material; a lona deixa passar a bala (`Canvas = 0,9` no `PASS`).
- **Estacas punji:** −20 de vida e mancando, não no VC, a cada 3 s no máximo (PLACEHOLDER).
- **Raias:** cada lado tem a própria raia de tiro dentro da base; a de antes atravessaria as barracas.
- **Veículos:** os depósitos usam as vagas das bases (`VehicleService.DEPOTS`):
  - EUA: 2 LVTP-5, 1 M48, 1 Ontos, 2 UH-34D, 1 M151, 1 M35;
  - VC: 1 Peugeot 403 (eram 2).

**Vila Xóm Gò:**
- 38 das 48 casas são os 10 modelos únicos do Blender, com interior e porta de 2,30 m; as outras 10
  usam as casas variadas de antes até as casas 11 e 12 existirem;
- duas casas a menos de 30 m nunca repetem o modelo.

**Rostos:** os 24 rostos de época (D-102) estão publicados; o `Corpo.ROSTOS` guarda os IDs de imagem
lidos no Studio.

**Ghillie v2:** substitui a v1 com o mesmo encaixe.

## D-106 — Blindados de bot saindo das baias e chegando ao objetivo (v38, 2026-11-13)

O teste da v38 no Studio achou o M48 e os LVTP-5 de bot parados na base: com as baias da D-105, a
rota ia reto para oeste, atravessava o talude e empacava. Depois disso, cada trecho do caminho
mostrou o próximo problema. O que mudou:
- **Vaga e saída:** as baias e a garagem abrem para o sul. O veículo nasce de frente para a boca
  (`DEPOTS.yaw`) e o bot sai em linha reta até a faixa livre (`exitM`, 13–15 m) antes de pedir rota.
  Na volta, para na frente da baia (a grade marca a baia inteira como obstáculo).
- **Picape do VC:** fica na frente do abrigo de palha, de frente para a trilha. O poste da cumeeira
  no meio da boca do abrigo não deixa carro nenhum sair de dentro dele.
- **Portão:** o braço erguido da cancela e o garfo de apoio ficam sem colisão. O vão do portão é
  de 21,6 studs; com os dois, sobravam 10,8 para um M48 de 13.
- **Grade de rota:**
  - concertina, mastros, gerador, tambores e reboque d'água contam como obstáculo (a rota cortava a
    cerca em vez de usar o portão);
  - o tronco de cada árvore com colisão (2.214 no mapa) barra só o veículo (marca de sebe); a mata
    era só "cara" e o tanque encalhava entre os troncos;
  - obstáculo aprendido: o veículo preso contra uma peça fixa fora das bases e da estrada marca a
    célula dela (teto de 300).
- **Estrada:** os pontos da rota de veículo que caem no leito vão para o eixo da estrada. Os centros
  de célula (16 studs) punham o casco 8 studs fora do eixo, contra a guarita.
- **Água rasa:** o teto de velocidade que o bot lê trata lâmina rasa como lama, igual à física. Numa
  lâmina de 3 cm o M48 lia teto 0 e parava de vez.
- **Encalhe:** "preso" usa a velocidade real do casco. A do motor oscila contra o obstáculo e a ré
  nunca acontecia. Na 3ª ré no mesmo lugar, o bot desencalha como o jogador (sobe e recua 6 m). A
  menos de 40 m do destino, fica ali mesmo (o transporte desembarca a tropa).
- **Aterro na saída da base:** 20 m fora do portão dos EUA corre um riacho de 2 m de fundo, com
  barranco e lama. Na ida o blindado passava no embalo; na volta não subia. Pelo eixo da rua da
  base, a primeira vala (até 40 m de boca) vira um aterro de terra batida da largura da rua mais
  1 m. O leito da vala até 110 m para cada lado fica fechado para veículo de bot.
- **Resultado no Studio:**
  - o M48 chega ao ponto de apoio e fica;
  - o LVTP-5 leva o squad, desembarca e volta para a baia;
  - testado em dois objetivos (oeste e sudoeste).
- **Não testado:** objetivos do VC, o Ontos (fica sem tripulação no teste) e o LVTP-5 nº 2.

## D-107 — Lista do dono de 12–13/11: tiros, morte, bots, movimento, itens, telas e celular (v39, 2026-11-13)

Pedidos do dono (lista de 12/11 e fotos do celular de 13/11), feitos em 8 frentes paralelas. Os
comentários do código citam "D-107" para tudo isto. Números novos são PLACEHOLDER até o Studio e o
jogo publicado confirmarem.

**Combate** ("os tiros não estão acertando", "concerte o hitbox", "3 ou 4 tiros para morrer",
"mais difícil de morrer", "mostre quando acerta", "melhore o áudio das armas"):
- **Causa dos tiros que não acertavam:** o `Combat_Fire` conferia o relógio do tiro
  (`GetServerTimeNow`, ~1,8 bilhão de s) e a semente (até 2^32) com um limite de 1e7. Todo tiro de
  jogador era descartado desde 2026-11-09: sem dano, sem munição descontada no servidor, sem tiro
  visto ou ouvido pelos outros e sem supressão dos bots. Corrigido (`Ballistics.clockOf`/`seedOf`).
- **Hitbox:** caixas do tamanho do que se vê (`Shared/Hitbox`): cabeça de bloco pela malha,
  capacete conta como cabeça e colete como tronco. O atirador avisa o acerto que viu
  (`Combat_Claim`) e o servidor confere a trajetória da semente, o caminho livre e a folga pela
  velocidade do alvo.
- **Dano** (`Medical.shotDamage`): arma × zona × energia restante. No tronco: fuzil 3–4 tiros,
  metralhadora 4, pistola 4–5, precisão 2. Fuzil na cabeça mata; membro 5 ou mais.
- **Marcador de acerto** só para quem atirou (`Combat_Confirm`, `Acerto.client`): número do dano e
  som leve; latão na cabeça, vermelho no abate. Exceção ao "sem hitmarker" da D-25.
- **Som das armas** em camadas (`Shared/SomArmas`), com cauda pelo lugar (aberto, mata, vila,
  túnel), estalo e zunido da bala, ferrolho e estojo.
- **Ritmo:** recarga do fuzil 3,0 → 2,4 s (bots iguais); ao ombro em 16/massa; recuo volta mais rápido.

**Morte e feridos** ("os feridos estão de pé", "os mortos não somem nem ficam deitados",
"animação de morte", "permita desistir sempre"):
- Caído deita de costas (servidor pela junta Root; clientes com pose de ferido, queda de 0,7 s);
  reanimado levanta agachado. A HumanoidRootPart do deitado sai das consultas de bala.
- Morte com boneco de pano no servidor, juntas limitadas, sem voar nem atravessar o chão.
- Corpo fica 25 s e some em 2,5 s; teto de 24 corpos.
- Desiste a qualquer hora (`Medical.giveUpAfter = 0`).

**Bots** ("só vejo 10 bots, cadê os 50?", "bots não avançam", "não precisam seguir o líder"):
- `BotService.fill()` dava 10 (15 no Studio). Agora completa até 50 por lado, 2 por segundo, com
  teto pelo Heartbeat do servidor: para abaixo de 45 Hz, tira abaixo de 35 Hz, piso de 12
  (`BotCap`, `BotHz`).
- Pensamento por distância do humano (0,3 / 0,6 / 1 s) num orçamento de 2,5 ms por quadro; longe
  de humano andam em linha simples.
- Cada squad tem papel na frente: ataque; 25% guardam o setor ameaçado, 50% com inimigo no ponto.
  Quem ataca avança em lances de 15–25 m; preso no máximo 5 s; o squad não espera o líder.
- Os bots do squad do jogador não o seguem mais; a marca na carta vale 2 min (45 s no lugar).
- Captura até 3x com 9 ou mais atacantes (setor inimigo em 60 s).

**Movimento e 3ª pessoa** ("copie a movimentação do Front 44", "ajeite a pegada e o tamanho da
arma", "capacetes bugados", "telas tremendo", "botão de 3ª pessoa"):
- Velocidades do Front 44 (mesma escala): trote 3,92, corrida 5,88, agachado 1,96, rastejar 1,12,
  mirando 2,52 m/s; VC ×1,12. Arrancada 40 → 30 m/s², parada 40, pulo de 0,825 m, deslizar
  agachando correndo (0,8 s), posturas mais rápidas, menos balanço de câmera.
- Arma em 3ª pessoa com a pose do Front 44 (`Shared/Pegada3P`), IK de dois ossos depois das
  animações, arma no tamanho real, mão de bloco a 0,55 da largura.
- Prévias remontadas pelas juntas (fora do Workspace elas não se resolviam); capacete nas
  proporções do Front 44.
- 3ª pessoa: tecla O, → segurado no D-pad, e no toque pelo menu.

**Itens** ("não consigo puxar arma e selecionar os itens", "arma secundária para todos", "copie a
fumaça do Front 44"):
- Vagas fixas (`Shared/Equipar`): 1 principal, 2 pistola, 3 granada, 4 fumaça, 5–0 itens; teclas,
  roda do mouse, Y e o cartão da arma no toque. A troca usa o saque do Front 44 e todos veem a arma
  na mão (`ArmaNaMao`).
- Pistola para todos (M1911A1 / Tipo 54). Comandante, corpsman e morteiro ganharam arma longa.
- Granada na mão: o gatilho tira o pino e arma; soltar lança; mirando, vai por baixo.
- Fumaça do Front 44: 7 sopros cortados por parede, abre em 1,5 s, 60 s de duração, estado no
  servidor e desenho em cada cliente, véu dentro da nuvem.
- Recarga automática no gatilho vazio; no toque e no controle, também ao esvaziar.

**Telas** ("Jogar agora", "melhore a tela de morte com a opção de veículo", "cores nos botões de
compra", "gostava mais da tela de carregamento antiga"):
- JOGAR AGORA (mesa, carta, baixa, menu, carregamento): lado, squad e papel da última escolha
  (perfil `unit`) e o último ponto ou o melhor (squad > reunião > QG; 1 s de espera = 18 studs).
- Tela de baixa: o soldado caído no chão (`CenaBaixa`); RENASCER é o jogar agora; COM VEÍCULO pelo
  pedido da D-103; desistir sempre visível.
- Cores de compra (`UiKit.PAGAR`): Robux verde, créditos âmbar, grátis oliva, apagado escuro.
- Carregamento com o visual do `b85331e` e o carregamento completo da v37.

**Celular** ("comandos do teclado no celular", "deixe a tela limpa", "o resto automático"):
- Fixos: analógico, FOGO, MIRA, PULAR, AGACHAR, ITEM, COMUNICAR, MAPA e MENU; o cartão da arma troca
  de arma. RECARGA, GOLPE, FÔLEGO, BANDAGEM e RÁDIO só aparecem quando servem.
- Automáticos com opção: recarga, transpor, inclinar na quina, respiração na luneta, pegar
  munição e caixote, assistência de mira. Tiro sozinho existe e vem desligado.
- Sem dica de tecla no toque; o painel de teclas só aparece com teclado ou controle. O HUD desenha
  em zonas livres (`Toque.ZONES`), testadas de 16:9 a 20:9 e no tablet.

**Veículos** ("helicóptero sem som", "veículos prontos de qualidade"):
- O UH-34D era mudo: o laço nunca foi publicado (ID 0). Agora tem sons próprios em camadas
  (`tools/sons_veiculos.py`): rotor, motor radial, vento, lagarta, jipe e caminhão. O rotor se ouve
  a 1,5 km e o helicóptero fica sempre replicado.
- O heliponto fica a 16 m da borda leste: o UH-34D nasce de nariz para oeste.
- Prontos da Creator Store avaliados (UH-1B, UH-1D, M48A1, M48A5, Ontos, jipe, M35, F100): nenhum
  entrou. Os bons têm origem duvidosa e modelo de terceiros não carrega no jogo publicado.
- No toque: só analógico, coletivo, tiro, LUGAR e SAIR; estabilizador sempre ligado.

**Ambiente** ("retire o vento, está pesando"): `GlobalWind` zerado e o arroz parou de balançar.

## D-108 — Classes simples, Suporte com caixa de munição, espingarda, armas maiores e nada flutuando (v40, 2026-11-13)

Pedidos do dono de 13/11 (14:00–14:05), feitos em 4 frentes. Números novos são PLACEHOLDER.

**Classes** ("faça classes mais simples, tem muitas"; "você já fez a sniper e a classe de sniper?"):
- De 16 papéis em 7 unidades para 8 papéis em 2 unidades (comando e infantaria). O squad de 6 tem
  Líder, Médico, Suporte, Metralhador, Antitanque e Atirador de elite (1 de cada) e Fuzileiros.
  São 9 squads por lado (55 vagas). Só o comandante pede posto (3).
- O que foi juntado: o granadeiro vira a M79 do fuzileiro; o fuzileiro automático vira a M14 do
  metralhador; engenheiro, sapador e morteiro viram o Suporte; o rádio vai para o líder; o
  observador vira o atirador de elite. Tripulante e piloto são só lugar de veículo (D-100).
- Arma principal à escolha no cartão do papel ("⇄ ARMA", vale no próximo nascimento).
- Papel e unidade antigos migram (`Roles.migrate`, `migrateUnit`): perfil, JOGAR AGORA e bots.

**Caixa de munição do Suporte** (`Shared/CaixaMunicao`, `CaixaMunicaoService`):
- Prévia verde ou vermelha com a malha do Blender e a pegada no chão. Até 4 m, rampa até 35°, sem
  água. Uma por suporte, outra só depois de 30 s.
- Quem é do lado e passa a 3 m pega sem tecla: reserva cheia, +1 granada e +1 foguete do
  antitanque. Cada um pega a cada 20 s; 8 pegadas; some em 4 min. XP "Reabastecimento" para quem pôs.
- Ícone ▣ com o estoque para o time (4 a 250 m) e marca na carta. Bots têm reserva de munição, vão à
  caixa e o bot suporte põe a caixa.
- Arte no Blender: `caixa_municao_us` (caixote verde-oliva com latas M19A1, carregadores de M14 e
  M26, estêncil de 1965) e `caixa_municao_vc` (caixote chinês com carregadores do Tipo 56 e
  granadas de cabo).

**Espingarda** ("faça a arma doze com sons realistas e dano bom"): Winchester Model 12 Trench Gun
(`win12`), a do USMC em 1965 (a Ithaca 37 chegou em quantidade só em 1966).
- 6+1 cartuchos, bomba de 0,7 s, recarga cartucho a cartucho. 9 bagos de 00 por tiro, cada um um
  raio; os bagos que pegam o mesmo soldado somam. Mata em 1 tiro até ~10 m, em 2 a 20–30 m, em 4 a
  50 m.
- Modelo do Blender em 5 peças (Arma, Telha, Culatra, Gatilho, Cartucho), mira de conta medida pelo
  `sight_align` (tipo "conta"). Sons de disparo, bomba e cartucho do Front 44.

**Armas maiores** ("estão pequenas"): `Corpo.ARMA_K = 1,4`.
- Em 1ª pessoa, arma, mãos e itens ficam 1,4x maiores. Mirando, o olho fica 1,4x mais longe, então
  a imagem da mira é a da arma real.
- Em 3ª pessoa a arma engrossa 1,4x e o comprimento fica (`ARMA_COMPRIMENTO_3P = 1,0`): com a coronha
  no ombro, a M60 já usa 96% do alcance do braço. O RPG-2 vai com o tubo no ombro.
- A balística não muda.

**Nada flutuando** ("helicópteros estão flutuando", "conserte tudo que esteja flutuando"):
- O Roblox desenha o chão meio voxel (0,56 m) acima da ocupação linear. O `TerrainBuilder` passou a
  descontar isso (`groundOcc`): construções, chapa do heliponto e pé das plantas deixam de ficar
  enterrados, a lâmina do arrozal fica 10 cm acima do fundo e o riacho volta aos 0,6 m.
- Todo patamar é de terra batida. Objeto sem patamar e planta assentam pelo mais baixo entre o
  plano e o chão real.
- UH-34D: a altura das rodas descontava 1,52 m a mais e o pouso parava a 1,81 m do chão. Abaixo de
  1,5 m, sem comando no coletivo, o helicóptero assenta.
- Gancho de medição: `VT65DevFlutua`.

## D-109 — Bots do Front 44, sem fogo amigo, corrida com a arma de lado, celular sem nada por cima e carregamento do mapa (v41, 2026-11-13)

Pedidos do dono de 13/11 (14:13–14:27, fotos do celular na v39). Feito sem agentes em paralelo.

**Celular: nada em cima de nada** ("botões estão em cima dos outros"):
- Caído no toque, o cartão vai para a zona nova `caido` do `Shared/Toque` (pé da tela, à esquerda do
  DESISTIR, que fica no lugar do tiro). O teste da zona confere só os botões de quem está caído
  (`Toque.ZONE_CTX`). O painel da captura some com o soldado caído.
- Os avisos (Toast) também usam a zona do canto com o soldado caído; antes voltavam grandes ao alto
  do meio, por cima da faixa.
- A faixa da frente sobe para a barra do Roblox ("como era antes"); a bússola vai ao alto.
- Eventos e avisos mais estreitos e encostados no canto esquerdo ("mais para o canto e menor").

**Objetivos A B C D E** (`Front.letra`): setores, faixa, carta, marcadores, relatórios, avisos e
falas. Os nomes no `crop_world.py` e no `MapConfig` começam pela letra. O tradutor ordena os padrões
pelas letras fixas e, no empate, pelos caracteres fixos ("captura A (Colina 43)" não pega o modelo
sem nome).

**Marcador do objetivo** ("esse atacar enorme está atrapalhando"): sem o quadro; a letra grande na cor
do papel e "atacar · 230 m" pequeno, a 45% de transparência.

**Sem a parede vermelha** ("tire essa parede vermelha do jogo"): era o disco do evento (e o da área
marcada), um plano na altura do centro do evento. Com o centro num morro, quem estava embaixo via o
disco acima dos olhos, vermelho até o horizonte. Os dois discos saíram; ficam o marcador e o raio na
carta.

**Sem fogo amigo** ("retire dano aliado"): `Medical.FRIENDLY_FIRE = false` e `Medical.blocked`.
- O `MedicalService.hit` recebe o lado de quem causou o dano. Bala, granada, explosão, napalm, golpe,
  canhão de veículo, artilharia pedida e barragem de evento passam o lado.
- O dano em si mesmo (a própria granada) vale. Dano sem dono (destroço de veículo, armadilha) também.
- Medido no Studio: tiro de M14 a 10 m num aliado deixou a vida em 100; no inimigo, 100 → 62,6.

**Corrida do Front 44** ("quando ele corre a arma fica de lado no corpo"): em 1ª pessoa, correndo, a
arma vai atravessada no peito com a boca para cima e para a esquerda. São os números do Front 44
(`SprintHighPort`): 12 cm para trás, 3 cm à esquerda e 7 cm abaixo; giro de 28°, 28° e 30°; balanço de
15%. Mirando, recarregando, arremessando e sentado, não. A 3ª pessoa já tinha a pose (`Pegada3P.PORT`).

**Bots do Front 44** ("os bots são ruins, copie exatamente os bots do Front 44"): o combate de
`F44/Bots.luau` e `Config.Bots` (v0.30), com distâncias em metros (stud de 0,28 m nos dois jogos).
`BotBrain.F44`:
- ver: cone de 130° ou a menos de 22 studs; até 160 studs (44,8 m), ou menos se a vegetação tapa;
- reagir: 0,45 s × 0,8–1,3;
- mirar: erro máximo de 4,5° que fecha em 1,1° em 1,2 s, ×1,5 andando, +0,008° por stud,
  antecipação do alvo e 18% das rajadas na cabeça;
- atirar: rajadas de 3 a 7 na automática com pausa de 0,25–0,7 s; tiro a tiro no resto;
- mover: de lado 9 studs (troca a cada 1,8–2,6 s); longe (> 70 studs), parado e agachado; recarrega
  num abrigo perto; com menos de 35% da vida, recua 3,5 s;
- sem alvo: investiga o último contato (8 s; quem o acertou, 7 s; tiro ouvido a até 110 studs, 6 s) e
  joga granada em quem sumiu (25%, uma a cada 12 s); depois volta ao objetivo do squad.
- Ficam daqui: navegação, squads, objetivo, veículos, túneis, caixa do Suporte e o orçamento (LOD).
- O combate antigo fica atrás de `workspace:SetAttribute("VT65BotsF44", false)` no Studio.
- Medido (`f44DuelHitChance`, jogador parado, 3 s): 10 m 100%; 25 m 81% (automática) e 50% (semi);
  40 m 34% e 16%; além de 44,8 m não vê. No Studio, o primeiro tiroteio foi aos 46 s, a 29 m.

**Mira do quadril** ("coloque uma mira quando você não está mirando"): a retícula da 3ª pessoa
também em 1ª, com arma de fogo pronta, sem mirar e sem correr. A abertura é a dispersão do quadril
(`Movement.hipSpreadDeg`), que passou a valer em 1ª pessoa (sem ela, mirar não valeria nada).

**Som da arma do tanque** ("a arma do tanque não sai som"): a metralhadora do assento (coaxial do M48 e
M60 da cúpula) atirada pelo jogador não tinha som para ele. O servidor manda o som só para os outros e
o cliente só fazia o clarão. Agora o `VehicleController` avisa o `AudioController`. O canhão de 90 mm
tocava: conferido no Studio (5,0 s, carregado).

**Barracas 1,5x** ("estão muito pequenas"): as barracas dos dois lados (GP média e grande, refeitório,
posto de comando e abrigos do VC).
- `tools/bases_dados.py` (`ESCALA`, `afastar`): cada barraca maior vai à vaga livre mais perto, a
  0,5 m das vizinhas, sem sair da base nem cobrir rua, trilha, pontos de nascer e estande.
- O posto de comando e o refeitório dos EUA mudaram de lugar.

**Nomes das armas** ("coloque o nome certo nas armas certas"): `Weapons.shortName` no cartão, nas
vagas e no aviso de troca.
- As duas Winchester apareciam cortadas e iguais. Agora são "M70 (luneta)" e "Escopeta 12".
- O lançador dos EUA é a "Bazuca M20"; o do VC, o "RPG-2".

**Mais leve** ("jogo está bem pesado ainda"). Medido no Studio com 100 bots: servidor a 60 Hz; o
cliente gasta 2,2 ms por quadro em script. O gargalo é a renderização: 66,8 ms por quadro no PC do dono
na qualidade 1, com 1,3 milhão de índices.
- A pose dos soldados longe da câmera roda em menos quadros: além de 60 m a cada 2 e além de 150 m a
  cada 4; a arma além de 150 m a cada 3. A lista de soldados é montada 4 vezes por segundo, não duas
  por quadro.
- Os laços de som calados ficam pausados.
- O disparo dos tiros de mais de 100 m tem teto de 16 por segundo (eram 33 sons de tiro ao mesmo
  tempo).
- A mata não muda por aparelho (regra da D-82).

**Carregar tudo na tela de início** ("carregue todo o jogo perfeitamente na tela de início"):
- A etapa 7 espera o terreno e a arte do servidor e pede o streaming em volta dos dois QGs e dos
  cinco objetivos. Depois baixa a arte do que chegou. Ao nascer, o servidor pede o streaming em volta
  do ponto antes de pôr o soldado.
- As malhas vão como peça. O id em texto era pedido como imagem: 511 avisos "Asset type does not
  match" que não baixavam nada; ficaram 7, de roupas do catálogo.

## D-110 — Caixa de munição à vista no capim e rodas do UH-34D (v42, 2026-11-13)

Pendentes da v40 e da v41, com o "sim, siga" do dono.

**Caixa de munição no capim alto** (achado da v40: a caixa de 0,54 m sumia no capim do terreno):
- Ao pôr a caixa, o capim do terreno em volta (Grass e LeafyGrass, cerca de 1,2 m para cada lado,
  na grade de voxel) vira terra pisada (Ground), como o napalm faz. A grama animada do Roblox só nasce
  no Grass.
- O terreno fica pisado depois que a caixa some.
- Medido no Studio: Ground sob a caixa e a 0,8 m dela; capim a 2,5 m. Na foto a caixa aparece numa
  clareira.

**Rodas do UH-34D** (o `uh34d_v2` veio do Blender com as duas rodas principais "Roda_E"):
- Na montagem (`VehicleService.artJoints`), a repetida que fica à direita do chassi vira "Roda_D".
  Sem lado claro, ganha um número.
- O giro já pegava as duas (o VehicleFx usa todo "Roda_*"); o nome repetido confundia a medição e a
  depuração.
- No Studio: Roda_E em x = −7,6, Roda_D em x = +7,6 e Roda_Cauda, nos dois helicópteros.

**Fica como está:** o soldado com 2,08 m medidos contra os 2,00 m da D-98. Acertar mexe na escala do
corpo, no alcance dos braços e nas pegadas testadas (`tests/luau/pegada.luau`).

## D-111 — Lote 1 da lista de 13/11 à tarde: abate, Robux, FPS, munição, controle, folhas, sol, recuo e pistola (v43, 2026-11-13)

A lista de 13/11 (14:49–15:22, 30 pedidos) vai em lotes pequenos, um por versão ("faça isso de pouco em
pouco"). A fila completa está no PROGRESS. Este é o lote 1.

**Abate:** a caveira vai para 62% da altura (abaixo da mira) e ganha o nome de quem caiu. O servidor
manda `Combat_Kill { name, w }` para quem levou o crédito; bot usa o `BotName` ("Fuzileiro 23").

**Renascer com Robux:** o botão fica verde vivo do Robux com borda dourada que pulsa. Travado (regra do
setor, espera), fica num verde escuro, sem virar o painel apagado.

**FPS e ping** no canto de baixo à esquerda (`Controllers/Fps`), com a cor pela faixa: ≥ 50 verde,
30–49 latão, < 30 vermelho. Liga e desliga em Configurações > Gráficos (`showFps`, padrão: mostrar).

**Painel de disputa mais baixo:** no PC a 74% da altura (era 66%); no toque, zona `captura` y 0,64–0,86
(era 0,58–0,80).

**Menos recuo:** `RECOIL_DEG_PER_MS` 0,9 → 0,6 (M14 ~1,5° por tiro), volta sozinha 0,75 → 0,85, desvio
para o lado 0,6 → 0,45.

**Pistola útil:** dano 25 → 34 (3 a 4 tiros no tronco até 50 m; 1 na cabeça de perto). Os testes de
dano da pistola mudaram junto.

**Idioma:** o chip da tela de entrada e da mesa só aparece enquanto o idioma está no automático e
some na hora da escolha (`Idioma.soAteEscolher`). O menu do jogo (Configurações) mantém o seu.

**Controle:**
- RB: granada rápida. Apertar puxa; segurando quando ela chega, arma; soltar lança.
- Direcional ↑: tocar troca 1ª/3ª pessoa; segurar troca o ombro.
- Direcional →: tocar marca; segurar abre a roda de comunicação.
- O binóculo fica na roda de equipamento (LB) e na tecla B. O canal de rádio fica na tecla U e no botão
  RÁDIO do toque.

**Tiros nas folhas:** no traçado comum (`Hitbox.trace`, servidor e cliente), peça sem colisão (folha,
cartão de capim, parte visual de modelo com colisão própria) deixa a bala passar, perdendo 2%. A lâmina
do arrozal continua parando. Antes eram 4 peças vazáveis por trecho de voo; na mata fechada a 5ª folha
encerrava o trecho sem olhar o soldado atrás. Agora são 16, e o soldado no trecho é acertado mesmo
assim.

**Sol:** a partida começa às 08:30 (era 07:00, com o sol a 6,2° no olho de quem olha para o leste). No
Studio o sol ficou a 28,3°. O brilho em volta do sol caiu a 1/3 (Glare 0,10), o disco do sol de 16 para
10, os raios de sol e o brilho (bloom) mais fracos.

**Munição no cartão** ("está muito bugado"): o servidor manda a reserva em carregadores, mas o cartão
dividia pela capacidade como se fossem balas. O fuzileiro com 8 carregadores via "1". Agora o cartão
mostra as balas em número grande ("20 /20", vermelho no último quarto) e os carregadores em ícones de
pente com "× 8". Na espingarda, "+N" cartuchos.

**Mão escorregando (D-111):** não reproduzido no Studio. Em 1ª pessoa as duas mãos ficaram paradas no espaço
da arma (variação 0,000 em 147 quadros andando). Nos bots em 3ª pessoa, andando, a mão esquerda ficou
a 2–5 cm do apoio. Falta saber do dono em que vista e em que momento acontece.

## D-112 — Lote 2: tela de baixa com retrato e rótulos claros (v44, 2026-11-13)

Pedido do dono: "esse bot caído na tela de morte está horrível, melhore essa tela, quero mais
intuitivo também".

**Retrato:** o soldado deitado (D-107) dependia de girar cada junta do boneco de bloco e saía quebrado.
Agora é um retrato de identificação (`CenaBaixa.RETRATO`):
- de pé, de frente, do peito para cima (o quadro mostra 42% da altura do corpo), câmera na altura do
  peito, um pouco à direita;
- tom sépia de foto de 1965, luz de cima e da frente, sem o chão de terra;
- juntas no repouso (`POSE_STAND`), sem a arma da mão.
- Usa o manequim do lado (o soldado da mesa). O retrato tirado em vida vinha com o repouso do pescoço
  já inclinado pela mira: no Studio, a cabeça olhava 48° para baixo e o capacete tapava o rosto. Sem o
  manequim, usa o retrato.
- A cena de caído continua no código (`RETRATO = false`).

**Rótulos que dizem o que acontece:**
- "NO MESMO LUGAR" → "RENASCER ONDE CAIU";
- "COM VEÍCULO" → "RENASCER COM VEÍCULO";
- "ESCOLHER NA CARTA" → "ESCOLHER OUTRO PONTO";
- "MESA" → "MENU";
- embaixo do RENASCER: "Você volta em: squad · papel · ponto".

**Ainda na fila do lote 2:** a revisão das outras telas ("uma criança tem que conseguir jogar") e os
bugs visuais que o dono viu (falta a foto de cada um).

## D-113 — Lote 3: veículos sem vidro preto, mais fáceis, helicóptero aberto e bots que não travam (v45, 2026-11-13)

Pedidos do dono: "bots parados nos veículos"; "bots estão se prendendo nos objetos"; "faça os
veículos sem janelas ou coloque elas com um vidro que eu possa ver, pq agora está preto o vidro";
"faça eles mais fáceis de controlar e um pouco mais rápidos"; "no helicóptero faça a parte de trás
aberta onde os passageiros ficam".

**Vidro:** no Roblox cada peça tem uma textura só (o atlas do bake), então o vidro sai opaco e escuro.
Em vez de vidro:
- M151 e M35: o para-brisa fica só com a moldura (muitos rodavam assim no Vietnã);
- Peugeot 403: janelas abertas, com forro por dentro como a cabine do UH-34D (de fora se vê quem
  dirige; de dentro, colunas e teto). O casco do Peugeot fica sem a limpeza de faces escondidas,
  que apagaria o forro e o interior;
- os IDs antigos ficam guardados como `<chave>_vidro`.

**Helicóptero:** o porão da tropa do UH-34D fica aberto também à esquerda (x de 2,15 a 4,25 m, a mesma
altura da porta da direita), sem as 3 janelas daquele lado. Liberdade de jogo: o H-34 real só tinha a
porta da direita. O ID antigo fica como `uh34d_v2_fechado`.

**Direção (`VehicleDrive.GAME`, por cima da ficha, PLACEHOLDER):**
- velocidade máxima: lagarta e anfíbio ×1,2 (M48A3 de 48 para 57,6 km/h); rodas ×1,05 (o M151 já
  fazia 106 km/h pela ficha: agora 111);
- força do motor ×1,3 (arranca mais rápido); freio ×1,25;
- resposta do volante: constante de tempo ×0,6; aderência lateral ×1,25; raio mínimo de curva ×0,85.

**Bots nos veículos (`BotVehicles`, vigia):**
- sem motorista sentado por 15 s, a tripulação se desfaz e todos descem e seguem a pé com o squad;
  no embarque o prazo é de 90 s (o motorista ainda está a caminho; no Studio, a tripulação do Ontos
  ficou mais de 4 min sem ninguém sentado) e o veículo fica 3 min sem tripulação de bot, para a mesma
  tripulação não se formar e se desfazer em ciclo;
- indo para o objetivo ou voltando, se o veículo anda menos de 4 m em 60 s, a tripulação desce e o
  veículo fica 3 min sem tripulação de bot (`BotAbandonedAt`);
- antes, os bots ficavam sentados para sempre (foto do dono: quatro em cima do tanque na base).

**Bots presos (`BotLocomotion`):** a saída de quem trava ganhou etapas:
1. pulo (como antes);
2. passo de lado por 1,2 s (era 0,8 s);
3. ré por 1,0 s;
4. o outro lado por 1,5 s;
5. só então desiste do caminho e pede outro.

**Conferido no Studio (2026-11-13):**
- os 9 veículos nascem com os modelos novos; do banco do motorista do M151 a vista sai livre pela
  moldura; o porão aberto do UH-34D e as janelas do Peugeot aparecem no jogo;
- o vigia agiu sozinho: o Ontos ficou 60 s parado indo para o objetivo e a tripulação desceu. Com o
  chassi de um LVTP-5 preso (Anchored), em 58 s a tripulação desceu (0 sentados) e o veículo ficou
  marcado;
- 0 erros de script.

**Não testado:** o prazo de 90 s do embarque ao vivo; dirigir com teclado ou controle de verdade (a
direção nova só foi medida no Lune: M151 a 111 km/h na estrada, M48A3 a 57,6 km/h); o bot preso
num objeto saindo pelas etapas novas.

## D-114 — Lote 4a: mapa de 500 x 500 m, objetivos perto do centro e 40 x 40 (v46, 2026-11-13)

Pedidos do dono: "acho que podemos diminuir ainda mais o mapa, talvez 500m x 500m" (confirmado:
"Sim, 500 m"); "deixe os objetivos mais perto do centro do mapa, alguns estão lá embaixo"; "faça o
jogo 40x40 jogadores". Substitui o tamanho da D-95. As cabanas e vilas maiores e a terra batida nas
ruas ficam para o lote 4b (v47).

**Recorte** (`geo.PLAY_ING`): E 269,66–270,16 x N 1692,64–1693,14, dentro do de 1 km (os dados já
recortados bastam). Varredura de chão plano para as duas bases (`crop_world`, 2026-11-13):
- fica a vila de Xóm Gò inteira no morro do centro (cume de 35,7 m), An Cường (2) com as 5 bocas
  de túnel e a trincheira sul (a 18–26 m da borda sul) e o casario a sudeste dela;
- saem Nam Yên (4), An Thới (2), a Colina 30, o cemitério de 1965 e o riacho (fica 50–75 m a leste,
  na margem do terreno).

**QGs:**
- VC: E 269,688 / N 1692,89, no pé oeste do morro (desnível de 0,9 m na área da base);
- EUA: E 270,105 / N 1692,935, a nordeste de An Cường (2), a 40 m da boca E2 (desnível de ~4 m,
  que os patamares cortam). A base leva tudo junto (posições relativas ao QG).

**Setores (oeste → leste):** A Encosta oeste (110 m), B Xóm Gò (100 m), C Sopé do morro (70 m),
D An Cường (2) (100 m), E Vale do riacho (120 m). A vila passou do setor 3 para o 2
(`crop_world.SETOR_VILA`).

**Pontos fortes (3 por setor):**
- todos a até 110 m da linha do meio, menos o do norte da base dos EUA (145 m), e a 45 m ou mais da
  borda;
- dois de setores vizinhos ficam a 74 m ou mais um do outro;
- B: a praça de Xóm Gò, os becos (travessa do lado do centro) e a ponta norte (a outra travessa);
- D: An Cường (2), a sebe ao norte (boca E4) e o arrozal ao sul (boca E3). A Trincheira sul deixou
  de ser ponto forte (a 20 m da borda), mas continua no mapa;
- reais: An Cường (2) e o casario a sudeste dela. Os outros são nomes de design (antes, um real por
  setor; no recorte de 500 m não há mais lugares da carta).

**Números que mudaram (PLACEHOLDER de projeto):**
- raio de captura: 35 m (era 50; o prompt pedia 40–60 m para setores de 200–400 m);
- `Front`: reunião avançada a 60 m (era 125), passo de 5 m, 10 m para dentro, busca + 100 m,
  reunião do squad sem inimigo a 60 m (era 100), 50 m do objetivo, 75 m do QG inimigo, 20 m da borda;
- reunião atrás do ponto forte: 30 m (era 60); bloqueio por inimigo: 60 m (era 75; o túnel do VC
  segue com 50);
- renascer onde caiu: bloqueado a menos de 60 m do QG inimigo (era 125);
- blindados dos bots: param a 110 m (M48), 90 m (Ontos) e 120 m (LVTP-5) do alvo; o LVTP-5
  desembarca a 90 m (eram 220, 180 e 250 m, e 180 m);
- clareira da base dos EUA na mata: 80 m (era 150, que pelaria An Cường (2));
- campo de tiro longo: alvos a 50, 100 e 150 m (eram 100, 200 e 300; o de 300 m caía fora);
- estradas: voltas por fora a 45 m da borda (eram 70).

**40 x 40:** `Roles.TEAM_MAX` e `BotBrain.CROWD.perSide` = 40 (eram 50, D-91). O servidor de 80
fica com o dono: a chave não tem a permissão (`server-size 80` respondeu "Scope not authorized";
`TODO_USUARIO.md`). Até lá o jogo limita 40 por lado.

**Carta:** refeita para o recorte novo (`tools/make_carta.py`) e publicada em 4 blocos; os IDs da de
1 km ficam como `Carta.<bloco>_1km`.

**Medido:**
- recorte: grade de 179 x 180 células; 19 diques, 5 tabuleiros, 126 sebes, 5 casas da carta e as 48
  de Xóm Gò; estradas: 1,1 km de principal e 1,1 km de voltas por fora;
- Lune: plano da mata com 2.573 plantas (2.248 na área, 325 na cortina); rotas dos bots de An Cường
  (2) até Xóm Gò sem desvio (166 e 223 m);
- Studio: terreno em 3 s (144 blocos), mata a 100% nos 5 setores, os 9 veículos dentro da área,
  primeiro tiroteio aos 15 s de partida (era 46 s), 40 bots do VC e 37 dos EUA mais o jogador,
  servidor a 60 Hz, 0 erros de script.

**Não testado:** partida inteira até o fim, celular, 40 jogadores de verdade num servidor.

## D-115 — Lote 4b: cabanas e vilas maiores, terra batida nas ruas (v47, 2026-11-13)

Pedidos do dono: "aumente as cabanas de todo jogo e o tamanho das vilas"; "cabanas muito pequenas
no mapa"; "dê um aspecto de terra batida para o chão do jogo nas ruas".

**Cabanas 30% maiores** (`ArtPlan.HOUSE_SCALE` e `Village.houseScale` = 1,3, PLACEHOLDER): no
Studio, a casa da vila tinha 8,3 x 8,3 m e 4,8 m até a cumeeira, e o beiral ficava na altura da
cabeça do soldado de 2,0 m (D-98). Agora:
- casas da vila 10,8 x 10,8 x 6,2 m; casas da carta (a de varanda: 10,4 x 10,4 x 8,0 m);
- cozinha, celeiro, meda, horta e varanda na mesma escala, e os anexos do quintal na medida do lote
  novo;
- a vila de Xóm Gò cresce junto (`vila_estradas.ESCALA_CASA`): lotes de 15,6 x 18,2 m, passo de
  18,2 m, travessas a ±72,8 m da praça, praça, pagode e casa comunal 30% maiores. Continuam as 48
  casas, numa rua de ~327 m (era ~255 m);
- a busca do lugar da vila ficou com passo de 7,5 m (era 15) e a margem do setor é meio lote + 1 m
  (era 12 m fixos): com os lotes maiores a vila fica justa no setor B.

**An Cường (2) virou vila:** no recorte de 500 m ela tinha só as 5 casas da carta.
`crop_world.casario_an_cuong` acrescenta 18 casas de design em volta dela:
- como os xóm do litoral de Quảng Ngãi: casas soltas a 20 m ou mais umas das outras, viradas para o
  sul ou para o norte, com até 15° de folga;
- fora das bocas de túnel e da trincheira (12 m), da base dos EUA (15 m), do mastro dos pontos fortes
  (12 m), do riacho e de chão com mais de 1,6 m de desnível;
- feito uma vez (`Grid.hamletAdded`). As estradas desviam delas.

**Túneis:** a boca E5 e a trincheira sul ficaram 20 m mais perto da vila (185 m do centro; eram
205). Os túneis partem do local da carta de An Cường (2) (E 270,030 / N 1692,850), e a 205 m metade
da trincheira caía fora do mapa de 500 m. Agora ela fica a 18–26 m da borda sul. Galeria: 454 m (era
474). O teste da borda passou a usar o mesmo centro do jogo; antes conferia pelo ponto forte.

**Terra batida:** ruas, becos, praça, quintais, patamares e diques usam o material Ground. Ele levava
a foto `forest_ground_06` (terra escura de mata: de cima e na rua parecia quase preto). Agora leva
`dirt_floor` (Poly Haven, CC0, 2,07 m por ladrilho), terra clara compactada. Os 3 mapas foram
publicados, e os IDs das imagens estão em `AssetIds.GroundImages`.

**Carta:** refeita e publicada (a da v46 ficou como `Carta.<bloco>_v46`).

**Conferido no Studio:**
- a rua de Xóm Gò e os quintais aparecem em terra batida;
- as casas aparecem na escala 1,30;
- o casario de An Cường (2) aparece com quintais e estradas de terra;
- primeiro tiroteio aos 17 s, servidor a 60 Hz, 0 erros de script.

**Não testado:** o soldado entrando pela porta de cada modelo de casa (a foto em terceira pessoa não
saiu: a câmera de primeira pessoa volta por cima) e o celular.

## D-116 — A grama de volta e mais árvores (v48, 2026-11-13)

Pedido do dono: "onde está a grama que tinha e coloque um pouco mais de árvores".

**Por que a grama sumiu (v47):** três coisas se somaram no mapa de 500 m:
- a roça seca ia até 110 m de cada casa (`Landscape.FARM_M`). Com as 18 casas novas de An Cường (2)
  (D-115), ela cobria quase toda a metade leste;
- a roça tem manchas de terra nua (`ArtPlan.ROCA_EARTH`, material Ground). Com a terra batida clara
  da D-115 elas apareciam laranja, no lugar do capim;
- a clareira em volta do QG dos EUA no `Landscape` tinha ficado em 150 m (a da mata já era 80 m desde
  a D-114).

**O que mudou (PLACEHOLDER de design):**
- roça seca até 45 m das casas (era 110);
- clareira da base dos EUA de 80 m (era 150);
- manchas de terra nua só onde o ruído passa de 0,8 (era 0,62);
- árvores da mata 40% mais frequentes, com o sub-bosque igual;
- na roça, de vez em quando, uma árvore de folha larga ou um coqueiro solto.

**Medido (Lune, plano da mata com os dados do mapa; v47 → v48):**
- mata de 30% para 47% da área; roça de 24% para 15%; clareira de 36% para 29%;
- terra nua de 8,7% para 2,3% do mapa;
- plantas na área de 1.744 para 2.475; árvores de 435 para 847.

**Studio:**
- mata com 2.401 plantas (eram 1.751), 100% do plano nos 5 setores;
- 54 fps no chão, servidor a 60 Hz;
- primeiro tiroteio aos 18 s, 0 erros de script.

**Não testado:** o fps num celular ou num PC fraco com a mata maior.

## D-117 — Lote 5: menu principal animado, tutorial fora da partida e carregamento do mapa inteiro (v49, 2026-11-13)

Pedidos do dono:
- "faça uma tela de menu animada bonita, que vai ter atrás o fundo do mapa bonito e o soldado, e vai
  ter as opções jogar, configurações, loja, passe e tutorial";
- "não quero mais o tutorial dentro do jogo";
- "a tela de carregamento inicial deve ficar ali até carregar o jogo e o mapa inteiro".

**Menu principal** (`Controllers/MenuPrincipal`): abre quando a tela de carregamento termina e fica
até o JOGAR.
- Fundo: o mapa de verdade. A câmera dá a volta em Xóm Gò a 120 m de raio e 40 m de altura, uma volta
  em 4 min, com cor quente, desfoque leve ao longe e vinheta escura à esquerda para o texto.
- À direita, o soldado (o manequim vestido pelo servidor), respirando devagar: o do lado do jogador
  ou, antes de escolher, os dois lados se revezando a cada 9 s.
- À esquerda, o título STARLITE · VIETNÃ 1965 e cinco botões que entram em cascata:
  - JOGAR: o Jogar agora (lado, squad, papel e ponto automáticos);
  - CONFIGURAÇÕES: o menu do jogo, aberto na aba Configurações (Bus `menu_open`);
  - LOJA e PASSE: as telas de sempre;
  - TUTORIAL: o COMO JOGAR.
- Enquanto aberto, o atributo `MenuPrincipal` esconde o lobby (a mesa) no `GameUI`. A mesa continua
  no menu do jogo e na tela de baixa.
- Controle: ↑ ↓ e A; teclado: setas e Enter; toque e mouse: tocar ou clicar.

**Tutorial fora da partida:**
- `Tutorial.IN_MATCH = false`: o painel de passos não começa mais ao nascer;
- "refazer o tutorial" abre o COMO JOGAR (`Controllers/ComoJogar`), em nove cartões: objetivo; andar
  e correr; mirar e atirar; se proteger; granada e faca; carta; ferido; squad; veículos;
- cada cartão tem uma frase curta e os botões do aparelho de agora em chips grandes, com o nome da
  ação embaixo. Os botões do mouse aparecem por extenso ("CLIQUE DIREITO");
- texto e botão ficam separados, para a tradução casar a frase inteira;
- o campo de tiro continua nas bases.

**Carregamento até o mapa inteiro:**
- o servidor conta as peças do mapa (`Map.PartCount`, ao marcar a arte pronta);
- a tela pede o streaming no centro e nos quatro quadrantes (além dos QGs e dos objetivos) e espera
  chegar 95% das peças, no máximo 90 s;
- teto de segurança de 4 min (era 90 s);
- no fim, marca `Pronto` e esmaece por cima do menu principal. Os botões JOGAR AGORA e MESA DE
  CAMPANHA da tela de entrada e a contagem de 10 s saíram.

**Conferido no Studio:**
- 69 a 72 s do início até o menu, com 8.156 das 8.164 peças do mapa no cliente (99,9%);
- o menu com o mapa girando, o soldado e os cinco botões;
- TUTORIAL, CONFIGURAÇÕES, PASSE e LOJA abrem e fecham (Backspace) de volta ao menu;
- JOGAR põe em campo (EUA, fuzileiro, squad Alfa), sem o painel de tutorial;
- 0 erros de script no servidor e no cliente.

**Não testado:** controle de verdade e celular no menu; o menu num servidor com o carregamento lento
(o teto de 4 min).

## D-118 — Menu principal em planos de cinema e tutorial que segue o aparelho (v50, 2026-11-13)

Pedido do dono, sobre a v49: "o tutorial tem que se adaptar conforme o local que a pessoa está
jogando. Melhore essa tela do lobby, não gostei do personagem e do fundo".

**Menu principal** (`Controllers/MenuPrincipal`):
- saíram o retrato grande do soldado, a etiqueta do lado e a volta da câmera por cima do morro;
- o fundo é o mapa em planos de cinema, sempre no fim de tarde:
  - a hora é o sol real de 18/08/1965 às 18:06 (UTC+8): baixo no oés-noroeste, luz dourada e sombras
    compridas;
  - enquanto o menu está aberto, o cliente segura essa hora contra o acerto do servidor (a cada 15 s);
  - ao fechar, volta a hora da partida;
- três planos de 11 s, com corte pelo preto de 0,7 s:
  1. fuzileiros nos becos de Xóm Gò, a câmera de frente, baixa, chegando perto;
  2. o Viet Cong no quintal oeste de An Cường (2), por cima do ombro, olhando a vila;
  3. fuzileiros na encosta leste, a câmera subindo atrás deles, com o morro de Xóm Gò contra o sol;
- os soldados são o manequim que o servidor vestiu (`SoldierPreview.newWorld`), em pé no chão do
  mapa. Cada plano:
  - procura chão livre para eles (sem casa, muro ou tronco), numa espiral de até 12 m do ponto;
  - tira a câmera de trás do que tapar o grupo;
  - foca no grupo e desfoca o resto;
- um balanço pequeno de câmera na mão, faixas pretas em cima e embaixo, vinheta à esquerda para o
  texto e o nome do lugar no canto de baixo à direita;
- sem terreno no cliente ainda, a câmera dá a volta em Xóm Gò como na v49 e tenta os planos de novo;
- os botões, o título e os atalhos não mudaram.

**COMO JOGAR segue o aparelho** (`Controllers/ComoJogar`):
- uma etiqueta no alto diz onde: NO CELULAR, NO CONTROLE ou NO COMPUTADOR;
- a frase do cartão tem versão para o celular e para o controle quando o jeito de fazer muda (no
  celular, "Toque em MIRA e depois em FOGO"; no controle, "Segure LT para mirar e aperte RT");
- os chips mostram o botão daquele aparelho. A granada é a tecla 3 no computador e o botão ITEM no
  celular;
- ao lado dos chips, o desenho do aparelho com o botão do assunto aceso e pulsando:
  - o celular deitado, com os botões do layout de toque padrão (`Toque.PRESETS.two`) no lugar deles;
  - o controle: gatilhos, botões de ombro, analógicos, direcional, A B X Y;
  - o lado esquerdo do teclado e o mouse;
- trocou de aparelho com o tutorial aberto (pegou o controle, tocou na tela): o cartão se refaz na
  hora.
- Teste novo (`interface.luau`): todo chip tem botão no layout de toque e está no desenho do teclado
  e do controle.

**Também nesta versão:**
- enquanto o menu principal está aberto, os avisos da partida ("setor perdido", "contra-ataque") e o
  cartão de veículo da carta de inserção não aparecem por cima dele nem do COMO JOGAR. A loja e o
  passe abertos do menu mostram os avisos deles.

**Conferido no Studio:**
- o menu abre entre 62 e 71 s;
- nos becos, os fuzileiros ficam de frente para a câmera; no quintal e na encosta, de costas, por cima
  do ombro, a 5 a 13 m da câmera. Isso foi medido pela direção do rosto de cada soldado;
- o COMO JOGAR muda na hora entre NO CONTROLE (L e A acesos), NO CELULAR (toque forçado; o analógico e
  o PULAR acesos no desenho do celular) e NO COMPUTADOR (R e os dois botões do mouse acesos);
- o JOGAR põe em campo (EUA, fuzileiro); a hora, a cor, o desfoque e os avisos voltam ao normal e os
  soldados da cena somem;
- 0 erros de script;
- o FPS no Studio ficou entre 7 e 15, tanto no menu quanto em campo, então o menu não pesa mais que o
  jogo. É a mesma máquina rodando o servidor e os bots.

**Ajustes vindos do teste:**
- a vinheta passou de vinho para preta, e a cor do menu ficou menos saturada (a terra batida no sol
  baixo ficava vermelha);
- folha e capim não puxam mais a câmera para perto do grupo;
- a câmera por cima do ombro fica atrás do grupo inteiro (antes passava a 0,9 m de um soldado);
- o grupo fica à direita da tela, longe dos botões;
- sem a imagem do analógico, o chip "Andar" do controle mostra "L".

**Visto e deixado para o lote 10:** em campo, a terra batida também parece vermelha.

**Não testado:** celular de verdade e controle de verdade no menu, além do controle ligado no PC do
dono, que mexia nos menus durante o teste.

## D-119 — Lote 7: a mira da RPD e da M60 no lugar certo (v51, 2026-11-13)

Pedido do dono: "a arma RPD está ruim, as balas não estão saindo aonde está a mira; conserte todas as
armas nesse sentido, incluindo pegada, aparência e local correto de saída das balas".

**Causa:**
- a bala vai para o centro da tela (a câmera); mirando, a arma em 1ª pessoa gira até a linha
  alça → massa cair nesse centro;
- só M14, Type 56, SKS e a espingarda tinham alça e massa medidas na malha (D-67). Nas outras, a
  linha era estimada: paralela ao cano, na altura do ponto mais alto perto da boca;
- na RPD esse ponto era a ponta do cano, 1,4 cm acima dele. A massa de verdade fica 4,3 cm acima do
  cano, dentro de um capuz, a 14% do comprimento a partir da boca, e a alça fica rente ao cano.
  Mirando, a massa que o jogador via ficava acima do centro: ele punha a massa no alvo e a bala ia
  baixo;
- na M60 a massa estimada também não era a massa (ela fica 11 cm acima do cano, num capuz).

**Correção** (`tools/sight_align.py` e `tools/weapon_landmarks.py`, que geram o `Shared/WeaponArt`):
- RPD: entalhe de 6,4 mm medido na alça e a ponta do poste dentro do capuz;
- M60: a alça da malha não tem entalhe limpo (são três dentes). No modo novo "topo", o olho passa
  rente ao dente que fica na linha da massa (1 mm do plano do cano) e a massa é a ponta do poste no
  capuz (10,7 cm acima do cano);
- pegada: nas duas, a mão direita desceu ao punho de pistola, 12 a 13 cm abaixo do cano (antes,
  5 cm, rente à caixa). Mirando, ela ficava a 2 cm da câmera e tapava meia tela;
- o olho fica a 12 cm da alça (a alça das duas malhas fica em cima do punho);
- na RPD, a mão esquerda desceu para 8 cm abaixo do cano: os dedos apareciam atrás da massa e
  tapavam o alvo;
- a boca do cano (clarão e começo do traçante) já saía do eixo do cano medido na malha e não mudou.

**Conferido no Studio:**
- mirando, a alça e a massa ficam no centro da tela: RPD a 1 px, M60 a 0,2 px e M1911 a 0,1 px;
- na mira da RPD, a mão esquerda fica 19° abaixo do centro e a direita 61°; na M60, 20° e 55°;
- com os braços escondidos, a massa da RPD aparece limpa no meio do entalhe;
- sem mirar, a RPD aparece inteira, com o bipé e as duas mãos.

**As outras armas:**
- M14, Type 56, SKS e a espingarda já eram medidas;
- nas pistolas, a alça e a massa ficam na mesma altura da linha estimada, e a M1911 alinha no centro;
- a M79 e o RPG-2 têm a linha própria da D-60;
- M70 e Mosin miram pela luneta.

**Visto e não corrigido:** a Type 54 em 1ª pessoa parece cinza-clara sob o sol forte. A malha tem
a textura (SurfaceAppearance); fica para a análise do lote 12.

**Não testado:** a RPD e a M60 em 3ª pessoa com a mão nova (o dono jogava na sessão do Studio do
teste); controle e celular mirando.

## D-120 — Lote 8: tela de baixa com quatro botões; loja e passe fora do menu do jogo (v52, 2026-11-14)

Pedidos do dono:
- "na tela de morte deixe só o botão de renascer aqui e depois aparecem duas opções de pagar com
  dinheiro do jogo ou Robux, e o Robux vai estar colorido; o outro botão vai ser o de escolher outro
  ponto, menu e nascer com veículo. Não quero nenhum outro botão além desses";
- o RENASCER grátis grande sai também (resposta do dono);
- "o passe e a loja não devem aparecer no menu": no menu do jogo (lado e squad); no menu principal
  continuam (resposta do dono).

**Tela de baixa** (`Controllers/CasualtyScreen`):
- **RENASCER AQUI**, grande, em cima. No próprio botão, uma linha: o motivo da regra ("inimigo a
  menos de 100 m"), a espera ou "créditos ou Robux". Com regra, fica apagado.
- O clique abre **COMO PAGAR**, com duas opções:
  - "Pagar $ 60", em âmbar ("Usar o guardado" se já pagou em Robux);
  - "Pagar 25 Robux", em verde vivo com a borda dourada que pulsa.
- **RENASCER COM VEÍCULO** e **ESCOLHER OUTRO PONTO**. A carta é o renascer de graça, no ponto que o
  jogador escolher.
- **MENU**: a mesa.
- Saíram o RENASCER grátis (jogar agora), LOJA, PASSE e MISSÕES.
- Controle: A renascer aqui, X créditos, Y Robux, RT veículo, LT carta, B menu.
- Teclado: Enter renascer aqui, V veículo, M carta, Backspace menu.

**Loja e passe fora do menu do jogo:**
- mesa: saiu a aba INTENDÊNCIA (loja e armário). A caixa de munição da mesa 3D ficou só de enfeite:
  sem o clique e sem o rótulo "INTENDÊNCIA (LOJA)";
- cartão do jogador na mesa: saíram o PASSE DE CAMPANHA e a oferta do Pacote de Recruta ("VER NA
  LOJA");
- menu do jogo: a 3ª aba virou **Campanha** (ficha, missões e cartão). No lugar da loja, do armário
  e do passe ficou "Menu principal (loja, passe e tutorial)", que reabre o menu principal (Bus
  `menu_principal_open`). Em campo, o JOGAR de lá só fecha o menu (o Jogar agora não faz nada com o
  soldado vivo);
- a tecla L continua abrindo a loja em campo: é um atalho, não um item de menu.

**Conferido no Studio:**
- a tela de baixa mostra só os quatro botões;
- o RENASCER AQUI abre "Pagar $ 60" e "Pagar 25 Robux";
- numa baixa de verdade, o botão fica apagado com "inimigo a menos de 100 m";
- o MENU abre a mesa sem a aba INTENDÊNCIA e sem o PASSE.

**Achado na mesa ("conserte a tela do menu do jogo para selecionar o lado"):**
- a câmera da mesa 3D tira os objetos do quadro em tela estreita;
- no Studio (proporção 1,19), a mesa do VC caiu fora da tela (x = −130 px) e a câmera ficou a 1,3 m
  dela, em vez dos ~2,5 m do plano. O fundo vira um borrão marrom, sem nenhum objeto da mesa;
- falta decidir com o dono se a câmera da mesa é consertada ou se a mesa vira uma tela 2D simples.

**Não testado:** a compra em Robux de verdade, controle e celular na tela de baixa.

## D-121 — Mesa 3D consertada e sem soldados (v53, 2026-11-14)

Resposta do dono à pergunta da D-120: "3D, porém tire os soldados dali".

**Câmera da mesa** (`Controllers/LobbyScene`):
- em tela estreita, a câmera recuava até 40% para caber a mesma largura. No abrigo do VC ela saía
  pelo teto e a mesa ficava atrás das toras: o fundo virava um borrão marrom, sem nenhum objeto;
- agora a câmera fica na distância do plano e abre o campo de visão: 50° em 16:9 e até 75° em tela
  estreita (`fovFor`);
- a câmera da mesa roda depois de todos os scripts de câmera (Camera + 20; antes, + 2, com o giro do
  corpo em + 3 e o tremor em + 5 depois dela);
- ela reafirma o tipo Scriptable a cada quadro (o menu principal, ao fechar, devolve "Custom");
- com o menu principal aberto por cima, ela não mexe.

**Sem soldados:**
- na barraca dos EUA e no abrigo do VC, o soldado de pé (o objeto "papel e equipamento") virou um
  cabide de madeira com a túnica do lado, o cinto de lona e o cantil;
- na sala de escolha do lado, saíram os dois soldados atrás da mesa. O lado se escolhe pelos dossiês
  sobre a mesa, que já eram os objetos de escolha.

**Conferido no Studio** (janela 671 × 565, proporção 1,19):
- antes: a mesa do VC ficava fora da tela, em x = −130 px;
- depois: a mesa aparece no quadro, em (410, 358), a 2,1 m da câmera, com FOV de 67°, os papéis, a
  lamparina e o abrigo, e nenhum soldado.

**Não testado:** a barraca dos EUA e a sala de escolha do lado depois da mudança; celular em pé.

## D-122 — Lote 9: 30 contra 30 e começo na base com contagem (v54, 2026-11-14)

Pedidos do dono: "quero o jogo 30v30"; "a partida deve começar com cada um na sua base com uma
contagem regressiva; após isso a partida começa e os jogadores vão dominar os pontos".

**30 contra 30:**
- `Roles.TEAM_MAX` = 30 e `BotBrain.CROWD.perSide` = 30 (eram 40);
- o servidor deve ter 60 vagas. A chave não muda isso, então ficou com o dono (TODO_USUARIO).

**Contagem do começo** (`MatchService.PREP_S` = 30; `Modules/PreparoService`;
`Controllers/Contagem`):
- cada partida nova abre com 30 s de preparo. Nesse tempo:
  - não há captura nem sangria de reforços;
  - o relógio da partida não anda e só começa no fim da contagem;
  - todo ponto de nascer fora do QG fica bloqueado ("Na contagem, todos nascem na base"), inclusive a
    reunião, o squad e o "renascer aqui";
  - quem passa de 60 m do QG do seu lado volta para a borda da base, menos quem está sentado num
    veículo;
  - os bots ficam parados; as viaturas freiam e os prazos do vigia de tripulação não contam;
- enquanto nenhum jogador está vivo em campo, a contagem fica cheia (30). Num servidor novo, a
  partida abre com todos ainda carregando (~60 a 70 s no Studio); a contagem corre quando o primeiro
  jogador nasce;
- na tela: "A PARTIDA COMEÇA EM", o número grande (os 5 últimos em latão, pulsando) e "Espere na sua
  base". No zero, "VALENDO!" e "Tome os pontos" por 2,5 s. Some com o menu principal aberto.

**Conferido no Studio:**
- a contagem ficou em 30 enquanto o jogador estava no menu;
- no JOGAR, ele nasceu a 7 m do QG dos EUA, a contagem correu com o relógio parado em 75:00 e os
  bots ficaram na base;
- no fim, "VALENDO!", o relógio começou (74:59) e os bots saíram (30 bots do VC e 18 dos EUA a mais
  de 60 m da base 30 s depois);
- 30 por lado: 29 bots mais o jogador nos EUA, 30 bots no VC;
- as tripulações embarcaram e saíram depois da contagem. Na 1ª tentativa, o vigia desfazia as quatro
  tripulações durante a contagem (corrigido);
- 0 erros de script.

**Não testado:** a contagem entre uma partida e a seguinte (depois do relatório pós-ação), vários
jogadores ao mesmo tempo e o celular.

## D-123 — Lote 10: mapa de 700 x 700 m, três objetivos e o solo (v55, 2026-11-14)

Pedidos do dono: "aumente o mapa para 700 x 700 m. As bases devem ser bem na ponta central de cada
lado do mapa e os objetivos bem distribuídos pelo mapa, sendo um bem no centro numa vila maior, o
outro em uma floresta densa e pouco acessível e o outro a sua escolha" (três objetivos, resposta do
dono) e "conserte o solo, os terrenos".

**Área** (`tools/geo.py` `PLAY_ING` = 269480–270180 E, 1692580–1693280 N; `tools/crop_world.py`):
- 700 x 700 m (2.500 x 2.500 studs), com Xóm Gò no meio. A origem local não mudou (centro do mundo
  gerado, D-63): `Bounds` x de −2.571,4 a −71,4 e z de −3.142,9 a −642,9;
- três setores em faixas norte-sul, divididos em E 269750 e E 269920:

  | Setor | Dono no começo | Pontos fortes |
  |---|---|---|
  | A Mata fechada | VC | Mata fechada; Picada na mata |
  | B Xóm Gò (centro) | neutro | Xóm Gò; Becos de Xóm Gò; Ponta norte de Xóm Gò |
  | C An Cường (2) | EUA | An Cường (2); Sebe ao norte; Arrozal ao sul |

- os QGs ficam no meio da borda de cada lado, 50 m para dentro (no canto, a área da base dos EUA saía
  do mapa): EUA em (270130, 1692930), VC em (269530, 1692930);
- os nomes da mata são de design (`real = false`), como os outros pontos inventados.

**Objetivo A, mata fechada e de difícil acesso:**
- `Vegetation.DENSE_SECTOR` = 1: até 70 m dos pontos fortes do setor A a mata fica 1,8 vez mais cheia,
  voltando ao normal até 105 m (densidade de design, PLACEHOLDER);
- a clareira dos dois pontos caiu de 30 m para 10 m (`Landscape.CLEAR_NAMED_M`). Com 30 m, o objetivo
  virava um descampado no meio da mata (Studio). A roda de captura (35 m) fica debaixo das árvores;
- sem estrada até os pontos do setor A (`crop_world.SEM_ESTRADA`): o teste de estradas exige 60 m ou
  mais da estrada principal. Viatura chega perto, mas o último trecho é a pé entre os troncos.

**Código para qualquer número de setores** (antes, vários lugares supunham 5):
- `MatchService`: o Offensive usa `#MapConfig.Sectors`; o Skirmish usa só o setor do meio;
- `FrontHud`: um chip por setor (A, B e C);
- `SelfTest` e os testes `modo`, `run`, `bots`, `botsmov`, `contato`, `estradas` e `f5` também.

**Ruas e construções:** a folga da estrada para a base passou de 1 m para 5 m
(`tools/vila_estradas.py` `BASE_FOLGA_M`); uma rua cortava o canto da base do VC. O celeiro que caía
em cima da estrada principal agora sai do plano (`ArtPlan`, conferido pela `Site.road`).

**Solo** (`Modules/TerrainLook.luau`):
- o terreno multiplica a textura pela cor do material. A terra batida (`dirt_floor`, D-115) tem cor
  média (182, 140, 100), medida na textura; com a cor antiga (108, 86, 60) as ruas saíam
  vermelho-escuras, perto de (77, 47, 23);
- `Ground` = (150, 168, 200): o tom puxa para o azul e o resultado fica perto de (107, 92, 78), terra
  seca acinzentada. `Mud` = (90, 80, 64), um pouco menos vermelho;
- conferido no Studio: no menu (sol baixo) a rua ficou cinza-terra; de manhã, na base, ela fica
  bege-alaranjada pela luz.

**Menu principal** (achados no teste):
- dois dos três planos ancoravam em pontos fortes que saíram (Quintal oeste de An Cường (2) e Encosta
  leste) e o menu ficava num plano só. Agora: Becos de Xóm Gò (EUA), Sebe ao norte de An Cường (2)
  (VC) e Arrozal ao sul de An Cường (2) (EUA). Um teste novo (`run.luau`) exige que todo plano ancore
  num ponto forte que existe;
- os Becos agora ficam no objetivo B, onde os bots brigam, e um soldado passou de costas na frente da
  câmera. Com o menu aberto, quem está a até 40 m do grupo do plano some só nesta tela
  (`LocalTransparencyModifier`; o próprio jogador fica de fora);
- aberto da tela de baixa (MENU > Menu principal), a baixa e a carta tática apareciam através dele.
  Agora as duas ficam escondidas enquanto ele está aberto.

**Tradução:** o `tools/i18n/extrai.py` pulava o texto de toda função terminada em "on("
(`section(`, `makeButton(`, `footButton(`), porque faltava o limite de palavra antes de `on` e `fire`
na lista de chamadas sem texto de tela. Com o conserto, apareceram 22 textos sem tradução (títulos
das configurações, JOGAR, CONFIGURAÇÕES, "◄ ANTERIOR" do tutorial, seções da loja e das missões).
Todos foram traduzidos para inglês, espanhol e vietnamita, além dos nomes novos do mapa.

**Carta:** refeita para a área nova (`tools/make_carta.py`) e enviada (4 blocos; os antigos ficaram em
`roblox_ids.json` como `Carta.*_v47`).

**Medido:**
- simulação (`contato.luau`): o VC que sai do QG troca tiro em 80 s; saindo do melhor ponto, em 0 a
  14 s;
- rotas (`botsmov.luau`): Sebe ao norte → Xóm Gò 166 m; Arrozal ao sul → Xóm Gò 224 m; An Cường (2)
  → Mata fechada 372 m;
- Studio: terreno em 15 s (210 blocos); 6.258 plantas da mata de 6.319 no plano; o jogador nasceu a
  7 m do QG dos EUA com a contagem; 2 min depois, 28 bots de cada lado em campo; numa das partidas o
  VC tomou o B primeiro.

**Não testado:** a partida inteira até o fim no mapa novo; celular; o desempenho (fps) no setor A com
a mata 1,8 vez mais cheia. O Studio avisa 1 construção com o chão a mais de 0,6 m do patamar do
plano; entre as construções carregadas, nenhuma passou disso na medida pelo raio no meio da peça.

## D-124 — Lote 11: passe em linha do tempo e loja com imagens (v56, 2026-11-14)

Pedidos do dono: "coloque o passe em ordem cronológica horizontal" (com design próprio, sem copiar o
de outro jogo) e "deixe a loja atrativa com imagens, cores, design bonito".

**Passe** (`Controllers/TelaPasse.client.luau`):
- os 50 níveis numa linha do tempo da esquerda para a direita, desenhada como a rota de uma operação
  na carta:
  - cada nível é um marco na rota, com o número no círculo; de 10 em 10, um marco maior;
  - o trecho andado fica em latão, até o nível atual mais a fração das estrelas; o marco atual pulsa;
  - a trilha VETERANO fica em cima (cartão puxado para o latão, filete de latão) e a GRÁTIS embaixo,
    cada cartão preso ao marco por um traço;
  - os rótulos das trilhas ficam fixos à esquerda ("LIBERADO" ou "COM O VETERANO"; "PARA TODOS");
- embaixo, a ficha do escolhido: ícone grande, tipo, nome, nível e trilha, e o motivo ("Pronto para
  receber", "Já é seu", "Precisa do Veterano", "Chegue ao nível N"); os botões em duas colunas
  (receber, receber tudo, Veterano e pular nível);
- para andar:
  - mouse: a roda (o Roblox já rola de lado uma ScrollingFrame só em X; um código nosso junto andava
    em dobro) e as setas ◄ ►, 4 níveis por clique; as setas somem nas pontas;
  - controle: direcional de nível em nível, LB/RB 10 níveis, LT/RT trocam a trilha;
  - toque: arrastar; o 1º toque mostra e o 2º recebe, como antes;
- o `CanvasPosition` anda em pixels de tela, com a escala do painel (medido no Studio: parou em 3.985
  = 4.545 − 559). A posição das colunas passa pela mesma escala; sem ela, a seta andava 6 níveis em
  vez de 4.

**Loja** (`Controllers/ShopController.client.luau`):
- abre na vitrine (LOJA E ARMÁRIO); antes abria na Intendência;
- imagens feitas com os modelos do próprio jogo (`tools/blender/loja.py`, Cycles, fundo transparente,
  luz de estúdio). A imagem mostra só o que o item dá:
  - Uniformes USMC 1965: o capacete M1 com a capa (o fuzil saiu da imagem: ele é de todos);
  - Uniformes da Força Principal 1965: o capacete de fibra e o chapéu de selva;
  - Kit de Elite: o colete M1955 e a granada de fumaça M18;
  - M151, M35 e Peugeot 403, para o cartão "VEÍCULO AO NASCER" da carta de inserção (é lá que eles são
    comprados; o Robux só abre com o lugar ao lado já reservado);
- `tools/loja_sombra.py` limpa a sombra: o apanhador de sombra deixava um véu fraco de alfa na
  imagem inteira, que desenhava um retângulo escuro sobre o cartão colorido (Studio);
- o destaque tem ao fundo uma faixa da capa do jogo (`tools/loja_banner.py`, recorte de
  `assets/capa`), com um véu escuro à esquerda para o texto; a imagem do item vai grande à direita;
- cartões mais altos (236 px, eram 176), com a imagem num fundo na cor do item (EUA azul, VC vermelho,
  kits oliva, apoio latão), de cima para baixo;
- os cartões do Mercado e das Vantagens usam o ícone publicado no passe, quando há;
- todos os produtos têm o mesmo ícone padrão do Roblox (o cubo cinza, ID 88963008124478, medido no
  Studio); ele não conta como imagem e fica o desenho na cor do item;
- Intendência: o escolhido ("LEVANDO", a aba ativa) em oliva escuro com texto claro (era cáqui com
  texto escuro).

**Imagens no Roblox:** 7 decals (`assets/upload_plan.json`, grupo `Loja`); o ID da imagem de cada
uma foi resolvido no Studio (InsertService) e está em `AssetIds.LojaImages`. As versões antigas
ficaram no `roblox_ids.json` como `Loja.*_v1` (com fuzil) e `Loja.*_v2` (com o véu de sombra).

**Teste novo** (`interface.luau`): a linha do tempo é de lado, a rolagem usa a escala, a loja abre
na vitrine, o cubo cinza não conta e as 7 imagens têm ID.

**Conferido no Studio:**
- o passe abre no começo com a seta esquerda escondida; uma seta anda 362 px (4 níveis × 140 ×
  0,647 de escala); no fim, o nível 50 fica inteiro na janela e a seta direita some;
- a vitrine com as imagens, as cores e a faixa da capa; as Vantagens com os ícones publicados; a
  Intendência sem as faixas bege.

**Não testado:** o cartão do veículo com a imagem numa inserção de verdade (o Studio só conferiu que
a imagem existe e fica escondida sem veículo escolhido); celular; compra de verdade.

## D-125 — Lote 12: análise de bots, gráficos, armas, tiros e veículos (v57, 2026-11-14)

Pedido do dono: "analise tudo do principal do jogo: bots, gráficos, armas, tiros, veículos" (junto do
lote 6: análise com ideias em imagens). Relatório completo, com números e capturas:
`testes/ANALISE_LOTE12_2026-11-14.md` e `testes/lote12/`.

**Corrigido:**
- **Embarque em loop no LVTP-5** (`BotVehicles.seatedThink`): o passageiro entrava com a tripulação
  no estado "board" e descia na hora (só podia ficar em "load"/"go" com o motorista sentado); o `calm`
  o sentava de novo. Um bot chegou a "embarcar" 47 vezes no mesmo lugar, um teletransporte a cada
  ~0,6 s. Agora ele espera sentado em "board" e "load"; na marcha ("go"), o motorista continua
  obrigatório. Depois: no máximo 2 embarques por bot numa sessão de ~8 min.
- **Autoteste** (`SelfTest.luau`), três falhas que eram do teste:
  - fecha a contagem do começo ao rodar (a chuva não mudava na contagem e o relógio do Offensive
    só começava depois dela);
  - conta as medas e os potes pelos nomes novos (`straw_stack`, `water_jar`) e aceita o arrozal de
    37 tabuleiros (D-114);
  - procura a letra do setor no relatório ("USMC toma B").
  Resultado: 17 ok e 1 falha (eram 14 e 4).

**Medido, sem mudança:**
- as 10 armas medidas têm alça e massa a 0,1 px do centro da tela e a linha a até 0,02° da direção
  do tiro; como o tiro sai do olho pelo centro, ele vai onde se mira;
- o gatilho solta no máximo um tiro por quadro: abaixo de ~12 fps a cadência cai (RPD 9 tiros/s
  contra 11,7 da ficha, com o Studio a ~10 fps);
- teto de bots em 22–24 por lado com o servidor do Studio a 34–35 Hz (a lotação baixa sozinha);
- bots em 180 s: mediana de 38 m andados, só 2 parados (guardando objetivo); primeiro tiroteio aos
  86 s;
- M151: 0 → 34 km/h em ~3 s.

**Perguntas ao dono** (não mudei sem resposta):
- M14: o olho a 6,3 cm da alça de anel (escolha de 2026-11-11) deixa as orelhas da alça tapando ~70%
  da tela. Afastar o olho?
- Capim: a cor (72, 92, 42) com a textura dá um verde quase preto e chapado; (100, 134, 74) mostra o
  relevo. O código diz que o mais claro "parecia gramado". Clarear?

**Aberto:** a pá do autoteste falha na 1ª rodada de cada sessão do Studio (cava, mas a sonda não vê o
buraco) e passa na 2ª.

## D-126 — Lote 13: medida de desempenho; nada muda na mata sem o dono (2026-11-14)

Pedido do dono: "um lote de desempenho (medir e aliviar a mata)". Relatório:
`testes/DESEMPENHO_2026-11-14.md`.

**Método** (vale para toda medida de fps no Studio):
- o Studio em segundo plano limita o jogo a 15 fps. Os "7–15 fps" da análise do lote 12 vinham disso;
  com a janela na frente, a mesma sessão foi a 55,8 fps;
- os bots do servidor dividem a CPU com o cliente no Studio; `BotFill` = 0 isola o desenho.

**Medido** (Studio na frente, sem bots, PC do dono):
- 38–51 fps olhando a mata e 60 fps fora dela;
- o gargalo é a CPU de desenho (18–21 ms por quadro; a GPU fica em 7–9 ms);
- a mata custa ~10 fps (árvores 6–11, arbustos ~4–5), a sombra do sol ~4 e a interface ~1;
- com 24 bots no mesmo processo, 24–42 fps.

**Tentado e retirado:** não desenhar as plantas baixas a mais de 200 m da câmera. O ganho ficou no
ruído (±2 fps) e o custo de jogo era real (soldado deitado à vista a distância).

**Decisão:** nada muda na mata agora. O que alivia de verdade mexe no visual ou num pedido anterior
(D-66: no mínimo 8 mil triângulos; D-123: mata do objetivo A 1,8 vez mais cheia). As opções vão ao
dono:
- menos árvores (−30%, ~2–3 fps estimados);
- menos arbustos (−50%, ~2 fps estimados);
- sombra do sol desligada por padrão (~4 fps medidos).

Falta medir num celular e no servidor do Roblox.

## D-127 — Metade dos arbustos e capim mais claro (v58, 2026-11-14)

Escolhas do dono depois da D-126: "Menos arbustos (−50%)", "M14: deixar como está", "Capim: clarear".

**Arbustos** (`Vegetation.SHRUB_KEEP` = 0,5):
- metade dos arbustos sorteados sai por um cara ou coroa da posição, feito depois de todos os
  sorteios. Assim o resto da mata fica igual, planta por planta;
- o teste da F5 confere que só os arbustos mudam (no plano do teste: 1.061 de 2.107, 50%);
- no jogo, a mata caiu de 6.465 para 5.502 plantas; no cliente, de 5.418 para 4.608, com 775
  arbustos (eram 1.585). O setor A planejado foi de ~33,8 para ~29,0 milhões de triângulos.

**Medido** (Studio na frente, sem bots, as mesmas vistas da D-126):

| Vista | Antes | Depois |
|---|---|---|
| Base dos EUA olhando a oeste | 38–43 fps | 42–47 fps |
| Xóm Gò olhando a mata A | 46–49 fps | 49–52 fps |
| Borda da mata A | 50–51 fps | 51–52 fps |

**Capim** (`TerrainLook.COLORS.Grass`): de (72, 92, 42) para (100, 134, 74). Com a textura, o capim
sai perto de (59, 70, 26) em vez de (43, 47, 15), e o relevo e os diques aparecem (captura
`testes/lote12/09_capim_v58.jpg`).

**M14:** fica como está (o olho a 6,3 cm da alça de anel, D-67).

## D-128 — Lote 14: cinco objetivos, um em cada canto (v59, 2026-11-14)

Pedido do dono (com a imagem da tela de outro jogo): "quero os objetivos do mapa igual o da imagem bem
separados em todos os cantos do mapa"; cinco objetivos (resposta do dono). Da imagem vale só a ideia
de espalhar os objetivos; nada da tela foi copiado.

**Setores e objetivos** (`tools/crop_world.py`; dados e `MapConfig` regenerados):

| Setor | Faixa (E, ING-A) | Objetivo | Canto | Dono no começo |
|---|---|---|---|---|
| A Baixada sudoeste | 269480–269600 | Baixada sudoeste | sudoeste | VC |
| B Mata fechada | 269600–269750 | Mata fechada | noroeste | VC |
| C Xóm Gò | 269750–269920 | Xóm Gò (praça) | centro | neutro |
| D An Cường (2) | 269920–270040 | Arrozal ao sul de An Cường (2) | sudeste | EUA |
| E Vau do riacho | 270040–270180 | Vau do riacho | nordeste | EUA |

- Um ponto forte por setor, sem sorteio: com o sorteio, os pontos podiam cair juntos perto do meio.
  Os Becos e a Ponta norte de Xóm Gò, a Picada na mata, An Cường (2) e a Sebe ao norte deixaram de
  ser objetivos. An Cường (2) segue no mapa, com os túneis, como local da carta.
- A Baixada sudoeste e o Vau do riacho são pontos novos, com nome de design. A Mata fechada foi 150 m
  para o norte.
- **Dono no começo:** cada lado com dois setores e o centro disputado. Com três neutros no meio, o VC
  ia para o B (noroeste) e os EUA para o D (sudeste), em cantos opostos, e ninguém se achava. A
  simulação de contato acusou: a LZ do minuto 1 ficou 15 min sem contato. Agora os 10 squads de bots
  atacam o C logo depois da contagem (Studio).
- A mata cerrada vale pelo nome do ponto (`Vegetation.DENSE_NAMES`); antes era o setor 1. A Mata
  fechada continua sem estrada; os outros quatro têm estrada a até 40 m.

**Menu principal:** planos na praça de Xóm Gò, na mata fechada e no arrozal ao sul de An Cường (2). O
`spXZ` também acha os locais da carta. O grupo fica 12 m atrás do mastro da bandeira: com um objetivo
por setor, todo ponto tem mastro, e ele atravessava a cabeça do soldado.

**Tutorial:** "Há cinco objetivos, de A a E", com a barra A B (VC), C (o da vez) e D E (EUA).

**Carta tática:** refeita, com as estradas novas até a baixada e o vau; os 4 blocos foram reenviados
(os antigos ficaram como `Carta.*_v55`).

**Testes:** o `run.luau` confere 5 setores, um ponto em cada, os cantos alternados e a distância das
bordas. O `modo.luau` conta as reuniões avançadas por par de setores vizinhos (8). O `estradas.luau`,
o `botsmov.luau` e o `eventos.luau` usam os pontos novos.

**Conferido no Studio:**
- as 5 fichas no HUD;
- a carta com os objetivos nos cantos;
- a LZ do minuto 1 a 140 m de C;
- os três planos do menu girando.

**Não testado:** a partida inteira até o fim; o Offensive com cinco setores no Studio (o teste do
Lune passa).

## D-129 — Lote 15: todos os itens da roda funcionando (v60, 2026-11-14)

Pedido do dono: "faça todos os itens da roda funcionarem, por exemplo a bandagem não está
funcionando". Cada item da roda de equipamento (e das vagas 5 a 0) foi testado no Studio.

**Por que a bandagem "não funcionava"** (três causas, todas caladas):
- quem andava durante os 6 s do curativo perdia tudo no fim (o servidor exigia ficar parado);
- sem sangramento, apertar não fazia nada (o curativo só fechava ferida);
- o curativo não devolvia vida: a tela seguia cinza e parecia que não tinha feito nada.

**Regras novas** (`Shared/Medical`, `Modules/MedicalService`):
- **Andar não cancela mais** curativo, torniquete, tratar nem reanimar. Cancelam: correr, cair,
  entrar num veículo, levar dano ou o companheiro sair dos 3 m.
- **O curativo devolve 30 de vida** (`Medical.C.bandageHeal`, PLACEHOLDER), além de estancar. Serve
  também para quem está ferido sem sangrar (`Medical.needsCare`).
- **O torniquete serve em qualquer braço ou perna sangrando**, não só na artéria. No tronco, não.
- Apertar de novo no meio de uma ação não recomeça o curativo.

**Aviso para o jogador** (evento novo `Medical_Aviso`, no Toast):
- **por que não faz nada:** "Você não está ferido", "Sem curativos: peça a um médico", "Torniquete
  é para braço ou perna sangrando: use a bandagem", "Ele não está ferido", "Só o médico reanima e
  trata";
- **por que parou:** "Interrompido: você correu" (ou caiu, foi atingido, entrou num veículo, o
  companheiro ficou longe);
- **quando dá certo:** "Curativo feito: sangramento parado e vida de volta", "Torniquete posto",
  "Companheiro tratado", "Companheiro de pé".

Os textos vão inteiros, sem `string.format`: a tradução troca o texto exato. O Toast divide
"Título: texto" e põe maiúscula no corpo; as partes também estão nos dicionários.

**Ferramenta do papel** (vaga 0 e roda) com o nome do que faz (`Equipar.roleToolLabel`):
- **Lançador** (antitanque): põe o lançador na mão. Antes, só um aviso "troque de arma".
- **Socorrer** (médico): trata ou reanima o companheiro a até 3 m. Sem ninguém perto, avisa.
- **Caixa de munição** (suporte) e **Ordens** (comandante): como antes, com o nome novo.

**Pá e construção:** agora avisam quando ficam prontas ("Buraco pronto: entre nele para se
abrigar", "Construção pronta"). Antes o buraco e a obra apareciam calados. O aviso vai pelo campo
novo `ok` do `Logistics_State`.

**Gancho do Studio:** `VT65DevFerido` ganhou "eu_perna", "eu_arteria", "eu_dano" e "eu_estado".

**Conferido no Studio:**
- **Bandagem andando:** a vida foi de 80,7 para 107,9 e o sangramento parou. O soldado andou ~11 m
  durante o curativo e gastou um curativo.
- **Bandagem pela roda:** de 75,2 para 105,2. Sem ferimento, aparece o aviso; correndo, interrompe.
- **Torniquete:** na artéria, estanca. Sem ferida de membro, explica por quê.
- **Granada e fumaça:** vêm para a mão e saem no gatilho (3 → 2 granadas, 2 → 1 fumaça).
- **Binóculo e caixa de munição:** o binóculo liga; a caixa mostra a prévia.
- **Pá:** cava (sacos de areia a 2,6 m) e avisa "Buraco pronto".
- **Construir:** o ninho de metralhadora saiu duas vezes. Perto de inimigo, aparece "Inimigos perto
  demais".
- **Lançador:** a vaga 0 e a roda põem o lançador na mão.
- **Socorrer:** sem ninguém perto, avisa; com o bot caído ao lado, ele levanta ("Companheiro de pé").

**Não testado:** "Ordens" do comandante (o soldado novo não tem posto para o papel); o celular e o
controle (a roda e o botão de bandagem usam o mesmo caminho).

**Achado de passagem:** as teclas funcionam por baixo da tela de carregamento. A pá cavou durante o
"Recebendo o mapa inteiro". Fica para a lista.

## D-130 — Lote 16: diária ao entrar, bandeiras na escolha do lado e passe colorido (v61, 2026-11-14)

Pedidos do dono:
- "recompensa diária deve aparecer toda vez que entro no jogo", "não precisa ter um local para ela";
- "na escolha do lado coloque uma bandeira do EUA e outra do Vietnã" (a do VC é a da Frente, resposta
  do dono);
- "coloque mais cores vivas no passe".

**Diária ao entrar** (`Controllers/DiariaEntrada.client`):
- abre sozinha por cima do menu principal, na primeira vez que ele abre na sessão (o MenuPrincipal
  dispara `Bus "diaria_entrada"` 1,2 s depois);
- mostra os 7 dias com o crédito de cada um, o de hoje em destaque e o item dos dias 3 e 7 do lado do
  jogador;
- um botão só: RESGATAR O DIA n (+$) ou CONTINUAR. Já resgatou hoje? Mostra quanto falta para o
  próximo prêmio. Enter, A, toque ou clique; B ou Backspace fecham;
- a aba RECOMPENSA DIÁRIA saiu da mesa do lobby, e o calendário e a caderneta da mesa ficaram só de
  enfeite, como a caixa da loja na D-120.

**Créditos da trilha:** a `Commerce.DailyTrack` guardava 25, 30, 40, 45, 50, 60 e 100, que ninguém
lia. O servidor pagava outra conta: 30 no 1º dia e +10 por dia (D-72). Agora a trilha tem os números
que o servidor já pagava (30 a 90, $ 420 a semana) e o servidor lê dela. O pagamento não mudou. Os
multiplicadores da campanha continuam valendo (+$ 33 no lugar de 30 com o passe), e a janela mostra
o que entrou de fato (`ProgressionService.addCredits` devolve o valor).

**Bandeiras** (`Controllers/Bandeiras`, em peças de interface, sem imagem para subir):
- EUA de agosto de 1965: 50 estrelas em 9 fileiras de 6 e 5, 13 listras e o cantão de 7 listras;
- Frente Nacional de Libertação: vermelho em cima, azul embaixo e a estrela amarela;
- o pano tem uma sombra de dobra que corre devagar. Ficam no alto à direita de cada ficha de
  alistamento.

**Passe** (`TelaPasse`):
- cada tipo de prêmio com uma cor cheia no ícone: créditos verde, emblema ouro, camuflagem lima,
  título azul, uniforme laranja, cartão de abate vermelho, gesto roxo, música ciano;
- os cartões do Veterano em dourado e os grátis em verde;
- a rota andada e a barra de estrelas em degradê de ouro a laranja; o cabeçalho em degradê quente;
- antes era tudo oliva e latão apagados.

**Conferido no Studio** (capturas em `testes/lote16/`):
- a diária abriu sozinha depois do carregamento;
- RESGATAR deu o dia 1 (RECEBIDO, AMANHÃ no dia 2) e o aviso "+$ 33 Dia de serviço";
- aberta de novo, mostrou "Você já resgatou hoje", com a contagem;
- as duas bandeiras nas fichas de alistamento;
- o passe colorido.

No arquivo local do Studio não há DataStore (PlaceId 0): o resgate fica só na memória e a janela
avisa (a nota de "sem DataStore" agora aparece também nesse caso).

**Não testado:** o resgate num servidor do Roblox (DataStore de verdade); celular e controle na
janela da diária.

## D-131 — Lote 17: camuflagens novas, tigrado e outras (v62, 2026-11-14)

Pedido do dono: "coloque umas camuflagens diferentes tipo tigrado etc". O jogo já tinha três skins de
uniforme nos EUA (OG-107 desbotado, tigrado dos assessores e duck hunter) e o pijama preto no VC.
Entraram mais quatro, dois por lado, com padrões que existiam em 1965 (`Shared/Skins`,
`tools/make_clothing_skins.py`):

| Skin | Lado | Padrão |
|---|---|---|
| Tiger stripe tadpole | EUA | o tigrado esparso do começo dos anos 60 (Rangers e assessores): traços finos e curtos com "cabeça", muito fundo claro |
| Lagarto (paraquedistas) | EUA | o TAP 47 francês dos paraquedistas sul-vietnamitas e dos assessores: pinceladas verticais verdes e marrons sobre verde-claro |
| Áo bà ba marrom | VC | a roupa do camponês do Sul tingida de củ nâu, marrom-avermelhado, no corte do pijama |
| Tiger stripe capturado | VC | tigrado do ARVN tomado em combate, gasto e encardido, no corte do uniforme do VC |

- **Fidelidade:** as cores são de olho (PLACEHOLDER até a foto). O tigrado no VC é raro nas fotos:
  fica com `check = "foto + consultor"`.
- **Moldes:** clássicos de 585 × 559, com a alfaiataria da v3 (costuras, bolsos, sol, suor, lama e
  mãos transparentes). O gerador ganhou os padrões "tadpole" e "lizard" e aceita o corte do VC. Os
  moldes antigos saíram idênticos (o gerador é determinístico).
- **Publicação:** 8 decals (`upload-assets Clothing.`). O `Characters.imageUrl` abre o decal no
  servidor e usa a imagem, como nos uniformes de antes.
- **Venda:** com $ do jogo ($ 15.000, o preço de uniforme). Ainda sem Game Pass em Robux: as chaves
  `PASS_SKIN_*` estão em 0, e o botão de Robux fica escondido até o dono decidir o preço
  (TODO_USUARIO).
- **Prévia:** a Intendência desenha o retalho de cada padrão (`Skin.pattern`: listras finas no
  tadpole, traços verticais no lagarto, liso no marrom).

**Conferido no Studio** (capturas em `testes/lote17/`):
- o soldado nasceu com a skin "skin_us_tadpole": camisa e calça com as imagens do tadpole;
- quatro cópias do soldado, cada uma com um dos moldes novos, mostram os padrões no corpo;
- a Intendência lista os novos, com nome, descrição e preço.

**Não testado:**
- a compra com $ até o fim (o soldado de teste tinha $ 1.306);
- o uniforme do VC num soldado do VC: as cópias usaram o corpo dos EUA, só para ver o pano.

## D-132 — Lote 18: ataque aéreo no objetivo, nos dois lados e com o som do A-4 (v63, 2026-11-14)

Pedido do dono: "o ataque aéreo deve ser nos objetivos e deve afetar os dois lados e deve ter um
som específico quando vai acontecer". Vale para o evento da partida "Ataque aéreo (A-4)"
(`Shared/Eventos`, `Modules/EventosService`). O ataque aéreo pedido pelo comandante
(`FireSupport.us_air_strike`) não mudou.

**No objetivo:**
- antes, o centro recuava até 80 m para longe da tropa de quem pedia (`Eventos.safeCenter`), e as
  bombas podiam cair fora do ponto;
- agora (`onTarget`) cai em cima do ponto forte que os EUA atacam, com quem estiver lá. Só a
  distância mínima dos QGs continua;
- as outras barragens (naval e morteiro) seguem recuando dos amigos.

**Nos dois lados** (`hitsAll`):
- as bombas explodem sem lado (`from = nil`, como destroço e armadilha), então o fogo amigo
  desligado da v41 não vale aqui;
- os dois lados recebem o alerta: "As bombas pegam todo mundo: saia da fumaça violeta";
- o aviso passou de 8 para 10 s, o tempo do avião chegar.

**Som do A-4** (`tools/som_ataque_aereo.py`, `Sounds.a4_mergulho`, 12 s):
- **Síntese:** turbojato chegando em mergulho, sintetizado em numpy:
  - rugido abafado de longe que clareia na chegada;
  - assobio do compressor e da turbina com o Doppler (agudo chegando, grave indo embora);
  - reflexo no chão.
- **Medida:** o centroide do espectro sobe de 770 Hz (1 s) para 3.400 Hz (8,8 s); a passagem fica
  a −3,6 dBFS e o começo a −39 dBFS.
- **No jogo:** o cliente (`AudioController`) lê o marcador do evento (alvo, rumo `RumoX/RumoZ` e
  início no relógio do servidor) e faz o som andar pelo céu na reta do avião, vindo do lado dos EUA
  e passando sobre o objetivo. Quem entra no meio ouve do ponto certo. O clipe se ressincroniza com
  o relógio do servidor (começava ~1,2 s atrasado enquanto carregava).
- **Legenda:** "Avião em mergulho: ataque aéreo chegando".

**Conferido no Studio:**
- o centro do ataque caiu a 0,0 m do ponto forte de C;
- o soldado americano parado no ponto morreu nas bombas do próprio ataque;
- um boneco do VC no ponto caiu, e o americano a 150 m ficou inteiro;
- o som carregou, tocou e passou a ~280 m do soldado; depois do ajuste, o clipe ficou a até 0,06 s
  do relógio do servidor.

**Achado:** um evento disparado durante a contagem de início é cancelado quando a partida começa
(`resetMatch`). Isso já acontecia; na partida normal o primeiro evento só vem no minuto 1.

**Não testado:** o som de ouvido (só medido) e num servidor do Roblox.

## D-133 — Lote 19: caixa de munição maior, bandeiras de pano na mesa e botões do tamanho (v64, 2026-11-14)

Pedidos do dono: "dobre o tamanho das caixas de munição"; "para escolher o lado quero a bandeira de
cada país esticada sobre a mesa, bem detalhadas e texturizadas"; "coloque os botões em caixas que
são do seu tamanho".

**Caixa de munição do Suporte com o dobro do tamanho** (`Shared/CaixaMunicao.ESCALA = 2`):
- as medidas do Blender ficam em `CaixaMunicao.BLENDER`; tamanho, pegada e ícone do jogo saem delas
  vezes 2;
- o `CaixaMunicaoService` escala o modelo publicado a partir do meio da base;
- o espaço livre exigido para pôr a caixa também dobra. O alcance para pegar munição (3 m do centro)
  não mudou;
- no Studio: 1,49 × 1,08 × 0,91 m (era 0,75 × 0,54 × 0,45);
- os caixotes de enfeite das bases ficam do tamanho real: o pedido foi lido como a caixa que o
  jogador põe e usa.

**Bandeiras esticadas sobre a mesa:**
- **Imagens** (`tools/bandeiras_textura.py`, `assets/bandeiras/`, publicadas como decal):
  - EUA de 1965 na geometria da Executive Order 10834: 50 estrelas bordadas em 9 fileiras, 13
    listras costuradas, a tira de lona do mastro com dois ilhoses;
  - a da Frente: metades costuradas e a estrela aplicada com pesponto;
  - nas duas: trama de algodão, vincos de bandeira guardada dobrada, bainha, poeira e sol.
- **Imagem no jogo:** o `ImagensUi` resolve o decal no servidor e põe o ID da imagem em
  `Img_bandeira_*`. O `Controllers/Bandeiras` usa a imagem quando ela chega, e o desenho em peças
  fica de reserva. As bandeiras das fichas de alistamento também ganharam a textura.
- **Na mesa** (`LobbyScene`, sala de arquivo):
  - os dois dossiês saíram, e no lugar ficam as duas bandeiras de pano (Fabric) estendidas, EUA à
    esquerda e a da Frente à direita;
  - clicar na bandeira escolhe o lado;
  - a câmera olha o meio da mesa de cima e de perto. Antes mirava 0,3 m atrás da mesa, e a mesa
    ficava escondida sob as fichas.

**Botões do tamanho:** o "ALISTAR-SE ►" das fichas virou uma caixa do tamanho do texto, no meio da
faixa de baixo; antes era a faixa inteira de 560 px. O JOGAR AGORA ficou como estava, porque mostra
embaixo a barra da espera e o resumo do lado e do squad.

**Conferido no Studio** (capturas em `testes/lote19/`):
- as imagens resolvidas (`Img_bandeira_eua` e `Img_bandeira_frente`);
- as duas bandeiras nítidas sobre a mesa, com estrelas, listras, trama e vincos;
- o ALISTAR-SE do tamanho do texto;
- a caixa de munição com o dobro, cercada pelos bots pegando munição.

**Achado:** a contagem de início ("A PARTIDA COMEÇA EM") aparece por cima da sala de arquivo,
cobrindo o meio da mesa durante a preparação. Isso já acontecia e fica para a lista.

**Não testado:** celular e controle na sala de arquivo; num servidor do Roblox.

## D-134 — Lote 20: a vila de Xóm Gò espalhada e todas as casas abertas (v65, 2026-11-14)

Pedidos do dono: "deixe a vila menos quadrada e mais esporádica"; "ainda não posso entrar em todas
as casas da vila".

**Por que algumas casas não abriam:**
- a vila sorteava 12 variantes de casa, mas só as 10 casas únicas do Blender (`vila_casa_01..10`)
  têm porta e interior;
- a 11 e a 12 estão com ID 0 e caíam na cabana do ForgeGUI, que é fechada: eram 10 das 48 casas;
- agora o gerador só sorteia as 10 (`vila_estradas.N_VARIANTES = 10`).

**A vila fora da grade** (`tools/vila_estradas.py`, `_espalha`). O centro, o rumo da rua, a praça, o
pagode, a casa comunal, o poço, as bancas e as travessas continuam onde estavam. As casas saem das
quatro fileiras retas:
- cada uma anda até 32% do passo ao longo da rua e recua um tanto diferente: a fileira da frente de
  0 a 6 m, a do fundo de −1,5 a 9 m;
- cada uma gira até 18° na frente e até 38° no fundo; 20% das do fundo ficam de lado (±90°);
- 12% dos lotes ficam vazios (roça ou quintal);
- 10 casas soltas ficam mais longe da rua (50 a 78 m), a 24 m das outras;
- cada posição é conferida:
  - corte do terreno e água;
  - dentro da área, fora da rua, da praça e das travessas;
  - folga do pagode e da casa comunal;
  - 17 m entre centros (a diagonal da casa é 15,6 m);
- os becos retos atrás das fileiras saíram. Cada casa ganha a trilha dela, da porta até a rua; se
  essa trilha passar por outra casa, vai até a porta da vizinha.

Resultado: 53 casas (eram 48), 24 recuos diferentes, 22 casas giradas mais de 12° e 40 trilhas.

**Estradas:** com as casas espalhadas, a volta do norte encurtava pela rua da vila e sumia da beira
norte. Os pontos de passagem dela foram para a faixa da beira (N 1693230, a ~50 m da borda). A volta
ficou contínua pela beira norte: 1.662 m de secundária, contra 1.806 antes; a diferença é o desvio
até a ponta da vila, que saiu. A principal e a rua não mudaram (1.247 e 399 m). Na lavoura, um ponto de dique e um trecho de cerca
viva se ajustaram à estrada nova (4 de 1.362 valores dos diques; 1.708 → 1.715 nas cercas).

**Carta tática:** refeita, com as casas giradas e as trilhas; os 4 blocos foram reenviados (os
antigos ficaram como `Carta.*_v64`).

**Antes de mexer:** o pipeline (`git checkout e36ea6d -- Data MapConfig fixture` e
`crop_world.py`) reproduziu os dados atuais byte a byte; só o `MapConfig` difere na formatação do
StyLua.

**Conferido no Studio:**
- **Caminhos:** o `PathfindingService` achou caminho de fora para dentro pela porta (agente de
  1,4 stud de raio e 7,4 de altura) nas **53 de 53** casas.
- **Boneco:** um boneco de 2,08 m (o corpo dos soldados), andando com o `MoveTo` do Roblox, entrou
  pela porta principal nas **53 de 53**.
- **Fotos** (`testes/lote20/`): a vila vista de cima e o interior de uma casa olhando pela porta; as
  plantas de antes e de depois e a carta.

**Fica como estava:** as 28 casas espalhadas pelo resto do mapa, inclusive as de An Cường (2),
seguem com as cabanas fechadas do ForgeGUI.

**Não testado:** um jogador de verdade entrando (o controle de movimento do jogo anula o `MoveTo`
do teste; o boneco usa o mesmo corpo); celular.

## D-135 — Lote 21: vegetação com até 6 mil triângulos (v66, 2026-11-14)

Pedido do dono: "diminua a vegetação para 6 mil triângulos". Isso troca a regra da D-66 (vegetação
com no mínimo 8 mil, na malha cheia do gerador): agora a vegetação tem teto de 6 mil por modelo
(`ArtBudget.MAX.veg = 6000`; o `MIN_VEG` e a lista `BELOW_MIN` saíram). As quantidades, as escalas e
as posições das plantas não mudaram (o plano é o mesmo: 4.835 plantas no servidor).

**Como cada modelo foi reduzido:**
- **9 plantas do ForgeGUI** (`tools/vegetacao_6k.py`): arbusto, capim-elefante, bananeira,
  coqueiro, tràm, taioba, canteiro de arroz e as duas árvores que só servem de substituto (colina
  e emergente).
  - Redução por quádricas (`decimate_glb`) preservando as costuras de UV. Primeiro com a borda
    presa; se parar acima do alvo, com a borda solta.
  - O manifest ganhou o bloco `reducao_local` e o `fetch_forgegui_assets.py` refaz a mesma redução.
- **Bambu sem o disco:** o `tools/blender/bambu_sem_disco.py` tira o disco e depois reduz.
- **4 árvores do Poly Haven** (`tools/prep_trees.py`): 2.050 cartões de folha (eram 4.800 a
  5.200) e 1.850 triângulos de madeira (eram 2.800 a 3.200).
  - Cada cartão cresce ~1,6x e a copa cobre o mesmo volume.
  - Testei também 2.200/1.550 e 1.900/2.150 (`testes/lote21/07_*`); 2.200/1.550 facetava o tronco.
  - Na `ph_tree_small_02`, o tronco para nas costuras de UV (1.339 com a borda solta), então ela
    tem 1.800 folhas.

| Modelo | Antes | Depois | Desvio médio / máximo |
|---|---|---|---|
| arbusto | 10.515 | 6.000 | 3,6 mm / 8 cm |
| capim-elefante | 7.978 | 6.000 | 1,9 mm / 6 cm |
| bananeira | 12.686 | 6.000 | 9 mm / 8 cm |
| coqueiro | 13.261 | 5.999 | 1,0 cm / 16 cm |
| tràm | 10.995 | 6.000 | 2,7 cm / 52 cm |
| taioba | 8.397 | 5.999 | 7 mm / 23 cm |
| canteiro de arroz | 13.066 | 6.000 | 3 mm / 13 cm |
| bambu (sem disco) | 11.428 | 6.000 | 1,4 cm / 1,14 m |
| colina (substituto) | 13.215 | 5.999 | 4,9 cm / 99 cm |
| emergente (substituto) | 13.636 | 6.000 | 6,0 cm / 1,46 m |
| árvores do Poly Haven | 12.554 a 13.736 | 5.948 a 5.955 | (folha refeita em cartões) |

O desvio é a distância de Hausdorff entre a malha original e a reduzida. Nas prévias de lado
(`testes/lote21/04_*`, `06_*`), o arbusto e a emergente perderam algumas folhas; o resto ficou quase
igual.

**IDs:** os 14 modelos foram reenviados. Os IDs antigos ficaram no `assets/roblox_ids.json` como
`Models.<chave>_v65`.

**Desempenho no Studio:**
- **Como:** PC do dono, Studio na frente, sem bots, interface e efeitos do menu desligados.
- **Mesmo script nas duas versões:** 8 s de espera em cada vista e mediana de 4 amostras de 120
  quadros; nos giros, 4 voltas de 8 direções.
- **Rodadas:** duas na v65 e uma na v66. Na tabela, a v65 é a da primeira rodada; a segunda deu
  números parecidos (base 54,5 fps; GPU de 5,2 a 9,6 ms).

| Vista | v65: fps, CPU, GPU | v66: fps, CPU, GPU |
|---|---|---|
| base dos EUA olhando a oeste | 54,0; 17,3 ms; 9,8 ms | 59,4; 15,1 ms; 7,9 ms |
| Xóm Gò olhando a mata A | 60; 12,5 ms; 6,5 ms | 60; 10,8 ms; 5,3 ms |
| borda da mata A | 60; 11,4 ms; 5,6 ms | 60; 10,1 ms; 4,4 ms |
| giro na célula mais densa (79 plantas em 60 m) | 58,3; 13,2 ms; 6,8 ms | 60,0; 11,0 ms; 5,2 ms |
| giro na 2ª célula mais densa | 57,1; 11,9 ms; 5,8 ms | 58,8; 11,5 ms; 5,7 ms |
| por cima do dossel | 60; 13,4 ms; 7,6 ms | 60; 11,2 ms; 5,8 ms |

- **O que mudou:** o tempo de GPU caiu de 0,1 a 1,9 ms por quadro e o de CPU, de 0,4 a 2,2 ms.
- **fps:** o Studio trava o jogo em 60 fps, então o fps só mostra a diferença onde não bate no
  teto: +5,4 fps na base dos EUA e +1,7 fps nos giros.
- **Ruído:** a primeira amostra logo depois de mover a câmera sai baixa (a arte ainda chegando): a
  base deu de 47,5 a 57 fps entre rodadas sem essa espera.

**Fotos** (`testes/lote21/01_*` a `03_*`): mesmas vistas, FOV 70 e 13h, v65 à esquerda e v66 à
direita.

**Não testado:** celular e num servidor do Roblox.

## D-136 — Lote 22: bandeiras iguais, grama mais baixa e contagem de 10 s (v67, 2026-11-14)

Pedidos do dono:
- "deixa as bandeiras na escolha de lado do mesmo tamanho";
- "diminua 1/3 da altura da grama";
- "faça de 10 seg a contagem regressiva onde os jogadores podem pegar os veículos etc, porém não
  podem sair da base".

**Bandeiras:**
- Antes, a dos EUA era 1,96:1 (1,9:1 mais a lona do mastro) e a da Frente 3:2, e a dos EUA ficava
  bem mais larga na mesa.
- Agora as duas usam o mesmo retângulo de 5:3, a proporção comercial da bandeira dos EUA (3 x 5 pés),
  com a lona do mastro dentro. Nada foi esticado:
  - `tools/bandeiras_textura.py` desenha as duas já em 1.020 x 612 px;
  - cantão em 2/5 do comprimento;
  - a estrela da Frente com o mesmo raio.
- `Bandeiras.RATIO` = 5:3 para as duas. A mesa (`LobbyScene.flagOnTable`) e as fichas de alistamento
  usam a proporção comum.
- Imagens reenviadas; as antigas ficaram como `Images.bandeira_*_v66`.

**Grama:** `Terrain.GrassLength` de 1 para 0,67 no bake (`tools/bake_place.luau`, `GRASS_LENGTH`). Só
o plugin ou o arquivo do place escreve essa propriedade.

**Contagem** (`MatchService.PREP_S` 30 → 10; `PreparoService`):
- Pegar veículo já era livre na contagem. O que faltava era prender o veículo: quem estava sentado
  saía da base dirigindo.
- Agora, a cada 0,5 s, o veículo com gente dentro que passou de 60 m do QG volta 6 m para dentro do
  raio. Ele volta na mesma altura sobre o chão (o helicóptero no ar), de frente para o QG, parado e
  com quem está sentado.
- Quem é puxado de volta (a pé ou no veículo) ganha +1 no atributo `PrepVolta` do Player. A contagem
  mostra "Não saia da base!" em vermelho por 2,5 s; o texto normal é "Pegue um veículo e espere na
  base" (traduções em en, es e vi).
- **Contagem fora da mesa:** a contagem aparecia por cima da mesa de escolha de lado e tapava as
  bandeiras; ali o número ficava parado em 10, porque a partida espera cheia até alguém nascer. Agora
  só aparece em campo: personagem vivo, papel escolhido e o `VT65LobbyBackdrop` desligado.

**Conferido no Studio:**
- a pé, levado a 80 m: voltou para 58 m;
- no jipe M151, levado a 90 m: voltou para 54 m em 1,2 s, sentado, parado e de frente para o QG
  (cosseno 0,98);
- nascendo no QG ninguém é puxado (o ponto de nascer fica dentro dos 60 m);
- em campo, a contagem vai de 9 a 1 e mostra "VALENDO!";
- fotos em `testes/lote22/`.

**Não testado:** um jogador de verdade dirigindo para fora (o teste moveu o jipe pelo servidor);
celular.

## D-137 — Lote 23: recompensa diária e passe para crianças (v68, 2026-11-14)

Pedido do dono: "melhore ainda mais as recompensas diárias e o passe, deixe elas mais atrativas para
crianças e deixe as escritas e principalmente as recompensas escritas maiores".

**Recompensa diária** (`Controllers/DiariaEntrada`):
- **Janela:** passou de 820 x 486 para 920 x 596 px de projeto. O `UiKit.fit` reduz em tela menor.
- **Letras maiores:**
  - título 34 → 44 px, em dourado;
  - regra 15 → 19 px, em branco: "Entre todo dia: o prêmio cresce! Pulou um dia, volta ao dia 1.";
  - valor de cada dia 19 → 30 px, em dourado;
  - nome do item 12 → 15 px;
  - etiquetas 12 → 16 px;
  - texto do resultado 16 → 20 px.
- **Desenho do prêmio em cada dia:** um círculo de cor viva com 💰 (créditos, dourado) ou 🎁 (dia com
  presente, roxo). O dia já recebido troca pelo ✔ verde. O 7º dia fica em dourado (o maior prêmio).
  Sem lado escolhido, o item aparece como "+ presente surpresa".
- **Dia de hoje:** o desenho pula (1 → 1,14) e o contorno dourado pisca enquanto o prêmio está para
  pegar; a etiqueta é "HOJE!" em dourado.
- **Dias seguidos:** "🔥 N" em dourado.
- **Botão:** verde vivo (`UiKit.PAGAR.premio`, novo: pegar prêmio não é compra), "PEGAR O PRÊMIO DO
  DIA N!" em 28 px com o valor em dourado. Pulsa enquanto há prêmio.
- **Ao receber:** 14 moedas e brilhos voam do cartão num leque para cima e o valor recebido sobe em
  letra grande (54 px) e some em 1,5 s.

**Passe** (`Controllers/TelaPasse`):
- **Painel:** a altura passou de 640 para 684 px de projeto.
- **Cartões:** 128 x 116 → 152 x 152 px; nome do prêmio 13 → 18 px; tipo 11 → 13 px; ícone 46 → 60 px.
- **Cabeçalho e marcos:** título 30 → 36 px; nível 40 → 48 px; nomes das trilhas 17 → 22 px; número
  dos marcos 14 → 17 px.
- **Ficha de baixo:** nome 26 → 32 px; texto 14 → 17 px, em branco.
- **Ícones:** emoji no lugar das letras (K, U, T, C, G):
  - 💰 créditos, 🎖️ emblema, 🌿 camuflagem, 🏷️ título, 👕 uniforme;
  - 💀 cartão de abate, 👋 gesto, 🎵 música, ⚡ reforço, ⭐ estrelas.
  O Roblox já desenha emoji nos eventos e na carta.
- **Prêmios futuros:** ficam legíveis (branco com 12% de transparência), não cinza; só o que já foi
  pego fica apagado.
- **Prêmio pronto para pegar:** contorno verde de 3 px que pisca devagar (um laço só, com a tela
  aberta).
- **Botões:** RECEBER e RECEBER TUDO em verde vivo (`premio`).

**Traduções:** quatro textos novos em en, es e vi; `premio` (o tipo do botão) no `ignorar.json`.

**Conferido no Studio:**
- a diária aberta;
- o resgate: moedas, "+$ 33" subindo, ✔ e RECEBIDO no dia 1, AMANHÃ no dia 2, 🔥 1;
- o passe com os ícones novos;
- fotos de antes e depois em `testes/lote23/`.

**Não testado:**
- o brilho dos prêmios prontos do passe (a conta de teste estava no nível 0);
- celular e TV (só a janela do Studio, de 671 x 564 px).

## D-138 — Lote 24: aviso de granada perto (v69, 2026-11-14)

Pedido do dono: "coloque símbolo de granada perto: vermelho que vai matar você e branco que vai dar
dano".

**Regra** (`Shared/GrenadeWarn`, módulo puro, testado em `tests/luau/combate.luau`):
- **Vermelho:** dentro do raio letal da granada (`Explosive.TYPES`), contado em pé: EUA 5 m, VC 4 m.
  Em pé é o pior caso (agachado ou atrás de cobertura o raio real é menor, `ExplosionService`),
  então o vermelho nunca falta quando a explosão mataria. O teste confere que, dentro do vermelho,
  `Explosive.effect` dá "lethal" em pé.
- **Branco:** do raio letal até o raio de baixas (EUA 15 m, VC 12 m), onde os estilhaços ferem.
- **Nada:**
  - mais longe que o raio de baixas;
  - granada de fumaça;
  - granada do próprio lado, que não fere (fogo amigo desligado, `Medical.blocked`).
- **A sua própria granada fere você e aparece.** O `FieldService` agora marca a granada com o
  `UserId` de quem jogou (atributo `By`).

**Tela** (`Controllers/AvisoGranada`, acima do HUD de campo):
- **Símbolo:** a granada desenhada (corpo redondo, alavanca e anel do pino), com a distância
  ("4 m"). O vermelho pulsa; o branco fica parado.
- **Granada à vista:** o símbolo fica em cima dela na tela.
- **Granada fora da vista:** o símbolo vai para um anel em volta do meio da tela (30% do menor lado),
  na direção dela, com uma seta para fora e a distância do lado de dentro.
- **Limites:** até 4 granadas (as mais perto); some fora de campo e quando ela explode.
- **Câmera:** a de cada quadro (o jogo troca de câmera entre o menu e o campo).

**Conferido no Studio** (`testes/lote24/01_aviso_de_granada.jpg`):
- três granadas do VC postas paradas:
  - 9 m à frente: branca, em cima dela;
  - 8 m à direita: branca, no anel com a seta para a direita;
  - 3 m atrás: vermelha, embaixo no anel;
- a granada jogada por mim: o aviso acompanhou o voo, vermelho de 1 a 5 m, branco de 7 a 15 m, e
  sumiu depois.

**Não testado:** celular e TV; várias granadas na mesma direção (os símbolos do anel se sobrepõem).

## D-139 — Lote 25: ícone, miniaturas e nome da página (2026-11-14)

Pedido do dono: "faça as alterações das imagens e nome do jogo, eu dou acesso para você". O nome
escolhido é **STARLITE: Vietnã 1965** (D-101); as imagens são as capas do dono em `marketing/capas`
(fora do Git, o repositório é público).

**Caminho:** o guia do Open Cloud "Manage experience icons and thumbnails":
- a imagem sobe como Image de uso aberto (Create Asset, `assetPrivacy` OpenUse);
- o place aponta para ela: Update Asset com `updateMask=icon` ou `previews`;
- tudo pelo comando novo `tools/roblox_cloud.py pagina [nome|icone|miniaturas|descricao]`, que lê
  `marketing/pagina.json`. Os IDs ficam no `roblox_ids.json` (`Pagina.*`).

**Feito:**
- **Ícone:** recorte quadrado da capa 01 (o soldado de capacete, 941 x 941 px a partir da direita),
  reduzido a 512 px, com o título STARLITE / VIETNÃ 1965 no estêncil das capas, embaixo (o rosto
  fica no alto). `tools/capa_titulo.py --icone --embaixo`. Legível a 150 px. O ícone anterior (um
  capacete numa estaca, em `assets/capa`) parece túmulo e atrai pouco criança.
- **Miniaturas:** as 8 capas na ordem do dono (a 01, com o título, primeiro), com texto alternativo
  em português. A página não tinha nenhuma.
- A leitura pela API confirma `icon` e as 8 `previews`. Os jogadores veem depois da moderação do
  Roblox.

**Pendente:**
- **Nome:** o PATCH do place (cloud/v2) voltou HTTP 403 "Scope not authorized": a chave não tem
  `universe.place:write`. Os passos estão no `TODO_USUARIO.md` (dar a permissão ou trocar à mão).
- **Descrição:** a de hoje fala do mapa antigo (2 x 2 km), de até 50 contra 50 e do operador de
  rádio. O texto novo, com o jogo de hoje (30 contra 30, 5 objetivos, os papéis do `Roles`, a
  recompensa diária e o passe), está em `marketing/descricao.txt` (883 caracteres). Só sobe com o
  aceite do dono (`pagina descricao`), porque é o texto público da página.

**Não feito:** as miniaturas da página inicial (Thumbnail Personalization); pedem outra permissão
(`universe.thumbnail:write`).

**Concluído no mesmo dia, depois da v73:**
- O dono pediu "uma descrição para crianças gostarem". O texto novo de `marketing/descricao.txt`
  tem frases curtas e emojis, mostra o que dá para fazer (5 bandeiras, os lugares do mapa, os
  papéis, veículos, eventos, pá e túneis) e os prêmios (diária que cresce, presente surpresa,
  camuflagens, passe, posto e medalhas). Tem 957 de 1000 caracteres e uma linha em inglês no fim.
  Só promete o que existe: o ataque aéreo e o apoio naval são eventos da partida, e o comandante
  pede ataque aéreo e suprimentos (EUA) ou reforço pelos túneis e carregadores (VC).
- O dono aprovou. A API recusou de novo (HTTP 403). O dono entrou na conta no navegador do app, e
  o nome **STARLITE: Vietnã 1965** e a descrição foram trocados no Creator Dashboard (Game
  details → Save). Conferido depois de recarregar a página.

## D-140 — Lote 26a: objetivos novos, bases mais longe e mais relevo (v70, 2026-11-14)

Pedidos do dono:
- (com uma imagem de mapa) "ideia de mapa para você, porém mantenha 1 objetivo na floresta densa e
  deixe as bases mais longe dos objetivos";
- "faça mais relevos no jogo para que fique mais realístico".

Comecei a aumentar o mapa para 1 km, porque a imagem dizia "1.000 m x 1.000 m". O dono corrigiu: "não
quero mapa de 1 km, quero de 700 m x 700 m, só estou dando ideia dos objetivos". O mapa continua o da
D-123. Da imagem vieram os objetivos e os cantos.

**Objetivos** (`tools/crop_world.py`; as cinco faixas de setor da D-128 não mudaram):

| Setor | Objetivo | Canto | Era | QG mais perto |
|---|---|---|---|---|
| A | Arrozais | sudoeste | Baixada sudoeste | 296 m (era 270) |
| B | Serraria | noroeste, na mata fechada | Mata fechada | 294 m (era 266) |
| C | Xóm Gò | centro | Xóm Gò | 295 m |
| D | Ponte e Cais | sudeste | Arrozal ao sul de An Cường (2) | 318 m (era 252) |
| E | Engenho | nordeste | Vau do riacho | 291 m (era 254) |

- **Bases mais longe:** os quatro objetivos dos cantos foram para perto das bordas norte e sul (55 a
  65 m delas) e para longe da borda da própria base. As bases ficaram onde estavam (no meio das
  bordas oeste e leste): a dos EUA já vai a 7 m da borda.
- **Lados:** a imagem punha os EUA a oeste. Ficaram a leste, do lado do mar (os fuzileiros
  desembarcaram pela Green Beach).
- **Mata fechada:** é a Serraria. `Vegetation.DENSE_NAMES` e a clareira de 10 m
  (`Landscape.CLEAR_NAMED_M`) seguem o nome; ela continua sem estrada (145 m da estrada principal) e
  com 25 plantas a até 25 m.
- **Arrozais:** o Landscape e o `relevo_dem` reconhecem o objetivo de arrozal por "arroz" (era
  "arrozal", que não pega "Arrozais"). A lavoura fica em volta dele (0 plantas a até 25 m) e a carta
  mostra os tabuleiros no sudoeste.
- **Menu principal:** os planos ficam na praça, na Serraria e nos Arrozais.
- Os nomes estão traduzidos (en, es, vi).
- **Pendente (lote 26b):** a ponte, o cais, a serraria e o engenho ainda não têm construção (por
  enquanto há só a bandeira); falta o rio no sul ligando os Arrozais à Ponte e Cais.

**Mais relevo** (`crop_world.mais_relevo`, antes da vila e das estradas, que se ajustam ao chão):
- O relevo real (DEM, D-66) tem só ~23 m de desnível no mapa; a mata parecia plana.
- **O que entra:** morros e grotas de design, um campo aleatório suavizado (semente fixa, desvio de
  40 m), até ±10 m (95% dos pontos), 50% maior fora da área jogável.
- **Onde não entra:** o peso vai a zero perto do que precisa de chão plano:
  - casas: de 25 a 60 m;
  - feições da lavoura (diques, sebes e lâminas): de 12 a 40 m. As da mata o jogo nem põe
    (FeatureBuilder);
  - riacho: de 15 a 40 m;
  - objetivos: de 35 a 70 m;
  - túneis: de 20 a 50 m;
  - vila de Xóm Gò: de 150 a 200 m;
  - bases: de 80 a 120 m;
  - lavoura dos Arrozais: de 130 a 160 m.
- **Resultado:** 38% da área ganhou relevo novo, de até 8,3 m; o desnível foi de 23,2 para 26,8 m.
  Rampa do chão: 95% abaixo de 26%. Fica gravado no Grid (`reliefAdded`): rodar de novo não soma.
- **Estradas:** principal com 1.501 m e secundária com 1.463 m (eram 1.247 e 1.662). O leito
  continua com rampa até 15%; o M48 vai e volta do QG a todos os objetivos (99,8% das células).

**Carta:** refeita e reenviada (os blocos antigos ficaram como `Carta.*_v69`).

**Testes:** o `modo.luau` comparava a distância "antes" e "agora" do sorteio de pontos com `<`; com um
ponto por setor as duas são iguais e o teste só passava por arredondamento. Agora aceita igual.

**Conferido no Studio** (fotos em `testes/lote26/`):
- os nomes dos setores no `MapConfig`;
- as distâncias de cada objetivo ao QG mais perto, medidas no jogo;
- a mata cerrada na Serraria e a lavoura nos Arrozais;
- o HUD com A a E;
- a carta tática com os objetivos novos nos cantos;
- o menu principal na Serraria.

**Não testado:** a partida inteira; o relevo de perto, no chão (as fotos de cima mostram pouco); o
celular.

## D-141 — Lote 26b: construções dos objetivos e o rio do sul (v71, 2026-11-14)

Pedido do dono (a mesma ideia de mapa da D-140): a serraria, o engenho, a ponte e o cais, e o rio no
sul ligando os Arrozais à Ponte e Cais. O mapa continua de 700 x 700 m.

**Rio do sul** (`crop_world.abre_rio`, logo depois do riacho; gravado no Grid como `riverCut`):
- Leito de 12 m de largura, fundo plano a 9,0 m e espelho a 9,6 m (fundo inclinado viraria
  degraus de 1,12 m na água, por causa do voxel de 4 studs).
- **Traçado** (`RIO_PONTOS`, de design):
  - no oeste corre por fora da borda sul, a ~20 m da área, para não inclinar os tabuleiros dos
    Arrozais;
  - entra no mapa a leste deles e passa 25 m ao sul da Ponte e Cais;
  - sai pelo sudeste e recebe o riacho fora da área.
- **Margens:** descem em rampa até a água (22%, 30 m de cada lado) e nunca sobem o chão. Não
  rebaixam a até 10 m de um tabuleiro nem a até 2 células do riacho. A margem mais baixa junto da
  água fica a 10,5 m, rebaixo máximo de 8,1 m.
- **Números:** 489 células de leito, 233 dentro da área. Saíram 12 diques que cruzavam o leito e
  nenhuma lâmina.
- **Carta:** o leito largo é uma mancha d'água com as duas margens em traço (o riacho continua em
  linha).

**Construções** (`ArtPlan.OBJECTIVE_LAYOUT` e o bloco da ponte em `ArtPlan.structures`):
- **Em peças** (`MapLife.objectivePart`), sem modelo novo para subir. São medidas de projeto
  (PLACEHOLDER):
  - **serraria:** galpão aberto de toras com palha, a mesa comprida com a tora, o cavalete da serra
    e a serragem;
  - **toras:** pilha de 9 em três camadas, escorada;
  - **tábuas:** pilha com sarrafos para secar;
  - **moenda:** de tração animal, com a pista, os três rolos de pau, a almanjarra, uma cobertura
    de palha e feixes de cana;
  - **caldeira:** casa das tachas aberta, de telha, com a fornalha de tijolo, três tachos de
    ferro e a chaminé;
  - **ponte, cais e sampana.**
- **Modelos que já existiam:** cozinha (galpão e armazém), casa de telha, cabana, celeiro, meda
  de palha e saco de arroz.
- **Onde cada peça fica:**
  - a 10–15 m do mastro, de frente para ele;
  - num giro do conjunto (12 tentados) em que nenhuma peça cai em lâmina, dique, estrada, beco,
    riacho, patamar, outro objeto ou ponto de nascer;
  - sem lugar, a peça se afasta até +24 m e até 0,6 rad para o lado. O Engenho precisou disso: o
    mastro fica na estrada, com o riacho a 10 m e dois pontos de nascer;
  - cada construção ganha patamar no terreno, como as casas.

| Objetivo | Peças (medido no plano, `tools/objetivos_plano.luau`) |
|---|---|
| A Arrozais | cabana (21 m), meda de palha (10 m), celeiro (11 m) |
| B Serraria | galpão da serra (11 m), toras (11 m), tábuas (10 m), cozinha (13 m) |
| D Ponte e Cais | ponte, cais, 2 sampanas, armazém e 4 sacos de arroz |
| E Engenho | caldeira (12 m), meda (11 m), casa de telha (21 m), moenda (30 m) |

- **Ponte:** 20 m x 3,6 m, na célula de rio mais perto do mastro, atravessada no leito e
  recentrada no meio dele.
  - Apoiada nas duas margens, no nível da mais baixa; estacas a cada ~4 m e guarda-corpo de 1 m.
  - O tabuleiro fica ~1,5 m acima da água. Dá para um jipe pela largura (não testado com veículo).
- **Cais:** 7 x 3 m na margem do lado do mastro, a 14 m da ponte.
  - 5,5 m sobre a água, no nível do chão a 1 m da beira; postes de amarração na ponta.
  - Travessas sob as pranchas e um degrau de embarque na ponta, 0,8 m abaixo do tabuleiro. No
    Studio, só com o tabuleiro alto, o cais parecia uma mesa dentro do rio.
  - As sampanas ficam no espelho d'água, uma de cada lado.
  - O armazém e os sacos de arroz ficam em terra.
- A ponte, o cais e as sampanas não têm patamar (o patamar tira a água) e não descem ao chão mais
  baixo da pegada (`Item.afloat`).
- **Serraria:** a clareira passou de 10 para 22 m (`Landscape.CLEAR_NAMED_M`), o pátio do galpão.
  A mata cerrada continua em volta até 70 m.
- **Carta:** galpões e casas dos objetivos em preto; a ponte com o símbolo das guardas e das asas.

**Correção da v70 (regressão):**
- O `mais_relevo` protegia a lavoura das casas da carta, mas a lavoura das casas soltas de Xóm Gò
  só é posta depois (`vila_e_estradas`).
- Com isso, o relevo inclinou tabuleiros que se viam, e o filtro de chão plano os tirou: o bake
  montava 44 lâminas na v69 e 24 na v70.
- Agora toda lâmina é protegida, e os diques e sebes a até 50 m de uma também: 53 tabuleiros ficam,
  0 em ladeira. O bake monta 47 lâminas.

**Testes:**
- O `run.luau` procurava o riacho varrendo cada linha de oeste para leste e achava antes o rio
  novo. Agora varre do leste.
- A margem do riacho perto da foz (N 1692,56) ficava abaixo do espelho dele (11,69 m contra
  10,67 m). Corrigido no `abre_rio` (margem longe do riacho).
- O `ArtEstimate` conta os modelos dos objetivos (a ponte de toras que ele somava não existe).

**Conferido no Studio** (Play, sem bots):
- as 28 peças montadas aparecem (log "28 em peças"): serraria, toras, tábuas, moenda, caldeira,
  ponte, cais e as 2 sampanas, com o rio cheio d'água;
- os modelos dos objetivos (cozinha, casa de telha, cabana, celeiro e medas) ficam rentes ao chão:
  0,00 m entre o fundo e o terreno;
- o soldado atravessou a ponte a pé em 6,5 s, só correndo (sem nadar), com a raiz a 43,9–44,0
  studs sobre a água;
- 47 lâminas no arrozal do terreno real.

**Não testado:** veículo na ponte; o rio visto do chão em toda a extensão; a partida inteira; o
celular. O aviso "1 construção com o chão real a mais de 0,6 m do patamar" é de um celeiro perto
de Xóm Gò (0,79 m abaixo do chão), fora dos objetivos: fica para o lote 27.

## D-142 — Lote 27: bugs de textura, gráficos, movimento, tiros e granadas (v72, 2026-11-14)

Pedido do dono: "conserte bugs de textura, gráficos, movimentação, tiros, granadas etc.". Sem uma
lista dele, os bugs saíram de três lugares:
- o Output do Studio;
- o autoteste dos 12 sistemas, rodado com e sem bots e numa sessão nova;
- as pendências da análise do lote 12 (`testes/ANALISE_LOTE12_2026-11-14.md`).

**Tiros: os sons das armas nunca tocavam** (`Controllers/Som`).
- **Causa:** o pré-carregamento conferia os 17 ids de fora (Pro Sound Effects, D-107) passando o id
  em texto, e o Roblox o pedia como imagem: "Asset type does not match requested type". Todos davam
  falha. O jogo tocava o som reserva (`alt`) ou nada: o ferrolho, o estojo caindo e o baque da bala
  no corpo não têm reserva.
- **Medido no Studio:** os 8 ids testados falham em texto e carregam como `Sound` (de 0,13 a 3,4 s).
- **Correção:** a conferência usa instâncias `Sound`.
- **Conferido:** numa rajada de 1 s da M60 tocaram o disparo da metralhadora (18 vezes, com a
  camada de corpo) e o estojo (5). A sessão inteira teve 0 avisos "does not match".

**Tiros: cadência abaixo de ~12 fps** (`Shared/Gatilho`, `WeaponController`).
- O gatilho soltava um tiro por quadro: a 10 fps a RPD dava 9 tiros por segundo (a ficha dá 11,7).
- Agora, no automático, o quadro longo solta até 2 tiros (`PER_FRAME`). O atraso acumulado fica em
  no máximo 1 intervalo, e o 1º tiro de cada aperto conta de agora (um toque rápido continua dando
  1 tiro).
- O servidor já guarda 2 créditos de cadência: aceita todos.
- **Teste novo (`armas.luau`):**

  | Arma | 10 fps | 5 fps |
  |---|---|---|
  | RPD | 11 tiros | 9 tiros |
  | Type 56 | 10 | 9 |
  | M60 | 9 | 7 |

  Todos aceitos pelo servidor; a 5 fps eram no máximo 5.
- Não medido no Studio (o Studio roda acima de 12 fps com ele na frente).

**Granadas: a dos bots caía longe** (`FieldService.throwFrom`).
- A conta do arco era feita no pedido, mas a granada sai 0,4 s depois, de onde a mão estiver (o bot
  anda).
- Depois de cair, ela quica e rola uns 2,5 m.
- **Correção:** a velocidade é refeita no instante em que a mão solta, e o bot mira 2,5 m antes do
  alvo.
- **Autoteste (alvo a 25 m):**
  - antes: 2,7, 2,9, 5,4 e 6,3 m do alvo;
  - agora: 2,2, 3,9, 1,2, 5,5 e 0,2 m (1 falha em 5 rodadas, pelo limite de 5 m).
  - O quique continua sorteado (giro e chão).

**Movimento: as teclas agiam por baixo da tela de carregamento** (`Controllers/Input`).
- A pá cavou durante o "Recebendo o mapa inteiro" (D-129).
- Agora, com a tela `VT65Loading` na frente, nenhuma ação do jogo sai.
- **Conferido:** com a tela reaberta, o C não agachou; sem ela, agachou.

**Pá de trincheira** (`FieldWorkService`). O autoteste da pá falhava na 1ª rodada de cada sessão
desde o lote 12. A causa eram os sacos de areia:
- `AssetLoader.place` põe um patamar de terra sob construção, e os sacos estavam girados 90°: o
  comprido apontava para o buraco. O aterro tapava o buraco recém-cavado.
  - **Agora:** o parapeito vai atravessado, 1 m à frente do centro, sem aterro (`placeAt`, assentado
    no chão mais baixo de 3 pontos).
- **Piso:** a pá cavava sob piso sólido (o autoteste cavou sob a esteira do heliponto dos EUA, com
  o buraco invisível).
  - **Agora** ela recusa: "Pá: aqui tem piso, procure chão de terra". O raio é curto, na faixa de
    0,6 m acima do chão, porque o raio de cima batia no helicóptero parado.
- **Fundo do buraco:** o fundo herdava o capim, e a grama animada crescia dentro e o escondia.
  Agora é terra (conferido: `Ground`).
- **Aviso:** "Cavando… fique parado 8 s" saía com o ✗ de erro. Agora é aviso de andamento.
- **Autoteste da pá:**
  - mede a roda de 2,5 m à frente, antes e depois;
  - confere o teletransporte (repete até 3 vezes; na rodada final precisou de 2);
  - segura o soldado parado enquanto cava (com os bots na base, um esbarrão cancelava).

**Gráficos:**
- **Caveira do abate** (`Controllers/Caveira`): a imagem publicada nunca aparecia. O
  pré-carregamento dava "Success", mas o código conferia o `IsLoaded` da imagem escondida, que fica
  falso. Agora vale o estado do pré-carregamento (0 avisos na sessão).
- **Anexos enterrados na vila** (`ArtPlan`): na divisa de dois terraços da encosta, o patamar da casa
  vizinha cobria parte do anexo.
  - O chão ali é a média dos dois e o anexo descia: um celeiro 0,8 m e duas cozinhas 0,4 m.
  - Agora os anexos do quintal vão depois de todas as casas e ficam de fora quando caem dentro do
    patamar de outra casa com outro nível. Saíram 6.
  - Nenhuma construção da vila fica mais de 0,3 m fora do chão do plano.
- **Bezerros** (autoteste "vida no mapa"): An Cường (2) ficou sem arrozal a até 200 m (o mais perto
  a 171 m, fora da área) e sobrava uma manada só. Agora há manada também nos Arrozais (2 bezerros).

**Conferido e sem bug:** deitado numa encosta de 14,8°, o soldado andou 0,01 m em 5 s. A falha do
autoteste ("deslizando 1,12 m/s") veio do lugar em que ele estava, perto do buraco da pá.

**Tradução:** o aviso novo da pá em en, es e vi. Os 18 nomes de peças do lote 26b (Cepo, Serra,
`parts:ponte`…) foram para `ignorar.json`: são identificadores e tinham escapado na v71.

**Autoteste final** (1ª rodada de uma sessão nova, com bots): 18 ok, 0 falhas, 0 pulados.

**Não feito (fica na lista):**
- a mão de apoio das pistolas no quadril;
- a Type 54 escura em 1ª pessoa;
- a cadência abaixo de 12 fps medida num aparelho lento de verdade;
- o quique da granada (a variação de até 5,5 m).

## D-143 — Lote 28: pistola no quadril e a Type 54 (v73, 2026-11-14)

Os dois itens que sobraram do lote 27 (análise do lote 12).

**Pistola no quadril** (`WeaponVisuals`, `HIP_PISTOL`).
- A pose do quadril era a do fuzil para todas as armas. Na pistola, o punho ficava a 23 cm do olho,
  18 cm abaixo e 12 cm à direita (medido no Studio).
- Com isso, as mãos saíam cortadas pela borda de baixo da tela e o braço esquerdo atravessava a
  tela: a mão de apoio parecia solta ("mão escorregando").
- As mãos estavam no lugar: a esquerda fica a 2 cm do punho mirando e no quadril.
- Agora a pistola tem quadril próprio, com os braços estendidos: o punho a 40 cm do olho, 17 cm
  abaixo e 7 cm à direita (mirando, 53 cm). As duas mãos aparecem fechadas no punho.
- O fuzil e as outras armas não mudam.

**Type 54:** conferida e sem bug.
- Vista de lado, à luz do dia: aço oxidado preto, punho marrom com a estrela; a textura
  (`SurfaceAppearance`) carrega.
- Em 1ª pessoa parece toda escura porque, de trás, só se vê a corrediça preta (a M1911 também).
- A arma em 3ª pessoa, no corpo do soldado, usa a mesma malha com a mesma textura.

**Não conferido:** a pistola caída no chão; o celular.

## D-144 — Lote 29: tradução da Intendência, acampamento do VC na mata e o quique da granada (v74, 2026-11-14)

Itens da lista de ideias (análise do lote 12), depois do "siga" do dono.

**Intendência em outros idiomas:**
- O equipamento aparece como `"• nome  (peso kg)"` (`Controllers/Progresso`). O nome sozinho
  estava no dicionário, mas a linha montada não: com o jogo em inglês, os 10 itens ficavam em
  português ("Bandoleira M2 de algodão").
- Entrou o modelo `"• %s  (%.1f kg)"` em en, es e vi.
- Dois nomes do VC não estavam em dicionário nenhum: "Bi đông extra (cantil)" e "Túi cứu thương
  (bolsa de socorro)".
- **Teste novo (`idiomas.luau`):** toda linha de equipamento traduz nos três idiomas.
- Fora isso, nos módulos de itens só ficam sem tradução os postos do VC em vietnamita e os modelos
  de arma, de propósito.

**Acampamento do VC na mata** (`Landscape.HQ_FOREST_M`, `Vegetation.DENSE_HQ_M`).
- **Antes:** no mapa de 700 m, o QG do VC caiu em roça seca (a carta de 1965 tem lavoura ali, perto
  de casas). As barracas, as redes e a cozinha ficavam no capim baixo.
- **Agora:** até 45 m do QG a roça vira mata, com a mesma mata cerrada da Serraria (1,8x).
- **Continuam sem planta:**
  - as pegadas e os patamares;
  - os pontos de nascer, com a clareira de 15 m e a visada;
  - a raia de tiro;
  - a saída da picape (`Vegetation.VC_DEPOT_EXIT_M`: três círculos de 5 m do abrigo até a
    trilha).
- **Medido no Studio:**
  - plantas a até 45 m do QG: 30 só com a mata, 73 com a mata cerrada;
  - setor A: ~4,8 milhões de triângulos (o setor B tem ~8,5);
  - as árvores cobrem as barracas; o meio continua aberto, que é a clareira de quem nasce.
- **Carta:** refeita (o acampamento aparece na mata); os blocos antigos ficaram em `Carta.*_v71`.

**Quique da granada: medido, sem mudança.** Cópia fiel da física (`FieldService.launch`) num chão
plano de capim, com 12 a 16 arremessos de 25 m por variante:

| Variante | Onde para, em relação ao ponto de queda mirado |
|---|---|
| Física de hoje | +3,5 m em média, desvio de 3,3 m (de −5,9 a +6,9 m) |
| Freio também nos quiques baixos | −1,1 m em média, desvio de 3,5 m (de −11,7 a +2,1 m) |
| Giro zerado e metade da velocidade no 1º toque, mais o freio | −3,0 m em média, desvio de 4,7 m (até −17 m) |

- Nenhuma variante foi claramente melhor, e a física ficou como estava.
- O erro é quase todo na direção do arremesso: de lado, ~0,1 m.
- A mira dos bots 2,5 m antes do alvo (D-142) compensa a média: erro mediano de 1,1 m.

**Não feito:** o desempenho num celular e num servidor do Roblox (precisa de aparelho do dono).

## D-145 — Lote 30: roda do mouse, gatilho com item na mão e o aviso de conexão (v75, 2026-11-14)

**Pedidos do dono (14/11, 18h26 a 19h22)**, divididos em lotes:
- lote 30: bugs graves;
- lote 31: armas (SKS, M14, M16);
- lote 32: bots;
- lote 33: mapa (base dos EUA, vila, estradas, pontes);
- lote 34: interface (entrar no veículo, inserção de helicóptero).

O questionário de classificação ficou como rascunho, **sem envio**: o dono disse "não faça isso
porque vai dar +18". O jogo continua para 16+.

**"As roletas de arma não estão funcionando"** (`Controllers/Input`):
- **Causa:** "roleta" é a rodinha do mouse. Ela já estava ligada à troca de arma, mas o giro era
  descartado quando chegava "processado", e a câmera do Roblox também usa a roda.
- **Agora:** só uma lista da interface (`ScrollingFrame` sob o ponteiro) segura a roda.
- Um giro manda vários eventos seguidos, que viravam várias trocas encavaladas; agora é uma troca a
  cada 0,18 s.
- **Studio:** um giro para baixo trocou da M14 para a M1911; um para cima voltou à M14, à vista.

**"Os itens não funcionam; a arma atira mesmo invisível"** (`ItemView.handsBusy`,
`WeaponController.canShoot`):
- **Causa:** com o curativo, o torniquete, tratar, reanimar, a pá ou o cantil nas duas mãos, a arma
  sai da vista, mas o gatilho só olhava a granada, a troca e a faca.
- **Agora** o gatilho não sai com as mãos ocupadas.
- **Studio:** com a bandagem nas mãos, 1 s de gatilho deu 0 tiros; sem ela, 2 tiros.
- **"Quando eu tento voltar para a arma ela some":** no meio do curativo ou da pá, a tecla da arma
  não fazia nada (a arma volta sozinha no fim), e parecia que ela tinha sumido. Agora aparece "Mãos
  ocupadas: a arma volta ao terminar".
- **Teclas que funcionam** (conferido com o teclado no Studio):
  - granada (3) e volta (1);
  - binóculo (7) e volta (1);
  - pá (8);
  - a bandagem sem ferimento recusa com o aviso do servidor.

**"Fica aparecendo conexão instável"** (`Aparelho.netStep`, `Reconexao`):
- **Regra antiga:** acusava com o ping acima de 0,45 s por 3 s, ou com 2 s quase sem dados, mesmo
  com o ping bom.
- **Regra nova:** ping acima de 0,7 s por 4 s, ou 3 s quase sem dados com o ping também acima de
  0,3 s.
- A faixa diz o motivo: "Ping alto: N ms", "Servidor lento (N Hz)" (pelo `BotHz` que o servidor
  publica; abaixo de 40 Hz a culpa é dos bots, não da conexão) ou "Quase nada chegando do
  servidor".
- O console do cliente (F9) registra `[VT65 REDE]` com o ping, os dados e os Hz.
- **Não medido no jogo publicado:** no Studio a regra não roda (a rede local não diz nada); vale o
  teste do Lune.

## D-146 — Lote 31: M16 da foto, SKS refeita e a mira da M14 (v76, 2026-11-15)

**Pedidos do dono (14/11):** "cadê a arma M4" (com a foto de um M16), "a mira da arma SKS está ruim
e dá pouco dano", "aumente a distância da mira da M14" e "utilize o Blender para criar as coisas
necessárias".

**M16** (`tools/blender/m16.py`, `Shared/Weapons`):
- O M4 é de 1994. A foto é o M16 da Guerra do Vietnã: guarda-mão triangular, alça de transporte,
  quebra-chamas de três dentes, carregador reto de 20. É o que foi feito.
- **Modelo no Blender:** 6.516 triângulos, atlas de 1024 px, 1,5 MB.
  - Materiais: plástico preto, alumínio anodizado e aço fosco.
  - A alça de transporte é um canal: a linha de visada passa por dentro dela até o poste.
  - Mira: anel de 5 mm e poste entre as orelhas da base em "A"; raio de visada de 0,502 m.
- **Ficha:** 5,56 x 45 mm (M193), 991 m/s, 750 tiros/min, 20 tiros, seletor semi e automático. Dano
  do fuzil (36).
- **Tiros para cair** (`tests/luau/combate`): 3 no tronco até 100 m, 4 a 200–300 m, 5 a 400 m (a bala
  leve perde energia rápido).
- **Quem leva:** escolha do fuzileiro, do suporte, do líder e do enfermeiro dos EUA
  (`Roles.PRIMARY`). Nos bots, o primeiro fuzileiro de cada squad dos EUA.
- **Som:** o disparo automático, mais agudo que o do Tipo 56 (PLACEHOLDER de ouvido).
- **Sem skin:** skin pede Developer Product, que é do dono.

**SKS** (`tools/blender/sks.py`):
- **Causa da mira ruim:** a SKS do gerador era uma malha só. Mirando, a linha de visada batia na tampa
  e na alavanca do ferrolho; o entalhe e a massa não apareciam limpos.
- **Agora:** refeita no Blender como a carabina Tipo 56 chinesa (a SKS do VC): coronha avermelhada,
  baioneta de espigão dobrada, carregador fixo de 10. 5.090 triângulos, 1,3 MB.
  - A linha de visada fica a 34 mm do cano. Telha de cima, tubo de gases e braçadeira ficam abaixo
    dela, e a tampa da culatra 15 mm abaixo.
  - Entalhe de 4,4 mm (o real é mais estreito; o de 2,6 mm saía com ~6 px no Studio) e poste de 2,4
    mm dentro do capuz redondo.
  - Aço com metal 0,3: com 0,6 o Roblox refletia o céu e a culatra saía cinza-clara na mira.
- **Dano:** 50 (era o do fuzil, 36, igual ao Tipo 56, que tem o mesmo cartucho e é automático).
  - Agora: 2 tiros no tronco até 100 m e 3 até 400 m; braço 4.
  - Com a vantagem de vida (1,12), 3 de perto.
  - O teste de combate trava esses números.
- **Asset:** a de antes fica no `roblox_ids.json` como `Models.sks_gerador`. O
  `tools/weapon_landmarks.py` usa os pontos do Blender quando o `pontos.json` existe.

**M14:** o olho fica a 10 cm da alça de anel (`adsEyeM`; era 4,5 cm, e o anel enchia a tela).

**Defeito do `tubo`** (`tools/blender/armas.py`):
- O tubo virava o anel 180° a cada ponto e saía torcido, em ampulheta. No M16 o punho e o guarda-mato
  saíram quebrados.
- Agora o anel segue o tubo sem girar.
- O M70, o Mosin e a Escopeta 12 publicados foram feitos antes da correção: guarda-mato, gatilho e
  zarelhos estão torcidos até serem refeitos.

**Studio (v76):**
- M16: na mão, com mira no anel. 1 s de gatilho no semi deu 1 tiro (carregador 20 → 19), sem recusa
  do servidor.
- M14: o anel pequeno no meio, com a caixa da culatra em volta.
- SKS nova: entalhe em U no meio, com a ponta do poste dentro; aço escuro.
- **Visto e não explicado:** numa sessão, o soldado do VC caiu "por estilhaços de granada, a poucos
  metros" logo depois de nascer no QG, sem bots no mapa. Não se repetiu em outra sessão (14 s depois
  do começo da partida, vida 112 o tempo todo).

## D-147 — Lote 32: bots atiram de mais longe e trabalham em equipe, no nível médio do Front 44 (v77, 2026-11-15)

**Pedido do dono (14/11):** "os bots estão tendo que chegar muito perto para atirar e não estão
trabalhando em equipe; faça eles no nível mediano igual do Front 44".

**Causa de "chegar muito perto"** (`BotBrain.F44`, v41):
- O combate do Front 44 foi copiado com os números de lá, inclusive a visão de 160 studs (44,8 m).
- Os mapas do Front 44 vão até 1.000 studs (Bastogne, 280 m); este tem 700 m. Além de 45 m o bot não
  via ninguém.
- A mira de lá soma 0,008° por stud: a 100 m o erro passava de 4°, e o bot quase não acertava.

**Agora: o Front 44 na escala daqui:**
- **Distâncias × 2,5** (`F44.escala`, 700 m ÷ 280 m): visão até 112 m no aberto (a mata continua
  tapando a 40 m e o capim a 15 m), parado e agachado para atirar além de 49 m, escopeta até 28 m,
  pistola até 49 m, tiro ouvido até 77 m.
- **Mira × 2** (`F44.escalaMira`): o bot daqui a 50 m mira como o de lá a 25 m. Com a mira também ×
  2,5, um jogador parado no aberto levava tiro em 96% das vezes em 3 s a 50 m, o mesmo da v36, que o
  dono achou forte demais.
- Reação (0,45 s), rajadas, giro e movimento ficam os do Front 44.
- **Chance de acertar ao menos uma vez em 3 s um jogador parado, em pé, no aberto** (automática /
  semi, `tests/luau/bots`):

  | Distância | 10 m | 25 m | 50 m | 75 m | 100 m | 112 m | 120 m |
  |---|---|---|---|---|---|---|---|
  | Antes (v76) | 100 / 100 | 81 / 50 | 0 | 0 | 0 | 0 | 0 |
  | Agora | 100 / 100 | 100 / 100 | 81 / 50 | 40 / 19 | 19 / 8 | 14 / 6 | 0 |

**Trabalho em equipe** (`BotBrain.TEAM`, `BotService`, `BotSquads.contactOf`):
- **Causa:** no combate do Front 44, o aviso de contato do squad (`BotSquads.callout`) era enviado,
  mas ninguém o usava. Cada bot só ia atrás do que ele mesmo viu ou ouviu.
- **Contato do squad:** o que um vê, ou de onde veio o tiro que ele tomou, chega aos outros em 1 a
  2,2 s (`calloutS`), e eles vão até lá.
- **Fogo e movimento:** no ataque com contato, o squad se divide em duas metades que se revezam a
  cada 5–8 s.
  - Quem cobre segura o lugar agachado e atira no contato (supressão, só dentro do alcance da arma).
  - Quem avança vai até ele.
  - A metralhadora sempre cobre.
- **Flanco:** um homem por squad (lugar 3) vai primeiro a um ponto 25 m ao lado do contato (e 5 m
  antes dele) e entra pelo lado. Só a mais de 35 m do contato, e um ponto por combate.

**Studio (v77), mesma partida, 30 x 30 bots, servidor a 41–58 Hz,** gancho novo
`workspace:SetAttribute("VT65DevBots", "distancias")`:

| Janela | Rajadas em alvo | Mediana | 90% até | Máximo | Além de 45 m | Cobertura | Flancos |
|---|---|---|---|---|---|---|---|
| Escala nova, 4,5 min | 718 | 55 m | 75 m | 112 m | 588 (82%) | 169 | 25 |
| Escala antiga, 4 min | 464 | 38 m | 43 m | 45 m | 0 | 110 | 13 |

- O gancho `VT65DevBots = "escala1"` volta à escala antiga, para comparar; `"escala"` devolve a nova.
- Primeiro tiroteio da partida aos 83 s, a 89 m.

**Não medido:** se o jogador sente o nível médio numa partida de verdade (vale a impressão do dono).

## D-148 — Lote 33: vila em meio círculo, estradas de terra, ponte para o tanque e a base dos EUA mais longe (v78, 2026-11-15)

**Pedidos do dono (14/11):**
- "faça a vila num formato meio circular mas não perfeito" e "quero que seja esporádica";
- "as estradas não estão feitas de terra";
- "faça as pontes grandes o suficiente para passar um veículo como o tanque";
- "a base americana está muito perto dos objetivos, coloque ela mais longe".

**Vila de Xóm Gò em meio círculo** (`tools/vila_estradas.py`):
- **Antes:** duas fileiras de lotes de cada lado de uma rua reta. A D-134 só empurrava e girava as
  casas dentro dessa grade, e na carta a vila continuava um retângulo de fileiras.
- **Agora:** a rua é o diâmetro e as casas ficam em cinco arcos em volta da praça, de um lado só
  (raios de 30 a 102 m, 18 m entre arcos).
  - **Torto:** o raio ondula pelo ângulo, cada ponta do meio círculo sorteia ±10°, e cada casa
    sorteia raio (±4 m), ângulo e giro.
  - **Esporádico:** 18% das vagas ficam vazias; há 8 casas soltas além do último arco e 4 do outro
    lado da rua.
  - Todas as casas olham para a praça (com giro livre de ±28°; 15% de lado).
  - Pagode no fundo da praça, casa comunal e bancas do mercado do outro lado da rua.
  - Cada porta tem uma trilha até a praça, e duas trilhas largas vão da praça ao fundo da vila.
- **Ajustes medidos:**
  - Com 15 m entre arcos (menos que os 17 m entre casas) e o sorteio de ±6 m, a vila ficou com 28 e
    depois 29 casas das 44 vagas que cabem no chão.
  - Com as pontas a −12°/192° e 8 casas do outro lado, parecia um círculo inteiro cortado pela rua.
  - A praça fica no centro do mapa (D-123), na janela E 269817–269842.
- **Resultado:** 32 casas (eram 53). 24 do lado do meio círculo, de 16° a 171°, de 43 a 130 m da
  praça, 23 de frente para ela.
- A estrada principal contorna a vila pelo sul; antes cortava a vila no meio.

**Estradas de terra** (`TerrainLook.COLORS.Ground`):
- A estrada já era do material `Ground` com a foto de terra batida (D-115). O tom da D-123 (150,
  168, 200) puxava para o azul e a terra saía cinza, ~(107, 92, 78).
- Sem a foto (aparelho fraco, foto carregando), sobre o `Ground` padrão do Roblox, a estrada saía
  cinza-azulada.
- **Agora:** (190, 172, 148), levemente quente: com a foto, ~(136, 94, 58), marrom de laterita.
- **Studio:** a troca de material pela foto está ativa (`GetBaseMaterialOverride(Ground)` =
  `VT65_Ground`); a praça e a rua saíram marrom-alaranjadas.

**Ponte para o tanque** (`ArtPlan.BRIDGE_WIDTH_M`, `MapLife` "ponte"):
- A ponte da Ponte e Cais tinha 3,6 m, só um jipe (o M48 tem 3,63 m). Agora tem 7 m, a largura da
  estrada principal.
- Ganhou uma fileira de estacas no meio e três vigas sob o tabuleiro.
- **Studio:** tabuleiro de 20 x 7 m.
- **Teste das estradas:** o tabuleiro conta como chão (antes, a ponte era um obstáculo). O M48 fica
  preso em 97 células (0,08%), no seco e na chuva. Na v77 eram 90 no seco e 2.783 na chuva, no
  mesmo trecho do rio: a ponte larga virou a saída.
- É a única ponte do mapa: o riacho é atravessado por aterro de estrada (5 a 7 m), e não há
  "Riacho" nos locais para a ponte de toras.

**Base dos EUA mais longe dos objetivos** (`tools/crop_world.py`):
- A base já encosta na borda leste: vai de 48 m a oeste a 42,5 m a leste do QG, e o QG fica a 50 m
  da borda. O mapa fica de 700 x 700 m (o dono confirmou na D-140), e a leste da borda, a 100 m do
  QG, passa o riacho.
- Por isso o que foi para longe foram os objetivos e a linha do setor:
  - **Fronteira S4/S5** de E 270040 para 270000. O portão da base fica a 86 m do setor que o VC pode
    tomar (eram 46 m). S4 tem agora 80 m (era 120) e S5, 180 m (era 140).
  - **D Ponte e Cais** de E 270000 / N 1692640 para 269930 / 1692645, na margem norte do rio (em N
    1692620 caía no leito e a estrada descia para dentro dele). Do QG dos EUA: 348 m (eram 318).
  - **E Engenho** de E 270070 / N 1693215 para 270045 / 1693233, a 47 m da borda (o teste pede 45).
    Do QG: 315 m (eram 291).
  - A volta norte das estradas passa a N 1693195 perto do Engenho (era 1693230).

**Junção das estradas** (`vila_estradas.suaviza`):
- A altura do leito era guardada só nos vértices de cada estrada (um a cada 2 células).
- Uma estrada que começava no meio de outra não ficava presa e entrava 1,4 m abaixo (rampa de 68% na
  ponta sul da rua nova da vila).
- Agora a altura vale em todas as células, interpolada. Rampa máxima medida no chão: 25,6%; o M48
  sobe 53% em terra na chuva.

**Paddy:** rodar o `crop_world.py` de novo tirou 26 diques e 4 sebes que não encostavam em nenhum
tabuleiro (sobra do rio da D-141). Pela regra do `reduz_arrozal`, eles saem.

**Carta:** refeita e reenviada (Carta.nw/ne/sw/se; os IDs da v71 a v77 ficaram como `*_v77`).

**Não testado:** um M48 atravessando a ponte no Studio. Vale o teste das estradas e a medida do
tabuleiro.

## D-149 — Lote 34: entrar no veículo com os lugares importantes e "Passageiro", e o texto do helicóptero (v79, 2026-11-15)

**Pedidos do dono (14/11):** "para entrar no veículo dê as opções importantes e as outras junte em
passageiro" e "simplifique o texto de inserção do helicóptero".

**Painel de entrar no veículo** (`VehiclePrompt`, `Vehicles.seatGroups`, `Vehicles.pickPassenger`):
- **Antes:** uma linha por lugar. O M35 e o LVTP-5 mostravam 14 e 15 linhas (motorista, carona e 12
  "Tropa").
- **Agora:**
  - os lugares importantes ficam um por linha: motorista ou piloto, atirador (ou a porta do
    UH-34D), comandante, municiador e copiloto;
  - o carona e a tropa viram uma linha só, "PASSAGEIRO", com "N DE M LIVRES" (e "· ATIRA" se algum
    livre deixa atirar com a própria arma), "LOTADO" ou "VOCÊ";
  - um toque nela põe o jogador no primeiro lugar livre de onde se atira e, sem ele, no primeiro
    livre.
- **Linhas por veículo:**

  | Veículo | Linhas importantes | Passageiro (lugares) |
  |---|---|---|
  | M48 | 4 | — |
  | Ontos | 3 | — |
  | LVTP-5 | 3 | 12 |
  | UH-34D | 3 | 8 |
  | M35 | 1 | 13 |
  | M151 | 1 | 3 |
  | Peugeot | 1 | 7 |

- O lugar "Tropa N" passou a se chamar "Passageiro N" (aparece assim no HUD de dentro do veículo).
- O modelo do subtítulo já vai em caixa alta ("%d DE %d LIVRES"): o dicionário não traduz "%d de %d
  livres" depois do `upper` (conferido no Lune: "3 DE 12 LIVRES" ficava sem tradução).

**Helicóptero** (`Eventos.DEFS.heli`, `EventosService`, `EventosHud`):
- **Nome:** "Helicóptero de reforço" (era "Inserção de helicóptero").
- **Aviso do lado que chega:** "Helicóptero pousando perto de C Xóm Gò: você pode nascer nele!". Era
  "UH-34D pousando reforços na LZ BS 699 929, a 140 m de C Xóm Gò. Nasça na LZ."
- **Aviso do outro lado:** "Helicóptero inimigo pousando perto de C Xóm Gò: ataque antes que os
  reforços saiam!". Era "Helicópteros pousando na LZ BS 699 929! Ataque a LZ antes que o reforço
  avance."
- **Linha do evento na tela:** "perto de C" (era "C · BS 699 929").
- **Ponto de nascimento:** "Helicóptero perto de C" (era "LZ — inserção (BS 699 929)").
- **Recompensas:** "Chegou de helicóptero" e "Atacou o helicóptero" (eram "Inserção pela LZ" e
  "Ataque à LZ").
- Traduções em inglês, espanhol e vietnamita (11 frases).

**Studio (v79):**
- O helicóptero veio sozinho no começo da partida, com os textos novos: o título "HELICÓPTERO DE
  REFORÇO", o aviso e a linha "perto de C".
- **Não visto no Studio:** o painel de entrar. No cliente de teste nenhum ProximityPrompt foi
  mostrado (PromptShown não disparou nem a 7 m do M35). O Studio estava com um controle fantasma,
  que trocava de arma e abria a carta sozinho. Valem o teste dos veículos (os grupos e a escolha do
  lugar) e o caminho do servidor, que não mudou (Vehicle_Board com o id do lugar).

## D-150 — Lote 35: M70, Mosin e Escopeta 12 refeitas com o tubo certo (v80, 2026-11-15)

**Pedido do dono:** "faça isso", em resposta à oferta de refazer as três armas que tinham guarda-mato,
gatilho e zarelhos torcidos (o `tubo` do `tools/blender/armas.py` virava o anel 180° a cada ponto;
corrigido na D-146).

- **Refeitas no Blender:** `armas.py -- m70 mosin` e `espingarda.py -- win12`, sem mudar a forma.
  - M70: 5.576 + 352 triângulos.
  - Mosin: 6.632 + 400.
- **Antes e depois** (prévia do GLB):
  - na Escopeta 12, o guarda-mato era um zigue-zague e virou um laço limpo;
  - na M70, o guarda-mato e os zarelhos saíram retos.
- **IDs novos:** M70 76814352866440, Mosin 87591536414880, Escopeta 12 88021040446518. Os antigos
  ficam no `roblox_ids.json` como `Models.*_v79`.
- O `WeaponArt` não mudou: os pontos são os mesmos, e a mira da Escopeta 12, medida de novo no GLB,
  deu o mesmo.
- **Studio:** a Escopeta 12 carrega o modelo novo na mão.
## D-151 — Lote 36: o botão da 3ª pessoa e o tronco que para a bala (v81, 2026-11-15)

**Pedidos do dono:** "onde está o botão para 3ª pessoa?" e "as árvores devem tancar os tiros".

**3ª pessoa** (`Toque`, `ToqueTelas`, `PainelComandos`, `ThirdPerson`):
- **Onde fica:**
  - computador: tecla O;
  - controle: ↑ no direcional;
  - celular e tablet: o botão CÂMERA, que tinha saído da tela na v39 e voltou.
- **Botão CÂMERA no toque** (id `view3p`): no canto de baixo à esquerda, ao lado do analógico.
  - Tocar troca 1ª / 3ª pessoa; segurar troca o ombro. Tem 9 mm, o mínimo do teste.
  - O lugar saiu de uma busca em todas as telas e layouts do teste do toque: embaixo do MAPA
    encostava nele, e entre o RÁDIO e a MIRA ou na fileira do alto não cabia no celular 16:9. No
    canto sobram 13 px.
- **Coluna de comandos** (computador e controle): ganhou a linha "1ª / 3ª pessoa", antes do Mapa.
- **Dica do primeiro nascimento:**
  - no controle dizia "Segure → no direcional", mas o comando é ↑ tocado; agora diz "↑ no
    direcional";
  - no toque, "Botão CÂMERA: 1ª / 3ª pessoa".
- **Nome do comando no toque:** era "MENU" (a câmera tinha ido para Configurações > Toque); agora
  é "CÂMERA" e "CÂMERA (segurar)".
- Traduções das 4 frases novas em inglês, espanhol e vietnamita.

**Tronco que para a bala** (`tools/troncos.py`, `Modules/TreeTrunks`, `Modules/TrunkProxy`,
`AssetLoader`):
- **Antes (medido no Studio, v80):** a bala só para em peça com colisão. Nas árvores prontas isso
  era a peça `Madeira0`, com a colisão automática do Roblox (um casco aproximado do tronco com os
  galhos grossos).
  - Na `ph_tree_small_02` (171 na área), a `Madeira0` é a galhada a mais de 7 m do chão. O tronco
    de verdade (`Madeira1`) não tinha colisão: todo tiro na altura de um soldado passava.
  - O coqueiro (159 na área) não tinha nenhuma peça sólida.
- **Agora:** cada árvore leva cilindros invisíveis (`Tronco_1`, `Tronco_2`...) que param a bala e o
  soldado, mas não o veículo (grupo `VT65Tronco`, D-67).
  - Os cilindros saem da malha: `tools/troncos.py` corta a madeira em fatias de 0,25 m e liga os
    contornos de uma fatia para a outra, do pé até 5 m (no coqueiro, 9 m) ou até o caule se abrir
    em galhos.
  - Caule com raio abaixo de 6 cm não conta; galho grosso que sai do tronco conta (menos no
    coqueiro, onde lá em cima é a copa). Até 6 cilindros por árvore.
  - Ficam no template: o clone leva junto e escala com a planta.
  - Copa, galhos e a madeira desenhada ficam sem colisão: a bala passa por eles como antes, perdendo
    um pouco (Ballistics.PASS).
- **Cilindros por árvore** (na escala típica da mata):

  | Árvore | Cilindros | Até | Raio (m) |
  |---|---|---|---|
  | ph_island_tree_01 | 6 | 4,1 m | 0,37 a 0,85 |
  | ph_island_tree_02 | 6 | 4,8 m | 0,16 a 0,61 |
  | ph_island_tree_03 | 3 | 0,8 m | 0,10 a 0,12 |
  | ph_tree_small_02 | 2 | 4,8 m | 0,28 a 0,31 |
  | coconut_palm | 3 | 6,5 m | 0,17 a 0,33 |

  A `ph_island_tree_03` tem caules finos e tortos: acima de 1 m todos têm 6 cm de raio ou menos, então
  só o pé para a bala.
- **Mapeamento:** o pivô do modelo é a origem do GLB. O ponto do GLB vai ao modelo com x e z
  trocados de sinal (o giro de 180° do importador, D-58), conferido nas peças da
  `ph_island_tree_02` no Studio.
- **Studio (v81):**
  - Bala com a regra do `Hitbox.trace`, em 16 direções a 0,5, 1,2 e 1,6 m, em 12 árvores de cada
    tipo: 192 de 192 tiros pararam no tronco invisível em cada altura e tipo (na
    `ph_island_tree_03`, só a 0,5 m).
  - `Hitbox.trace` da M16 a 25 m, mirando o tronco a 1 m de altura, 4 tiros em cada uma de 30
    árvores por tipo:

    | Árvore | No tronco | No terreno antes |
    |---|---|---|
    | coqueiro | 110 de 120 | 10 |
    | ph_tree_small_02 | 115 de 120 | 5 |
    | ph_island_tree_02 | 120 de 120 | 0 |
    | ph_island_tree_01 | 116 de 120 | 4 |

    Nenhum tiro passou.
  - Fotos com os cilindros pintados de vermelho (coqueiro, `ph_tree_small_02`, `ph_island_tree_01`
    e `_02`): o cilindro fica dentro do tronco desenhado.
  - Os bots continuam vendo 1.793 troncos que barram os veículos, o mesmo número da v80
    (`BotWorld.markTrunks` aceita a `Madeira0` sem colisão quando há o tronco invisível).
- **Muda para quem anda:** o soldado esbarra no cilindro do tronco, não mais no casco do tronco com
  os galhos grossos. Não testado andando no Studio.
- **Teste novo** (F5): toda árvore que a mata põe tem tronco medido, e a peça cai no cilindro sem
  descer do pé.

## D-152 — Lote 37: medir o mapa e mexer no que pesa (v82, 2026-11-15)

**Pedido do dono:** aplicar um texto sobre beleza e desempenho do mapa: medir antes e depois, sombra
só no que importa, simplificar o que está longe, colisões simples, cuidado com a transparência da
folhagem, reuso de modelos e detalhe nos caminhos, interiores e objetivos.

**Medida completa:** `testes/DESEMPENHO_2026-11-15.md`.
- **Método:** seis vistas fixas, sem bots, com a qualidade gráfica fixa nos níveis 10 e 3. Contam as
  chamadas de desenho e os triângulos por quadro; cada mudança foi testada em A/B na mesma vista.
- **Limite:** o Studio ficou atrás de outra janela (o dono usava o computador). O fps travou em 15 e
  o tempo de CPU por quadro oscilou entre ~12 e ~30 ms sem relação com o teste. Por isso não há
  número de fps antes e depois.

**O que pesava** (base dos EUA, nível 10):
- casas e objetos: 1,56 milhão de triângulos, quase tudo a cerca de bambu;
- outras plantas (bambu, palmeira, capim-elefante, bananeira, taioba, tràm): 1,34 milhão;
- folhas: 0,43 milhão;
- madeira: 0,44 milhão;
- arbustos: 0,35 milhão;
- sombra: 187 chamadas (461 na base do VC).

**Mudou:**
1. **Sombra das copas respeitando a opção "Sombra das árvores"** (defeito; `AssetLoader`,
   `Graficos`):
   - a planta sai do servidor sem sombra, e o cliente liga ou desliga subindo até o modelo com
     `PlantShadow`;
   - antes, a folha num submodelo (`Folhas0_0_Node`) escapava da busca, e as copas que chegavam pelo
     streaming ficavam com sombra com a opção desligada (586 numa sessão);
   - **Studio:** desligada, 0 peças de copa com sombra; ligada, 1.758; desligada de novo, 0;
   - **A/B:** de 8 a 52 chamadas de sombra e até 260 mil triângulos a menos por quadro.
2. **Cerca de bambu: 16.418 → 6.000 triângulos** (`tools/vegetacao_6k.py`, motivo próprio no
   manifest):
   - ela entra no teto da vegetação (D-135), uma exceção à regra de não reduzir objetos abaixo de 20
     mil (D-66);
   - **por quê:** 62 das 65 cercas ficam em An Cường (2), na frente da base dos EUA, e eram 1,12
     milhão de triângulos nessa vista (um quarto dela);
   - desvio máximo de 1,4 cm; de perto, no Studio, continua igual;
   - ID novo 134018898436044 (o antigo fica como `Models.bamboo_fence_v81`).
3. **Cortina de fora da área sem os troncos invisíveis da D-151:** 1.754 peças a menos.

**Testado e não entrou** (números no relatório):
- **Sombra desligada nos 148 objetos pequenos** (potes, sacos, caixas, arame farpado, varal):
  - as chamadas de sombra não mudaram (242 → 247; 476 → 467);
  - no máximo 90 mil triângulos a menos;
  - o Roblox já desenha os iguais juntos.
- **Folhas com transparência:** escondê-las mudou a GPU em menos de 1 ms. Não é o gargalo no PC.
- **Colisões:** a física custa 0,045 ms por passo com 25 mil peças paradas. Script também não muda o
  `CollisionFidelity`.
- **Distância e reuso:** todas as malhas já usam `RenderFidelity` automática. São 12.044 malhas de
  759 modelos, com 100 a 290 chamadas de cena por vista.

**Antes e depois:**
- **Triângulos no nível 3:**
  - base dos EUA 3,00 → 2,49 milhões (−17%);
  - Xóm Gò 1,24 → 1,12;
  - base do VC 2,34 → 2,20;
  - mata B, ponte e arrozal iguais (sem cerca).
- **Peças no mapa:** 24.868 → 23.114.
- **Peças com sombra no servidor:** 2.677 → 919.
- **Arte no mapa:** 34,66 → 33,98 milhões de triângulos.

**Decisão do dono** (o relatório lista):
- afinar bambu, capim-elefante e bananeira longe dos caminhos e dos objetivos (1,3 milhão de
  triângulos nas vistas das bases);
- sombra do sol desligada por padrão no celular;
- medir o fps num celular e num servidor cheio.

## D-153 — Lote 38: bambu, capim-elefante e bananeira afinados longe dos caminhos (v83, 2026-11-15)

**Escolha do dono** (depois do lote 37): "afinar plantas longe" (concentrar o detalhe nos caminhos e
objetivos).

**Regra** (`Vegetation.FAR`, `Vegetation.farKeep`, `roadSegments`, `focusCircles`):
- **Onde:** na mata, a mais de 30 m das estradas e trilhas (`Data/Roads`) E a mais de 60 m de
  objetivo, QG ou vila da carta.
- **Quanto:** fica metade do bambu, do capim-elefante e da bananeira. A passagem é suave em 15 m.
- **Como:** cara ou coroa fixo pela posição, depois de todos os sorteios (como a D-127). O resto da
  mata fica igual planta por planta.
- **Fora da regra:** a mata cerrada da Serraria (D-123), a cortina de fora e as plantas de quintal,
  sebe e vila.
- O `tools/ArtEstimate` usa a mesma regra.

**Medido:**
- **No Studio:**
  - bambu 603 → 524, capim-elefante 633 → 503, bananeira 254 → 202;
  - mata 4.877 → 4.616 plantas;
  - arte 33,98 → 32,42 milhões de triângulos (−4,6%).
- **Vistas, nível 3 (milhões de triângulos):**
  - arrozal A 2,58 → 2,41;
  - ponte D 1,60 → 1,55;
  - base VC 2,20 → 2,16;
  - as outras, iguais dentro da oscilação.
- **Por que o ganho por vista é pequeno:** o que saiu fica no fundo da mata. As vistas das bases olham
  para as vilas, cujo bosque fica inteiro.
- **Captura** a 70 m da estrada: as árvores, os arbustos e o capim do chão continuam. Fica menos
  bambu, capim-elefante e bananeira por baixo.

**Jogo:** menos esconderijo longe dos caminhos (onde se flanqueia). Perto das estradas e dos objetivos,
nada muda.

**Teste novo** (F5):
- o plano afinado é o completo sem algumas plantas das três espécies, na mesma ordem;
- nenhuma some perto de estrada ou objetivo;
- longe de tudo fica perto da metade (260 de 539 com a semente do teste).

## D-154 — Lote 39: SLIM, baking e trim sheets no nosso pipeline (2026-11-15, sem versão nova)

**Pedido do dono:** aplicar um texto sobre SLIM, baking e trim sheets. O primeiro passo que ele
sugere é testar o SLIM numa casa e num pequeno conjunto. Relatório:
`testes/SLIM_BAKING_TRIM_2026-11-15.md`.

**SLIM não dá para testar hoje.** A documentação pede três coisas:
- o Team Create ligado (a nuvem só gera o SLIM nesse caso);
- o place salvo no Roblox;
- o modelo salvo no arquivo do place com `LevelOfDetail = SLIM`, parado durante a partida.

O que trava:
1. **Toda a arte é posta pelo `AssetLoader` quando o jogo abre** (D-57), e as casas são tingidas
   nessa hora.
2. **O Team Create** é configuração da experiência, decisão do dono.
3. **O Lune 0.8 (pipeline) não grava SLIM.** No teste, o Studio aceitou `LevelOfDetail = SLIM` em
   `vila_casa_03`, `granary`, `water_jar` e `straw_stack`, num place XML de rascunho. O Lune falhou ao
   ler e gravar:
   - não conhece o valor 4 do `ModelLevelOfDetail`;
   - não lê o `Content` novo (`<uri>`), e as malhas chegaram sem `MeshId`;
   - erro de tipo no `AssetService.Tags` ao gravar.

**Baking:** já é o caminho do projeto (`comum.assar`):
- as casas da vila têm 3 atlas de 1024 assados do modelo detalhado;
- as bases, os veículos e a faca também.

**Trim sheets:** hoje cada modelo do Blender tem os próprios atlas.
- São 104 texturas diferentes nas casas da vila e 138 nas bases.
- Uma folha comum da vila (madeira, bambu, palha, metal, amarrações) diminuiria isso, à custa de
  refazer o UV e de parte do detalhe único.

**Nada mudou no jogo.** Decisões do dono:
- ligar o Team Create e autorizar a troca do Lune, para o teste do SLIM;
- testar uma trim sheet da vila numa casa.

## D-155 — Lote 40: o SLIM preparado (arte fixa no place, desligada até o Team Create) (v84, 2026-11-15)

**Escolha do dono:** "Preparar o SLIM" (depois da D-154).

**O caminho** (sem trocar o Lune):
1. `tools/estatico_copiar.luau`: rodado no servidor do Studio pelo MCP, copia do jogo rodando um
   conjunto já posto pelo `AssetLoader` (assentado, escalado, tingido e com o `MapLife` aplicado).
   - O texto é compacto: malha, posição, giro, tamanho, colisão, sombra e texturas.
   - Ele passa pela conversa porque o assistente do Studio não deixa mandar por HTTP; foi conferido
     por uma soma FNV calculada no Studio.
   - O primeiro conjunto é `assets/estatico/vila_casa_03_xomgo.txt`: a `vila_casa_03` da entrada de
     Xóm Gò, o pote, a cozinha, o celeiro e duas cercas (6 modelos, 61 peças).
2. `tools/estatico.py` gera um `.model.json` do Rojo por modelo (`src/Workspace/Estatico`) e o
   `Modules/StaticArt` (chave e pivô de cada um).
   - Cada modelo leva `LevelOfDetail` = 4 (SLIM), `ModelStreamingMode = Atomic` e os atributos
     `VT65Estatico` e `VT65Chave`.
   - O Rojo grava o valor 4, e o Lune 0.8 passa adiante sem ler.
3. `tools/bake_place.luau` põe os modelos em `Map.Art` com o nome da chave.
4. `AssetLoader`:
   - reaproveita a pasta `Art` do arquivo;
   - quando a cópia do plano cairia no mesmo lugar (mesma chave, pivô a menos de 1 stud), devolve a
     fixa no lugar (`staticModel`). Assim a casa conta na vida da vila e nos animais, e o sorteio
     segue igual;
   - não mexe no `ModelStreamingMode` da fixa.
   - Chaves que dependem do jogo rodando (estacas punji, escadas, fumaça do VC, cancela) são
     recusadas.

**O que o Rojo 7.4 aceita** (testado):
- `CFrame` só no formato tipado `{"CFrame": {"position", "orientation"}}`. Sem o tipo, ele dá o erro
  enganoso "no project file was found";
- os atributos tipados dentro de `Properties` (`{"Attributes": {"Attributes": {...}}}`). No topo do
  `.model.json` ele aceita e ignora em silêncio;
- `WorldPivotData` como `{"OptionalCFrame": ...}`, `InitialSize` e `LevelOfDetail` `{"Enum": 4}`.

**Studio:**
- Com o conjunto ligado:
  - o arquivo tem os 6 modelos com SLIM, Atomic e os atributos (50 caixas de colisão da casa com
    `Material`);
  - o servidor pulou as 6 cópias;
  - o log bate com a v83 em tudo (390 construções, 27 animais, a mesma vida nas vilas, 855 modelos,
    240 abrigos dos bots);
  - os raios param nas paredes da casa fixa;
  - a foto de fora é idêntica à da v83.
- **Diferença achada:** o interior da casa fixa sai claro, e o da v83, escuro.
  - Peça de malha criada fora do Studio não traz a colisão calculada (`PhysicsData`), e a luz do
    Roblox usa essa forma para a sombra de dentro.
  - Testado no Studio: com `Hull` calculado na hora, o interior escurece; com `Box`, continua claro.
  - As peças que colidem vão em caixa (a colisão das casas do Blender já é de caixas; uma cabana
    aberta do gerador vira bloco).

**Por isso o conjunto está desligado** (`assets/estatico/ativos.json` = `[]`). Sem o Team Create o SLIM
não é gerado, e ligar agora só traria o interior mais claro (casa clara esconde menos). Desligado, o
place sai igual à v83 (conferido no Studio).

**Para testar o SLIM:**
1. o dono liga o Team Create;
2. pôr `"vila_casa_03_xomgo"` em `ativos.json`, rodar `tools/estatico.py` e publicar;
3. no jogo publicado, comparar a casa perto e longe com as outras `vila_casa_03`.

O interior claro fica como limite conhecido até o pipeline ler a colisão do Studio (Lune novo).

**Testes:**
- `tests/test_estatico.py`: leitura da cópia, modelo do Rojo, recusa de chave e ligado igual ao
  gerado;
- os 644 testes Lune passam.

## D-156 — Lote 41: trim sheet da vila, a prova no Blender (2026-11-15, sem versão nova)

**Contexto:** o SLIM ficou preparado e desligado (D-155) porque depende do Team Create. O dono pediu
para seguir sem precisar fazer nada, e a outra técnica do texto é a trim sheet: uma folha de
materiais dividida por muitos objetos.

**Prova** (`tools/blender/vila_trim.py`, só no Blender, nada mudou no jogo):
- **O grupo Casa da `vila_casa_03`** (paredes, piso, estrutura e anexos; hoje um atlas de 1024 só
  dela) tem 2.194 triângulos e usa 6 materiais procedurais.
  - Cada peça tem o atributo `local` em metros (ao longo, altura, através), que o material usa e
    que serve de mapa para a folha.
- **A folha** (1024 px) tem 5 faixas de 192 px, com 6 px de borda repetida.
  - Cada material é assado uma vez numa faixa que repete na horizontal (25% a mais e a costura
    misturada).
  - Reboco: faixa de 3,2 m (60 px/m) com V = altura, para o pé molhado e o escorrido ficarem no
    lugar.
  - Madeira, madeira escura, bambu e barro: faixas de 0,8 m (240 px/m), com U ao longo do veio.
  - O piso é uma textura de 512 que repete a cada 4 m nos dois sentidos.
- **Conversão:** 130 peças. As faces vão para a faixa do seu material pelo `local`. Telhado e
  mobília ficam com os atlas de hoje.
- **Resultado:** `testes/trim/previa_vila_casa_03.jpg` (em cima, o GLB de hoje; embaixo, a casa com
  a folha).
  - Por fora e por dentro, a casa fica praticamente igual: as manchas, o pé molhado e os veios saem
    do mesmo material, nas mesmas coordenadas.
  - O bake leva 76 s, contra 18 min do build inteiro da casa.

**Para usar no jogo** (lotes seguintes, ainda não feitos):
- **Paleta:** o grupo Casa das 10 casas usa 26 variantes de material.
  - Madeira, madeira escura, bambu, barro e piso são iguais em todas.
  - As paredes variam por casa (3 de reboco, 3 de taipa, 2 de caiada, esteira, tábua, muro etc.).
  - Uma folha comum pede uma paleta de paredes unificada (a variedade de cor já vem da tinta por
    casa, `ArtPlan.TINTS`) e 2 ou 3 folhas, com cada nó do GLB numa folha só (uma
    `SurfaceAppearance` por peça).
- **Dividir de fato:** cada modelo enviado ganha cópias próprias das imagens. Para as casas
  dividirem a mesma textura, o `AssetLoader` troca a `SurfaceAppearance` das peças de construção
  por um clone da de um modelo "portador" (clonar é permitido; mudar o `ColorMap` por script, não).
- **Ganho esperado** (estimativa): as 30 texturas do atlas Casa das 10 casas viram as 6 a 9 das
  folhas e do piso.

## D-157 — Lote 42: conferência no Studio das portas das casas e do tanque na ponte (2026-11-15, sem versão nova)

**Pedido do dono:** "siga para outra" (deixar a trim sheet nas 10 casas para depois). Foram
conferidos dois "não testado" do PROGRESS que dependiam só do Studio.

**Portas das casas da vila** (v47, D-115: casas na escala 1,3):
- Caixa do tamanho do soldado passada em cada porta externa:
  - 0,5 m de largura, de 0,25 m a 2,05 m acima do piso;
  - de 2,5 m fora até 1,5 m dentro;
  - colisão como a do jogo (`RespectCanCollide`), com paredes, terreno, cercas e plantas.
  - Portas pelo `metricas.json` de cada casa.
  - Resultado: **57 de 57 portas livres**, nas 32 casas e nos 10 modelos.
- Andando de verdade (o soldado em campo, `MoveTo` do cliente de 3 m fora até 2 m dentro), uma
  porta de cada modelo:
  - 9 modelos entraram em 1,2 a 1,3 s;
  - na `vila_casa_10`, o biombo de alvenaria (`binh_phong`) fica a 3 m da porta e barra a linha
    reta, como numa casa vietnamita. Contornando por um lado ou pelo outro, entrou em 1,9 s.

**Tanque na ponte do objetivo D** (D-148: tabuleiro de 20 x 7 m):
- O W enviado pelo MCP não chega ao jogo com o Studio atrás de outra janela. Então o M48 andou
  pelo servidor do mesmo jeito que os bots motoristas:
  - `DriveVelocity` no plano a 3 m/s;
  - `DriveAttitude` com a inclinação lida do chão pelas 4 pontas.
- **Resultado:** partindo 6 m antes da cabeceira oeste, ele
  - desceu o barranco (−12° a −16°);
  - cruzou os 20 m do tabuleiro em altura constante (o chassi 3 studs acima das tábuas, desvio
    lateral de 0,02 m);
  - subiu o barranco leste a +12° até 8 m depois da ponte, em 11,7 s;
  - não bateu nos corrimões nem afundou.
- **Não testado:** um jogador dirigindo com o teclado (a mesma física vale para o motorista
  jogador, do lado do cliente).

**Nada mudou no jogo.**

## D-158 — Lote 43: autoteste no mapa de 700 m, o Offensive e o aviso que cobria o fim (2026-11-15, v85)

**Pedido do dono:** "continue". Foram rodados no Studio o autoteste inteiro e o modo Offensive da
v84.

**Autoteste (`VT65SelfTest`), antes:** 15 ok e 1 falha, a "vida no mapa".
- Ela pedia pelo menos 10 fumaças de cozinha nas vilas. O mapa de 700 m (D-148) dá 7 em toda
  partida: o sorteio das vilas é fixo. O mínimo de 10 era do mapa maior, e o teste falhava sem
  defeito no jogo.
- Agora o mínimo é 5 (`SelfTest.luau`).
- Três IDs de asset que o Output do Studio cita (80134531404034, 129663110534648 e
  122703273903429) não estão no repositório nem em nenhuma instância do jogo: são do próprio
  Roblox ou do Studio.

**Offensive** (`VT65DevMode`):
- a frente começou no setor 4; a captura foi de −0,76 ao neutro e o VC passou a retomar;
- com os dois lados na área, o progresso parou, como deve (`Capture.luau` congela a disputa);
- o `VT65DevEnd` mostrou o cartão "EMPATE" e o relatório ("Combate mais pesado: D (53 mortos)").

**Defeito achado:** a promoção que o pagamento do fim da partida dá saía por cima do título do
cartão de fim, por alguns segundos.
- **Correção:** `Toast.hold(on, quem)`. Cada tela segura a pilha de avisos pelo nome: "baixa" é a
  tela de baixa (D-93), e "fim" é o cartão de fim. A pilha volta quando nenhuma segura mais.
- O `FrontHud` segura no `showEnd` e solta no `closeEnd`. Todos os jeitos de fechar o cartão
  passam por ele: o clique, os 9 s, o voltar, a tecla e a partida nova. Assim, os avisos nunca ficam
  presos.

**Studio, v85:**
- **Cartão de fim:** com o `VT65DevTela` "fim" e o `VT65DevToast` "promocao", a pilha ficou
  escondida e sem aviso durante os 9 s do cartão. Aos 9,2 s o cartão saiu e a promoção apareceu.
- **Autoteste, com o soldado em campo pelos EUA e os bots:** 18 ok, 0 falhas, 0 pulados.
  - bots: 28 EUA × 29 VC;
  - vida no mapa: 7 fumaças;
  - arte no chão: 847 de 853 a até 2 m (a pior é a `Vila_ponte`, a −2,7 m, como antes);
  - medevac, morteiro, granada de bot e Offensive com relatório: ok.
- **Sem bots** (`BotFill` 0), o autoteste dá 1 falha e 4 pulados: os testes de bot precisam deles.

## D-159 — Lote 44: trim sheet nas 10 casas da vila (2026-11-15, v86)

**Pedido do dono:** "faça o trim" (a trim sheet provada na D-156, agora no jogo).

**Antes:** cada casa única trazia 3 atlas próprios de 1024: Telhado, Casa e Mobília. O atlas Casa
cobre paredes, piso, estrutura e anexos. Nas 10 casas eram 30 atlas, e o grupo Casa sozinho
somava 10.

**As folhas** (`tools/blender/vila_trim.py -- folhas`, 50 s no Blender):
- Cada material procedural do grupo Casa é assado uma vez numa faixa que repete na horizontal,
  com 6 px de borda repetida.
- **M** (madeira): madeira, madeira escura, bambu, esteira e o pote. São faixas de 0,8 m
  (240 px/m), com o veio da madeira e os nós do bambu ao longo da faixa.
  - Na prova (D-156) o veio saía atravessado: o bake usava o `local` da parede.
- **W** (paredes): barro, barro com a trama exposta (vila_casa_05), cal, tijolo rebocado e taipa.
  São faixas de 3,2 m (60 px/m), com V = altura (o pé molhado fica embaixo).
- **O** (outros): esteira e tábua de parede (faixas inteiras), mais meias faixas de 0,8 m
  (112 px/m) para terra, rede, ferro, pedra, resina e o tijolo do terreiro.
- **P**: o piso de terra batida, 512 px que repetem a cada 4 m.
- **Paleta:** as 10 casas usavam 26 variações. A cor de cada casa variava pouco (±6% no
  catálogo) e ficou uma por material. Trocas:
  - o muro e o tijolo das casas 08 e 10 vão para o tijolo rebocado (exposto 0,35);
  - a cinza vai para o ferro;
  - a esteira fina vai para a esteira.
- **Terreiro de tijolo da vila_casa_10:**
  - foi cortado em fileiras de 0,78 m (6 pares de fiadas), cada uma do pé da faixa, e a amarração
    continua na emenda;
  - mapeado como pedra, o terreiro tinha ficado cinza na primeira prévia.

**As casas** (`vila_trim.py -- vila_casa_NN`):
- O GLB novo copia Telhado, Mobília e as colisões do de hoje e troca o atlas Casa pelos nós
  `Trim_M`, `Trim_W`, `Trim_O` e `Trim_P`, sem textura (só a cor média, caso o portador falte).
- Cada GLB ficou com 6 imagens em vez de 9 e ~1,4 MB a menos (5,2 → 3,7 MB na vila_casa_01).
- **Triângulos** iguais, com três exceções:
  - vila_casa_02, 7.818 → 9.274: o grupo Casa tinha sido reduzido no atlas;
  - vila_casa_07, 7.819 → 8.473: o mesmo;
  - vila_casa_10, 7.788 → 7.806: as fileiras do terreiro.
- As prévias de antes × depois estão em `testes/trim/previa_vila_casa_NN.jpg` e as folhas em
  `testes/trim/folhas_vila.jpg`.
  - A casa fica praticamente igual. Na vila_casa_02, o serrilhado em blocos que o atlas tinha na
    parede do fundo sumiu.

**No jogo:**
- O portador `vila_trim` é um cubo por folha, com as imagens.
- O `AssetLoader.template` clona a SurfaceAppearance dele em toda peça `Trim_<letra>`. Script do
  jogo não troca o `ColorMap`, mas clona a SurfaceAppearance pronta.
- As 10 casas e o portador subiram de novo. Os IDs antigos ficam como `Models.vila_casa_NN_atlas` no
  `roblox_ids.json`.

**Studio, v86:**
- O log mostra "36 peças com a folha comum", nos 10 modelos, sem aviso; continuam 855 modelos de
  arte.
- No mapa: 32 casas e 111 peças `Trim_*`, todas com textura. São só 4 imagens de cor para todas.
- **Imagens distintas nas casas:** 91 → 75. As de cor, normal e rugosidade foram de 90 para 72; as
  do grupo Casa, de 30 para 12.
  - Em pixels, pelo tamanho das imagens enviadas, o grupo Casa foi de 23,6 para 7,7 milhões.
- **A/B na mesma vista, em sessão nova de cada versão:** a câmera a 24 m do centro da vila e 11 m
  acima, qualidade 10, campo de 70°, 30 s.

  | Medida | v85 | v86 |
  |---|---|---|
  | Memória de textura | 131,8 MB (ainda subindo) | 122,5 MB (parada) |
  | Chamadas de desenho | 268 | 229 |

- **Fotos:** a vila_casa_10 de frente e a vila_casa_02 de perto saem certas (cal com manchas,
  tijolo do terreiro, mureta com limo, esteira, bambu com nós, rede).
  - O tanque da vila_casa_10 tinha o tijolo à mostra por acaso do ruído; agora sai rebocado.
- **Autoteste:** 18 ok, 0 falhas, 0 pulados (arte no chão 846 de 852).

**Não testado:**
- fps num celular;
- a memória no jogo publicado (no Studio a textura acumula o que já foi visto, então a medida vale
  para a mesma sequência de vistas).

**Limite:** o `assets/estatico/vila_casa_03_xomgo.txt` (D-155) foi copiado da casa antiga. Antes de
ligar o SLIM, copie de novo.

## D-160 — Lote 45: água, arrozal, veículo comprado e desvirar conferidos no Studio (2026-11-15, v87)

**Pedido do dono:** "Siga para outra". Foram conferidos no Studio itens da lista "O que NÃO foi
verificado" que só tinham rodado no Lune: D-93 (água), D-100 (desvirar), D-103 (veículo ao nascer)
e D-104 (peças móveis).
- Sem teclado no Studio em segundo plano, nada aqui mede a velocidade andando. O soldado foi posto
  no lugar e os estados foram lidos pelo gancho `VT65DevMov = "info"`.

**Água no mapa de 700 m:** na grade de 24 studs (6,7 m), 124 pontos d'água, todos no rio do sul,
com leito de até 0,60 m.
- Não há água funda dentro da área: nadar só acontece fora dela.
- O gancho achou ainda uma poça de 0,60 m perto do QG dos EUA.

**D-93, água:**

| Leito | Modo | Estado do Humanoid | Altura do corpo | Postura |
|---|---|---|---|---|
| 0,38 m | vadear | Running em 20 de 20 leituras | parada em 5 s | deitado volta a agachado em 0,5 s |
| 0,51 m (riacho de fora) | vadear | Running | parada | — |
| 0,60 m | vadear | Running em 20 de 20 leituras | 0 m de oscilação em 5 s | agachar fica; deitado volta a agachado em 0,5 s |

- Nenhuma troca entre andar e nadar, nem o corpo boiando.
- O limite de postura é o da D-93: deitado até 0,3 m, agachado até 0,8 m.

**D-93, arrozal:** 9 pontos espalhados num tabuleiro de 32 × 36 m leram sempre "paddy", fator 0,62,
sem alternar entre lâmina e capim.

**D-103, veículo comprado em campo** (`VT65DevCompra`, sem cobrar):

| Onde | Pedido | Resultado |
|---|---|---|
| arrozal | M151 | a 8,5 m, no capim seco fora do tabuleiro, nivelado |
| dentro de uma casa de Xóm Gò | M35 | a 7 m, fora da casa, nivelado |
| mata da Serraria (10 plantas a 12 m) | M151 | a 4 m, nenhum tronco na caixa |
| ladeira de 28° perto de Xóm Gò | M35 | a 4 m, num trecho com 0,40 m de desnível entre os cantos; parado e a 0,1° |
| dentro do rio | M151 | recusou ("sem lugar") |

- O M35 da casa encosta 0,18 m na beirada do piso da casa, que tem 0,2 m de altura. A conferência
  da caixa começa 0,35 m acima do chão de propósito, para aceitar meio-fio e soleira.
- Na casa, o pedido não cai no "teto": os telhados não têm colisão. O veículo sai fora da casa
  mesmo assim.
- O abandonado (sem ninguém a 30 m) sumiu ~90 s depois que o soldado saiu de perto: o M35 e o
  M151.

**D-104, peças móveis:** `VT65DevVeh = "todos"` e `"pecas"`.
- Os 7 veículos têm todas as juntas: rodas, portas, escotilhas, torre, cano e rotores.
- Nenhuma peça falta e nenhum usa o substituto.

**D-100, desvirar:** `VT65DevVeh = "tombar"` deitou o M35.
- O UpVector foi a −0,17.
- O pedido de desvirar pelo painel (remote `Vehicle_Board`, a 4 m) o pôs de pé (1,00) com o aviso
  "Veículo desvirado".
- Pedido de novo, com ele de pé: "O veículo não está tombado nem preso".

**Corrigido (só o gancho de teste):** o `VT65DevMov = "agua"` procurava água num raio de 200 m sem
olhar o mapa.
- Do QG dos EUA, ele achou um riacho na margem de fora e pôs o soldado lá, onde o jogo mata quem sai
  do mapa.
- Agora só procura dentro da área, com 10 m de folga. Conferido: do QG achou a poça de 0,60 m de
  dentro; no rio, um ponto de 0,60 m.

**Não testado:**
- a velocidade vadeando;
- a passada assistida no dique;
- a inclinação da câmera;
- o tanque subindo o dique.

Tudo isso pede o teclado no jogo.

## D-161 — Lote 46: carta do veículo, partida longa com bots e as tripulações presas (2026-11-15, v88)

**Pedido do dono:** "continue".

**D-103, a carta** (pelos remotes, como o botão da tela):
- O soldado morto pediu um M151 em CI (`Vehicle_Order`), e o pedido ficou "armado".
- Ao nascer no QG, veio "M151 MUTT ao seu lado":
  - a 4 m, virado para oeste (o lado dos objetivos);
  - os créditos foram de 1.300 para 1.150 (o preço é 150);
  - a espera entre dois pedidos foi a 120 s.
- Pedir um M35 com o M151 ainda em campo foi recusado: "Você já tem um veículo comprado em campo".

**Partida longa com bots** (Warfare, 59 bots, o soldado parado no QG; o `VT65DevBots = "squad0"`
tirou os bots do squad do jogador):
- Servidor: 0 erros em ~25 min de partidas, física a 60 por segundo, heartbeat de 1 a 1,6 ms.
- Um aviso de imagem que não carregou (o rosto nº 5 do VC) foi passageiro: no cliente, os 24 rostos
  estão carregados, e 3 bots usam aquele.
- **O VC vence o Warfare só de bots em 6min26s–6min27s**, nas duas partidas medidas até o fim. Linha
  do tempo:
  - toma C (Xóm Gò) no 1º minuto;
  - toma D (Ponte e Cais) entre o 3º e o 4º;
  - toma E (Engenho) no 6º.
  - Baixas parecidas (48 × 47 e 70 × 60).
- **Por quê, contado no Studio:**
  - em 1,1–1,3 min, 27–28 dos 29 bots do VC estão em Xóm Gò;
  - dos EUA, 11–19 ainda estão no QG e 13–14 sentados nos veículos;
  - depois, 8 dos EUA atacam Xóm Gò de 70–90 m enquanto o VC toma Ponte e Cais quase sem defensor.
  - O VC está 25 m mais perto do centro e é 12% mais rápido (D-93). Só os EUA têm blindados (D-90): a
    regra monta até 5 tripulações com 30 bots, mais os passageiros dos LVTP-5.
  - Mexer no equilíbrio é decisão de jogo, e fica para o dono.

**Defeito achado e corrigido: tripulação de bot presa** (`BotVehicles`):
1. **Na contagem do começo** (D-122), o `driveTo` responde "chegou", porque a viatura fica parada de
   propósito. Com isso:
   - a marcha virava "hold" (segurando a posição) na própria base e ficava assim;
   - o transporte com tropa podia largar os passageiros ali.
   - Agora, na contagem, o estado da tripulação não anda.
2. **Partida nova:** a tripulação guardava setor, destino e rota da anterior. Agora esquece, e quem
   segurava, largava ou voltava recomeça (`BotBrain.crewStateOnNewMatch`).
3. **Vigia** (D-113):
   - antes, "hold" nunca contava, e "andar" era qualquer deslocamento de 4 m. O desencalhar recua 6 m,
     então um blindado preso indo e voltando nunca era desfeito;
   - agora "hold" a mais de 40 m do destino conta (`BotBrain.crewShouldMove`);
   - indo para o destino, progresso é chegar 4 m mais perto: 60 s em "hold" e 120 s em "go" (a rota
     pode contornar o rio).
- **No Studio:**
  - antes da correção, o Ontos ficou 4 min em "hold" a 206 m, desencalhando em laço;
  - depois, a tripulação sai em "go" na contagem e não vira "hold";
  - o M48 (preso a 195–197 m) e o Ontos (207–208 m) foram desfeitos em 120 s, e os bots seguiram a pé;
  - na troca de partida, nenhuma tripulação ficou em "hold" longe do destino.
- **Onde eles encalham:** no pátio do depósito dos EUA, a ~35 m do QG, encostados no contêiner
  (`us_conex`), nos galões (`us_jerrycans`), no gerador e um no outro.
  - Os galões não estavam na grade de rota e entraram (`BotWorld.NAV_BLOCK`). O contêiner e o
    gerador já estavam.
  - A saída do pátio pede um lote próprio.

**Testes:** bots.luau ganhou o teste da D-161; Lune 235 ok.

## D-162 — Lote 47: equilíbrio dos bots no Warfare (2026-11-15, v89)

**Pedido do dono:** "Equilibre os bots" (achado da D-161: o VC vencia o Warfare só de bots em ~6,5
min, sempre).

**Como foi medido:** partida de Warfare com 59 bots no Studio. O soldado fica parado no QG, e o
`VT65DevBots = "squad0"` tira os bots do squad dele. Anota-se a linha do tempo do relatório
pós-ação, os reforços e quem está a 100 m de Xóm Gò.

**O que segurava os EUA, achado e corrigido nesta ordem:**
1. **Pátio do depósito:**
   - na escala 1,5× das barracas (v41), o `bases_dados.py` afastou a barraca de comando para leste;
   - o gerador, os galões e os dois contêineres "do QG" ficaram sozinhos no descampado por onde os
     blindados vão das baias ao portão;
   - o M48 e o Ontos encalhavam ali toda partida.
   - Eles foram para o canto noroeste, entre a baia 1 e a cerca (`tools/blender/bases_layout.py`).
     A barraca de comando e o refeitório ficaram fixos onde já estavam no jogo; sem isso, o
     `afastar` os puxava de volta para a passagem. Só os 4 objetos mudaram no `Data/Bases`.
2. **Portão:** com a passagem livre, o M48 e o LVTP-5 chegavam juntos ao vão de 6 m da cancela,
   com bots a pé no meio, e travavam. Agora um blindado do lado sai da baia por vez, com 10 s entre
   um e outro (`BotBrain.VEHICLE.departGapS`, `departReady`).
3. **Squad caminhando:**
   - o líder caminha (1,4 m/s) se o último está mais de 25 m atrás do lugar dele;
   - um bot preso na concertina contava como atrasado para sempre, e o squad inteiro ia andando
     até Xóm Gò (medianas de 1,2–1,5 m/s nos EUA contra 4,1 no VC);
   - agora só conta o atrasado que está andando (`BotBrain.SQUAD.lagMovingMps`).
   - Os líderes passaram a trotar a 3,3–3,9 m/s. O rótulo de depuração mostra o atraso que o
     líder vê.
4. **Defesa:**
   - eram 25% dos squads guardando o setor ameaçado e 50% com o inimigo dentro, e o lado que
     tomava o centro passava por cima;
   - agora são 40% e 70% (`BotBrain.TASK`).
5. **Velocidade dos bots do VC:**
   - a D-93 diz que o bônus de 12% do VC é do jogador e que os bots ficam na velocidade-base, mas
     o `BotLocomotion` aplicava o bônus também aos bots;
   - com ele, o VC de bots chegava ao centro ~20 s antes (288 m a 4,1 m/s contra uns 330 m, pelo
     portão, a 3,65 m/s) e tomava Xóm Gò sempre;
   - agora o bot não usa o bônus. O jogador do VC continua 12% mais rápido.

**Partidas medidas (Warfare só de bots; o VC venceu todas as que terminaram):**

| Configuração | Duração | Xóm Gò | Ponte e Cais | Baixas EUA × VC |
|---|---|---|---|---|
| v88 (antes) | 6:26 e 6:27 | 1º min | 3º–4º min | 48×47 e 70×60 |
| + blindados livres (1 e 2) | 7:00 | 1º min | 3º–4º min | 50×49 |
| + defesa 40/70% | 13:03 | 1º min | 9º–10º min | 146×130 |
| + squad (3) e 1 blindado a cada 10 bots | ~7 | 2º min | 4º min | 78×58 |
| + squad (3), blindados como antes | 9:08 | 2º min | 4º–5º min | 108×90 |
| + bots sem o bônus (5): a v89 | 19:56, reforços dos EUA acabaram | VC no 2º min, EUA no ~7º, VC no ~8º | dos EUA a partida toda | 257×277 |

- A tripulação "a cada 10 bots" foi desfeita: com os blindados saindo do pátio, eles são o poder
  de fogo dos EUA.
- Uma partida por configuração tem muita variação (as linhas de ~7 e 9 min diferem só nisso). A
  última mudança foi a única que mudou o jeito da partida:
  - Xóm Gò trocou de mãos três vezes;
  - os EUA seguraram Ponte e Cais e Engenho a partida inteira;
  - os reforços andaram juntos (241×245 aos 6 min, 164×172 aos 10,6 min);
  - o VC perdeu mais gente (277 × 257).
  - Terminou 2 × 3 em setores, e o VC venceu pelo sangramento de quem tem menos setores (3 por
    minuto por setor de diferença).

**Não testado:** com jogadores dos dois lados; servidor cheio no Roblox.

## D-163 — Lote 48: Offensive só de bots e a tentativa de marcha forçada (2026-11-15, sem versão nova)

**Pedido do dono:** "Siga para outra".

**Bots presos na cerca da base dos EUA** (o achado da D-162):
- Em ~2 min de partida, com amostras a cada 12–15 s, apareceu no máximo 1 bot parado por vez,
  encostado na concertina do canto noroeste.
- Pouco impacto; ficou como está.

**Offensive só de bots (v89):**
- Os EUA tomaram Ponte e Cais (D) aos ~5,6 min.
- Diante de Xóm Gò (C), ficaram 7 min sem avançar, até a medida acabar aos 12,4 min:
  - aos 10,7 min, 20 do VC estavam a menos de 100 m do ponto (12 dentro do raio de 35 m) e 1 dos
    EUA;
  - os EUA estavam a 100–250 m, 18 deles "em combate".
- **Por quê:**
  - no combate do Front 44 (v41), o bot que vê um alvo entra em duelo: longe, agacha e atira
    parado, a qualquer distância;
  - o lance de assalto da D-107 só existe no combate antigo;
  - de 100 a 250 m quase ninguém acerta, então o ataque para ali.

**Tentativa, desfeita:** o atacante com o alvo longe e o ponto ainda longe seguiria a marcha do
squad, atirando andando (`pressPastTarget`).

| Passa por alvo além de | Ponte e Cais (D) |
|---|---|
| sem a mudança (v89) | tomada aos ~5,6 min |
| 80 m | não tomada aos 10 min; 20 dos EUA mortos ou voltando do QG |
| 150 m | não tomada aos 8 min |

- Andando para dentro do fogo, contra defensores agachados, os atacantes morrem mais do que
  avançam. A mudança foi desfeita, e o jogo segue igual à v89.
- Uma partida por variante tem muita variação. Mas as duas variantes pioraram no mesmo ponto
  (o primeiro setor), que sem a mudança cai.

**Fica para o dono decidir:** no Offensive só de bots, o VC deve vencer pelo relógio, defendendo
Xóm Gò. É o desenho do modo (o defensor do morro e da vila tem vantagem), e com jogadores quem
empurra é o jogador. Se o dono quiser o ataque de bots mais forte, as alavancas são:
- o tempo do Offensive (20 + 15 min por setor, `Offensive.C`);
- os bots de ataque com granada de fumaça;
- mais bots dos EUA no Offensive.

## D-164 — Lote 49a: os 4 uniformes da D-131 em Robux (2026-11-15, v90)

**Pedido do dono:** "Robux ... quero isso vc tem permissao total para colocar".

- A loja em Robux já estava quase toda criada: passes de uniforme, unidade, apoiador, kits,
  campanha, recruta e as 8 vantagens; produtos de apoio, renascer onde caiu, pular nível, XP e
  créditos dobrados, pacotes de créditos, os 3 veículos ao nascer e as 17 skins de arma. Eu tinha
  dito ao dono que os botões de Robux estavam escondidos; estava errado, e o `TODO_USUARIO` foi
  corrigido.
- Faltavam os 4 uniformes da D-131 (tadpole, lagarto, áo bà ba marrom e tigrado capturado). Foram
  criados como Game Pass a R$ 79, o preço dos outros uniformes (`tools/roblox_cloud.py
  create-skins`), e os IDs estão em `Skins.IDS`.
- Continuam com o dono: servidores privados (preço), a assinatura e o Managed Pricing.

## D-165 — Lote 49b: telhados na trim sheet, medidos e desfeitos (2026-11-15, sem mudança no jogo)

**Pedido do dono:** "Telhados na trim sheet (menos memória de textura): faço ou não? faça".

**O que foi feito:**
- Uma 5ª folha, R (cor e normal de 1024 e rugosidade de 512), com 3 faixas: palha, folha de
  palmeira e telha. Cada faixa foi assada de uma água de telhado de verdade (`vila_comum.placa`,
  com o relevo fino).
- O telhado das casas foi refeito baixo (grade de 0,6 m; só a franja do beiral ficou na malha), com
  as UVs da placa (u ao longo do beiral, v subindo a água) e a cumeeira no topo da faixa.
- As 10 casas foram convertidas e subidas. Nas prévias do Blender, telha, palha e folha ficaram
  fiéis. Triângulos por casa: −4% a −24% (a 05 foi de 6.853 para 5.229).

**Medida no Studio:**
- **Como:** sem bots (`BotFill` 0 no Edit, antes do Play), Studio novo a cada medida, qualidade 10,
  FOV 70, a vista da vila da D-159, memória `GraphicsTexture` depois de 60 s.
- Com bots o número muda de uma sessão para outra (cada bot traz as texturas do avatar): 167,5 MB
  na v89 e 192,3 MB com os telhados. Por isso a medida que vale é a sem bots:

| Versão | Textura | Imagens distintas | Chamadas de desenho |
|---|---|---|---|
| v89 (telhado no atlas de cada casa) | 129,6 MB | 365 | 261 |
| telhado na folha R | 167,7 e 170,2 MB | 335 | 262 |
| telhado na folha R, sem aplicar a R | 134,9 MB | 335 | — |

- **A faixa R sozinha custa ~35 MB nessa vista.** Os 10 atlas de telhado que saíram quase não
  pesavam: sem eles e sem a R, a memória ficou como a da v89. Com 30 imagens a menos, a memória
  subiu.
- **Por que (suposição, não medida):** o Roblox parece carregar cada textura na resolução que a tela
  pede. Cada telhado ocupava um pedaço do atlas da casa e pedia pouca resolução. A faixa R se
  repete muito na água do telhado e pede a folha inteira, ainda mais com a casa de perto.

**Resultado:** desfeito. As casas voltaram aos assets da v89, e os assets subidos ficaram anotados
como `*_telhado` em `assets/roblox_ids.json`. Antes de passar outro grupo para a trim sheet, medir
como acima: só vale trocar a textura que o Roblox carrega grande.

## D-166 — Lote 50: bots ofensivos no Offensive (2026-11-15, v90)

**Pedido do dono** (sobre a pergunta da D-163, "deixo o VC segurar Xóm Gò ou dou mais tempo aos
EUA?"): "quero os bots bem ofensivos".

**O que ficou no jogo:**
- **Lance de assalto também no duelo.** O lance da D-107 (`BotBrain.PUSH`, `shouldRush`) só existia
  no combate antigo; no duelo do Front 44, o atacante que via o alvo agachava e trocava tiro de longe
  até o fim. Agora, no duelo:
  - a equipe da vez corre até o próximo abrigo a caminho do ponto com o alvo a mais de 80 m, ou
    depois de 6 s parada;
  - qualquer um do ataque corre depois de 14 s no mesmo lugar;
  - ninguém corre com o alvo a menos de 35 m, recarregando, com a vida abaixo de 35% ou dentro do
    ponto;
  - o lance começado vai até o fim mesmo se o alvo some.
  - `VT65DevBots = "distancias"` conta os lances.
- **No Offensive, o VC defende com 2/3.** O lado que defende completa o time só até 20 de 30
  (`BotBrain.OFFENSIVE.defenderShare`, `modeFill`). Os humanos contam igual, e o Warfare não muda.
  Na Operação Starlite os fuzileiros eram muito mais numerosos que o batalhão do VC.

**Medidas** (Studio; Offensive só de bots, com um soldado dos EUA em campo e o squad dele sem bots;
amostra a cada 30 s; o objetivo é Ponte e Cais, D):

| Variante | Bots EUA × VC | Dentro de D (EUA × VC) | D tomada? |
|---|---|---|---|
| v89 (D-163, 1ª partida) | 30 × 30 | — | aos ~5,6 min |
| v89, 2ª partida | 29 × 30 | 0 × 8–22 até 10,5 min | não até 10,5 min |
| lance no duelo + fumaça | 29 × 30 | 0–5 × 4–19 | não até 10,7 min |
| lance no duelo + VC com 2/3 (fica) | 29 × 20 | 3–6 × 6–11 dos 9,5 aos 11,5 min | não até 11,5 min |

- A tomada aos 5,6 min da D-163 foi a exceção: em 4 das 5 partidas medidas (contando as 2 da
  marcha forçada, D-163), D não caiu até 8–11 min.
- **Por que o ataque perde:** em 90 s da variante que ficou, morreram 29 dos EUA e 11 do VC.
  - Os EUA caíam a 87–160 m de D, com um VC a 5–27 m.
  - O VC sai do ponto atrás do tiro ouvido e do último contato e luta de perto. Ali a rajada de 3 a 7
    tiros das armas automáticas dele vence o M14 semiautomático.
  - O túnel avançado do VC fica perto da frente; o bot dos EUA renasce no QG, a ~250 m, porque o
    companheiro de squad está sempre em combate.
- **Fumaça, tentada e desfeita:** o squad que ataca jogava uma lata (1 por vida, 1 por squad a cada
  40 s) a 22 m na direção do contato. Foram 33 latas e 5 lances em 8,7 min, e nenhum americano entrou
  em D: com o alvo tapado, metade do squad anda até o contato e sai da nuvem perto do VC.
- Com a variante que ficou, os EUA entraram em D, o que a v89 não fez na mesma janela. Mas uma
  partida por variante tem muita variação, e nenhuma tomou D.

**Próximas alavancas** (não feitas, mudam o jogo do jogador):
- o tempo do Offensive (`Offensive.C`);
- o fogo de perto do bot dos EUA (rajada da M14 ou mais M60 no squad);
- o defensor do Offensive mais preso ao ponto (menos caça ao contato).

## D-167 — Lote 51: o SLIM ligado na casa de Xóm Gò (2026-11-15, v91)

**Pedido do dono:** "quero fazer o slim".

- **Team Create ligado:** conferido pela API de desenvolvimento do Roblox
  (`develop.roblox.com/v1/universes/10775697296/teamcreate` → `isEnabled: true`), lida no navegador
  do app com a conta do dono. A versão 90 do place, que apareceu por fora do pipeline (D-166), veio
  daí.
- **Cópia nova do conjunto:** a de D-155 era da v83, antes da trim sheet (D-159). O conjunto foi
  copiado de novo da v90 (`tools/estatico_copiar.luau` no servidor do Studio).
  - 6 modelos e 60 peças, sem nenhuma linha `X`.
  - A casa tem 55 peças: Mobilia, Telhado, `Trim_M/W/P` (com a SurfaceAppearance do portador já
    aplicada) e 50 caixas de colisão.
  - Conferido pela soma FNV-1a (`a34b3f7d`, 8.653 bytes) calculada no Studio e no arquivo. A soma do
    Studio precisa da multiplicação dividida (`h*403 + ((h*256) % 65536) * 65536`): `h * 16777619`
    passa de 2^53 e perde precisão no Luau.
- **Ligado:** `assets/estatico/ativos.json` = `["vila_casa_03_xomgo"]`; `tools/estatico.py` gerou
  `src/Workspace/Estatico` (6 modelos) e `Modules/StaticArt`.
- **Studio:**
  - o arquivo tem os 6 modelos com `LevelOfDetail = SLIM` e `Atomic`;
  - o servidor pulou as 6 cópias do plano;
  - a vila saiu igual: 855 modelos, 390 construções, 27 animais, 240 peças de abrigo dos bots;
  - 6 de 8 raios param nas paredes da casa fixa (os outros passam pelas portas e pela varanda);
  - de fora, a casa sai com o telhado, as paredes da trim sheet, o pote e as cercas;
  - autoteste: 18 ok, 0 falhas; nenhum erro no Output.
- **Limite conhecido (D-155):** o interior da casa fixa fica mais claro que o das outras, porque a
  peça feita fora do Studio colide em caixa.
- **Falta (só no jogo publicado):** o Roblox gera o SLIM na nuvem depois da publicação. Comparar a
  casa da entrada de Xóm Gò de perto e de longe com as outras `vila_casa_03`. Se o SLIM funcionar,
  passar mais conjuntos para arte fixa (mais casas da vila).
- **Tentativa de conferir (2026-11-15, depois da v91):**
  - Pela documentação, não há API do estado do SLIM: só a cor de depuração (F9 →
    DebugVisualizations → SlimTintMode, ou o menu de visualização do Studio). A geração só acontece
    no place da nuvem.
  - Com o place da nuvem aberto no Studio (sem editar), Play, e o soldado levado a 1.434 studs da
    casa (o raio do streaming é 1.280):
    - em 6 min o cliente passou de 733 para 687 modelos de arte e parou;
    - a casa fixa não saiu do streaming (115 peças no cliente);
    - `GraphicsSlimModels` ficou em 0 MB.
  - Com memória sobrando, o `Opportunistic` quase não libera, então o teste por distância não
    mostrou o SLIM no Studio.
  - A cor de depuração ficou para depois: o dono estava com outro jogo aberto, e o Studio foi
    fechado para não travar a placa de vídeo.

## D-168 — Lote 52: SLIM para as construções de peças e a escolha dos próximos alvos (2026-11-15, sem versão nova)

**Pedido do dono:** "continue fazendo o slim o baking e o trim sheet".

**Contexto:** o dono estava jogando outro jogo (placa de vídeo de 2 GB). Sem Studio e sem Blender
pesado, o lote ficou no código e na análise.

**SLIM para as construções de peças** (o relatório da D-154 diz que é onde o SLIM ajuda mais: as
19 construções do `MapLife`, com até 51 peças com sombra cada):
- `tools/estatico_copiar.luau`:
  - `Part`, `WedgePart` e `CornerWedgePart` viram linhas `B`;
  - cada linha leva o CFrame inteiro (o alpendre é inclinado a −8°), o material do Roblox, a cor e
    o atributo `Material` da bala;
  - recusa (linha `X`) superfície que não seja lisa, transparência parcial, filho, atributo além de
    `Material` e nome com espaço.
- `tools/estatico.py` lê a linha `B` e gera a peça do Rojo. Conferido: um modelo com a cunha a −8° e
  uma tora em cilindro, construído no Rojo 7.4 e lido de volta no Lune, sai com a mesma matriz (as
  linhas passam como linhas), o cilindro, o material, a cor, as superfícies lisas e o atributo.
- `MapLife.villagePart` põe o pivô no centro da base, com o giro do plano.
- `AssetLoader.placeItem` procura a cópia fixa (`Vila_<tipo>`) antes de montar a construção.
- **Feito depois, com o Studio (v92):**
  - o copiador ganhou o modo `PREFIXO`: com `"Vila_"`, copia as 19 construções de peças do mapa
    (serraria, toras, tábuas, moenda, caldeira, ponte, cais, 2 barcos, 4 hortas, o pagode, a casa
    comunal e 4 bancas): 239 peças, 12 inclinadas, sem marca de problema depois de uma correção;
  - a correção: a `WedgePart` nasce com `BottomSurface = Inlet` (o padrão do Roblox), e só as
    pontas dos barcos ficavam assim; agora o `MapLife` põe lisa, igual à cópia;
  - o texto (`assets/estatico/vila_construcoes.txt`, 258 linhas, 45.462 bytes) foi conferido pela
    soma FNV-1a `f651c81d`, no Studio e no arquivo;
  - ligado em `ativos.json`: 25 modelos fixos e 299 peças no arquivo, todos com SLIM;
  - Studio: 25 cópias do plano puladas, as 19 `Vila_` do mapa são as fixas, vila igual (855
    modelos, 390 construções, 27 animais, 240 abrigos dos bots), arte no chão igual (846 de 852,
    pior a ponte a −2,7 m, como antes) e autoteste 18 ok, 0 falhas.
  - Peça comum colide pela forma de verdade (sem o problema de colisão da malha da D-155), então
    estas construções não ficam com o interior mais claro.

**Próximo alvo da trim sheet** (`tools/textura_custo.py`): custo teórico das texturas dos modelos do
jogo, com o teto de 1024 do Roblox, 4 bytes por pixel e os mipmaps, sem a compressão:

| Grupo | Modelos | Texturas | MB teóricos |
|---|---|---|---|
| outros (bichos, plantas, morteiro, objetos) | 50 | 142 | 647 |
| base dos EUA | 21 | 93 | 282 |
| casas da vila | 10 | 60 | 240 |
| veículos | 11 | 51 | 220 |
| árvores da mata (Poly Haven) | 4 | 24 | 128 |
| base do VC | 9 | 30 | 75 |

- **Base dos EUA:** é onde o jogador nasce e fica perto de tudo, então as texturas carregam
  grandes. O posto de comando tem 9 texturas; cada barraca, o refeitório e o pátio de veículos, 6.
  Lona, sacos de areia, madeira e chapa se repetem: bom alvo para uma folha comum.
- **Árvores da mata:** 6 texturas por espécie (casca e folha em atlas separados), perto da câmera
  em todo o mapa. Assar casca e folha num atlas só (baking) baixaria para 3.
- **A medida que decide** (regra da D-165): no Studio, sem bots, na vista da base, a memória de
  textura com e sem as SurfaceAppearance da base. Só vale converter se a diferença for grande.

**Baking:** já é o caminho do projeto para o que sai do Blender (casas, bases, veículos, faca). O
próximo uso concreto é o atlas único das árvores da mata, depois da medida.

**A medida, com o Studio (depois da v92):**
- **Como:** uma cópia da v92 com um corte injetado no `AssetLoader` (só na cópia, pelo Edit). As
  peças das chaves escolhidas trocam a SurfaceAppearance pela folha `Trim_P` (512), como se o grupo
  estivesse todo numa folha só. Studio novo por medida, sem bots, qualidade 10, FOV 70, câmera fixa
  olhando o QG dos EUA (onde o jogador nasce), memória `GraphicsTexture` depois de 60 s.
- **Apagar a SurfaceAppearance não serve de medida:** sem ela, a peça usa a textura do material do
  Roblox, e a memória foi de 132,7 para 273,6 MB.

| Vista do QG dos EUA | Textura | Chamadas de desenho |
|---|---|---|
| v92 normal | 132,7 MB | 358 |
| a base dos EUA (78 modelos, 41 SA) numa folha só | 126,6 MB | 358 |
| todos os modelos do mapa (282 SA) numa folha só | 109,9 MB | 358 |
| sem os 4 `MaterialVariant` do chão | 132,8 MB | 358 |

- **Toda a textura de modelo custa ~23 MB nessa vista, e a base dos EUA ~6 MB.** O resto (~110 MB)
  é o chão do Roblox, o céu, a interface e os personagens. Tirar as 4 variantes fotográficas não
  muda nada: o chão padrão ocupa o mesmo.
- **Conferência do SLIM (2026-11-15, depois da v92):**
  - No Studio desta versão, o menu de visualização (engrenagem do viewport, 32 modos) não tem modo
    do SLIM. O que existe é o `SlimTintMode` do Console do Desenvolvedor (F9 → DebugVisualizations),
    com `None`, `LevelOfDetail` e `DataModelState`; o `TranscoderStatus` da documentação não aparece.
  - Place da nuvem, Play no Studio, `DataModelState` ligado (a legenda aparece): nenhum modelo
    ficou verde ou amarelo, nem de perto nem a ~300 m da vila, nem depois de sair e entrar de novo
    (1 min depois). `GraphicsSlimModels` ficou em 0 MB. **No Studio, nada foi desenhado pelo SLIM.**
  - Jogo publicado (conta do dono, servidor vazio): o modo liga, mas o menu mostra cenas de perto
    (o Roblox desenha peça por peça), e na partida o mouse fica preso e a mata tapa a vila. Não deu
    para ver a vila de longe. **Não confirmado.**
  - **Achado à parte, no jogo publicado:** o console mostrou 109 a 113 erros "Failed to load …
    SurfaceAppearance. PBR textures may not be visible in game" (granary, casas, Trim_O, cozinha,
    poço, toca, trincheira) e o mesmo para os `MaterialVariant` do chão (`VT65_Grass`,
    `VT65_Ground`). No Studio esses erros não aparecem. **Não investigado:** pode ser a qualidade
    gráfica automática baixa na placa de 2 GB (o Roblox desliga o PBR em qualidade baixa) ou falha
    de carga de verdade.
- **Conclusão (trim e baking):** trim sheet e baking de modelos não têm mais o que ganhar em memória
  de textura. A trim sheet da base economizaria no máximo ~6 MB, pouco para refazer as UVs e perder
  detalhe (o mesmo que a D-165 mostrou no telhado). Não feita. O que ainda pesa no desenho (chamadas
  e triângulos de longe) é o que o SLIM ataca.

## D-169 — Lote 53: as casas da vila no SLIM, por molde (2026-11-15, v93)

**Pedido do dono:** "Passe mesmo assim" (mais casas no SLIM, sem esperar a conferência do D-168).

- **Por molde:** as casas únicas da vila são clones do mesmo modelo, sem tinta (só o pivô, o giro em
  Y e a escala mudam; `ArtPlan` não põe `tint` nelas). O copiador ganhou o modo `MOLDES`: a primeira
  casa de cada chave sai inteira (o molde) e as outras só como `I <chave> <x> <y> <z> <giro>
  <escala>`. O `tools/estatico.py` leva o molde ao pivô de cada instância.
- **Sem transcrição:** o texto (938 linhas, 58.648 bytes) voltou do Studio em 4 pedaços marcados
  `VT65COPIA casas i/4`, e o `tools/copia_da_conversa.py` o tirou do registro da conversa e gravou
  `assets/estatico/vila_casas.txt`. A soma FNV-1a bateu (`db1c2595`).
- **Casas:** 28 (9 moldes e 19 instâncias). A `vila_casa_09` fica com o jogo: o `MapLife` mexe nela
  (escada). Com a casa de Xóm Gò da D-167, são 29 das 32 casas únicas.
- **Conferido:**
  - o telhado e o piso de cada uma das 28 casas geradas contra a casa do jogo: maior diferença
    0,0014 stud;
  - Studio: 53 modelos fixos (1.722 peças), 53 cópias do plano puladas, nenhuma peça da trim sheet
    sem textura, vila igual (855 modelos, 390 construções, 27 animais, 42 lamparinas, 240 abrigos
    dos bots, arte no chão 846 de 852), autoteste 18 ok, 0 falhas.
- **Limites:**
  - o interior das casas fixas fica mais claro que o de antes (a peça de malha feita fora do Studio
    colide em caixa, D-155). Casa clara esconde menos quem está dentro;
  - o SLIM em si segue sem confirmação (D-168).

## D-170 — Lote 54: tiro sozinho no celular, mira da SKS e M60 nova (2026-11-15)

**Pedidos do dono:** "coloque q quem mira no celular atira sozinho para ele quando acha uma
jogador"; "a mira da m60 está horrível e precisa melhorar ainda mais da sks".

- **Tiro sozinho no celular:** o `touchAutoFire` (toque v39, `ToqueAuto`: mirando, atira quando a
  linha do olho passa num inimigo à vista; nada através de parede, mata ou fumaça) agora vem ligado. Quem já tinha salvo a configuração com ele desligado (o
  padrão antigo) também passa a ter ligado uma vez (`touchRev` 2); depois disso, quem desligar no
  painel continua desligado.
- **SKS:** olho a 14 cm da alça tangente (era 26 cm). Visto do olho no Studio: a 26 cm o entalhe
  e a massa ficavam minúsculos no fim da tampa da caixa; a 14 cm o entalhe em U enquadra a massa no
  centro.
- **M60 refeita no Blender** (`tools/blender/m60.py`, como a SKS e o M16 da D-146):
  - a do gerador tinha a alça em três dentes grossos, e o do meio ficava fora da linha da massa e
    tapava o alvo;
  - a nova tem a alça de folha atrás da tampa de alimentação, com um anel de 11 mm numa haste fina
    no alto, e a massa em lâmina de 5 mm numa base alta perto do quebra-chamas. Linha de visada a
    7 cm do cano, raio de visada 0,70 m (PLACEHOLDER, de fotos);
  - a folha real envolve o furo numa placa. Testei assim (furo de 7 mm, depois 11 mm) e, a 12 cm
    do olho, a placa preta tapava o meio da tela. Ficou o anel numa haste, que deixa ver em volta;
  - tem bipé dobrado, alça de transporte à esquerda e um pedaço da fita de munição saindo da
    bandeja. São 6.024 triângulos e 1,2 MB;
  - mão direita a 10 cm abaixo do cano e olho a 12 cm do anel: são os mínimos do teste das armas
    para metralhadora (lote 7);
  - a do gerador fica no `roblox_ids.json` como `Models.m60_gerador` (78397702456512);
  - antes do anel subiram duas versões de teste (73121910270823 e 111948356962277), que não são
    usadas.
- **Conferido:**
  - no Studio, do ponto do olho (FOV de mira 50,4°): o anel fica centrado e a lâmina no meio dele.
    Nada entre a alça e a massa sobe até a linha;
  - Lune 37 arquivos, 0 falhas (pegada, F5, armas e toque); pytest 61.

## D-171 — Lote 55: a carta tática no estilo de página de atlas (2026-11-15)

**Pedido do dono:** "deixe o mapa nesse estilo" (imagem de um atlas político aberto: países em
cores chapadas, fronteiras escuras, mar azul com as linhas de costa, nomes em etiquetas bege com
seta). Da imagem vale o estilo; o mapa é o nosso, de 700 x 700 m (regra da memória).

- **Folha** (`tools/make_carta.py --estilo atlas`, blocos `assets/carta/atlas_*.png`):
  - papel claro e cores chapadas da paisagem: mata verde-claro, lavoura amarelo-palha;
  - relevo só num sombreado leve, sem curvas de nível nem símbolos de vegetação;
  - o rio do sul em azul de atlas com três linhas de costa dentro d'água;
  - estradas, casas, vilas, bases e grade de 1 km (em azul), com moldura dupla;
  - sem a caixa da rosa dos ventos: a janela já tem o norte e a escala, e a letra do setor A caía
    em cima dela.
  - A topográfica (`--estilo topo`, o padrão do script) continua no `roblox_ids.json` como
    `Carta.*_topo`.
- **Por cima, no jogo** (`CartaView`):
  - cada setor pintado pelo dono como um país do atlas: azul dos EUA, vermelho do VC, creme
    neutro. A cor continua fixa por lado. Transparência 0,6 no setor em jogo, 0,76 fora de jogo e
    0,88 no neutro (era 0,84/0,9/0,94, quase invisível);
  - fronteiras: tracejado escuro entre setores do mesmo dono e, no contato, as duas cores com um
    fio escuro no meio. A letra do setor sai na cor do lado escurecida, com o halo do papel;
  - objetivos: etiqueta bege com tinta escura, afastada 40 px do ponto rumo ao meio da carta (os
    dos cantos não saem da folha), presa por uma linha com seta. "ATACAR/DEFENDER" virou uma tarja
    no alto da etiqueta: fora dela, as duas se cobriam.
- **Conferido no Studio:**
  - os 4 blocos novos resolvidos pelo `CartaService`;
  - a `CartaView` montada numa tela de teste com uma partida de exemplo (VC em A e B, neutro em C,
    EUA em D e E, B em disputa, C sendo tomado): setores, fronteiras e as 5 etiquetas com seta
    legíveis.
  - O fluxo de abrir o mapa pelo M não foi conferido: o teclado do MCP não chega ao jogo com o
    Studio atrás de outra janela.
- Subiram duas séries de blocos. A primeira (115672300899918, 116059414410035, 110806933850980 e
  117558276761799) ainda tinha a rosa dos ventos e não é usada.

## D-172 — Lote 56: mais construções e árvores nos objetivos e na vila (2026-11-15)

**Pedido do dono:** "traga mais coisas para os outros objetivos, mais árvores, construções grandes,
mais árvores na vila."

- **Segundo anel de construções** (`ArtPlan.OBJECTIVE_EXTRA`), de 16 a ~55 m do mastro:
  - A Arrozais: a fazenda. Casa grande (`vila_casa_04`), casa de varanda, celeiro maior e duas
    medas;
  - B Serraria: o segundo galpão, mais duas pilhas de toras, a palhoça dos lenhadores e um abrigo
    de folhas;
  - D Ponte e Cais: o armazém grande (`vila_casa_06`), a casa de telha, o celeiro e a cozinha;
  - E Engenho: a casa do dono (`vila_casa_08`), a segunda caldeira, a casa de varanda e o celeiro.
  - No plano entraram as 18. Os objetivos passaram de 3/4/9/4 peças para 8/9/13/8 (A/B/D/E).
- **Sem mexer no que é fixo (SLIM, D-155):**
  - as peças novas entram numa passada própria, depois da vila, com 3 m de folga de patamar,
    objeto e estrada. No Arrozais, que é todo lâmina e dique e não tem peça fixa, a folga é 1 m;
  - a pegada fica a 10 m da borda da área: a casa grande do Arrozais caía rente à borda sul;
  - conferido no Lune: as 409 construções de antes têm chave, posição, giro e base idênticos;
  - no Studio, 53 de 53 modelos fixos casaram, sem aviso.
- **Árvores** (sorteios próprios, para as plantas de antes não mudarem):
  - em volta de cada objetivo, de 22 a 48 m (`ArtPlan.OBJECTIVE_TREES`): coqueiros e bananeiras
    nas fazendas, árvores grandes no Engenho, na Ponte e na Serraria (com emergentes na mata);
  - na vila: árvores de sombra em volta da praça e uma grade do meio para fora nos vãos entre os
    lotes (até 30, a 6 m uma da outra). No fundo dos lotes não cabem: é tudo patamar, beco e rua.
    A grade de canto a canto punha as 30 na borda.
  - A 90 m do meio da vila são 34 árvores fora a mata (eram 2). No jogo, as plantas de quintal,
    sebe e vila foram de 394 para 467 e a arte carregada de 855 para 946 modelos.
- **Carta:** as construções novas entram na carta de atlas (`CONSTRUCAO_OBJETIVO` do
  `make_carta.py`). Os blocos foram regerados e subidos de novo.
- **Limite:** os bots usam as construções novas como abrigo, como as outras; não foi medido se o
  Offensive ficou mais lento.

## D-173 — Lote 57: caixas de suprimentos (2026-11-15)

**Pedido do dono:** "faça isso agora" + um prompt de monetização completa: loja, passes,
assinatura, passe de temporada, inventário, caixas grátis e pagas com chances, Fragmentos,
conformidade com o Roblox.

**Revê a D-20** ("caixa-surpresa paga rejeitada") só nas caixas: elas existem. A venda paga fica
desligada (`Caixas.PAGAS_LIGADAS = false`) até o dono reenviar o questionário de classificação. A
política de conteúdo manda reenviar quando uma atualização muda uma resposta, e o dono pediu antes
para não enviar o questionário.

- **Lido nas fontes oficiais (2026-11-15):**
  - chance numérica de cada resultado final, somando 100%, antes da compra;
  - lista com texto (ícone sem palavra não vale);
  - a chance atualiza quando um resultado muda para o jogador;
  - `ArePaidRandomItemsRestricted` por jogador; moeda comprável conta como paga;
  - recompensa aleatória sem Robux não precisa divulgar;
  - `ProcessReceipt` só concede com gravação; nunca pelo `PromptProductPurchaseFinished`.
- **Feito (5 caixas, 19 cosméticos novos e 25 skins):**
  - tabelas com pesos inteiros na base 100.000, versão por caixa e validação. Tabela ruim desliga
    a caixa na partida;
  - sorteio só no servidor (`Random`), dentro da transação atômica (`PlayerData.transact`,
    `UpdateAsync`). O resultado é gravado antes de ir ao cliente, e a animação só mostra;
  - caixa paga: `PolicyService` no servidor antes do prompt e na hora do recibo. Restrito, sem
    resposta ou com a venda desligada, o recibo vira Fragmentos fixos, sem sorteio;
  - recibo idempotente pelo PurchaseId (o resultado fica gravado com ele);
  - caixa gratuita com Bilhetes de Recompensa: 1 por missão do dia, 2 por missão da semana, teto de
    4 por dia, 2 de boas-vindas. Nunca à venda. Créditos ($), que são vendidos, não abrem caixa;
  - repetida vira Fragmentos de Arsenal (10/25/60/150/400). A troca por item garantido custa 10× o
    valor da raridade;
  - garantia progressiva pronta e desligada (`Caixas.PITY`): ligada, a tela mostra a chance
    efetiva;
  - itens novos, todos originais (sem insígnia real): 7 emblemas (`emb_*`, os do cartão), 6
    plaquetas (`tag_*`, o nome do jogador gravado no cartão) e 6 molduras (`mol_*`, borda e faixa
    do cartão). As skins entram com a raridade fixa por item;
  - tela: aba CAIXAS na loja e, por cima dela, itens e probabilidades, abertura 3D, troca,
    histórico e cartão;
  - animação completa, curta ou desligada, e PULAR. Caixa paga só aparece para quem pode comprar;
  - analytics: abertura por caixa, raridade e novo/repetido; Bilhetes e Fragmentos como economia
    (fonte e gasto);
  - textos em pt, en, es e vi.
- **Conferido:** Lune 20 ok (100.000 sorteios por caixa, qui² abaixo do limite em todas) e Studio.
  Detalhes e números em `testes/CAIXAS_2026-11-15.md`; auditoria em `MONETIZATION.md`.
- **Erros achados no Studio e corrigidos:**
  - remote com o tipo trocado parava a subida do servidor. O início das caixas ficou protegido, e
    há teste do tipo dos remotes;
  - recibo repetido refazia a abertura.
- **Não conforme com o pedido, esperando o dono:** a loja antiga vende vantagem de jogo. São as
  vantagens até +12% (D-101), os kits (D-72), renascer onde caiu, o veículo ao nascer (D-103), a
  camuflagem contra os bots (D-85) e os reforços de XP. O pedido novo diz "nenhum item pago pode
  criar vantagem competitiva", mas mexer nisso muda o que gente já comprou.
- **Fica para os próximos lotes:** Game Passes novos (Identidade Militar, Uniformes Históricos,
  Personalização de Armamentos, Fundador), Clube de Veteranos (assinatura), passe de 8 semanas,
  pacotes de compra direta, painel de configuração, caixas 3D próprias com som.

## D-174 — Lote 58: caixas grátis por marco, prêmios de saldo e compra direta (2026-11-16)

**Pedido do dono:** "deixe como esta e faça isso" + o "PROMPT MASTER DEFINITIVO" (jogo envolvente
para público jovem, monetização ética, caixas de recompensa, regras do Roblox).

**Decisão do dono:** os itens que dão vantagem na loja antiga ficam como estão (vantagens até +12%,
kits, renascer onde caiu, veículo ao nascer, camuflagem contra os bots, reforços de XP). A linha
"Igualdade competitiva" do `MONETIZATION.md` segue "Não conforme", agora como escolha registrada.

- **Caixas grátis por marco (5 novas, `fonte = "marco"`):** ficam guardadas no perfil
  (`caixas.guardadas`) até o jogador abrir. Cada marco só dá uma vez (`caixas.marcos`, teto de 512).
  O jogador recebe um aviso; a loja não abre sozinha.

  | Caixa | Marco |
  |---|---|
  | Recruta | treinamento de um papel ou a primeira partida completa (uma vez por conta) |
  | Serviço | cada posto novo |
  | Batalhão | cada missão da semana cumprida |
  | Campanha | níveis 10, 20, 30, 40 e 50 da trilha grátis do passe |
  | Veterano | 10, 25, 50, 100 e 200 partidas completas |

  A caixa de Bilhete (D-173) continua igual.
- **Prêmios de saldo**, só nas caixas grátis: $ 500 e $ 1.500 em créditos, 100 e 250 Fragmentos.
  Não viram repetida nem posse e não entram na troca nem na compra direta. A validação recusa prêmio
  de saldo em caixa paga.
- **Fragmentos 5/15/40/100/250** por raridade (eram 10/25/60/150/400, D-173), como no pedido. A
  troca segue em 10× (50/150/400/1.000/2.500).
- **Compra direta (caminho C):** o emblema, a plaqueta ou a moldura escolhidos, por créditos, sem
  sorteio. Preço por raridade: $ 1.500 / 3.000 / 7.500 / 15.000 / 30.000 (~300 por partida,
  `Skins.MONEY_PER_MATCH`). As skins seguem na Intendência.
  - A compra é atômica: o `PlayerData.transact` junta antes os créditos ganhos na sessão (o delta
    da memória) e trava o salvamento automático enquanto grava.
- **Nome da moeda:** o pedido chama de "Créditos de Serviço" a moeda ganha jogando. O jogo já tem os
  créditos de intendência, mostrados com o cifrão ($). Ficou o nome do jogo, para não haver duas
  moedas com nomes diferentes. As três moedas do pedido são: créditos ($), Fragmentos de Arsenal e
  Bilhetes de Recompensa.
- **Tela (aba CAIXAS):**
  - caixas de marco com "Como ganhar" e "ABRIR · N GUARDADA(S)";
  - saldo de créditos na linha de saldos;
  - botão COMPRA DIRETA, com a lista e "LEVAR · $ N";
  - aviso de caixa ganha;
  - prêmio de saldo desenhado como ficha com a quantidade;
  - textos em en, es e vi.
- **Ganchos de Studio novos** (`VT65DevCaixa`): `"creditos"` (+5.000), `"marco:<caixa>"` e
  `"partidas:<n>"`.
- **luau-lsp:** corrigidos erros de tipo que vinham da D-172 (`ArtPlan.OBJECTIVE_TREES` virou
  registro, com os mesmos valores) e da D-173 (perfil talvez nil no `CaixaService`; `pcall` no
  `Main`).
- **Conferido:** Lune 25 ok nas caixas (100 mil sorteios em cada uma das 10) e a suíte inteira.
  No Studio: caixas dadas pelos marcos, abertura de caixa guardada, compra direta ($ 6.300 →
  $ 4.800), aviso e prêmio de Fragmentos. A arte fixa bateu com o plano (53 de 53). Detalhes em
  `testes/CAIXAS_D174_2026-11-16.md`.
- **Próximos lotes do pedido:**
  - 59: "ARQUIVO MILITAR STARLITE" (álbum com coleções temáticas e recompensa garantida);
  - 60: os 4 Game Passes novos e o Clube de Veteranos.
  - Depois: sequência diária que não zera, medalhas com progresso e data, convite de amigos,
    funil do onboarding, cerimônia de posto, batalhões com nome filtrado, temporada de 8 semanas.

## D-175 — Lote 59: ARQUIVO MILITAR STARLITE (2026-11-16)

**Pedido do dono:** "siga" (lote 59 do prompt master definitivo, item 10: álbum de coleção). Na mesma
mensagem, a roleta das caixas entrou na fila como lote 61 (texto em `especificacao/`, só local).

- **O álbum** (aba ARQUIVO da loja, `Shared/Arquivo.luau` + `Controllers/ArquivoTela.client.luau`):
  - 53 itens em 5 categorias: uniformes, acabamentos de arma, insígnias, plaquetas e molduras;
  - cada item mostra o nome, a imagem (arma em 3D; soldado vestido no detalhe; pano da farda na
    grade; desenho do emblema, plaqueta e moldura), a raridade, se o jogador tem, como conseguir
    (caixas, troca, compra direta, Intendência, Robux, coleção) e "Compra direta" / "Grátis jogando";
  - categorias do pedido sem item no jogo (capacetes, mochilas, animações de inspeção) não
    aparecem. "Itens históricos de temporada" virou a marca da origem na caixa de temporada.
- **9 coleções temáticas** com prêmio garantido (valores de design, PLACEHOLDER):

  | Coleção | Itens | Prêmio |
  |---|---|---|
  | Objetivos da Operação | 5 emblemas dos objetivos | Plaqueta: carta dos objetivos + 100 Fragmentos |
  | Operação Starlite | Starlite, Chu Lai, carta de operações, moldura Starlite | Emblema: Operação + 150 |
  | Plaquetas de Identificação | as 6 plaquetas | Moldura: identidade + 150 |
  | Molduras do Cartão | as 6 molduras | Emblema: Arquivo + 150 |
  | Arsenal dos Fuzileiros | 8 acabamentos dos EUA | Moldura: arsenal dos fuzileiros + 300 + $ 3.000 |
  | Arsenal da Frente | 9 acabamentos da Frente | Moldura: arsenal da Frente + 300 + $ 3.000 |
  | Fardas dos Fuzileiros | 5 uniformes dos EUA | Plaqueta: fardas dos fuzileiros + 500 + $ 5.000 |
  | Fardas da Frente | 3 uniformes da Frente | Plaqueta: fardas da Frente + 300 + $ 3.000 |
  | Arquivo Completo | as 8 coleções completas | Moldura: Arquivo Militar + 1.000 + $ 10.000 |

- **Regras do pedido, cobradas no teste:**
  - nenhuma coleção exige caixa paga: todo item tem caminho grátis (caixa grátis, troca, compra
    direta ou Intendência com os créditos ganhos jogando);
  - o prêmio é um cosmético exclusivo (`exclusivo = "arquivo"`), fora das caixas, da troca e da
    compra direta. Assim quem joga de graça ganha algo que não se compra.
- **Resgate atômico, uma vez por conta:** `CaixaRegras.resgatarColecao` dentro do
  `PlayerData.transact`. Grava em `caixas.arquivo[coleção]`, separado dos marcos das caixas, e entra
  no histórico com a origem "colecao". O servidor confere a posse (Game Pass de uniforme conta). Uma
  coleção com erro na partida desliga o resgate, e o álbum continua visível.
- **`caixas.marcos`:** o teto subiu de 512 para 2048. As missões da semana dão até 3 marcos por
  semana; no teto, um marco perdido daria a caixa de novo.
- **Desenho comum (`Controllers/ItemArte.luau`):** a tela das caixas passou a usar o mesmo desenho,
  com a arma em 3D também na troca e na abertura. A roleta do lote 61 vai usar o mesmo módulo.
- **Ganchos de Studio:** `VT65DevCaixa = "colecao:<id>"` dá os itens de uma coleção, e
  `VT65DevTela = "arquivo"` abre a aba.
- **Conferido:** Lune 9 ok no álbum e a suíte inteira (684 ok); Studio com o resgate pelo clique, a
  recusa do segundo pedido e das coleções incompletas, e 0 erros. Detalhes em
  `testes/ARQUIVO_D175_2026-11-16.md`.

## D-176 — Lote 60: conjuntos em Game Pass (2026-11-16)

**Pedido do dono:** "continua" (lote 60 do prompt master definitivo, item 19, com a criação dos 4
Game Passes na conta).

- **4 conjuntos de compra única** (`Shared/Conjuntos.luau`), com os preços de referência do pedido:

  | Conjunto | Robux | Itens (todos novos, exclusivos e só visuais) |
  |---|---|---|
  | Identidade Militar | 49 | plaquetas de cobre e de aço enegrecido; emblemas Bússola e Sinalizador; molduras de cordão de paraquedas e de carimbo de serviço |
  | Uniformes Históricos | 99 | HBT verde-sálvia e tigrado dourado (EUA); áo bà ba verde-oliva e anil (Frente) |
  | Personalização de Armas | 149 | M14 nogueira oleada, M60 fosfato novo, M1911A1 talas de plástico marrom, Tipo 56 madeira avermelhada, SKS madeira clara, RPD aço azulado e madeira escura |
  | Fundador STARLITE | 499 | uniforme de fundador nos dois lados, Insígnia de Fundador, Emblema Fundador 1965, plaqueta comemorativa, moldura (o cartão exclusivo) e o título "Fundador STARLITE" |

- **Do pedido, o que ficou de fora** (não existe no jogo, e nada é vendido sem existir): capacetes,
  acessórios e variações de equipamento (Uniformes Históricos), gravações e animações de inspeção
  (Armas). Fica para quando houver o sistema.
- **Posse:**
  - a skin vale pelo passe (`Skins.owns`, com `robuxKey` igual à chave do conjunto);
  - `soPasse` tira a skin do $ da Intendência e do Mercado. Lá aparece "Só no conjunto em Game
    Pass", com o botão VER O CONJUNTO;
  - os itens de cartão e o título são gravados no perfil (`campaign.owned`) quando o servidor vê
    o passe (ao entrar e depois da compra, `CommerceService.onConjuntos`). Assim o cartão, o
    álbum e o USAR veem igual.
- **Fora de tudo o que é sorteio ou troca:**
  - `exclusivo = "passe"`: não entra em caixa, a validação recusa;
  - não entra na troca de Fragmentos nem na compra direta;
  - no ARQUIVO, a origem é o conjunto, sem caminho grátis;
  - nenhuma coleção pede item de conjunto.
- **Venda:** página CONJUNTOS no ARQUIVO.
  - O botão COMPRAR mostra o preço lido do Roblox e abre o prompt oficial.
  - Quem já tem vê "NO SEU ARQUIVO".
  - A loja não fica aberta em combate, então não há prompt acidental.
- **Uniformes:** 6 moldes novos no gerador (`tools/make_clothing_skins.py`, as mesmas costuras da
  v3), subidos ao Roblox. As cores são de olho: PLACEHOLDER até a foto (`check = "foto"`).
- **Imagens dos passes:** montadas no próprio jogo (`ItemArte` e o manequim do lobby com os moldes
  novos) e recortadas. O nome do jogador nas plaquetas virou "STARLITE", porque a imagem é pública.
- **Criados no Roblox:**
  - 4 Game Passes à venda: Identidade 2088634972, Uniformes 2088232933, Armas 2089588819 e
    Fundador 2087975040;
  - 12 decals de roupa.
- **Clube de Veteranos (assinatura):** ainda não. A assinatura só se cria no Creator Hub (é do
  dono). Os benefícios entram quando houver o ID.
- **Conferido:** Lune 6 ok nos conjuntos e 690 na suíte. No Studio, a posse dos 4 passes, os itens
  gravados, a página CONJUNTOS e o soldado em campo com o molde novo, com 0 erros. Detalhes em
  `testes/CONJUNTOS_D176_2026-11-16.md`.

## D-177 — Lote 61: roleta horizontal nas caixas (2026-11-16)

**Pedido do dono:** "siga para a roleta". O texto do pedido está em
`especificacao/PROMPT_ROLETA_CAIXAS.md` (só local): roleta horizontal inspirada no Counter-Strike,
com identidade própria. Só a apresentação muda.

- **Não mudou:** sorteio, chances, preços, prêmios, regras de quem pode comprar, inventário,
  compras e gravação. O resultado continua gravado pelo servidor antes de qualquer animação.
- **Galeria antes de abrir** (ITENS E PROBABILIDADES):
  - imagens do mesmo tamanho, com a chance real de cada item embaixo, o fundo e a borda da
    raridade e o selo ✓ no que já tem;
  - sem nome no cartão. O nome, a raridade, o tipo, a chance e o "vira +N Fragmentos" aparecem na
    descrição ao passar o cursor, focar com o controle ou tocar;
  - as regras ficam na mesma tela, antes do botão de abrir ou comprar.
- **Roleta** (`Shared/Roleta.luau`, puro, com teste):
  - 48 cartões, com o vencedor do servidor no 42º;
  - o enchimento é sorteado no cliente com os mesmos pesos da lista, cada cartão independente e
    sem olhar o vencedor. Nada de item raro posto ao lado para fingir "quase saiu";
  - a parada é exata no centro do cartão (sem deslocamento de "por pouco");
  - duração: 6 s no modo completo e 2,6 s no curto, com desaceleração Quint (velocidade zero no
    fim). O PULAR existe desde o começo;
  - de 3 a 7 cartões conforme a largura; no celular (só toque), no máximo 5.
- **Visual:** fundo escuro de campanha, a janela da faixa, o marcador de latão fixo no centro com
  as setas, as pontas escurecidas, a borda acesa da raridade no cartão e um destaque ao parar.
  Épico e lendário têm clarão, halo e raios girando.
- **Imagens dos itens** (`ItemArte`, os modelos do próprio jogo):
  - arma em 3D com o acabamento, de lado;
  - uniforme vestido no soldado do lobby com o molde de verdade. O servidor resolve o id da imagem
    (`ImagensUi.moldes`, atributos `Molde_*`), porque o cliente não abre decal;
  - emblema, plaqueta e moldura centralizados; ficha para créditos e Fragmentos.
- **Recompensa:** o cartão ampliado, a raridade com a luz dela, o som da raridade, EQUIPAR e
  VOLTAR. EQUIPAR põe a plaqueta ou a moldura no cartão, o emblema pelo `card_set` e a skin pelo
  `Gear_Equip`. Troca, compra direta, conta restrita e efeitos desligados vão direto à recompensa.
- **Sons** (`tools/sons_roleta.py`, síntese própria, 5 áudios enviados ao Roblox): a lingueta a
  cada cartão (no máximo 1 a cada 45 ms), a trava ao parar, e um sino conforme a raridade.
- **Carregamento:** os cartões são montados em lotes de 12 por quadro. Os moldes de roupa são
  pré-carregados como imagem, até 1,5 s, antes de girar, para nenhum cartão mudar no meio.
  Pré-carregar o Shirt/Pants gerava aviso no Output.
- **Conserto da D-175:** o botão "FALTAM %d" do álbum empatava com o "FALTAM %s" que já existia, e
  a tradução dependia da ordem do dicionário. Virou "AINDA FALTAM %d".
- **Conferido:** Lune 5 ok na roleta e a suíte inteira. No Studio, 4 aberturas pararam no item do
  servidor (índice 42, desvio de 0,5 px), com e sem PULAR. Também a galeria, a recompensa e o
  EQUIPAR, e o Output sem os avisos dos moldes depois do conserto. Detalhes em
  `testes/ROLETA_D177_2026-11-16.md`.

## D-178 — Lote 62: 100 itens novos nas caixas, extravagantes (2026-11-16)

**Pedido do dono:** "crie 100 novas skins e itens para ganhar nessas caixas, podem ser bem
extravagantes se inspire no cs battlefield e outros jogos faça com maestria".

- **O que entrou:** 60 acabamentos de arma e 40 itens de cartão (14 emblemas, 13 plaquetas e
  13 molduras), todos só visuais.
  - Por raridade: 9 comuns, 18 incomuns, 29 raros, 28 épicos e 16 lendários.
  - A inspiração é o estilo de pintura dos jogos de tiro: degradê, damasco, tigre, carbono,
    cromo, camuflagem digital, lava, galáxia. Os nomes e os desenhos são próprios. "Fibra de
    Carbono" virou "Trama de Carbono" para não repetir nome de skin de outro jogo.
- **Acabamentos (`Skins.EXTRAVAGANTES`, campo `soCaixa`):**
  - saem só das caixas e da troca de Fragmentos. A Intendência ($ e Robux) e o Mercado não os
    vendem (`canBuy` responde "só nas caixas");
  - na lista de armas do perfil, aparecem só para quem já tem;
  - 6 na M14, M16, Tipo 56, SKS e RPD; 5 na M60, M1911A1, Winchester M70, Winchester 12, Tipo 54
    e Mosin-Nagant.
- **Texturas de verdade** (`tools/acabamentos.py`, teste `tests/test_acabamentos.py`):
  - 23 receitas de desenho mais a "tinta";
  - a malha de cada arma é rasterizada no espaço da textura (cada texel ganha a posição 3D e a
    normal), e o padrão é pintado em 3D, contínuo na arma inteira;
  - a luz e os detalhes da textura original continuam por cima (razão de luminância);
  - a cor original separa madeira, metal, latão e pano. O latão (cartuchos, cinto) e a bandoleira
    nunca são pintados. A receita diz o alvo: tudo, só o metal ou só a madeira;
  - camuflagem, pixel e laca medem a cobertura na própria arma, então cada cor cobre a mesma
    fração em qualquer arma;
  - prévias de lado em `assets/acabamentos/previas` (fora do Git, como os GLB das armas).
- **Conserto: os acabamentos antigos não apareciam.** A arte das armas é uma malha só, sem as
  peças Madeira/Metal que a tinta da D-131 pintava. Os 23 acabamentos de antes (17 da Intendência
  e 6 do conjunto da D-176) agora também têm textura, pela receita "tinta": a cor de madeira,
  guarda-mão e metal sobre a textura original, e a fita enrolada no guarda-mão.
- **Como aplica (`Skins.applyWeapon`):**
  - troca o `TextureID` da MeshPart pela textura do acabamento (`Shared/AcabamentosArte.luau`,
    gerado por `--luau`);
  - guarda a SurfaceAppearance numa pasta da peça e devolve tudo ao tirar a skin. Script não pode
    trocar o mapa de cor de uma SurfaceAppearance, por isso a troca de textura;
  - a textura sobe como **Decal** (como as imagens do chão e da loja) e o ID da imagem é
    resolvido no Studio (`--resolver`, `assets/acabamentos_imagens.json`);
  - no Studio, cada textura nova no `TextureID` escreve 3 avisos "No asset content
    representation" no Output, com Image ou Decal e mesmo pré-carregada. A textura carrega e
    aparece;
  - a roleta pré-carrega as texturas das armas antes de girar, junto dos moldes de roupa. Sem isso
    a arma aparece clara por um instante.
- **Itens de cartão:** cor de degradê (`cor3`). O fundo do emblema, a plaqueta e a borda da
  moldura passam de `cor` para `cor3` (UIGradient a 45°), no cartão do jogador e nas imagens das
  caixas e do ARQUIVO. A sigla do emblema fica na cor dela.
- **Nas caixas, sem mudar nenhuma porcentagem** (`Caixas.acrescentar`):
  - dentro de cada raridade, os pesos são redivididos. O total da raridade fica igual e cada item
    novo pesa como a média dos antigos dela (pesos inteiros, maior resto);
  - todo item novo está numa caixa grátis e na de Suprimentos:
    - Recruta e Recompensa recebem os comuns;
    - Recompensa e Serviço, os incomuns;
    - Serviço, Batalhão e Campanha dividem os raros;
    - Campanha e Veterano, os épicos;
    - Veterano, os lendários;
  - nas pagas, Suprimentos recebe os 100, Equipamentos Especiais de incomum a lendário e Arsenal de
    Elite de raro a lendário. A Operações Históricas não muda;
  - a caixa que mudou subiu de versão (o resultado gravado guarda a versão da tabela).
- **Traduções:** 200 textos em inglês, espanhol e vietnamita. As siglas e os nomes em inglês dos
  itens de cartão foram para o `ignorar.json`.
- **Conferido:** Lune 697 ok na suíte (caixas 27, skins 17, arquivo 9), pytest 67
  (`test_acabamentos` 6). No Studio:
  - troca → equipar → campo, com a M14 de 1ª e 3ª pessoa no Tigre de Fogo;
  - a roleta parou no item do servidor (índice 42, desvio de 0,5 px) e o EQUIPAR pôs a textura
    na M60;
  - o degradê no cartão aparece e some ao trocar;
  - 0 erros. Detalhes em `testes/ACABAMENTOS_D178_2026-11-16.md`.

## D-179 — Lote 63: acabamentos universais estilo R6 e relevo de verdade (2026-11-16)

**Pedido do dono:** "faca skins estilo jogo r6 tbm como inverno sombrio, geleiras, entre outras" e
"skins das pedras tem q ter relevo", com imagens de referência (gemas lapidadas, ouro, gelo).

- **12 acabamentos universais** (`Skins.UNIVERSAIS`): um item vale em qualquer uma das 11 armas
  com arte (`Skins.ARMAS_UNIVERSAL`), do lado do jogador, como as gemas do R6.
  - Gemas lapidadas: Cristal Rubro, Ciano, Cobalto, Âmbar, Violeta e Esmeralda, e o Quartzo
    Rosa.
  - Pedra e metal: Obsidiana Lapidada, Ouro Lapidado e Ônix Polido.
  - Gelo: Inverno Sombrio (azul quase preto cortado por lascas de gelo, geada e neve em cima) e
    Geleira Antiga (gelo em camadas com rachaduras).
  - Os nomes são próprios: nada de "Ruby", "Glacier" ou outro nome de skin de jogo.
  - Raridades: 2 raros, 7 épicos e 3 lendários. Só caixas e troca de Fragmentos.
- **Equipar:** o universal aparece debaixo de cada arma do perfil (aba ARMAS) para quem tem, e
  equipa na arma do cartão (`Gear_Equip(id, on, arma)`).
  - Pode ficar em várias armas ao mesmo tempo.
  - O EQUIPAR da roleta põe na arma da mão ou, sem ela, na de fábrica do lado (M14 ou Tipo 56).
  - A regra do encaixe é `Skins.cabe`.
- **Relevo de verdade** (`tools/acabamentos.py`):
  - a rasterização guarda a tangente e a bitangente de cada texel. O relevo da receita vira mapa
    normal em espaço tangente, somado ao relevo da arte original (mistura "whiteout");
  - nas gemas cada faceta é um plano inclinado (normal sorteada por faceta), com a luz correndo
    nele. No gelo e na pedra o relevo sai de uma altura: rachaduras fundas, geada e camadas;
  - as pedras de antes também ganharam relevo: jade, mármore (2), malaquita, lava (2) e escamas
    (3);
  - mapas de material por classe (`CLASSES`): gema, ouro, gelo, pedra e espelho (cromo e ouro de
    antes). Têm metal e aspereza próprios onde o acabamento pinta e os da arte original no resto.
- **SurfaceAppearance pronta** (`src/ReplicatedStorage/VT65AcabamentosSA.model.json`, gerada por
  `--luau`):
  - cada acabamento tem a dele: a cor nova, mais o relevo e o material (novos ou os da arte
    original, lidos no Studio em `assets/armas_pbr.json`);
  - `Skins.applyWeapon` clona a pronta (script não muda o ColorMap) e guarda a original;
  - todos os acabamentos das 11 armas passam a usar a pronta, então os da D-178 recuperam o
    relevo e o brilho da arte;
  - a M79 e o RPG-2 continuam pelo `TextureID`, porque não têm a cópia de 1ª pessoa.
- **Nas caixas, sem mudar nenhuma porcentagem** (`Caixas.ACRESCIMOS_D179`, a mesma regra da
  D-178):
  - raros em Batalhão e Campanha; épicos em Campanha e Veterano; lendários no Veterano;
  - os 12 em Suprimentos, Equipamentos Especiais e Arsenal de Elite.
- **Conferido:** Lune 699 ok, pytest 70 (`test_acabamentos` 9). No Studio:
  - a pasta com 212 SurfaceAppearance no place; os 12 universais nas armas de vitrine;
  - troca, equipar na M14 e na M1911 (recusa na Tipo 56) e a M14 em campo com o Cristal Rubro;
  - o EQUIPAR e o TIRAR do perfil na M16; os acabamentos da D-178 pela pronta;
  - 0 erros. Detalhes em `testes/UNIVERSAIS_D179_2026-11-16.md`.

## D-180 — Lote 64: mais 12 universais e os acabamentos de antes melhorados (2026-11-16)

**Pedido do dono:** "continue fazendo e melhore os outros", com imagens de referência de skins de
jogos de tiro (gemas nevadas, cristal iridescente, ouro escorrendo, flores, nuvens desenhadas,
ondas, porcelana, jade com ouro, malha neon). Das imagens vale a ideia; o desenho e os nomes são
próprios.

- **12 universais novos** (o lote `Skins.UNIVERSAIS_D180`; agora são 24 universais):
  - Nevasca Rubra, Violeta e Rosa: metade das facetas brancas de geada, metade lapidadas na cor;
  - Cristal Iridescente (facetas claras com reflexo rosa, verde-água e lilás) e Cristal Polar
    (gelo azul em facetas com a geada nas arestas);
  - Ouro Derretido: preto lustroso com o ouro escorrendo de cima em pingos de ponta redonda;
  - Mar Revolto (escamas de onda), Galho de Cerejeira, Nuvem Rubra (nuvens de contorno duplo e
    fios de ouro), Rede Neon (malha de triângulos acesa do magenta ao ciano), Porcelana de Huế
    (esmalte branco, flores e ramos azul-cobalto e frisos de ouro) e Jade e Ouro (filigrana);
  - raridades: 1 raro, 7 épicos e 4 lendários. Só caixa e troca, na mesma regra das caixas
    (`Caixas.ACRESCIMOS_D180`).
- **Os de antes, melhorados:**
  - todo acabamento agora tem o material dele na SurfaceAppearance:
    - laca e porcelana: verniz brilhante;
    - damasco, titânio e ouro derretido: metal;
    - carbono: semibrilho;
    - degradê, tigre, zebra, colmeia, chamas, raio, galáxia, óleo, escamas e os desenhados:
      pintura acetinada;
    - camuflagem, pixel, bambu e carta: tinta fosca de campo;
  - antes só as pedras, o gelo e o espelho tinham material;
  - ganharam relevo:
    - a trama do carbono (3);
    - a colmeia (2), com a célula alta e a linha funda;
    - o damasco gravado (3) e as lascas da laca (4);
    - os nós do bambu (2) e as curvas da carta (2).
- **Gerador mais rápido:** a cor e o relevo da mesma gema dividem as facetas (`Ctx.memo`): 12
  universais numa arma em 90 s.
- **Conferido:** Lune 700 ok, pytest 70. No Studio, as 344 SurfaceAppearance no place, os 12 novos nas armas de vitrine e o Ouro Derretido trocado, equipado na M14 e visto em campo; 0 erros. Detalhes em `testes/UNIVERSAIS_D180_2026-11-16.md`.

## D-181 — Lote 65: desempenho e carga dos acabamentos (2026-11-16)

**Pedido do dono:** "faça isso então", depois do relatório da D-180, que deixava sem teste o jogo
publicado e o desempenho com muitas armas de acabamento na tela.

- **Medido no Studio** (60 armas na frente da câmera, qualidade 10):
  - 60 armas de fábrica: 65 chamadas de desenho, 743 mil triângulos, GPU 1,5 ms;
  - as mesmas 60 com 60 acabamentos diferentes (o pior caso de uma partida 30 contra 30):
    - 140 a 148 chamadas de desenho (cada acabamento é um material);
    - triângulos e GPU iguais (1,5 a 1,6 ms);
    - +104 a +137 MB de textura (169 mapas de 1024 novos: 60 de cor, 49 de relevo, 30 de metal
      e 30 de aspereza);
  - o contador de memória de textura do Studio oscila mais que a diferença a medir: trocar os
    mapas de metal e aspereza de 512 de volta para 1024 deu −35 MB. Vale a conta de pixels, não
    esse número.
- **Mapas de metal e aspereza em 512** (`TAM_CLASSE`): quase não têm detalhe e, em 512, têm 1/4
  dos pixels. As 180 imagens foram refeitas e enviadas de novo.
- **Carga das texturas** (`Controllers/AcabamentoCarga`, etiqueta `Skins.TAG_ACABAMENTO`):
  - no Studio, 10 de 240 imagens pedidas de uma vez falharam, e a imagem recém-enviada também
    falha por alguns minutos. Antes, a arma ficava clara a partida inteira;
  - agora a SA do acabamento é pré-carregada. Se falhar, há 3 novas tentativas (4, 8 e 12 s), e
    a SA é recolocada na peça quando a textura chega;
  - se não chegar, a arte de fábrica volta só naquele cliente (atributo `AcabamentoFalhou` na
    peça), e o próximo acabamento entra normalmente;
  - os acabamentos equipados (`WeaponSkins`) são pré-carregados ao mudar, antes de nascer;
  - script do jogo não lê o `ColorMap` da SurfaceAppearance (só plugin). Os 4 IDs vão no
    atributo `Mapas` da SA pronta (`--luau`), e `Skins.chavePronta` dá a chave.
- **Conferido no Studio:**
  - simulando uma imagem que não existe, a arma voltou à arte de fábrica em 26 s;
  - trocar de acabamento depois e tirar a skin funcionaram;
  - na 2ª medição, as 240 imagens carregaram em 6 s, sem falha;
  - 0 erros.
- **Jogo publicado** (Roblox Player, versão 110 do place):
  - nas galerias das caixas, os acabamentos da D-178 e os universais aparecem com a cor
    certa;
  - o console do cliente tem 134 erros "Failed to load … SurfaceAppearance. PBR textures
    may not be visible in game". Atingem os acabamentos e também a arma de fábrica, as casas
    da vila, as árvores, os animais e o chão: não é dos acabamentos;
  - fora do Studio, não deu para confirmar se o relevo e o brilho aparecem;
  - detalhes em `testes/CARGA_D181_2026-11-16.md`.

## D-182 — Lote 66: o contador do pente, sem tiro correndo e o JOGAR leva à mesa (2026-11-16)

**Pedido do dono** (16/11): uma lista de 24 itens e a especificação da adaptação para celulares e
tablets (`especificacao/PROMPT_MOBILE.md`, só local; "Use esta versão para substituir a
anterior"). Vai em lotes pequenos, primeiro os defeitos que atrapalham a partida. Este lote traz os
três mais simples:
- "eu atiro e contagem de balas n cai no pente";
- "estou conseguindo atirar enquanto corro";
- "o botao do lobby jogar n deve me levar direito pro jogo".

- **Contador do pente** (`HudCampo`):
  - a causa: o HUD só recebia a munição do servidor (`Combat_Ammo`), que é mandada ao equipar
    e ao recarregar;
  - agora ele segue a cada tiro os atributos locais `Carregador` e `Reserva` do
    `WeaponController`;
  - o servidor continua corrigindo pelo `Combat_Ammo`.
- **Correndo não se atira:**
  - `WeaponController.canShoot` recusa o tiro a pé com `Input.state.sprinting` ou com o atributo
    `Sprinting` do corpo;
  - o gatilho tira da corrida (`InfantryController`), como o mirar já fazia, e o tiro sai assim
    que o corpo para de correr;
  - no toque, o analógico na borda não volta a correr com o dedo no gatilho (`ToqueHud`);
  - sentado em veículo, nada muda.
- **JOGAR do menu principal** (`MenuPrincipal`):
  - o menu esmaece e mostra a mesa do lobby (lado, squad, papel e ponto), em vez de chamar o
    Jogar agora;
  - o JOGAR AGORA continua na mesa e no menu do jogo, e o RENASCER continua na tela de baixa;
  - novo subtítulo, traduzido em en, es e vi: "Escolha o lado, o squad, o papel e onde nascer.".
- **Teste no Lune:** o `interface.luau` agora cobra que o `play()` do menu principal não chame o
  `jogar_agora` e revele a mesa.
- **Conferido no Studio** (cópia local, toque forçado com `VT65DevToque`):
  - JOGAR → a mesa "ESCOLHA O SEU LADO", sem lado e fora de campo;
  - 3 toques no gatilho da M14: o carregador e o HUD foram de 20 para 17;
  - correndo pelo analógico, nenhum tiro saiu. Com o gatilho apertado no meio da corrida, a
    corrida parou e o tiro saiu 0,12 s depois (17 → 16).
- **Não testado:** mouse e Shift no computador (o mouse do MCP não dispara a arma de forma
  confiável), controle, celular de verdade e o jogo publicado.
- Detalhes em `testes/LOTE66_D182_2026-11-16.md`.

## D-183 — Lote 67: a pá funciona no mapa inteiro e foi feita no Blender (2026-11-19)

**Pedido do dono** (lista de 16/11): "crie a pá no blender" e "ela n esta funcionando".

**O que estava errado** (Studio, 2026-11-16, antes de mexer):
- no centro (C, neutro) e no setor do inimigo (A), a pá recusava com "Pá: só em setor do seu
  lado". No começo os EUA só têm D e E e o VC A e B, então onde se luta a pá nunca cavava;
- na base dos EUA ela cavava, mas o buraco tinha 0,62 m de fundo (pedido: 1,2 m). A pegada de
  0,6 m virava 1 voxel de largura (1,12 m), e a suavização do terreno enchia o fundo;
- em 1ª pessoa só apareciam as mãos: a ponta da lâmina ficava ~41° abaixo do centro, e a tela vai
  até ~35°;
- a animação dava UMA pazada (o laço de 0,6 a 2,0 s) e ficava parada até os 8 s, porque depois do
  laço vinha o fim inteiro (2,0 a 8 s).

**Regras novas** (`Shared/FieldWork`):
- cava em qualquer chão de terra, menos a até 75 m da base inimiga (`DIG.enemyHqM`, o mesmo do
  ponto de reunião do squad, `Front.squadRallyHqM`). Continuam: água, piso, 1 por minuto e 80 por
  partida;
- o limite por minuto diz quanto falta: "Pá: próximo buraco em %d s";
- buraco de 2 x 2 voxels (2,24 m de lado) alinhado à grade do terreno (`FieldWork.holeGrid`), com
  o centro 1,7 m à frente (a grade desloca até 0,56 m). A folga do fundo (`SMOOTH_EXTRA_M`) foi
  medida no Studio: 0,3 m deu 0,87 a 0,94 m; 0,6 m deu 1,24 m nos 4 pontos medidos; 0,9 m deu
  1,54 m. Ficou 0,6 m;
- o piso é procurado no meio e nos 4 cantos de dentro do buraco;
- o parapeito de sacos vai no lado do buraco que dá para onde o soldado olha, paralelo a ele e
  fora da parede (1,98 m do centro).

**Ao cavar** (`FieldWorkService`):
- o servidor põe a pá na mão com o relógio dele (`VT65Item`/`VT65ItemT`): a animação de todos
  começa junto com a terra e o som (antes era o `Posture_Set` do cliente, uma ida e volta depois);
- terra no buraco para todos: poeira ao cravar e torrões para a direita de quem cava ao jogar, nas
  5 pazadas;
- som da pazada (`tools/sons_pa.py`, sintetizado, 1,4 s) em laço no buraco;
- o soldado se agacha enquanto cava e volta a ficar em pé no fim (se estava em pé);
- cancela na hora em que ele sai do lugar (mais de 1 m no chão; antes só no fim dos 8 s).

**Animação** (`Shared/ItemAnim`): as 5 pazadas de 1,4 s vão por extenso de 0,6 a 7,6 s
(`ItemAnim.PA`). As chaves de 1ª pessoa são novas: a ponta da lâmina fica de 21° a 30° abaixo do
centro e vai de 15° à esquerda a 35° à direita ao jogar a terra.

**A pá do Blender** (`tools/blender/novos.py`, classe "pequeno"):
- `shovel_us`: M1943 aberta, de lâmina verde-oliva com nervura, dobradiça, porca serrilhada e cabo
  de freixo; 0,582 m;
- `shovel_vc`: cópia chinesa da MPL-50, inteiriça, com tubo do encaixe, tira rebitada e cabo
  alargado; 0,502 m, lâmina de 15 x 18 cm (Wikipedia, MPL-50);
- as duas com 600 triângulos e textura de 512; publicadas (`AssetIds.Models.shovel_us`/`_vc`);
- `Shared/PaArte` monta a pá da mão de 1ª e 3ª pessoa. O servidor copia os modelos para
  `ReplicatedStorage.VT65ItemArte`; sem eles, fica a pá em peças de antes.

**Defeito antigo achado no teste:** os objetos de mão de 3ª pessoa com mais de uma peça eram presos
com `WeldConstraint` antes de entrar no `workspace`. Essa solda grava o desvio quando entra, e aí a
`Weld` do tronco já tinha levado a peça principal para a mão. Resultado: as lentes do binóculo (e a
malha da pá nova) ficavam a ~1.900 studs do soldado. Agora é `Weld` com o desvio escrito (`C0`), no
`PaArte` e no `PostureController`.

**Toque:** a prévia "Buraco de combate" tem 2,24 x 2,24 m e cai na mesma grade do servidor.

**Limite que fica:** em 3ª pessoa, mesmo agachado, a ponta da pá fica de 0,33 a 0,52 m do chão
(em pé eram 0,50 a 0,68 m): com a pá curta, só ajoelhado ela encosta. Fica para o lote das
animações (correr sem saltitar e deslizar).

## D-184 — Lote 68: o helicóptero pousa nas rodas (2026-11-19)

**Pedido do dono** (lista de 16/11): "helicopoteros quando pousam ainda flutuam".

**Medido no Studio antes de mexer** (place da v107):
- **helicóptero de reforço do evento** ("Helicóptero pousando perto de C"): o fundo da malha ficava
  **3,09 m acima do chão** (`testes/lote68/evento_antes_flutuando.jpg`). Era o modelo velho do
  ForgeGUI ("uh34d"), com o pivô na base, e o código punha o pivô a meia altura do chão;
- **UH-34D parado no heliponto:** no chão (−0,01 m);
- **UH-34D pilotado:**
  - no heliponto pousou certo (−0,01 m na esteira);
  - fora dele, em chão abaulado, as rodas ficaram de 0,35 a 0,39 m no ar. O chassi é uma caixa de
    4 x 11,5 m com o fundo inteiro na altura das rodas: ela apoiava no meio, com os cantos de 0,48
    a 0,57 m no ar, e o pouso media a altura só no centro.

**Helicóptero do evento** (`EventosService`, inserção e medevac):
- usa a arte do UH-34D pilotável (Blender, `uh34d_v2`, na medida real) com o mesmo giro da arte no
  chassi (−90°). O modelo velho só entra se faltar a arte nova;
- pousa pelas rodas: o fundo da caixa vai no chão e o plano do chão sob as 3 rodas (peças `Roda_*`)
  inclina o helicóptero, até 12° (`Eventos.C.heliTiltMaxDeg`);
- o nariz aponta para onde ele vai, do QG para a LZ;
- o rotor gira no cliente (`Controllers/HeliEvento.client`, pela etiqueta `Eventos.HELI_TAG`);
- tem o som do rotor (`uh34d_rotor`) em laço no cubo, até 420 m.

**UH-34D pilotável** (`VehicleService`, `VehicleController`):
- **colisão nas rodas:**
  - o chassi não colide mais; continua com a massa, os assentos e os raios;
  - colidem, invisíveis e sem massa, a fuselagem (`Colisao_Casco`) e uma bola de 0,6 m em cada roda
    da arte (`Colisao_Roda`), com o fundo no fundo do chassi;
  - a fuselagem tem 2 m de largura, vai do nariz até a roda da cauda e fica com o fundo 0,45 m
    acima das rodas (PLACEHOLDER). Com a caixa inteira, numa encosta de 12° o canto de trás
    encostava no chão e as rodas ficavam a 0,5 m;
- **altura do pouso:** é a da roda mais perto do chão (antes, o raio no meio do chassi);
- **no chão:**
  - o vertical fica com a gravidade (a `LinearVelocity` passa a segurar só o plano, o deslize), e o
    helicóptero assenta nas 3 rodas;
  - a atitude é a do plano do chão sob as rodas (`VehicleDrive.groundPlane`, até 20°), não mais a
    das 4 pontas da caixa;
- **sem piloto:** enquanto ele cai e para, a atitude segue o plano do chão sob as rodas
  (`settleHeli`, também ao nascer):
  - presa na atitude de quando o piloto saiu, numa encosta de 6° ele ficava com duas rodas no ar;
  - solta de vez, tombava numa de 12°.
- A conta do plano (3 pontos, inclinação limitada) é pura e tem teste no Lune
  (`VehicleDrive.groundPlane`, `tests/luau/eventos.luau`).

**Conferido no Studio** (rodas da arte contra o chão, pelo raio que respeita a colisão):
- evento: −0,00, −0,00 e +0,01 m, inclinado com o chão (`evento_depois_pousado.jpg`); o rotor
  gira, o nariz aponta para a LZ e o som toca;
- heliponto: −0,01 m nas 3 rodas;
- pilotado:
  - fora do heliponto: +0,00, −0,00 e +0,01 m, com o piloto e depois que ele saiu;
  - numa encosta (≈10° de arfagem): +0,00, −0,00 e +0,01 m;
- vazio, solto sobre encostas: 6,3° → +0,01, +0,00 e +0,00 m; 11,9° → +0,00, +0,01 e +0,00 m;
  parado.

**Não testado:**
- o som do rotor do evento (não foi ouvido);
- o pouso com controle e no toque (só teclado);
- a subida do helicóptero do evento no fim (o código dela não mudou);
- o jogo publicado.

## D-185 — Lote 69: os eventos que ninguém via (2026-11-20)

**Pedido do dono** (lista de 16/11): "os eventos n estao acontecendo" e "melhore eles".

**O que o teste mostrou** (Studio, place da v108, partida com bots e o soldado na base dos EUA):
- a agenda funciona: o helicóptero de reforço veio 71 s depois de nascer e o depósito do VC 129 s
  depois disso;
- pelo gancho do Studio, os outros 5 (naval, aéreo, morteiro, medevac e contra-ataque) começaram
  sem erro, passaram pelas fases e mandaram os avisos;
- tudo caiu longe do soldado:
  - tiro naval: 6 impactos a 357–373 m;
  - bombas do A-4: 4 a 320–346 m;
  - morteiro: 8 a 300–389 m;
- para quem joga, cada evento era um aviso de texto curto (3 a 4 s) e uma linha na faixa da direita.
  O A-4 era só som. Dá para jogar sem perceber os eventos: é isso que o dono viu.

**O que mudou:**
- **Cartão do começo** (`Controllers/EventoCartao`, pelo `Toast.custom`, na faixa dos avisos e
  na zona do celular): o primeiro aviso de cada evento vira um cartão maior, de 7 s, com:
  - o ícone grande num selo da cor do que o evento é para quem vê (`Eventos.stance`): verde
    "A SEU FAVOR", vermelho "CONTRA VOCÊ" ou âmbar "PERIGO PARA TODOS" (o A-4 pega os dois lados);
  - o nome do evento e o que fazer (o texto do servidor);
  - onde: o setor, a distância e o rumo de quem vê ("C · ~325 m a oeste", `Eventos.whereFrom`);
  - numa barragem que pode ferir quem vê, dentro da área (raio do evento + 30 m,
    `Eventos.inside`), a linha vermelha "VOCÊ ESTÁ NA ÁREA: SAIA AGORA";
  - o estalo do rádio (`radio_squelch`) ao chegar.
  Os avisos seguintes do mesmo evento (barragem terminou, depósito destruído) continuam em texto.
- **Faixa da direita:** em vez da grade de 1965, a distância até o evento ("C · ~60 m"),
  atualizada 4 vezes por segundo.
- **O A-4 aparece:** uma silhueta em peças no tamanho real (12,2 m, 8,4 m de envergadura), com o
  rastro escuro do motor, na mesma reta do som (250 m de altura, 200 m/s). PLACEHOLDER de forma
  até um modelo do Blender.
- **Mais eventos:** um a cada 1,5 a 2,5 min (era 2 a 3 min). O primeiro continua no minuto 1.

**Conferido no Studio:**
- cartão a favor (tiro naval): selo verde, "APOIO NAVAL", a instrução e "C · ~325 m a oeste"
  (`testes/lote69/cartao_a_favor.jpg`);
- cartão contra, com o soldado a 60 m do centro de um morteiro do VC (raio de 148 m): selo
  vermelho e a linha "VOCÊ ESTÁ NA ÁREA: SAIA AGORA" (`cartao_perigo_na_area.jpg`);
- faixa com "C · ~60 m" em cada evento (`faixa_com_distancia.jpg`);
- A-4: 5 peças, nariz para oeste, a 250 m de altura, passou a 253 m do soldado e saiu depois de
  ~12 s; uma cópia parada fotografada de perto (`a4_silhueta.jpg`).

**Não testado:**
- o cartão âmbar do A-4 (a regra tem teste no Lune);
- o som do rádio (não ouvido);
- o celular;
- o jogo publicado.

**Visto de passagem:**
- numa janela estreita (a do Studio, ~840 px) o cartão cobre parte da faixa da direita;
- o Output do Studio enche de "Failed to upload TexturePack … 429 … PBR textures may not be
  visible": é o Studio subindo as texturas das SurfaceAppearance de uma cópia local.

## D-186 — Lote 70: a tela de entrada curta, com CONTINUAR (2026-11-20)

**Pedido do dono** (20/11): "a tela de carregamento inicial esta demorando demais" e "quero q antes
de vc realizar o prompt vc melhore as telas de carregamento". O prompt da interface (§5) pede:
nome STARLITE, ação principal "Continuar", configurações essenciais à mão, a dica de entrada pelo
aparelho, etapas reais (sem porcentagem fictícia), os estados de falha e continuar assim que o
essencial estiver pronto.

**Por que demorava:** desde a D-117 a tela esperava o jogo inteiro antes de sair: todos os sons,
todas as armas, o streaming do mapa todo, 95% das peças do Map (até 90 s) e a arte de tudo o que
chegou. Teto de 4 min.

**O que mudou** (visual da tela de 13/11 mantido: película, briefing e carta):
- **Só o essencial segura a tela**, em seis etapas reais: jogo, servidor, interface, sua ficha,
  soldados do menu e terreno (com o streaming dos três lugares dos planos do menu: Xóm Gò, Serraria
  e Arrozais). Teto do essencial: 60 s.
- **Sem porcentagem:** a barra tem uma parte por etapa, que enche com o que foi contado nela; a
  contagem aparece ("24/31") e "ETAPA 3/6" fica no lugar da porcentagem. Etapa que só espera o
  servidor tem o brilho que corre.
- **CONTINUAR** (Enter, A ou o toque; a dica muda com o aparelho) e **CONFIGURAÇÕES** (C ou X: o
  menu abre a aba Configurações e a recompensa diária espera ela fechar). Nada avança sozinho.
- **Avisos do que não chegou**, em âmbar: os dados do jogador ("Seus dados ainda não chegaram." ou
  "Seus dados não carregaram: esta sessão não salva."), os arquivos que falharam ("N arquivos não
  baixaram; o jogo tenta de novo."), o servidor que demora e o teto.
- **Em segundo plano:** armas, movimentos, sons e o mapa inteiro (D-117) terminam depois; a linha
  aparece embaixo da barra e no canto do menu principal ("Em segundo plano · sons: 40/164").
- **Medida:** os segundos de cada etapa ficam em atributos do script (`T_<etapa>`), e os do segundo
  plano também (`T_fundo_<parte>`).
- **Imagens:** o PreloadAsync não baixava id de imagem em texto solto (no Studio, 22 de 25 voltavam
  "Failure"; numa ImageLabel as mesmas carregam). O código antigo tinha o mesmo defeito e não
  contava as falhas. Agora cada imagem vai numa ImageLabel. Baixando de verdade, o chão (texturas
  do MaterialVariant), o céu e a carta tática custavam ~8 s da interface: foram para o segundo
  plano, o primeiro dele ("chão e céu").

**Medido no Studio** (mesmo PC, bots ligados, place local):
- antes (v109 com as marcas de tempo): as partes essenciais em 6,6 s, o mapa inteiro em 70,4 s e a
  tela saiu em **70,9 s**;
- depois: jogo 0,5 s, servidor 0,5 s, interface 4,3 s, ficha 4,6 s, soldados 10,1 s, terreno
  12,3 s e o **CONTINUAR em 12,7 s**. O segundo plano seguiu no menu (armas, movimentos e sons
  em ~2 s; a arte do mapa terminou aos ~74 s);
- CONFIGURAÇÕES: abriu a aba Configurações por cima do menu; a recompensa diária veio depois de
  fechar;
- o aviso mostrou "3 arquivos não baixaram" (da arte dos manequins; as 39 imagens da interface,
  do chão, do céu e da carta carregaram todas numa ImageLabel).

## D-187 — Lote 71: o soldado no veículo e a corrida depois do tiro (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 1): "o personagem some ao entrar no carro" e
"receber tiro não deve impedir a corrida".

**Causas:**
- `VehicleController` escondia o próprio corpo (LocalTransparencyModifier = 1) a cada quadro em
  QUALQUER câmera, inclusive na perseguição, e nada o devolvia ao sair;
- um tiro na perna ligava `legImpaired`: a velocidade caía para o passo (1,4 m/s), sem corrida, sem
  pulo e sem transpor até o curativo (D-93).

**O que mudou:**
- no veículo o próprio corpo só some na 1ª pessoa do assento e aparece na perseguição, esmaecendo
  com a câmera; ao sair (ou com o veículo destruído) fica como a câmera a pé espera; morto, à
  mostra. Os outros sempre veem o ocupante (só a transparência local muda);
- `Movement.LEG_WOUND_LIMITS = false`: a perna ferida não limita mais velocidade, corrida, pulo,
  transpor nem passada (jogadores e bots). O ferimento continua (sangra, pede curativo, aparece na
  tela). `true` volta a regra da D-93.

**Conferido no Studio:**
- jipe M151, motorista: em 1ª pessoa as 34 peças do corpo escondidas (câmera a 1,6 studs da
  cabeça); em 3ª pessoa as 34 à mostra, o soldado sentado ao volante na perseguição (11,8 studs);
  ao sair em 1ª pessoa, escondido; em 3ª, à mostra (o esmaecer da câmera colada, 0,42);
- perna ferida (`VT65DevFerido = "eu_perna"`): `LegImpaired` = true e, correndo, WalkSpeed 26,71
  studs/s = 7,48 m/s (a corrida nova vezes a vantagem 1,06 do dono); pulo 30. Antes ficaria em
  1,4 m/s sem pulo.

## D-188 — Lote 72: 20% mais rápido a pé, uma vez só, e o L3 da corrida (2026-11-20)

**Pedido do dono** (item 2): velocidade a pé dos dois times × 1,2, sem acumular; corrida por clique
no L3.

**O que mudou:**
- `Movement.FOOT_SPEED_K = 1,2`, aplicado na definição: andar 1,68, trote 4,70, corrida 7,06,
  agachado 2,35, rastejar 1,34, mirando 3,02, nado, transição, deslize (9,07) e os limiares de
  deslizar e mergulhar. Ninguém multiplica de novo (morrer, renascer, trocar de lado, veículo e
  partida nova leem as constantes). No Studio, a pé: WalkSpeed 17,81 studs/s = 4,99 m/s (o trote
  novo vezes a vantagem 1,06 do dono) e, correndo, 7,48 m/s;
- as acelerações sobem junto: arrancar, parar e virar levam o mesmo tempo de antes;
- pulo, gravidade e veículos ficam fora. A passada da animação segue a velocidade real (teto de
  reprodução 3,0 → 3,6, para rastejar e o VC agachado) e os passos seguem a distância;
- o L3 já alternava a corrida no controle (Parte 12.2); o teste novo cobre o aperto, o soltar que
  não desliga e a limpeza ao morrer, renascer, entrar no veículo e no túnel.

## D-189 — Lote 73: inclinar alternando, o tiro que mira no celular e a vibração da eliminação (2026-11-20)

**Pedido do dono** (itens 3 a 5).

**O que mudou:**
- **Inclinar:** três estados. Um aperto inclina, outro no mesmo lado volta, o outro lado vai direto
  (`InputMap.leanNext`). No controle, LB/RB mirando (antes L3/R3); mirando, LB e RB só inclinam
  (não abrem a roda nem lançam a granada). Prender a respiração foi para o L3 mirando; o R3 volta ao
  corpo a corpo. Q/E no teclado. Sair da mira, morrer, o veículo e o túnel centralizam (a D-99
  mantinha a inclinação ao soltar a mira). "Segurar" fica em Configurações › Acessib. › Inclinar. O
  toque (trava do botão, quina sozinha) segue segurando.
- **Celular:** o botão de tiro também mira com arma de fogo na mão (granada, pá, curativo: só a ação
  deles). Soltar desce a arma. O arrasto no botão gira a câmera, com outro dedo andando. Opção "só
  atira" em Configurações › Toque › Botão de tiro.
- **Toque rápido logo depois de correr:** a arma vale a corrida local por 1 s depois de parar (o
  "Sprinting" do servidor chega um ping depois e jogava o tiro fora).
- **Vibração:** o servidor numera cada abate no `Combat_Kill` (só quem abateu; assistência não); o
  cliente dá um pulso curto por número, no controle (motores) e no celular (HapticEffect), com a
  opção Vibração › Eliminação confirmada.

**Conferido no Studio** (toque forçado, `VT65DevToque`):
- segurar o tiro 1,5 s com a M14: a mira ligou na hora, saiu um tiro (semiautomática) e a mira
  desceu ao soltar; um toque de 0,12 s deu um tiro durante a subida da arma e a mira desceu;
- com a granada na mão, segurar o tiro não mirou e soltar lançou (granadas 3 → 2);
- o abate de um boneco pela granada mandou um `Combat_Kill` com `k = 1`.

**Não testado:** o inclinar no controle e no teclado (o teclado do MCP não chega ao jogo com o
Studio atrás), a vibração sentida e o celular de verdade.

## D-190 — Lote 74: a roda de equipamento com imagens e o binóculo fora do jogo (2026-11-20)

**Pedido do dono** (itens 11 e 12): roda "inspirada na referência de GTA", com as imagens das armas
e dos itens; retirar o binóculo das formas de obtenção e uso.

**O que mudou:**
- **Roda de equipamento:** 9 posições fixas, as duas armas no alto (o nome curto da vaga), depois
  granada, fumaça, bandagem, torniquete, pá, construir e a ferramenta do papel. Cada ficha mostra o
  próprio modelo do jogo num ViewportFrame (`Controllers/RodaArte`: a arte publicada da arma, a
  granada, a pá do Blender, as peças da mão), a munição da arma na mão, as granadas, fumaças,
  curativos e torniquetes que sobram, "EM USO" e o item apagado quando não dá. Escolher uma arma
  troca pela vaga, com o saque. Construir, caixa de munição, bolsa do médico e rádio são
  PLACEHOLDER de forma (peças simples).
- **Sem pulo entre vizinhos:** a escolha muda só a mais de meio setor + 7° do centro do setor
  escolhido (`InputMap.wheelIndexSticky`); no toque, o centro ainda cancela.
- A roda aceita até 10 fichas (teclas 1 a 9 e 0).
- **Binóculo:** `Equipar.REMOVED`. Saiu da vaga 7 (a faixa esconde, a tecla não faz nada), da roda,
  da tecla B, do tutorial e do toque. Ajuste de tecla salvo de ação que não existe mais é
  descartado no `InputMap.validate`. A ótica do comandante do veículo (`v_binoculars`) continua: é
  a vista do assento, não o item.

**Conferido no Studio** (`VT65DevTela = "roda_equip"`, gancho novo): as 9 fichas com o modelo de
cada coisa (M14, M1911A1, granada, fumaça, bandagem, torniquete, pá, sacos de areia), "EM USO" e
20/8 na M14, as quantidades (3 granadas, 2 fumaças, 4 bandagens, 2 torniquetes), construir e a
ferramenta do papel apagados para o fuzileiro. Com a roda aberta, 45 fps contra 37–38 fechada (o
número oscila com os bots; a roda não pesa). A faixa das vagas ficou com 1 a 6 e 8 a 10.

**Não testado:** a escolha pelo mouse, pelo analógico e pelo toque (só pelo gancho), o
binóculo do comandante no veículo.

## D-191 — Lote 75: a granada sem metragem e com piso, e os passos pelo chão (2026-11-20)

**Pedido do dono** (itens 6 e 8).

**O que mudou:**
- **Granada:** sem o número da distância no aviso de granada perto (a cor, o pulso e a direção
  continuam). O freio no chão depende do piso (`Shared/GrenadePhysics`: lama 0,45 e arrozal 0,40
  seguram, madeira 0,82, metal 0,85 e pedra 0,84 deixam rolar; antes 0,72 em qualquer chão) e, a
  cada quadro, um raio do lugar de antes ao de agora devolve a bola que pulou uma face fina e a faz
  quicar. O servidor continua dono do lançamento, da espoleta e da única detonação.
- **Piso** (`Shared/Superficie`): terra e grama, lama e dique, arrozal, água, areia e sacos de
  areia, madeira de casas e pontes, metal de veículos e pedra. O raio para no que está logo embaixo
  (a ponte vale mais que o rio).
- **Passos:** o som pelo piso; na divisa só troca com duas leituras seguidas; no ar não conta passo.
- **Faltam** os passos em metal e em pedra (sem asset): PLACEHOLDER com o da madeira e o da areia,
  listados em `Superficie.MISSING_STEPS`.

**Conferido no Studio** (`VT65DevGranada`, gancho novo): a 6 m/s a granada bateu no boneco e parou
a 2,5 m em 1,3 s; o aviso de granada perto apareceu sem o número (a etiqueta escondida e vazia).

**Não testado:** os passos ouvidos em cada piso e a granada passando por uma parede fina.

## D-192 — Lote 76: a queda do corpo pelo golpe que matou e a morte no veículo (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 7: ragdoll). O boneco de pano da D-107 já tinha
juntas com limite, uma queda por morte, a física do servidor que todos veem, o corpo congelado sem
colisão (não colide com veículo nem com outro corpo), o teto de 24 corpos e o tempo de vida.

**O que mudou:**
- o golpe que matou fica marcado no soldado (CombatService: de onde veio o tiro; ExplosionService:
  o centro, a distância e o raio). Até 0,6 s antes da morte ele empurra o corpo inteiro para longe:
  bala leve (8 studs/s), explosão mais forte perto do centro (até 30 no plano e 12 para cima),
  sempre abaixo do freio do assentar (`Corpos.impulso`). Sem golpe recente, o empurrão leve de
  antes. Corpo caído também é empurrado pela explosão (antes, só quem morria em pé);
- veículo: o assento solta (Sit e a SeatWeld). Lugar fechado: sem corpo, como antes. Lugar aberto
  (jipe, escotilha, porta): o corpo cai do lado de fora, a 5 studs.

**Conferido no Studio:** um boneco caído, morto por uma granada a 1,1 m (`VT65DevGranada`): golpe
"explosao", o tronco saiu a 3,3 m/s e deslizou 0,78 m no chão.

**Não testado:** a morte por bala, a morte num lugar aberto de veículo e o resultado visto por outro
jogador.

## D-193 — Lote 77: o fim de partida com pódio, votação e a volta do mapa (2026-11-20)

**Pedido do dono** (itens 21 e 22): comemoração com os três melhores do time que venceu, votação de
mapa mesmo com um mapa só, restauração e contagem.

**Regras (`Shared/Rodada`, testadas no Lune):** o pódio dos até três melhores do time que venceu
(desempate por pontos, abates, menos mortes, entrada e nome; empate entre os lados mostra os
melhores dos dois), a votação (um voto por jogador; sem voto, o mapa que existe; voto em mapa
inexistente não conta), as fases e o número da rodada.

**Fases** (`RodadaService`, 38 s no total, que viram o `MatchService.NEXT_MATCH_S`):
- fim (8 s): o relatório pós-ação de antes, com a faixa "VITÓRIA · <lado>";
- comemoração (12 s): os três melhores, cada um com o seu soldado girando (o personagem, ou o
  manequim do uniforme quando o jogador saiu);
- votação (15 s): um cartão por mapa, com a carta tática (2x2 blocos); o voto troca até o fim;
- restauração (3 s), e a partida nova começa com a contagem de antes.
- O estado vai para o cliente em atributos do ReplicatedStorage (`VT65Fase`, `VT65FaseAte`,
  `VT65Podio`, `VT65Mapas`, `VT65Votos`, `VT65MapaEscolhido`, `VT65Rodada`); o voto, pelo remote
  `Rodada_Votar`.
- Pontos por partida no `MatchService.placar`: o XP de cada recompensa, os abates e as mortes,
  zerados na partida nova.

**A restauração, em ordem:** corpos; objetos soltos (granadas, fumaça, armas caídas, napalm);
armadilhas; buracos (o voxel de antes de cavar volta e o parapeito sai); crateras; veículos (todos
saem, inclusive com gente dentro, e voltam aos depósitos; um temporizador de respawn antigo não
dobra o veículo); jogadores vivos voltam ao QG. Pedido de spawn com a partida encerrada é recusado.

**Conferido no Studio** (`VT65DevEnd`):
- as fases passaram de fim a jogo; o voto contou ("1 voto", "SEU VOTO");
- o fundo do buraco subiu 1,24 m e o parapeito saiu;
- havia 9 veículos antes e depois. O jipe, empurrado 80 studs, foi refeito. Nesse teste ficou a 60
  studs do ponto medido antes, que não era o depósito. Conferido no teste do lote 78, medindo o
  depósito antes de o jogo começar: depois da restauração o jipe estava a 0,04 stud dele;
- os corpos foram de 13 para 1;
- o soldado voltou vivo a 11 m do QG, e a rodada passou a 2;
- o pódio de três lugares apareceu com um pódio montado à mão (só havia um jogador).

**Não volta:** a grama queimada pelo napalm, as construções da logística e um tiro de morteiro ou
barragem já marcado. Os bots mantêm o estado.

**Não testado:** com vários jogadores (votos diferentes e o pódio de verdade), no celular e no jogo
publicado.

## D-194 — Lote 78: a troca de arma como estado (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 10): a arma atual desce, a próxima é puxada e entra
em posição, integrada à mira, à corrida, ao tiro, à recarga, à granada, ao veículo e à morte, sem
duplicar munição, recarregar de graça nem deixar o jogador travado, e visível em 3ª pessoa.

**O que já havia:** a descida e a subida de 1ª pessoa (KnifeView, tempos do Front 44 no
`Equipar.DRAW_S`), o gatilho preso durante a troca e a última troca valendo.

**Achado no código e corrigido:**
- uma troca pedida no meio de outra recomeçava a curva do alto: a arma pulava para cima;
- voltar à arma que estava descendo não cancelava: a outra entrava assim mesmo;
- a recarga continuava no servidor com a arma guardada. Trocar e voltar dava a arma cheia sem
  esperar com ela na mão;
- a mira apertada no meio da troca ligava com a arma ainda subindo;
- em 3ª pessoa a arma só trocava de lugar (sem descer), 0,1 s depois de chegar embaixo;
- o gancho de teste `"vaga:N"` nunca casava (o padrão aceitava só letras).

**Agora (`Shared/Equipar.Troca`, testado no `tests/luau/troca.luau`):**
- a altura da arma (0 em uso, 1 embaixo) é um estado com começo, descida que falta e subida. Troca
  nova parte da altura de agora (descida = holster × (1 − altura)). Voltar à arma que descia sobe
  de onde está (saque × altura). O modelo troca lá embaixo, no passo do quadro;
- recarga: a troca, a granada e o item nas mãos (curativo, pá) param a recarga. O cliente avisa
  (`Combat_Reload { cancel }`) e o servidor também para quando a mão muda (`Posture_Set { arma }`).
  Na espingarda ficam os cartuchos que já entraram (`Weapons.tubeLoaded`). A animação de 1ª pessoa,
  os cartuchos que faltam, a barra do HUD e o clipe de 3ª pessoa param juntos;
- mira apertada no meio liga no fim, se ainda estiver apertada (ou alternada); recarga pedida no
  meio sai no fim; golpe de faca e baioneta, não;
- veículo: entrar termina a troca (a arma certa ao sair); sair faz a arma subir do cinto, pelo
  sinal do assento (pelo passo do quadro ela aparecia um quadro em cima);
- granada: a arma desce da altura em que está; com uma troca pendente, depois do arremesso volta a
  arma que vinha;
- 3ª pessoa: o cliente avisa a curva no começo (`Posture_Set { troca }`); o servidor (ArmaNaMao,
  até 12 por segundo, com limites) põe o atributo "Troca" no personagem com o relógio do servidor.
  Cada cliente baixa a arma a partir da pega de agora (0,25 m abaixo, a boca 50° para o chão),
  espera a arma nova chegar à mão (até 0,6 s) e sobe. O próprio usa o atributo local "VT65Troca".
  A mão nova vale na hora no servidor (antes esperava 0,1 s).
- Deitado, a arma baixa só a metade (para não entrar no chão).

**Conferido no Studio** (M14 e M1911 do fuzileiro, 60 fps):
- M14 para pistola: a M14 chega embaixo em 0,27 s (0,24 + um quadro), a pistola fica pronta em
  0,54 s; o maior salto entre quadros é 0,16 stud;
- volta no meio: a pistola desceu a 38% e subiu em 0,114 s, sem trocar de arma;
- troca no meio da subida da M14: salto de 0,05 stud logo depois do pedido (recomeçar do alto
  saltaria ~0,65);
- recarga: 3 tiros (20 para 17), recarga, troca aos 0,7 s, 3 s com a pistola: a M14 voltou com 17
  e 8 carregadores. Antes voltaria com 20;
- mira apertada aos 0,11 s ligou aos 0,565 s (fim da troca, 0,54);
- saída do jipe: o 1º quadro já baixo e a M14 subindo até a posição em 0,57 s;
- granada puxada e guardada: na mão aos 0,25 s, no corpo (servidor) aos 0,32 s, de volta sem gastar
  granada (3 para 3);
- 3ª pessoa: o servidor pôs o "Troca" e a arma nova chegou à mão 0,03 s depois do fundo; na pose
  baixa a boca foi de −37° para −81° e a mão direita desceu 0,2 m.

**Não testado:** a troca vista por outro jogador (só havia um no Studio), o capim alto escondeu a
arma baixa nas capturas, a corrida e o deitar no meio da troca, o controle e o toque, o celular e o
jogo publicado.
## D-195 — Lote 79: a pá com uma pazada por aperto e o buraco que cresce (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 13): apertar o gatilho a cada cavada. A pá bate no
chão, a terra sai no contato, o buraco muda e a próxima pede soltar e apertar de novo. Segurar não
cava; o gatilho analógico precisa de limites de acionamento e liberação; cliques e toques valem uma
cada; sem fila sem fim. O buraco cresce aos poucos, com profundidade e colisão de verdade, bordas
irregulares, terra exposta e retirada, partículas e som juntos, validado no servidor, consistente com
vários cavando e restaurado na partida nova.

**Antes:** uma ação de 8 s (5 pazadas animadas em laço) que fazia o buraco inteiro no fim.

**Agora:**
- a pá fica na mão (vaga 8, roda, prévia do toque) até trocar de arma, puxar a granada, sentar num
  veículo ou cair ferido. Ao guardar, a arma sobe de baixo e quem pegou a pá se agacha (de pé, a
  ponta não chegava ao chão) e levanta;
- cada aperto do gatilho (RT, clique, toque no tiro) é UMA pazada de 1,4 s: a animação e o som de uma
  pazada, com a lâmina cravando aos 0,35 s, quando a terra sai. Apertos rápidos: no máximo uma na
  fila (nos últimos 40% da pazada); segurar não repete;
- gatilho analógico: aperta acima do limiar do jogador e só solta abaixo dele menos 0,08
  (`InputMap.triggerDown`). Vale para todo gatilho, inclusive o tiro;
- servidor (`FieldWorkService`): confere a pá na mão, a cadência (1,4 s com folga de 0,3 s; o excesso
  é jogado fora), o lugar (as regras de antes: terra, longe da base inimiga, fora da água e de piso,
  1 buraco novo por minuto, limite no mapa) e, no contato, que quem cava não andou 1 m nem saiu de
  3,2 m do buraco;
- buraco: 6 pazadas. A grade 4 x 4 de voxels em volta (o buraco 2 x 2 no meio, como na D-183) é
  escrita a cada pazada a partir do terreno de antes (`FieldWork.colunaVoxels`). O resultado é o mesmo
  não importa quem cavou nem em que ordem (vários jogadores no mesmo buraco), e quem entrar depois vê
  o terreno (é o terreno). O fundo desce por igual, com a folga da suavização desde a 1ª pazada. A
  borda desce até 0,15 m nas 2 primeiras, irregular e fixa por coluna. A fileira da frente sobe com
  a terra tirada (até 0,3 m). O capim do fundo vira terra revolvida. O parapeito de sacos fica em
  cima do monte, no fim;
- a obra guarda o terreno de antes na 1ª pazada: a partida nova devolve (D-193), inclusive o buraco
  pela metade;
- 3ª pessoa: o atributo `VT65PazadaT` (relógio do servidor) põe a pazada no clipe e no IK de todos
  (`ItemAnim.paTime`). O clipe gravado de 8 s fica, e a pá usa a subida e a 1ª pazada dele;
- o autoteste (`FieldWorkService.dig`) pega a pá, dá as 6 pazadas na cadência e guarda (~9 s, como
  antes).

**Conferido no Studio** (fuzileiro dos EUA, grama a ~90 m do QG; um aperto por `VT65DevRajada`):
- fundo depois de cada pazada, 1ª versão (sem a folga desde a 1ª): 0,00, 0,07, 0,34, 0,64, 0,94 e
  1,24 m. As 2 primeiras não apareciam;
- versão final: 0,24, 0,44, 0,64 e 0,84 m; depois 1,04 e 1,24 m. Um aperto entre elas não virou
  pazada no servidor (sem `VT65PazadaT` nem aviso). O provável é a folga de 0,15 s com um engasgo do
  servidor, e ela passou a 0,3 s. Não retestei depois disso;
- "Buraco pronto" e o parapeito no fim; apertos a mais no mesmo buraco: "Pá: este buraco já está
  pronto";
- borda de −0,20 a −0,55 m e monte de −0,09 a +0,22 m, em relação ao chão de fora;
- 10 apertos em 1 s: 2 pazadas; gatilho segurado 3 s: 1 pazada;
- trocar para a arma com a pá na mão: a pá saiu do corpo em 0,07 s e a M14 subiu de baixo em
  0,6 s. Na 1ª versão a arma aparecia pronta, porque o atributo ainda valia como mãos ocupadas;
- movido 4 m 0,05 s depois do aperto: "pazada perdida".

**Limites e não testado:**
- o servidor vê o corpo do cliente com o atraso da física (~0,15–0,2 s): um teleporte de 1,6 m
  0,2 s depois do aperto ainda não aparece no contato (a pazada contou). Por isso a regra do
  alcance também vale;
- a pazada perdida no buraco novo já conta o buraco no limite de 1 por minuto;
- não testado: vários jogadores no mesmo buraco, controle e celular de verdade, o som ouvido e o
  jogo publicado.
## D-196 — Lote 80: a torre leva a tripulação e as escotilhas, e o cano não entra no casco (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 15): espaço real para a torre e o atirador, com a
base e o eixo de giro, a altura e a posição do ocupante, o espaço do cano, os limites de elevação e
giro, o acesso e a saída e o modelo casado com a colisão. A torre não pode atravessar o chassi nem o
corpo do atirador; motorista e atirador independentes.

**Achado no código:**
- os lugares da torre (atirador, comandante e municiador do M48; atirador do Ontos; atirador da
  cúpula do LVTP-5) eram soldados ao casco. A torre girava só no desenho de cada cliente (o Transform
  da junta) e passava por cima dos corpos, e as cabeças saíam das escotilhas;
- as escotilhas da torre (comandante e municiador no M48, a da torre no Ontos) estavam presas ao
  casco e ficavam paradas no ar quando a torre girava;
- o cano tinha só os limites da ficha e podia descer por dentro do convés do motor.

**Agora:**
- `VehicleDrive.ART[id].torre`: os lugares e as peças que giram com a torre. As escotilhas da lista
  ganham a junta na Torre (`artJoints`) e os lugares, a solda (`addSeat`);
- o servidor gira as juntas da torre e do cano no mesmo passo dos clientes (`VehicleDrive.torreGira`,
  na velocidade da ficha; elevação a 20°/s): os corpos na torre ficam no mesmo lugar no servidor
  (que confere os acertos) e em todos os clientes;
- a câmera de quem está na torre sai do assento (`EYE_ABOVE_SEAT` acima), que gira com ela;
- mínimo do cano por giro (`VehicleDrive.limiteCano`), medido na malha no Studio: raio no casco
  (malha com colisão por decomposição convexa) ao longo do cano, a partir de 15% dele e outro 0,1 m
  abaixo, de 15 em 15° de giro;
  - M48: cano de 4,05 m; −7° a 165°, −4° a 180°, −7° a 195°, −6° a 210°; no resto, os −9° da ficha;
  - Ontos: −10° (da ficha) em toda a volta;
  - LVTP-5: não usado. A cúpula não tem peça de cano no modelo, e o comprimento de 1,1 m que usei na
    medida foi chute;
- o cliente (desenho) e o servidor (a pontaria e o tiro do canhão) usam o mesmo mínimo: o tiro não
  sai para dentro do próprio casco;
- motorista e atirador continuam independentes (o motorista fica no casco).

**Conferido no Studio:**
- soldas: M48 com o atirador, o comandante e o municiador na Torre; Ontos com o atirador; LVTP-5
  com o atirador da cúpula; escotilhas do comandante e do municiador (M48) e da torre (Ontos) com a
  junta na Torre;
- `AimYaw` de 90° no M48: a torre girou 90,0° no servidor. O atirador andou 1,22 m, o comandante
  1,08 m e o municiador 1,02 m com ela, e o motorista 0,00 m;
- no cliente, o comandante a 0,00 m de onde o servidor o via, com a escotilha logo acima dele.

**Não testado e limites:**
- sentado como atirador (o papel de tripulante no Studio), a câmera girando com a torre e o tiro
  rente ao convés;
- o giro do Ontos: a fonte (wiki:M50_Ontos) só dá "cerca de 40 graus" de giro num protótipo, sem
  dizer se é o total ou para cada lado; ficou livre, como antes;
- o cano passando por cima da cabeça do motorista do M48 (fora do pedido; seguiu como antes);
- a escotilha da torre do Ontos (0,44 m) é mais estreita que os ombros do soldado (0,53 m,
  relatório do Blender): a malha não mudou.
## D-197 — Lote 81: a destruição dos veículos em ordem, com explosão do tamanho e destroço queimando (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 16): uma sequência coerente de dano, explosão e
destroço, com clarão, fogo, fumaça, poeira, poucos fragmentos e som do tamanho do veículo; a
destruição uma vez só; propulsão e armas paradas; ocupantes pelo sistema de dano, sobreviventes
soltos, ninguém preso; o destroço não aceita ninguém e some ou volta no ciclo; efeito separado do
dano, sem quebrar juntas em volta; integrado ao reinício da partida.

**O que já havia:** a destruição uma vez só (atributo `Destroyed`), as armas paradas, o destroço que
some aos 30 s e o veículo que volta ao depósito (180 s, e na partida nova, D-193). O dano das
explosões é o do `ExplosionService`, sem o `Explosion` do Roblox (não quebra juntas).

**Achado e corrigido:**
- a propulsão seguia ligada: o destroço podia seguir andando com a velocidade pedida;
- todos os ocupantes levavam 3000 J no tronco. Na regra médica isso só derruba, e o caído ficava
  sentado no destroço até ele sumir;
- os assentos nunca eram desligados: `Seat` também é `BasePart`, e o laço só os pintava. O destroço
  aceitava gente;
- a arte texturizada não escurecia: a cor da peça não pinta a SurfaceAppearance;
- a explosão usava o tipo do canhão de 90 mm, e a tela de ferido dizia "canhão de tanque";
- não havia efeito próprio: só a explosão de um projétil de 90 mm, igual para jipe e tanque, e
  nenhuma fumaça ou fogo pelo dano.

**Agora (`Shared/VeiculoDano`, testado no `tests/luau/destroco.luau`):**
- porte pela massa da ficha:
  - leve, abaixo de 3 t: jipe e Peugeot;
  - médio, até 15 t: M35, Ontos e UH-34D;
  - pesado: M48 e LVTP-5.
- A explosão de cada porte (escala, fragmentos 5/7/10, som e tom, fumaça do destroço 20/25/28 s) é
  PLACEHOLDER de efeito;
- servidor (`destroyVehicle`), nesta ordem:
  - marca `Destroyed`, integridade 0 e motor desligado;
  - desliga `DriveVelocity` e `DriveAttitude` (o helicóptero cai);
  - ocupantes: lugar fechado (casco, cabine, helicóptero) morre (cabeça, 3000 J); lugar aberto leva
    900 J no tronco, abaixo do que derruba;
  - quem ficou vivo, caído ou não, sai do lugar: o jogador é posto fora do chassi, o bot pelo
    `botLeave`;
  - a explosão do dano (`Explosive.veiculo`, o alcance do 90 mm e o nome "explosão de veículo");
  - o destroço escurece (peça e SurfaceAppearance), desliga os assentos e o painel de embarque;
- cliente (`Controllers/VeiculoDano.client`), só efeito:
  - fumaça clara do motor com integridade ≤ 60, fogo e fumaça escura com ≤ 25;
  - destruído e visto ao vivo: clarão, bola de fogo, núcleo, faíscas, fumaça preta subindo, poeira
    rasteira, os pedaços de chapa do porte (física local, somem em 4 s) e o som da explosão no
    volume e tom do porte;
  - o destroço queima e fumega, o fogo some antes, até o servidor tirá-lo. Quem chega pelo
    streaming vê só o destroço;
- gancho do Studio: `VT65DevVeh = "destruir"` destrói o veículo mais perto pelo caminho do jogo.

**Conferido no Studio** (jipe M151 criado pelo gancho, soldado no carona, lugar aberto):
- `Destroyed`, `DriveVelocity` e `DriveAttitude` desligados, motor apagado, integridade 0;
- o soldado saiu do lugar no mesmo quadro e ficou fora do jipe (2,1 m do centro). Ficou caído com
  2 de vida (na repetição, 1): os 900 J do lugar mais a explosão logo em volta. Vivo e solto, para o
  médico;
- 5 pedaços de chapa (porte leve), 7 efeitos na pasta no máximo, e o destroço com fumaça 13,7/s e
  fogo 18,3/s logo depois;
- o lugar do carona ficou desligado;
- caminhão M35: integridade 50, fumaça 6/s e sem fogo; 20, fumaça escura 10/s e fogo 18/s;
- a tela de ferido: "Ferido por estilhaços de explosão de veículo" (antes "canhão de tanque").

**Não testado:** a explosão vista e ouvida de perto (as capturas foram da tela de ferido), um tanque
e um helicóptero destruídos, a tripulação de lugar fechado morrendo, bots dentro e o jogo publicado.
## D-198 — Lote 82: as explosões grandes do ataque aéreo, e a fumaça escura que aparece (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 17): explosões das bombas e dos impactos do ataque
aéreo grandes, pesadas e convincentes:
- clarão curto, bola de fogo que evolui, poeira rente ao chão e coluna de fumaça;
- detritos controlados, som com impacto e cauda, tremor pela distância com ajuste;
- conforme a superfície e com variação entre uma e outra;
- tamanho, dano e impulso independentes, partículas, luzes e pedaços limitados, e detalhe menor de
  longe.

**O avião:** o A-4 do ataque aéreo só passa no céu (EventosVisual) e não pode ser destruído. Não há
efeito de destruição de aeronave a fazer.

**Agora:**
- `Shared/ExplosaoEfeito`: o tamanho do efeito (escala e classe) separado do raio de dano
  (`Explosive.lethalM`/`casualtyM`, sem mudança) e do empurrão dos corpos (`Explosive.impulsoM`:
  bomba 28 m e tiro naval 20 m, PLACEHOLDER; antes o empurrão ia até o raio de baixas, 70 m na
  bomba). Além do `impulsoM`, o estilhaço que matou empurra como bala (`Corpos.impulso`);
- a classe "pesada" (bomba de 250 lb e tiro naval de 5 pol.) ganha a explosão grande (`ExplosionFx`):
  - clarão: luz forte e curta (teto de 4 ao mesmo tempo) e um branco rápido na tela a menos de
    500 m (`ColorCorrectionEffect`);
  - bola de fogo em 3 a 5 lóbulos que crescem, sobem e escurecem (~15 m na bomba), com o núcleo e
    as faíscas;
  - anel de poeira (ou de água) que corre rente ao chão em 8 jatos;
  - coluna de fumaça escura que sai por até 6 s e pende com a variação, com a poeira clara junto
    (cinza-marrom embaixo, escura em cima);
  - detritos com física pela superfície (torrões, galhos e folhas, tábuas; na água, a coluna branca
    e as gotas), com teto de 40 ao mesmo tempo;
  - superfície pelo raio no ponto: água (terreno ou lâmina do arrozal), estrutura (peça que colide),
    vegetação (capim, folhagem) ou terra;
  - variação por semente: lóbulos, giro, ritmo (±15%), tamanho (±12%) e inclinação da coluna;
  - detalhe pela distância (até 150 m tudo; cai até 35% a 900 m) e pela qualidade gráfica, nunca
    abaixo de 25%; até 3 explosões grandes completas ao mesmo tempo, as outras simples;
- som (`AudioController`): nas pesadas, além do estrondo de sempre, o corpo grave e a cauda (eco),
  mais grave e longa, 0,22 s depois, pela velocidade do som e ouvida de mais longe;
- tremor da câmera em todas as explosões pela distância (`ExplosaoEfeito.tremor`), vezes o ajuste
  novo das Configurações > Acessibilidade, "Tremor das explosões" (0 a 100%, `cameraShake`).

**Achado no Studio, corrigido:** a textura `smoke_main.dds` só aparece com cor clara. Com cinza
escuro ou preto ela some (teste lado a lado: a branca e a marrom grande apareceram, a cinza-escura
não). Por isso estavam invisíveis:
- a fumaça cinza das explosões menores (D-77);
- a coluna escura da 1ª versão desta bomba;
- a fumaça escura do destroço de veículo (D-197).
A fumaça escura agora usa a `explosion01_smoke_main.dds`, que já é escura, com cor clara; o teste
cobra que a `smoke_main` nunca leve cor escura.

**Conferido no Studio** (efeito disparado pelo `Fire_Impact`, só imagem e som, sem dano; bots
desligados; câmera presa num ponto de observação a ~70 m):
- 1ª bomba, a 70 m: 5 lóbulos, 9 pedaços, 1 luz, 11 emissores e a coluna saindo até +3,5 s;
- pior quadro: 176 ms na 1ª bomba da sessão. Na 2ª, 24 ms; sem explosão, 27 ms (média 17 ms). O pico
  é só da primeira vez;
- versões:
  - na mata fechada a copa escondeu as partículas;
  - no aberto, a 1ª versão mostrou só o fogo (a textura acima);
  - a 2ª saiu um borrão preto;
  - a final mostra a bola de fogo grande, o anel de poeira e a coluna cinza-marrom com o alto
    escuro (`testes/lote82`);
- o destroço do jipe (D-197) com a fumaça escura nova, 7/s logo depois.

**Não testado:** a explosão na água e numa estrutura (só a regra no Lune), o som ouvido, várias
bombas do ataque aéreo de verdade em sequência (só disparos soltos), celular e jogo publicado.

## D-199 — Lote 83: o UH-34D refeito na silhueta do desenho, e o rotor girando de verdade (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 18): melhorar o helicóptero sem trocar de aeronave:
- silhueta e proporções; cabine, vidros, portas e bancos; o interior que aparece;
- trem de pouso, rotor principal e de cauda, pintura, desgaste e detalhe de superfície;
- o rotor convincente em cada rotação e distância;
- colisão simples, ocupantes visíveis, câmera compatível, o voo igual e sem perda grande de
  desempenho.

**Silhueta medida, não desenhada a olho.** O contorno do UH-34D (perfil, planta e frente) foi lido
por código, coluna a coluna, no desenho de três vistas do the-blueprints.com, na escala do
comprimento da fuselagem (14,25 m: 0,0559 m por pixel). O v2 estava longe do H-34:
- cabine dos pilotos baixa: o teto do v2 ficava a 3,54 m, e no desenho fica a 3,86 m, acima do teto
  do porão;
- mastro alto: o topo do cubo ficava a 4,85 m; no desenho, 4,53 m. A Wikipedia dá 4,36 m de altura
  e flugzeuginfo/Sikorsky, 4,85 m;
- cone de cauda raso: no desenho ele é fundo e estreito (1,6 m de altura atrás do porão) e sobe numa
  deriva inclinada;
- trem principal: a roda vai em x = 5,03 m (Ø 0,76 m), e o amortecedor sobe até o nariz;
- bequilha: no desenho fica bem atrás, em x = −3,92 m (no v2, −1,65 m). Entre-eixos de 8,95 m;
- rotor de cauda a 3,83 m de altura e 0,55 m à esquerda.

**Agora (UH-34D v3, `tools/blender/veic_uh34d.py`; 13.648 triângulos, 3 atlas de 1024):**
- casco em 48 lados com a parte de cima mais estreita (cabine e carenagem), cortado reto nas janelas
  e nas portas;
- vidro do para-brisa num nó próprio, "Vidro": o `AssetLoader` deixa transparente (0,55), nos dois
  lados, sem sombra e sem barrar raio (bala e câmera passam). As janelas de correr dos pilotos ficam
  abertas, com o vidro corrido para trás por fora;
- molduras nas janelas e portas, a coluna do meio e a porta de correr aberta. A porta é a própria
  chapa do casco, 1,3 m para trás, com a janelinha e os trilhos;
- interior num nó próprio, "Interior":
  - cabine: painel com 16 mostradores, capô, console do eixo entre os pilotos, comandos, pedais,
    bancos com blindagem e o fosso dos pedais;
  - porão: bancos de lona com tubos, cavernas, argolas no piso, extintor, caixa de primeiros socorros
    e a M60 da porta com caixa, coronha, cano, bipé, cunhete e fita;
- nariz com a grade de ar das portas em concha, escapamentos, venezianas, degraus, alça, antena,
  farol anticolisão e luzes de posição;
- cubo articulado: braços, dobradiças, punhos, amortecedores, chifres, hastes e o prato cíclico;
- pás com o perfil NACA 0012 (fonte: Army Aviation e Sikorsky Archives), queda na ponta e a faixa
  laranja-amarela nos 6 pol. de fora. A cor da faixa vem de um resumo de busca; a página não abriu.
  Corda de 0,41 m: PLACEHOLDER;
- rotor de cauda com 4 pás de perfil e a caixa na deriva; estabilizador à direita;
- pneus com banda de rodagem e parafusos; trem com amortecedor, V e freio;
- pintura com linhas de painel e rebites, fuligem do escapamento, poeira, lascas;
- marcas coladas na pele: MARINES, insígnia nacional com a faixa vermelha, YN, 150570 e o 19.
  As posições de MARINES e da insígnia são PLACEHOLDER.

**A cabine 0,22 m mais alta que o desenho (teto a 4,08 m).** O soldado R15 sentado do jogo tem, do
centro do assento (Studio): cabeça 1,33 m e capacete 1,59 m acima, quadril 0,30 m acima, pés 0,19 m
abaixo. Assento-capacete passa de 1,6 m; na altura do desenho só havia 1,31 m do piso ao teto. No v2,
a cabeça do piloto já atravessava o teto. Agora:
- olho do piloto a 3,57 m (a câmera);
- assento com `ART.seatDrop` (0,46 m a mais de descida, só o corpo; a câmera fica no olho);
- fosso dos pedais a 2,08 m.
Medido no Studio, do chão das rodas: quadril 2,60 m (estofado 2,58), pés 2,11 m (fosso 2,08) e
capacete 3,89 m, sob o teto de 4,04 m acima da cabeça.

**Rotor (`Shared/RotorVisual`, `Controllers/RotorDisco`):**
- de 0 a 30% da rotação, as pás da malha giram inteiras;
- de 30% a 70%, somem (`LocalTransparencyModifier`, só neste cliente). A 220 rpm uma pá passaria 22°
  por quadro a 60 fps;
- entra o disco borrado: decal em `Images.rotor_borrao`, `tools/rotor_borrao.py`:
  - 4 rastros gaussianos, mais fortes perto do cubo;
  - o anel fraco da ponta e um véu leve;
  - simétrico, então serve visto de cima e de baixo;
- o disco gira devagar (0,55 volta/s na rotação cheia) e inclina como antes. De 80 m a 700 m ele cai
  até 45% da força;
- sem a imagem, fica o disco cinza de antes;
- antes, o rotor só girava a até 220 m da câmera e longe as pás ficavam paradas. Agora gira e mostra
  o disco até 1,5 km, o alcance do som do rotor;
- o helicóptero do evento (inserção e medevac) usa o mesmo disco. As pás invisíveis nem são movidas.

**Colisão e voo:**
- a arte continua sem colisão. Os colisores do D-184 saem das rodas da arte: as três bolas foram
  junto, e o corpo vai até a bequilha nova;
- no Studio, as três rodas tocaram o chão (−1 cm) nos dois helicópteros, nivelados;
- decolagem com Espaço: subiu 28 m a 10,5 m/s, nivelado (D-61: ~10,7 m/s).

**Desempenho** (Studio, mesma vista a ~27 m, qualidade 10; um v2 e um v3 parados lado a lado):

| Cena | Chamadas de desenho | Triângulos | Sombras |
|---|---|---|---|
| sem nenhum | 115,6 | 193,9 mil | 41 |
| só o v2 | +11,7 | +4,8 mil | +24 |
| só o v3 | +12,3 | +13,7 mil | +6 |

O disco borrado soma 2 peças com decal por rotor.

**Studio:** `VT65DevRotor` (cliente) fixa a rotação vista dos helicópteros.

**Não testado:**
- pouso em encosta com o corpo de colisão até a bequilha nova;
- um segundo jogador vendo o piloto: aqui só um cliente, com o corpo forçado visível;
- a tropa embarcando e as câmeras dos passageiros e do atirador;
- celular e jogo publicado.

## D-200 — Lote 84: o RPG-2 do VC integrado de verdade (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, item 19): um lançador antiveículo para o VC, com o RPG-2
(B40) como referência de 1965, integrado como as outras armas:
- loadout, inventário e roda; imagem e informação na tela;
- animações de equipar, mirar, disparar e recarregar; sons e efeitos;
- munição e reposição; dano contra veículos; controles de computador, controle e celular;
- trajetória e colisão confiáveis, explosão no impacto;
- o servidor valida o uso, a munição, a cadência e o resultado;
- números de equilíbrio definidos e uma apresentação que distinga o lançador das armas comuns.

**Antes:** o antitanque do VC já levava um "RPG-2" na vaga do lançador, mas de forma simples:
- o foguete saía pelo `Vehicle_Fire` com 6 s entre tiros;
- não havia tubo carregado, recarga, alça, projétil visível nem cartão na tela;
- o som era o do canhão sem recuo de 106 mm.

**Agora (`Shared/Lancador`, `Modules/LancadorService`, `Controllers/LancadorFx`):**
- **Munição:** "Rockets" é o total, contando o do tubo; "RocketLoaded" diz se o tubo está carregado.
  - Nasce com 3 (1 no tubo e 2 na bolsa).
  - A caixa de munição do Suporte repõe o total, como antes.
  - Só atira carregado; a recarga põe uma granada da bolsa no tubo.
- **Servidor:** confere tudo no tiro (`Lancador_Acao`):
  - vivo, a pé, papel antitanque e o lançador na mão (atributo novo `ArmaMao`, do `ArmaNaMao`);
  - tubo carregado, intervalo mínimo e direção válida.
  - A alça e a dispersão saem do servidor, não do cliente.
  - O voo é simulado a cada Heartbeat, com gravidade.
  - No veículo, a penetração e o dano de antes (`VehicleService.projectileHit`); em tudo, a explosão
    do PG-2. O abate fica com quem atirou.
  - Antes de 5 m a espoleta não arma: o projétil falha e não explode (muro colado na cara também).
- **Recarga:** 6 s no servidor ("RocketReloadUntil"). Só completa com o lançador ainda na mão; trocar
  de arma ou pedir "cancelar" para tudo.
- **Alça:** 50, 100 e 150 m, como a do RPG-2. Sem ela, a 84 m/s o PG-2 cai ~7 m em 100 m. A ponta do
  centro da tela é onde ele cai na distância da alça; muda com as teclas de alça.
- **Cliente:**
  - gatilho atira, ou recarrega com o tubo vazio; R recarrega;
  - a troca de arma cancela a recarga;
  - mirar leva a alça do RPG-2 ao olho;
  - o tranco no disparo vai para a arma e a câmera;
  - celular e controle usam as mesmas ações (gatilho, mira, recarga).
- **Animação de 1ª pessoa:** na recarga, o tubo desce do ombro e a boca sobe à frente (~0,55 m do
  olho). A mão esquerda vai à bolsa, traz a granada PG-2 e a enfia pela haste.
- **Animação de 3ª pessoa:** todos veem o tubo ficar de pé à frente do corpo enquanto ele recarrega.
- **Visto por todos (`LancadorFx`):**
  - clarão na boca e a nuvem cinza-clara de pólvora em volta do atirador (o PG-2 sai por carga de
    pólvora, sem motor);
  - o sopro para trás, que levanta poeira do chão;
  - a granada PG-2 voando (ogiva, haste e aletas), com um rastro fino e o som do voo;
  - no fim, a explosão do PG-2, ou o baque e a poeira da falha. No máximo 12 projéteis ao mesmo
    tempo.
- **Tela:** o cartão da arma mostra "RPG-2 · TIRO ÚNICO · Alça 100 m", o tubo (1 ou 0, vermelho
  vazio), "PG-2 no tubo", "tubo vazio" ou "recarregando", e a reserva. Na roda, a ferramenta do
  antitanque mostra "tubo+reserva".
- **Sons próprios** (`tools/sons_rpg.py`, síntese):
  - o disparo: estampido, baque grave do tubo aberto, sopro da pólvora e cauda;
  - o voo, em laço: vento nas aletas;
  - a recarga: pano da bolsa, raspão e a trava.
  - Também a legenda "Disparo de lançador antitanque".

**Números de equilíbrio (Shared/Lancador):**

| Item | RPG-2 | Fonte |
|---|---|---|
| velocidade | 84 m/s | wiki:RPG-2; DTIC AD0783955 |
| alça | 50/100/150 m | wiki (eficaz 100–150 m, máximo 200 m); russianwarrior (alça até 150 m) |
| recarga | 6 s | equilíbrio: 4 a 6 tiros por minuto com a mira (Small Arms Survey) |
| granadas | 3 (1 + 2) | PLACEHOLDER (como antes) |
| espoleta arma em | 5 m | PLACEHOLDER |
| dispersão | 0,4° (desvio-padrão) | PLACEHOLDER |
| penetração | 150 mm | `Vehicles.PEN.pg2` (wiki; weaponsystems.net) |
| contra infantaria | letal 2 m, baixas 8 m | `Explosive.pg2` (PLACEHOLDER, como antes) |

O PG-2 fura o Ontos, o LVTP-5 e o lado do M48, mas não a frente do M48 (110 mm a 60°). A bazuca M20
dos EUA usa o mesmo caminho com a ficha dela (sem arte de 1ª pessoa).

**Studio:** `VT65DevRajada` (cliente) agora aperta o gatilho com o lançador na mão e escreve
`[VT65 LANÇADOR] granadas a -> b, tubo, alça`.

**Conferido no Studio** (VC antitanque em campo, Ontos posto a 14 m):
- 1º tiro: granadas 3 → 2, tubo vazio, Ontos de 100 para 16,7 de integridade; o 2º o destruiu;
- tiro com o tubo vazio recusado (granadas continuaram 2);
- recarga de 6 s e o tubo carregado depois;
- troca para a pistola no meio: a recarga parou e o tubo ficou vazio;
- tiro aos pés (menos de 5 m): falhou, sem explosão, vida igual (112);
- o gatilho pelo caminho do cliente atirou e, vazio, recarregou;
- mirando, a alça e a massa no centro da tela;
- na recarga, a boca a −0,05/−0,09/−0,55 m do olho, como calculado;
- o tubo de pé em 3ª pessoa; a nuvem, o rastro e o cartão na tela.

**Não testado:**
- outro jogador vendo o tiro e a recarga (só um cliente);
- celular e controle de verdade;
- a bazuca dos EUA;
- os sons ouvidos;
- a granada da recarga depois do último ajuste de tamanho;
- o jogo publicado.

**Limite conhecido:** a arte do RPG-2 (ForgeGUI) é uma malha só, com a ogiva sempre na boca: vazio ou
recarregando, ela continua aparecendo. Para tirar, é preciso um RPG-2 do Blender com a ogiva em peça
própria.
## D-201 — Lote 85: objetivos mais centrais, centro mais baixo e mais relevo fora (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, §20): aproximar os cinco objetivos do centro levando o
conjunto inteiro (área de captura, construções, cobertura, acessos e pontos), sem juntar tudo num
ponto; rebaixar o centro numa depressão suave e legível, com saídas e cobertura e sem ficar exposto
aos altos; mais relevo fora do centro, sem um ponto alto que domine todos os objetivos; revisar
estradas, pontes, água, vegetação e construções; atualizar marcadores, zonas, carta e spawns; medir os
tempos de chegada com a velocidade nova e conferir as rotas dos veículos. O mapa continua de 700 x
700 m, com as bases no meio das bordas oeste e leste.

**Revê a D-128/D-140** ("um objetivo em cada canto, longe das bases") e o "morro do centro" da vila
(D-95, D-114): o pedido novo manda o contrário nos dois.

**Objetivos** (`tools/crop_world.py`, `PONTOS_FORTES`; metros a leste/norte do centro do mapa):

| Objetivo | Era | Agora | Do centro | Do QG mais perto |
|---|---|---|---|---|
| A Arrozais | (−275, −295) | (−205, −165) | 403 → 263 m | 296 → 190 m |
| B Serraria | (−130, +240) | (−125, +165) | 273 → 207 m | 294 → 240 m |
| C Xóm Gò | praça (−13, +15) | praça (−13, +30) | — | — |
| D Ponte e Cais | (+100, −285) | (+80, −165) | 302 → 183 m | 348 → 275 m |
| E Engenho | (+215, +303) | (+195, +165) | 372 → 255 m | 315 → 196 m |

- Entre objetivos vizinhos na ordem dos setores: A→B 554 → 340 m, B→C 254 → 176 m, C→D 320 → 216
  m, D→E 599 → 350 m. Os quatro continuam nos quatro quadrantes, com mata e lavoura entre eles.
- **Setores:** S1/S2 em x = −165 m (era −230); S2/S3 em −80; S3/S4 com um degrau, +40 m ao sul de N
  1692,83 (a Ponte e Cais) e +90 m ao norte (a vila inteira no C); S4/S5 em +150 (era +170: o portão da
  base dos EUA fica a 106 m do setor que o VC pode tomar, eram 86). Cada objetivo a 40 m ou mais da
  sua fronteira. A carta e o `Carta.boundary` já tratavam fronteira em degrau; o teste do `modo` passou
  a pedir trechos retos que somam a altura do mapa.
- **O conjunto vem junto:**
  - as construções, as árvores, a clareira, a lavoura e os pontos de reunião saem da posição do mastro
    (ArtPlan, Landscape, Vegetation, SpawnRules); o plano pôs as 8/9/13/8 peças de A/B/D/E, como na
    D-172;
  - **Arrozais:** os 16 tabuleiros, 67 diques e 9 sebes a até 115 m do lugar antigo foram com o chão
    deles (cópia por células inteiras, +71,7 m a leste e +129,9 m ao norte, o chão 3,86 m acima).
    No lugar novo saíram 1 lâmina, 6 diques e 15 sebes que ficavam por baixo. Os 44 tabuleiros que
    ficaram têm o mesmo desnível de antes (0 acima de 0,8 m);
  - **Ponte e Cais:** o rio foi junto (abaixo).

**Rio do sul** (`RIO_PONTOS`): entra pela borda oeste ao sul dos tabuleiros, corre para leste, passa
~30 m ao sul da Ponte e Cais, vira para o sul a oeste de An Cường (2) e sai pela borda sul; fora da área
vai até o riacho. 641 células de leito, 368 dentro da área (eram 489 e 233).
- O rio antigo foi desfeito (`desfaz_rio_antigo`): voltam ao chão da v70 (Git, 6c0b188) só as células
  que o `abre_rio` antigo gravou (489 de leito e 1.249 de margem, e 486 de classe). A v70 não serve
  inteira: a v71 refez o relevo perto dos tabuleiros (D-141). A diferença v71−v70 das vizinhas entra
  também nessas células (sem ela ficavam degraus de até 5 m).
- A margem nova não rebaixa a até 12 m das bocas de túnel e da trincheira nem a até 15 m de casa; fora
  da área, a beira junto da água sobe até 0,9 m acima do espelho (o chão a sudeste é baixo). Margem mais
  baixa junto da água: 10,5 m (espelho 9,6 m).
- A faixa ao sul do rio virou caminho de flanco: a volta sul das estradas cruza o rio em dois vaus
  aterrados (o leito de estrada com bueiro da Site) e a ponte da Ponte e Cais.

**Centro mais baixo** (`centraliza`, gravado no Grid como `centerLowered`):
- O "chão de fora" (alturas a mais de 215 m do centro, alisadas em 70 m) passa por cima do centro, e o
  centro fica 5 m abaixo dele até 50 m, subindo até 185 m; o terreno antigo dá lugar a isso até 155 m
  e volta inteiro em 245 m. Fica 30% do relevo miúdo antigo.
- O morro de 35,7 m da vila sumiu: o centro baixou 20,6 m. No jogo (teste `run`): fundo 14,3 m (0–40
  m da praça) contra 19,4 m no anel de 130–200 m. No Studio: praça 14,1 m, e 21,9 m 200 m ao norte.
- A vila foi replanejada no chão novo (35 casas) e as estradas também (principal 1.102 m, secundária
  1.895 m).
- **Não fica exposto:** de 8 pontos a 200 m da praça, com o olho a 1,6 m, só 0 a 14 de 121 pontos da
  vila ficam à vista (média de 3%; raios contra o terreno e as peças, no Studio). O capim alto, o
  bambu, as casas e a curva do chão tapam o resto. Saídas: a principal corta a baixada de sudoeste a
  nordeste e há estradas para a Ponte e Cais e para a base dos EUA; o sul abre para o vale do rio.

**Mais relevo fora do centro** (com peso 0 no que tem altura própria, como no lote 26: tabuleiros,
diques e sebes da lavoura, casas, riacho, túneis e bases):
- 5 morros de 5 a 7 m atrás dos objetivos (vistos do centro), a 270–415 m da praça; 2 lombadas de 4 m
  entre as bases e o centro (~150 m); 2 taludes de 2,5–3 m (norte e sudoeste); relevo aleatório de ±6 m
  a mais de 200–280 m do centro (outra semente; o do lote 26 continua).
- Vale do rio: o chão acima de 10,5 m + 10% da distância ao eixo desce até ele (até 140 m).
- Na área: desnível de 8,9–35,7 m para 7,2–29,7 m; rampa p95 26,5% (era ~26%), máxima 58,6%. O ponto
  mais alto (29,6 m) fica no setor A, a 209 m da praça.
- **Nenhum alto domina:** dos 4% mais altos da área, com só o chão, ninguém vê mais que 3 objetivos até
  300 m, nem mais que 4 até 400 m (na v118, 3 e 3: os cantos ficavam longe demais do morro).

**Tempos de chegada a pé** (`tools/tempos_chegada.py`: caminho mais rápido na grade, trote de 4,70
m/s da D-188, VC × 1,12, rampa, mata, tabuleiro e água do `Movement`; sem casas e árvores):

| De → para | v118 | agora |
|---|---|---|
| QG VC → A | 60 s | 40 s |
| QG VC → B | 66 s | 52 s |
| QG VC → C | 64 s | 62 s |
| QG VC → D | 108 s | 91 s |
| QG VC → E | 133 s | 113 s |
| QG EUA → A | 161 s | 130 s |
| QG EUA → B | 124 s | 113 s |
| QG EUA → C | 75 s | 72 s |
| QG EUA → D | 85 s | 67 s |
| QG EUA → E | 79 s | 51 s |

**Veículos** (teste `estradas`): M48A3, M151, M35, LVTP-5 e Ontos vão e voltam do QG dos EUA a todos os
objetivos; o M48 alcança e volta de 99,8% das células onde cabe.

**Raia de tiro:** com a vila na baixada, uma casa caiu na linha do alvo de 150 m do VC (o autoteste
parou nela). A escolha da direção (`TrainingService`) agora também recusa construção de `Map.Art` a
menos de 8 m da linha do tiro (depois dos primeiros 10 m).

**Arte fixa (SLIM, D-155):** recopiada do jogo rodando, sem nenhum conjunto ligado:
- `vila_construcoes`: 24 construções de peças (eram 19: as 4 de peças da D-172 e uma horta a mais),
  301 peças, 57.320 bytes, FNV-1a 717725730 no Studio e no arquivo;
- `vila_casas`: a vila inteira, 9 moldes e 26 instâncias (35 casas; as 3 `vila_casa_09` ficam com o
  jogo), 58.185 bytes, FNV-1a 3314851559. O conjunto `vila_casa_03_xomgo` (D-167) saiu: a casa dele
  é o molde da `vila_casa_03` agora;
- no Studio: 59 modelos no arquivo e 59 cópias do plano puladas, sem aviso.

**Carta:** refeita e reenviada (os blocos antigos ficaram como `Carta.*_v118`).

**Autoteste** (4 rodadas no Studio): a raia passou nos 6 alvos depois da correção. A granada de bot
caiu longe em 2 das 4 (12,3 e 16,0 m de um alvo a 25 m à frente de onde o bot estiver; já falhava
por sorteio, lote 12, e o relevo maior faz o chão do caminho barrar mais). A pá falhou 1 vez, depois
do teste de Offensive mudar a frente (passou nas outras). "Deitado" falhou 1 vez com a arte ainda
carregando.

**Flutuando:** `VT65DevFlutua` sem nada novo no ar nos objetivos e na vila. Ficaram 3 casos em An Cường
(cabana com um canto 1,43 m no ar, pote 0,44 m, bunker 0,25 m), onde o chão não mudou neste lote
(diferença 0,00 m): eram de antes. Os barcos da Ponte e Cais "no ar" estão na água.

**Não testado:** outro jogador; celular; o jogo publicado; o tempo de chegada andando de verdade no
jogo (medido na grade); bots numa partida inteira no mapa novo.
## D-202 — Lote 86: a comemoração dos três melhores como cena, com gestos (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, §21): ao fim da partida, uma tela ou cena com os três
melhores do time que venceu: personagens completos (aparência e equipamento), o 1º em destaque, o 2º e
o 3º ao lado, nome, colocação, pontos e estatísticas, o time vencedor, animações de comemoração
variadas, cenário coerente, empate sem inventar vencedor e a cena valendo mesmo se alguém sair.

**O que já existia** (D-193): o pódio congelado no fim pela pontuação da partida (os pontos de cada
ação da progressão, desempate por pontos, abates, menos mortes, entrada e nome), o empate com os
melhores dos dois lados, menos de três quando houver menos, e um cartão por lugar com o soldado
girando num ViewportFrame (sem animação).

**Agora:**
- **Cena** (`Controllers/CenaComemoracao`, num ViewportFrame só): três caixotes de madeira (1,4 m,
  0,9 m e 0,55 m; faixa de latão, aço e bronze), sacos de areia dos lados, caixas de munição, o mastro
  de bambu com o pano da cor do lado que venceu (dois, um de cada cor, no empate), coqueiros e mata
  ao fundo, céu de fim de tarde. Nada na frente dos soldados. A câmera balança ±6° e se aproxima
  devagar, sempre com os três no quadro.
- **Cartões** embaixo de cada soldado, numa faixa própria (antes da faixa, eles tapavam os caixotes):
  colocação e nome, pontos, abates e mortes. Seguem a câmera (`Cena.telaX`).
- **Gestos** (`Shared/Comemoracao`, módulo puro): fuzil erguido com pulinhos, punho no ar, aceno e
  braços em V. Cada lugar tem a sua sequência em laço e começa noutro ponto, e a troca de gesto mistura
  em 0,6 s. A mão direita segura a arma da partida, então os gestos de mão livre usam a esquerda.
  - Procedurais, sem asset de animação: cinemática direta sobre peças ancoradas (o ViewportFrame não
    simula).
  - As juntas do soldado são AnimationConstraint (R15 do HumanoidDescription), medido no Studio: 15
    juntas e 14 BallSocket. Cada uma volta aos anexos de rig dela, então o personagem copiado
    deitado, agachado, mirando ou caído fica de pé; acessórios e armas seguem as soldas
    (WeldConstraint da arma na mão, Weld do acessório).
  - Os pés ficam no tampo pela sola mais baixa; no pulo, sobem.
- **Aparência congelada** (`RodadaService`): no fim da partida o servidor copia o personagem de cada
  lugar do pódio para `ReplicatedStorage.VT65PodioModelos.<UserId>`. A cena usa essa cópia; sem ela,
  o personagem de agora; sem os dois (saiu sem corpo), o manequim do lado. A pasta esvazia antes da
  partida nova. A cópia do personagem local em 1ª pessoa vinha sem rosto (a cabeça escondida); a
  montagem zera esse esconderijo.

**Conferido no Studio** (um jogador; os outros lugares postos à mão com ids sem jogador, o caminho do
manequim):
- fim pelo gancho com o soldado pontuando: o servidor congelou a cópia dele e a cena a usou (o 1º com
  o fuzil erguido);
- vitória dos EUA com três, empate (um do VC em 1º, os dois panos) e pódio vazio (o palco e a frase em
  faixa escura);
- os gestos trocando entre capturas e a câmera balançando;
- o ciclo inteiro: fim 8 s → comemoração 12 s → votação 15 s → restauração 3 s → partida, sem erro no
  Output (fora os "TexturePack" do Studio local), e a cena vazia depois.

**Erros achados no Studio e corrigidos:** o laço do pano passava pela chave do topo do mastro guardada na
mesma tabela (a câmera parava em (0, 20, 20)); os cartões tapavam os caixotes; o 1º quase não se
destacava em altura; o pano saía cortado no alto; a cópia local sem rosto.

**Testes:** `comemoracao.luau` (5): juntas no limite (cotovelo e joelho só para o lado certo), maior
passo entre dois quadros a 60 fps de 10,6° (era 19° com o "soco" de expoente 0,6 e 11,7° com a mistura
de 0,45 s), os três nunca no mesmo gesto e cada um com dois ou mais em 12 s, o palco e as amarras.

**Não testado:** com três jogadores de verdade (só um no Studio), alguém saindo depois do fim (a cópia
congelada foi conferida, a saída não), o custo da cena num celular e o jogo publicado.

## D-203 — Lote 87: a partida nova sem sobra da anterior e a contagem pelo relógio do servidor (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, §22): o ciclo inteiro no mesmo servidor (fim, comemoração,
votação mesmo com um mapa, restauração, contagem, partida). A restauração devolve pontuação e
objetivos, jogadores com equipamento e munição, veículos e aeronaves, destroços e corpos, granadas e
projéteis, buracos e terreno cavado, câmera, mira, inclinação e corrida, telas e cronômetros, e mantém
a progressão. A contagem é sincronizada, com visual claro e sinal de início. Quem entra no meio vê o
estado certo. Um identificador de rodada impede que tarefa ou evento antigo afete a partida nova.

**O que já existia** (D-193): o ciclo e as fases no relógio do servidor (`VT65Fase`, `VT65FaseAte`),
a votação com o mapa real, a rodada (`MatchService.rodada`, `VT65Rodada`) e a restauração de corpos,
granadas, fumaça, armas no chão, napalm (a pasta), armadilhas, buracos da pá, crateras, veículos (com
a época que impede o reaparecimento velho) e jogadores (corpo novo no QG, o que zera mira, corrida,
inclinação e roda pelo `InputMap`). A progressão nunca é tocada. A auditoria deste lote achou o que
ainda passava de uma partida para a outra.

**Agora:**
- **Tarefa presa à partida** (`Rodada.presa`, módulo puro; `MatchService.presa`): a função só roda se
  a rodada ainda é a de quando foi criada e, com `paraNoFim`, se a partida não acabou.
  - Comandante: o disparo, o aviso de chegada e o impacto de cada tiro (morteiro, naval, ataque
    aéreo) e o caixote a caminho passam por ela. Antes, uma salva pedida no fim caía nas telas do fim
    ou na partida nova.
  - Pedido depois do fim: recusado ("a partida acabou").
  - As recargas e o último alvo zeram na partida nova (`CommanderService.restaurar`).
- **Napalm:** o fogo apaga no fim da partida ou quando a restauração tira a pasta (antes queimava até
  o fim do prazo e ainda feria). O capim que vira terra é guardado antes (`ExplosionService.guardar`,
  o mesmo das crateras) e volta. A caixa de munição, que também troca o capim por terra, guarda igual.
- **Logística** (`LogisticsService.restaurar`): as construções saem (posição de morteiro, ninho, posto
  de reunião), com o reforço de túnel aberto e a posição de morteiro do lado. O suprimento volta ao do
  começo (150) e os caixotes iniciais voltam aos QGs.
- **Caixas de munição** (`CaixaMunicaoService.limpar`): saem todas (as dos bots também), e a espera de
  cada Suporte zera.
- **Bots:**
  - depois do fim ficam parados e não atiram (a rajada em curso para) nem nascem; as viaturas deles
    param;
  - na restauração, depois dos veículos, o corpo sai sem morrer (sem arma no chão nem baixa) e a
    espera zera (`BotService.restaurar`). Eles nascem na contagem da partida nova, que só deixa nascer
    no QG (PreparoService).
  - Antes, eles seguiam lutando nas telas do fim e começavam a partida nova onde a anterior acabou.
- **Contagem sincronizada:**
  - o servidor publica a hora em que a partida vale no relógio dele (`VT65InicioEm`, GetServerTimeNow),
    e cada cliente calcula o número (`Rodada.contagem`, 20 vezes por segundo);
  - antes o número vinha no `Match_State`, a cada 1 s, e cada cliente virava o número quando o
    pacote chegava;
  - quem entra no meio lê o atributo; depois do fim (`VT65Fase` fora de "jogo") não há contagem.
- **Sinal de início:** além do "VALENDO!", um toque seco em cada um dos 5 últimos segundos e um apito
  de campo (dois toques curtos e um longo) no zero. Os sons são de síntese própria
  (`tools/sons_partida.py`, numpy para OGG, como a roleta), subidos como `Sounds.contagem_tique` e
  `Sounds.partida_apito`. O apito foi conferido por código: três toques de 0–170, 250–420 e 530–1310 ms,
  pico em 2.974 Hz.

**Conferido no Studio** (um jogador, como Suporte dos EUA; três fins pelo gancho):
- **Contagem:**
  - na partida nova cada número virou 33–101 ms depois do segundo exato do relógio do servidor, e
    54–57 ms na partida depois da restauração;
  - os 5 tiques tocaram 4–50 ms antes de cada segundo inteiro: o som entra no mesmo quadro em que o
    número vira;
  - o apito tocou 4–49 ms depois do zero e o "VALENDO!" saiu em 55–99 ms;
  - a tela fechou 2,6 s depois.
- **Bots nas telas do fim:** em 16 s, o maior deslocamento entre os 59 foi de 1,6 mm, e nenhum
  morreu. Os traçadores de tiro que chegaram ao cliente foram 198 na partida e 0 nas quatro fases do
  fim.
- **Restauração**, com uma posição de morteiro, um ninho e uma caixa de munição postos antes:
  - a logística ficou só com os 4 caixotes iniciais, sem caixa de munição;
  - o suprimento voltou a 150 e a posição de morteiro do jogador sumiu;
  - perto da caixa, 19 voxels de terra voltaram a capim;
  - o registro do servidor: 6 peças da logística, 2 caixas (uma de bot), 10 trechos de terreno, 9
    veículos, 59 bots e 1 jogador.
- **Bots na partida nova:** todos nasceram no QG (nenhum a mais de 60 m até 15 s; depois andam).
  Na 2ª partida o modo sorteado foi Offensive, em que o VC completa só 20 bots: os 10 a menos são o
  modo, não a restauração.
- **Fases:** 0 / 8,0 / 20,0 / 35,2 / 38,1 s; sem erro no servidor.

**Testes:** `rodada.luau`, com 4 testes novos:
- a tarefa presa (velha não roda na nova; com `paraNoFim`, nem depois do fim);
- a contagem em segundos inteiros, que vira no segundo exato;
- as amarras no servidor: todo `task.delay` do comandante passa pela guarda, o fogo apaga, e a
  logística, as caixas e os bots voltam;
- a tela pelo relógio do servidor, com os dois sons publicados.

A ordem da restauração ganhou logística, caixas, comandante e bots.

**Não testado:**
- o tiro do comandante no Studio: o perfil local tem posto 1 e o comandante pede posto 3, então a
  guarda ficou nos testes do Lune;
- o napalm no Studio (sai do ataque aéreo do comandante);
- a contagem em dois clientes ao mesmo tempo: a sincronia vem do relógio do servidor, medida num
  cliente;
- o jogo publicado.

## D-204 — Lote 88: um kit de som próprio para cada arma, e o campo com variações (2026-11-20)

**Pedido do dono** (prompt de jogabilidade, §9): "não gosto dos sons atuais das armas". Quer:
- uma mudança perceptível de qualidade e identidade, trocando a fonte, não só o volume ou o tom;
- em cada arma, ataque, corpo, mecânica, cauda, recarga, manejo e clique seco, com variações
  discretas;
- a própria arma diferente da dos outros, o perto diferente do longe e o fechado do aberto;
- a cauda da rajada terminando natural, sem estalo, saturação ou corte;
- variações também em passos, cavadas, impactos, granadas, explosões e motores;
- tiros com presença sem esconder o resto do que importa ouvir, e o tiro previsto não tocando de
  novo quando chega a confirmação;
- avaliar AudioPlayer e AudioEmitter.

**Antes:**
- 12 armas dividiam 5 gravações de biblioteca (as do Front 44, da Pro Sound Effects), uma por
  classe, com o tom trocado por arma;
- o "corpo" era o mesmo arquivo uma oitava abaixo;
- a cauda era um efeito (eco ou reverberação) no próprio disparo, cortado com ele;
- a recarga era uma por lado (EUA ou VC) e o clique seco, um só para todas.

**A fonte:** a loja da Roblox (busca de áudio no Studio) só trouxe sons tirados de outros jogos
(CS:GO, Day of Infamy, ARMA 3, mods), que a regra do projeto proíbe. Ficou a síntese própria, como
nos veículos, no RPG-2 e na pá: `tools/sons_armas.py` (numpy; o Blender só grava o OGG).

**Kits (19 arquivos, 281 trechos, 3,4 MB; `Shared/SomKits`, gerado pelo script):**
- **Um por arma** (12):
  - p1..p4: o tiro em 1ª pessoa (mecânica no ouvido, grave forte, estalo da bala fraco, reflexo do
    chão a ~8 ms);
  - e1..e3: o tiro de outro soldado perto (sopro da boca e estalo da bala na frente, mecânica quase
    sumida, reflexo do chão a <1 ms);
  - seco; as peças da recarga do tipo da arma (carregador, pistola, fita, clipe da SKS, cartucho a
    cartucho, 40 mm); ciclo (ferrolho manual ou bomba); estojo1 e estojo2 (latão de fuzil ou de
    pistola, plástico).
  - Cada tiro tem camadas com nome: o pulso de pressão (Friedlander), o sopro dos gases com a voz
    da boca, o estrondo grave que cai de tom, o estalo supersônico (onda N), a mecânica (modos de
    aço amortecidos) e o reflexo do chão.
  - A identidade sai do calibre, do cano, do sistema de ação e do material. Exemplos: a mola do
    amortecedor da M16, o transportador pesado da Type 56, o "ping" do pistão da SKS, o ferrolho
    aberto e a fita da M60 e da RPD, o ferrolho de aço da M1911, o percussor dos fuzis de ferrolho,
    o "bum" largo da 12 e o "tum" oco do 40 mm.
- **Caudas** pelo lugar de quem ouve (3 famílias × 4 lugares × 2):
  - aberto: batidas que voltam das árvores e escurecem, até 2,2 s;
  - mata: curta e abafada;
  - fechado: reflexos cedo, clara;
  - túnel: grave, com batidas a cada ~12 ms.
- **Distância** (3 famílias × médio/longe × 3) e **balas**: estalo e zunido (3 de cada) e os
  marcadores de acerto.
- **Passos** (5 chãos × 6), **impactos** (terra, água, madeira, palha e carne × 4), **explosões**
  (granada × 3, pesada × 2, eco × 2) e **pazadas** (4).

**Medido no arquivo** (`--medir`, `assets/armas_sons/medidas.json`):
- **Centroide do espectro, 1ª pessoa:** M79 945, Winchester 12 1.480, Mosin 1.661, M70 1.710,
  M60 1.717, M14 1.828, Type 56 1.876, RPD 1.975, SKS 2.074, M16 2.360, M1911 2.392 e Type 54
  3.068 Hz.
- **3ª pessoa:** sempre mais clara (1.880 a 4.893 Hz).
- **Variações da mesma arma:** o centroide muda até 20% (a M70; a maioria ≤ 12%). A normalização
  passou a ser pela energia, não pelo pico do ruído: pelo pico, chegava a 40%.
- **Sem clipar:** pico máximo de −0,85 dBFS depois do Vorbis, as bordas de cada trecho em 0 e 60 ms
  de silêncio entre os trechos.

**No jogo:**
- **Tocar um trecho:** `Controllers/Som` toca só o trecho pedido (PlaybackRegion), 2D ou 3D. A
  variação nunca repete a última (`SomArmas.sorteia`); o tom só ganha ±1% de ajuste fino.
- **Caudas:** tocam até o fim, em vagas: 2 do próprio tiro e 4 dos outros. A que entra apaga a mais
  velha em 80 ms (Tween no volume), sem corte seco, e a última da rajada rola inteira.
- **Recarga:** peça a peça, com a âncora de cada trecho na fração da animação de 1ª pessoa (o
  carregador sai em 0,13, encaixa em 0,64, o tapa em 0,66 e a alavanca em 0,79). A troca de arma
  cala o resto.
- **Clique seco e ciclo:** o clique é o da arma (Bus "dry_fire"). O ferrolho e a bomba seguem a
  duração do ciclo; o estojo da espingarda e do ferrolho sai no ciclo, não no tiro.
- **Tiro dos outros:** perto, o "e"; médio e longe, a família; o atraso e os agudos caindo
  continuam como antes.
- **Bala, impactos, explosões e passos:** a bala e os impactos vêm dos kits. A explosão pesada não
  baixa mais o tom: toca o próprio trecho mais o eco. Os passos agora são um por passada (antes, um
  arquivo de 4 passos a cada 4 passadas), sem repetir o último de cada soldado.
- **Pazada:** é do servidor e sorteia 1 das 4.
- **Motor:** cada veículo tem um tom fixo de ±2,5% pelo id, e dois iguais não soam iguais.
- **Mixagem:**
  - os tiros, as caudas e as explosões vão num grupo próprio (`VT65Tiros`, dentro dos efeitos),
    com limitador (−6 dB, 8:1), para muitos juntos não saturarem;
  - o ambiente abaixa durante o tiroteio (compressor ligado ao grupo dos tiros, 3:1, volta em
    0,6 s);
  - os passos, a bala passando, o rádio e os avisos ficam fora e não abaixam.
- **Tiro previsto:** o próprio tiro toca só pelo Bus "shot_fired". O servidor não manda o
  traçante a quem atirou (`if other ~= exceptPlayer`), então não toca de novo.
- **AudioPlayer e AudioEmitter:** avaliados e não usados agora.
  - O motivo para a API nova seria a reverberação (AudioReverb) continuar depois de o som parar,
    mas a cauda agora é gravada e toca até o fim.
  - O resto do jogo (ambiente, veículos, grupos) é Sound e SoundGroup, e misturar exigiria ligar
    AudioListener e AudioDeviceOutput em tudo.
  - Fica para um lote de migração, se o dono quiser.

**Conferido no Studio** (um jogador, M14):
- **Kits:** os 19 carregaram no cliente (PreloadAsync: 0 falhas) com a duração igual à do
  `SomKits` (diferença 0).
- **Tiro próprio:** 8 tiros tocaram p1 p4 p2 p4 p2 p3 p2 p3, sem repetir. Cada um teve cauda e
  estojo; 16 sons no grupo dos tiros e 8 nos efeitos. Nenhum "e": o próprio tiro não voltou pela
  rede.
- **Recarga da M14:** solta 0,25, sai 0,28, cai 0,70, entra 1,28, tapa 1,40 e ferrolho 1,68 s. Cai
  na fração de uma recarga de 2,13 s (2,4 s × 0,88 da vantagem de recarga do perfil), com erro de
  até ~0,05 s.
- **Com os bots em 30 a 35 s:**
  - 76 a 341 tiros médios e 226 a 268 longes, nas 3 variações;
  - passos na grama nas 6 variações;
  - estalo da bala, impactos e granadas nas 3 variações.
- **Tiro de perto:** a câmera do MCP ficou presa no QG (Scriptable) e o ouvinte é a câmera, então os
  bots soavam longe. O tiro de perto foi disparado pelo próprio remote do servidor (Combat_Tracer
  com a origem a 10–30 m). Tocaram e1/e2/e3, as caudas por família (fuzil, pistola, pesado), o
  ciclo da 12 e do Mosin, o estalo da bala a 3 m e os impactos.
- **Vagas:** numa rajada de 14 tiros de RPD a 10 m, o máximo de caudas juntas foi 5 (4 + 1
  apagando), e não 14.
- **Pazadas:** 6 em 4 trechos diferentes (0,00/1,46/2,92/4,38 s), sem repetir a anterior.
- **Erros:** 0, fora os dos meus próprios comandos de teste.

**Testes:**
- `sons.luau` (6): todo kit publicado e com os seus trechos; trechos sem sobreposição; variação
  sem repetir; a recarga na fração da animação; as amarras.
- `test_sons_armas.py` (6): nada clipa, bordas em zero, a ordem dos calibres, a 3ª pessoa mais
  clara e as variações próximas.
- Atualizados: `combate`, `classes` e `explosao`.

**Se o dono quiser gravações de verdade depois**, os pontos de troca são os trechos de cada kit (um
arquivo por kit, os mesmos nomes; `Shared/SomKits` diz onde cada um começa).

**Não testado:**
- **De ouvido:** ninguém ouviu os sons; só foram medidos (espectro, nível, bordas, tempos).
- Dois jogadores, o celular e o jogo publicado.
- **Clique seco no Studio:** a M14 trava o ferrolho e recarrega no vazio.
- A recarga das outras armas no Studio (só a M14; as outras têm o tempo conferido no Lune).

## D-205 — Lote 90: a fundação da interface (cores por função, estados, preferências, confirmação, abas e foco) (2026-11-20)

**Pedido do dono** (prompt de interface, o 1º lote dele): antes de refazer cada tela, uma base comum.
- §3: âmbar para foco, seleção e ação importante; oliva, papel, lona e metal de apoio; estados de
  componente (normal, foco, pressionado, selecionado, desabilitado, carregando, erro) e de item
  (adquirido, equipado, bloqueado, indisponível para a classe), nunca só pela cor.
- §4: transições curtas, de 0,15 a 0,30 s.
- §18: componentes compartilhados, entre eles abas e modais; confirmação clara para descartar
  alterações, com confirmar e voltar e foco previsível.
- §19: foco inicial definido, foco devolvido ao fechar um modal, LB/RB nas abas.
- §20: seguir as preferências do jogador (movimento reduzido, tamanho do texto) e contraste.
- §21: nada de conexão sobrando.

**Cores por função (`Estilo.V`):**
- `AMBAR` (226, 166, 46) é o fundo da ação principal, com `AMBAR_TEXTO` (24, 20, 10) por cima;
  `AMBAR_HI` com o foco; `FOCO` (255, 206, 64) é a moldura do foco; `PAPEL`, `LONA` e `METAL` de
  apoio. O oliva deixou de ser a cor da ação principal.
- Contraste medido no Lune (WCAG 2): texto do botão principal 8,5:1, texto no painel 14,7:1, texto
  secundário 6,4:1; a moldura do foco passa de 3:1 contra os três tons de painel.
- Mudaram: o botão principal do kit (`Estilo.button`, `UiKit.action`), o JOGAR do menu principal e
  o CONTINUAR da tela de entrada.

**Estados (`Estilo.ESTADO`):** cada um tem cor, símbolo, palavra e o rótulo pronto para a tradução
("✓ EQUIPADO", "🔒 BLOQUEADO", "× OUTRA CLASSE", "● SELECIONADO", "… CARREGANDO", "! ERRO",
"✓ SEU").
- `Estilo.estadoTag` desenha a etiqueta, sempre no Arimo Bold. No Studio o "✕" saiu como um
  quadrado (o Arimo não tem) e o Oswald desenhava o "×" como um ponto. Ficou o "×".
- `Estilo.cardEstado(cartão, estado)` põe a etiqueta no canto do cartão de item, apaga o nome do
  item bloqueado ou de outra classe e encolhe o nome para a etiqueta. No Studio, "NÃO NESTA CLASSE"
  cobria o nome; virou "OUTRA CLASSE" e o nome encolhe.
- Botão (`UiKit.action`): afunda para 0,97 enquanto apertado; `carregando(true)` trava o clique e
  mostra "…" (sem pedido duplicado, §9); `erro(msg)` pinta a borda de vermelho e escreve o motivo
  por 2,5 s. A conexão de troca de dispositivo sai com o botão (antes, uma sobrava a cada tela
  recriada).

**Preferências do jogador:**
- Do Roblox (`GuiService`), com sinal de mudança, conferidas no Studio:
  - `ReducedMotionEnabled`: o que desliza ou cresce troca direto (`UiKit.tween`, `Estilo.enter`, a
    moldura de foco sem respirar);
  - `PreferredTransparency` (0 a 1): multiplica a transparência dos painéis e botões translúcidos
    (`Estilo.fundo`);
  - `PreferredTextSize`: o texto cresce 1, 1,15, 1,3 ou 1,45 (`Estilo.TEXTO_K`, pelo `Estilo.ts` e
    pelo `UiKit.text`).
- Do jogo: Configurações › Acessib. › "Reduzir movimento da interface" (`uiReduceMotion`, começa
  desligada). Liga o mesmo caminho pelo atributo local `VT65ReduzMovimento`.
- Com movimento reduzido também param: o pulso do JOGAR, o pulso e o salto da diária (e as moedas
  voando), o travelling da câmera do lobby (corta), o halo do "você" na carta e o giro da cena de
  baixa.
- Tempos: `QUICK` 0,15 s (era 0,14, abaixo da faixa) e `SOFT` 0,30 s; o UiKit usa os do Estilo.

**Confirmação (`UiKit.modal`):** título, texto, VOLTAR e CONFIRMAR (vermelho quando `perigo`).
- Fica por cima das telas (DisplayOrder 95); o véu escuro não deixa clicar atrás.
- O foco do controle abre em VOLTAR e não sai da janela (`SelectionGroup` com as 4 direções
  paradas). B ou Backspace voltam. Responde uma vez só.
- O cursor virtual subiu para 99, senão ficaria por baixo da janela.
- Ligada no menu do jogo: os 5 "Restaurar ... padrão" de cada aba (teclas, gráficos, toque, som,
  botões), o "Restaurar padrões" de tudo e o "Sair do squad". Com ela aberta, LB/RB, LT/RT e o direcional não mexem no menu de baixo (`busy()` olha a
  tela de cima).

**Abas (`UiKit.abas`):** a fileira com LB/RB (ou Q/E) nas pontas, que trocam conforme o
dispositivo e somem no toque; a ativa em texto claro com o traço âmbar embaixo.
- Clique, toque, LB/RB e Q/E trocam a aba; LB/RB só valem para as abas da tela de cima e à vista.
- Um registro só no módulo (as ações do `Input` não se desligam); a fileira sai dele ao ser
  destruída.
- As telas existentes (menu do jogo, loja) ainda têm as abas delas; passam para esta nos lotes de
  cada tela.

**Foco:**
- A pilha de telas (`UiKit.opened`/`closed`) guarda o foco de antes de cada tela e o devolve ao
  fechar, se ele ainda estiver à vista (só no controle).
- `UiKit.principal(botão)` marca a ação principal, e o `UiKit.focus` começa nela. A diária abre no
  RESGATAR e a confirmação no VOLTAR.
- O vigia de foco (`UiKit.watch`) não puxa mais o foco de uma tela que está por cima (DisplayOrder
  maior).

**Conferido no Studio** (um jogador, mouse; gancho `VT65DevTela` = `"componentes"`, `"confirma"` e
`"aba:±1"`):
- CONTINUAR e JOGAR em âmbar com o texto escuro.
- Os 7 estados no cartão, sem a etiqueta cobrir o nome, todos no Arimo.
- Os 6 tipos e estados de botão (principal, secundário, perigo, apagado, carregando, com erro).
- **Abas:** pelo clique e pelo mesmo caminho do LB/RB, nos dois sentidos, com a volta ao início.
- **Confirmação:**
  - VOLTAR respondeu "voltou" e CONFIRMAR "confirmou", e a janela fechou;
  - com ela aberta, nem o LB/RB nem o clique na aba de trás mudaram a aba;
  - depois de fechar, as sub-abas do menu voltaram a responder.
- **Do menu real:** Som › "Restaurar o som padrão" abriu a confirmação, e VOLTAR não mudou nada.
- **Movimento reduzido:** a janela abriu em escala 1,000 já no 2º quadro; sem a opção, 0,971 no 2º
  quadro e 1,000 em 0,5 s.
- **Texto "Largest":** a aba foi de 17 para 25 px.
- **A opção "Reduzir movimento"** do menu ligou o atributo do jogador.
- **Preferências do Roblox no Studio:** `ReducedMotionEnabled` false, `PreferredTransparency` 1 e
  `PreferredTextSize` Medium (as três leem sem erro).
- **Erros:** 0, fora os "TexturePack 429" do Studio.

**Testes:** `componentes.luau` (11): contraste calculado das cores do código; estados com símbolo e
palavra; as três preferências e a escala do texto; tempos do §4; movimento reduzido nas telas;
âmbar; estados do botão; a confirmação (foco, pilha, ordem acima de todas as telas de menu, cursor
acima dela); os resets do menu; as abas no LB/RB e Q/E; o foco na ação principal.

**Não testado:**
- **Controle de verdade:** o MCP não manda controle. O foco devolvido, o foco em VOLTAR e o B
  fechando ficaram só no código e no Lune.
- A preferência real de movimento e de texto do Roblox ligada no aparelho (só os ganchos
  `VT65DevMovimento` e `VT65DevTexto`).
- A transparência `VT65DevTransparencia` 0, só olhada, sem número.
- O corte da câmera do lobby com movimento reduzido.
- O celular e o jogo publicado.

## D-206 — Lote 91: o lobby na composição das referências, com o próprio soldado num acampamento (2026-11-20)

**Pedido do dono:** "quero q vc se baseie nas imagens para criar o lobbys a loja o passe quero q
vc faça com imagens bem feitas transições de qualidade como se fosse um jogo sensacional de alta
qualidade visual". As imagens são as que vieram com o prompt de interface:
- 9 no chat de 20/11 e 11 nos dois .zip do WhatsApp;
- as de lobby, loja, passe, placar e personalização são de um jogo de luta do Roblox;
- as de HUD e mapa são de um jogo de guerra do Roblox.

O texto do prompt (§6) diz o que vale delas: "Inspire-se na composição das referências, com
soldado equipado em destaque e navegação organizada". Ficam a composição e a qualidade. Saem os
nomes, textos, ícones, cores e a moeda delas: a identidade é a deste jogo (1965, âmbar e oliva, as
capas do dono). Este lote é o lobby; a loja e o passe vêm nos próximos, sobre o mesmo palco.

**A composição (§6), numa grade dentro da área segura:**
- **Esquerda, no escuro:**
  - a marca;
  - o cartão grande do JOGAR (a ação mais evidente), com imagem, o botão âmbar, a linha de
    descrição e o modo com os jogadores no servidor;
  - a navegação em letras grandes: ARSENAL, MISSÕES, PERFIL, COMO JOGAR;
  - depois LOJA, PASSE DE CAMPANHA (com o nível) e CONFIGURAÇÕES.
- **Centro:** o soldado do próprio jogador, de pé, na luz.
- **Direita:**
  - o passe: temporada, fim, nível, estrelas e o estado do Veterano;
  - as 3 ordens do dia, com progresso e prêmio;
  - a recompensa diária: o dia e os 7 selos;
  - um destaque em posição secundária: a loja e o passe, trocando a cada 7 s.
- **Rodapé:** os comandos do aparelho à esquerda; à direita, saldo, posto, jogadores no servidor,
  o jogador e a barra de XP do posto.
- Os números são todos do jogo (CampanhaCliente, Daily_Get, atributos do jogador). Sem o estado,
  aparece "carregando…", nunca uma conta vazia.

**O soldado do próprio jogador (PreviewService.pessoal):** o prompt pede "o próprio avatar do
jogador com seu uniforme, arma e equipamentos". Antes, o menu mostrava manequins iguais para todos.
- Agora o servidor monta um soldado por jogador como no spawn:
  - Characters.describe/dress com os cosméticos equipados do lado;
  - as skins de uniforme e camuflagem desse lado, gravadas no próprio modelo (no lobby o jogador
    ainda não tem lado);
  - o rosto pelo UserId e a arma principal do último papel.
- O `Characters` aceita o atributo "Dono" no modelo para o rosto, o papel e as skins.
- Vai para a PlayerGui.VT65MeuSoldado: só o dono recebe.
- É refeito, no máximo uma vez a cada 1,5 s, quando o jogador:
  - equipa um cosmético (Commerce_Equip);
  - troca uma skin;
  - troca de lado ou de papel (atributos UltimaEscolha, Faction e Role).
- Sem ele ainda, aparece o manequim do lado.
- **Medido no Studio:**
  - o soldado chegou (EUA, M14, 34 peças);
  - ao escolher o VC na mesa, virou VC com a SKS em 2,0 s;
  - a pasta continuou na PlayerGui depois de nascer em campo.

**O palco (Controllers/LobbyPalco):** o acampamento de 1965 ao fim da tarde, montado no cliente,
no alto e fora do mapa, e só no Workspace com o menu aberto.
- **EUA:**
  - a barraca de comando com lampião e a barraca de lona;
  - caixas de munição empilhadas e um rádio de campanha;
  - sacos de areia, galões, tambores, o M151 e o mastro;
  - o UH-34D pousado ao longe, entre coqueiros.
- **VC:**
  - o abrigo de folha, a rede e o armário de armas;
  - o caixote, os sacos de arroz e a lamparina;
  - a cozinha Hoàng Cầm, entre bambus e bananeiras.
- Os modelos são os do mapa, já preparados pelo `AssetLoader.template`. O PreviewService copia 20
  para VT65Preview.Props.
- **Luz:**
  - o sol real das 18h06 de 18/08/1965 (como o menu já fazia);
  - o palco gira para o sol ficar atrás e à direita do soldado (contorno e céu claro atrás);
  - uma luz principal quente do lado da câmera, que acende na entrada;
  - um preenchimento frio e o lampião tremendo;
  - poeira no facho;
  - cor quente com mais contraste e o fundo desfocado (profundidade de campo).
- **Câmera:**
  - cada entrada tem um enquadramento (corpo inteiro no início; torso e arma no ARSENAL; busto no
    PERFIL; de cima nas MISSÕES; o soldado no canto na LOJA e no PASSE);
  - a câmera vai de um a outro em 0,55 s, sem tranco, partindo de onde está;
  - na abertura, um travelling de 1,7 s desce até o soldado;
  - um respiro leve;
  - o soldado fica no meio do espaço livre entre as colunas, medido na tela. No Studio, com a
    janela estreita, a coluna da direita o cobria (`testes/lote91/antes_soldado_coberto.jpg`).
- **Girar o soldado:** arrastar o mouse ou o dedo fora da coluna da esquerda, ou o analógico
  direito. Volta de frente depois de 8 s parado. O gesto não aciona nada (só fora dos botões e sem
  tela por cima).

**As imagens:** as capas do dono (marketing/capas), já publicadas como imagens da página do jogo
(`Pagina.miniatura_*`, tipo Image), entram em `AssetIds.Capas`. Cada entrada do menu tem a sua, e o
cartão grande troca para ela no foco, em fusão de 0,3 s com um zoom lento.

| Entrada | Capa |
|---|---|
| JOGAR | os fuzileiros olhando o arrozal |
| ARSENAL | a trincheira em 1ª pessoa |
| MISSÕES | a travessia do riacho |
| PERFIL | a vila na chuva |
| COMO JOGAR | o posto de comando |
| PASSE | o bambuzal à noite |
| LOJA | o banner da vitrine |

**Transições (§4):**
- **Entrada:**
  - os blocos esmaecem e deslizam um depois do outro;
  - os itens da esquerda chegam em escada (45 ms);
  - as sombras e a luz do soldado sobem.
- **Foco (mouse, controle, cursor virtual ou toque):**
  - a barra âmbar cresce ao lado da entrada e o texto desliza e fica âmbar;
  - a descrição troca, a capa funde e o soldado muda de enquadramento;
  - sem foco por 0,5 s, volta ao JOGAR e ao quadro de início.
- **Tela por cima** (loja, passe, missões, cartão, configurações, tutorial): o menu esmaece e o
  soldado vai para o enquadramento dela; ao fechar, tudo volta.
- **JOGAR:** a câmera entra no soldado, a tela escurece num preto quente e a mesa do lobby aparece,
  como antes (lote 66).
- **Movimento reduzido:** a entrada só esmaece, a câmera corta, sem travelling, sem poeira e sem o
  zoom das capas.

**Mapeamento até os lotes das telas:**

| Entrada | Abre |
|---|---|
| ARSENAL | a Intendência (equipamento por posto e créditos) |
| MISSÕES | as ordens |
| PERFIL | o cartão do jogador |
| COMO JOGAR | o tutorial |
| LOJA | a vitrine |
| PASSE | o passe |
| CONFIGURAÇÕES | a aba do menu do jogo |

O Arsenal de verdade (categorias, prévia, equipar) é de um lote próprio.

**Conferido no Studio** (janela de 839 × 656; um jogador, mouse; nome de teste pelo
`VT65DevNome`):
- **Composição:** o soldado próprio no centro, grande, entre as colunas.
- **Acampamentos:** o dos EUA com 23 modelos carregados; o do VC pelo `VT65DevPalco`.
- **Foco:** a câmera foi para a arma no ARSENAL e para o busto no PERFIL, e a capa e a descrição
  trocaram.
- **Giro:** 150 px de arraste giraram o soldado 94°, sem abrir nada.
- **Telas:** a LOJA abriu por cima com o menu esmaecido; o JOGAR levou à mesa.
- **Erros:** 0 novos.
- **Custo do palco:** 177 peças, 49 chamadas de desenho (149 de sombra), ~128 mil triângulos na
  cena; ~54 fps no Studio atrás de outras janelas.
- **Dois acertos depois da 1ª captura:**
  - os três modelos de planta tinham o nome errado (`_v65`) e não chegavam;
  - a câmera do ARSENAL (2,25 m) e a do PERFIL (1,55 m) estavam perto demais.

**Testes:**
- `lobby.luau` (7):
  - todo modelo do acampamento tem ID;
  - cada vaga do palco usa um modelo que o servidor manda;
  - as câmeras a 2,5 m ou mais e o alvo perto do meio;
  - o soldado próprio e os ganchos;
  - o JOGAR e as entradas do §6;
  - as capas são as da página;
  - as transições e o movimento reduzido.
- `run.luau`: o teste dos planos do menu antigo virou "palco fora do mapa e longe da mesa".
- `componentes.luau`: âncoras do movimento reduzido.

**Não testado:**
- **Tela 16:9 cheia:** o Studio do MCP fica numa janela de 839 × 656. A conta diz que, em
  1920 × 1080, o soldado fica em 54% da largura.
- **Controle de verdade:** navegação, analógico direito e foco devolvido.
- **Toque e celular:** o lote do celular reorganiza o lobby (§6: "no celular, reorganize").
- **Cosmético equipado:** a troca do soldado foi medida pelo lado; o caminho do Commerce_Equip só
  pelo Lune.
- **O jogo publicado.**

## D-207 — Lote 92: a loja sobre o palco, a compra só pelo destaque e os códigos de resgate (2026-11-20)

**Pedido do dono:** o mesmo do D-206 ("lobby, loja e passe ... com imagens bem feitas, transições de
qualidade"), com as referências da loja: o título, as abas com o botão de troca, o saldo no alto, a
grade de cartões com imagem e preço, e o personagem na luz à direita. O §9 do prompt pede:
- as categorias "Destaques, Itens, Conjuntos, Caixas e Códigos";
- detalhes e prévia antes de comprar;
- os estados da compra (em andamento, cancelada, confirmada, erro, entrega pendente), sem pedido
  duplicado;
- códigos válido, inválido, vencido e já usado, confirmados pelo servidor.

**A casca (ShopController):**
- O painel saiu do meio (720 × 620) para a esquerda (1120 × 900; `UiKit.fit` encolhe numa janela
  menor).
- **No lobby**, o fundo é só o escuro da esquerda, e o palco mostra o soldado do jogador à direita
  (quadro "loja", em 82% da largura). **Em campo** (tecla L), um véu na tela inteira.
- **Cabeçalho:** "LOJA", a linha "VISUAIS, CAIXAS E APOIO · AS VANTAGENS TÊM TETO" e, à direita, o
  saldo de créditos com um "+" que leva ao MERCADO.
- **Abas:** as 7, com o botão do controle ou a tecla (Q/E) nas pontas e o traço âmbar na ativa:
  DESTAQUES (a vitrine de antes), MERCADO, CAIXAS, ARQUIVO, VANTAGENS, INTENDÊNCIA e CÓDIGOS.
- **Grades:** a vitrine e o mercado em 3 colunas.
- **Abertura:** o painel entra da esquerda em 0,28 s.

**Compra (§9):**
- O cartão não compra mais. O botão de preço leva o item para o destaque (nome, descrição, a imagem
  grande e o preço), sobe a lista até ele e passa o foco do controle para o COMPRAR.
- A compra só sai do destaque:
  - **em andamento:** o botão trava com "…" enquanto a janela do Roblox está aberta;
  - **cancelada:** "Compra cancelada", na borda vermelha;
  - **comprada (passe):** "ENTREGANDO…" até o servidor mandar a posse;
  - **entrega pendente:** sem a posse em 15 s, o botão destrava com "Entrega pendente" e um aviso;
  - **produto:** "Compra confirmada".
- O resultado da janela do Roblox (`Prompt*PurchaseFinished`) só muda a tela; quem entrega continua
  sendo o servidor.
- **O armário** usa o último lado escolhido quando o jogador ainda não tem lado (no lobby). Equipar
  ali refaz o soldado do palco (D-206): é a prévia no soldado do §9.

**Códigos (`Shared/Codigos`, `CampanhaService` op "code_redeem"):**
- O servidor limpa o texto (caixa alta, sem espaço nem traço, só letras e números, até 24) e
  responde válido, inválido, vencido, "ainda não vale" ou já usado.
- O uso fica em `campaign.owned["codigo:<CÓDIGO>"]`: o mapa de posse da campanha, já gravado e
  unido entre servidores. Não precisou de versão nova do perfil.
- O prêmio sai por `ProgressionService.bonus` (créditos) e pelas estrelas do passe, e o perfil é
  gravado na hora.
- Mais de 8 erros no minuto: "Muitas tentativas: espere um minuto" (contra tentar todos).
- **Na tela:** o campo e o RESGATAR (trava com "…", destrava sem resposta em 8 s); a resposta do
  servidor em verde ou vermelho; os códigos que a conta já usou.
- **Código de lançamento:** `STARLITE1965`, 250 créditos (pouco mais que uma semana de recompensa
  diária, que dá 30 a 90 por dia), até 31/01/2027. Proposto neste lote e aprovado pelo dono em
  2026-11-20 ("Pode ficar").

**Conferido no Studio** (janela de 839 × 656):
- A loja nova abriu pelo LOJA do lobby: cabeçalho, saldo, abas com Q/E, destaque e a grade de 3
  colunas com as imagens; o MERCADO também (`testes/lote92`).
- **Códigos pelo mesmo pedido do botão** (`Campanha_Action`):
  - "naoexiste99": "Este código não existe.";
  - "starlite-1965": "Código aceito: $ 250", e o saldo foi de 1.333 para 1.583;
  - "STARLITE1965" de novo: "Você já usou este código.";
  - "Já usados nesta conta: STARLITE1965" apareceu;
  - 8 erros seguidos: o 9º pedido recebeu "Muitas tentativas".
- **O clique do MCP** no RESGATAR e num cartão da vitrine não chegou ao botão. O botão não recebeu
  nem o MouseButton1Down e ficou "Idle" com o mouse do MCP em cima. Já o `GetGuiObjectsAtPosition`
  no centro do botão devolve o próprio botão por cima de tudo. Os cliques nas abas e no LOJA
  chegaram. O desvio parece do clique do MCP dentro do painel com escala (a captura sai 1,25× maior
  que os pixels da tela). O clique de verdade não foi testado.
- **Erros:** 0 novos.

**Testes:**
- `loja.luau` (6):
  - os 5 estados do código;
  - os códigos cabem no mapa de posse e têm prêmio;
  - o servidor valida, marca, grava e limita;
  - as categorias e o painel à esquerda;
  - o cartão não compra (nenhum `UiKit.bind(bt, o.action`) e a compra tem os estados;
  - o armário pelo último lado.
- `interface.luau`: a linha dos códigos usados não junta texto com `..`.

**Não testado:**
- **O clique de verdade** no RESGATAR e nos cartões (o do MCP desvia).
- **Uma compra de verdade:** nenhuma janela de compra foi aberta, nem no Studio.
- A tela 16:9 cheia, o controle e o celular.
- **O jogo publicado.**
- **O que fica para os próximos lotes:**
  - a prévia de item que o jogador ainda não tem no soldado (o servidor só veste o que é dele);
  - o mercado e as vantagens ainda compram direto do cartão (a janela do Roblox é a confirmação);
  - os conjuntos com a lista exata do que vem.

## D-208 — Lote 93: o passe sobre o palco, com o desenho de cada recompensa (2026-11-20)

**Pedido do dono:** o mesmo do D-206 ("lobby, loja e passe ... com imagens bem feitas"). As
referências do passe mostram:
- o painel com a trilha grátis e a premium alinhadas por nível;
- a imagem grande do prêmio escolhido;
- os selos de nível, XP e premium no alto;
- as missões a um passo;
- o personagem na luz à direita.

O §11 pede a imagem de cada recompensa e os estados bloqueada, alcançada, disponível, resgatada e
dependente do premium.

**O que fica (pedidos de antes do dono):**
- a linha do tempo horizontal dos 50 níveis (D-124: "coloque o passe em ordem cronológica
  horizontal");
- as cores vivas das trilhas, verde a grátis e dourada a Veterano (D-130);
- as letras grandes (lote 23).

**O que mudou:**
- **Casca:**
  - o painel saiu do meio para a esquerda e cresceu de 1000 para 1180 (mais níveis à vista);
  - no lobby, o fundo é o escuro da esquerda, e o palco mostra o soldado do jogador à direita
    (quadro "passe");
  - em campo, o véu de antes;
  - o painel entra da esquerda em 0,3 s.
- **Encaixe na tela:** o `UiKit.fit` passou a contar a margem da esquerda, no passe e na loja.
  Antes, no Studio, o FECHAR do passe saía da tela à direita (`testes/lote93/passe_antes_da_margem.jpg`).
- **Cabeçalho:** escuro, com o ouro só subindo da esquerda e o filete do alto.
  - Ao lado do fim da temporada, o estado do Veterano: "✓ VETERANO ATIVO" ou "🔒 VETERANO
    BLOQUEADO".
  - "ORDENS DO DIA ›" ao lado do FECHAR abre a tela das ordens no lugar do passe.
- **A imagem de cada recompensa:** `ItemArte.recompensa` entrou no lugar do emoji do lote 23.
  - **Itens de verdade:** acabamento de arma (a arma em 3D com o acabamento) e uniforme (o pano da
    farda), pelo `ItemArte.desenha` das caixas e do arquivo.
  - **Desenhos do ItemArte:** a ficha de créditos, a faixa de título e a insígnia do emblema, com
    sigla e cores por emblema.
  - **Desenhos novos, feitos com quadros:**
    - o cartão de abate: a moldura com a faixa vermelha e a caveira;
    - a música: o disco de vinil com os sulcos e o selo;
    - o gesto: o soldado em silhueta, com a mão na testa, o mapa ou o cantil;
    - o reforço: o selo "2×" em âmbar.
  - A arte de cada cartão é montada uma vez por recompensa, num CanvasGroup que apaga inteiro.
  - A ficha embaixo mostra a arte grande, que cresce de 92% ao trocar (sem crescer com movimento
    reduzido).
- **Estados (§11), com cor, símbolo e palavra:**
  - "RECEBER" (disponível, verde, o contorno pisca);
  - "✓ RECEBIDO" (resgatada, a arte a 55%);
  - "🔒 VETERANO" (dependente do premium);
  - "NÍVEL n" (ainda bloqueada, a arte a 25%).

**Conferido no Studio** (janela de 839 × 656):
- O passe abriu pelo PASSE do lobby, com o estado do Veterano.
- **Arte:** emblema S1, cartão de abate, selo 2× XP, fichas de créditos, o pano do uniforme e a
  faixa do título.
- **Foco no nível 2 do Veterano:** a ficha trocou para a arte grande do cartão de abate.
- **Nível 10:** as armas em 3D com o acabamento nas duas trilhas (2 ViewportFrames); no 12, o gesto
  de continência.
- **Margem:** depois do ajuste, o FECHAR coube na janela.
- **Erros:** 0 novos.

**Testes:**
- `passe.luau` (3): todo tipo de recompensa da temporada tem desenho (e nada de emoji); os cinco
  estados; a casca e a linha do tempo horizontal.
- `interface.luau`: o teste do lote 23 passou a cobrar o desenho por tipo no lugar do emoji.

**Não testado:**
- Receber uma recompensa e comprar o Veterano nesta tela nova: a lógica não mudou; nada foi recebido
  nem comprado.
- A tela 16:9 cheia, o controle, o celular e o jogo publicado.
- **Fica para depois:** as ordens dentro do próprio passe (como numa aba), em vez de abrir a tela
  delas.

## D-209 — Lote 94: escolher onde nascer e confirmar no NASCER (2026-11-20)

**Pedido:** o §8 do prompt de interface:
- "Selecionar um marcador deve destacar o ponto e atualizar o painel com nome, situação e motivo de
  eventual bloqueio. Mapa, painel e resumo inferior devem refletir o mesmo destino selecionado.";
- "O servidor recebe o identificador do ponto e da rodada, revalida a solicitação e escolhe a
  posição real de nascimento. Durante o processamento, bloqueie confirmações duplicadas.";
- o NASCER em destaque embaixo à direita, habilitado só com o ponto apto;
- preservar o ponto ao voltar do equipamento;
- oferecer alternativas quando o ponto perde a disponibilidade.

**Antes:** o clique (ou o A) num ponto pronto já pedia o nascer. O servidor recusava em silêncio, e
a ordem de inserção esperava 8 s pelo corpo para dizer "recusada (o ponto mudou?)".

**O que mudou:**
- **Escolher e confirmar são passos separados:**
  - clique, toque, LB/RB (Q/E) e o 1º A num ponto só escolhem;
  - o NASCER confirma: o botão, o A ou o Enter no escolhido;
  - arrastar a carta não escolhe nada.
- **Destino inicial e memória:**
  - sem destino, a carta abre com o ponto sugerido escolhido (pronto, mais perto do objetivo do
    time);
  - o destino fica guardado ao voltar da mesa ou do equipamento e depois de morrer, enquanto o
    ponto existir;
  - partida nova (`VT65Rodada`) limpa o destino.
- **O mesmo destino nos três lugares:**
  - na carta, o anel âmbar em volta do ponto, com o nome sempre aberto (forma, além da cor). A
    legenda curta ganhou "ESCOLHIDO";
  - o painel no canto de baixo à direita da carta;
  - a faixa de baixo: "Destino: <nome> · <situação>".
- **O painel:**
  - o tipo do ponto (QG do lado, reunião avançada, zona de pouso, boca de túnel, companheiro do
    squad, onde você caiu...);
  - o nome e a etiqueta do estado, com cor, símbolo e palavra: "● PRONTO", "⏳ AGUARDANDO",
    "× BLOQUEADO", "… PEDIDO", "× FORA DA CARTA";
  - o motivo (o `why` do servidor, "Libera em 12 s" ou a recusa por 6 s);
  - o NASCER em âmbar.
- **Alternativa:** com o escolhido bloqueado ou fora da carta, "► Pronto perto: <ponto>" escolhe o
  pronto mais perto dele.
- **No toque,** o botão grande usa o mesmo painel (`NascerPedido.painel`), no lugar do
  `ToqueTelas.spawnButton`.
- **O pedido leva a rodada:**
  - todo nascer passa pelo `SpawnTransition.pedir(id, pagamento)`, que manda
    `Spawn_Request(id, pagamento, VT65Rodada)`: a carta, o jogar agora e o renascer onde caiu;
  - o cliente nunca manda coordenada.
- **O servidor confere tudo e responde no `Spawn_Result` novo:**
  - `{ id, ok = true }` ao nascer;
  - `{ id, ok = false, cod, msg }` na recusa. Os códigos (`Shared/NascerPedido.MOTIVO`): rodada,
    fim, sem_lado, em_campo, terreno, papel, ponto (saiu da carta; companheiro caiu ou saiu),
    espera, bloqueado (com o motivo do ponto), sem_lugar, pagamento e falhou;
  - o `mateSpawn` e o `inPlace` passaram a devolver o motivo;
  - um pedido repetido enquanto o primeiro corre (`inf.busy`) não tem resposta própria.
- **Pedido duplicado:** o cliente trava o NASCER ("NASCENDO…") até a resposta, o corpo novo ou 12 s
  (`NascerPedido.ESPERA_S`).
- **Recusa na hora:** a `SpawnTransition` para ao receber a recusa. Ela escreve o motivo na ordem e
  carimba RECUSADA, sem esperar os 8 s do corpo.
- **Textos novos (en, es, vi):** 41.

**Conferido no Studio** (janela de 839 × 656, dois places do pipeline):
- **Abertura:** pelo JOGAR, a carta abriu com o QG escolhido: "● PRONTO", NASCER em âmbar, "Destino:
  QG · Pronto para nascer" (`testes/lote94/carta_qg_escolhido.jpg`).
- **Ponto bloqueado:** o clique na reunião avançada a escolheu; o servidor a bloqueava na contagem.
  - O painel mostrou "× BLOQUEADO" com "Na contagem, todos nascem na base", o botão "BLOQUEADO" e
    "► Pronto perto: QG" (`ponto_bloqueado_alternativa.jpg`).
  - O clique no NASCER bloqueado não mandou pedido.
  - A alternativa voltou o destino ao QG.
- **Recusas pelo remote, todas com resposta e motivo:**
  - rodada errada (8) e sem rodada → `rodada`;
  - ponto que não existe → `ponto`;
  - `lz:1` na contagem → `bloqueado`, "Na contagem, todos nascem na base".
- **Nascer:** dois cliques no NASCER com 0,12 s de intervalo deram uma resposta só
  (`{"id":"hq","ok":true}`); o soldado nasceu no QG (`transicao_em_campo.jpg`).
- **Destino guardado:** depois de morrer, o ESCOLHER OUTRO PONTO da baixa abriu a carta com o QG
  ainda escolhido.
- **Recusa pela tela:** com a rodada trocada só no cliente (99), o destino foi limpo e voltou o
  sugerido. O NASCER saiu com a rodada errada; a ordem marcou RECUSADA na hora, com "A partida mudou:
  escolha o ponto de novo" (`recusa_rodada.jpg`).
- **Ajustes vistos no Studio:**
  - o "◷" saía como um quadrado no Arimo: virou "⏳" e "…";
  - o painel de 560 × 96 tapava o rótulo do objetivo D: ficou com 470 × 88
    (`painel_antes_de_compactar.jpg`).
- **Erros:** 0 no Output (cliente e servidor), fora os avisos de TexturePack (429) do Studio.

**Testes:**
- `nascer.luau` (10): estados, painel, pedido em curso, tipos, alternativa, motivos, o handler do
  servidor (a rodada antes de tudo, cada recusa responde), todo pedido com a rodada e a carta.
- `toque_telas` e `jogaragora` seguem o caminho novo.

**Não testado:**
- **Controle de verdade:** o LB/RB, o A e o Enter (o teclado do MCP não chega com o Studio atrás).
  A lógica está nos testes de fonte.
- **Telas e partidas:** o celular, a tela 16:9 cheia, o jogo publicado e a troca de partida de
  verdade (só a rodada trocada no cliente).
- **Renascer onde caiu:** pago com créditos ou Robux, nesta versão (não comprado).

**Fica para depois (§8, outros lotes):**
- as abas Nascimento, Equipamento, Aparência e Perfil;
- mostrar só os companheiros aptos: hoje aparecem todos, com o motivo, e os do QG tapam o símbolo
  do QG;
- agrupar os pontos vizinhos;
- arrastar a carta no controle sem o cursor.

## D-210 — Lote 95: o HUD de infantaria em zonas (2026-11-20)

**Pedido:** o §13 do prompt de interface. As zonas:
- alto ao centro: placar, tempo e A–E;
- alto à direita: XP discreto e feed limitado de abates;
- lateral esquerda: esquadrão;
- pé ao centro: vida e estados;
- pé à direita: arma ativa com imagem, munição e equipamento;
- centro: mira e retorno de combate.

Também pede:
- capturar, defender e contestar nos marcadores;
- menos nomes perto da mira;
- a vida com o valor real e o dano recebido diferente da direção do objetivo.

**O que já havia e fica:**
- a faixa da frente (placar, tempo, A–E);
- a bússola;
- o cartão da arma com as balas e os pentes (v43);
- a faixa das vagas que aparece ao trocar (BarraItens: a "lista breve" do §13);
- o marcador de acerto e a caveira;
- a roda de equipamento.

**Decisão que muda:** a "sem barra de vida" do MedicalController (Parte 1, HUD mínimo) cai. O §13 pede
"atualize a vida com o valor real". A visão que perde cor com a vida continua.

**O que mudou:**
- **Vida e estados** (`Controllers/HudInfantaria`, pé ao centro, logo acima da bússola):
  - a barra com o número inteiro do Humanoid, cor por nível (verde > 60%, âmbar > 30%, vermelho) e
    marcas de 25%;
  - o dano deixa um rastro claro que encolhe em 0,4 s;
  - em cima, os estados do `Medical_State`: HEMORRAGIA (vermelho), SANGRANDO, PERNA FERIDA e BRAÇO
    FERIDO;
  - no veículo a barra sai (o painel do veículo é o próximo lote).
- **Direção do dano:**
  - três pedaços de arco vermelho em volta da mira (raio de 120 px), apontando para a origem do tiro
    (`Combat_Hit`);
  - os arcos acompanham a câmera enquanto duram (1,6 s); o mesmo lado renova em vez de empilhar
    (até 4);
  - o objetivo segue em latão na bússola: cor, forma e lugar diferentes.
- **Abates e XP** (alto à direita, abaixo da faixa quando ela chega até ali):
  - `Combat_Feed` novo: o servidor manda a todos o abate creditado a um jogador (nomes, lados e
    arma; nunca posição);
  - no máximo 4 linhas de 6 s, nas cores fixas dos lados, com a arma entre colchetes; o seu abate ou
    a sua queda com o filete âmbar;
  - o XP em campo sai do meio da tela e vai para uma linha só ("+100 XP · +10 CI · Abate"), que soma
    o mesmo rótulo por 3 s;
  - no toque os abates não aparecem e o XP volta ao aviso de sempre (a tela limpa da v39).
- **Esquadrão** (lateral esquerda, abaixo da reserva das listas do Roblox e da ordem):
  - o líder primeiro com ★, o nome, o papel e o estado com símbolo e cor: em campo ●, caído ✚,
    fora ○;
  - vem do `Squad_State`, sem o próprio jogador;
  - a coluna de comandos (PainelComandos) começa embaixo dele. Numa tela baixa, se não cabe nem na
    escala mínima, ela recolhe (o §14 pede a ajuda recolhível).
- **Cartão da arma** (HudCampo), de 290 × 108 para 340 × 140:
  - a imagem do modelo do jogo (`RodaArte`, o mesmo desenho da roda), enchendo a largura;
  - seletor, alça e munição na coluna da direita;
  - embaixo, granada, fumaça e bandagem com a imagem pequena e a quantidade (zero em vermelho).
- **Capturar, defender, contestar** (`HudInfantaria.verbo`, o mesmo na faixa, nos marcadores e na
  carta): o objetivo em disputa (`Match_State.contested`) vira CONTESTAR; ATACAR virou CAPTURAR.
- **Perto da mira** (9% da altura): os nomes dos aliados somem e o ícone apaga; no objetivo fica só a
  letra.
- **Textos novos (en, es, vi):** 9.

**Conferido no Studio** (janela de 839 × 656):
- **Antes:** sem vida, sem dano, sem abates (`testes/lote95/hud_antes.jpg`).
- **Faixa e vida:** "CAPTURAR" na faixa; a vida com 112.
- **Dano de verdade:** 40 de dano pelo servidor levou a barra de 112 a 72, com o rastro; o
  `Combat_Hit` da esquerda acendeu o arco do lado esquerdo (`vida_e_dano_real.jpg`).
- **Feed:** o `Combat_Feed` pelo servidor chegou: "SOLDADO TESTE [M1911A1] Bot VC 21".
- **Gancho `hud_infantaria`:** arcos, estados, abates (o próprio com o filete), a linha de XP e o
  esquadrão de exemplo com líder, caído e fora (`hud_exemplos_esquadrao.jpg`).
- **Ajustes vistos no Studio:**
  - o feed ficou embaixo da faixa: as telas contam a faixa do Roblox de jeitos diferentes, e agora a
    conta desconta a origem de cada tela (`feed_sob_a_faixa_antes_do_ajuste.jpg`);
  - a arma saía pequena no cartão: a câmera chega a 55% da distância;
  - o esquadrão cobria a coluna de comandos: ela recolhe e volta quando ele sai
    (`esquadrao_sobre_a_coluna_antes_do_ajuste.jpg`).
- **Erros:** 0 no cliente e no servidor.

**Testes:** `hud_infantaria.luau` (10).

**Não testado:**
- **Abate de verdade:** um jogador abatendo outro de verdade (o crédito do servidor não mudou; o
  `Combat_Feed` sai junto do `Combat_Kill`).
- **XP de verdade:** um ganho real pelo `Progress_State` (a ligação está nos testes de fonte).
- **Companheiros de verdade:** só o exemplo.
- **Telas:** o toque, a TV, o 16:9 cheio e o jogo publicado.

## D-211 — Lote 96: o ARMÁRIO no lobby, a M16 à vista e os nomes sem vietnamita (2026-11-20)

**Pedidos do dono (20/11):**
- "cadê a m16 para os americanos";
- "coloque o botão do armários no lobby";
- "simplifique as escritas retire os nomes vietnamitas do jogo deixe apenas vila, arrozal, engenho
  por exemplo".

**A M16:**
- **Já existia (D-146):** é escolha do líder, do fuzileiro, do médico e do suporte dos EUA.
- **Por que não se achava:** só se trocava num botão pequeno do cartão do papel, e a escolha durava
  a sessão.
- **Agora a escolha fica no perfil** (campo novo `armas`, por "lado:papel"):
  - o pedido `Arma_Escolher` confere a lista do papel, grava, publica no atributo `ArmasPreferidas`
    e, se for o papel de agora, troca o equipamento do próximo nascimento;
  - o papel escolhido sem arma usa a do perfil;
  - o botão do cartão do papel grava do mesmo jeito.

**O ARMÁRIO:**
- **No lobby:** a entrada ARMÁRIO, entre a LOJA e o PASSE.
- **Na loja:** a aba ARMÁRIO, a segunda, com:
  - **EUA | VC:** começa no lado de agora ou no último escolhido;
  - **ARMA PRINCIPAL:** cada papel com mais de uma arma, em cartões com o modelo 3D do jogo (RodaArte)
    e "✓ ESCOLHIDA";
  - **VISUAIS:** o que você já tem para vestir naquele lado, com ● equipado;
  - **o atalho "ACABAMENTOS E UNIFORMES ›":** leva à INTENDÊNCIA.
- As abas passaram a 8 (a letra encolheu de 20 para 18).

**Nomes sem vietnamita na tela:**
- **O setor C:** "C Xóm Gò" virou "C Vila", e o ponto forte "Xóm Gò" virou "Vila" (MapConfig e o
  gerador `crop_world.py`, que agora escreve os nomes novos).
- **VC:**
  - "Chỉ huy" virou "Comando";
  - "Tiểu đội 1–9" virou "Esquadra 1–9";
  - os 13 postos viraram as funções em português ("Recruta", "Combatente", "Chefe de célula"...
    "Comandante de regimento"), com siglas novas.
- **Itens:** Cantil extra, Bolsa de socorro, Sandálias de pneu, Morteiro 82 mm, Porcelana imperial e
  Emblema: Vila.
- **Telas:**
  - os subtítulos e a carta da tela de entrada ("OPERAÇÃO STARLITE · AGOSTO DE 1965");
  - as dicas ("a vila dos túneis");
  - o relatório pós-ação;
  - a medalha;
  - descrições de acabamentos;
  - os textos da mesa 3D do lobby ("CROQUI DA VILA", "1º REGIMENTO"; a mesa do VC não traduz mais os
    rótulos).
- **Ficam:**
  - os nomes de lugar que servem de chave no código e não aparecem (An Cường, An Thới: a vila dos
    túneis e as aldeias);
  - a fonte vietnamita pré-carregada;
  - o idioma vietnamita, em que os postos do VC voltam aos nomes originais;
  - as anotações históricas dos eventos, que não aparecem na tela.
- **Textos novos (en, es, vi):** 58.

**Conferido no Studio:**
- **Lobby:** a entrada ARMÁRIO e o subtítulo novo (`testes/lote96/lobby_com_armario.jpg`).
- **ARMÁRIO:** a aba com M14, M16, Escopeta 12 e M79 em 3D (`armario_arma_principal.jpg`).
- **A M16 escolhida:**
  - pelo mesmo pedido do cartão, o atributo virou "US:rifleman=m16" e o cartão passou a "✓ ESCOLHIDA"
    (`armario_m16_escolhida.jpg`);
  - depois, como fuzileiro sem dizer a arma: `Loadout = m16,m1911` e a M16 na mão
    (`m16_no_cartao_da_arma.jpg`).
- **Faixa:** "CAPTURAR · C Vila · ~325 m a oeste".
- **Erros:** 0 (cliente e servidor).

**Testes:** `armario.luau` (6).

**Não testado:**
- o clique de verdade nos cartões do ARMÁRIO (o clique do MCP não chega dentro do painel com escala,
  D-207);
- o perfil gravado e lido de novo numa sessão nova (a migração está no teste);
- o jogo publicado.

**Correção (lote 97):** o total do Lune deste lote é 840 ok, não 845. Somei de novo os 6 do
`armario.luau`, que já estavam na conta.

## D-212 — Lote 97: a loja na composição das referências, com as caixas em imagens novas (2026-11-20)

**Pedido do dono:** "faça a loja do jogo igual da imagem, com o msm layout imagens brilhantes e
realistas, utilize o blender se necessário, coloque as caixas para vender ali modifique as imagens
das caixas, traga vida para a loja".

**As referências** (fotos do jogo de boxe de 18/11, aba de destaques):
- à esquerda, a vitrine que troca com o tempo e a fixa;
- no meio, dois pacotes grandes com arte;
- à direita, a lista dos outros com "coletados";
- uma aba de conjuntos em cartões altos;
- o lutador na luz à direita.

**O que entrou:**
- **Composição, com a identidade do STARLITE:** nomes, cores, textos e arte são nossos (a regra de
  não copiar nome, interface e sons de outro jogo continua). A arrumação segue a referência, como o
  dono pediu.
- **As imagens das caixas** (`tools/blender/caixas_loja.py`, Cycles na CPU):
  - as 10 caixas modeladas, cada uma com o corpo dela:
    - madeira em tábuas e ripas, madeira pintada, baú de chapa ou laca vermelha;
    - cantoneiras de aço ou latão, alças e cintas;
    - o nome em estêncil e a estrela nas de patente;
    - a luz da raridade saindo pela fresta da tampa e um halo atrás na cor da caixa;
    - relevo fino de uso nos materiais;
  - 768 × 768 com fundo transparente (`assets/ui/caixas`);
  - subidas como Decal (`CaixaLoja.*`, `AssetIds.CaixaLoja`); o servidor resolve a imagem ao abrir
    (`ImagensUi.caixas`, atributo `ImgCaixa_<id>`);
  - `CaixaImagem` desenha a imagem; sem ela, o caixote 3D de antes. A aba CAIXAS usa a imagem nova.
- **A vitrine dos DESTAQUES** (no alto, acima do destaque, que continua sendo o único lugar de comprar
  os passes):
  - **esquerda:**
    - MERCADO DO DIA: 3 itens com a arte (ItemArte), o preço e "● NOVOS ITENS EM 22 H 18 MIN";
    - SEMPRE NA LOJA: 3 itens fixos, que levam ao destaque.
  - **meio:** duas caixas grandes, cada uma com:
    - a imagem flutuando devagar;
    - as etiquetas ("GRÁTIS JOGANDO", "COLETADOS 0/43");
    - o botão "ABRIR · 2 PRONTAS" (ou "GANHE JOGANDO", o preço, os bilhetes).
  - **direita:** mais 4 caixas em linhas, com o nome curto ("CAMPANHA"), "COLETADOS x/y" e a ação.
  - **Vida:** os cartões entram subindo, um depois do outro, e as imagens flutuam. Com movimento
    reduzido, nada mexe.
  - **Ordem das caixas:** as pagas primeiro (quando à venda), depois as que dá para abrir agora.
  - **O clique numa caixa** abre a aba CAIXAS parada nela, com a borda em âmbar. As probabilidades vêm
    antes de abrir ou comprar, como manda a regra das caixas.
- **Caixas pagas:** só aparecem para quem pode comprar agora (D-173). A venda segue desligada até o
  dono reenviar o questionário de classificação (TODO_USUARIO, item 2). Quando ligar, elas entram
  sozinhas na frente da vitrine.
- **CONJUNTOS** (aba nova): os 4 conjuntos em cartões altos, cada um com:
  - a cor do conjunto, "EXCLUSIVO" e "N ITENS";
  - os primeiros itens em leque (ItemArte) e a lista do que vem;
  - o preço do passe, ou "✔ SEU". A posse é perguntada ao Roblox, porque o `Commerce_State` só traz
    os passes do Commerce.
- **Abas:** DESTAQUES, CONJUNTOS, CAIXAS, ARMÁRIO, MERCADO, ARQUIVO, VANTAGENS e CÓDIGOS. A
  INTENDÊNCIA ficou oculta: abre pelo ARSENAL do lobby e pelo atalho do ARMÁRIO, e o LB/RB pula.
- **Textos novos (en, es, vi):** 17.

**Conferido no Studio** (janela de 839 × 656):
- **Imagens:** as 10 resolvidas pelo servidor (`ImgCaixa_*`).
- **Vitrine:** as três colunas (`testes/lote97/destaques_vitrine.jpg`).
- **Ajustes vistos no Studio** (`destaques_antes_do_ajuste.jpg`):
  - os nomes da direita cortavam ("CAIXA DE...");
  - a descrição das caixas grandes ficava embaixo da imagem.
- **Clique na Caixa de Veterano:** a aba CAIXAS abriu nela, com a borda âmbar
  (`caixas_veterano_em_foco.jpg`).
- **CONJUNTOS:** os 4 cartões com "✔ SEU" (no Studio a conta do dono tem os passes). A captura não
  foi guardada: a plaqueta desenha o nome da conta.
- **Renders:** `caixas_blender_1.jpg` e `caixas_blender_2.jpg`, sobre o fundo escuro da loja.
- **Erros:** 0 (cliente e servidor).

**Testes:** `loja_vitrine.luau` (5).

**Não testado:**
- uma compra de verdade (nenhuma janela de compra foi aberta);
- as caixas pagas na vitrine (a venda está desligada);
- o controle percorrendo a vitrine, o celular, a TV e o jogo publicado.

**Fica para o lote 98:** a animação da abertura das caixas e os efeitos da loja. Também o símbolo
que falta no conjunto Fundador.

## D-213 — Lote 98: a abertura das caixas com efeitos e a loja com vida (2026-11-20)

**Pedido do dono:** "faça uma nova animação perfeita e realista com efeitos visuais para a loja e
para a abertura das caixas itens etc".

**A abertura da caixa** (antes da roleta; roteiro no `Shared/Efeitos`, puro e testado):
1. **queda:** a caixa cai do alto do painel, acelerando, com a sombra crescendo no chão;
2. **pouso** (0,42 s): baque (`caixa_pouso`), poeira dos dois lados, tranco no painel e a caixa
   amassando e voltando;
3. **tremor** (0,62 a 1,62 s): sacode cada vez mais forte e mais rápido (`caixa_tremor`), a luz da
   caixa cresce e faíscas escapam pela fresta;
4. **estouro** (1,62 s): clarão curto, a tampa salta e tomba para o lado, a caixa fica aberta com a
   luz saindo de dentro, faíscas, a onda de choque, raios girando e o tranco (`caixa_estouro`);
5. **saída** (2,15 a 2,45 s): a caixa cresce um pouco e some na luz; a roleta sai da luz (cresce de
   90 %) com os raios atrás dela.

**Regras da abertura:**
- **A cor é a da CAIXA, nunca a do item sorteado.** O resultado só aparece na roleta; a abertura não
  recebe o resultado (nada de adiantar nem de fingir um "quase", D-177).
- **Efeitos curtos:** a mesma coisa em 0,75 s, sem a queda.
- **Sem efeitos ou com movimento reduzido:** a roleta vem direto.
- **PULAR** corta a abertura e a roleta.
- Nenhum sorteio nesta tela (o teste da roleta proíbe `math.random`): a posição das faíscas da
  fresta anda pelo tempo.
- **Robustez** (vista no Studio):
  - um quadro travado conta no máximo 0,1 s: a abertura fica mais lenta, mas não pula fase;
  - as camadas abertas baixam no ABRIR (`preCaixa`, antes da resposta do servidor), só as da caixa
    que vai abrir;
  - o estouro espera as duas carregarem (até 1,2 s, a caixa sacode mais um pouco).

**A caixa aberta em duas camadas** (`tools/blender/caixas_loja.py -- todas --aberta`):
- o mesmo enquadramento da fechada, então as camadas se encaixam na tela:
  - **corpo:** oco (fundo e quatro paredes), com o miolo aceso e a luz de dentro pintando as paredes
    na cor da caixa, mais o facho (três cartões de luz de pé, um largo e dois finos em leque);
  - **tampa:** sozinha, com as cantoneiras e a cinta, iluminada por baixo;
- o alto do corpo tem o alfa caindo a zero (`topo_suave`; no jogo, a borda reta do facho aparecia);
  `--so-topo` refaz só isso;
- 20 imagens de 768 × 768 (média de 503 KB), subidas como `CaixaLoja.<id>_corpo` / `_tampa`; o
  servidor resolve primeiro as fechadas, depois as camadas (`ImgCaixa_<id>_corpo`).

**Efeitos de interface** (`Controllers/UiEfeitos`, um laço só que se desliga sozinho):
- faíscas (rastro alinhado com o voo e bolinhas de luz, com arrasto e gravidade, em fórmula
  fechada), onda de choque, raios girando, halo respirando, cintilas de quatro pontas, o brilho
  que varre um cartão, brasas subindo, tranco e clarão;
- texturas feitas por fórmula (`tools/efeitos_ui.py`: brilho, faísca, raio, anel e cintila;
  33 KB no total), brancas e pintadas na cor (`Images.efeito_*`, atributo `Img_efeito_*`). Sem a
  imagem, um quadro redondo de reserva;
- movimento reduzido: nada voa nem treme; o halo fica parado;
- os laços da loja param com a loja fechada.

**A roleta e a recompensa:**
- o marcador acende a cada cartão que passa;
- o cartão vencedor solta a onda e as faíscas na cor da raridade (mais no épico e no lendário, com
  tranco);
- na recompensa, o halo macio respira atrás do item, com os raios do raro para cima, faíscas e onda
  ao aparecer, cintilas, o brilho passando pelo cartão e brasas no épico e no lendário. A
  quantidade sobe com a raridade (16 no comum a 64 no lendário).

**A loja com vida:**
- nas caixas grandes da vitrine:
  - o halo da caixa respira atrás dela (mais forte com caixa pronta para abrir);
  - brasas sobem e o brilho passa pelo cartão;
- nas linhas, o mercado do dia e a aba CAIXAS, a luz de cada caixa e o brilho, fora de fase;
- a compra que passou (passe, produto ou mercado) acende a loja com a onda e faíscas douradas (só o
  enfeite; quem entrega é o servidor).

**Sons novos** (`tools/sons_roleta.py`, síntese com semente própria; os cinco da roleta não mudaram):
- `caixa_pouso` (450 ms);
- `caixa_tremor` (1,1 s);
- `caixa_estouro` (1,6 s).

**Conjunto Fundador:** o "símbolo que faltava" eram os uniformes de pano liso, que sozinhos viravam um
quadrado de cor. O leque dos CONJUNTOS agora veste o soldado (`fundador_uniformes_vestidos.jpg`).

**Gancho do Studio:** `VT65DevAbrir = "<caixa grátis>"` (cliente) abre pelo mesmo caminho do botão
ABRIR: o servidor confere, sorteia e grava. No MCP, o controle fantasma (D-149) trocou a aba da loja
no meio do teste e apertou o PULAR e o VOLTAR; para gravar a abertura inteira, zere o
`GuiService.SelectedObject` a cada quadro no cliente.

**Conferido no Studio** (janela de 839 × 656, Studio atrás de outra janela, ~15 fps):
- **vitrine** com os halos, as brasas e o brilho (`testes/lote98/destaques_com_vida.jpg`);
- **6 aberturas gravadas em vídeo** (Recompensa, Veterano e Campanha):
  - fases na Campanha: pouso 0,508 s, tremor 0,708 s, estouro e troca das camadas 1,66 s, fim 2,48 s;
    espera pelas camadas 0 ms; pior quadro 202 ms;
  - a roleta parou no item que o servidor gravou (`RoletaItem` = `RoletaServidor`, desvio de 0 a
    0,5 px);
  - sequência em `abertura_campanha_sequencia.jpg` e `abertura_tampa_voando.jpg`;
- **recompensa** comum (cinza) e épica (raios roxos, brilho, cintilas): sem captura no repositório,
  porque a plaqueta e a roleta desenham o nome da conta;
- **o que o Studio mostrou e foi corrigido:**
  - a caixa sumia no estouro (camadas ainda baixando);
  - o clarão branco apagava tudo;
  - a borda reta no alto do facho;
  - um quadro de 0,8 s pulava do estouro para a saída;
- **Output:** 0 erros de script. Os avisos "Asset content representation is being generated" são das
  texturas de acabamento da roleta (D-178), não das imagens novas (conferido).

**Testes:** `efeitos.luau` (11).

**Não testado:**
- a abertura de caixa paga e a comemoração da compra (nenhuma compra foi feita);
- o celular, a TV, o controle de verdade e o jogo publicado;
- o fps numa máquina sem o Studio atrás (no Studio o limite é 15 fps).

## D-214 — Lote 99: o pódio com os três e a câmera no melhor, e as comemorações como itens (2026-11-21)

**Pedido do dono:** "faça o podio como no r6 mostrando os 3 primeiros e depois dando zoom para o
melhor bem animado e podendo fazer comemoração que iremos vender comemoração dps".

**O roteiro do pódio** (os 12 s da comemoração, `Comemoracao.PODIO`, puro e testado):
- **chegada:** o 3º (0,15 s), o 2º (0,45 s) e o 1º (0,85 s) caem no caixote, cada um na vez dele,
  com um quique pequeno;
- **os três à vista** até 4,2 s, com a câmera aberta e o balanço da D-202;
- **a câmera vai até o 1º** (4,2 a 5,6 s, na curva mais suave): de 31 para 16 studs, campo de 34° para
  30°, das coxas até acima da cabeça, com uma órbita lenta;
- **o 1º faz a comemoração dele** a partir de 5,0 s (saindo do gesto de antes em 0,5 s); o 2º e o 3º
  seguem nos gestos de sempre;
- **a tela:** os cartões do 2º e do 3º saem quando a câmera vai e entra a faixa
  "★ MELHOR DA PARTIDA", com o nome, a comemoração dele e faíscas douradas.

**As comemorações** (`Comemoracao.CATALOGO`; cada uma é um item):
- **grátis (todo mundo tem):**
  - Vitória (o fuzil no alto e os braços em V; a de sempre);
  - Apresentar armas (sentido, o fuzil à frente do peito);
- **EM BREVE (para vender depois):**
  - Grito de guerra (o punho no peito e os braços no alto);
  - Rajada para o alto (três tiros para o céu com o tranco);
  - Aceno à tropa;
  - Pulos de alegria.
- Os gestos novos (sentido, apresentar, grito, rajada) são procedurais como os da D-202, nos mesmos
  limites de junta e sem salto entre quadros (o maior passo nas comemorações é de 10,7° a 60 fps).

**Itens e compra futura:**
- **perfil:** `comemoracao` (a escolhida, padrão "padrao") e `comemoracoes` (as que o jogador tem, para
  quando forem vendidas);
- **escolha:** pelo remote `Comemoracao_Equipar`. O servidor só aceita a que o jogador tem e publica
  `Comemoracao` e `ComemoracoesTem`;
- **pódio:** o servidor guarda a comemoração de cada um (`l.com`) ao congelar o resultado;
- **para vender:** basta dar `comemoracoes[id] = true` no recibo do produto (nenhum produto foi criado:
  o preço e o produto são do dono).

**ARMÁRIO:**
- a seção nova "COMEMORAÇÃO NO PÓDIO" tem a prévia ao vivo (a mesma cena, só o soldado do lobby no
  caixote do meio, de corpo inteiro) e os 6 cartões;
- o cursor (ou o foco do controle) já mostra a comemoração na prévia, e o clique escolhe;
- as EM BREVE só se veem.

**Erros achados:**
- **No Studio:** o campo `self.solo` tinha o nome do método `Cena.solo`. Vazio, o Luau achava o
  método pelo metatable e o pódio inteiro rodava no modo prévia. O teste agora proíbe campo com nome
  de método.
- **Sem Studio:** `UiKit.estadoTag` não existe (o certo é `UiKit.Estilo.estadoTag`), e o luau-lsp não
  acusou: a aba do ARMÁRIO teria quebrado. Achado por uma varredura; o teste `efeitos.luau` agora
  confere todo `UiKit.<nome>` usado nos controladores.

**Conferido no Studio** (janela de 839 × 656, nomes de teste):
- **o remote:** pedir "pulos" (EM BREVE) deixou "padrao"; pedir "apresentar_armas" trocou;
  `ComemoracoesTem` = "padrao,apresentar_armas";
- **1ª rodada do pódio (ainda com o erro do nome):**
  - os três na cena;
  - aos ~6 s, os cartões do 2º e do 3º saíram e entrou a faixa "★ MELHOR DA PARTIDA · SOLDADO TESTE 1 ·
    COMEMORAÇÃO: APRESENTAR ARMAS" (`testes/lote99/podio_tres_e_destaque.jpg`; a câmera ali era a da
    prévia, por causa do erro);
- **2ª rodada (corrigida):**
  - a câmera lida no cliente estava perto do 1º;
  - os três soldados estavam nos lugares;
  - mas os ViewportFrames pararam de desenhar (nem um cubo de teste aparecia): o jogo do dono estava
    aberto com 2,3 GB e a GPU é de 2 GB. Parei o Studio (a regra do CLAUDE.md) e a imagem ficou sem
    ver.

**Testes:** `comemoracao.luau` (10: os 5 de antes e mais 5); `efeitos.luau` (12, com a varredura do
UiKit).

**Conferido depois** (o jogo do dono fechado, no lote 100):
- o pódio inteiro em vídeo:
  - a cortina "FIM DA PARTIDA";
  - os três chegando nos caixotes (a cena aberta mostra os caixotes);
  - a câmera indo até o 1º;
  - a faixa do melhor;
  - o 1º com o fuzil apresentado à frente do peito e depois no alto
  (`testes/lote99/podio_aberto_e_perto.jpg`);
- a prévia do ARMÁRIO: o soldado do lobby de corpo inteiro, "PRÉVIA: VITÓRIA" e os 6 cartões, com os
  braços erguidos (mãos a 12,8 studs, cabeça a 11,7) (`armario_comemoracoes.jpg`);
- 0 erros de script (cliente e servidor).

**Não testado:** com jogadores de verdade, no celular e no jogo publicado.

## D-215 — Lote 100: as transições das telas (a cortina, a palavra da vitória e o desfoque) (2026-11-21)

**Pedidos do dono:** "quero transição nas telas de vitoria carregamento etc" e "analise como o jogo de
box no roblox faz suas transições tela de carregamento etc".

**A análise do jogo de boxe:**
- **O jogo:** a busca na web não achou o título (nem "Stand and Bang" nem o "OCTAFOLD" do ringue);
  vídeo não dá para ver daqui. A análise sai das 11 capturas do dono (18/11).
- **Moldura fixa:** a barra de cima, as dicas de botão embaixo e o lutador iluminado à direita ficam;
  só o conteúdo do meio troca (LOJA, PACOTES, CÓDIGOS, CARREIRA). A troca é de conteúdo, não de tela
  inteira. Nós já fazíamos assim nas abas (a folha desliza 14 px, D-207).
- **Modal sobre o fundo escurecido e desfocado:** "BACK TO THE MAIN MENU?" por cima da CARREIRA
  apagada. Nós escurecíamos, mas não desfocávamos.
- **Cartão de título nas passagens grandes:** antes da luta, a arena vista do alto com
  "FELPO vs SAMUEL" e "GET READY 9". A passagem grande tem nome e contagem; nós já temos a contagem
  (D-203).
- **Cor quente e contínua:** o vermelho e o laranja do fundo se repetem em todas as telas; a troca
  não muda a luz.

**O que entrou:**
- **A cortina** (`ReplicatedFirst/Cortina`, a conta em `CortinaCurva`): um quadrado escuro inclinado
  (14°) atravessa a tela da esquerda para a direita, com as faixas âmbar e cáqui na frente.
  - Cobre em 0,34 s (freando), mostra "STARLITE" e o nome da próxima tela, e sai pela direita em
    0,4 s (acelerando), com as faixas de trás. A troca de conteúdo acontece coberta: nada pisca.
  - Cobre qualquer proporção (16:9, 4:3, 21:9, celular em pé e deitado: o teste confere os cantos) e
    some inteira nas pontas.
  - Uma de cada vez. Com movimento reduzido, esmaece no lugar (0,16 + 0,12 + 0,2 s).
  - Reservas: se a cortina falhar, a troca acontece mesmo assim e ela some. Na tela de entrada, volta
    o esmaecer de antes; o jogador nunca fica preso.
- **Onde ela passa:**
  - **da tela de entrada para o lobby** ("STARLITE · OPERAÇÃO STARLITE · AGOSTO DE 1965"): coberta, a
    tela de entrada sai e a mesa do lobby começa o travelling de chegada, que aparece já se mexendo;
  - **nas fases do fim de partida:** VITÓRIA → comemoração ("FIM DA PARTIDA"), → votação ("VOTAÇÃO DO
    MAPA"), → preparando ("PREPARANDO O CAMPO") e → a partida nova ("A PARTIDA VAI COMEÇAR"). Antes,
    as três trocavam seco. Quem entra no meio de uma fase não vê a cortina.
- **A palavra da VITÓRIA/DERROTA bate na tela:** cresce de 150 % e assenta com mola.
  - Na vitória: faíscas e a onda na cor do lado e um brilho passando pela palavra (os efeitos da
    D-213).
  - Na derrota: o tranco.
  - Com movimento reduzido: sem nada disso.
- **O desfoque da confirmação:** com uma confirmação aberta (UiKit.modal), o mundo atrás desfoca
  (BlurEffect 14 na câmera do cliente; a interface não desfoca).

**Achado no caminho:** o luau-lsp escreve os diagnósticos na saída de erro, e eu a descartava desde o
lote 98. O "limpo" dos lotes 98 e 99 não valia. A rodada certa (o código de saída e o arquivo com as
duas saídas) achou tipos na `Comemoracao` (lote 99) e na `Cortina`; os dois corrigidos. Nos arquivos
do lote 98 não havia nada.

**Testes:** `transicoes.luau` (4):
- a cobertura em 6 proporções de tela, com as pontas fora;
- as curvas;
- o tempo, abaixo de 1 s;
- as ligações e as reservas.

**Conferido no Studio** (com o jogo do dono fechado; janela de 839 × 656, em vídeo):
- **da tela de entrada para o lobby:** a cortina cobriu, mostrou "STARLITE · OPERAÇÃO STARLITE ·
  AGOSTO DE 1965" e saiu pela direita com as faixas, já com o lobby;
- **fases do fim:**
  - pódio → "VOTAÇÃO DO MAPA" → votação;
  - → "PREPARANDO O CAMPO" → tela de preparo;
  - → "A PARTIDA VAI COMEÇAR" → lobby (`testes/lote100/cortina_sequencia.jpg`);
- **VITÓRIA DO USMC:** a palavra batendo, com as faíscas e a onda azuis. A faixa do brilho estava
  dentro do quadro do título (tamanho automático) e esticava a moldura até o botão; foi para um quadro
  irmão do tamanho da palavra (`vitoria_palavra.jpg`, já corrigido);
- **confirmação:** o desfoque chegou a 14 e saiu ao fechar pelo VOLTAR (resposta "voltou");
- **erros:** 0 de script (cliente e servidor; os "TexturePack" do Studio local de sempre).

**Não testado:**
- a derrota (o tranco);
- o celular, a TV e o jogo publicado.

## D-216 — Lote 101: a mira inclinada e os textos no celular (2026-11-21)

**Pedidos do dono:** "não consigo inclinar a mira e quando tento o personagem da uma facada" e "os
textos no celular estão horriveis tudo em cima do outro".

**Mira inclinada:**
- A facada vinha do R3: mirando, ele caía na ação `melee` da camada de baixo. Agora, mirando, o R3 é
  `lean_cycle` (reto, direita, esquerda, reto).
- O `Inclinar` lia a tecla segura e a câmera voltava ao soltar; agora lê `Input.state.lean`.
- No toque, os botões ◄ e ► aparecem ao mirar, e o ITEM sai da frente deles.
- Medido no Studio pelo caminho real (gancho `VT65DevInclinar`), mirando: rolagem da câmera 0°, −14°,
  +13,9°, 0°; fica de lado sem segurar; a arma continua na mão e nenhuma animação de faca toca.

**Textos no celular** (simulador do Studio, Galaxy A06, 800 × 360, área de 705 × 338):
- `ReplicatedFirst/TextoCabe`: texto maior que a própria caixa encolhe até caber, nunca abaixo de 8 px
  nem acima do tamanho de projeto.
- **Lobby:** a escala parava em 0,42 e a coluna media 453 px numa tela de 338: LOJA, ARMÁRIO, PASSE e
  CONFIGURAÇÕES ficavam cortados. Abaixo de 620 de altura entra um arranjo compacto (escala 0,56): a
  coluna começa abaixo dos botões do Roblox e termina em 275 de 280 px; à direita ficam o passe e as
  ordens; o rodapé encolhe. Saem a marca, as dicas de teclado, a diária e o destaque.
- **Contagem:** sobe e encolhe, para a frase não cair no cartão da arma.
- **FPS:** no lobby do celular sai de cima da coluna.
- **Auditoria** (retângulo real das letras, par a par): lobby 0 pares em 85 textos.

## D-217 — Lote 101: o símbolo do Robux, os botões e uma imagem por entrada (2026-11-21)

**Pedidos do dono:** "troque o R$ pelo simbolo do robux", "deixe os botoes do passe e da loja
chamativos" e "a cada negocio q vc passa em cima tem uma imagem diferente como no jogar".
- Preço com o caractere do Robux (U+E002, `Estilo.robux`), conferido na tela.
- Cada entrada do lobby tem a própria imagem no fundo, que acende no foco.
- LOJA em âmbar e PASSE em vermelho, com o brilho correndo.
- ARMÁRIO com imagem própria (`Images.menu_armario`).

## D-218 — Lote 101: as insígnias dos emblemas (2026-11-21)

**Pedido do dono:** "faça imagens sencacionais para os emblemas".
- `tools/blender/emblemas.py`: 29 insígnias de metal e esmalte em Cycles (512 px, 48 amostras, 335 s
  na CPU). A chapa muda com a raridade (bronze, aço, prata, ouro em estrela, ouro em sol), o esmalte usa
  as cores do item e o símbolo é modelado por pontos.
- O servidor resolve `ImgEmblema_<id>`; `Controllers/EmblemaImagem` desenha no item, na plaqueta e na
  lista do cartão. Enquanto não chega, fica a sigla.

## D-219 — Lote 101: o nome das caixas na língua do jogador (2026-11-21)

**Pedido do dono:** "as escritas nas caixas devem mudar conforme a lingua".
- `caixas_loja.py -- todas --idiomas`: renderiza só a faixa do nome, com a mesma câmera, e cola sobre a
  imagem em português com a emenda suave. 54 imagens (fechada e corpo aberto) em 216 s.
- As palavras saem do dicionário do jogo. Igual ao português (ELITE em inglês; RECOMPENSA e VETERANO em
  espanhol) usa a imagem original. O vietnamita vai em Arial Bold: a Stencil não tem os acentos.
- Os PNG por língua (34 MB) ficam fora do Git: o script os refaz e os IDs estão no `roblox_ids.json`.

## D-220 — Lote 101: tiros e explosões gravados, e a música calma (2026-11-21)

**Pedidos do dono:** "os sons estão horriveis" e "troque a musica do jogo, por uma mais calma".
- A D-204 trocou a biblioteca pela síntese porque a busca do Studio só trazia sons tirados de outros
  jogos. A API da loja, filtrada pelo criador verificado **ProSoundEffects**, traz gravações com a arma
  na descrição.
- `Shared/SomGravacoes`: 39 arquivos e 42 recortes, cada arma com os seus. Medidos no áudio decodificado
  (começo do tiro, fim antes do tiro seguinte, pico).
  - Type 56: AK-47. SKS: outras tomadas de AK-47. M16: CAR-16. M14: BAR .30-06. M60: SG-43.
  - RPD: rajadas de AK-47. Mosin e M70: SG-43. M1911: Grizzly .45. Type 54: Beretta 9 mm.
  - Espingarda: Remington 870. Granada: morteiro. Bomba: explosão grande.
- Continuam sintetizados: recarga, ferrolho, estojo, passos, bala, impactos e o M79.
- Se uma gravação não carregar, toca o trecho do kit.
- Música do menu: "A Place Of Tranquility - Underscore" (Bruce Maginnis, APM, 2:28).
- No Studio: 39 de 39 carregaram, os 42 recortes cabem nos arquivos e a música toca.
- **Não ouvi nada:** a escolha foi pela descrição e pela medida. Quem julga o som é o dono.

## D-221 — Lote 101: a comemoração refeita (2026-11-21)

**Pedido do dono:** "essa comemoração esta horrosa sem trabalho nenhum sem animações fodas efeitos
especiais, qualidade visual".
- **Tela cheia:** a cena era uma faixa fina; agora ocupa a tela, com o título no alto e os cartões no pé.
- **Cenário:** pôr do sol pintado por código (`tools/podio_fundo.py`), com o sol atrás do 1º.
- **Palco:** noite que acende a cada pouso, caixotes com filete de luz e número, bandeira de verdade
  ondulando em dez tiras.
- **Coreografia** por poses-chave: salto com preparação e pouso, volta no ar e rugido. A queda no
  caixote dobra as pernas. Maior passo de junta: 10,7° por quadro a 60 fps (limite 12°).
- **Câmera:** começa baixa e de lado, sobe nos três, vai ao 1º de baixo para cima e treme no impacto.
- **Efeitos** (`Controllers/PodioEfeitos`): fachos de holofote, sol, canhões de confete, poeira, faíscas
  e onda no pouso, sinalizadores no céu, brasas, fumaça, vinheta e faixas de cinema. "Reduzir movimento"
  deixa só a luz parada.

## D-222 — Lote 102: o lobby parado, sem personagem (2026-11-21)

**Pedidos do dono:** "troque o fundo do lobby, coloque algo com mais qualidade e não deixe ele tremendo" e
"quero que as imagens apareçam no lobby somente quando passar por cima dos botões".
- O fundo é uma imagem parada (`tools/blender/lobby_fundo.py`, 2048 x 1152, sem pessoas), em 4 blocos de
  1024 x 576 (`tools/lobby_recorta.py`, `Controllers/FundoLobby`), cobrindo a tela sem distorcer.
- O primeiro render saiu magenta. `--troca-ceu` troca só o céu do EXR pronto (render + (1 − alfa) x (céu
  novo − céu velho)), sem refazer a luz.
- Em repouso nenhuma entrada tem imagem. Com o foco, a entrada acende a dela; a capa do JOGAR só com o
  foco nele.

## D-223 — Lote 102: a preparação em quatro passos (2026-11-21)

**Pedidos do dono:** "isso está horrível, genérico, sem imagens", com a imagem-alvo "ESCOLHA ONDE NASCER",
e "permita alterar o equipamento dentro do jogo na escolha da classe".
- `Controllers/Preparacao` desenha 01 TIME, 02 GRUPO, 03 CLASSE e 04 ONDE NASCER; a `DeployScreen` ficou
  só com a lógica. A mesa 3D e o soldado saíram.
- CLASSE: lista com insígnias, abas ARMA PRINCIPAL, SECUNDÁRIA e EQUIPAMENTO, e ficha da arma.
- EQUIPAMENTO: + e − por item (`Kit_Set`), barra de peso e o motivo quando bate no limite.
- O antitanque mostra o lançador do lado (Bazuca M20 ou RPG-2).

## D-224 — Lote 102: o horário do dia na votação (2026-11-21)

**Pedido do dono:** "coloque opções de horários do dia no mapa, que será escolhido na escolha de mapa".
- `Shared/Horarios`: manhã (8h30), meio-dia (12h12), fim de tarde (18h30) e noite (20h36).
- O voto vai no `Rodada_Votar`; o servidor valida, apura (empate: o primeiro da lista) e aplica antes da
  restauração. A cor fica num `ColorCorrection` próprio (`VT65Hora`).
- Medido no Studio: às 17h20 o sol ainda estava alto e a noite saía laranja; daí a hora e a tinta.

## D-225 — Lote 102: o armário em categorias (2026-11-21)

**Pedido do dono:** "melhore o armário, faça igual o do box".
- `Controllers/ArmarioTela`: categorias à esquerda (ARMAS, ACABAMENTOS, UNIFORMES, CAMUFLAGEM, VISUAIS e
  COMEMORAÇÃO), grade de imagens no meio e ficha à direita.
- Estados separados: em foco, selecionado, seu, equipado e bloqueado, com o caminho para conseguir.
- O servidor manda o equipado de cada lado (`porLado`), e o `Gear_Equip` aceita o lado mostrado.

## D-226 — Lote 102: o passe com imagens (2026-11-21)

**Pedido do dono:** "melhore as imagens do passe do jogo, faça igual ao do box".
- Painel no centro, imagem do prêmio de 68 para 132 px, selo só quando há estado a mostrar.
- O cabeçalho diz o próximo prêmio e quantas estrelas faltam.
- Créditos, reforço, música, gesto, cartão de abate e estrelas têm imagem em Blender.

## D-227 — Lote 102: as ordens do dia (2026-11-21)

**Pedido do dono:** "melhore o visual das ordens do dia".
- Duas colunas (DO DIA, DA SEMANA) de cartões com imagem, estado escrito, barra e recompensa.
- No lobby, cada ordem tem imagem e diz RECEBER ou RECEBIDA.

## D-228 — Lote 102: o mapa de onde nascer (2026-11-21)

**Pedido do dono:** "isso está horroroso, sem ordem, bagunçado, não gosto do mapa, não faz sentido".
- A carta virou uma vista aérea ilustrada (`tools/mapa_aereo.py`), alinhada aos dados do mapa.
- Na escolha de onde nascer saem as faixas, as fronteiras e o raio dos eventos. Objetivos são pinos com
  etiqueta; ponto bloqueado mostra cadeado.
- A ficha do destino fica à direita (foto, estado, time, grupo, classe, veículo).
- No celular, o NASCER fica no pé, à esquerda do cartão do veículo.

## D-229 — Lote 102: as imagens de catálogo e das skins (2026-11-21)

**Pedido do dono:** "melhore as imagens da skin e delas no jogo também".
- `tools/blender/armas_catalogo.py`: 17 armas, 14 equipamentos, 8 classes, 2 times e 10 prêmios.
- `tools/blender/skins_catalogo.py`: 347 acabamentos. Por arma, só as passadas de luz e a UV; a cor, o
  metal e a aspereza de cada acabamento entram depois (~1 s por imagem, em vez de um render).
- `tools/catalogo_imagens.py` leva os PNG ao `AssetIds.Catalogo` (tipo Image). Os PNG ficam fora do Git.
- A textura da arma dentro da partida não mudou.

## D-230 — Lote 102: a loja no centro e as caixas em grade (2026-11-21)

**Pedido do dono:** "isso está horrível", sobre a aba CAIXAS.
- Sem soldado à direita, a loja volta ao centro.
- CAIXAS em três colunas de cartões, com a caixa grande; as chances continuam à vista antes de abrir.
- No celular, a escala mínima fazia a loja passar da tela: agora o painel encurta e as páginas rolam.

## D-231 — Lote 103: corrida, câmera, avisos e limite do mapa (2026-11-21)

**Pedido do dono:** os pontos de jogabilidade do relatório colado no lote 102.
- **Limite do mapa:** cartão compacto com a seta para o ponto mais perto dentro da área, a distância e a
  contagem (`BoundaryController`, `Geometry.voltaParaArea`). Vermelho nos últimos 3 s.
- **Câmera:** indo para a 3ª pessoa, a arma desce junto com a câmera, em vez de sumir na metade.
  "Reduzir movimento" troca sem a câmera viajar. A confirmação vai no cartão da arma.
- **Avisos:** levando tiro, no máximo 2 na tela e ganhos de 1,8 s.
- **Corrida:** dano não desliga (medido e travado em teste). **Troca de arma** (D-194) e **zonas de
  captura** (v41) já atendiam ao relatório.

## D-232 — Lote 104: expansão da Vila e do Arrozal e vegetação do mapa (2026-11-21)

**Pedido do dono:** acrescentar construções, interiores, passagens e vegetação à Vila e ao Arrozal, sem
mapa novo nem objetivo novo, preservando capturas, nascimentos e entradas.
- **Dados à parte:** `Modules/Expansao.luau`. `Expansao.LIGADA = false` tira só a expansão.
- **O antigo não muda:** `ArtPlan.expansao` roda depois de todo o plano. Becos, patamares e valas novos
  ficam marcados (`exp`), e as plantas antigas são sorteadas no chão de antes (`site.semExp`). Só saem
  as que caem no chão novo (13 de 5.080). As 437 construções ficam iguais (`tools/expansao_check.luau`).
- **Vila:** 19 peças a oeste, na clareira vazia (palafitas, casas ligadas, casa da vala, abrigo de
  carroça, abrigo semienterrado, 18 m de trincheira, vala com 2 pranchas e objetos de quintal).
- **Arrozal:** 21 peças a leste, em terra seca (celeiro, pátio, galpão, depósito, telheiro, casa verde,
  ruína, canal, comporta, passarela, muros e objetos). Os campos ficam abertos.
- **Água:** o leito só desce, fica em divisa de voxel e termina no leito do rio. Sem nível dinâmico.
- **Vegetação:** 5 modelos novos e 349 plantas. A folha é puxada para a cor média da mata antiga.
- **Luz:** um lampião local por cômodo, sem sombra (11 no mapa).
- **Medido:** chamadas de desenho +17,9% na soma de 9 vistas (de +8% a +32%). Celular não medido.
- **Fora do lote:** estado "colhido" dos tabuleiros, porque mudaria os tabuleiros antigos.

## D-233 — Lote 105: acabamento da expansão (2026-11-21)

**Pedido do dono:** "continue", depois das pendências da v136.
- **Rocha sólida:** a `exp_rocha` era planta sem colisão. Agora tem um cilindro invisível no miolo
  (`tools/troncos.py`, `ROCHAS`), que para a bala e o soldado, com impacto de pedra.
- **Forro:** o telhado de chapa ganhou uma face de baixo de zinco escuro (`exp_comum.forro`).
- **Colhido:** `RiceField.colhido` marca parte dos tabuleiros em pousio, que recebem medas sem colisão.
  O estado continua "fallow" para o resto do jogo. Sai com `Expansao.LIGADA = false`.
- **Desenho:** `Shared/ExpansaoLod` esconde de longe só o que não tem colisão (raízes, samambaia e piso
  das casas térreas). **Móvel e objeto de quintal ficam:** sumir com eles criaria barreira invisível.
- **Medido:** +15,2% de chamadas de desenho sobre a v135 nas 9 vistas (era +17,9% na v136).

## D-234 — Lote 106: sobrados grandes na Vila (2026-11-21)

**Pedido do dono:** casas novas grandes, de dois andares, "embaixo aberto e algumas fechadas".
- **Modelos:** `tools/blender/exp_sobrado.py` faz 4 sobrados de 13,8 a 15,4 m de frente e 8,2 a 8,6 m
  de altura. `a` e `b` têm térreo aberto e escada de fora; `c` e `d`, térreo fechado e escada por dentro.
- **Na Vila:** 8 casas (5 abertas, 3 fechadas) e 7 caminhos novos em `Modules/Expansao.luau`. Todas a
  mais de 55 m da bandeira, para o andar de cima não dominar a captura (o teste `expansao` cobra).
- **Coluna de alvenaria:** o `V.bloco` grava o `local` para o veio da madeira. Em material de parede,
  regrave com a altura no 2º eixo (`_pilar`), senão a textura deita e vira listras.
- **Forro de telha:** fica no grupo Casa, com esteira (`_placa_forro`). No grupo Telhado a redução da
  malha o engole.
- **Medido:** +3,1% de chamadas de desenho sobre a v137 nas 9 vistas (+18,8% sobre a v135).

## D-235 — Lote 107: a expansão na arte fixa e o piso que some de longe (2026-11-21)

**Pedido do dono:** "Sim, fazer agora" (passar a expansão para a arte fixa e o corte à distância).
- **Só o visual vai para o arquivo** (`assets/estatico/expansao.txt`, 31 construções, 113 peças). A
  colisão, as luzes, a espuma e o piso que some ficam num modelo do jogo em `Map.Art.ExpansaoColisao`:
  peça criada fora do Studio colide em caixa, e a rampa da escada e as águas viraram blocos.
- **Modelo `exp_` refeito ou movido pede cópia nova** (`estatico_copiar.luau` com `MOLDES = "exp_"` e
  `SO_VISUAL = true`). O teste `expansao` cobra posição e quantidade.
- **Piso dos sobrados:** some a partir de 90 m (`Shared/ExpansaoLod`). Móvel continua sempre visível.
- **Custo aceito (precedente da D-169):** sem a forma calculada, o interior fica mais claro: +36% no
  térreo fechado, +39% em cima e +252% no chão do térreo aberto. À noite, +1%.
- **Decisão do dono:** "Manter assim", depois de ver `testes/lote107/luz_antes_e_agora.jpg`.
- **Medido:** -0,5% de chamadas de desenho sobre a v138. O ganho do SLIM não foi medido.

## D-236 — Lote 108: personagens, sons, casas, veículos, telas e miras (2026-11-21)

**Pedido do dono:** personagens mais bonitos, M16 automática, inclinar em L e R, sons reais, casas e
veículos maiores, soldado dentro do veículo, cura melhor, miras limpas e telas refeitas.
- **Causa de "casas e veículos pequenos":** o soldado tem 2,03 m num mundo em tamanho real.
- **Casas:** `tools/casas_escala.luau` escolhe até +25% por casa, sem encostar em estrada, beco, água,
  centro de captura ou outra construção, e grava `Modules/CasasEscala` e `assets/estatico/ajuste_casas.json`.
  Anexo que ficou embaixo vai para o lado; sem lugar, sai. Para rodar de novo: apague o ajuste, rode o
  `estatico.py`, a ferramenta e o `estatico.py` outra vez (senão o ajuste soma sobre ele mesmo).
- **Veículos:** `Vehicles.ESCALA = 1,25`. Quem está em lugar fechado não aparece
  (`Vehicles.ocupanteAparece`, `Controllers/OcupanteVeiculo`).
- **Armas e controle:** M16 com automático e semi; L3 inclina à esquerda e R3 à direita (o toque).
- **Cura (`Shared/Socorro`, `SocorroHud`):** cartão perto da mira e cruz sobre o ferido. Curativo 3 s,
  tratamento 5 s (vida inteira) e reanimar 5 s (volta com 45).
- **Sons:** recarga, acerto e dano com gravações da biblioteca do Roblox (`Shared/SomGravacoes`).
  Música do menu entre as duas últimas, escolhida por ritmo e brilho medidos.
- **Rostos (`tools/rostos/make_rostos2.py`):** volume pintado com sombra e luz em alfa, que serve para
  todo tom de pele. **Uniformes (`tools/make_clothing_v4.py`):** dobras, vincos e brilho do pano sobre
  os 35 moldes v3, com o reflexo da bota. Sobem como Image: o ID vai direto no molde.
- **Telas:** recompensa com arte de Blender por dia (`tools/blender/recompensas.py`), raios e moedas
  voando; "Levar veículo" virou uma vitrine com um cartão por viatura.
- **Miras (`tools/mira_limpa.py`):** move só os vértices da linha de visada, com o mesmo UV, para não
  invalidar os acabamentos. M16: furo de 5 para 8,4 mm, trilhos fora do anel. SKS: entalhe de 4,4 para
  7,6 mm e 5,5 mm mais fundo (antes o fundo escondia o poste).
- **Rosto em placa:** a cabeça padrão do Roblox é malha com o rosto antigo na textura, e um Decal nela
  segue o UV. O `Characters` tira a textura e põe o rosto na peça `Head.Rosto` (invisível, sem colisão).
- **Quem aparece no veículo:** o jipe, o atirador da porta do UH-34D e quem atira com a própria arma. Quem
  atira não pode ser invisível. A Peugeot vai toda fechada: a fila de trás não atira mais pela aba.
- **Moldes como Image:** a chave `Clothing.*_v3` aponta para o arquivo v4. O ID antigo fica em `*_decal_v139`.
- **Medido:** 276 de 276 trechos a pé, autoteste 18 de 18 e -0,8% de chamadas de desenho sobre a v139.
  Detalhes e o que ficou sem teste em `testes/LOTE108_D236_2026-11-21.md`.

## D-237 — Lote 109: rosto, armário, ganhos, navegação, torretas do LVTP-5 e bots (2026-11-21)

**Pedido do dono (1º de 4 lotes):** rostos estilo Roblox, o personagem do armário mudar com o time,
símbolos de Robux e de $, moedas e patentes com som, recompensa até o dia 30, botões de menu, voltar e
avançar, duas torretas no LVTP-5, bots sem prender no arame e sem chão branco.
- **Rostos (`tools/rostos/make_rostos3.py`):** 12 expressões de olho oval, sobrancelha e boca de um
  traço. O PNG é transparente e a pele vem da cabeça. Sobem como `Rostos3.f_NN`.
- **Armário:** o soldado do lobby só vale na prévia do lado dele; no outro lado, o manequim daquele time.
- **Preços:** `$` no lugar de CI e o glifo do Robux (`UiKit.robux`) no lugar da palavra.
- **Recompensa (`Commerce`):** `TRACK_DAYS = 30`; depois do dia 30 repete de 8 a 30. Baús nos dias 14, 21,
  28 e 30. Os valores dos dias 8 a 30 são PLACEHOLDER.
- **Ganhos (`Controllers/GanhoFx`):** moeda, +$, +XP, motivo e barra até a patente seguinte; promoção com
  faixa, raios e fanfarra. No Studio: `VT65DevGanho = "ganho"` ou `"promocao"` (Client).
- **Navegação (`Preparacao`):** MENU e VOLTAR em todo passo e `GRUPO ►` para quem já tem lado. O cartão
  JOGAR AGORA fica ao lado dele: por cima, o clique no avançar mandava o soldado para o campo.
- **LVTP-5:** duas torretas giratórias com M60, a da frente (`gunner`) e a de trás (`commander`,
  `VehicleDrive.torretaDe`). Cada uma tem mira e clarão próprios. Em 1ª pessoa a M60 montada some só para
  quem atira. Os bots ocupam as duas (`BotVehicles`, um `Posto` por torreta). Passageiros ficam dentro.
- **Bots:** a concertina virou `F.BLOCK` na grade (como "casa", a rota passava por dentro), e a falha de
  rota é lida antes do novo pedido de movimento, senão a desistência nunca era vista.
- **Chão branco:** textura de terra neutralizada (`dirt_floor_neutro`) e `Ground` mais escuro.
- **Medido:** autoteste 18 de 18, Lune 920, pytest 77; 1 de 82 bots parado 12 s ou mais junto do arame
  (pior caso 16 s, saiu sozinho). Detalhes e o que ficou sem teste em `testes/LOTE109_D237_2026-11-21.md`.
