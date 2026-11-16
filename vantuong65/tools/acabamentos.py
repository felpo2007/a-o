"""Texturas dos acabamentos de arma (D-178).

A arte de cada arma é uma malha com uma textura só (atlas de 1024). O acabamento troca essa
textura por uma pintada aqui (Skins.applyWeapon troca o TextureID da MeshPart):

1. a malha é rasterizada no espaço da textura: cada texel ganha a posição 3D e a normal da face
   (cache em assets/acabamentos/_cache);
2. a cor original separa madeira, metal, latão e pano (latão e bandoleira nunca são pintados);
3. a receita (`arte.receita` em Shared/Skins) pinta o padrão em 3D, contínuo na arma inteira,
   e a luz e os detalhes da textura original continuam por cima (razão de luminância);
4. o acabamento antigo, de cor de madeira e metal (`finish`), vira a receita "tinta".

Uso:
    uv run --group arte python tools/acabamentos.py            # gera as que faltam + prévias
    uv run --group arte python tools/acabamentos.py --todas    # refaz todas
    uv run --group arte python tools/acabamentos.py --so skin_m14_tigre_fogo --previas
    uv run --group arte python tools/acabamentos.py --mascaras # prévia de madeira/metal/latão
    uv run --group arte python tools/acabamentos.py --plano    # põe as que faltam no upload_plan

Para o jogo (a textura sobe como Decal, como as imagens do chão e da loja):
    uv run --env-file .env python tools/roblox_cloud.py upload-assets Acab.
    uv run --group arte python tools/acabamentos.py --resolver <saida.luau>
      -> rode o <saida.luau> no Studio (execute_luau, Server) e grave o texto que ele devolve
         com tools/copia_da_conversa.py <registro> acab_imagens assets/acabamentos_imagens.json
    uv run --group arte python tools/acabamentos.py --luau     # grava Shared/AcabamentosArte.luau

Precisa dos GLB das armas: rode antes o fetch_forgegui_assets.py (os do gerador) e os scripts do
Blender das armas (assets/blender/arma_*).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from glb_leitor import Glb  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SAIDA = ROOT / "assets/acabamentos"
CACHE = SAIDA / "_cache"
PREVIAS = SAIDA / "previas"
PLANO = ROOT / "assets/upload_plan.json"
IDS = ROOT / "assets/roblox_ids.json"
LUAU = ROOT / "src/ReplicatedStorage/Shared/AcabamentosArte.luau"
# ID da imagem de cada decal Acab.* (o TextureID não abre decal), resolvido no Studio pelo
# InsertService (--resolver)
IMAGENS = ROOT / "assets/acabamentos_imagens.json"
TAM = 1024
VERSAO = 3  # sobe quando a rasterização muda (invalida o cache)

# arma (Shared/Weapons) -> GLB que subiu como AssetIds.Models.<arma>
ARMAS = {
    "m14": "assets/forgegui/models/m14_studs_parker.glb",
    "type56": "assets/forgegui/models/type56_studs_parker.glb",
    "rpd": "assets/forgegui/models/rpd_studs_parker.glb",
    "m1911": "assets/forgegui/models/m1911_studs_parker.glb",
    "type54": "assets/forgegui/models/type54_studs_parker.glb",
    "m79": "assets/forgegui/models/m79_studs_parker.glb",
    "rpg2": "assets/forgegui/models/rpg2_studs_parker.glb",
    "m60": "assets/blender/arma_m60/arma_m60.glb",
    "sks": "assets/blender/arma_sks/arma_sks.glb",
    "m16": "assets/blender/arma_m16/arma_m16.glb",
    "m70": "assets/blender/arma_m70_unertl/arma_m70_unertl.glb",
    "mosin": "assets/blender/arma_mosin_pu/arma_mosin_pu.glb",
    "win12": "assets/blender/arma_win12/arma_win12.glb",
}


# ===================================================================== malha no espaço da textura
@dataclass
class Mapa:
    """Texels cobertos pela malha: posição normalizada, normal e o t ao longo do comprimento."""

    cob: np.ndarray  # (H, W) bool
    q: np.ndarray  # (H, W, 3) [través, alto, comprimento], arma com ~4 unidades de comprimento
    n: np.ndarray  # (H, W, 3) normal na mesma ordem
    t: np.ndarray  # (H, W) 0 = fim da coronha, 1 = boca do cano
    lado: dict  # G-buffer das prévias de lado


def _eixos(pos: np.ndarray) -> tuple[int, int, int, float, float, float]:
    """Eixo do comprimento, do alto e do través; sinal da boca do cano; mínimo e comprimento."""
    lo, hi = pos.min(axis=0), pos.max(axis=0)
    ext = hi - lo
    comp = int(np.argmax(ext))
    alto = 1 if comp != 1 else 2
    trav = 3 - comp - alto
    L = float(ext[comp])
    c = pos[:, comp]

    # a boca do cano é a ponta mais fina: compara a altura da malha perto de cada ponta
    def altura(sel: np.ndarray) -> float:
        y = pos[sel, alto]
        return float(y.max() - y.min()) if len(y) else 0.0

    tras = altura(c < lo[comp] + 0.07 * L)
    frente = altura(c > hi[comp] - 0.07 * L)
    sinal = 1.0 if frente <= tras else -1.0
    return comp, alto, trav, sinal, float(lo[comp]), L


def _tri_pixels(a: np.ndarray, b: np.ndarray, c: np.ndarray, W: int, H: int):
    """Pixels (centro dentro) de um triângulo 2D em pixels; devolve xs, ys e os pesos."""
    x0 = max(int(np.floor(min(a[0], b[0], c[0]))), 0)
    x1 = min(int(np.ceil(max(a[0], b[0], c[0]))), W - 1)
    y0 = max(int(np.floor(min(a[1], b[1], c[1]))), 0)
    y1 = min(int(np.ceil(max(a[1], b[1], c[1]))), H - 1)
    if x1 < x0 or y1 < y0:
        return None
    area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    if abs(area) < 1e-12:
        return None
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    px, py = xs + 0.5, ys + 0.5
    w0 = ((b[0] - px) * (c[1] - py) - (b[1] - py) * (c[0] - px)) / area
    w1 = ((c[0] - px) * (a[1] - py) - (c[1] - py) * (a[0] - px)) / area
    w2 = 1.0 - w0 - w1
    eps = -1e-4
    dentro = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
    if not dentro.any():
        return None
    return xs[dentro], ys[dentro], w0[dentro], w1[dentro], w2[dentro]


def _dilatar(cob: np.ndarray, *mapas: np.ndarray, passos: int = 8) -> np.ndarray:
    """Espalha os texels cobertos pela borda das ilhas (o filtro não pega a cor velha)."""
    cob = cob.copy()
    for _ in range(passos):
        falta = ~cob
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            viz = np.roll(cob, (dy, dx), axis=(0, 1))
            pega = falta & viz
            if pega.any():
                for m in mapas:
                    m[pega] = np.roll(m, (dy, dx), axis=(0, 1))[pega]
                cob |= pega
                falta &= ~pega
    return cob


def _lado(prims, comp: int, alto: int, trav: int, sinal: float, W: int = 1100) -> dict:
    """G-buffer das duas vistas de lado (UV e luz por pixel) para as prévias."""
    todas = np.concatenate([p.pos for p in prims])
    lo, hi = todas.min(axis=0), todas.max(axis=0)
    L = hi[comp] - lo[comp]
    esc = (W - 40) / L
    Hh = int((hi[alto] - lo[alto]) * esc) + 40
    vistas = []
    for olho in (1.0, -1.0):  # de um lado e do outro
        uv = np.zeros((Hh, W, 2), np.float32)
        luz = np.zeros((Hh, W), np.float32)
        prof = np.full((Hh, W), -np.inf, np.float32)
        for p in prims:
            h = (p.pos[:, comp] - lo[comp]) * esc + 20
            if sinal < 0:
                h = W - h
            if olho < 0:
                h = W - h  # do outro lado, a boca fica à esquerda
            v = (hi[alto] - p.pos[:, alto]) * esc + 20
            d = p.pos[:, trav] * olho
            for i0, i1, i2 in p.tri:
                A, B, C = p.pos[i0], p.pos[i1], p.pos[i2]
                nn = np.cross(B - A, C - A)
                ln = np.linalg.norm(nn)
                if ln < 1e-12:
                    continue
                nn = nn / ln
                r = _tri_pixels(
                    np.array([h[i0], v[i0]]),
                    np.array([h[i1], v[i1]]),
                    np.array([h[i2], v[i2]]),
                    W,
                    Hh,
                )
                if r is None:
                    continue
                xs, ys, w0, w1, w2 = r
                z = w0 * d[i0] + w1 * d[i1] + w2 * d[i2]
                ok = z > prof[ys, xs]
                if not ok.any():
                    continue
                xs, ys, w0, w1, w2, z = xs[ok], ys[ok], w0[ok], w1[ok], w2[ok], z[ok]
                prof[ys, xs] = z
                uv[ys, xs] = (
                    w0[:, None] * p.uv[i0] + w1[:, None] * p.uv[i1] + w2[:, None] * p.uv[i2]
                )
                # luz: de cima e um pouco de frente para o olho
                n3 = np.zeros(3)
                n3[alto], n3[trav] = nn[alto], nn[trav] * olho
                if n3[trav] < 0:
                    n3 = -n3
                ld = np.zeros(3)
                ld[alto], ld[trav] = 0.75, 0.66
                luz[ys, xs] = 0.38 + 0.62 * max(0.0, float(n3 @ ld))
        vistas.append({"uv": uv, "luz": luz, "cob": np.isfinite(prof)})
    return {"vistas": vistas}


def mapa_da_arma(arma: str) -> Mapa:
    glb = ROOT / ARMAS[arma]
    if not glb.exists():
        raise SystemExit(f"falta o GLB da arma {arma}: {glb.relative_to(ROOT)}")
    chave = hashlib.sha1(glb.read_bytes() + bytes([VERSAO])).hexdigest()
    CACHE.mkdir(parents=True, exist_ok=True)
    arq = CACHE / f"{arma}.npz"
    if arq.exists():
        z = np.load(arq, allow_pickle=True)
        if str(z["chave"]) == chave:
            lado = z["lado"].item()
            return Mapa(z["cob"], z["q"], z["n"], z["t"], lado)
    prims = Glb(glb).primitivas()
    todas = np.concatenate([p.pos for p in prims])
    comp, alto, trav, sinal, cmin, L = _eixos(todas)
    centro = (todas.min(axis=0) + todas.max(axis=0)) / 2
    P = np.zeros((TAM, TAM, 3), np.float32)
    N = np.zeros((TAM, TAM, 3), np.float32)
    cob = np.zeros((TAM, TAM), bool)
    for p in prims:
        uvpx = p.uv * TAM
        for i0, i1, i2 in p.tri:
            A, B, C = p.pos[i0], p.pos[i1], p.pos[i2]
            nn = np.cross(B - A, C - A)
            ln = np.linalg.norm(nn)
            if ln < 1e-12:
                continue
            r = _tri_pixels(uvpx[i0], uvpx[i1], uvpx[i2], TAM, TAM)
            if r is None:
                continue
            xs, ys, w0, w1, w2 = r
            P[ys, xs] = w0[:, None] * A + w1[:, None] * B + w2[:, None] * C
            N[ys, xs] = nn / ln
            cob[ys, xs] = True
    cob = _dilatar(cob, P, N)
    # ordem [través, alto, comprimento]; o comprimento cresce para a boca do cano
    rel = (P - centro) / L * 4.0
    q = np.stack([rel[..., trav], rel[..., alto], rel[..., comp] * sinal], axis=-1)
    n = np.stack([N[..., trav], N[..., alto], N[..., comp] * sinal], axis=-1)
    t = np.clip(q[..., 2] / 4.0 + 0.5, 0, 1)
    lado = _lado(prims, comp, alto, trav, sinal)
    np.savez_compressed(arq, chave=chave, cob=cob, q=q, n=n, t=t, lado=np.array(lado, dtype=object))
    print(f"  {arma}: malha rasterizada ({int(cob.sum())} texels)")
    return Mapa(cob, q, n, t, lado)


def textura_original(arma: str) -> np.ndarray:
    return np.asarray(Glb(ROOT / ARMAS[arma]).imagem(0).convert("RGB"), np.float32) / 255.0


# ===================================================================== regiões pela cor
# matiz máxima da madeira (graus) por arma, medida no histograma da textura: a bandoleira de pano
# verde-oliva começa logo acima (Tipo 56 ~35-45°, M14 ~40-55°); a madeira da RPD vai até ~40°
MADEIRA_H = {"type56": 33.0, "m14": 38.0, "rpd": 41.0}
PANO = {"m14", "type56"}  # armas com bandoleira de pano na malha


def regioes(rgb: np.ndarray, mapa: Mapa, arma: str = "") -> dict[str, np.ndarray]:
    """madeira, latão, pano e metal (o resto), pela cor da textura original, sem ruído de texel.

    O latão (cartucho, cinto de munição) e o pano (bandoleira) nunca são pintados."""
    im = Image.fromarray((rgb * 255).astype(np.uint8))
    hsv = np.asarray(im.convert("HSV"), np.float32) / 255.0
    h, s, v = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    hmax = MADEIRA_H.get(arma, 40.0)
    latao = (h >= 34) & (h <= 62) & (s > 0.42) & (v > 0.5)
    madeira = (h >= 4) & (h <= hmax) & (s > 0.3) & (v > 0.1) & ~latao
    pano = (
        (h > hmax) & (h <= 75) & (s > 0.25) & (v > 0.08) & ~latao
        if arma in PANO
        else np.zeros_like(latao)
    )

    def limpa(m: np.ndarray) -> np.ndarray:
        f = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.6))
        return np.asarray(f, np.float32) / 255.0 > 0.5

    latao, pano = limpa(latao), limpa(pano) & ~limpa(latao)
    madeira = limpa(madeira) & ~latao & ~pano
    cob = mapa.cob
    return {
        "madeira": madeira & cob,
        "latao": latao & cob,
        "pano": pano & cob,
        "metal": cob & ~madeira & ~latao & ~pano,
    }


def guarda_mao(reg: dict, mapa: Mapa) -> np.ndarray:
    """Madeira da frente (guarda-mão): o grupo mais perto da boca, separado por um vão."""
    tm = mapa.t[reg["madeira"]]
    if tm.size == 0:
        return np.zeros_like(reg["madeira"])
    hist, borda = np.histogram(tm, bins=100, range=(0, 1))
    tem = hist > max(20, tm.size * 0.002)
    idx = np.nonzero(tem)[0]
    if idx.size == 0:
        return np.zeros_like(reg["madeira"])
    corte = None
    vao = 0
    for i in range(idx[-1], idx[0] - 1, -1):
        if tem[i]:
            if vao >= 4:
                corte = borda[i + vao + 1]
                break
            vao = 0
        else:
            vao += 1
    if corte is None:  # coronha inteiriça: o terço da frente da madeira
        a, b = borda[idx[0]], borda[idx[-1] + 1]
        corte = b - 0.35 * (b - a)
    return reg["madeira"] & (mapa.t >= corte)


# ===================================================================== ruído (numpy puro)
def _hash(ix: np.ndarray, iy: np.ndarray, iz: np.ndarray, seed: int) -> np.ndarray:
    h = (ix * 374761393 + iy * 668265263 + iz * 1274126177 + seed * 144665) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = (h ^ (h >> 16)) & 0xFFFFFF
    return h.astype(np.float32) / float(0xFFFFFF)


def ruido(p: np.ndarray, seed: int) -> np.ndarray:
    """Ruído de valor 3D suave, 0..1."""
    pf = np.floor(p)
    i = pf.astype(np.int64)
    f = (p - pf).astype(np.float32)
    u = f * f * (3 - 2 * f)
    out = np.zeros(len(p), np.float32)
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1 - u[:, 2]
                out += wx * wy * wz * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(
    p: np.ndarray, seed: int, oitavas: int = 5, lac: float = 2.03, ganho: float = 0.5
) -> np.ndarray:
    tot, amp, soma = np.zeros(len(p), np.float32), 1.0, 0.0
    for o in range(oitavas):
        tot += amp * ruido(p * (lac**o) + o * 17.13, seed + o * 101)
        soma += amp
        amp *= ganho
    return tot / soma


def worley(p: np.ndarray, seed: int) -> tuple[np.ndarray, np.ndarray]:
    pf = np.floor(p)
    i = pf.astype(np.int64)
    f1 = np.full(len(p), 9.0, np.float32)
    f2 = np.full(len(p), 9.0, np.float32)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                cx, cy, cz = i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz
                fx = cx + _hash(cx, cy, cz, seed)
                fy = cy + _hash(cx, cy, cz, seed + 1)
                fz = cz + _hash(cx, cy, cz, seed + 2)
                d = np.sqrt((p[:, 0] - fx) ** 2 + (p[:, 1] - fy) ** 2 + (p[:, 2] - fz) ** 2)
                d = d.astype(np.float32)
                f2 = np.where(d < f1, f1, np.minimum(f2, d))
                f1 = np.minimum(f1, d)
    return f1, f2


def smooth(a: float, b: float, x: np.ndarray) -> np.ndarray:
    k = np.clip((x - a) / (b - a), 0, 1)
    return k * k * (3 - 2 * k)


def mix(a: np.ndarray, b: np.ndarray, k: np.ndarray) -> np.ndarray:
    k = np.asarray(k, np.float32)
    if k.ndim == 1:
        k = k[:, None]
    return a * (1 - k) + b * k


def plano(q: np.ndarray, n: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Coordenada 2D da face (projeção pelo eixo dominante da normal)."""
    k = np.argmax(np.abs(n), axis=1)
    u = np.where(k == 2, q[:, 0], q[:, 2])
    v = np.where(k == 1, q[:, 0], q[:, 1])
    return u, v


