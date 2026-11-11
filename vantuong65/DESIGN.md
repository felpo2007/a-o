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

**Limites:**
- Texto montado aos pedaços com `..` nem sempre casa com o dicionário e fica em português.
- As fontes de época (SpecialElite) não têm todas as letras vietnamitas.

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

**Falta:**
- criar os 17 Developer Products e os 7 Game Passes (depende da permissão da chave);
- refazer as armas no Blender com as peças `Madeira`, `GuardaMao` e `Metal`. Hoje cada arma é uma
  malha só, e a skin de arma só aparece na arma provisória.

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
