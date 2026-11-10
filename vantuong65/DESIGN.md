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
