# Instruções para o Claude: VẠN TƯỜNG '65 (jogo de Roblox)

Esta pasta é o jogo **VẠN TƯỜNG '65**: FPS tático 30 contra 30 no Roblox, na Operação Starlite
(agosto de 1965), mapa 1:1 de 4 × 2,4 km. O `CLAUDE.md` da raiz do repositório é de OUTRO projeto
(estratégias de trade). Aqui vale este arquivo. Responda sempre em português.

## Antes de qualquer coisa
1. Leia `PROGRESS.md` (estado e números medidos), `TODO_USUARIO.md` (o que depende do dono) e as
   decisões recentes em `DESIGN.md` (D-45 em diante).
2. O código está no branch `claude/bold-albattani-67hga9`. Traga as novidades com `git pull`.

## Ferramentas
- Roblox: Rojo 7.4, Lune 0.8, StyLua 2.0, luau-lsp (Luau `--!strict`).
- Python: `uv` (grupo `arte` para reduzir malhas: pymeshlab).
- Construir o place:

  ```
  rojo build default.project.json -o build/VanTuong65_base.rbxl
  lune run tools/bake_place.luau
  ```

  O resultado é `build/VanTuong65_F1.rbxl`; copie para `place/VanTuong65.rbxl`.
- **Não salve o place pelo Studio:** o Studio grava com outra compressão, que o Lune 0.8 não lê
  ("Decompression failed"). Teste mudanças no Studio pelo MCP, mas gere o `.rbxl` pelo pipeline.
- **No PC do dono (Windows):**
  - Rojo 7.4.4, Lune 0.8.9, StyLua 2.0.2 e luau-lsp 1.70.1 portáteis ficam em
    `%LOCALAPPDATA%\Programs\vt65-tools`. As definições do Roblox ficam em
    `vt65-tools\luau-lsp\globalTypes.None.d.luau`;
  - o GitHub CLI fica em `%LOCALAPPDATA%\Programs\gh` e é o login do Git para o push;
  - o checkout tem CRLF, então o `stylua --check` acusa todos os arquivos. Cheque numa cópia LF:
    `git -c core.autocrlf=false worktree add --detach <pasta> HEAD`.
- Os modelos do ForgeGUI não vão para o Git:

  ```
  uv run --group arte python tools/fetch_forgegui_assets.py
  ```

  Ele baixa, confere o sha256 e refaz as reduções locais.

## Testes (rode antes de cada commit)
```
for t in run f2 f3 f4 controle f5 f6 atualizacoes; do lune run tests/luau/$t.luau; done
uv run --group arte pytest -q && uv run ruff check .
stylua --check src tests/luau tools
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=<globalTypes.None.d.luau> --sourcemap=sourcemap.json --ignore "src/ServerStorage/VT65Build/Data/**" src
```
O `sourcemap.json` não vai para o Git.

## Teste no Studio (MCP do Roblox Studio)
- Abra `place/VanTuong65.rbxl` e dê Play.
- Na barra de comando, do lado do servidor, use os ganchos (só funcionam no Studio):
  - `workspace:SetAttribute("VT65SelfTest", true)`: autoteste de 11 sistemas. As linhas
    `[VT65 TESTE]` aparecem no Output;
  - `workspace:SetAttribute("VT65DevMode", "Offensive")`: troca o modo (Warfare, Offensive ou
    Skirmish);
  - `workspace:SetAttribute("VT65DevEnd", true)`: encerra a partida e mostra o relatório pós-ação;
  - `workspace:SetAttribute("VT65DevRain", 1)`: força a chuva (0 a 1).
- O `execute_luau` do MCP roda em outra VM: `require` de módulo do jogo devolve uma CÓPIA. Use
  os ganchos acima ou observe por atributos e remotes.
- Relatórios de teste ficam em `testes/`.

## Assets no Roblox (publicados em 2026-11-10)
- 82 assets publicados; os IDs estão em `Shared/AssetIds.luau` e `assets/roblox_ids.json`. Faltam
  só `uh34d_loop` e os 4 ícones de passe.
- Para subir mais: ponha no `assets/upload_plan.json` e rode
  `uv run --env-file .env python tools/roblox_cloud.py upload-assets`. O script lê
  `ROBLOX_API_KEY` do ambiente, não do arquivo: sem `--env-file` a resposta é 401. Ele sobe só o
  que falta.
- O importador do Roblox gira cada GLB 180° em Y (D-58). Frente de modelo se confere no Studio,
  não no GLB.
- Arma nova: acrescente em `tools/weapon_landmarks.py` (frente e frações das mãos, vistas numa
  captura) e rode-o para regenerar `Shared/WeaponArt.luau`. Depois confira a mira no Studio
  (captura mirando): a massa deve aparecer no centro sem nada tapando. Se algo tapar, ajuste
  `EYE_OFFSET_M` (D-60).
- O place da nuvem abre no Studio com
  `roblox-studio:1+task:EditPlace+placeId:125635672454807+universeId:10775697296`.

## Regras
- Nunca invente número: todo valor medido sai de código executado ou do Studio. Diga o que não
  foi testado.
- Não use nome, interface, sons nem layout de Hell Let Loose ou de outro jogo.
- Segredos só no `.env` (no `.gitignore`), nunca no código nem no chat.
- ForgeGUI: nunca regenerar um job em `outcome_unknown`. "failed" com `retryable` pode ser
  retomado com `generation_retry`.
- Mudou regra ou número de design? Registre em `DESIGN.md` (próximo: D-63) e atualize `PROGRESS.md`.
- Metas da Parte 2: vegetação ≤ 3 mil triângulos, props ≤ 5 mil, herói ≤ 20 mil (`ArtBudget`,
  conferido pelo teste da F5).
- Commits no branch acima, com mensagem em português.
