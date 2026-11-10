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
| M48A3: potência | 750 hp | a confirmar: a infobox lista 810/825 hp para versões a gasolina e trunca a do A3 |
| M48: velocidade | 48 km/h | **fonte**, mas é o valor do M48A5 |
| M48: laterais e traseira | 76/51/25 mm | PLACEHOLDER |
| Ontos | 8.600 kg; 3,83 × 2,59 × 2,13 m; 145 hp; 48 km/h; 6 × M40A1C | **fonte** (wiki:M50_Ontos) |
| Ontos: blindagem | 13 mm | PLACEHOLDER |
| M40: v0 do M344 HEAT | 503 m/s | **fonte** (wiki:M40_recoilless_rifle) |
| LVTP-5 | 37,4 t; 9,04 × 3,57 × 2,92 m; 704 hp; 48 km/h em terra e 11 km/h na água; 6–16 mm; 3+34 | **fonte** (wiki:LVTP-5) |
| H-34 | rotor de 56 ft (2.463 ft²); vazio 7.646 lb; bruto 11.867 lb; máx. 13.300 lb; 1.525 hp na decolagem; 122 mph; subida vertical de 600 ft/min; teto de pairar IGE 9.600 ft e OGE 5.500 ft (H-34A) | **fonte** (wiki:Sikorsky_H-34) |
| Penetração (PG-2 150, 3,5" 250, 106 HEAT 400 mm) | — | PLACEHOLDER |
| Raios letal e de baixas dos explosivos | — | PLACEHOLDER |
| CEP, cadência e recargas das missões de fogo | — | design |
| Navio a 3 km da praia e v0 naval de 760 m/s | — | PLACEHOLDER |
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
