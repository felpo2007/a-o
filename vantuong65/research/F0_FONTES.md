# F0 — Fontes encontradas (bibliografia de trabalho)

Sessão de 2026-11-09. Legenda de status:
- **obtida**: arquivo baixado e lido por código nesta sessão;
- **bloqueada**: existe, mas o acesso falhou daqui (o motivo está anotado);
- **a buscar**: identificada, ainda não tentada.

Nenhum número dos documentos do projeto vem de fonte marcada como bloqueada ou "a buscar".

## 1. Cartografia

| # | Fonte | Status | O que dá | Observações |
|---|---|---|---|---|
| C1 | **DMA, Series L7014, folha 6739 I "Bình Sơn", 1:50.000, Edição 3-DMA**. GeoPDF do USGS/NGA: <https://store.usgs.gov/assets/yimages/NGA/L701467391_geo.pdf> | **obtida** (9,5 MB) | Carta georreferenciada da área inteira da batalha: vilas e números entre parênteses, cotas, curvas, trilhas, riachos, matas, arrozais e praia | Na margem: "**Compiled in 1983 from best available source**", impressa pelo DMAHTC em 4-85. Datum horizontal **Indian 1960**, elipsoide **Everest**, grade UTM zona 49 (quadrados **BS**/BT), datum vertical: nível médio do mar em Hà Tiên. **Curvas de 20 m, suplementares de 10 m.** Declinação da grade: convergência de 0°34′ no centro da folha. **Não é uma carta de 1965**: serve de base geométrica, mas o uso do solo tem de ser conferido com C2/C3. |
| C2 | AMS, Series L7014, folha 6739 I, **edição 1** (1965–66) | **não encontrada** | A mesma folha no estado mais próximo de agosto de 1965 | A PCL/UT lista "Binh Son 6739-1", mas essa cópia é a ed. 3 de 1983 (ver C3; o site exige navegador por causa do Anubis). Texas Tech tem folhas L7014 de dez/1965 da coleção Cossaboom, mas o host falha no TLS pelo proxy desta sessão. |
| C3 | Wikimedia Commons, "File:Map by the US Army Map Service - Binh Son - - vietnam - binh son-6739-1.pdf" (origem: PCL/UT) | **conferida** | Nada de novo | Tem **9.527.168 bytes**, o mesmo tamanho do GeoPDF de 1983 (C1). É a mesma edição 3, não a de 1965 (DESIGN D-19). |
| C4 | Mapas da operação em *The First Fight* (ver H1): situação às 13:00 de 18/08 (PDF p. 28) e fases seguintes (PDF p. 20, 22, 35, 41, 48) | **obtida** | LZ Red/White/Blue, Green Beach, Phase Lines Apple/Banana, posições das companhias | Mapas "adapted by Marine Corps History Division", com escala gráfica de 1.000 m e sem quadrícula |
| C5 | Copernicus DEM **GLO-30** (DSM, 30 m), tile N15 E108: `s3://copernicus-dem-30m/Copernicus_DSM_COG_10_N15_00_E108_00_DEM/` | **obtida** (32,9 MB) | Relevo para o heightmap v0 | É modelo de **superfície** (copas e telhados entram). Exige atribuição: © DLR e.V. 2010-2014 e © Airbus Defence and Space GmbH 2014-2018, Copernicus/ESA. |
| C6 | Sentinel-2 L2A, cena **S2C_49PBS_20250327** (nuvens 0,95%), COGs públicos em `sentinel-cogs` (AWS) | **obtida** (recortes TCI, B03, B08) | "Satélite" de 10 m usado no controle do georreferenciamento e na linha d'água atual (NDWI) | Resolução de 10 m: limita a precisão dos pontos de controle visuais |
| C7 | Fotografia de satélite CORONA (KH-4/KH-4A, 1965–67), USGS EarthExplorer, coleção "Declassified Data" | **aguardando o usuário** (ele tem conta) | Uso do solo real de 1965–67 (arrozais, sebes, vilas) a ~2–3 m | Passo a passo em `research/F0_CORONA.md` |
| C8 | SRTM 1 arc-second (30 m) | **a buscar** | Segundo DEM para comparação (também é DSM, de 2000) | Opcional |

## 2. Histórico e operação

