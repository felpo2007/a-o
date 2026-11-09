# VẠN TƯỜNG '65 — Progresso

## Fase atual (2026-11-09, sessão 3)
| Fase | Estado |
|---|---|
| F0 Pesquisa | parcial: critério de 25 m atingido no setor oeste; setor leste depende da CORONA (`research/F0_CORONA.md`) |
| F1 Greybox | código e place prontos; **fps e travessia ainda sem medição no Studio** |
| **Monetização** | **implementada** (`MONETIZATION.md`); falta você criar os itens no Creator Dashboard e colar os IDs |
| **F2 Loop central** | **código completo com placeholders**; lógica testada fora do Roblox; **não executado no Roblox** |
| F3 em diante | não iniciadas |

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
| Testes Lune | `run.luau` **11 ok**; `f2.luau` **17 ok** |
| pytest | **10 passed** |
| luau-lsp (API do Roblox, `--!strict`) | **0 erros** em todo `src/` |
| StyLua / Ruff | limpos |
| Queda calculada com zeragem a 100 m | M14 0,16 m (200 m) e 0,52 m (300 m); Type 56 0,24 m e 0,80 m. **Não validada** contra tabela de tiro |
| M14 a 300 m | 640 m/s e 1.946 J (calculado) |

## O que NÃO foi verificado
- **Nada da F2 nem da monetização rodou dentro do Roblox.** Só a lógica (Lune) e os tipos (luau-lsp)
  foram verificados.
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
   - ferimentos: tiro no braço → G (curativo); médico reanima com F;
   - morte: espere 60 s e as ondas de 20 s;
   - loja (B), mapa (M), HUD de medição (F3).
5. Me mande os erros do Output e os números do HUD.

## Problemas
1. Não há como rodar o Roblox aqui: todo o comportamento em jogo precisa do seu teste.
2. Desempenho do greybox: 30,6 mil peças (D-14).
3. A balística e o dano ainda não foram calibrados com fonte primária nem com playtest (D-21, D-22).
4. A carta é de 1983 e o uso do solo de 1965 depende da CORONA.
5. O repositório próprio depende de você criar um repositório vazio (D-18).

## Próximos passos
1. Seu teste no Studio (F1 + F2) → correções.
2. Criar os itens de monetização e colar os IDs (checklist em `MONETIZATION.md`).
3. Importar os modelos e sons do ForgeGUI e colar os IDs em `AssetIds.luau`.
4. F3, a fatia vertical: setor central com a arte do Lote 1, luz, áudio e túneis.