def gradiente(cores: np.ndarray, x: np.ndarray) -> np.ndarray:
    """Cores igualmente espaçadas em 0..1, transição suave."""
    k = len(cores)
    if k == 1:
        return np.repeat(cores[:1], len(x), axis=0)
    x = np.clip(x, 0, 1) * (k - 1)
    i = np.minimum(np.floor(x).astype(int), k - 2)
    f = smooth(0, 1, x - i)
    return mix(cores[i], cores[i + 1], f)


# ===================================================================== receitas
@dataclass
class Ctx:
    q: np.ndarray  # (n, 3)
    n: np.ndarray
    t: np.ndarray
    lum: np.ndarray
    c: np.ndarray  # (k, 3) cores 0..1
    seed: int

    def cor(self, i: int) -> np.ndarray:
        return self.c[min(i, len(self.c) - 1)]


def r_tigre(x: Ctx):
    """Listras de tigre finas, de largura variada, afiladas de um lado e com a borda serrada."""
    q = x.q
    w = fbm(q * 0.8, x.seed, 4) - 0.5
    larg = fbm(q * 2.2 + 5, x.seed + 7, 3)
    ang = np.arctan2(q[:, 1], q[:, 0])
    f = np.sin(2 * np.pi * (q[:, 2] * 2.9 + w * 1.9 + q[:, 1] * 0.3))
    serra = (fbm(q * 11.0, x.seed + 3, 2) - 0.5) * 0.4
    # a listra afina para baixo (como no bicho) e some em partes
    lim = 0.42 + 0.5 * larg + serra + 0.22 * np.sin(ang - 0.6)
    m = smooth(lim - 0.05, lim + 0.05, f)
    base = mix(x.cor(0) * 0.92, x.cor(0) * 1.08, fbm(q * 3, x.seed + 9, 3))
    return mix(base, x.cor(1), m), None


