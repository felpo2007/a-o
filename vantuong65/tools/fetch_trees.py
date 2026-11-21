"""Baixa árvores e plantas prontas do Poly Haven (CC0, sem login) para a mata (D-67).

Os modelos vêm em glTF de 1k (textura de 1024 px), com folhas em cartão com transparência.
Destino: assets/arvores_src/<id>/ (fora do Git). Depois rode tools/prep_trees.py.

Uso: uv run python tools/fetch_trees.py [id ...]
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "assets" / "arvores_src"
UA = {"User-Agent": "vt65-asset-fetch/1.0"}

# Espécies escolhidas (D-67): copa de beira-mar e de mata seca, porte de 3 a 24 m.
MODELOS = [
    "island_tree_01",
    "island_tree_02",
    "island_tree_03",
    "jacaranda_tree",
    "tree_small_02",
    "pachira_aquatica_01",
    "fern_02",
    "calathea_orbifolia_01",
    "shrub_02",
]


def _get(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def baixar(asset_id: str, res: str = "1k") -> Path:
    files = json.loads(_get(f"https://api.polyhaven.com/files/{asset_id}"))
    g = files["gltf"][res]["gltf"]
    pasta = DESTINO / asset_id
    pasta.mkdir(parents=True, exist_ok=True)
    alvo = pasta / f"{asset_id}.gltf"
    if not alvo.exists() or alvo.stat().st_size != g["size"]:
        alvo.write_bytes(_get(g["url"]))
    for rel, inc in g.get("include", {}).items():
        dst = (pasta / rel).resolve()
        if pasta.resolve() not in dst.parents:
            raise ValueError(f"caminho fora da pasta: {rel}")
        if dst.exists() and dst.stat().st_size == inc["size"]:
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(_get(inc["url"]))
    return alvo


def main() -> None:
    ids = sys.argv[1:] or MODELOS
    for i in ids:
        print(i, baixar(i))


if __name__ == "__main__":
    main()
