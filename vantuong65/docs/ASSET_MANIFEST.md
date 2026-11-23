# Manifesto de assets: área piloto da Vila

Gerado por `tools/manifesto_assets.py`.
Tamanhos, triângulos e colisões saem do `metricas.json`.
Trechos de cerca, trilhas e folhas têm a contagem final no log do jogo.

| Chave | Asset ID | Dimensões (m) | Triângulos | Colisões | Trim sheet | Cópias fixas |
|---|---|---|---:|---:|---|---:|
| `ret_vila_capim` | 113378259611458 | 3.3 × 0.9 × 3.3 | 136 | 0 | não | 0 |
| `ret_vila_carga` | 105429882255826 | 4.4 × 1.4 × 1.3 | 1116 | 6 | não | 6 |
| `ret_vila_cerca` | 94642387854419 | 4.0 × 1.3 × 0.1 | 84 | 1 | não | 0 |
| `ret_vila_detritos` | 99718967680023 | 3.6 × 0.0 × 3.6 | 2 | 0 | não | 0 |
| `ret_vila_dinh` | 119008876566197 | 21.6 × 7.4 × 13.4 | 13542 | 78 | sim | 1 |
| `ret_vila_palafita_a` | 128279811715114 | 12.3 × 8.1 × 12.5 | 15674 | 79 | sim | 4 |
| `ret_vila_palafita_b` | 118010616206508 | 9.7 × 7.5 × 11.7 | 11552 | 75 | sim | 5 |
| `ret_vila_passarela` | 96960290417727 | 6.0 × 0.5 × 1.4 | 404 | 1 | não | 0 |
| `ret_vila_poca` | 126564286703535 | 5.0 × 0.0 × 4.0 | 2 | 0 | não | 12 |
| `ret_vila_posto` | 132231703592408 | 17.5 × 6.5 × 4.3 | 7508 | 23 | não | 1 |
| `ret_vila_sacos` | 81587349783261 | 4.8 × 0.9 × 0.7 | 4096 | 2 | não | 7 |
| `ret_vila_terra` | 75564168564646 | 13.6 × 5.4 × 9.0 | 9302 | 63 | sim | 3 |
| `ret_vila_torre` | 82529998720270 | 5.1 × 9.5 × 9.9 | 8388 | 16 | não | 1 |
| `ret_vila_trilha` | 82488753059309 | 6.0 × 0.0 × 3.4 | 2 | 0 | não | 0 |

Soma de uma cópia de cada modelo: 71808 triângulos.

- **RenderFidelity:** `Automatic` (padrão), sem `Precise`.
- **SLIM:** ainda não. O SLIM só é gerado para modelos no arquivo do place,
  e o piloto é montado em tempo de jogo enquanto não for aprovado.
  Depois da aprovação ele entra na arte fixa.
- **Teste em jogo:** resultados em `docs/QA_RESULTS.md`.