| # | Fonte | Status | O que dá |
|---|---|---|---|
| H1 | Andrew Jr., Rod (Col., USMCR). ***The First Fight: U.S. Marines in Operation Starlite, August 1965.*** Marines in the Vietnam War Commemorative Series. Quantico: History Division, Marine Corps University, 2015. ISBN 978-0-16-092879-6. Cópia FDLP: <https://permanent.fdlp.gov/gpo62355/Starlite_TheFirstFight2.pdf> | **obtida** (66 p.) | Narrativa com localização (citações abaixo) e mapas da operação. A bibliografia remete aos AARs e às *command chronologies* |
| H2 | Mesmo livreto no site da USMCU: <https://www.usmcu.edu/Portals/218/The_First_Fight_Starlite.pdf> | **bloqueada** (Akamai "Access Denied" por IP, inclusive em navegador real) | Duplicata de H1 |
| H3 | Shulimson, J. & Johnson, C. M. *U.S. Marines in Vietnam: The Landing and the Buildup, 1965.* History and Museums Division, HQMC, 1978. <https://www.marines.mil/Portals/1/Publications/U.S.%20Marines%20in%20Vietnam_The%20Landing%20and%20the%20Buildup%201965%20%20PCN%2019000307600_3.pdf> | **bloqueada** (Akamai "Access Denied" por IP, inclusive em navegador real; o espelho purl.fdlp.gov/GPO/gpo82174 está fora da lista de hosts) | Capítulo Starlite (citado no prompt) |
| H4 | RLT-7, *After Action Report (Operation Starlite)*, 31 ago. 1965. <https://www.usmcu.edu/Portals/218/Regimental%20Landing%20Team-7%20%20After%20Action%20Report%20%28Operation%20Starlite%29%2C%2031%20August%201965.PDF> | **bloqueada** (Akamai "Access Denied" por IP, inclusive em navegador real; sem espelho conhecido) | Referências de grade da época (objetivos, LZs, linhas de fase): é a fonte para fechar a posição da LZ Blue, da trincheira e da extensão da Green Beach |
| H5 | *Command chronologies* de 3/3, 2/4, 3/7 e RLT-7 (ago. 1965), Vietnam Center & Archive / Texas Tech: <https://vva.vietnam.ttu.edu/> | **bloqueada** ("unable to get local issuer certificate" pelo proxy; não desliguei a verificação TLS) | Grades e horários por companhia |
| H6 | VFW Magazine, "VC 'Soundly Defeated' at Chu Lai" (citado no prompt para dunas e An Cường 2) | **a buscar** (host liberado) | Dunas de ~180 m e casas de An Cường 2 |
| H7 | HistoryNet (citado no prompt para a trincheira VC) | **a buscar** (host liberado) | Trincheira entre a praia e Vạn Tường (1) |
| H8 | Lehrack, Otto J. *The First Battle: Operation Starlite and the Beginning of the Blood Debt in Vietnam.* Casemate, 2004 | **a buscar** (livro) | Citado por H1 como referência popular principal |
| H9 | operationstarlite.com, "guide" | **bloqueada** (DNS não resolve; site possivelmente fora do ar) | Segundo a busca web, lista grades como BS 698926 e BS 702929. Não lido; sem uso nos números |
| H10 | Fotos do NARA (catalog.archives.gov) e do USMC sobre Starlite | **a buscar** (host liberado) | Dossiê de fotos (Parte 9, item 1) |

### Citações de H1 usadas nos dados (página = página do PDF)

- **Sebes** (PDF p. 10): "Even the rice paddies were divided and segmented by hedgerows **six to eight feet high** consisting of bamboo thickets and hardwood trees". Isso dá **1,8–2,4 m**, enquanto o prompt fala em 3–8 m (ver DESIGN D-07).
- **Desembarque** (PDF p. 21): "Companies K and I ... landed as planned at **0630** on 18 August"; a praia não foi bombardeada "because of the danger to the nearby village of **An Cuong (1)**". A Cia K tomou "the high ground immediately beyond the village, which included **Hill 22**" (a △22 da carta, 390 m a NNE de An Cường (1)).
- **Trincheira do avanço da Cia K** (PDF p. 21): a Cia K virou para o norte e avançou "nearly two kilometers inland from the beach" até ser parada por "a trench line in their front". Isso a põe cerca de 2 km ao norte de An Cường (1), fora da área proposta (ver D-05).
- **Trincheira de An Cường (2)** (PDF p. 23): "There was a wide, deep trench south of the village"; An Cường (2) era "a heavily wooded village fortified with trench lines covered with branches and log[s]" (PDF p. 25).
- **LZ Blue** (PDF p. 29): "just south of Nam Yen (3) ... The village was only **100–200 meters north** of the landing zone, while a small knoll, **Hill 43**, was approximately **400 meters to the southwest**. The other high ground that overlooked the landing zone was **Hill 30, just north of the village of An Cuong (2)**."
- **Riacho** (PDF p. 27): "the streambed just east of An Cuong (2)".
- **Nome da praia** (PDF p. 18): "Green Beach at An Cuong (2)\*". Isso contradiz PDF p. 21, onde o desembarque é junto a An Cường (1). Pela carta e pela △22, adotamos An Cường (1) (ver D-05).

## 3. Texturas, céu e áudio (fases F1+)

| # | Fonte | Status |
|---|---|---|
| T1 | Poly Haven (texturas e HDRI CC0) | **bloqueada** pela rede (host fora da lista); entra na F1/F3 |
| T2 | ambientCG (texturas CC0) | **bloqueada** pela rede; entra na F1/F3 |
