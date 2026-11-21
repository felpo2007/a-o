"""Ladrilho de arrozal em cartões (D-74): o arroz que cobre os 1.155 tabuleiros do mapa.

O canteiro do ForgeGUI (rice_patch) tem 13 mil triângulos para 2 x 1,45 m: cobrir os arrozais
(78% do mapa) com ele passaria de 10 bilhões de triângulos. Aqui o arroz vira um ladrilho de
16 x 16 studs (4,5 m) de cartões recortados, posto pelo cliente só em volta da câmera:
- textura desenhada (folhas de arroz em touceiras, cores tiradas da textura do canteiro do
  ForgeGUI), 2 variantes empilhadas, alfa = contorno das folhas, cor sangrada na borda;
- "alto" (perto): linhas a cada 1 stud (28 cm, espaçamento do transplante) e colunas a cada 2;
- "baixo" (longe): linhas a cada 2 e colunas a cada 4, cartões de 8 studs;
- cada cartão tem as duas faces com normal quase para cima: o arroz fica iluminado igual dos
  dois lados (com face dupla do Roblox o verso ficaria escuro);
- base 0,35 stud abaixo da água (o caule sai da água), altura de 2,65 studs (74 cm, arroz de
  agosto, ~50 dias depois do transplante).

Saída: assets/arroz/arroz_alto.glb, arroz_baixo.glb e arroz_textura.png (fora do Git).
Uso: uv run --group arte python tools/make_rice.py
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prep_trees import Glb  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "assets" / "arroz"
TILE = 16.0  # studs
BASE_Y = -0.35
ALTURA = 2.65
TEX = 512  # textura final (2 variantes de 512 x 256)
SS = 4  # superamostragem do desenho

# cores do canteiro do ForgeGUI (média e percentis 10/90 dos pixels verdes): 84,103,38;
# 66,86,16; 105,119,64. Pé mais escuro (sombra da touceira), ponta mais clara.
PE = np.array([46.0, 66.0, 20.0])
MEIO = np.array([86.0, 110.0, 36.0])
PONTA = np.array([132.0, 146.0, 62.0])


def lamina(d_rgb, d_a, x0, y0, ang, comp, larg, curva, tom, rng):
    """Uma folha: curva que sai do pé, afina até a ponta e cai para fora."""
    n = 12
    p = np.array([x0, y0], dtype=np.float64)
    pts = [p.copy()]
    for k in range(n):
        t = (k + 0.5) / n
        a = ang + curva * t * t
        p = p + np.array([np.sin(a), -np.cos(a)]) * comp / n
        pts.append(p.copy())
    pts = np.array(pts)
    for k in range(n):
        t0, t1 = k / n, (k + 1) / n
        w0 = larg * (1 - t0) ** 0.7 / 2
        w1 = larg * max(1 - t1, 0.0) ** 0.7 / 2
        dvec = pts[k + 1] - pts[k]
        nv = np.array([-dvec[1], dvec[0]]) / max(np.linalg.norm(dvec), 1e-6)
        quad = [
            tuple(pts[k] + nv * w0),
            tuple(pts[k + 1] + nv * w1),
            tuple(pts[k + 1] - nv * w1),
            tuple(pts[k] - nv * w0),
        ]
        tm = (t0 + t1) / 2
        cor = PE + (MEIO - PE) * min(tm * 2, 1) + (PONTA - MEIO) * max(tm * 2 - 1, 0)
        cor = np.clip(cor * tom, 0, 255)
        d_rgb.polygon(quad, fill=tuple(int(c) for c in cor))
        d_a.polygon(quad, fill=255)


def textura(rng: np.random.Generator) -> bytes:
    w, h = TEX * SS, TEX * SS
    rgb = Image.new("RGB", (w, h), tuple(int(c) for c in MEIO))
    alfa = Image.new("L", (w, h), 0)
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(alfa)
    meia = h // 2
    for var in range(2):
        topo = var * meia
        chao = topo + meia - 2 * SS
        # 5 touceiras por cartão de 4 studs (transplante a ~20 cm). Cada folha é desenhada
        # também deslocada de uma largura para cada lado: a textura emenda sem costura quando o
        # cartão a repete (cartões de 8 studs do ladrilho de longe)
        for k in range(5):
            x0 = (k + 0.5) / 5 * w + rng.normal(0, 0.03) * w
            for _ in range(int(rng.integers(20, 30))):
                ang = float(np.clip(rng.normal(0, 0.32), -0.75, 0.75))
                comp = (meia - 6 * SS) * rng.uniform(0.55, 0.97)
                curva = np.sign(ang + 1e-3) * rng.uniform(0.1, 0.7)
                larg = rng.uniform(13, 21)
                tom = rng.uniform(0.82, 1.15)
                xb = x0 + rng.normal(0, 6) * SS / 4
                for desl in (-w, 0, w):
                    lamina(dr, da, xb + desl, chao, ang, comp, larg, curva, tom, rng)
    rgb = rgb.resize((TEX, TEX), Image.Resampling.LANCZOS)
    alfa = alfa.resize((TEX, TEX), Image.Resampling.LANCZOS)
    a = np.asarray(alfa).astype(np.uint8)
    cor = np.asarray(rgb).copy()
    # sangria: o pixel transparente recebe a cor da folha mais próxima (sem halo na borda)
    _, (iy, ix) = ndimage.distance_transform_edt(a < 128, return_indices=True)
    cor = cor[iy, ix]
    out = Image.fromarray(np.dstack([cor, a]).astype(np.uint8), "RGBA")
    buf = io.BytesIO()
    out.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def cartoes(passo_linha: float, passo_coluna: float, comp: float, rng: np.random.Generator):
    """Cartões do ladrilho: (centro x, centro z, direção x, direção z, comprimento)."""
    out = []
    n_lin = int(round(TILE / passo_linha))
    for i in range(n_lin):
        z = -TILE / 2 + (i + 0.5) * passo_linha + rng.normal(0, 0.06)
        n = int(round(TILE / comp))
        for j in range(n):
            x = -TILE / 2 + (j + 0.5) * comp
            out.append((x, z, 1.0, 0.0, comp))
    n_col = int(round(TILE / passo_coluna))
    for i in range(n_col):
        x = -TILE / 2 + (i + 0.5) * passo_coluna + rng.normal(0, 0.1)
        n = int(round(TILE / comp))
        for j in range(n):
            z = -TILE / 2 + (j + 0.5) * comp
            out.append((x, z, 0.0, 1.0, comp))
    return out


def malha(cards, rng: np.random.Generator):
    pos, nrm, uv, idx = [], [], [], []
    up = np.array([0.0, 1.0, 0.0])
    for cx, cz, dx, dz, comp in cards:
        d = np.array([dx, 0.0, dz])
        c = np.array([cx, 0.0, cz])
        meio = comp / 2
        alt = ALTURA * rng.uniform(0.9, 1.08)
        var = int(rng.integers(0, 2))
        vt, vb = var * 0.5 + 0.004, var * 0.5 + 0.496
        reps = comp / 4.0  # textura de 4 studs repetida no cartão
        u0 = float(rng.uniform(0, 1))
        u1 = u0 + reps
        if rng.random() < 0.5:
            u0, u1 = u1, u0
        nc = np.cross(d, up)
        for lado in (1, -1):
            n = up * 0.8 + nc * 0.2 * lado
            n /= np.linalg.norm(n)
            b = len(pos)
            for p, q in (
                (c - d * meio, (u0, vb)),
                (c + d * meio, (u1, vb)),
                (c + d * meio, (u1, vt)),
                (c - d * meio, (u0, vt)),
            ):
                yy = BASE_Y if q[1] == vb else BASE_Y + alt
                pos.append([p[0], yy, p[2]])
                nrm.append(n)
                uv.append(q)
            if lado == 1:
                idx += [b, b + 1, b + 2, b, b + 2, b + 3]
            else:
                idx += [b, b + 2, b + 1, b, b + 3, b + 2]
    return (
        np.array(pos, np.float32),
        np.array(nrm, np.float32),
        np.array(uv, np.float32),
        np.array(idx, np.uint32),
    )


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(1965)
    tex = textura(rng)
    (SAIDA / "arroz_textura.png").write_bytes(tex)
    for nome, cards in (
        ("arroz_alto", cartoes(1.0, 2.0, 4.0, rng)),
        ("arroz_baixo", cartoes(2.0, 4.0, 8.0, rng)),
    ):
        pos, nrm, uv, idx = malha(cards, rng)
        g = Glb()
        ti = g.texture(tex, "image/png")
        mi = g.material("Arroz", ti, None, True)
        g.js["materials"][mi]["doubleSided"] = False  # as duas faces já estão na malha
        g.mesh("Arroz", pos, nrm, uv, idx, mi)
        (SAIDA / f"{nome}.glb").write_bytes(g.bytes())
        print(nome, "cartões", len(cards), "triângulos", len(idx) // 3)


if __name__ == "__main__":
    main()
