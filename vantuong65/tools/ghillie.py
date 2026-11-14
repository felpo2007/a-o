"""Camuflagem de mato (ghillie) das skins (Shared/Skins): feixes de folha e capim em cartões
recortados, um conjunto para cada parte do corpo R15.

Duas metades no mesmo arquivo:
- **fora do Blender** (`uv run python tools/ghillie.py`): desenha as 3 texturas (como o
  `tools/make_rice.py`: folhas em PIL com superamostragem, alfa = contorno, cor sangrada na borda),
  chama o Blender sem janela para montar a malha e exportar o GLB, e escreve as medidas no bloco
  GHILLIE do `Shared/Skins.luau` (o `Characters` escala e solda cada peça com elas);
- **dentro do Blender** (`blender -b --factory-startup -P tools/ghillie.py -- args`): monta uma
  malha por parte do corpo ("Ghillie_<parte>"), exporta `ghillie.glb` e, com `--previa`, renderiza
  frente, costas e lado num manequim de blocos (Cycles na CPU).

Desenho (pedido do dono: "como se fosse parte do mato, com várias folhas que sobrepõem o
personagem"):
- tufos de 2 cartões cruzados que saem da superfície da parte: uns sobem e abrem para fora (folha
  presa no equipamento), outros caem (capim pendurado);
- pouca coisa na cabeça (só em cima, dos lados e atrás: nada na frente do rosto) e nos braços (só
  do lado de fora e de trás; nada entre o braço e o tronco, onde fica a arma); o resto no tronco e
  nas pernas;
- textura de 512 x 512 com 16 tufos desenhados (4 x 4 quadros); cada cartão usa um. Três
  variantes com o mesmo arranjo: arrozal (capim verde-claro e palha), selva (folha larga escura) e
  bambu (folha estreita verde-amarelada). No jogo a variante entra por TextureID;
- a malha é feita em volta de uma parte de referência (REF, studs) com origem no centro da parte
  (x direita, y cima, z costas; a frente do soldado é -z); o Characters escala por eixo;
- cartões de face única (o Characters liga DoubleSided), normais viradas para fora e para cima
  (luz igual à da superfície do corpo, como no arroz);
- até 3 mil triângulos no total (meta de vegetação, CLAUDE.md).

Saída (fora do Git): assets/ghillie/ghillie.glb, ghillie_arroz.png, ghillie_selva.png,
ghillie_bambu.png e ghillie_fit.json; a prévia vai para testes/conferencia_ghillie.png.
Uso: uv run python tools/ghillie.py [--previa] [--blender CAMINHO]
"""

from __future__ import annotations

import io
import json
import math
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "assets" / "ghillie"
SKINS = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "Skins.luau"
PREVIA = RAIZ / "testes" / "conferencia_ghillie.png"
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe"
MAX_TRIS = 3000
SEMENTE = 1965_0818

TEX = 512
SS = 4
COLS, ROWS = 4, 4  # tufos na textura (quadros quadrados de 128 px)

Cor = tuple[float, float, float]


# --------------------------------------------------------------------------------------------
# Corpo de referência (studs): largura, altura, profundidade e centro (pés em y = 0) para a prévia.
# Soldado de 1,75 m = 6,25 studs (Characters, D-77). As medidas reais vêm do corpo no jogo: o
# Characters escala cada peça por (Size da parte / REF), eixo a eixo.
# --------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Parte:
    nome: str
    ref: tuple[float, float, float]
    centro: tuple[float, float, float]
    tufos: int
    setores: tuple[tuple[float, float], ...]  # ângulos permitidos (graus; 0 = +x, 90 = costas)
    faixa_y: tuple[float, float]  # altura dos tufos do lado, em fração da meia altura
    topo: float  # fração dos tufos na face de cima
    comp: tuple[float, float]  # comprimento do tufo (studs)
    cai: float  # fração dos tufos que caem (capim pendurado)
    costas: float = 0.0  # tufos a mais nas costas (fração)


