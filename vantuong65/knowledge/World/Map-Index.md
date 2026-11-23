---
project: STARLITE
type: map-index
status: verified
source_paths:
  - src/ReplicatedStorage/Shared/MapasRet.luau
  - src/ReplicatedStorage/Shared/MapaAtivo.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Índice de mapas

| Mapa | id | Modo | Tamanho | Dados | Situação |
|---|---|---|---|---|---|
| [[Mapa-Principal]] (Operação Starlite) | padrão | Warfare, Offensive, Skirmish | 700 × 700 m | `VT65Build/Data` | **No ar** |
| [[Vale-das-Cinco-Passagens]] | `frente` | Linha de Frente | 700 × 300 m | `VT65Build/Data_frente` | Studio |
| [[Estrada-do-Bambu]] | `comboio` | Comboio | 900 × 300 m | `VT65Build/Data_comboio` | Studio |

## Convenções
- **Escala:** 1 stud = 0,28 m.
- **Mapas retangulares:** planta com X para leste e Y para norte. No mundo,
  `X = (x - comp/2) / 0,28` e `Z = -(y - prof/2) / 0,28`. Norte = -Z.
- **Mapa principal:** coordenadas em studs do mundo gerado, com X leste e Z sul.
- **Rumo das construções** (`kb.py mapa`): 0 = frente para o norte, 90 = leste, 180 = sul.
- **Lados:** oeste = VC, leste = EUA.

Dados sempre atuais: `uv run python tools/kb.py mapa frente` ou `mapa frente C`.
Como gerar e alterar: [[Pipeline-Mapas]].
