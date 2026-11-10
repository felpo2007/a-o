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

## Assets no Roblox (o bloqueio atual)
- `src/ReplicatedStorage/Shared/AssetIds.luau` está com os IDs em 0, então a arte não carrega.
- **Caminho 1:** chave Open Cloud válida no `.env` (`ROBLOX_API_KEY`, nunca no Git) e
  `cloud.json` (copie de `cloud.example.json`). Depois rode
  `uv run --env-file .env python tools/roblox_cloud.py all`:
  ele sobe tudo, inclusive os modelos já reduzidos, e preenche os IDs. A chave anterior dava 401
  "Invalid API Key".
- **Caminho 2:** ForgeGUI → Roblox (`artifact_publish`), que exige uma "Personal connection" em
  forgegui.com/forge-mcp. Ele só publica os arquivos do ForgeGUI: os 11 modelos reduzidos
  localmente (ver `manifest.json`, campo `reducao_local`) subiriam pesados. Deixe esses para o
  caminho 1.

## Regras
- Nunca invente número: todo valor medido sai de código executado ou do Studio. Diga o que não
  foi testado.
- Não use nome, interface, sons nem layout de Hell Let Loose ou de outro jogo.
- Segredos só no `.env` (no `.gitignore`), nunca no código nem no chat.
- ForgeGUI: nunca regenerar um job em `outcome_unknown`. "failed" com `retryable` pode ser
  retomado com `generation_retry`.
- Mudou regra ou número de design? Registre em `DESIGN.md` (próximo: D-55) e atualize `PROGRESS.md`.
- Metas da Parte 2: vegetação ≤ 3 mil triângulos, props ≤ 5 mil, herói ≤ 20 mil (`ArtBudget`,
  conferido pelo teste da F5).
- Commits no branch acima, com mensagem em português.