def _espelho(setores: tuple[tuple[float, float], ...]) -> tuple[tuple[float, float], ...]:
    return tuple((180 - b, 180 - a) for a, b in setores)


_BRACO_C = ((-70.0, 150.0),)
_ANTEBRACO = ((-40.0, 110.0),)
_PERNA = ((-150.0, 150.0),)  # sem o lado de dentro (entre as pernas)

PARTES: tuple[Parte, ...] = (
    Parte("Head", (1.2, 1.2, 1.2), (0, 5.7, 0), 9, ((-30.0, 210.0),), (0.0, 0.85), 0.35,
          (0.45, 0.8), 0.0),
    Parte("UpperTorso", (2.0, 1.75, 1.0), (0, 4.225, 0), 150, ((0.0, 360.0),), (-0.95, 0.85),
          0.18, (0.75, 1.35), 0.35, 0.3),
    Parte("LowerTorso", (2.0, 0.45, 1.0), (0, 3.125, 0), 50, ((0.0, 360.0),), (-0.9, 0.9), 0.0,
          (0.6, 1.0), 0.55),
    Parte("RightUpperArm", (0.85, 1.2, 0.85), (1.425, 4.5, 0), 20, _BRACO_C, (-0.7, 0.9), 0.15,
          (0.5, 0.85), 0.3),
    Parte("LeftUpperArm", (0.85, 1.2, 0.85), (-1.425, 4.5, 0), 20, _espelho(_BRACO_C),
          (-0.7, 0.9), 0.15, (0.5, 0.85), 0.3),
    Parte("RightLowerArm", (0.8, 1.1, 0.8), (1.425, 3.35, 0), 8, _ANTEBRACO, (-0.6, 0.8), 0.0,
          (0.45, 0.7), 0.4),
    Parte("LeftLowerArm", (0.8, 1.1, 0.8), (-1.425, 3.35, 0), 8, _espelho(_ANTEBRACO),
          (-0.6, 0.8), 0.0, (0.45, 0.7), 0.4),
    Parte("RightUpperLeg", (0.95, 1.3, 0.95), (0.5, 2.25, 0), 60, _PERNA, (-0.9, 0.95), 0.0,
          (0.6, 1.1), 0.55),
    Parte("LeftUpperLeg", (0.95, 1.3, 0.95), (-0.5, 2.25, 0), 60, _espelho(_PERNA),
          (-0.9, 0.95), 0.0, (0.6, 1.1), 0.55),
    Parte("RightLowerLeg", (0.85, 1.3, 0.85), (0.5, 0.95, 0), 45, _PERNA, (-0.95, 0.9), 0.0,
          (0.55, 1.0), 0.6),
    Parte("LeftLowerLeg", (0.85, 1.3, 0.85), (-0.5, 0.95, 0), 45, _espelho(_PERNA),
          (-0.95, 0.9), 0.0, (0.55, 1.0), 0.6),
)
# partes do manequim da prévia que não levam folha
MAOS_PES = (
    ("RightHand", (0.75, 0.35, 0.75), (1.425, 2.625, 0)),
    ("LeftHand", (0.75, 0.35, 0.75), (-1.425, 2.625, 0)),
    ("RightFoot", (0.85, 0.3, 1.1), (0.5, 0.15, -0.1)),
    ("LeftFoot", (0.85, 0.3, 1.1), (-0.5, 0.15, -0.1)),
)

UP = np.array([0.0, 1.0, 0.0])


