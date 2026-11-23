---
project: STARLITE
type: baseline
status: stale
source_paths:
  - src/ServerScriptService/Modules/ArtBudget.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Linha de base de desempenho

**Última medida completa: 2026-11-15 (v82-v83), só no mapa principal.** O jogo mudou muito depois:
trate como referência de método. Os mapas retangulares **não foram medidos**. 60 FPS é meta, não
resultado comprovado.

## Método (`testes/DESEMPENHO_2026-11-15.md`)
- **Plataforma:** PC do dono, Studio pelo MCP, sem bots, GPU de 2 GB.
- **Seis vistas fixas** a 1,7 m do chão; qualidade fixa nos níveis 3 e 10.
- **Compare** chamadas de desenho e triângulos, com A/B na mesma vista. O Studio atrás de outra janela
  trava em 15 fps, então esse fps não vale.

## Medições de 2026-11-15, nível 3 (milhões de triângulos por quadro, v83)
Base EUA 2,47; vila 1,19; mata B 1,98; ponte D 1,55; arrozal A 2,41; base VC 2,16.

## O que se aprendeu
- **Peso maior:** casas e objetos, depois bambu, capim-elefante e bananeira.
- **Não era gargalo:** transparência das folhas (menos de 1 ms de GPU) e física (0,045 ms por passo
  com 25.301 peças paradas). O teste foi só no Studio.
- **Um objeto repetido pode custar caro:** a cerca de bambu tinha 16.418 triângulos em 62 cópias.
- **Textura (D-168):** na vista do QG dos EUA, textura de modelo era ~23 MB de ~133 MB.

## Orçamentos (`ArtBudget.luau`)
Vegetação até 6 mil triângulos; props e heróis até 20 mil.

## Falta medir
Fps em celular e tablet, servidor cheio, memória nos mapas retangulares.
Arte fixa e SLIM: [[Arte-Fixa-e-Texturas]].