def r_fade(x: Ctx):
    k = x.t + (fbm(x.q * 1.4, x.seed, 3) - 0.5) * 0.12
    cor = gradiente(x.c, (k - 0.08) / 0.84)
    brilho = 0.94 + 0.12 * (x.n[:, 1] * 0.5 + 0.5)
    return cor * brilho[:, None], None


def r_damasco(x: Ctx):
    q = x.q
    w = fbm(q * 1.1, x.seed, 5)
    v = np.sin(2 * np.pi * (q[:, 1] * 2.2 + q[:, 2] * 0.55 + q[:, 0] * 1.2 + w * 3.2) * 7.0)
    m = smooth(-0.55, 0.55, v)
    cor = mix(x.cor(0), x.cor(1), m)
    if len(x.c) > 2:
        cor = mix(cor, x.cor(2), smooth(0.86, 0.98, v) * 0.8)
    return cor, None


# fração da arma que cada camada de mancha cobre (a de cima pinta por cima da de baixo)
CAMADAS = (0.4, 0.3, 0.22)


def r_camo(x: Ctx):
    """Manchas de camuflagem: o limiar sai da distribuição do ruído na própria arma, então cada
    cor cobre a mesma fração em qualquer arma e em qualquer semente."""
    q = x.q
    cor = np.repeat(x.cor(0)[None], len(q), axis=0)
    for i in range(1, len(x.c)):
        r = fbm(q * (1.25 + 0.2 * i) + i * 31.7, x.seed + 13 * i, 4)
        lim = float(np.percentile(r, 100 * (1 - CAMADAS[min(i - 1, 2)])))
        cor = mix(cor, x.cor(i), smooth(lim - 0.006, lim + 0.006, r))
    return cor, None


