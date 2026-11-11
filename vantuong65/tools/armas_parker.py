"""Acabamento das armas (D-67): aço fosfatizado/oxidado em vez de prata brilhante.

Pedido do usuário (2026-11-11): "melhore a qualidade das miras e armas com mais texturas e
detalhes".
Na captura da mira no Studio o metal da M14 parecia prata polida: os GLB do gerador vêm com textura
de 4096 px, mapa de metal médio (~0,4) e rugosidade ~0,5, e o Roblox reduz a textura para 1024.

Aqui, sem mexer na malha (os pontos do WeaponArt continuam valendo):
- as três texturas vão a 1024 px com Lanczos, e a cor ganha nitidez (máscara de nitidez), para
  a redução ser nossa e não a do Roblox;
- onde o mapa de metal diz metal, a cor vai para o cinza-esverdeado escuro do aço fosfatizado
  (Parkerizing, padrão dos EUA em 1965) ou do oxidado azulado (armas chinesas e soviéticas), a
  rugosidade sobe e o metal desce: o aço deixa de espelhar o céu;
- madeira, lona e plástico ficam como estão.

Saída: assets/forgegui/models/<arma>_studs_parker.glb. --plano aponta o upload_plan para elas e tira
os IDs antigos (o upload-assets sobe de novo).

Uso: uv run python tools/armas_parker.py [--plano]
"""

from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from matte_glb import read_glb, write_glb  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "assets" / "forgegui" / "models"
PX = 1024
# cor do aço (sRGB) por arma: EUA fosfatizado cinza-esverdeado; bloco comunista oxidado azulado
FOSFATO = (64, 66, 60)
OXIDADO = (52, 54, 60)
ACO = {
    "m14": FOSFATO,
    "m60": FOSFATO,
    "m79": FOSFATO,
    "m1911": FOSFATO,
    "type56": OXIDADO,
    "sks": OXIDADO,
    "rpd": OXIDADO,
    "type54": OXIDADO,
    "rpg2": OXIDADO,
}
ROUGH_MIN = 0.62  # rugosidade mínima do aço
METAL_K = 0.7  # metal restante


def _img(chunks: list[bytes], gltf: dict, tex: dict | None) -> tuple[int, Image.Image] | None:
    if tex is None:
        return None
    img = gltf["images"][gltf["textures"][tex["index"]]["source"]]
    vi = img["bufferView"]
    return vi, Image.open(io.BytesIO(chunks[vi]))


def _png(im: Image.Image) -> bytes:
    out = io.BytesIO()
    im.save(out, "PNG", optimize=True)
    return out.getvalue()


def processar(key: str) -> dict:
    src = MODELS / f"{key}_studs.glb"
    gltf, rest = read_glb(src)
    blob = rest[0][1]
    views = gltf["bufferViews"]
    chunks = [
        blob[v.get("byteOffset", 0) : v.get("byteOffset", 0) + v["byteLength"]] for v in views
    ]
    info: dict = {"arma": key}
    for mat in gltf["materials"]:
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        cor = _img(chunks, gltf, pbr.get("baseColorTexture"))
        mr = _img(chunks, gltf, pbr.get("metallicRoughnessTexture"))
        nor = _img(chunks, gltf, mat.get("normalTexture"))
        if cor is None:
            continue
        ci, cim = cor
        c = cim.convert("RGB").resize((PX, PX), Image.Resampling.LANCZOS)
        c = c.filter(ImageFilter.UnsharpMask(radius=1.2, percent=70, threshold=2))
        a = np.asarray(c).astype(np.float32)
        if mr is not None:
            mi, mim = mr
            m = np.asarray(mim.convert("RGB").resize((PX, PX), Image.Resampling.LANCZOS)).astype(
                np.float32
            )
            metal = m[..., 2] / 255.0
            # aço: luminância original guarda o desenho (riscos, desgaste); a cor vai ao tom do aço
            lum = a.mean(axis=2, keepdims=True) / 255.0
            alvo = np.array(ACO[key], np.float32)[None, None, :] * (0.55 + 0.9 * lum)
            w = np.clip((metal - 0.25) / 0.35, 0, 1)[..., None]
            a = a * (1 - w) + alvo * w
            rough = m[..., 1] / 255.0
            m[..., 1] = 255.0 * (rough * (1 - w[..., 0]) + np.maximum(rough, ROUGH_MIN) * w[..., 0])
            m[..., 2] = m[..., 2] * (1 - w[..., 0] * (1 - METAL_K))
            chunks[mi] = _png(Image.fromarray(np.clip(m, 0, 255).astype(np.uint8), "RGB"))
            gltf["images"][gltf["textures"][pbr["metallicRoughnessTexture"]["index"]]["source"]][
                "mimeType"
            ] = "image/png"
            info["fracao_aco"] = round(float(w.mean()), 3)
        chunks[ci] = _png(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB"))
        gltf["images"][gltf["textures"][pbr["baseColorTexture"]["index"]]["source"]]["mimeType"] = (
            "image/png"
        )
        if nor is not None:
            ni, nim = nor
            chunks[ni] = _png(nim.convert("RGB").resize((PX, PX), Image.Resampling.LANCZOS))
            gltf["images"][gltf["textures"][mat["normalTexture"]["index"]]["source"]][
                "mimeType"
            ] = "image/png"
    new = b""
    for v, data in zip(views, chunks, strict=True):
        new += b"\x00" * ((4 - len(new) % 4) % 4)
        v["byteOffset"] = len(new)
        v["byteLength"] = len(data)
        new += data
    gltf["buffers"][0]["byteLength"] = len(new)
    dst = MODELS / f"{key}_studs_parker.glb"
    write_glb(dst, gltf, [(rest[0][0], new), *rest[1:]])
    info["mb"] = round(dst.stat().st_size / 2**20, 2)
    return info


def plano() -> None:
    plan_path = ROOT / "assets" / "upload_plan.json"
    ids_path = ROOT / "assets" / "roblox_ids.json"
    plan = json.loads(plan_path.read_text("utf-8"))
    ids = json.loads(ids_path.read_text("utf-8"))
    for item in plan:
        k = item["key"].split(".", 1)[1] if item["key"].startswith("Models.") else None
        if k in ACO and not item["file"].endswith("_parker.glb"):
            item["file"] = f"assets/forgegui/models/{k}_studs_parker.glb"
            item["name"] = f"VT65 {k} aco"
            print(item["key"], ids.pop(item["key"], None), "-> republicar", item["file"])
    plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=1) + "\n", "utf-8")
    ids_path.write_text(json.dumps(ids, ensure_ascii=False, indent=1), "utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plano", action="store_true")
    ap.add_argument("armas", nargs="*")
    a = ap.parse_args()
    if a.plano:
        plano()
        return
    for k in a.armas or list(ACO):
        print(json.dumps(processar(k), ensure_ascii=False))


if __name__ == "__main__":
    main()
