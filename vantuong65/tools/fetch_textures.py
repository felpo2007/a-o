"""Baixa as texturas do chão (D-66) do Poly Haven: PBR fotográfico, licença CC0.

Mapas de cor, normal (OpenGL) e rugosidade em 1k (o máximo que o Roblox usa por imagem é 1024 px).
Saída: assets/texturas/<id>_<mapa>.jpg (fora do Git; refaça com este script).

Uso: uv run python tools/fetch_textures.py
"""

from __future__ import annotations

import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "texturas"
API = "https://api.polyhaven.com"
UA = {"User-Agent": "vt65-asset-tool"}

# material do terreno -> textura do Poly Haven (todas CC0; autores no README, por cortesia)
TEXTURAS = {
    "LeafyGrass": "forrest_ground_01",  # chão de mata: folhas, gravetos e capim (Rob Tuytel)
    "Grass": "leafy_grass",  # capim e arrozal (Charlotte Baglioni)
    "Mud": "brown_mud_leaves_01",  # barranco de riacho (Rob Tuytel)
    # terra batida de rua, beco, praça, quintal e dique (D-115, pedido do dono: "dê um aspecto de
    # terra batida para o chão do jogo nas ruas"); era forest_ground_06, terra escura de mata
    "Ground": "dirt_floor",
}
MAPAS = {"cor": "Diffuse", "normal": "nor_gl", "rugosidade": "Rough"}


def get_json(url: str) -> dict:
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.loads(r.read())


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for material, tid in TEXTURAS.items():
        files = get_json(f"{API}/files/{tid}")
        info = get_json(f"{API}/info/{tid}")
        for nome, chave in MAPAS.items():
            url = files[chave]["1k"]["jpg"]["url"]
            dst = OUT / f"{tid}_{nome}.jpg"
            if not dst.exists():
                req = urllib.request.Request(url, headers=UA)
                with urllib.request.urlopen(req, timeout=120) as r:
                    dst.write_bytes(r.read())
            print(f"{material:10} {dst.name}  ({dst.stat().st_size // 1024} KB)")
        lado_m = info["dimensions"][0] / 1000
        print(f"{'':10} {tid}: {lado_m:.2f} m de lado, autores {', '.join(info['authors'])}")


if __name__ == "__main__":
    main()