def r_carbono(x: Ctx):
    """Sarja 2x2 de fibra: os feixes deitados e os em pé refletem diferente, em escada diagonal."""
    u, v = plano(x.q, x.n)
    a, b = u * 22.0, v * 22.0
    ia, ib = np.floor(a), np.floor(b)
    fa, fb = a - ia, b - ib
    deitado = ((ia + ib).astype(np.int64) % 4) < 2
    largura = np.where(deitado, fb, fa)  # o feixe é redondo na largura
    ao_longo = np.where(deitado, fa, fb)
    redondo = np.sin(np.pi * largura) ** 0.5
    nivel = np.where(deitado, 1.0, 0.42) * (0.55 + 0.45 * redondo)
    nivel = nivel * (0.92 + 0.08 * np.sin(2 * np.pi * ao_longo * 3))
    return mix(x.cor(0), x.cor(1), nivel), None


def r_laca(x: Ctx):
    """Laca (sơn mài): fundo polido da cor 1 e a incrustação da cor 2 em lascas quebradas (folha de
    ouro ou madrepérola), mais pó fino da mesma cor."""
    q = x.q
    k = x.n[:, 1] * 0.5 + 0.5
    fundo = x.cor(0) * (0.9 + 0.22 * smooth(0.3, 1.0, k))[:, None]
    # madrepérola: clara e quase sem cor (o ouro também é claro, mas é saturado)
    perola = lum(x.cor(1)) > 0.75 and float(x.cor(1).max() - x.cor(1).min()) < 0.2
    p = q * (6.0 if perola else 3.4) + (fbm(q * 2.0, x.seed + 4, 3)[:, None] - 0.5) * 0.8
    mancha = fbm(p, x.seed, 4)
    lim = float(np.percentile(mancha, 78))
    lasca = smooth(lim - 0.008, lim + 0.008, mancha)
    f1, f2 = worley(q * 9.0, x.seed + 7)
    racha = 1 - smooth(0.015, 0.05, f2 - f1)  # a folha quebrada mostra o fundo nas rachas
    lasca = lasca * (1 - racha * 0.85)
    cel = np.floor(q * 85)
    po = smooth(
        0.988,
        0.996,
        _hash(
            cel[:, 0].astype(np.int64),
            cel[:, 1].astype(np.int64),
            cel[:, 2].astype(np.int64),
            x.seed + 3,
        ),
    )
    inc = x.cor(1)
    if perola:  # madrepérola: a lasca muda de tom com a luz
        tom = fbm(q * 6.0 + x.n * 0.8, x.seed + 9, 3)
        rosa, verde, azul = (
            np.array([1.0, 0.86, 0.9]),
            np.array([0.86, 1.0, 0.92]),
            np.array([0.86, 0.92, 1.0]),
        )
        inc = mix(
            mix(rosa[None], verde[None], smooth(0.3, 0.55, tom)), azul[None], smooth(0.55, 0.8, tom)
        )
        branco = np.array([1.0, 0.99, 0.97])
        inc = mix(branco[None], inc, 0.6) * (0.97 + 0.06 * tom[:, None])
    else:
        inc = inc[None] * (0.85 + 0.3 * ruido(q * 40.0, x.seed + 5))[:, None]
    m = np.clip(lasca + po, 0, 1)
    return mix(fundo, inc, m), m * 0.35


def r_digital(x: Ctx):
    tam = 0.085
    cel = (np.floor(x.q / tam) + 0.5) * tam
    cor = np.repeat(x.cor(0)[None], len(cel), axis=0)
    for i in range(1, len(x.c)):
        r = fbm(cel * (1.6 + 0.15 * i) + i * 19.3, x.seed + 17 * i, 3)
        lim = float(np.percentile(r, 100 * (1 - CAMADAS[min(i - 1, 2)])))
        cor = np.where((r > lim)[:, None], x.cor(i)[None], cor)
    return cor, None


def r_cromo(x: Ctx):
    """Espelho: o chão escuro (cor 2) embaixo, o céu claro (cor 1) em cima, a faixa do horizonte
    na cor 3."""
    e = x.n[:, 1] * 0.5 + 0.5 + (fbm(x.q * 1.6, x.seed, 3) - 0.5) * 0.25
    hor = smooth(0.44, 0.52, e)
    cor = mix(x.cor(1), x.cor(0), hor)
    if len(x.c) > 2:
        faixa = smooth(0.5, 0.56, e) * (1 - smooth(0.6, 0.72, e))
        cor = mix(cor, x.cor(2), faixa * 0.8)
    reflexo = smooth(0.86, 0.97, e) * 0.3
    return np.clip(cor + reflexo[:, None], 0, 1), reflexo


