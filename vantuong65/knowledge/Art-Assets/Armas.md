---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Arte das armas

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Armas`.

- Mira da M16 e da SKS (D-236): `uv run --group arte python tools/mira_limpa.py` move só os vértices
  da linha de visada no GLB e mantém o UV dos acabamentos.
- Armas: `tools/armas_parker.py` gera `<arma>_studs_parker.glb` (aço fosco, texturas de 1024) a
  partir do GLB do gerador; é ele que sobe. Rode depois do `fetch_forgegui_assets.py`.
- Acabamentos de arma (D-178, D-179): a arte da arma é uma malha só, então o acabamento é uma
  textura inteira. `Skins.applyWeapon` clona a SurfaceAppearance pronta dele
  (`src/ReplicatedStorage/VT65AcabamentosSA.model.json`: a cor nova e o relevo e o material,
  novos ou os da arte em `assets/armas_pbr.json`); sem ela, troca o `TextureID`
  (`Shared/AcabamentosArte.luau`). O universal (D-179) tem uma textura por arma (`id@arma`).
  - Relevo: receita em `RELEVO` (mapa normal `<id>_n.png`); material em `CLASSE`/`CLASSES`
    (`classes/<arma>_<classe>_<alvo>_m/_r.png`); `assets/acabamentos_meta.json` guarda qual
    acabamento tem cada um;
  - arma nova ou refeita: releia no Studio os mapas da SurfaceAppearance dela para o
    `armas_pbr.json` (Server, `VT65WeaponArt`) e gere de novo;
  - `uv run --group arte python tools/acabamentos.py` pinta as que faltam (`--todas` refaz;
    `--mascaras` mostra madeira/metal/latão/pano) e faz prévias em
    `assets/acabamentos/previas`. Receita nova: `RECEITAS` no script e `arte` no `Skins`;
  - para o jogo: `--plano`, `upload-assets Acab.` (Decal), `--resolver <arquivo>` rodado no
    Studio (Server) e gravado com o
    `copia_da_conversa.py ... acab_imagens assets/acabamentos_imagens.json`, e `--luau`;
  - arma refeita (GLB novo)? Rode de novo: o cache sai do GLB, e as texturas também.
  - no Studio, cada textura nova no `TextureID` escreve 3 avisos "No asset content
    representation" no Output (com Image ou Decal, e mesmo pré-carregada); ela carrega e aparece.
- Armas do Blender (D-146): M70 e Mosin (`tools/blender/armas.py`), Escopeta 12 (`espingarda.py`),
  M16 (`m16.py`) e SKS (`sks.py`, no lugar da do gerador). Rode com
  `blender -b --factory-startup -P tools/blender/<arquivo>.py -- <chave>` (`--montar` para só a
  forma); os pontos saem em `assets/blender/arma_<chave>/pontos.json` e o `weapon_landmarks.py`
  os lê.
- Mira (D-67): `tools/sight_align.py` mede o centro do anel ou do entalhe e a ponta da massa na
  malha (M14, Type 56, RPD, M60; na M60 o modo "topo", D-119; a SKS agora é do Blender, D-146); o
  `weapon_landmarks.py` usa. `--side` desenha a arma de lado para
  achar as janelas de uma arma nova.
- Mira e mãos em 1ª pessoa (D-242): `adsEyeM`/`adsSobeM` na ficha (`Weapons`) e `ADS_MAO_BAIXA` no
  `WeaponVisuals`. Para ver todas: `VT65DevArma` = id (Server) e `Aiming = true` a cada quadro (Client); a luneta
  só abre pelo `VT65DevGranada = "mirar:<s>"`. Para olhar a 3ª pessoa, use bot ancorado do mesmo lado, senão ele
  é abatido na foto.
- Reflexo das skins (D-241): mude `CLASSES` no `tools/acabamentos.py` e rode `--so-classes`; tire as chaves
  `AcabM.`/`AcabR.` do `roblox_ids.json`, `upload-assets AcabM. AcabR.` e `--luau`. Para testar imagem no
  `PreloadAsync`, passe uma ImageLabel: com o texto do ID ele devolve Failure até em imagem boa.
- Arma nova: acrescente em `tools/weapon_landmarks.py` (frente e frações das mãos, vistas numa
  captura) e, se tiver alça de anel ou entalhe, as janelas em `tools/sight_align.py`. Rode o
  `weapon_landmarks.py` para regenerar `Shared/WeaponArt.luau`. Depois confira a mira no Studio
  (captura mirando): o anel ou o entalhe e a massa devem aparecer no centro sem nada tapando. Sem
  medida, ajuste `EYE_OFFSET_M` (D-60).
