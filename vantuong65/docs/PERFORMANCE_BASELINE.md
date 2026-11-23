# Desempenho: linha de base da V5

Medido em 2026-11-22 na v152 (antes de qualquer mudança da V5), no Studio, sem bots, com a câmera fixa a 1,7 m do
chão e janela de 671 × 525. Comparar por chamadas de desenho e triângulos.

## Limites desta medida
- `RenderCPUFrameTime` e `RenderGPUFrameTime` voltaram 0 no Studio. Tempo de quadro ainda não medido.
- O fps do Studio não vale: a janela fica atrás de outra e, às vezes, com outro jogo aberto no PC.
- Celular, tablet e servidor cheio não foram medidos.

## Qualidade 3
| Vista | Chamadas | Triângulos (milhões) |
|---|---:|---:|
| Base EUA | 267 | 2,99 |
| Vila C | 154 | 1,85 |
| Mata B | 214 | 2,84 |
| Ponte D | 232 | 1,70 |
| Arrozal A | 307 | 3,24 |
| Base VC | 343 | 3,34 |

## Qualidade 10
| Vista | Chamadas | Triângulos (milhões) | Sombra (chamadas) |
|---|---:|---:|---:|
| Base EUA | 406 | 5,68 | 41 |
| Vila C | 191 | 2,01 | 0 |
| Mata B | 320 | 5,33 | 0 |
| Ponte D | 301 | 3,52 | 0 |
| Arrozal A | 393 | 6,84 | 1 |
| Base VC | 433 | 5,73 | 0 |

Coração da vila (qualidade 8): 307 chamadas, 3,28 milhões de triângulos, 51 chamadas de sombra.
Memória total ao longo da medida: de 1.411 a 3.175 MB. Textura: de 534 a 728 MB.

## Depois do piloto
Comparação no mesmo build, com o piloto desligado e ligado, em `docs/QA_RESULTS.md`.
