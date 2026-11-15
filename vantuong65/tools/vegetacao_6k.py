"""Vegetação com até 6 mil triângulos por modelo (pedido do dono, D-135).

A D-66 pedia a malha cheia do gerador (8 a 13,6 mil triângulos). Aqui cada planta do ForgeGUI é
reduzida por quádricas (tools/decimate_glb.py) para ALVO triângulos, preservando as costuras de UV.
Primeiro com a borda presa; se a redução parar acima do alvo (folhas são lâminas abertas), refaz
com a borda solta.

O GLB reduzido entra no lugar do original (`arquivo` do manifest) e o manifest ganha o bloco
`reducao_local`: o `fetch_forgegui_assets.py` baixa o original, confere o sha256 de origem e refaz
a mesma redução. Depois:
    uv run python tools/matte_glb.py                        # refaz os *_fosco.glb
    uv run --group arte python tools/blender/bambu_sem_disco.py   # bambu (sem disco, já reduz)
    uv run --group arte python tools/prep_trees.py          # árvores do Poly Haven

Prévia de lado (antes | depois) em `--previas <pasta>`; não é o render do Roblox.

Uso: uv run --group arte python tools/vegetacao_6k.py [--previas pasta] [chave ...]
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
import tempfile
from importlib.metadata import version
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from decimate_glb import accessor, load_mesh, node_scale, read_glb, run  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
FORGE = RAIZ / "assets" / "forgegui"
ALVO = 6000
MOTIVO = "D-135: vegetação com até 6 mil triângulos (pedido do dono, 2026-11-14)"
# D-152: a cerca de bambu (16.418 triângulos) era 1 milhão de triângulos na vista da base dos EUA
# (62 cercas em An Cường), ~1/4 da vista medida no Studio; entra no teto da vegetação
MOTIVOS = {
    "bamboo_fence": "D-152: cerca de bambu no teto da vegetação (desempenho do mapa, 2026-11-15)",
}
# plantas do ForgeGUI (o bambu sem disco é reduzido no tools/blender/bambu_sem_disco.py)
CHAVES = [
    "shrub",
    "elephant_grass",
    "banana",
    "coconut_palm",
    "hill_tree",
    "rice_patch",
    "canopy_tree",
    "melaleuca_grove",
    "taro_fern",
    "bamboo_fence",
]


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def reduz(src: Path, dst: Path) -> tuple[dict, bool]:
    """Reduz com a borda presa; se não chegar ao alvo, com a borda solta."""
    r = run(src, dst, ALVO, False)
    if r["tris"] <= ALVO:
        return r, False
    return run(src, dst, ALVO, True), True


def pecas_previa(glb: Path):
    """Malha e textura de cor de um GLB de uma primitiva, para o rasterizador do prep_trees."""
    js, blob = read_glb(glb)
    pos, uv, faces = load_mesh(js, blob)
    pos = pos * node_scale(js)
    pr = js["meshes"][0]["primitives"][0]
    nrm = accessor(js, blob, pr["attributes"]["NORMAL"]).astype(np.float64)
    mat = js["materials"][pr["material"]]
    tex = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img = js["images"][js["textures"][tex]["source"]]
    bv = js["bufferViews"][img["bufferView"]]
    o = bv.get("byteOffset", 0)
    im = Image.open(io.BytesIO(blob[o : o + bv["byteLength"]])).convert("RGBA").resize((256, 256))
    cor = np.asarray(im).astype(np.float64)
    cor[..., 3] = 255
    return [("malha", pos, nrm, uv, faces.reshape(-1), cor)]


def previa_lado_a_lado(antes: Path, depois: Path, saida: Path, titulo: str) -> None:
    from prep_trees import previa

    with tempfile.TemporaryDirectory() as tmp:
        a, b = Path(tmp) / "a.png", Path(tmp) / "b.png"
        previa(pecas_previa(antes), a, 480)
        previa(pecas_previa(depois), b, 480)
        ia, ib = Image.open(a), Image.open(b)
        out = Image.new("RGB", (ia.width + ib.width + 10, ia.height + 28), (255, 255, 255))
        out.paste(ia, (0, 28))
        out.paste(ib, (ia.width + 10, 28))
        from PIL import ImageDraw

        ImageDraw.Draw(out).text((8, 8), titulo, fill=(0, 0, 0))
        saida.parent.mkdir(parents=True, exist_ok=True)
        out.save(saida)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("chaves", nargs="*")
    ap.add_argument("--previas", type=Path)
    a = ap.parse_args()
    caminho = FORGE / "manifest.json"
    texto = caminho.read_text("utf-8")
    man = json.loads(texto)
    pm = version("pymeshlab")
    for m in man["models"]:
        chave = m.get("chave")
        if chave not in (a.chaves or CHAVES):
            continue
        if m.get("reducao_local"):
            print(f"{chave}: já reduzido ({m['triangulos']} triângulos)")
            continue
        src = FORGE / m["arquivo"]
        if sha(src) != m["sha256"]:
            raise SystemExit(f"{chave}: {src.name} não é o original do manifest")
        with tempfile.TemporaryDirectory() as tmp:
            orig = Path(tmp) / "origem.glb"
            orig.write_bytes(src.read_bytes())
            r, solta = reduz(orig, src)
            if a.previas:
                titulo = f"{chave}: {r['tris_antes']} -> {r['tris']} triangulos"
                previa_lado_a_lado(orig, src, a.previas / f"{chave}.png", titulo)
        m["reducao_local"] = {
            "ferramenta": "tools/decimate_glb.py (tools/vegetacao_6k.py)",
            "pymeshlab": pm,
            "faces": ALVO,
            "soltar_bordas": solta,
            "sha256_origem": m["sha256"],
            "triangulos_origem": r["tris_antes"],
            "desvio_max_m": r["desvio_max_m"],
            "desvio_medio_m": r["desvio_medio_m"],
            "motivo": MOTIVOS.get(chave, MOTIVO),
        }
        m["sha256"] = sha(src)
        m["triangulos"] = r["tris"]
        m["dim_studs_xyz"] = r["dim_studs_xyz"]
        print(
            f"{chave}: {r['tris_antes']} -> {r['tris']} triângulos, borda "
            f"{'solta' if solta else 'presa'}, desvio máx {r['desvio_max_m']} m, "
            f"médio {r['desvio_medio_m']} m, caixa {r['dim_antes']} -> {r['dim_studs_xyz']}"
        )
    fim = "\n" if texto.endswith("\n") else ""
    caminho.write_text(json.dumps(man, ensure_ascii=False, indent=2) + fim, "utf-8")


if __name__ == "__main__":
    main()
