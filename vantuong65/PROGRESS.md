# VẠN TƯỜNG '65 — Progresso

## Fase atual
- **F0 — Pesquisa: parcial** (sessão de 2026-11-09). Entregas prontas; o critério de aceite foi
  cumprido no setor oeste e ainda não foi verificado no setor leste.
- **Próxima: fechar a F0** (passos 6–9 de `research/F0_GEORREF.md`) e, depois da resposta à P1,
  começar a F1 (greybox).

## F0 — o que foi feito
1. **Fontes** (`research/F0_FONTES.md`): carta DMA L7014 6739 I ed. 3 (GeoPDF), *The First Fight*
   (2015), Copernicus GLO-30 e Sentinel-2 de 27/03/2025 obtidos. AAR do RLT-7, livro do USMC de 1978 e
   edição de 1965 da carta continuam bloqueados (motivos registrados).
2. **Georreferenciamento** (`research/F0_GEORREF.md`): cadeia carta → ING-A → WGS 84 → quadro local →
   studs, implementada em `tools/geo.py`, com correção medida no Sentinel-2.
3. **Locais reais** (`research/locais.csv` e `.geojson`): 19 pontos com grade de 1965, WGS 84 e
   coordenadas locais em m e studs.
4. **Heightmap 16-bit v0** (`research/heightmap/`): área de 5,0 × 3,4 km a 8 studs/px, mais o anel do
   horizonte de 14 × 14 km.
5. **Imagens de conferência** (`research/previews/`).
6. **ForgeGUI**: a run do Lote 1 foi conferida (2 prontos, 6 com falha retomável, 3 em
   `outcome_unknown`, 2 recusados). Nova tentativa recusada por falta de créditos (100 disponíveis,
   1.600 pedidos), registrada na run. `ASSETS.csv` foi criado.
7. **Ambiente**: criado e em uso o ambiente pessoal "a-o", que libera só os hosts das fontes de
   pesquisa.

## Resultados-chave (medidos)
| Medida | Valor |
|---|---|
| Resíduo do registro do GeoPDF (7 pontos) | 1,5–7,0 m |
| Grade impressa × registro | 5–11 m |
| Deslocamento ING-A → WGS 84 | −501,8 m E, +336,1 m N |
| Erro perpendicular bruto nos 3 controles da Rota 523 | 7,4 / 10,7 / 9,4 m |
| Correção 2D aplicada | −18,2 m E, +5,3 m N (19 m) |
| Colina 43 → Green Beach | 3.363 m (3.255 m no eixo L–O) |
| LZ Blue → Green Beach | 3.001 m |
| Colina 43 → LZ Blue / LZ Blue → Nam Yên (3) | 424 m / 224 m (o texto diz ~400 m / 100–200 m) |
| An Cường (2) → Colina 30 | 596 m (o prompt diz ~400 m) |
| Testes da pasta `vantuong65` | `pytest`: 8 passed; `ruff check`: limpo |

## Suposições registradas (DESIGN.md)
D-01 (projeto em subpasta), D-03 (área de 4,0 × 2,4 km, pendente), D-05 (Green Beach em An Cường 1 e
duas trincheiras), D-06 (heightmap do DSM como provisório), D-07 (sebes de 1,8–2,4 m nos arrozais,
pendente), D-08 (setores com fronteiras desiguais), D-09 (as capturas enviadas só como referência de
luz).

## Problemas
1. A carta obtida é a **edição de 1983**, não a de 1965. O uso do solo precisa da edição 1 ou de
   CORONA.
2. **USMCU e marines.mil respondem 403** (WAF) a qualquer cliente automatizado. A PCL/UT exige
   navegador (Anubis). O Commons deu 429 nesta sessão.
3. O **ForgeGUI está sem créditos**, e o host de arquivos dele está bloqueado pela rede desta sessão.
4. O critério de 25 m ainda **não foi verificado no setor leste**.

## Perguntas que bloqueiam (resposta do usuário)
- **P1 — tamanho do mapa:** 4,0 × 2,4 km em 1:1 com todos os locais (recomendado), 2,2 × 2,2 km só
  no oeste (sem praia), ou 2 × 2 km só no leste (sem Colina 43)? Detalhes em DESIGN D-03.
- **P2 — créditos do ForgeGUI:** recarregar (a prioridade está em DESIGN D-10, cerca de 30 mil
  créditos para destravar o Lote 1) ou seguir com placeholders até a F3?
- **P3 — PDFs bloqueados:** dá para baixar no navegador e colocar em `vantuong65/research/src/` (são
  de domínio público): o AAR do RLT-7, o livro de 1978 e a folha 6739 I edição 1 da PCL?
- **P4 — CORONA e imagem de alta resolução:** você tem ou cria uma conta gratuita no USGS
  EarthExplorer para baixar os quadros de 1965–67, ou prefere licenciar uma ortofoto atual de ≤ 1 m?
- **P5 — repositório:** mover o jogo para um repositório próprio antes da F1?

## Próximos passos
1. Com a P3 respondida: extrair as grades do AAR e fechar LZ Blue, trincheira e Green Beach.
2. Vetorizar as curvas de 20/10 m e gerar o DTM (passo 6).
3. Pontos de controle no setor leste (passo 7) e uso do solo de 1965 (passo 8).
4. Com a P1 respondida: abrir a F1, com Rojo, greybox, import do heightmap e medição de fps.