def _hexdist(u: np.ndarray, v: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Distância à borda da célula hexagonal (0 na borda) e um id da célula."""
    s3 = np.sqrt(3.0)
    pu, pv = u, v
    a_u, a_v = np.mod(pu, 1.0) - 0.5, np.mod(pv, s3) - s3 / 2
    b_u, b_v = np.mod(pu - 0.5, 1.0) - 0.5, np.mod(pv - s3 / 2, s3) - s3 / 2
    da, db = a_u * a_u + a_v * a_v, b_u * b_u + b_v * b_v
    gu = np.where(da < db, a_u, b_u)
    gv = np.where(da < db, a_v, b_v)
    cid = np.floor(np.where(da < db, pu, pu - 0.5)) * 7 + np.floor(
        np.where(da < db, pv / s3, (pv - s3 / 2) / s3)
    )
    ax, ay = np.abs(gu), np.abs(gv)
    d = 0.5 - np.maximum(ax * 0.5 + ay * (s3 / 2), ax)
    return d, cid


def r_hex(x: Ctx):
    u, v = plano(x.q, x.n)
    d, cid = _hexdist(u * 9.0, v * 9.0)
    linha = 1 - smooth(0.035, 0.07, d)
    var = _hash(
        cid.astype(np.int64), np.zeros_like(cid, np.int64), np.zeros_like(cid, np.int64), x.seed
    )
    base = x.cor(0) * (0.86 + 0.28 * var[:, None])
    cor = mix(base, x.cor(1), linha)
    return cor, (linha * 0.6 if len(x.c) > 2 else None)


def r_zebra(x: Ctx):
    q = x.q
    w = fbm(q * 1.2, x.seed, 4) - 0.5
    f = np.sin(2 * np.pi * (q[:, 2] * 2.6 + q[:, 1] * 0.6 + w * 2.0))
    m = smooth(-0.08, 0.08, f)
    return mix(x.cor(0), x.cor(1), m), None


def r_escamas(x: Ctx):
    """Escamas de réptil: células irregulares com a borda na cor 2, o corpo na cor 1, o brilho no
    meio de cada escama na cor 3, e o tom que varia devagar pela arma."""
    u, v = plano(x.q, x.n)
    w = (fbm(x.q * 1.4, x.seed + 2, 3) - 0.5) * 0.9
    p = np.stack([u * 15.0 + w, v * 17.0 - w, np.zeros_like(u)], axis=1)
    f1, f2 = worley(p, x.seed)
    borda = 1 - smooth(0.05, 0.14, f2 - f1)
    tom = 0.78 + 0.4 * ruido(p * 0.3 + 3.1, x.seed + 5)
    corpo = x.cor(0)[None] * tom[:, None]
    brilho = x.cor(2) if len(x.c) > 2 else x.cor(0) * 1.3
    corpo = mix(corpo, brilho[None], (1 - smooth(0.05, 0.6, f1)) * 0.65)
    return mix(corpo, x.cor(1)[None], borda), None


def r_lava(x: Ctx):
    p = x.q * 4.2 + (fbm(x.q * 1.5, x.seed + 5, 3)[:, None] - 0.5) * 1.4
    f1, f2 = worley(p, x.seed)
    racha = 1 - smooth(0.02, 0.09, f2 - f1)
    rocha = x.cor(0) * (0.65 + 0.5 * fbm(x.q * 4, x.seed + 2, 4))[:, None]
    calor = mix(x.cor(1), x.cor(2) if len(x.c) > 2 else x.cor(1), racha**2)
    cor = mix(rocha, calor, racha)
    return cor, racha * 0.85


def _crista(p: np.ndarray, seed: int, oitavas: int) -> np.ndarray:
    """1 na linha onde o ruído cruza o meio, caindo dos dois lados (o ruído é esticado para
    cobrir 0..1, senão quase tudo fica perto do meio)."""
    f = fbm(p, seed, oitavas)
    f = (f - float(np.median(f))) / max(float(f.std()), 1e-4) * 0.18
    return 1 - np.clip(np.abs(f) * 2, 0, 1)


def r_raio(x: Ctx):
    """Relâmpagos: linhas finas e tortas, acesas, num fundo escuro com um brilho fraco em volta."""
    r1 = _crista(x.q * 1.25, x.seed, 5)
    r2 = _crista(x.q * 2.1 + 9, x.seed + 4, 4)
    raio = np.maximum(smooth(0.965, 0.99, r1), smooth(0.975, 0.995, r2) * 0.8)
    halo = np.maximum(smooth(0.88, 0.97, r1), smooth(0.93, 0.985, r2) * 0.6) * 0.45
    base = x.cor(0) * (0.8 + 0.3 * fbm(x.q * 2.5, x.seed + 8, 3))[:, None]
    brilho = x.cor(2) if len(x.c) > 2 else x.cor(1)
    cor = mix(mix(base, x.cor(1), halo), brilho, raio)
    return cor, np.maximum(raio, halo * 0.7)


def r_ouro(x: Ctx):
    """Ouro polido (cor 1 clara, cor 2 a sombra) com arabesco gravado em manchas. Cor 2 quase preta:
    armação negra e só a parte de cima (o ferrolho da pistola) em ouro."""
    e = x.n[:, 1] * 0.5 + 0.5 + (fbm(x.q * 1.4, x.seed, 3) - 0.5) * 0.3
    negro = lum(x.cor(1)) < 0.12
    sombra = x.cor(0) * 0.55 if negro else x.cor(1)
    cor = mix(sombra, x.cor(0), smooth(0.25, 0.8, e))
    w = fbm(x.q * 2.2, x.seed + 3, 4)
    grav = np.abs(np.sin(2 * np.pi * w * 7.0))
    linha = (1 - smooth(0.05, 0.16, grav)) * smooth(0.45, 0.6, fbm(x.q * 1.1, x.seed + 9, 3))
    cor = mix(cor, cor * 0.45, linha)
    if negro:
        alto = x.q[:, 1]
        topo, base = float(np.percentile(alto, 99.5)), float(np.percentile(alto, 0.5))
        ferrolho = smooth(-0.02, 0.02, alto - (topo - 0.3 * (topo - base)))
        armacao = x.cor(1)[None] * (0.8 + 0.4 * (x.n[:, 1:2] * 0.5 + 0.5))
        cor = mix(armacao, cor, ferrolho)
    return cor, None


def r_marmore(x: Ctx):
    q = x.q
    w = fbm(q * 1.3, x.seed, 6)
    v = np.abs(np.sin(2 * np.pi * (q[:, 2] * 0.45 + q[:, 1] * 0.8 + w * 2.6)))
    veia = 1 - smooth(0.0, 0.1, v)
    w2 = fbm(q * 2.4 + 3, x.seed + 5, 5)
    v2 = np.abs(np.sin(2 * np.pi * (q[:, 2] * 0.9 - q[:, 0] * 0.7 + w2 * 3.4)))
    veia2 = (1 - smooth(0.0, 0.05, v2)) * 0.7
    base = x.cor(0) * (0.93 + 0.1 * fbm(q * 3, x.seed + 2, 4))[:, None]
    cor = mix(base, x.cor(1), veia * 0.9)
    return mix(cor, x.cor(2) if len(x.c) > 2 else x.cor(1), veia2), None


def r_topo(x: Ctx):
    """Carta topográfica: curvas de nível finas e juntas, a mestra de 5 em 5 na cor 3."""
    f = fbm(x.q * 0.8, x.seed, 5)
    h = (f - float(f.min())) / max(float(f.max() - f.min()), 1e-4) * 26.0
    fr = h - np.floor(h)
    dist = np.minimum(fr, 1 - fr)
    linha = 1 - smooth(0.05, 0.13, dist)
    mestra = (np.floor(h + 0.5).astype(int) % 5 == 0) & (linha > 0)
    base = mix(x.cor(0), x.cor(0) * 1.12, smooth(0.3, 0.7, fr))
    cor = mix(base, x.cor(1), linha)
    if len(x.c) > 2:
        cor = np.where(mestra[:, None], mix(cor, x.cor(2), linha), cor)
    return cor, None


def r_bambu(x: Ctx):
    q = x.q
    seg = q[:, 2] * 2.1 + (fbm(q * 0.8, x.seed, 2) - 0.5) * 0.3
    fr = seg - np.floor(seg)
    no = np.maximum(smooth(0.92, 0.985, fr), 1 - smooth(0.0, 0.03, fr))
    ang = np.arctan2(q[:, 1], q[:, 0])
    fibra = 0.92 + 0.08 * np.sin(ang * 60 + fbm(q * 6, x.seed + 2, 2) * 6)
    base = x.cor(0) * fibra[:, None] * (0.9 + 0.2 * smooth(0.0, 0.9, fr))[:, None]
    cor = mix(base, x.cor(1), no)
    if len(x.c) > 2:
        manchas = smooth(0.66, 0.72, fbm(q * 3.2, x.seed + 6, 4))
        cor = mix(cor, x.cor(2), manchas * 0.8)
    return cor, None


def r_galaxia(x: Ctx):
    q = x.q
    neb = fbm(q * 1.15, x.seed, 6)
    neb2 = fbm(q * 1.9 + 7, x.seed + 4, 5)
    cor = mix(x.cor(0), x.cor(1), smooth(0.45, 0.78, neb))
    cor = mix(cor, x.cor(2) if len(x.c) > 2 else x.cor(1), smooth(0.55, 0.85, neb2) * 0.8)
    cel = np.floor(q * 70)
    h = _hash(
        cel[:, 0].astype(np.int64),
        cel[:, 1].astype(np.int64),
        cel[:, 2].astype(np.int64),
        x.seed + 9,
    )
    centro = np.linalg.norm(q * 70 - cel - 0.5, axis=1)
    estrela = smooth(0.985, 0.998, h) * (1 - smooth(0.22, 0.42, centro))
    branco = x.cor(3) if len(x.c) > 3 else np.array([1.0, 1.0, 1.0], np.float32)
    cor = mix(cor, branco, estrela)
    return cor, np.maximum(estrela, smooth(0.62, 0.9, neb) * 0.35)


def r_chamas(x: Ctx):
    """Chamas de hot rod: cheias na frente da caixa e lambendo para trás em línguas curvas, com o
    miolo mais claro. A boca do cano fica na cor de fundo."""
    q, t = x.q, x.t
    alt = q[:, 1] + q[:, 0] * 0.25
    onda = alt * 6.5 + np.sin(t * 11.0) * 0.35 + fbm(q * 1.3, x.seed, 3) * 1.1
    lingua = (0.5 + 0.5 * np.sin(2 * np.pi * onda)) ** 1.6
    ponta = 0.66 - (0.12 + 0.42 * lingua)  # até onde a língua chega para trás
    frente = 0.86  # da caixa para a frente, só o fundo
    m = smooth(ponta, ponta + 0.025, t) * (1 - smooth(frente - 0.02, frente, t))
    nucleo = smooth(ponta + 0.08, ponta + 0.25, t) * (1 - smooth(frente - 0.12, frente, t))
    fogo = mix(x.cor(1)[None], (x.cor(2) if len(x.c) > 2 else x.cor(1))[None], nucleo)
    contorno = smooth(ponta + 0.025, ponta + 0.04, t) * (1 - smooth(ponta + 0.04, ponta + 0.06, t))
    fogo = mix(fogo, fogo * 0.6, contorno * 0.5)
    return mix(x.cor(0)[None].repeat(len(q), 0), fogo, m), m * 0.25


def r_anodizado(x: Ctx):
    q = x.q
    esc = np.stack([q[:, 0] * 60, q[:, 1] * 60, q[:, 2] * 1.4], axis=1)
    escovado = (fbm(esc, x.seed, 3) - 0.5) * 0.18
    if len(x.c) > 2:  # cor de têmpera: corre ao longo da arma, como o aço aquecido
        k = x.t + (fbm(q * 1.2, x.seed + 3, 3) - 0.5) * 0.25 + x.n[:, 1] * 0.06
        cor = gradiente(x.c[::-1], (k - 0.1) / 0.8)
    else:
        k = x.n[:, 1] * 0.5 + 0.5
        cor = mix(x.cor(0), x.cor(1) if len(x.c) > 1 else x.cor(0), smooth(0.2, 0.9, k))
    return np.clip(cor * (1 + escovado[:, None]), 0, 1), None


OLEO = (
    np.array(
        [[255, 60, 140], [250, 200, 60], [60, 220, 120], [40, 140, 255], [150, 60, 230]], np.float32
    )
    / 255
)


def r_oleo(x: Ctx):
    """Película de óleo: o arco-íris corre pela arma e muda com o ângulo da face."""
    fase = fbm(x.q * 1.05, x.seed, 5) * 2.6 + x.n[:, 1] * 0.45 + x.n[:, 0] * 0.25
    fr = fase - np.floor(fase)
    pal = x.c if len(x.c) >= 3 else OLEO * (x.c[0] if len(x.c) else 1.0)
    k = len(pal)
    pos = fr * k
    i = np.floor(pos).astype(int) % k
    j = (i + 1) % k
    cor = mix(pal[i], pal[j], smooth(0, 1, pos - np.floor(pos)))
    escuro = np.array([0.06, 0.06, 0.08], np.float32)
    return mix(escuro[None].repeat(len(fr), 0), cor, 0.8), None


def r_malaquita(x: Ctx):
    """Malaquita: faixas concêntricas em ondas, do claro (cor 1) ao escuro (cor 2), com o fio
    claro (cor 3) entre elas."""
    q = x.q
    w = fbm(q * 0.75, x.seed, 5)
    v = w * 16.0 + fbm(q * 3.0, x.seed + 2, 3) * 0.6
    fr = v - np.floor(v)
    cor = mix(x.cor(0), x.cor(1), smooth(0.15, 0.85, fr))
    if len(x.c) > 2:
        cor = mix(cor, x.cor(2), (1 - smooth(0.0, 0.07, fr)) * 0.8)
    return cor, None


def r_jade(x: Ctx):
    q = x.q
    nuvem = fbm(q * 1.7, x.seed, 5)
    cor = mix(x.cor(0), x.cor(1), smooth(0.3, 0.8, nuvem))
    w = fbm(q * 2.2, x.seed + 3, 5)
    v = np.abs(np.sin(2 * np.pi * (q[:, 2] * 0.6 + q[:, 1] * 0.7 + w * 2.2)))
    veia = (1 - smooth(0.0, 0.07, v)) * 0.6
    return mix(cor, x.cor(2) if len(x.c) > 2 else x.cor(1) * 1.2, veia), None


RECEITAS = {
    "tigre": r_tigre,
    "fade": r_fade,
    "damasco": r_damasco,
    "camo": r_camo,
    "carbono": r_carbono,
    "laca": r_laca,
    "digital": r_digital,
    "cromo": r_cromo,
    "hex": r_hex,
    "zebra": r_zebra,
    "escamas": r_escamas,
    "lava": r_lava,
    "raio": r_raio,
    "ouro": r_ouro,
    "marmore": r_marmore,
    "topo": r_topo,
    "bambu": r_bambu,
    "galaxia": r_galaxia,
    "chamas": r_chamas,
    "anodizado": r_anodizado,
    "oleo": r_oleo,
    "jade": r_jade,
    "malaquita": r_malaquita,
}
# quanto da luz e do detalhe da textura original passa (1 = tudo; metais brilhantes, mais)
CONTRASTE = {"cromo": 1.15, "ouro": 1.1, "anodizado": 1.0, "laca": 0.95}


def aplicar(receita: str, ctx: Ctx) -> tuple[np.ndarray, np.ndarray | None]:
    """Roda a receita e prende a cor (e a parte acesa) em 0..1."""
    cor, emis = RECEITAS[receita](ctx)
    cor = np.clip(np.asarray(cor, np.float32), 0, 1)
    if emis is not None:
        emis = np.clip(np.asarray(emis, np.float32), 0, 1)
    return cor, emis


# ===================================================================== composição
def lum(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def _seed(texto: str) -> int:
    return zlib.crc32(texto.encode()) % 100000


def pintar(spec: dict, mapa: Mapa, orig: np.ndarray, reg: dict) -> tuple[np.ndarray, list[str]]:
    avisos: list[str] = []
    L = lum(orig)
    out = orig.copy()
    ref = np.ones_like(L)
    for r in ("madeira", "metal"):
        m = reg[r]
        if m.any():
            ref[m] = max(float(np.median(L[m])), 0.04)
    arte = spec.get("arte")
    if arte:
        alvo = arte["alvo"]
        if alvo == "madeira" and reg["madeira"].sum() < 0.03 * mapa.cob.sum():
            avisos.append("arma quase sem madeira: pinta tudo")
            alvo = "tudo"
        sel = {
            "tudo": reg["madeira"] | reg["metal"],
            "metal": reg["metal"],
            "madeira": reg["madeira"],
        }[alvo]
        ctx = Ctx(
            mapa.q[sel],
            mapa.n[sel],
            mapa.t[sel],
            L[sel],
            np.array(arte["cores"], np.float32) / 255.0,
            _seed(spec["id"]),
        )
        cor, emis = aplicar(arte["receita"], ctx)
        s = np.clip(L[sel] / ref[sel], 0.18, 2.2) ** CONTRASTE.get(arte["receita"], 0.85)
        final = np.clip(cor * s[:, None], 0, 1)
        if emis is not None:
            final = mix(final, np.clip(cor, 0, 1), np.clip(emis, 0, 1))
        out[sel] = final
        return out, avisos
    # receita "tinta": a cor de madeira, guarda-mão e metal do acabamento de cor (D-176 e antes)
    f = spec.get("finish") or {}
    gm = guarda_mao(reg, mapa)
    partes = [
        ("madeira", reg["madeira"] & ~gm, f.get("wood")),
        ("guarda", gm, f.get("handguard") or f.get("wood")),
        ("metal", reg["metal"], f.get("metal")),
    ]
    for nome, m, rgb in partes:
        if rgb is None or not m.any():
            continue
        c = np.array(rgb, np.float32) / 255.0
        s = np.clip(L[m] / ref[m], 0.25, 2.0) ** (1.0 if nome != "metal" else 0.9)
        cor = np.clip(c[None] * s[:, None], 0, 1)
        if nome == "guarda" and f.get("handguardMat") == "Fabric":
            # fita enrolada: faixas em diagonal ao longo do guarda-mão
            q = mapa.q[m]
            ang = np.arctan2(q[:, 1], q[:, 0]) / (2 * np.pi)
            faixa = np.sin(2 * np.pi * (q[:, 2] * 9.0 + ang))
            cor = cor * (0.86 + 0.14 * smooth(-0.6, 0.6, faixa))[:, None]
        out[m] = cor
    if not any(rgb is not None for _, _, rgb in partes):
        avisos.append("acabamento sem cor")
    return out, avisos


# ===================================================================== prévias
def previa(mapa: Mapa, tex: np.ndarray, titulo: str) -> Image.Image:
    linhas = []
    for v in mapa.lado["vistas"]:
        uv, luz, cob = v["uv"], v["luz"], v["cob"]
        x = np.clip((uv[..., 0] * TAM).astype(int), 0, TAM - 1)
        y = np.clip((uv[..., 1] * TAM).astype(int), 0, TAM - 1)
        cor = tex[y, x] * luz[..., None]
        fundo = np.array([0.16, 0.17, 0.16], np.float32)
        img = np.where(cob[..., None], cor, fundo)
        linhas.append(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)))
    W = max(i.width for i in linhas)
    H = sum(i.height for i in linhas) + 26
    folha = Image.new("RGB", (W, H), (40, 42, 40))
    ImageDraw.Draw(folha).text((8, 6), titulo, fill=(235, 230, 210))
    y = 26
    for i in linhas:
        folha.paste(i, (0, y))
        y += i.height
    return folha


def folha_contato(imgs: list[Image.Image], destino: Path, larg: int = 1100) -> None:
    if not imgs:
        return
    imgs = [i.resize((larg, int(i.height * larg / i.width))) for i in imgs]
    cols = 2
    rows = (len(imgs) + cols - 1) // cols
    h = max(i.height for i in imgs)
    folha = Image.new("RGB", (larg * cols, h * rows), (30, 30, 30))
    for k, i in enumerate(imgs):
        folha.paste(i, ((k % cols) * larg, (k // cols) * h))
    destino.parent.mkdir(parents=True, exist_ok=True)
    folha.save(destino)


# ===================================================================== catálogo, plano e Luau
def lune() -> str:
    exe = shutil.which("lune")
    if exe:
        return exe
    local = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/vt65-tools/lune/lune.exe"
    if local.exists():
        return str(local)
    raise SystemExit("lune não encontrado (PATH ou %LOCALAPPDATA%/Programs/vt65-tools/lune)")


def catalogo() -> list[dict]:
    SAIDA.mkdir(parents=True, exist_ok=True)
    arq = SAIDA / "_specs.json"
    subprocess.run([lune(), "run", "tools/acabamentos_dump.luau", str(arq)], cwd=ROOT, check=True)
    return json.loads(arq.read_text("utf-8"))


def _grava_json(p: Path, dados) -> None:
    raw = p.read_bytes() if p.exists() else b""
    nl = "\r\n" if b"\r\n" in raw else "\n"
    txt = json.dumps(dados, ensure_ascii=False, indent=1)
    if raw.endswith(b"\n"):
        txt += "\n"
    p.write_bytes(txt.replace("\n", nl).encode("utf-8"))


def cmd_plano(specs: list[dict]) -> None:
    plano = json.loads(PLANO.read_text("utf-8"))
    tem = {x["key"] for x in plano}
    novos = 0
    for s in specs:
        key = f"Acab.{s['id']}"
        arq = SAIDA / f"{s['id']}.png"
        if key in tem or not arq.exists():
            continue
        plano.append(
            {
                "key": key,
                "file": arq.relative_to(ROOT).as_posix(),
                "assetType": "Decal",
                "name": f"Acabamento {s['id'][5:]}",
                "description": "VAN TUONG 65: textura de acabamento de arma (D-178)",
            }
        )
        novos += 1
    _grava_json(PLANO, plano)
    print(f"{novos} acabamentos novos no upload_plan.json")


def cmd_luau(specs: list[dict]) -> None:
    ids = json.loads(IDS.read_text("utf-8")) if IDS.exists() else {}
    imagens = json.loads(IMAGENS.read_text("utf-8")) if IMAGENS.exists() else {}
    validos = {s["id"] for s in specs}
    decais = {k[5:] for k in ids if k.startswith("Acab.") and k[5:] in validos}
    pares = sorted((k, int(v)) for k, v in imagens.items() if k in decais and int(v) > 0)
    falta = sorted(decais - {k for k, _ in pares})
    if falta:
        print(
            f"{len(falta)} decais sem a imagem resolvida (rode a resolução no Studio):", falta[:5]
        )
    corpo = "".join(f"\t{k} = {v},\n" for k, v in pares)
    txt = (
        "--!strict\n"
        "-- Gerado por tools/acabamentos.py --luau (D-178); não edite à mão. Textura (ID de\n"
        "-- imagem do Roblox) de cada acabamento de arma: a textura da arma repintada pela\n"
        "-- receita da skin.\n"
        "-- Skins.applyWeapon troca o TextureID da MeshPart por ela.\n"
        + (
            "return {\n" + corpo + "} :: { [string]: number }\n"
            if pares
            else "return {} :: { [string]: number }\n"
        )
    )
    LUAU.write_text(txt, "utf-8", newline="\n")
    print(f"{len(pares)} texturas em {LUAU.relative_to(ROOT)}")


def cmd_resolver(specs: list[dict], saida: Path) -> None:
    """Escreve o Luau que resolve, no Studio, a imagem de cada decal Acab.* (InsertService) e
    devolve um JSON {skin: imagem} no formato do copia_da_conversa.py (nome acab_imagens)."""
    ids = json.loads(IDS.read_text("utf-8")) if IDS.exists() else {}
    validos = {s["id"] for s in specs}
    pares = sorted(
        (k[5:], int(v)) for k, v in ids.items() if k.startswith("Acab.") and k[5:] in validos
    )
    lista = "".join(f'\t{{ "{k}", {v} }},\n' for k, v in pares)
    txt = (
        "-- Gerado por tools/acabamentos.py --resolver (D-178): rode no Studio (Server).\n"
        'local InsertService = game:GetService("InsertService")\n'
        'local HttpService = game:GetService("HttpService")\n'
        "local DECAIS = {\n" + lista + "}\n"
        "local out, falhas = {}, 0\n"
        "for i, par in DECAIS do\n"
        "\tlocal ok, m = pcall(InsertService.LoadAsset, InsertService, par[2])\n"
        '\tlocal d = ok and m and m:FindFirstChildWhichIsA("Decal", true)\n'
        '\tlocal img = d and tonumber(string.match(d.Texture, "%d+$"))\n'
        "\tif img then\n"
        "\t\tout[par[1]] = img\n"
        "\telse\n"
        "\t\tfalhas += 1\n"
        "\tend\n"
        "\tif ok and typeof(m) == \"Instance\" then\n"
        "\t\tm:Destroy()\n"
        "\tend\n"
        "\tif i % 10 == 0 then\n"
        "\t\ttask.wait()\n"
        "\tend\n"
        "end\n"
        'return "VT65COPIA acab_imagens 1/1\\n" .. HttpService:JSONEncode(out)'
        ' .. "\\n-- falhas: " .. falhas\n'
    )
    saida.write_text(txt, "utf-8", newline="\n")
    print(f"{len(pares)} decais em {saida}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--so", help="ids separados por vírgula")
    ap.add_argument("--arma", help="só os acabamentos desta arma")
    ap.add_argument("--todas", action="store_true", help="refaz mesmo as que já existem")
    ap.add_argument(
        "--previas", action="store_true", help="só as folhas de prévia (sem regravar PNG)"
    )
    ap.add_argument("--mascaras", action="store_true", help="prévia de madeira, metal e latão")
    ap.add_argument("--plano", action="store_true")
    ap.add_argument("--luau", action="store_true")
    ap.add_argument("--resolver", help="escreve o Luau de resolver decal -> imagem no Studio")
    a = ap.parse_args()

    specs = catalogo()
    if a.plano:
        cmd_plano(specs)
        return
    if a.luau:
        cmd_luau(specs)
        return
    if a.resolver:
        cmd_resolver(specs, Path(a.resolver))
        return
    if a.so:
        quer = set(a.so.split(","))
        specs = [s for s in specs if s["id"] in quer]
    if a.arma:
        specs = [s for s in specs if s["arma"] == a.arma]
    por_arma: dict[str, list[dict]] = {}
    for s in specs:
        if s["arma"] not in ARMAS:
            print("sem GLB para a arma", s["arma"], "->", s["id"])
            continue
        por_arma.setdefault(s["arma"], []).append(s)

    for arma, lista in por_arma.items():
        mapa = mapa_da_arma(arma)
        orig = textura_original(arma)
        reg = regioes(orig, mapa, arma)
        if a.mascaras:
            cores = np.zeros_like(orig)
            cores[reg["madeira"]] = (0.85, 0.45, 0.15)
            cores[reg["metal"]] = (0.45, 0.5, 0.6)
            cores[reg["latao"]] = (1.0, 0.85, 0.1)
            cores[reg["pano"]] = (0.75, 0.2, 0.75)
            gm = guarda_mao(reg, mapa)
            cores[gm] = (0.2, 0.75, 0.25)
            mascara = np.clip(
                cores * (0.4 + 0.6 * lum(orig)[..., None] / max(lum(orig).mean(), 1e-3)), 0, 1
            )
            folha_contato(
                [
                    previa(mapa, orig, f"{arma}: original"),
                    previa(mapa, mascara, f"{arma}: madeira/guarda/metal/latão"),
                ],
                PREVIAS / f"_mascaras_{arma}.png",
            )
            continue
        imgs = [previa(mapa, orig, f"{arma}: original")]
        for s in lista:
            png = SAIDA / f"{s['id']}.png"
            if png.exists() and not a.todas:
                tex = np.asarray(Image.open(png).convert("RGB"), np.float32) / 255.0
            else:
                tex, avisos = pintar(s, mapa, orig, reg)
                for av in avisos:
                    print(f"  aviso {s['id']}: {av}")
                if not a.previas:
                    Image.fromarray((np.clip(tex, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
                        png, optimize=True
                    )
            rec = s["arte"]["receita"] if s.get("arte") else "tinta"
            imgs.append(previa(mapa, tex, f"{s['id']} ({rec})"))
            print(f"  {s['id']} ({rec})")
        folha_contato(imgs, PREVIAS / f"{arma}.png")
        print(
            f"{arma}: {len(lista)} acabamentos; prévia em "
            f"{(PREVIAS / f'{arma}.png').relative_to(ROOT)}"
        )


if __name__ == "__main__":
    main()
