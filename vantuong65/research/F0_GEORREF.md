# F0 — Plano de georreferenciamento e resultados medidos

Todos os números abaixo saíram dos scripts de `tools/`, rodados em 2026-11-09. Para reproduzir:
`tools/fetch_sources.sh` e depois os comandos da seção 5.

## 1. Cadeia de coordenadas

```
carta L7014 6739 I (GeoPDF)        Indian 1960 "ING-A" / UTM 49N (Everest 1830)  = grade impressa "BS"
   │  1. afim do LGIDict (7 pontos de registro do próprio PDF)
   ▼
GeoTIFF da carta (EPSG:3149)
   │  2. troca de datum TR8350.2 ING-A -> WGS 84: dX=198, dY=881, dZ=317 m (±25–44 m nominal)
   │  3. correção empírica medida no Sentinel-2: dE −18,2 m, dN +5,3 m
   ▼
WGS 84 / UTM 49N (EPSG:32649)       = DEM Copernicus, Sentinel-2, GPS
   │  4. translação para o centro da área jogável; x = leste, z = SUL (−Z = norte no Roblox)
   ▼
quadro local (m)  ── ÷ 0,28 ──►  studs
```

Implementação: `tools/geo.py`. Escolhemos a transformação de 3 parâmetros de forma explícita
(`+towgs84=198,881,317`). Usar só `EPSG:3149` deixaria o PROJ escolher entre três transformações
diferentes.

## 2. Resultados

| Passo | Medida | Resultado |
|---|---|---|
| 1. Afim do LGIDict | Resíduo nos 7 pontos de registro | **1,5 / 5,0 / 4,9 / 1,7 / 5,2 / 7,0 / 3,1 m** |
| 1. Cantos da folha | Pontos de registro × graticule 15°15′–15°30′ N, 108°45′–109°00′ E projetado em Everest/UTM 49 | **0,0 m**: o registro está no datum da própria carta |
| 1. Grade impressa | 621 cruzamentos detectados automaticamente (`detect_grid.py`) × afim do LGIDict | Diferença de **5–11 m** em três pontos de amostra. O RMS do ajuste (17 m E / 35 m N, máximo de 167 / 269 m) vem de detecções falsas (texto e estradas pretas), não da carta. Confirmado à vista no cruzamento 269/1692 |
| 2. Troca de datum | Deslocamento ING-A → WGS 84 na área | **dE −501,8 m, dN +336,1 m** (cerca de 600 m). Uma grade de 1965 "BS xxxyyy" lida direto como WGS 84 erra por esse valor |
| 3. Controle (estradas) | Transectos perpendiculares em 3 trechos da Rota 523 (100 + 47 + 21 transectos, ±60 m, passo de 1 m), carta × Sentinel-2 | Erro perpendicular **antes** da correção: **−7,4 m, −10,7 m e +9,4 m**. Deslocamento 2D ajustado: **dE −18,2 m, dN +5,3 m (19 m)**. Resíduo depois da correção: 0,1–0,3 m, com só 1 observação redundante |
| Rejeitado | Cumes do DEM × cotas da carta (43, △45, △22, △10) | Diferenças de 105–199 m em direções diferentes: o DSM marca o topo das copas, não o cume. Não serve de ponto de controle |
| Rejeitado | Casamento de chanfro: curvas da carta × isolinhas do DEM, e costa rochosa da carta × NDWI | Os dois sinais discordam: (−20, +60) m contra (+80, −160) m. São ruidosos demais (DSM; costa em 1D) |

**Critério da F0 ("erro < 25 m nos pontos de controle"): atendido em parte.**
- Atendido no setor oeste: nos três pontos de controle da Rota 523 o erro bruto ficou entre 7 e 11 m, e o deslocamento total estimado em 19 m.
- **Não verificado no setor leste** (praia, An Cường): não achei ali feições nítidas e estáveis desde 1983 que o Sentinel-2 de 10 m resolva. A costa arenosa mudou, e a costa rochosa só restringe uma direção.
- A correção de (−18, +5) m vem de três trechos de estrada com orientações parecidas. Ela restringe bem a direção NE–SO e pouco a NO–SE.

## 3. Locais reais medidos

Estão em `research/locais.csv` e `research/locais.geojson`: 19 pontos com grade de 1965, lat/lon WGS 84,
UTM WGS 84, quadro local (m e studs), precisão de leitura e fonte. Distâncias calculadas:

