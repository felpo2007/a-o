"""Fuzis de precisão do VẠN TƯỜNG '65 (2026-11-12, pedido do dono: "faça sniper").

Modela no Blender, assa as texturas PBR (mesmos materiais e bake das facas, tools/faca) e exporta o
GLB de cada chave, com os pontos da arma no referencial da MeshPart publicada:
- m70: Winchester Model 70 de cano pesado com luneta Unertl 8x em montagens de alvo (USMC, 1965);
- mosin: Mosin-Nagant 91/30 com luneta PU 3,5x na montagem lateral e alavanca dobrada (VC/ENV).

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/armas.py -- m70 mosin

Convenções (as das outras armas do jogo, `Shared/GunModel.fit` e `Shared/WeaponArt`):
- trabalho em metros, eixo do cano no eixo Y do Blender, boca em -Y (no Roblox a boca fica em -Z
  da MeshPart: forward "-Z"), Z para cima, lado direito do atirador em -X (+X no Roblox);
- dois nós: "Arma" (a arma inteira, a maior peça: o GunModel.fit põe nela os pontos) e "Ferrolho"
  (alavanca e cabeça do ferrolho, animada no WeaponVisuals/Ferrolho em torno do eixo "bolt");
- atlas único 1024 x 1024 (cor, normal, metal/rugosidade), metal só no aço;
- `pontos.json`: muzzle (boca), sight (centro da ocular), front (centro da objetiva), grip (mão
  direita), support (mão esquerda), bolt (eixo do ferrolho), lowX, lengthM, eyeM (alívio de olho da
  luneta) em studs, no referencial local da MeshPart "Arma" (o importador gira o GLB 180° em Y e
  centra a peça na caixa dos vértices do nó), relendo o GLB exportado. O tools/weapon_landmarks.py
  lê este arquivo para gerar o Shared/WeaponArt.luau.

Medidas: as com fonte estão em `FONTES`; o resto é PLACEHOLDER (desenho a partir de fotos de época,
sem planta). Saídas: assets/blender/arma_<chave>/arma_<chave>.glb, pontos.json, metricas.json e
previa.png; texturas em assets/blender/_trabalho/arma_<chave>/.
"""

from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(RAIZ / "tools" / "faca"))
import comum  # noqa: E402
import materiais  # noqa: E402
import produzir as faca  # noqa: E402  (bake e composição das texturas das facas)

M_POR_STUD = 0.28
PASTA = {"m70": "arma_m70_unertl", "mosin": "arma_mosin_pu"}
MAT_MADEIRA, MAT_ACO, MAT_VIDRO = 0, 1, 2

FONTES = {
    "m70": {
        "comprimento_cano_m": "0.61 (24 pol.: usmcweaponry.com, 'medium-heavy target barrels')",
        "comprimento_total_m": "1.13 (PLACEHOLDER: ~44,5 pol. com cano de 24 pol.)",
        "luneta_comprimento_m": "0.61 (24 pol.: anúncio CT Firearms Auction, Unertl USMC 8x)",
        "luneta_objetiva_m": "0.032 (1 1/4 pol.: anúncio Rock Island Auction)",
        "luneta_tubo_m": "0.019 (3/4 pol.: PLACEHOLDER, tubo das Unertl de alvo)",
        "altura_luneta_m": "0.050 (PLACEHOLDER: montagens de alvo sobre blocos)",
        "alivio_olho_m": "0.075 (PLACEHOLDER)",
        "coronha": "PLACEHOLDER (coronha de alvo com pente alto e guarda-mão largo, de fotos)",
    },
    "mosin": {
        "comprimento_total_m": "1.232 (wiki:Mosin–Nagant; snipercentral.com: 48,5 pol.)",
        "comprimento_cano_m": "0.730 (wiki; snipercentral.com: 28,7 pol.)",
        "luneta_comprimento_m": "0.169 (wiki:PU_scope)",
        "alivio_olho_m": "0.072 (wiki:PU_scope)",
        "luneta_tubo_m": "0.025 (PLACEHOLDER)",
        "altura_luneta_m": "0.058 (PLACEHOLDER: montagem lateral sobre a caixa da culatra)",
        "coronha": "PLACEHOLDER (coronha reta de bétula, de fotos)",
    },
}


