---
project: STARLITE
type: map
status: verified
source_paths:
  - src/ReplicatedStorage/Shared/MapasRet.luau
  - tools/mapas_ret.py
last_verified: 2026-11-22
verified_commit: 5d59912
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

## Cenas (D-251)
| Setor | Lugar | Marcos (`tools/blender/ret_comboio.py`) |
|---|---|---|
| A | Arrozais das Comportas | `ret_comp_bomba`, `ret_comp_celeiro`, `exp_comporta` |
| B | Vila do Sino Baixo | `ret_sino_salao`, `ret_sino_loja_a`, `ret_sino_loja_b` |
| C | Ponte do Canal Torto | `ret_canal_ponte`, `ret_canal_oficina`, `ret_comp_bomba` |
| D | Serraria | `ret_serra_galpao`, `ret_serra_portico`, `ret_serra_toras`, `ret_serra_secagem` |
| E | Engenho do Espigão | `ret_esp_armazem`, `ret_esp_chamine` |

- Monte perto da estrada com `na_rua` (`u` ao longo da pista, `lado`, `folga`). Na curva em U, o prédio
  grande vai do lado de fora.
- A ponte é só arte: a colisão fica no `MapaPontes` (`arte = true`).
- Medido: entrega em cerca de 290 s; 16 de 16 e 18 de 18 bots andando. Fichas em
  `testes/LOTE120_D251-252_2026-11-22.md`.

## Avisos atuais do gerador
Um conjunto de nascer sem lugar em s = 712, lado -1 (restam 31, o mínimo é 16).
