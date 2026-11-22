---
project: STARLITE
type: map
status: verified
source_paths:
  - src/ReplicatedStorage/Shared/MapasRet.luau
  - tools/mapas_ret.py
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Estrada do Bambu (Comboio)

900 × 300 m, sem publicar. Peças atuais: `uv run python tools/kb.py mapa comboio <setor>`.

## Percurso (planta, em metros)
N1 (40,120), N2 (125,170), **N3 (215,115) CP1**, N4 (310,205), N5 (400,155), **N6 (480,105) CP2**,
**N7 (575,200) CP3**, N8 (670,135), N9 (770,195), **N10 (850,150) entrega**.
Bases fora da estrada: oeste (20,168), leste (882,104). Ponte em (440,130). Lomba em (527,5, 152,5).

## Regras (de `MapasRet.COMBOIO.regras`)
Velocidade 3,8 m/s; 18 m entre veículos; escolta a 14 m; contesta a 10 m; checkpoint 8 s; dano 10
por segundo; integridade 100; imobilizado 15 s; reparo 6 s por pessoa, até 2; recupera 25; proteção
20 s; rodada de 9 min; onda de 10 s.

## Medido no Studio (`testes/D-243_parte2_2026-11-22.md`)
Trajeto de 1.011,91 m; entrega em 283 s; caminhões a 17,5-18,2 m entre si.

## Cenas planejadas (ainda não construídas)
Arrozais das Comportas, Vila do Sino Baixo, Ponte do Canal Torto, Serraria e Engenho do Espigão.
Especificação: `especificacao/mapas_retangulares/PROMPT.txt` (fora do Git). Hoje o mapa usa casas
genéricas. Reaproveite o método do [[Vale-das-Cinco-Passagens]].

## Avisos atuais do gerador
CP2 com 10 de 13 casas, ENT com 11 de 13, e um conjunto de nascer sem lugar em s = 278, lado -1.
