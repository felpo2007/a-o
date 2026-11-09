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
