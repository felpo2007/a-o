"""Tira o metal dos modelos que não são de metal (D-64).

O gerador do ForgeGUI exporta todo GLB com textura de metal/rugosidade. No Roblox ela vira o
MetalnessMap da SurfaceAppearance, e folhas, palha, madeira e terra refletem o céu como cromo
(captura no Studio, 2026-11-10: a mata ficava azul-acinzentada). Este script reescreve só o JSON
do GLB: metallicFactor 0, sem metallicRoughnessTexture (rugosidade fixa e alta). A malha e a
textura de cor não mudam, então os triângulos do manifest continuam valendo.

Uso:
    uv run python tools/matte_glb.py --listar     # mostra os materiais
    uv run python tools/matte_glb.py              # grava *_fosco.glb ao lado dos originais
    uv run python tools/matte_glb.py --plano      # aponta o upload_plan para os foscos e libera
                                                  # as chaves no roblox_ids.json para republicar
    uv run --env-file .env python tools/roblox_cloud.py upload-assets
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "assets" / "forgegui" / "models"

# chave do AssetIds -> arquivo; só o que não é de metal
FOSCOS = {
    "Models.shrub": "arbusto_studs.glb",
    "Models.elephant_grass": "capim_elefante_studs.glb",
    "Models.bamboo_clump": "bambu_touceira_studs.glb",
    "Models.banana": "bananeira_studs.glb",
    "Models.coconut_palm": "coqueiro_studs.glb",
    "Models.hill_tree": "arvore_colina_studs.glb",
    "Models.rice_patch": "arroz_canteiro_studs.glb",
    "Models.hut_thatch": "casa_palha_studs.glb",
    "Models.hut_veranda": "casa_varanda_studs.glb",
    "Models.hut_kitchen": "cozinha_studs.glb",
    "Models.house_tile": "casa_telha_studs.glb",
    "Models.granary": "celeiro_studs.glb",
    "Models.well": "poco_studs.glb",
    "Models.shrine": "altar_studs.glb",
    "Models.grave_mound": "tumulo_studs.glb",
    "Models.tunnel_entrance": "entrada_tunel_studs.glb",
    "Models.vc_bunker": "bunker_vc_studs.glb",
    "Models.trench_section": "trincheira_secao_studs.glb",
    "Models.bamboo_fence": "cerca_bambu_studs.glb",
    "Models.spider_hole": "toca_aranha_studs.glb",
    "Models.log_bridge": "ponte_troncos_studs.glb",
    "Models.sandbags": "sacos_areia_studs.glb",
    "Models.water_buffalo": "bufalo_studs.glb",
    "Models.chicken": "galinha_studs.glb",
}
ROUGHNESS = 0.9

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A


def read_glb(path: Path) -> tuple[dict, list[tuple[int, bytes]]]:
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC or version != 2:
        raise ValueError(f"{path.name}: não é GLB 2.0")
    chunks = []
    off = 12
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunks.append((ctype, data[off + 8 : off + 8 + clen]))
        off += 8 + clen
    if chunks[0][0] != JSON_CHUNK:
        raise ValueError(f"{path.name}: primeiro chunk não é JSON")
    return json.loads(chunks[0][1].decode("utf-8")), chunks[1:]


def write_glb(path: Path, gltf: dict, rest: list[tuple[int, bytes]]) -> None:
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    body = struct.pack("<II", len(js), JSON_CHUNK) + js
    for ctype, cdata in rest:
        pad = (4 - len(cdata) % 4) % 4
        body += struct.pack("<II", len(cdata) + pad, ctype) + cdata + b"\x00" * pad
    path.write_bytes(struct.pack("<III", GLB_MAGIC, 2, 12 + len(body)) + body)


def matte(gltf: dict) -> int:
    n = 0
    for mat in gltf.get("materials", []):
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        had_tex = pbr.pop("metallicRoughnessTexture", None) is not None
        if had_tex or pbr.get("metallicFactor", 1.0) != 0.0:
            n += 1
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = ROUGHNESS
    return n


def describe(gltf: dict) -> str:
    out = []
    for mat in gltf.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {})
        tex = "sim" if "metallicRoughnessTexture" in pbr else "não"
        out.append(
            f"metal={pbr.get('metallicFactor', 1.0)} rough={pbr.get('roughnessFactor', 1.0)} "
            f"mrTex={tex} alpha={mat.get('alphaMode', 'OPAQUE')}"
        )
    return "; ".join(out)


def point_plan() -> None:
    plan_path = ROOT / "assets" / "upload_plan.json"
    ids_path = ROOT / "assets" / "roblox_ids.json"
    plan = json.loads(plan_path.read_text("utf-8"))
    ids = json.loads(ids_path.read_text("utf-8"))
    for item in plan:
        name = FOSCOS.get(item["key"])
        if name:
            item["file"] = f"assets/forgegui/models/{Path(name).stem}_fosco.glb"
            item["name"] = item.get("name", item["key"]).replace(" fosco", "") + " fosco"
            old = ids.pop(item["key"], None)
            print(f"{item['key']:24} {old} -> republicar {item['file']}")
    plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=1) + "\n", "utf-8")
    ids_path.write_text(json.dumps(ids, ensure_ascii=False, indent=1), "utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--listar", action="store_true")
    ap.add_argument("--plano", action="store_true")
    args = ap.parse_args()
    if args.plano:
        point_plan()
        return 0
    for key, name in FOSCOS.items():
        src = MODELS / name
        if not src.is_file():
            print(f"FALTA {src} (rode tools/fetch_forgegui_assets.py)")
            return 1
        gltf, rest = read_glb(src)
        if args.listar:
            print(f"{key:24} {describe(gltf)}")
            continue
        n = matte(gltf)
        dst = src.with_name(src.stem + "_fosco.glb")
        write_glb(dst, gltf, rest)
        check, _ = read_glb(dst)
        print(f"{key:24} {n} material(is) fosco(s) -> {dst.name} ({describe(check)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
