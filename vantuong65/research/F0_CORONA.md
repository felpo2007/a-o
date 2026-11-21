# Fotos de satélite CORONA (1965–67): como baixar no USGS EarthExplorer

Para que servem:
- fechar o critério de 25 m no setor leste (passo 7 de F0_GEORREF);
- vetorizar o uso do solo de 1965 (passo 8), porque a carta que temos é a edição de 1983.

Eu não consigo entrar na sua conta, e você não deve colar senha nem token no chat. O download é
seu; a partir dos arquivos, o resto fica comigo.

## Passo a passo (cerca de 10 min)
1. Entre em <https://earthexplorer.usgs.gov/> com a sua conta.
2. Na aba **Search Criteria → Polygon**, informe os 4 cantos (graus decimais, WGS 84). Eles cobrem a
   área jogável com 1 km de folga:

   | Canto | Latitude | Longitude |
   |---|---|---|
   | NO | 15.3400 | 108.8150 |
   | NE | 15.3400 | 108.8900 |
   | SE | 15.2700 | 108.8900 |
   | SO | 15.2700 | 108.8150 |

3. **Date Range**: de 01/01/1965 a 31/12/1967. Com poucas cenas, amplie até 1969.
4. Aba **Data Sets → Declassified Data**: marque **Declassified Satellite Imagery - 1** (CORONA,
   ARGON, LANYARD) e também **Declassified Satellite Imagery - 2** (KH-7/KH-9).
5. Na aba **Results**, dê preferência às missões **KH-4A** e **KH-4B** (1965–67, ~2–3 m) e a quadros
   com pouca nuvem. O ícone de "olho" mostra a prévia.
6. Baixe o arquivo de maior resolução de 1 a 3 quadros. Os que dizem "Download available" são
   gratuitos. Os de "scan on demand" podem levar dias e às vezes são pagos: só peça se não houver
   outro.
7. Coloque os arquivos (`.tif` e `.tgz`) em `vantuong65/research/src/corona/` e me avise. A pasta já
   está no `.gitignore`, porque os arquivos são grandes.

## O que faço com eles
- Georreferencio na carta e no Sentinel-2 com 15 ou mais pontos e transformação polinomial (os
  quadros CORONA têm distorção panorâmica).
- Meço o erro nos pontos de controle do setor leste, onde a carta ainda não foi verificada.
- Vetorizo arrozais, sebes, vilas e dunas de 1965 e substituo a classificação da carta de 1983 no
  exportador (`tools/landcover.py`).
