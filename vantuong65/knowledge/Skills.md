---
project: STARLITE
type: index
status: verified
source_paths:
last_verified: 2026-11-22
verified_commit: 28289d6
---
# Skills do projeto

Ficam em `.claude/skills/` e só carregam quando a tarefa pede. **O `CLAUDE.md` e o código mandam sobre
qualquer skill.** Use a menor quantidade que resolva: normalmente uma.

| Skill | Use quando | Cuidado neste jogo |
|---|---|---|
| `roblox-dev` | Código que depende de API do Roblox: remotes, DataStore, recibos, UI, input, desempenho | As versões citadas envelhecem. A API real do Studio tem prioridade |
| `map-design` (própria) | Montar ou revisar setor, rota ou cena | Leia antes de mexer em `tools/mapas_ret.py` |
| `viewmodel` (própria) | Arma e mãos em 1ª pessoa, mira, recarga | Só visual; tiro e dano são do servidor |
| `level-design` | Ritmo, fluxo e bloqueio de um trecho | Exemplos em Godot: use o método, não o código |
| `fps-shooter` | Tempo para matar, recuo, dispersão, queda de dano, sensibilidade | Não copie números de outros jogos |
| `game-ai` | Bots: percepção, decisão, travamento, justiça | Estenda `BotBrain` e `BotMove`, não crie outro sistema |
| `game-feel` | Impacto de tiro, explosão e HUD | Nada de pausar o tempo global: o jogo é multijogador |
| `game-ui-ux` | HUD e menus em várias telas, foco no controle, acessibilidade | Reaproveite os componentes de [[UI-Arquitetura]] |
| `input-systems` | Controle, toque, zona morta e remapeamento | Exemplos em Godot; no Roblox, confira com `roblox-dev` |
| `performance-optimization` | Baixo fps, travadas, orçamento por quadro | Comece por [[Performance-Baseline]] |

**Abra a sessão na pasta `vantuong65`.** Num processo novo do Claude Code 2.1.330, as 10 skills foram
encontradas nessa pasta e nenhuma na raiz do repositório. Uma sessão já aberta não vê skill criada depois.

## Já disponíveis pelo MCP do Studio (oficiais do Roblox)
Carregue com `get_roblox_skill` só quando for usar:
- `rbx-perf-profiling`: MicroProfiler e gargalos de CPU e GPU.
- `rbx-scene-analysis`: render, memória e vazamento de instâncias.
- `rbx-network-simulator`: latência, perda de pacote e 3G/4G.
- `rbx-device-simulator-lua`: telas de celular e tablet.
- `rbx-debug`: pontos de parada no jogo rodando.
- `rbx-unit-test`, `rbx-permissions`, `rbx-open-cloud-usage`, `rbx-import-asset`, `rbx-docs-search`.

## Regras para instalar outra
1. Origem identificada, licença que permita copiar e commit fixo. Sem licença, não entra.
2. Baixe em pasta isolada e leia o `SKILL.md` inteiro. Instrução em skill vira instrução do agente.
3. Copie só texto: nada de instalador, script, hook ou servidor MCP.
4. Só instale o que resolver uma necessidade real, e registre aqui.
5. `kb.py check` recusa skill sem origem, sem licença ou com arquivo executável.

## Avaliadas e não instaladas
- `surf-map-design`: não encontrada em busca pública, e é de outro gênero.
- `ohzw/roblox-dev-skills`: sem licença, não pode ser copiada.
- `afrxo/roblox-agent-skills` e as skills Roblox do catálogo `gamedev-skills`: repetem `roblox-dev`.
- `MartinRapcan/blender-claude-skill`: traz scripts, e o projeto já tem um kit próprio no Blender.