| Par | Distância | Leste–oeste |
|---|---|---|
| Colina 43 → Green Beach | **3.363 m** | 3.255 m |
| LZ Blue → Green Beach | **3.001 m** | 2.950 m |
| Colina 43 → LZ Blue | 424 m (az. 46°) | H1 diz "~400 m a SW" da LZ ✔ |
| LZ Blue → Nam Yên (3) | 224 m (az. 27°) | H1 diz "100–200 m ao norte" ✔ (no limite) |
| An Cường (2) → Colina 30 | 596 m (az. 17°) | o prompt diz "cerca de 400 m ao norte" ✘ (a carta mostra cerca de 600 m) |
| An Cường (1) → △22 | 388 m (az. 12°) | H1: "high ground immediately beyond the village, which included Hill 22" ✔ |
| An Cường (1) → An Cường (2) | 1.597 m | |

**Conflito com o prompt:** a área de 2,0 × 2,0 km não comporta ao mesmo tempo a Green Beach na borda leste e a
Colina 43 na borda oeste. A distância leste–oeste real é de cerca de 3,3 km, e de cerca de 3,9 km contando
as encostas e a faixa de mar. O prompt também diz que a LZ Blue fica "cerca de 2 km a oeste da praia";
a carta dá 2,95 km. Isso virou a pergunta P1.

## 4. Heightmap v0

`research/heightmap/heightmap_area_v0.png`: 16-bit, 2232 × 1518 px, 8 studs/px (2,24 m), cobrindo
5,0 × 3,4 km (a área jogável proposta de 4,0 × 2,4 km mais 500 m de margem). As alturas vão de
−0,2 a 78,0 m, com os metadados no `.json` ao lado. O anel do horizonte (`heightmap_horizonte_v0`)
tem 14 × 14 km a 30 m/px.

Limites que precisam ficar claros:
1. O GLO-30 é DSM. A abertura morfológica de 70 m remove copas e casas isoladas, mas o resultado
   ainda não é o terreno nu.
2. 30 m de resolução não mostram diques, sebes nem túmulos: esses entram esculpidos à mão, como o
   prompt manda.
3. Ainda não confirmei se o importador de heightmap do Studio aceita PNG de 16 bits nesse tamanho.
   É a primeira verificação da F1.

## 5. Plano de georreferenciamento (passos e estado)

1. ✔ Baixar a carta GeoPDF (C1), rasterizar a 300 dpi (`pdftoppm`) e georreferenciar pelo LGIDict
   (`tools/georef_carta.py`).
2. ✔ Validar a grade impressa contra o registro (`tools/detect_grid.py`, `tools/grid_crop.py`).
3. ✔ Trocar o datum com parâmetros explícitos (`tools/reproj_carta.py`) e sobrepor ao Sentinel-2
   (`tools/overlay.py`).
4. ✔ Medir os pontos de controle por transectos de estrada (`tools/road_transects.py`) e aplicar a
   correção em `tools/geo.py`.
5. ✔ Ler os locais reais na carta com quadrícula de 100 m e cruzar com o texto de H1
   (`tools/make_locais.py`).
6. ☐ **DTM de 1965**: vetorizar as curvas de 20/10 m e as cotas da carta (C2, a edição de 1965,
   quando ela vier) e interpolar o terreno nu. O GLO-30 fica só para conferência. Prazo: começo da
   F1.
7. ☐ **Controle no setor leste**: 4 ou mais pontos com imagem de ≤ 1 m (ortofoto ou imagem comercial
   que o usuário possa licenciar) ou com CORONA de 1965–67 (C7), para fechar o critério de 25 m na
   praia e em An Cường (1).
8. ☐ **Uso do solo de 1965 vetorizado**: polígonos de arrozal, vila, mata/sebe, duna e água digitalizados
   da C2/C7 (a C1 é de 1983) e conferidos com as fotos de Starlite.
9. ☐ **Grades do AAR (H4)**: converter as referências "BS xxxyyy" do relatório com `geo.ing_to_wgs_utm`
   para fechar a posição da LZ Blue, da trincheira e da extensão da Green Beach.

## 6. Imagens de conferência

- `research/previews/carta_L7014_ed3_area_proposta.jpg`: carta (ed. 3, 1983) com a área proposta e os locais.
- `research/previews/carta_L7014_ed3_sobre_sentinel2.jpg`: traço da carta (vermelho = preto da carta,
  amarelo = curvas, azul = água) sobre o Sentinel-2 de 27/03/2025, com quadrícula WGS 84 de 500 m.
- `research/previews/heightmap_v0_relevo.jpg`: relevo sombreado do heightmap v0 com a área e os locais.

As duas primeiras usam a edição de 1983 (C1) e serão regeradas quando a edição de 1965 (C2) for
obtida.
