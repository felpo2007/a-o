---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Pipeline de assets

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Blender-Pipeline`.

- O `upload-assets` regrava no `AssetIds` o ID de toda chave do `roblox_ids.json`: trocar um ID só no
  `AssetIds` é desfeito na próxima subida. Troque também no `roblox_ids.json`.
- Os modelos do ForgeGUI não vão para o Git:

  ```
  uv run --group arte python tools/fetch_forgegui_assets.py
  ```

  Ele baixa, confere o sha256 e refaz as reduções locais.
- 82 assets publicados; os IDs estão em `Shared/AssetIds.luau` e `assets/roblox_ids.json`. Faltam
  só `uh34d_loop` e os 4 ícones de passe.
- Para subir mais: ponha no `assets/upload_plan.json` e rode
  `uv run --env-file .env python tools/roblox_cloud.py upload-assets`. O script lê
  `ROBLOX_API_KEY` do ambiente, não do arquivo: sem `--env-file` a resposta é 401. Ele sobe só o
  que falta.
- O importador do Roblox gira cada GLB 180° em Y (D-58). Frente de modelo se confere no Studio,
  não no GLB.
- Todo GLB do gerador vem com mapa de metal: folha, palha e madeira refletem o céu como cromo.
  Modelo que não é de metal passa por `tools/matte_glb.py` antes de subir (D-64).
- Modelo novo (props na malha cheia, até 20 mil triângulos, D-66; vegetação até 6 mil, D-135):
  1. gere no ForgeGUI e prepare em studs com `asset_prepare` (pivô na base). O preparo é grátis,
     no máximo 3 de cada vez;
  2. planta: reduza a 6 mil com `tools/vegetacao_6k.py` (põe a `reducao_local` no manifest);
     prop: só use `tools/decimate_glb.py` se passar de 20 mil (na folhagem, com
     `--soltar-bordas`);
  3. registre no `manifest.json` e no `ArtBudget`;
  4. ponha em `FOSCOS` (e em `COLOR_GAIN` se a textura for escura) no `matte_glb`;
  5. suba com `upload-assets`.