def log(*a) -> None:
    print("[ARMAS]", *a, flush=True)


# ------------------------------------------------------------------ montador de malha
class Malha:
    """Vértices (m, Blender) e faces com material e nó (0 = Arma, 1 = Ferrolho)."""

    def __init__(self) -> None:
        self.v: list[tuple[float, float, float]] = []
        self.f: list[list[int]] = []
        self.mat: list[int] = []
        self.no: list[int] = []

    def vert(self, x: float, y: float, z: float) -> int:
        self.v.append((float(x), float(y), float(z)))
        return len(self.v) - 1

    def face(self, idx: list[int], mat: int, no: int) -> None:
        self.f.append(list(idx))
        self.mat.append(mat)
        self.no.append(no)

    def aneis(
        self, rings: list[list[int]], mat: int, no: int, cap0: int | None, cap1: int | None
    ) -> None:
        k = len(rings[0])
        for a, b in zip(rings[:-1], rings[1:], strict=True):
            for i in range(k):
                j = (i + 1) % k
                self.face([a[i], a[j], b[j], b[i]], mat, no)
        if cap0 is not None:
            self.face(list(reversed(rings[0])), cap0, no)
        if cap1 is not None:
            self.face(list(rings[-1]), cap1, no)

    # perfil por estações ao longo do cano (d = distância da soleira, y = -d)
    def loft(
        self, secs, mat: int, no: int = 0, k: int = 32, caps=(True, True), cap_mat=None
    ) -> None:
        """secs: [(d, topo_z, base_z, meia_largura, expoente, centro_x)]; superelipse."""
        rings = []
        for s in secs:
            d, top, bot, hw, n = s[:5]
            cx = s[5] if len(s) > 5 else 0.0
            cz, hh = (top + bot) / 2, (top - bot) / 2
            ring = []
            for i in range(k):
                a = 2 * math.pi * i / k
                c, sn = math.cos(a), math.sin(a)
                x = cx + hw * math.copysign(abs(c) ** (2 / n), c)
                z = cz + hh * math.copysign(abs(sn) ** (2 / n), sn)
                ring.append(self.vert(x, -d, z))
            rings.append(ring)
        cm = mat if cap_mat is None else cap_mat
        self.aneis(rings, mat, no, cm if caps[0] else None, cm if caps[1] else None)

    def torno(
        self, perfil, ax: float, az: float, mat: int, no: int = 0, k: int = 24, cap0=None, cap1=None
    ) -> None:
        """Sólido de revolução em torno de um eixo paralelo ao cano: perfil [(d, r)]."""
        rings = []
        for d, r in perfil:
            ring = []
            for i in range(k):
                a = 2 * math.pi * i / k
                ring.append(self.vert(ax + r * math.cos(a), -d, az + r * math.sin(a)))
            rings.append(ring)
        self.aneis(rings, mat, no, cap0, cap1)

    def cilindro_z(
        self, x: float, d: float, z0: float, z1: float, r: float, mat: int, no: int = 0, k: int = 16
    ):
        """Cilindro vertical (tambor de elevação)."""
        rings = []
        for z in (z0, z1):
            rings.append(
                [
                    self.vert(
                        x + r * math.cos(2 * math.pi * i / k),
                        -d + r * math.sin(2 * math.pi * i / k),
                        z,
                    )
                    for i in range(k)
                ]
            )
        self.aneis(rings, mat, no, mat, mat)

    def cilindro_x(
        self, x0: float, x1: float, d: float, z: float, r: float, mat: int, no: int = 0, k: int = 16
    ):
        rings = []
        for x in (x0, x1):
            rings.append(
                [
                    self.vert(
                        x,
                        -d + r * math.cos(2 * math.pi * i / k),
                        z + r * math.sin(2 * math.pi * i / k),
                    )
                    for i in range(k)
                ]
            )
        self.aneis(rings, mat, no, mat, mat)

    def caixa(self, x0, x1, d0, d1, z0, z1, mat: int, no: int = 0) -> None:
        y0, y1 = -d0, -d1
        p = [self.vert(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
        for f in (
            (0, 1, 3, 2),
            (4, 6, 7, 5),
            (0, 4, 5, 1),
            (2, 3, 7, 6),
            (0, 2, 6, 4),
            (1, 5, 7, 3),
        ):
            self.face([p[i] for i in f], mat, no)

    def esfera(self, cx, d, cz, r, mat: int, no: int = 0, seg: int = 12, an: int = 8) -> None:
        top = self.vert(cx, -d, cz + r)
        rings = []
        for j in range(1, an):
            t = math.pi * j / an
            rings.append(
                [
                    self.vert(
                        cx + r * math.sin(t) * math.cos(2 * math.pi * i / seg),
                        -d + r * math.sin(t) * math.sin(2 * math.pi * i / seg),
                        cz + r * math.cos(t),
                    )
                    for i in range(seg)
                ]
            )
        bot = self.vert(cx, -d, cz - r)
        for i in range(seg):
            j = (i + 1) % seg
            self.face([top, rings[0][i], rings[0][j]], mat, no)
            self.face([bot, rings[-1][j], rings[-1][i]], mat, no)
        self.aneis(rings, mat, no, None, None)

    def tubo(self, pts, r: float, mat: int, no: int = 0, k: int = 10, achatar: float = 1.0) -> None:
        """Tubo ao longo de uma poligonal (x, d, z), com tampas."""
        P = [np.array([p[0], -p[1], p[2]], float) for p in pts]
        rings = []
        ref = np.array([1.0, 0.0, 0.0])
        for i, p in enumerate(P):
            t = P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]
            t /= np.linalg.norm(t)
            if abs(np.dot(ref, t)) > 0.95:
                ref = np.array([0.0, 0.0, 1.0])
            u = np.cross(t, ref)
            u /= np.linalg.norm(u)
            w = np.cross(t, u)
            ref = w
            ring = []
            for j in range(k):
                a = 2 * math.pi * j / k
                q = p + r * (math.cos(a) * u * achatar + math.sin(a) * w)
                ring.append(self.vert(*q))
            rings.append(ring)
        self.aneis(rings, mat, no, mat, mat)

    def objeto(self, nome: str) -> bpy.types.Object:
        me = bpy.data.meshes.new(nome)
        me.from_pydata(self.v, [], self.f)
        me.update(calc_edges=True)
        me.polygons.foreach_set("material_index", np.array(self.mat, np.int32))
        for nm, arr in (("no", self.no), ("dup", [0] * len(self.no))):
            a = me.attributes.new(nm, "INT", "FACE")
            a.data.foreach_set("value", np.array(arr, np.int32))
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        me.update()
        obj = bpy.data.objects.new(nome, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# ------------------------------------------------------------------ as armas
def interp(keys, d: float) -> list[float]:
    """Interpolação linear das estações da coronha [(d, topo, base, meia largura, expoente)]."""
    for a, b in zip(keys[:-1], keys[1:], strict=True):
        if a[0] <= d <= b[0]:
            t = (d - a[0]) / max(b[0] - a[0], 1e-9)
            return [a[i] + (b[i] - a[i]) * t for i in range(5)]
    return list(keys[-1][:5]) if d > keys[-1][0] else list(keys[0][:5])


def estacoes(keys, passo: float = 0.02) -> list[list[float]]:
    d0, d1 = keys[0][0], keys[-1][0]
    ds = sorted(
        set(
            [round(d0 + i * passo, 4) for i in range(int((d1 - d0) / passo) + 1)]
            + [k[0] for k in keys]
        )
    )
    return [[d] + interp(keys, d)[1:] for d in ds]


def m70() -> tuple[Malha, dict]:
    g = Malha()
    L = 1.13
    HS = 0.050  # eixo da luneta acima do eixo do cano
    # coronha de alvo (nogueira): pente alto para o olho na luneta, punho de pistola e
    # guarda-mão largo
    coronha = [
        (0.006, -0.012, -0.148, 0.021, 3.2),
        (0.10, -0.002, -0.128, 0.022, 3.2),
        (0.18, 0.004, -0.108, 0.021, 3.0),
        (0.215, -0.004, -0.100, 0.019, 2.8),
        (0.245, -0.018, -0.112, 0.017, 2.6),
        (0.270, -0.022, -0.118, 0.017, 2.6),
        (0.292, -0.020, -0.086, 0.0175, 2.6),
        (0.310, -0.012, -0.071, 0.019, 2.8),
        (0.340, -0.006, -0.073, 0.021, 3.0),
        (0.470, -0.006, -0.075, 0.021, 3.0),
        (0.520, -0.006, -0.066, 0.024, 3.2),
        (0.800, -0.008, -0.058, 0.026, 3.2),
        (0.845, -0.010, -0.052, 0.024, 3.0),
        (0.860, -0.015, -0.046, 0.019, 2.6),
    ]
    g.loft(estacoes(coronha), MAT_MADEIRA)
    # soleira de aço
    g.loft([(0.0, -0.013, -0.149, 0.0215, 3.2), (0.0062, -0.012, -0.148, 0.0213, 3.2)], MAT_ACO)
    # caixa da culatra, cano pesado (com a alma) e espiga
    g.torno([(0.300, 0.0172), (0.520, 0.0175)], 0, 0, MAT_ACO, k=28, cap0=MAT_ACO, cap1=MAT_ACO)
    g.torno(
        [
            (0.520, 0.0155),
            (0.60, 0.0150),
            (0.75, 0.0135),
            (1.10, 0.0112),
            (L, 0.0112),
            (L, 0.0039),
            (L - 0.03, 0.0039),
        ],
        0,
        0,
        MAT_ACO,
        k=28,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    g.caixa(-0.004, 0.004, 0.300, 0.318, -0.016, -0.004, MAT_ACO)  # espiga
    # guarda-mato, gatilho e chapa do depósito (5 cartuchos)
    g.tubo(
        [
            (0, 0.322, -0.068),
            (0, 0.326, -0.090),
            (0, 0.345, -0.098),
            (0, 0.380, -0.093),
            (0, 0.396, -0.071),
        ],
        0.0032,
        MAT_ACO,
        achatar=0.6,
    )
    g.caixa(-0.002, 0.002, 0.340, 0.346, -0.088, -0.070, MAT_ACO)
    g.caixa(-0.0165, 0.0165, 0.352, 0.470, -0.0775, -0.0735, MAT_ACO)
    # blocos de alvo (receptor e cano) e montagens da Unertl: traseira com os tambores micrométricos
    for dB, zb, traseira in ((0.505, 0.0172, True), (0.690, 0.0130, False)):
        g.caixa(-0.0075, 0.0075, dB - 0.007, dB + 0.007, zb - 0.003, 0.026, MAT_ACO)
        g.caixa(-0.006, 0.006, dB - 0.009, dB + 0.009, 0.026, HS - 0.0085, MAT_ACO)
        g.torno(
            [
                (dB - 0.009, 0.0098),
                (dB - 0.009, 0.0128),
                (dB + 0.009, 0.0128),
                (dB + 0.009, 0.0098),
            ],
            0,
            HS,
            MAT_ACO,
            k=24,
            cap0=None,
            cap1=None,
        )
        if traseira:
            g.cilindro_z(0, dB, HS + 0.012, HS + 0.026, 0.0075, MAT_ACO)  # elevação
            g.cilindro_x(-0.026, -0.012, dB, HS, 0.0065, MAT_ACO)  # deriva, lado direito
    # luneta Unertl 8x: ocular, tubo de 3/4 pol. e objetiva de 1 1/4 pol. (as lentes são vidro)
    g.torno(
        [
            (0.262, 0.0118),
            (0.256, 0.0118),
            (0.256, 0.0152),
            (0.300, 0.0152),
            (0.316, 0.0100),
            (0.330, 0.0095),
            (0.800, 0.0095),
            (0.822, 0.0122),
            (0.840, 0.0162),
            (0.866, 0.0162),
            (0.866, 0.0136),
            (0.858, 0.0136),
        ],
        0,
        HS,
        MAT_ACO,
        k=28,
        cap0=MAT_VIDRO,
        cap1=MAT_VIDRO,
    )
    # zarelhos da bandoleira
    g.tubo(
        [(0, 0.080, -0.128), (0, 0.083, -0.140), (0, 0.090, -0.140), (0, 0.093, -0.128)],
        0.0018,
        MAT_ACO,
        k=8,
    )
    g.tubo(
        [(0, 0.770, -0.056), (0, 0.773, -0.068), (0, 0.780, -0.068), (0, 0.783, -0.056)],
        0.0018,
        MAT_ACO,
        k=8,
    )
    # FERROLHO (nó 1): capa traseira, alavanca baixa (inclinada 25° para baixo, para passar sob a
    # luneta ao abrir 90°) e bola
    g.torno(
        [(0.282, 0.0095), (0.288, 0.0118), (0.300, 0.0118)],
        0,
        0,
        MAT_ACO,
        no=1,
        k=20,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    g.caixa(-0.004, 0.004, 0.282, 0.290, 0.011, 0.016, MAT_ACO, no=1)  # trava de segurança
    a = math.radians(-25)
    tip = (-0.050 * math.cos(a), 0.334, 0.050 * math.sin(a))
    g.tubo(
        [(-0.006, 0.330, 0.0), (-0.030 * math.cos(a), 0.332, 0.030 * math.sin(a)), tip],
        0.0042,
        MAT_ACO,
        no=1,
    )
    g.esfera(tip[0] - 0.006, tip[1] + 0.001, tip[2] - 0.003, 0.0095, MAT_ACO, no=1)
    pontos = {
        "muzzle": (0.0, L, 0.0),
        "sight": (0.0, 0.262, HS),
        "front": (0.0, 0.858, HS),
        "grip": (0.0, 0.275, -0.068),
        "support": (0.0, 0.525, -0.046),
        "bolt": (0.0, 0.300, 0.0),
        "eyeM": 0.075,
        "comprimento_m": L,
    }
    return g, pontos


def mosin() -> tuple[Malha, dict]:
    g = Malha()
    L = 1.232
    HS = 0.058
    # coronha reta de bétula (sem punho de pistola) e guarda-mão de cima
    coronha = [
        (0.006, -0.040, -0.167, 0.020, 3.0),
        (0.10, -0.036, -0.140, 0.021, 3.0),
        (0.20, -0.032, -0.112, 0.020, 2.8),
        (0.28, -0.030, -0.088, 0.0175, 2.5),
        (0.31, -0.028, -0.080, 0.017, 2.5),
        (0.34, -0.016, -0.074, 0.019, 2.7),
        (0.37, -0.010, -0.070, 0.021, 2.9),
        (0.505, -0.008, -0.064, 0.021, 2.9),
        (0.540, -0.006, -0.050, 0.019, 2.8),
        (0.900, -0.004, -0.042, 0.0175, 2.6),
        (1.130, -0.004, -0.034, 0.015, 2.5),
        (1.150, -0.007, -0.030, 0.012, 2.4),
    ]
    g.loft(estacoes(coronha), MAT_MADEIRA)
    g.loft(
        [
            (0.540, 0.0165, -0.002, 0.016, 2.2),
            (0.690, 0.0165, -0.002, 0.0155, 2.2),
            (0.840, 0.0150, -0.002, 0.0145, 2.2),
        ],
        MAT_MADEIRA,
    )
    g.loft(
        [(0.0, -0.041, -0.168, 0.0205, 3.0), (0.0062, -0.040, -0.167, 0.0203, 3.0)], MAT_ACO
    )  # soleira
    # caixa da culatra, cano (com a alma), braçadeiras, massa com túnel e alça
    g.torno([(0.335, 0.0160), (0.505, 0.0160)], 0, 0, MAT_ACO, k=28, cap0=MAT_ACO, cap1=MAT_ACO)
    g.torno(
        [
            (0.505, 0.0150),
            (0.55, 0.0140),
            (0.70, 0.0125),
            (1.10, 0.0105),
            (L, 0.0095),
            (L, 0.0039),
            (L - 0.03, 0.0039),
        ],
        0,
        0,
        MAT_ACO,
        k=24,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    g.loft([(0.855, 0.0145, -0.045, 0.0190, 2.5), (0.873, 0.0145, -0.045, 0.0190, 2.5)], MAT_ACO)
    g.loft([(1.125, 0.0125, -0.037, 0.0165, 2.5), (1.143, 0.0125, -0.037, 0.0165, 2.5)], MAT_ACO)
    g.caixa(-0.0012, 0.0012, 1.208, 1.214, 0.0090, 0.0215, MAT_ACO)
    g.tubo(
        [
            (-0.0085, 1.211, 0.012),
            (-0.006, 1.211, 0.0205),
            (0.0, 1.211, 0.0235),
            (0.006, 1.211, 0.0205),
            (0.0085, 1.211, 0.012),
        ],
        0.0012,
        MAT_ACO,
        k=8,
    )
    g.caixa(-0.012, 0.012, 0.580, 0.640, 0.0115, 0.0195, MAT_ACO)
    g.caixa(-0.008, 0.008, 0.585, 0.640, 0.0195, 0.0225, MAT_ACO)
    # depósito de 5, guarda-mato e gatilho
    g.caixa(-0.0165, 0.0165, 0.385, 0.465, -0.0865, -0.062, MAT_ACO)
    g.tubo(
        [
            (0, 0.322, -0.068),
            (0, 0.326, -0.088),
            (0, 0.345, -0.093),
            (0, 0.372, -0.088),
            (0, 0.384, -0.070),
        ],
        0.0030,
        MAT_ACO,
        achatar=0.6,
    )
    g.caixa(-0.002, 0.002, 0.343, 0.349, -0.086, -0.068, MAT_ACO)
    # montagem lateral (lado esquerdo, +X), anéis, tambores e a luneta PU 3,5x
    g.caixa(0.0155, 0.0225, 0.370, 0.470, -0.006, 0.014, MAT_ACO)
    g.caixa(0.0090, 0.0200, 0.380, 0.460, 0.014, HS - 0.0110, MAT_ACO)
    for dR in (0.372, 0.468):
        g.torno(
            [
                (dR - 0.006, 0.0125),
                (dR - 0.006, 0.0156),
                (dR + 0.006, 0.0156),
                (dR + 0.006, 0.0125),
            ],
            0,
            HS,
            MAT_ACO,
            k=24,
        )
    g.torno(
        [
            (0.341, 0.0102),
            (0.336, 0.0102),
            (0.336, 0.0140),
            (0.356, 0.0140),
            (0.362, 0.0125),
            (0.480, 0.0125),
            (0.486, 0.0135),
            (0.505, 0.0135),
            (0.505, 0.0110),
            (0.499, 0.0110),
        ],
        0,
        HS,
        MAT_ACO,
        k=28,
        cap0=MAT_VIDRO,
        cap1=MAT_VIDRO,
    )
    g.cilindro_z(0.0, 0.420, HS + 0.010, HS + 0.023, 0.011, MAT_ACO)  # elevação (1 a 13)
    g.cilindro_x(0.010, 0.023, 0.420, HS, 0.0095, MAT_ACO)  # deriva, lado esquerdo
    # FERROLHO (nó 1): pomo de armar, corpo à vista e a alavanca dobrada para baixo (de sniper)
    g.torno(
        [(0.300, 0.0108), (0.318, 0.0115), (0.334, 0.0095), (0.340, 0.006)],
        0,
        0,
        MAT_ACO,
        no=1,
        k=20,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    g.tubo(
        [
            (-0.007, 0.352, 0.0),
            (-0.030, 0.352, -0.004),
            (-0.040, 0.349, -0.020),
            (-0.044, 0.347, -0.034),
        ],
        0.0042,
        MAT_ACO,
        no=1,
    )
    g.esfera(-0.045, 0.347, -0.043, 0.0100, MAT_ACO, no=1)
    pontos = {
        "muzzle": (0.0, L, 0.0),
        "sight": (0.0, 0.341, HS),
        "front": (0.0, 0.499, HS),
        "grip": (0.0, 0.300, -0.052),
        "support": (0.0, 0.550, -0.035),
        "bolt": (0.0, 0.320, 0.0),
        "eyeM": 0.072,
        "comprimento_m": L,
    }
    return g, pontos


ARMAS = {"m70": m70, "mosin": mosin}


# ------------------------------------------------------------------ materiais
def madeira(nome: str, escuro, claro, polido: float):
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    n = materiais.Nos(mat)
    cor, rug, alt = materiais._madeira(n, escuro, claro, polido=polido)
    return mat, n.finalizar(cor, rug, 0.0, alt)


def vidro(nome: str):
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    n = materiais.Nos(mat)
    p = n.P()
    tom = n.mapa(n.ruido(p, 0.08, 2.0), 0.3, 0.7)
    cor = n.mix(tom, n.rgb(0.006, 0.008, 0.014), n.rgb(0.02, 0.03, 0.05))
    return mat, n.finalizar(cor, 0.06, 0.0, None)


def materiais_de(chave: str) -> dict:
    if chave == "m70":
        mad = madeira("madeira_m70", (0.045, 0.020, 0.009), (0.15, 0.075, 0.035), 0.25)  # nogueira
    else:
        mad = madeira(
            "madeira_mosin", (0.075, 0.032, 0.012), (0.24, 0.12, 0.05), 0.3
        )  # bétula com goma-laca
    return {"madeira": mad, "aco_azul": materiais.criar("aco_azul"), "vidro": vidro("vidro")}


# ------------------------------------------------------------------ pontos e prévia
def para_roblox(p, c: np.ndarray) -> list[float]:
    """(x, d, z) do montador (m) -> studs no referencial local da MeshPart (180° em Y, centrada)."""
    x, d, z = p
    y = -d
    r = np.array([-x, z, y]) / M_POR_STUD - c
    return [round(float(v), 4) for v in r]


def medir(pontos: dict, caminho: Path) -> dict:
    nos = faca.ler_nos(caminho)
    R = nos["Arma"] * np.array([-1.0, 1.0, -1.0])
    lo, hi = R.min(axis=0), R.max(axis=0)
    c = (lo + hi) / 2
    out = {
        k: para_roblox(pontos[k], c)
        for k in ("muzzle", "sight", "front", "grip", "support", "bolt")
    }
    v = R - c
    out["lowX"] = round(float(v[:, 0].min() - out["grip"][0]), 4)
    out["lengthM"] = round(float(hi[2] - lo[2]) * M_POR_STUD, 4)
    out["eyeM"] = pontos["eyeM"]
    out["forward"] = "-Z"
    out["tamanho"] = [round(float(x), 4) for x in hi - lo]
    out["_conferencia"] = {
        # a boca deve ser o vértice mais à frente (−Z) e a soleira o mais atrás
        "boca_vs_vertice_mais_a_frente": round(out["muzzle"][2] - float(lo[2] - c[2]), 4),
        "comprimento_ficha_m": pontos["comprimento_m"],
    }
    return out


def previa(objs, caminho: Path) -> None:
    cena = bpy.context.scene
    cena.render.engine = "CYCLES"
    cena.cycles.device = "CPU"
    cena.cycles.samples = 24
    cena.render.resolution_x, cena.render.resolution_y = 1600, 560
    cena.render.film_transparent = False
    w = cena.world
    if hasattr(w, "use_nodes") and not w.use_nodes:
        w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.55, 0.6, 0.65, 1.0)
        bg.inputs[1].default_value = 0.8
    sol = bpy.data.objects.new("Sol", bpy.data.lights.new("Sol", "SUN"))
    sol.data.energy = 3.0
    sol.rotation_euler = (math.radians(50), 0, math.radians(-60))
    cena.collection.objects.link(sol)
    lo = np.min([np.array(o.bound_box).min(0) + np.array(o.location) for o in objs], axis=0)
    hi = np.max([np.array(o.bound_box).max(0) + np.array(o.location) for o in objs], axis=0)
    ctr = (lo + hi) / 2
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = float(hi[1] - lo[1]) * 1.08
    cam.location = (float(ctr[0]) - 1.5, float(ctr[1]), float(ctr[2]) + 0.12)  # lado direito (−X)
    cam.rotation_euler = (math.radians(85), 0, math.radians(-90))
    cena.collection.objects.link(cam)
    cena.camera = cam
    cena.render.filepath = str(caminho)
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------ produção
def produzir(chave: str) -> dict:
    t0 = time.time()
    cena = faca.cena_cpu()
    g, pontos = ARMAS[chave]()
    obj = g.objeto(chave)
    mats = materiais_de(chave)
    for nome in ("madeira", "aco_azul", "vidro"):
        obj.data.materials.append(mats[nome][0])
    faca.triangular_e_vivas(obj, set())
    comum.selecionar_so(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")
    uso = faca.empacotar(obj)
    arma = faca.extrair(obj, "Arma", lambda no, dup: no == 0)
    ferrolho = faca.extrair(obj, "Ferrolho", lambda no, dup: no == 1)
    bpy.data.objects.remove(obj)
    alvos = [arma, ferrolho]
    cena.world.light_settings.distance = 0.012
    bk = faca.assar(cena, alvos, mats)
    pasta = comum.SAIDA / PASTA[chave]
    texturas, info = faca.compor(bk["imgs"], comum.TRABALHO / PASTA[chave])
    caminho = pasta / f"{PASTA[chave]}.glb"
    exp = comum.exportar_glb(
        [("Arma", arma), ("Ferrolho", ferrolho)], caminho, texturas, metal=True
    )
    pts = medir(pontos, caminho)
    tris = {
        nome: len(comum.arrays_malha(o)[3]) // 3
        for nome, o in (("Arma", arma), ("Ferrolho", ferrolho))
    }
    (pasta / "pontos.json").write_text(
        json.dumps(pts, ensure_ascii=False, indent=1) + "\n", "utf-8"
    )
    met = {
        "chave": chave,
        "triangulos": tris,
        "textura_px": faca.TEX,
        "mb": exp["mb"],
        "uso_uv": uso,
        "texturas": info,
        "bake_s": bk["tempos"],
        "medidas_reais": FONTES[chave],
        "comprimento_m": pts["lengthM"],
    }
    comum.gravar_json(pasta / "metricas.json", met)
    try:
        previa(alvos, pasta / "previa.png")
    except Exception as e:  # a prévia não segura a produção
        log("prévia falhou:", e)
    log(
        chave,
        json.dumps({**met, "pontos": pts}, ensure_ascii=False),
        f"total {time.time() - t0:.0f} s",
    )
    return met


def main() -> None:
    for chave in comum.argumentos() or list(ARMAS):
        produzir(chave)


if __name__ == "__main__":
    main()
