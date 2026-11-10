# VẠN TƯỜNG '65 — Progresso

## Fase atual (2026-11-10, sessão 6)
| Fase | Estado |
|---|---|
| F0 Pesquisa | parcial: critério de 25 m atingido no setor oeste; setor leste depende da CORONA (`research/F0_CORONA.md`) |
| F1 Greybox | código e place prontos; **fps e travessia ainda sem medição no Studio** |
| Monetização | implementada (`MONETIZATION.md`); `tools/roblox_cloud.py create-store` cria os itens assim que houver chave Open Cloud |
| F2 Loop central | código completo + **bots** (D-28); lógica testada fora do Roblox; **não executado no Roblox** |
| **F3 Fatia vertical** | **código e arte entregues** (setor 3); critério (60 fps e teste de foto) **só medível no Studio** |
| **F4 Sistemas pesados** | **código entregue**: comandante, logística, morteiros, M48A3, Ontos, LVTP-5, UH-34D. Lógica testada no Lune; critério (30v30 com 6 veículos) **só medível no Roblox** |
| **Parte 12 Controle** | **código entregue** (vale a partir da F2): layout completo, menus/mapa/comandante sem mouse, mira no analógico, veículos, vibração; 17 testes. **Não testado num controle real** |
| **F5 Arte total e otimização** | **em andamento**: 18 modelos reduzidos às metas da Parte 2; arte nos 5 setores com teto, prioridade, desbaste uniforme e streaming; fusão de diques. Critério (60 jogadores a 60 fps em todos os setores) **só medível no Roblox** |
| F6 | não iniciada |

## F5: o que foi feito (sessões 5 e 6)
- **Remesh:** 18 modelos de uso repetido reduzidos às metas da Parte 2. Números medidos no GLB
  preparado, em D-45, `manifest.json` e `ASSETS.csv`.
  - Vegetação: 1.865 a 3.020 triângulos.
  - Casas: 3.054 a 3.135.
  - Props: 2.838 a 3.975.
  - **Seis remeshes terminaram em `outcome_unknown`** e não foram regenerados (regra do ForgeGUI):
    cozinha, celeiro, poço, altar, túmulo e uma das tentativas do bambu.
    - A cozinha saiu do sorteio das casas.
    - O celeiro não é colocado.
    - Poço, altar e túmulos ficam acima da meta: 8 cópias, ~113 mil triângulos.
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
  - das touceiras de sebe, entram 20%, 37%, 24%, 21% e 54% nos setores 1–5 com o teto provisório
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

## Resultados-chave (medidos aqui)
| Medida | Valor |
|---|---|
| Testes Lune | `run.luau` **11 ok**; `f2.luau` **17 ok**; `f3.luau` **6 ok** |
| pytest | **17 passed** |
| Sol em 18/08/1965 (calculado, UTC+8) | 06:30 → −0,9°; 12:00 → 78,1°; 18:30 → 7,8° |
| Túneis (gerados) | 64 peças, 474 m de galeria |
| Testes Lune F4 | `f4.luau` **12 ok** |
| Testes Lune controle | `controle.luau` **17 ok** (inclui 10.000 eventos aleatórios sem estado preso) |
| Giro de 180° no analógico (quadril) | **0,58 s** (calculado) |
| Testes Lune F5 | `f5.luau` **8 ok** |
| Arte estimada por setor (teto 2,5 mi) | ~1.000 modelos; touceiras de sebe 20/37/24/21/54% nos setores 1–5 (cálculo) |
| Diques após a fusão | 18.926 → **18.095** (comprimento 2.113.038 → 2.113.037 studs) |
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
- Os modelos e sons do ForgeGUI ainda precisam de import e upload pelo Studio. Depois, os IDs vão em
  `Shared/AssetIds.luau`.

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
5. Me mande os erros do Output e os números do HUD.

## Problemas
1. Não há como rodar o Roblox aqui: todo o comportamento em jogo precisa do seu teste.
2. Desempenho do greybox: 30,6 mil peças (D-14).
3. A balística e o dano ainda não foram calibrados com fonte primária nem com playtest (D-21, D-22).
4. A carta é de 1983 e o uso do solo de 1965 depende da CORONA.
5. O repositório próprio depende de você criar um repositório vazio (D-18).

## Próximos passos
1. **Você:** itens 1 e 2 de `TODO_USUARIO.md` (experiência + chave Open Cloud). Com eles, eu publico
   tudo sozinho.
2. Seu teste no Studio (F1–F4) → correções.
3. Trocar os PLACEHOLDER da D-36 por fichas técnicas.
4. F5: com o fps medido, ajustar `ArtBudget.SECTOR_MAX` e fazer a malha única por bloco (EditableMesh) para diques e lâminas.
