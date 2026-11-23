---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Veículos e sons

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Veiculos-e-Sons`.

- Torretas do LVTP-5 (D-237): `gunner` na frente e `commander` atrás (`VehicleDrive.torretaDe`). O alvo de
  teste precisa ser um bot de verdade (clone não entra no `Combatants`), e quem atira não recebe o próprio
  `Combat_Tracer`.
- Sons das armas e do campo (D-204): `blender -b --factory-startup -P tools/sons_armas.py` gera os 19
  kits (`assets/armas_sons/kit_*.ogg`) e o `Shared/SomKits.luau` (os trechos);
  `uv run --group arte python tools/sons_armas.py --medir` dá os números e os espectrogramas.
  - Mudou um kit já publicado? Tire a chave dele do `assets/roblox_ids.json` e suba de novo com
    `upload-assets Sounds.kit_<nome>`: o script não troca versão, sobe um asset novo.
  - A síntese é determinística (semente por trecho): o mesmo código gera o mesmo som.
  - No Studio pelo MCP, o ouvinte é a câmera, que pode ficar presa longe do soldado (Scriptable).
    Para ouvir o tiro de perto, dispare do servidor
    `VT65Remotes.Combat_Tracer:FireClient(player, { w, ox, oy, oz, dx, dy, dz, seed })` perto da
    câmera.
- Tiros e explosões gravados (D-220): `Shared/SomGravacoes` (Pro Sound Effects, biblioteca da Roblox).
  Recorte novo: meça no áudio (início, duração, pico) e confira no Studio com `IsLoaded` e `TimeLength`.
- Pá de trincheira (D-183): `blender -b --factory-startup -P tools/blender/novos.py -- shovel_us` (ou `shovel_vc`)
  e o som com `blender ... -P tools/sons_pa.py`. A mão de 1ª e 3ª pessoa sai do `Shared/PaArte`.
  Objeto de mão de 3ª pessoa com várias peças: solde com `Weld` e `C0`, não com `WeldConstraint`.
- UH-34D v3 (D-199): `blender -b --factory-startup -P tools/blender/veiculos.py -- uh34d`
  (`--previa` só renderiza). A silhueta foi medida por código no desenho de três vistas (veja
  `MEDIDAS` no `veic_uh34d.py`). Depois do build:
  - copie o `metricas.json` para `assets/veiculos/uh34d_metricas.json` (o `assets/blender` fica fora
    do Git);
  - passe o `art_novo` e as juntas dele para o `VehicleDrive.ART.uh34d` (o teste `rotor.luau`
    cobra).

  O disco borrado do rotor sai de `uv run python tools/rotor_borrao.py` (Decal em
  `Images.rotor_borrao`; o `ImagensUi` resolve).
