"""Marcas do chão da área piloto (D-254): poça, trilha de roda e folhas secas.

Cada uma é um quadrado com textura de borda suave (alfa), para o chão não parecer recortado. O nó se
chama `Folhas`: o AssetLoader liga a transparência e as duas faces. Geram só 2 triângulos por cópia.

Saída: assets/blender/<chave>/<chave>.glb e metricas.json (lidos por tools/ret_registrar.py).
Uso (de vantuong65/): uv run --group arte python tools/vila_decais.py
"""

from __future__ import annotations

import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

RAIZ = Path(__file__).resolve().parents[1]
M = 0.28
PX = 512


def ruido(rng: np.random.Generator, beta: float = 2.2) -> np.ndarray:
    """Ruído fractal que emenda nas bordas, de 0 a 1."""
    f = np.fft.fft2(rng.normal(size=(PX, PX)))
    fx = np.fft.fftfreq(PX)[:, None]
    fy = np.fft.fftfreq(PX)[None, :]
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1
    r = np.fft.ifft2(f / k ** (beta / 2)).real
    return (r - r.min()) / (r.max() - r.min())


def liso(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def grade() -> tuple[np.ndarray, np.ndarray]:
    v = (np.arange(PX) + 0.5) / PX * 2 - 1
    return np.meshgrid(v, v, indexing="ij")


def poca(rng) -> np.ndarray:
    y, x = grade()
    n = ruido(rng, 2.6)
    forma = 1 - np.sqrt(x * x + y * y) + (n - 0.5) * 0.42
    # o Roblox corta o alfa parcial da SurfaceAppearance: aqui fica só a lâmina d'água
    agua = liso(0.4, 0.46, forma)
    fundo = ruido(rng, 1.6)[..., None]
    cor_agua = np.array([62, 57, 47.0]) * (0.9 + 0.2 * fundo)
    return np.dstack([cor_agua, agua * 0.86 * 255])


def halo_poca(rng) -> np.ndarray:
    """A terra molhada em volta da água, com borda suave (vai em Decal)."""
    y, x = grade()
    n = ruido(rng, 2.6)  # o mesmo primeiro ruído da poça: a mancha acompanha a água
    forma = 1 - np.sqrt(x * x + y * y) + (n - 0.5) * 0.42
    fino = ruido(rng, 1.4)
    alfa = liso(0.0, 0.42, forma) * (0.62 + 0.14 * fino)
    cor = np.array([60, 46, 33.0]) * (0.85 + 0.3 * fino[..., None])
    return np.dstack([cor, np.clip(alfa, 0, 1) * 255])


def trilha(rng) -> np.ndarray:
    y, x = grade()  # y: atravessa a pista; x: ao longo
    n = ruido(rng, 2.0)
    fino = ruido(rng, 1.1)
    k = 0.09 * (n - 0.5)
    sulco = np.zeros_like(x)
    for c in (-0.46, 0.46):
        sulco = np.maximum(sulco, 1 - liso(0.05, 0.2, np.abs(y - c + k)))
    # as ranhuras do pneu, atravessando o sulco
    grava = 0.92 + 0.08 * np.sign(np.sin(x * 62 + y * 9))
    fim = 1 - liso(0.72, 1.0, np.abs(x))
    falha = liso(0.12, 0.34, n)
    alfa = sulco * fim * falha * (0.46 + 0.3 * fino) * grava
    base = np.array([54, 42, 31.0]) * (0.75 + 0.5 * fino[..., None])
    return np.dstack([base, np.clip(alfa, 0, 1) * 255])


def detritos(rng) -> np.ndarray:
    a = np.zeros((PX, PX, 4), np.float32)
    y, x = np.mgrid[0:PX, 0:PX].astype(np.float32)
    cores = np.array(
        [(112, 84, 44), (138, 104, 54), (92, 72, 40), (120, 110, 62), (74, 58, 38), (150, 118, 72)],
        np.float32,
    )
    for _ in range(95):
        cx, cy = rng.uniform(46, PX - 46, 2)
        if np.hypot(cx - PX / 2, cy - PX / 2) > PX * 0.45:
            continue
        ang = rng.uniform(0, np.pi)
        comp, larg = rng.uniform(9, 22), rng.uniform(3.5, 8)
        x0, y0 = int(max(cx - 26, 0)), int(max(cy - 26, 0))
        xs, ys = x[y0 : y0 + 52, x0 : x0 + 52] - cx, y[y0 : y0 + 52, x0 : x0 + 52] - cy
        u = xs * np.cos(ang) + ys * np.sin(ang)
        v = -xs * np.sin(ang) + ys * np.cos(ang)
        d = (u / comp) ** 2 + (v / (larg * (1.05 - np.abs(u / comp)))) ** 2
        m = 1 - liso(0.8, 1.05, d)
        cor = cores[rng.integers(len(cores))] * rng.uniform(0.8, 1.1)
        nervura = 1 - 0.3 * np.exp(-((v / 0.9) ** 2))
        sub = a[y0 : y0 + 52, x0 : x0 + 52]
        for c in range(3):
            sub[..., c] = sub[..., c] * (1 - m) + cor[c] * nervura * m
        sub[..., 3] = np.maximum(sub[..., 3], m * 225)
    # pedrinhas
    for _ in range(38):
        cx, cy = rng.uniform(30, PX - 30, 2)
        r = rng.uniform(2.2, 6.5)
        x0, y0 = int(max(cx - 12, 0)), int(max(cy - 12, 0))
        xs, ys = x[y0 : y0 + 24, x0 : x0 + 24] - cx, y[y0 : y0 + 24, x0 : x0 + 24] - cy
        m = 1 - liso(r * 0.75, r * 1.05, np.hypot(xs, ys * 1.25))
        tom = rng.uniform(70, 118)
        luz = 1 + np.clip(-ys / r, -1, 1)[..., None] * 0.18
        sub = a[y0 : y0 + 24, x0 : x0 + 24]
        pedra = np.array([tom * 1.04, tom, tom * 0.92])[None, None] * luz
        sub[..., :3] = sub[..., :3] * (1 - m[..., None]) + pedra * m[..., None]
        sub[..., 3] = np.maximum(sub[..., 3], m * 235)
    a[..., 3] = ndimage.gaussian_filter(a[..., 3], 0.6)
    return a


def capim_tex(rng) -> np.ndarray:
    """Lâminas de capim recortadas por alfa: base escura e ponta mais seca."""
    lado = PX * 2
    img = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = [(70, 92, 38), (84, 104, 42), (98, 112, 46), (62, 84, 36), (112, 118, 54)]
    for _ in range(150):
        x = rng.uniform(0, lado)
        alto = rng.uniform(0.55, 0.98) * lado
        larg = rng.uniform(9, 20)
        curva = rng.uniform(-0.22, 0.22) * alto
        cor = np.array(base[rng.integers(len(base))], float) * rng.uniform(0.85, 1.15)
        esq, dir_ = [], []
        for i in range(8):
            t = i / 7
            cx = x + curva * t * t
            cy = lado - 1 - alto * t
            w = larg * (1 - t) ** 0.8
            esq.append((cx - w / 2, cy))
            dir_.append((cx + w / 2, cy))
        d.polygon(esq + dir_[::-1], fill=(*(int(np.clip(c, 0, 255)) for c in cor), 255))
    a = np.asarray(img.resize((PX, PX), Image.LANCZOS), np.float32).copy()
    y = np.linspace(0, 1, PX, dtype=np.float32)[:, None, None]  # 0 no topo, 1 na base
    a[..., :3] *= 1.12 - 0.42 * y
    return a


def capim_malha(rng):
    """Tufo de 3 m com 34 cartões dobrados (4 triângulos cada), sem animação nenhuma."""
    pos, uv, idx = [], [], []
    for _ in range(34):
        ang, r = rng.uniform(0, 2 * np.pi), 1.5 * np.sqrt(rng.random())
        cx, cz = r * np.cos(ang), r * np.sin(ang)
        giro = rng.uniform(0, np.pi)
        w, h = rng.uniform(0.7, 1.1), rng.uniform(0.6, 0.95)
        inclina = rng.uniform(-0.16, 0.16)
        ux, uz = np.cos(giro) * w / 2, np.sin(giro) * w / 2
        nx, nz = -np.sin(giro), np.cos(giro)
        u0 = rng.uniform(0, 0.5)
        u1 = u0 + 0.5 * w / 1.1
        b = len(pos)
        for f, v in ((0.0, 1.0), (0.55, 0.45), (1.0, 0.0)):
            desvio = inclina * f * f
            for s, u in ((-1, u0), (1, u1)):
                pos.append(
                    ((cx + s * ux + nx * desvio) / M, h * f / M, (cz + s * uz + nz * desvio) / M)
                )
                uv.append((u, v))
        for k in (0, 2):
            i = b + k
            idx += [i, i + 1, i + 3, i, i + 3, i + 2]
    p = np.array(pos, np.float32)
    n = np.tile(np.array((0, 1, 0), np.float32), (len(p), 1))
    return p, n, np.array(uv, np.float32), np.array(idx, np.uint16)


def png(a: np.ndarray) -> bytes:
    rgba = np.clip(a, 0, 255).astype(np.uint8).copy()
    # sangria: a cor sob o alfa zero acompanha a vizinha, sem franja escura no filtro da textura
    vazio = rgba[..., 3] < 8
    if vazio.any() and not vazio.all():
        idx = ndimage.distance_transform_edt(vazio, return_distances=False, return_indices=True)
        rgba[..., :3] = rgba[..., :3][idx[0], idx[1]]
    b = io.BytesIO()
    Image.fromarray(rgba, "RGBA").save(b, "PNG", optimize=True)
    return b.getvalue()


def grava(chave: str, larg_m: float, prof_m: float, tex: np.ndarray, rug: float) -> None:
    hx, hz = larg_m / M / 2, prof_m / M / 2
    pos = np.array([(-hx, 0, -hz), (hx, 0, -hz), (hx, 0, hz), (-hx, 0, hz)], np.float32)
    nor = np.tile(np.array((0, 1, 0), np.float32), (4, 1))
    uv = np.array([(0, 0), (1, 0), (1, 1), (0, 1)], np.float32)
    idx = np.array([0, 2, 1, 0, 3, 2], np.uint16)
    grava_malha(chave, pos, nor, uv, idx, tex, rug, (larg_m, 0.0, prof_m))


def grava_malha(chave, pos, nor, uv, idx, tex, rug, dim) -> None:
    imagem = png(tex)
    # sem normal e rugosidade o importador usa TextureID, que ignora o alfa e o brilho da água
    plano = np.full((16, 16, 4), 255, np.float32)
    plano[..., 0], plano[..., 1], plano[..., 2] = 128, 128, 255
    normal = png(plano)
    orm = np.full((16, 16, 4), 255, np.float32)
    orm[..., 0], orm[..., 1], orm[..., 2] = 255, rug * 255, 0
    mr = png(orm)
    partes = [
        idx.tobytes(),
        pos.tobytes(),
        nor.tobytes(),
        uv.tobytes(),
        imagem,
        normal,
        mr,
    ]
    bin_ = b""
    views = []
    for p, alvo in zip(partes, (34963, 34962, 34962, 34962, None, None, None), strict=True):
        v = {"buffer": 0, "byteOffset": len(bin_), "byteLength": len(p)}
        if alvo:
            v["target"] = alvo
        views.append(v)
        bin_ += p + b"\0" * ((4 - len(p) % 4) % 4)
    doc = {
        "asset": {"version": "2.0", "generator": "VT65 tools/vila_decais.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Folhas", "mesh": 0}],
        "meshes": [
            {
                "name": "Folhas",
                "primitives": [
                    {
                        "attributes": {"POSITION": 1, "NORMAL": 2, "TEXCOORD_0": 3},
                        "indices": 0,
                        "material": 0,
                    }
                ],
            }
        ],
        "materials": [
            {
                "name": f"{chave}_Folhas",
                "alphaMode": "BLEND",
                "doubleSided": True,
                "pbrMetallicRoughness": {
                    "baseColorTexture": {"index": 0},
                    "metallicRoughnessTexture": {"index": 2},
                    "metallicFactor": 0.0,
                    "roughnessFactor": 1.0,
                },
                "normalTexture": {"index": 1},
            }
        ],
        "textures": [{"source": 0}, {"source": 1}, {"source": 2}],
        "images": [
            {"bufferView": 4, "mimeType": "image/png"},
            {"bufferView": 5, "mimeType": "image/png"},
            {"bufferView": 6, "mimeType": "image/png"},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
            {
                "bufferView": 1,
                "componentType": 5126,
                "count": len(pos),
                "type": "VEC3",
                "min": [float(v) for v in pos.min(0)],
                "max": [float(v) for v in pos.max(0)],
            },
            {"bufferView": 2, "componentType": 5126, "count": len(nor), "type": "VEC3"},
            {"bufferView": 3, "componentType": 5126, "count": len(uv), "type": "VEC2"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_)}],
    }
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    pasta = RAIZ / "assets" / "blender" / chave
    pasta.mkdir(parents=True, exist_ok=True)
    arq = pasta / f"{chave}.glb"
    arq.write_bytes(
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<I", len(js))
        + b"JSON"
        + js
        + struct.pack("<I", len(bin_))
        + b"BIN\0"
        + bin_
    )
    met = {
        "chave": chave,
        "novo": {
            "arquivo": f"assets/blender/{chave}/{chave}.glb",
            "triangulos": len(idx) // 3,
            "dim_m_xyz": [round(float(v), 3) for v in dim],
            "dim_studs_xyz": [round(float(v) / M, 3) for v in dim],
            "atlas": 1,
            "mb": round(arq.stat().st_size / 2**20, 3),
        },
        "colisao": [],
    }
    (pasta / "metricas.json").write_text(json.dumps(met, ensure_ascii=False, indent=1), "utf-8")
    print("ok", chave, met["novo"]["mb"], "MB")


def principal() -> None:
    grava("ret_vila_poca", 5.0, 4.0, poca(np.random.default_rng(1965)), 0.07)
    grava("ret_vila_trilha", 6.0, 3.4, trilha(np.random.default_rng(1966)), 0.82)
    grava("ret_vila_detritos", 3.6, 3.6, detritos(np.random.default_rng(1967)), 0.9)
    r = np.random.default_rng(1968)
    p, n, uv, idx = capim_malha(r)
    dim = (p.max(0) - p.min(0)) * M
    grava_malha("ret_vila_capim", p, n, uv, idx, capim_tex(r), 0.86, tuple(dim))
    pasta = RAIZ / "assets" / "blender" / "vila_chao"
    pasta.mkdir(parents=True, exist_ok=True)
    (pasta / "poca_halo.png").write_bytes(png(halo_poca(np.random.default_rng(1965))))
    (pasta / "trilha.png").write_bytes(png(trilha(np.random.default_rng(1966))))
    print("ok decais do chão")


if __name__ == "__main__":
    principal()
