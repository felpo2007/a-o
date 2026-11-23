---
project: STARLITE
type: map
status: verified
source_paths:
  - src/ReplicatedStorage/Shared/MapConfig.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Mapa principal: Operação Starlite

Esta pasta é o jogo **VẠN TƯỜNG '65**: FPS tático 30 contra 30 no Roblox (D-122), na Operação
Starlite (agosto de 1965), mapa 1:1 de 700 × 700 m com cinco objetivos: quatro nos quadrantes, a
180–265 m do centro, e a vila de Xóm Gò numa baixada no centro (D-201): A Arrozais, B Serraria (mata
fechada), C Vila (vila em meio círculo, D-148; na tela era "Xóm Gò" até a D-211, que tirou os nomes
vietnamitas da tela), D Ponte e Cais (rio do sul) e E Engenho. O mapa é coberto de mata fechada com
lavoura em volta das vilas (D-65). O `CLAUDE.md` da raiz do
repositório é de OUTRO projeto (estratégias de trade). Aqui vale este arquivo. Responda sempre em português.

## Dados (de `MapConfig.luau`, gerado por `tools/crop_world.py`; em studs)
- **Limites:** X de -2571,4 a -71,4; Z de -3142,9 a -642,9 (700 × 700 m).
- **Raio de captura:** 35 m. **Fora da área:** morte em 10 s.
- **Dono inicial dos setores:** VC, VC, neutro, EUA, EUA.

| Lugar | X | Z |
|---|---|---|
| QG VC (oeste) | -2392,9 | -1892,9 |
| A Arrozais | -2053,6 | -1303,6 |
| B Serraria | -1767,9 | -2482,2 |
| C Vila | -1366,1 | -2000,0 |
| D Ponte e Cais | -1035,7 | -1303,6 |
| E Engenho | -625,0 | -2482,2 |
| QG EUA (leste) | -250,0 | -1892,9 |

Interiores, vegetação e relevo: [[Pipeline-Mapas]]. Desempenho medido: [[Performance-Baseline]].
