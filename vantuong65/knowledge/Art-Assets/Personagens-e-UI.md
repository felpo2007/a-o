---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Arte de personagens e interface

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Personagens-e-UI`.

- Rostos e uniformes (D-236): `uv run --group arte python tools/rostos/make_rostos2.py` e
  `tools/make_clothing_v4.py` (tipo Image: o ID vai direto). As roupas são as chaves `Clothing.*_v3`
  do plano, com o arquivo em `assets/clothing/v4`. O rosto fica na peça `Head.Rosto`: um Decal na
  cabeça padrão sai torto, porque ela é malha e segue o UV.
- Rostos estilo Roblox (D-237): `uv run --group arte python tools/rostos/make_rostos3.py` (`Rostos3.f_NN`,
  usados em `Corpo.ROSTOS`). Ganhos e promoção: `Controllers/GanhoFx`; no Studio, `VT65DevGanho` =
  `"ganho"` ou `"promocao"` (Client).
- Corrida, rastejo e recarga (D-238): `Shared/Passada3P` e `Shared/Recarga`. Para congelar a pose no Studio
  (Client): no soldado, `VT65DevPassada` = `"c;<fase>;<m/s>"` ou `"r;<fase>"` e `VT65DevRecargaP` = fração;
  em 1ª pessoa, `workspace.VT65DevRecarga1P` = fração. Fotografe um bot ancorado: o próprio vira com a câmera,
  e o bot volta a ficar de pé se a postura não for regravada a cada quadro.
- Prêmios da recompensa (D-236): `tools/blender/recompensas.py -- todas` (CPU, `VT65_CPU=1`).
- Imagens das caixas (D-212): `tools/blender/caixas_loja.py -- todas` (CPU, `VT65_CPU=1`) gera
  `assets/ui/caixas/<id>.png`. Caixa nova:
  - ponha a receita em `CAIXAS` no script;
  - ponha a entrada no `assets/upload_plan.json` (`CaixaLoja.<id>`) e suba com
    `upload-assets CaixaLoja.`;
  - ponha o ID em `AssetIds.CaixaLoja`. O servidor resolve a imagem (`ImgCaixa_<id>`) e o
    `Controllers/CaixaImagem` desenha.
  - D-213: `-- todas --aberta` gera as duas camadas da caixa aberta (`<id>_corpo`, `<id>_tampa`),
    no enquadramento da fechada; `--so-topo` refaz só o degradê do alto do corpo. Suba como
    `CaixaLoja.<id>_corpo`/`_tampa`.
  - O `upload-assets` só troca o número de chave que já existe no `AssetIds.luau`: chave nova, ponha
    a linha (com o ID do `roblox_ids.json`) à mão.
- Emblemas (D-218): `tools/blender/emblemas.py -- todos --amostras 48`; caixa por língua (D-219):
  `tools/blender/caixas_loja.py -- todas --idiomas` (os PNG ficam fora do Git). Cenário do pódio
  (D-221): `uv run --group arte python tools/podio_fundo.py`.
- Bandeiras dos times (D-240): `tools/blender/bandeiras_epicas.py us vc --saida <pasta>` (depois de `--`) e
  `uv run --group arte python tools/bandeiras_pos.py`; o final vai em `assets/ui/times`. Comemoração: `Controllers/PodioEpico`.
  ViewportFrame parou de desenhar no Studio, até com um cubo num quadro novo? Reabra o Studio.
- Efeitos de interface (D-213, `Controllers/UiEfeitos`): as texturas saem de
  `uv run --group arte python tools/efeitos_ui.py` (`Images.efeito_*`, atributo `Img_efeito_*`).
  Os sons da abertura saem de `blender -b --factory-startup -P tools/sons_roleta.py -- caixa_`.
- Imagens da loja (D-124): a imagem mostra só o que o item dá.
  1. `blender -b --factory-startup -P tools/blender/loja.py -- todas` (Blender 5.3 em
     `C:\Program Files\Blender Foundation`);
  2. `uv run --group arte python tools/loja_sombra.py` (tira o véu de alfa da sombra) e
     `tools/loja_banner.py` (faixa da capa para o destaque);
  3. suba com `upload-assets Loja.`, resolva o ID da imagem de cada decal no Studio (InsertService)
     e grave em `AssetIds.LojaImages`.
- Imagens de catálogo (D-222 a D-229), CPU com `VT65_CPU=1`:
  - `tools/blender/visuais_catalogo.py -- todas` (D-239: visuais do Armário, camuflagens e vantagens, `Catalogo.vis_*`);
  - `tools/blender/armas_catalogo.py -- todas` (armas, equipamento, classes, times, prêmios);
  - `tools/blender/skins_catalogo.py` (347 acabamentos; `--reusar` refaz só a combinação);
  - `tools/blender/lobby_fundo.py` e `uv run --group arte python tools/lobby_recorta.py <png>`;
  - `uv run python tools/mapa_aereo.py` (a carta aérea, `AssetIds.CartaImages`). Mudou o mapa? Refaça;
  - para o jogo: `uv run python tools/catalogo_imagens.py plano`, `upload-assets Catalogo.` e
    `uv run python tools/catalogo_imagens.py ids`. Sobem como Image: o ID vai direto na ImageLabel.
