# VẠN TƯỜNG '65 — Progresso

## Fase atual
- **F0 — Pesquisa: parcial.** O critério de 25 m foi atingido no setor oeste. O setor leste depende da
  CORONA (`research/F0_CORONA.md`, download do usuário).
- **F1 — Greybox: código e place prontos, sem medição no Studio.** Os critérios da F1 (piso de
  60 fps e travessia) **só podem ser medidos no Studio**, que não roda neste ambiente.

## Respostas do usuário (2026-11-09) e o que foi feito com elas
| Pergunta | Resposta | Resultado |
|---|---|---|
| P1 tamanho | 4 × 2,4 km | DESIGN D-03 firme; área, setores e pontos fortes implementados |
| P2 créditos | seguir com placeholders | greybox todo em peças simples (`ASSETS.csv`) |
| P3 PDFs | "faça você" | AAR do RLT-7 e livro de 1978: **bloqueio do Akamai por IP**, inclusive com Chromium real. Não contornei, e não há espelho conhecido. A "6739-1" da UT/Commons é a **mesma** edição de 1983 (D-19). O arquivo de Texas Tech falha no TLS pelo proxy. |
| P4 CORONA | "tenho" conta | passo a passo em `research/F0_CORONA.md`; aguardando os arquivos |
| P5 repositório | "faça" | **não tenho permissão para criar repositório** nesta sessão (D-18). Falta você criar um vazio. |

## F1 — o que foi feito
1. `tools/landcover.py`: uso do solo na grade de 4,48 m (carta de 1983 + DEM), detecção de 234
   símbolos de casa e dos riachos na carta.
2. `tools/export_roblox.py`: relevo calibrado nas cotas (D-13), 9.589 quadros de arrozal em terraço,
   diques, sebes, casas, setores em polilinha, 15 pontos fortes, QGs e grade de 1965. Saída em
   módulos Luau.
3. Projeto Rojo (`default.project.json`):
   - `Shared/` com Units, Geometry e MapConfig;
   - `VT65Build/` com Base64, WorldData, TerrainBuilder, FeatureBuilder, Build e os dados;
   - `MapService` (limites da área: aviso e morte em 10 s);
   - `BoundaryController` e `DebugHud` (F3: fps, p99, grade de 1965, setor, m/s e cronômetro de
     travessia);
   - luz Future, Atmosphere, pós-processo contido e streaming.
4. `tools/bake_place.luau` (Lune): assa as 30.635 peças no place, `place/VanTuong65_F1.rbxl`.

## Resultados-chave (medidos aqui)
| Medida | Valor |
|---|---|
| Área jogável | 4.000 × 2.400 m = 14.286 × 8.571 studs (teste Luau) |
| Grade do terreno | 1116 × 759 células de 16 studs, mais 500 m de margem |
| Peças do greybox | 30.635 BaseParts (18.926 diques, 7.263 lâminas, 3.832 sebes, 199 casas, 17 marcadores) |
| Terreno | 3.360 blocos de 64×64 voxels, 127,2 milhões de voxels. O laço Luau leva **30 s** no Lune; o tempo do motor (WriteVoxels) **não foi medido** |
| Colina 43 no terreno gerado | 43 m (±1,2 m no teste do TerrainBuilder com WriteVoxels simulado) |
| Setores | cobrem a área sem buraco nem sobreposição (amostra a cada 50 m) |
| Travessia L–O estimada a 3,1 m/s | ~21,5 min (cálculo, não medição) |
| Testes | Lune: **11 ok**; pytest: **10 passed**; luau-lsp (API do Roblox): **0 erros**; StyLua e Ruff: limpos |

## O que NÃO foi verificado (precisa do Studio)
- O terreno gerado de verdade por `Terrain:WriteVoxels`: a lógica foi testada com um mock, não o
  motor.
- O desempenho: fps, p99, memória e heartbeat. O risco principal são as 30,6 mil peças (D-14).
- `MapService`, `BoundaryController` e `DebugHud` só passaram na checagem de tipos; ainda não foram
  executados.
- A aparência da luz e da atmosfera.

## Como testar no Studio (uns 15 min)
1. Abra `vantuong65/place/VanTuong65_F1.rbxl` no Roblox Studio.
2. Barra de comando (View → Command Bar):
   `require(game.ServerStorage.VT65Build.Build).terrain()` e espere a mensagem "terreno pronto".
3. Salve o place (Ctrl+S).
4. Dê Play e aperte **F3**. Para medir a travessia, vá até a borda leste (Green Beach) e corra para o
   oeste. Anote o fps médio, o p99 e o tempo, e confira o aviso de saída da área.
5. Me mande os números (ou um print do HUD e do MicroProfiler, Ctrl+F6) para eu registrar e ajustar.

## Problemas
1. A carta é de 1983 e o uso do solo de 1965 depende da CORONA.
2. AAR e livro de 1978 continuam inacessíveis daqui (bloqueio por IP).
3. Um greybox com 30 mil peças pode reprovar no piso de 60 fps. Há plano de corte em D-14.
4. Há menos casas que no real, porque a carta generaliza os símbolos (D-17).

## Próximos passos
1. Você cria o repositório vazio → eu movo o projeto (D-18).
2. Você baixa a CORONA → eu georreferencio, meço o setor leste e refaço o uso do solo de 1965.
3. Você mede no Studio → eu otimizo (D-14) até o piso de 60 fps e fecho a F1.
4. F2 (loop central): captura, spawn por mapa com espera, squads, papéis, balística com validação
   no servidor, ferimentos com bandagem e reanimação.
