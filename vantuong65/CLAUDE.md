# STARLITE: Vietnã 1965 (VẠN TƯỜNG '65), jogo de Roblox

FPS tático multijogador no Roblox, na Operação Starlite (agosto de 1965). Responda sempre em português.
O `CLAUDE.md` da raiz do repositório é de OUTRO projeto (estratégias de trade). Aqui vale este arquivo.
Este arquivo é um mapa: o conhecimento fica em `knowledge/` (abre como cofre do Obsidian).

## Como começar qualquer tarefa
1. **Continuação** ("continue de onde paramos"): leia `knowledge/01-CURRENT-STATE.md` e
   `knowledge/Sessions/HANDOFF.md`. Se a tarefa acabou, não invente outra.
2. **Busque antes de ler:** `uv run python tools/kb.py onde <termos>`. Abra de 1 a 3 notas, só o trecho.
3. **Verifique no código.** A nota pode estar velha: código e testes são a verdade do que existe.
4. **Amplie só se faltar.** Nunca leia `knowledge/`, `DESIGN.md` ou `PROGRESS.md` inteiros.

Consultas que leem o código na hora (`uv run python tools/kb.py ...`):
`modulo <Nome>`, `remote <Nome>`, `decisao D-243 [--texto]`, `ativo <termo>`, `mapa frente C`,
`check`, `velhas`, `confere <nota>`. Guia: `knowledge/00-START-HERE.md`.

## Arquitetura
- **Rojo 7.4** (`default.project.json`) gera o place; **Luau `--!strict`**.
- **Servidor autoritativo:** `src/ServerScriptService` (5 Scripts em `Services`, serviços em `Modules`).
- **Compartilhado:** `src/ReplicatedStorage/Shared`, com regras em módulos puros testados no Lune.
- **Cliente:** `src/StarterPlayer/StarterPlayerScripts/Controllers` e `src/ReplicatedFirst`.
- **Remotes:** todos em `Shared/Net.luau`. O cliente nunca decide dano, moeda, posse ou nascimento.
- **Mapas:** escolhidos no boot por `Modules/MapaBoot`; dados em `src/ServerStorage/VT65Build`.
- **Arte:** Blender em `tools/blender`, sobe por `tools/roblox_cloud.py`, IDs em `Shared/AssetIds.luau`.

## Onde olhar
| Assunto | Nota em `knowledge/` |
|---|---|
| Todos os sistemas | `02-SYSTEM-INDEX.md` |
| Testar no Studio | `Tests/Studio-Metodo.md`, `Tests/Studio-Ganchos.md` |
| Ferramentas e testes | `Tests/Ferramentas.md`, `Tests/Test-Strategy.md` |
| Mapas e coordenadas | `World/Map-Index.md`, `World/Pipeline-Mapas.md` |
| Modelos e Blender | `Art-Assets/Blender-Pipeline.md` e vizinhas |
| Desempenho | `Optimization/Performance-Baseline.md` |
| Erros já resolvidos | `Bugs-Lessons/Licoes.md` |
| Decisões D-xxx | `DESIGN.md`, por `kb.py decisao` |
| O que só o dono faz | `TODO_USUARIO.md` |

## Convenções
- 1 stud = 0,28 m. Soldado de 2,00 m no design (o jogo mede 2,07 m); confira porta e escada andando.
- Regra nova em módulo puro, com teste em `tests/luau`. Reaproveite componente antes de criar outro.
- Script de servidor novo: `MapaBoot.iniciar()` antes do primeiro `require`.
- Texto novo de interface passa pelo i18n (`tools/i18n`).
- Edite por Python em UTF-8, preservando o fim de linha. Não use `Get-Content`/`Set-Content` para regravar.

## Comandos
```powershell
powershell -File tools/dev/verifica.ps1
```
```powershell
powershell -File tools/dev/abre_studio.ps1 -Nome VT65_teste -ComJogo
```
- Place: `rojo build default.project.json -o build/VanTuong65_base.rbxl` e `lune run tools/bake_place.luau`.
  O resultado é `build/VanTuong65_F1.rbxl`; copie para `place/VanTuong65.rbxl`.
- Subir assets: `uv run --env-file .env python tools/roblox_cloud.py upload-assets <prefixos>`.
- Publicar (só com o lote pronto e o Studio fechado): `... roblox_cloud.py publish-place`.
- Ferramentas portáteis: `%LOCALAPPDATA%\Programs\vt65-tools`. GitHub CLI: `%LOCALAPPDATA%\Programs\gh`.

## Fluxo de um lote
Entender → buscar → planejar → implementar → testar (Lune e Studio, com números) → registrar →
commit e push no branch `claude/bold-albattani-67hga9`, em português. O dono deu permissão para seguir
sem perguntar a cada passo: pergunte só o que for mesmo dele. Publicar só quando o lote estiver pronto.

## Atualizar a memória (só o que economiza trabalho depois)
- Decisão ou número de design: `DESIGN.md` e `PROGRESS.md`.
- Sistema mudou: corrija a nota e rode `kb.py confere <nota>`.
- Erro que pode voltar: uma linha em `Bugs-Lessons/Licoes.md`; se repetir, vira teste ou regra aqui.
- Fim de sessão: reescreva `Sessions/HANDOFF.md` e, se mudou, `01-CURRENT-STATE.md`.
- Antes do commit: `kb.py check` passa. Nada de código copiado, log ou segredo nas notas.

## Regras
- Nunca invente número: todo valor medido sai de código executado ou do Studio. Diga o que não
  foi testado.
- Não use nome, interface, sons nem layout de Hell Let Loose ou de outro jogo.
- Segredos só no `.env` (no `.gitignore`), nunca no código nem no chat.
- ForgeGUI: nunca regenerar um job em `outcome_unknown`. "failed" com `retryable` pode ser
  retomado com `generation_retry`.
- Mudou regra ou número de design? Registre em `DESIGN.md` (próximo: D-245) e atualize `PROGRESS.md`.
- Tetos de triângulos por modelo: vegetação ≤ 6 mil (D-135), props e herói ≤ 20 mil (`ArtBudget`,
  conferido pelo teste da F5).
- Commits no branch acima, com mensagem em português.
- **Não salve o place pelo Studio** nem edite o place da nuvem por ele. Teste numa cópia.
- `especificacao/` e `marketing/capas` não vão para o Git. O repositório é **público**.
- Nunca leia nem imprima `.env`. Não apague nem sobrescreva sem preservar no Git.
- Sem compra real de Robux, sem ativar `PAGAS_LIGADAS`, sem inventar IDs ou preços.
- Blender só na CPU (`VT65_CPU=1`): a GPU de 2 GB já travou o Studio e o jogo do dono.
- Captura não pode mostrar o nome da conta: use `VT65DevNome = "SOLDADO TESTE"`.
