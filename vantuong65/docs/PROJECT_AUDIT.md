# Auditoria do projeto (prompt V5, §2)

Feita em 2026-11-22, sobre a v152 (commit `693350d`).

## Ferramentas
| Item | Situação |
|---|---|
| Roblox Studio com MCP | funciona; escolhe por `list_roblox_studios` |
| Rojo 7.4.4, Lune 0.8.9, StyLua, luau-lsp | funcionam |
| Blender 5.3 com `bpy` | funciona, só na CPU (`VT65_CPU=1`) |
| Git e GitHub | funcionam, branch `claude/bold-albattani-67hga9` |
| Open Cloud (`tools/roblox_cloud.py`) | sobe modelos, imagens e publica |
| `verifica.ps1` | Lune, mapas, pytest, ruff, luau-lsp e base de notas |

## Skills
- **Do projeto:** `roblox-dev`, `fps-shooter`, `game-ai`, `game-feel`, `game-ui-ux`, `input-systems`, `level-design`,
  `map-design`, `performance-optimization`, `viewmodel`.
- **Do Studio:** `rbx-perf-profiling`, `rbx-scene-analysis`, `rbx-import-asset`, `rbx-unit-test`, entre outras.
- **`rbx-convert-to-streaming`:** não existe neste Studio. O jogo já usa Instance Streaming.

## Estado técnico
| Item | Medido |
|---|---|
| Escala | 1 stud = 0,28 m; soldado de 2,07 m |
| Mapa publicado | 700 × 700 m, 5 objetivos, QG do VC a oeste e dos EUA a leste |
| Streaming | ligado, raio mínimo 384 e alvo 1.280 studs, `Opportunistic` |
| Arte fixa com SLIM | 89 modelos no arquivo do place |
| Trim sheet | 3 folhas de 1024 e piso de 512, nas 10 casas da vila |
| Scripts de Blender | 64 |
| Testes antes da V5 | Lune 1.001, pytest 84 |

## Backup
- Tag `backup/antes-v5-v152` no GitHub.
- Place em `C:\Users\Acer\Documents\VanTuong65_backups\v152_antes_V5.rbxl`.

## Riscos ainda abertos (de antes da V5)
Listados em `knowledge/01-CURRENT-STATE.md`: clarão da torreta, `Commerce_Track`, recompensa diária, códigos de
resgate e `Suprimento_Comprar`.
