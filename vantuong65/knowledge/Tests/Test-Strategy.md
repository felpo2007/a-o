---
project: STARLITE
type: tests
status: verified
source_paths:
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Estratégia de testes

Rode tudo com saída curta: `powershell -File tools/dev/verifica.ps1`.

| Camada | O que cobre | Limite |
|---|---|---|
| Lune (`tests/luau`) | Regras em módulos puros e texto de código | Não roda física nem render |
| `tools/mapas_check.luau`, `tools/expansao_check.luau` | Dados dos mapas | Não anda no mapa |
| pytest (`tests`) | Geradores em Python | Só as ferramentas |
| ruff, StyLua, luau-lsp | Estilo e tipos | Não prova comportamento |
| `tools/kb.py check` | Links, caminhos, segredos e tamanho da base | Não prova que a nota está certa |
| Autoteste no Studio (`VT65SelfTest`) | 12 sistemas no jogo rodando | Precisa do Studio |
| Teste manual pelo MCP | Caminhada, câmera, bots | Ver [[Studio-Metodo]] e [[Studio-Ganchos]] |

**Passar nos testes locais não significa ter testado no Studio.** Diga sempre o que não foi rodado.

## Comandos originais
```
for t in run f2 f3 f4 controle f5 f6 atualizacoes movimento uniformes progressao bots; do lune run tests/luau/$t.luau; done
uv run --group arte pytest -q && uv run ruff check .
stylua --check src tests/luau tools
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=<globalTypes.None.d.luau> --sourcemap=sourcemap.json --ignore "src/ServerStorage/VT65Build/Data/**" src
```
O `sourcemap.json` não vai para o Git.
