"""Recorte do fundo do lobby (D-222).

O Roblox limita cada imagem a 1024: o render de `tools/blender/lobby_fundo.py` vai em 4 blocos de
1024 x 576, que o `Controllers/FundoLobby` junta na tela.

Uso: uv run --group arte python tools/lobby_recorta.py <render.png>
Saída: assets/ui/lobby/fundo.png e assets/ui/lobby/lobby_{nw,ne,sw,se}.png
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

SAIDA = Path(__file__).resolve().parent.parent / "assets" / "ui" / "lobby"
TAM = (2048, 1152)


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("uso: lobby_recorta.py <render.png>")
    final = Image.open(sys.argv[1]).convert("RGB")
    if final.size != TAM:
        final = final.resize(TAM, Image.LANCZOS)
    SAIDA.mkdir(parents=True, exist_ok=True)
    final.save(SAIDA / "fundo.png", optimize=True)
    w, h = final.size
    for nome, x, y in (("nw", 0, 0), ("ne", w // 2, 0), ("sw", 0, h // 2), ("se", w // 2, h // 2)):
        final.crop((x, y, x + w // 2, y + h // 2)).save(SAIDA / f"lobby_{nome}.png", optimize=True)
    print("ok", final.size, sorted(p.name for p in SAIDA.glob("*.png")))


if __name__ == "__main__":
    main()
