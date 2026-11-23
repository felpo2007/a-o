"""Faixa de fundo do destaque da loja (D-124): recorte da capa do jogo (`assets/capa`, feita pelo
`tools/blender/capa.py` com os modelos do próprio projeto) na proporção do destaque (~2,86 : 1).

Uso:
    uv run --group arte python tools/loja_banner.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parents[1]
FONTE = RAIZ / "assets" / "capa" / "capa_espaco_titulo_1920x1080.png"
SAIDA = RAIZ / "assets" / "ui" / "loja" / "destaque.png"
LARG, ALT = 1024, 358  # proporção do destaque da loja (676 x 236 px no PC)


def main() -> None:
    im = Image.open(FONTE).convert("RGB")
    w, h = im.size
    alt = round(w * ALT / LARG)  # largura inteira; a faixa de baixo tem a vila, o dique e o arrozal
    topo = h - alt - round(h * 0.06)
    faixa = im.crop((0, topo, w, topo + alt)).resize((LARG, ALT), Image.LANCZOS)
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    faixa.save(SAIDA, optimize=True)
    print(SAIDA, faixa.size, "recorte y", topo, "a", topo + alt)


if __name__ == "__main__":
    main()
