---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Ferramentas e ambiente

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Ferramentas`.

- Roblox: Rojo 7.4, Lune 0.8, StyLua 2.0, luau-lsp (Luau `--!strict`).
- Python: `uv` (grupo `arte` para reduzir malhas: pymeshlab).
- Construir o place:

  ```
  rojo build default.project.json -o build/VanTuong65_base.rbxl
  lune run tools/bake_place.luau
  ```

  O resultado é `build/VanTuong65_F1.rbxl`; copie para `place/VanTuong65.rbxl`.
- **No PC do dono (Windows):**
  - Rojo 7.4.4, Lune 0.8.9, StyLua 2.0.2 e luau-lsp 1.70.1 portáteis ficam em
    `%LOCALAPPDATA%\Programs\vt65-tools`. As definições do Roblox ficam em
    `vt65-tools\luau-lsp\globalTypes.None.d.luau`;
  - o GitHub CLI fica em `%LOCALAPPDATA%\Programs\gh` e é o login do Git para o push;
  - o checkout tem CRLF, então o `stylua --check` acusa todos os arquivos. Cheque numa cópia LF:
    `git -c core.autocrlf=false worktree add --detach <pasta> HEAD`.

## Ajudantes do dia a dia (`tools/dev`)
- `tools/dev/verifica.ps1`: todas as checagens, com saída curta.
- `tools/dev/abre_studio.ps1 -Nome VT65_x -ComJogo`: formata, confere tipos, gera o place e
  abre uma cópia no Studio (em `%TEMP%\vt65_teste`).
- `tools/dev/stylua_utf8.ps1`: StyLua em cópias LF, sem estragar acentos.
- `tools/dev/tira_id.py <chaves>`: tira um modelo do `roblox_ids.json` para subir de novo.
- `tools/dev/folha.py saida.jpg a.jpg b.jpg`: folha de contato de capturas.