def _unit(v: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else np.array([1.0, 0.0, 0.0])


def _angulo(rng: np.random.Generator, setores: tuple[tuple[float, float], ...]) -> float:
    total = sum(b - a for a, b in setores)
    x = rng.uniform(0, total)
    for a, b in setores:
        if x <= b - a:
            return math.radians(a + x)
        x -= b - a
    a, b = setores[-1]
    return math.radians(b)


@dataclass
class Malha:
    pos: np.ndarray  # (n, 3) espaço da parte, studs (x direita, y cima, z costas)
    nrm: np.ndarray  # (n, 3)
    uv: np.ndarray  # (n, 2) convenção do Blender (v = 0 embaixo)
    quads: list[tuple[int, int, int, int]]


def tufos(parte: Parte, rng: np.random.Generator) -> Malha:
    """Cartões da parte: 2 por tufo, cruzados a ~70°, raiz um pouco para dentro da superfície."""
    w, h, d = parte.ref
    rx, rz, hy = w / 2, d / 2, h / 2
    pos: list[np.ndarray] = []
    nrm: list[np.ndarray] = []
    uv: list[tuple[float, float]] = []
    quads: list[tuple[int, int, int, int]] = []
    for _ in range(parte.tufos):
        if rng.random() < parte.topo:
            # face de cima: abre para fora e para cima (ombro, alto da cabeça)
            ang = _angulo(rng, parte.setores)
            r = math.sqrt(rng.uniform(0, 1)) * 0.85
            p = np.array([math.cos(ang) * rx * r, hy, math.sin(ang) * rz * r])
            radial = _unit(np.array([math.cos(ang) / rx, 0.0, math.sin(ang) / rz]))
            n = _unit(UP + radial * 0.6)
            a = math.radians(rng.uniform(5, 40))
            direcao = UP * math.cos(a) + radial * math.sin(a)
        else:
            costas = rng.random() < parte.costas
            ang = math.radians(rng.uniform(40, 140)) if costas else _angulo(rng, parte.setores)
            y = rng.uniform(*parte.faixa_y) * hy
            p = np.array([math.cos(ang) * rx, y, math.sin(ang) * rz])
            n = _unit(np.array([math.cos(ang) / rx, 0.0, math.sin(ang) / rz]))
            if rng.random() < parte.cai:
                b = math.radians(rng.uniform(12, 35))
                direcao = -UP * math.cos(b) + n * math.sin(b)
            else:
                lift = (10, 45) if parte.nome == "Head" else (15, 55)
                a = math.radians(rng.uniform(*lift))
                direcao = UP * math.cos(a) + n * math.sin(a)
        tang = _unit(np.cross(UP, n)) if abs(n[1]) < 0.95 else np.array([1.0, 0.0, 0.0])
        direcao = _unit(direcao + tang * rng.normal(0, 0.15))
        comp = rng.uniform(*parte.comp)
        larg = comp * rng.uniform(0.8, 1.0)  # quadro da textura é quadrado
        base = p - n * 0.05 - direcao * 0.1
        ponta = base + direcao * comp
        t0 = _unit(np.cross(direcao, n))
        t1 = np.cross(direcao, t0)
        phi = math.radians(rng.uniform(-20, 20))
        for k in range(2):
            f = phi + (0 if k == 0 else math.radians(rng.uniform(60, 80)))
            lado = t0 * math.cos(f) + t1 * math.sin(f)
            meia = lado * larg / 2
            geo = _unit(np.cross(meia, direcao))
            normal = _unit(n * 0.6 + UP * 0.6 + geo * 0.3)
            col, lin = int(rng.integers(0, COLS)), int(rng.integers(0, ROWS))
            m = 0.004
            u0, u1 = col / COLS + m, (col + 1) / COLS - m
            if rng.random() < 0.5:
                u0, u1 = u1, u0
            vb, vt = 1 - (lin + 1) / ROWS + m, 1 - lin / ROWS - m
            i = len(pos)
            for q, (uu, vv) in zip(
                (base - meia, base + meia, ponta + meia, ponta - meia),
                ((u0, vb), (u1, vb), (u1, vt), (u0, vt)),
                strict=True,
            ):
                pos.append(q)
                nrm.append(normal)
                uv.append((uu, vv))
            quads.append((i, i + 1, i + 2, i + 3))
    return Malha(np.array(pos), np.array(nrm), np.array(uv), quads)


def malhas() -> dict[str, Malha]:
    rng = np.random.default_rng(SEMENTE)
    return {p.nome: tufos(p, rng) for p in PARTES}


def medidas(ms: dict[str, Malha]) -> dict:
    """Caixa de cada peça no espaço da parte (o Characters escala e solda por ela)."""
    out: dict = {"ref": {}, "parts": {}, "tris": 0}
    for p in PARTES:
        m = ms[p.nome]
        mn, mx = m.pos.min(axis=0), m.pos.max(axis=0)
        tris = 2 * len(m.quads)
        out["ref"][p.nome] = [round(float(x), 3) for x in p.ref]
        out["parts"][p.nome] = {
            "size": [round(float(x), 3) for x in (mx - mn)],
            "offset": [round(float(x), 3) for x in (mn + mx) / 2],
            "tris": tris,
        }
        out["tris"] += tris
    return out


# --------------------------------------------------------------------------------------------
# Texturas (fora do Blender: PIL e scipy)
# --------------------------------------------------------------------------------------------
# arrozal: as cores do canteiro (make_rice) e palha seca
ARROZ_VERDE = ((46, 66, 20), (86, 110, 36), (132, 146, 62))
ARROZ_PALHA = ((112, 92, 52), (168, 148, 88), (204, 188, 132))
# selva: folha larga escura (taioba, folha de árvore do sub-bosque)
SELVA = ((24, 36, 18), (40, 62, 30), (64, 90, 40))
SELVA_SECA = ((70, 64, 30), (100, 92, 44), (128, 116, 58))
# bambu: folha estreita verde-amarelada, algumas velhas amarelando
BAMBU = ((84, 104, 38), (126, 142, 56), (158, 166, 74))
BAMBU_VELHA = ((128, 118, 52), (170, 158, 84), (196, 184, 112))
VARIANTES = {"arroz": "rice", "selva": "jungle", "bambu": "bamboo"}


def _grad(cores, t: float, tom: float) -> tuple[int, int, int]:
    a, b, c = (np.asarray(x, np.float64) for x in cores)
    cor = a + (b - a) * min(t * 2, 1) + (c - b) * max(t * 2 - 1, 0)
    return tuple(int(x) for x in np.clip(cor * tom, 0, 255))


def _curva(x0, y0, ang, comp, curva, n=14):
    pts = [np.array([x0, y0], np.float64)]
    p = pts[0].copy()
    for k in range(n):
        t = (k + 0.5) / n
        a = ang + curva * t * t
        p = p + np.array([math.sin(a), -math.cos(a)]) * comp / n
        pts.append(p.copy())
    return pts


def _lamina(dr, da, pts, larg, cores, tom, forma: str) -> None:
    """Folha ao longo de uma curva. forma: "capim" (afina até a ponta, cor do pé à ponta), "larga"
    (oval com ponta) ou "lanca" (estreita, larga no primeiro terço). As duas últimas saem num
    polígono só (em faixas apareciam emendas claras), com uma metade em sombra e a nervura."""
    n = len(pts) - 1
    if forma == "capim":
        for k in range(n):
            t0, t1 = k / n, (k + 1) / n
            w0, w1 = (1 - t0) ** 0.7, max(1 - t1, 0) ** 0.7
            dv = pts[k + 1] - pts[k]
            nv = np.array([-dv[1], dv[0]]) / max(np.linalg.norm(dv), 1e-6)
            quad = [
                tuple(pts[k] + nv * w0 * larg / 2),
                tuple(pts[k + 1] + nv * w1 * larg / 2),
                tuple(pts[k + 1] - nv * w1 * larg / 2),
                tuple(pts[k] - nv * w0 * larg / 2),
            ]
            dr.polygon(quad, fill=_grad(cores, (t0 + t1) / 2, tom))
            da.polygon(quad, fill=255)
        return
    esq, dir_ = [], []
    for k, p in enumerate(pts):
        t = k / n
        if forma == "larga":
            w = math.sin(math.pi * min(t * 0.95 + 0.05, 1)) ** 0.75
        else:
            w = math.sin(math.pi * min(t**0.7, 1)) ** 0.9
        a, b = pts[max(k - 1, 0)], pts[min(k + 1, n)]
        dv = b - a
        nv = np.array([-dv[1], dv[0]]) / max(np.linalg.norm(dv), 1e-6)
        esq.append(tuple(p + nv * w * larg / 2))
        dir_.append(tuple(p - nv * w * larg / 2))
    folha = esq + dir_[::-1]
    dr.polygon(folha, fill=_grad(cores, 0.6, tom))
    da.polygon(folha, fill=255)
    meio = [tuple(p) for p in pts]
    dr.polygon(esq + meio[::-1], fill=_grad(cores, 0.3, tom))  # metade em sombra
    cor = _grad(cores, 0.95, tom * 1.12)  # nervura central mais clara
    dr.line(meio[: max(n - 1, 2)], fill=cor, width=max(2, int(larg * 0.05)))


def _tufo(dr, da, cx: float, chao: float, ch: float, var: str, rng) -> None:
    if var == "arroz":
        for _ in range(int(rng.integers(16, 24))):
            ang = float(np.clip(rng.normal(0, 0.38), -0.85, 0.85))
            comp = ch * rng.uniform(0.55, 0.96)
            curva = np.sign(ang + 1e-3) * rng.uniform(0.1, 0.8)
            larg = rng.uniform(26, 44)
            cores = ARROZ_PALHA if rng.random() < 0.35 else ARROZ_VERDE
            pts = _curva(cx + rng.normal(0, 10), chao, ang, comp, curva)
            _lamina(dr, da, pts, larg, cores, rng.uniform(0.85, 1.12), "capim")
    elif var == "selva":
        for _ in range(int(rng.integers(5, 8))):
            ang = float(np.clip(rng.normal(0, 0.55), -1.0, 1.0))
            haste = ch * rng.uniform(0.12, 0.3)
            p0 = _curva(cx + rng.normal(0, 8), chao, ang * 0.6, haste, 0.1, 4)
            dr.line([tuple(p) for p in p0], fill=SELVA[0], width=10)
            da.line([tuple(p) for p in p0], fill=255, width=10)
            comp = ch * rng.uniform(0.45, 0.68)
            larg = comp * rng.uniform(0.42, 0.56)
            curva = np.sign(ang + 1e-3) * rng.uniform(0.2, 0.9)
            cores = SELVA_SECA if rng.random() < 0.12 else SELVA
            x1, y1 = p0[-1]
            pts = _curva(x1, y1, ang, comp, curva)
            _lamina(dr, da, pts, larg, cores, rng.uniform(0.85, 1.15), "larga")
    else:
        for _ in range(int(rng.integers(2, 4))):
            ang0 = float(np.clip(rng.normal(0, 0.3), -0.6, 0.6))
            caule = _curva(cx + rng.normal(0, 14), chao, ang0, ch * rng.uniform(0.7, 0.95), 0.3)
            dr.line([tuple(p) for p in caule], fill=(96, 104, 44), width=7)
            da.line([tuple(p) for p in caule], fill=255, width=7)
            for k in range(3, len(caule) - 1, 2):
                for sgn in (-1, 1):
                    if rng.random() < 0.8:
                        ang = ang0 + sgn * rng.uniform(0.6, 1.3)
                        comp = ch * rng.uniform(0.2, 0.32)
                        larg = comp * rng.uniform(0.14, 0.2)
                        cores = BAMBU_VELHA if rng.random() < 0.18 else BAMBU
                        x, y = caule[k]
                        pts = _curva(x, y, ang, comp, sgn * rng.uniform(0.3, 0.9), 10)
                        _lamina(dr, da, pts, larg, cores, rng.uniform(0.88, 1.12), "lanca")


def textura(var: str) -> bytes:
    from PIL import Image, ImageDraw
    from scipy import ndimage

    rng = np.random.default_rng(SEMENTE + len(var))
    w = h = TEX * SS
    cw, ch = w // COLS, h // ROWS
    fundo = {"arroz": ARROZ_VERDE[1], "selva": SELVA[1], "bambu": BAMBU[1]}[var]
    rgb = Image.new("RGB", (w, h), fundo)
    alfa = Image.new("L", (w, h), 0)
    for lin in range(ROWS):
        for col in range(COLS):
            # cada tufo num quadro largo próprio, depois reduzido (mesma escala nos dois eixos)
            # até caber no seu lugar da textura: nada corta na borda nem vaza para o vizinho; a
            # raiz fica embaixo, no meio
            qw = cw * 3
            q_rgb = Image.new("RGB", (qw, ch), fundo)
            q_a = Image.new("L", (qw, ch), 0)
            dr, da = ImageDraw.Draw(q_rgb), ImageDraw.Draw(q_a)
            _tufo(dr, da, qw / 2, ch - 3 * SS, ch - 8 * SS, var, rng)
            caixa = q_a.getbbox() or (0, 0, qw, ch)
            meia = max(qw / 2 - caixa[0], caixa[2] - qw / 2, 1)
            k = min(1.25, (cw / 2 - 2 * SS) / meia, (ch - 2 * SS) / max(ch - caixa[1], 1))
            nw, nh = max(1, round(qw * k)), max(1, round(ch * k))
            q_rgb = q_rgb.resize((nw, nh), Image.Resampling.LANCZOS)
            q_a = q_a.resize((nw, nh), Image.Resampling.LANCZOS)
            # recorta na largura do lugar (o que sobra dos lados é vazio)
            corte = max(0, (nw - cw) // 2)
            janela = (corte, 0, corte + min(nw, cw), nh)
            x0 = col * cw + (cw - (janela[2] - janela[0])) // 2
            y0 = lin * ch + (ch - nh)
            rgb.paste(q_rgb.crop(janela), (x0, y0))
            alfa.paste(q_a.crop(janela), (x0, y0))
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


# --------------------------------------------------------------------------------------------
# Bloco do Skins.luau
# --------------------------------------------------------------------------------------------
def _num(x: float) -> str:
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def _vec(v) -> str:
    return "{ " + ", ".join(_num(x) for x in v) + " }"


def bloco_luau(fit: dict) -> str:
    linhas = ["Skins.GHILLIE = {", "\tref = {"]
    for p in PARTES:
        linhas.append(f"\t\t{p.nome} = {_vec(fit['ref'][p.nome])},")
    linhas += ["\t},", "\tparts = {"]
    for p in PARTES:
        q = fit["parts"][p.nome]
        linhas.append(
            f"\t\t{p.nome} = {{ size = {_vec(q['size'])}, offset = {_vec(q['offset'])}, "
            f"tris = {q['tris']} }},"
        )
    linhas += ["\t},", f"\ttris = {fit['tris']},", "} :: GhillieFit"]
    return "\n".join(linhas)


def escrever_skins(fit: dict) -> None:
    s = SKINS.read_text("utf-8")
    novo = re.sub(
        r"(-- BEGIN GHILLIE[^\n]*\n).*?(\n-- END GHILLIE)",
        lambda m: m.group(1) + bloco_luau(fit) + m.group(2),
        s,
        count=1,
        flags=re.S,
    )
    if novo == s and "BEGIN GHILLIE" not in s:
        raise RuntimeError("bloco GHILLIE não encontrado no Skins.luau")
    SKINS.write_text(novo, "utf-8", newline="\n")
    stylua = shutil.which("stylua") or str(
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/vt65-tools/stylua/stylua.exe"
    )
    if Path(stylua).is_file():
        subprocess.run(
            [stylua, "--config-path", str(RAIZ / "stylua.toml"), str(SKINS)], check=False
        )
    else:
        print("aviso: rode o StyLua no Skins.luau (stylua.exe não encontrado)")


# --------------------------------------------------------------------------------------------
# Dentro do Blender
# --------------------------------------------------------------------------------------------
def _bl(v) -> tuple[float, float, float]:
    """Espaço do Roblox (x, y cima, z costas) -> Blender (x, y, z cima). O exportador glTF (+Y
    para cima) devolve (x, y, z) do Roblox."""
    return (float(v[0]), float(-v[2]), float(v[1]))


def _material(bpy, nome: str, imagem, cor: Cor | None = None):
    mat = bpy.data.materials.new(nome)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
        out = out or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Roughness"].default_value = 0.85
    if imagem is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = imagem
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        corte = nt.nodes.new("ShaderNodeMath")
        corte.operation = "GREATER_THAN"
        corte.inputs[1].default_value = 0.5
        nt.links.new(tex.outputs["Alpha"], corte.inputs[0])
        nt.links.new(corte.outputs[0], bsdf.inputs["Alpha"])
        for attr, val in (("blend_method", "CLIP"), ("surface_render_method", "DITHERED")):
            try:
                setattr(mat, attr, val)
            except (AttributeError, TypeError):
                pass
    elif cor is not None:
        bsdf.inputs["Base Color"].default_value = (*cor, 1.0)
    return mat


def _objeto(bpy, nome: str, m: Malha, mat):
    mesh = bpy.data.meshes.new(nome)
    mesh.from_pydata([_bl(p) for p in m.pos], [], [list(q) for q in m.quads])
    mesh.update()
    camada = mesh.uv_layers.new(name="UVMap")
    for li, loop in enumerate(mesh.loops):
        u, v = m.uv[loop.vertex_index]
        camada.data[li].uv = (float(u), float(v))
    try:
        mesh.normals_split_custom_set_from_vertices([_bl(n) for n in m.nrm])
    except (AttributeError, RuntimeError, TypeError) as e:
        print("normais personalizadas indisponíveis:", e)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(nome, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _caixa(bpy, nome: str, tam, centro, mat):
    w, h, d = tam
    x, y, z = w / 2, h / 2, d / 2
    vs = [(sx * x, sy * y, sz * z) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh = bpy.data.meshes.new(nome)
    mesh.from_pydata([_bl(v) for v in vs], [], faces)
    mesh.update()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(nome, mesh)
    obj.location = _bl(centro)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _previa(bpy, objs: dict, saida: Path) -> list[str]:
    cena = bpy.context.scene
    farda = _material(bpy, "Farda", None, (0.09, 0.1, 0.06))
    pele = _material(bpy, "Pele", None, (0.45, 0.25, 0.15))
    for p in PARTES:
        objs[p.nome].location = _bl(p.centro)
        _caixa(bpy, "Corpo_" + p.nome, p.ref, p.centro, pele if p.nome == "Head" else farda)
    for nome, tam, centro in MAOS_PES:
        _caixa(bpy, "Corpo_" + nome, tam, centro, pele if "Hand" in nome else farda)
    mundo = bpy.data.worlds.new("Ceu")
    cena.world = mundo
    try:
        mundo.use_nodes = True
        fundo = next(n for n in mundo.node_tree.nodes if n.type == "BACKGROUND")
        fundo.inputs[0].default_value = (0.42, 0.47, 0.52, 1.0)
        fundo.inputs[1].default_value = 0.9
    except (AttributeError, StopIteration):
        mundo.color = (0.42, 0.47, 0.52)
    sol = bpy.data.lights.new("Sol", type="SUN")
    sol.energy = 3.2
    luz = bpy.data.objects.new("Sol", sol)
    luz.rotation_euler = (math.radians(50), math.radians(10), math.radians(150))
    cena.collection.objects.link(luz)
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 8.2
    cam = bpy.data.objects.new("Camera", cam_data)
    cena.collection.objects.link(cam)
    cena.camera = cam
    cena.render.engine = "CYCLES"
    cena.cycles.device = "CPU"
    cena.cycles.samples = 24
    # muitos cartões em fila: com o limite padrão (8) o raio para no meio e pinta de preto
    cena.cycles.transparent_max_bounces = 128
    try:
        cena.cycles.use_denoising = True
    except AttributeError:
        pass
    cena.render.resolution_x, cena.render.resolution_y = 420, 640
    cena.render.film_transparent = False
    vistas = {
        "frente": ((0, 12, 3.3), (math.pi / 2, 0, math.pi)),
        "costas": ((0, -12, 3.3), (math.pi / 2, 0, 0)),
        "lado": ((12, 0, 3.3), (math.pi / 2, 0, math.pi / 2)),
    }
    feitos = []
    for nome, (loc, rot) in vistas.items():
        cam.location = loc
        cam.rotation_euler = rot
        caminho = saida / f"previa_{nome}.png"
        cena.render.filepath = str(caminho)
        bpy.ops.render.render(write_still=True)
        feitos.append(str(caminho))
    return feitos


def dentro_do_blender(argv: list[str]) -> None:
    import bpy

    saida = Path(argv[argv.index("--saida") + 1])
    textura_png = Path(argv[argv.index("--textura") + 1])
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    imagem = bpy.data.images.load(str(textura_png))
    try:
        imagem.alpha_mode = "STRAIGHT"
    except (AttributeError, TypeError):
        pass
    mat = _material(bpy, "Folhas", imagem)
    ms = malhas()
    objs = {p.nome: _objeto(bpy, "Ghillie_" + p.nome, ms[p.nome], mat) for p in PARTES}
    # conta na malha do Blender (não só no plano): cada polígono de n lados = n - 2 triângulos
    tris = {n: sum(len(f.vertices) - 2 for f in o.data.polygons) for n, o in objs.items()}
    fit = medidas(ms)
    for n, t in tris.items():
        fit["parts"][n]["tris"] = t
    fit["tris"] = sum(tris.values())
    if fit["tris"] > MAX_TRIS:
        raise RuntimeError(f"{fit['tris']} triângulos (meta: até {MAX_TRIS})")
    glb = saida / "ghillie.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB")
    print("ok", glb, "triângulos", fit["tris"])
    if "--previa" in argv:
        fit["previa"] = _previa(bpy, objs, saida)
    (saida / "ghillie_fit.json").write_text(json.dumps(fit, indent=1), "utf-8")


# --------------------------------------------------------------------------------------------
# Fora do Blender
# --------------------------------------------------------------------------------------------
def folha_previa(caminhos: list[str]) -> None:
    from PIL import Image, ImageDraw

    ims = [Image.open(c).convert("RGB") for c in caminhos]
    w, h = ims[0].size
    folha = Image.new("RGB", (w * len(ims) + 8 * (len(ims) + 1), h + 30), (54, 56, 52))
    d = ImageDraw.Draw(folha)
    for i, (im, c) in enumerate(zip(ims, caminhos, strict=True)):
        x = 8 + i * (w + 8)
        folha.paste(im, (x, 22))
        d.text((x, 4), Path(c).stem.replace("previa_", ""), fill=(240, 236, 220))
    PREVIA.parent.mkdir(parents=True, exist_ok=True)
    folha.save(PREVIA, optimize=True)
    print("ok", PREVIA.relative_to(RAIZ))


def main(argv: list[str]) -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    for nome in VARIANTES:
        (SAIDA / f"ghillie_{nome}.png").write_bytes(textura(nome))
        print("ok", f"assets/ghillie/ghillie_{nome}.png")
    blender = os.environ.get("BLENDER", BLENDER)
    if "--blender" in argv:
        blender = argv[argv.index("--blender") + 1]
    cmd = [
        blender,
        "-b",
        "--factory-startup",
        "-P",
        str(Path(__file__).resolve()),
        "--",
        "--saida",
        str(SAIDA),
        "--textura",
        str(SAIDA / "ghillie_arroz.png"),
    ]
    if "--previa" in argv:
        cmd.append("--previa")
    subprocess.run(cmd, check=True)
    fit = json.loads((SAIDA / "ghillie_fit.json").read_text("utf-8"))
    escrever_skins(fit)
    print("ok Skins.GHILLIE:", fit["tris"], "triângulos")
    if fit.get("previa"):
        folha_previa(fit["previa"])


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
    except ImportError:
        main(sys.argv[1:])
    else:
        args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
        dentro_do_blender(args)
