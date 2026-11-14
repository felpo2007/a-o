"""Vila grande no centro do mapa e estradas para os veículos (pedido do dono, 2026-11-12).

Chamado pelo tools/crop_world.py depois do recorte, do riacho e da base dos EUA. Escreve:
  src/ServerStorage/VT65Build/Data/Village.luau  lotes, casas, praça, pagode, casa comunal e becos
  src/ServerStorage/VT65Build/Data/Roads.luau    estradas: traçado, largura e altura do leito
e tira das feições (Features) a lâmina d'água, o dique e a sebe que caem na estrada ou na vila (o
dique é cortado só na largura da passagem).

Vila "Xóm Gò" (nome de design; não há vila da carta de 1965 no morrote do centro):
  - rua principal no rumo das curvas de nível do flanco leste do morrote (o rumo que pede menos
    corte do terreno), com praça do mercado no meio, pagode ao norte, casa comunal (đình) ao sul,
    poço na praça, becos atrás das casas e duas travessas;
  - lotes de 12 x 14 m em duas fileiras de cada lado da rua; casa de até 8,5 x 8,5 m na frente do
    lote, quintal atrás;
  - cada casa ganha variante (1..12: vila_casa_XX), tom, escala (±8%) e anexos (varanda, cozinha,
    celeiro, horta, cerca, pote, meda, varal) de modo que duas casas a menos de 30 m nunca tenham a
    mesma combinação.
O terreno não é deformado além do patamar de cada casa (TerrainBuilder).

Estradas (terra batida):
  - principal (7 m: o M48 tem 3,6 m): árvore geradora mínima de custo de terreno entre os dois QGs e
    os 15 pontos fortes, passando pela rua da vila;
  - secundárias (5 m): voltas por fora, ao norte e ao sul, de QG a QG;
  - custo do caminho: rampa (acima de 30% não passa), riacho (atravessa pouco), casa (não passa);
    o leito sobe e desce no máximo GRADE_MAX (o M48 sobe ~30% em terra seca, VehicleDrive).
Determinístico: só depende do terreno e das casas, então rodar de novo dá o mesmo resultado.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from skimage.graph import MCP_Geometric

STUD_M = 0.28
ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "src/ServerStorage/VT65Build/Data"

# ---------- vila ----------
VILA_NOME = "Xóm Gò"
# centro (praça) procurado nesta janela da grade de 1965: o morrote levado para perto do centro do
# mapa (crop_world.MORRO_PARA, cume em E 269,815 / N 1692,99)
VILA_E = (269780.0, 269870.0)
VILA_N = (1692930.0, 1693050.0)
# D-115 (pedido do dono: "aumente as cabanas de todo jogo e o tamanho das vilas"; "cabanas muito
# pequenas no mapa"): casas 30% maiores (o soldado tem 2,0 m, D-98; o beiral ficava na altura da
# cabeça dele) e a vila cresce junto: lotes, passo, travessas, praça, pagode e casa comunal. O jogo
# lê a escala em Village.houseScale.
ESCALA_CASA = 1.3
LOTE_W, LOTE_D = 12.0 * ESCALA_CASA, 14.0 * ESCALA_CASA  # m
CASA_MAX = 8.5 * ESCALA_CASA  # m: a casa cabe neste quadrado (os modelos únicos do Blender também)
RUA_W = 7.0  # rua principal da vila (é a estrada principal)
PASSO_U = 14.0 * ESCALA_CASA  # m entre lotes ao longo da rua
SLOTS = 17  # lotes por fileira
TRAVESSAS = (-56.0 * ESCALA_CASA, 56.0 * ESCALA_CASA)  # u (m) das travessas: os lotes ali saem
PRACA_U = 21.0 * ESCALA_CASA  # meia largura da praça ao longo da rua
CORTE_MAX = 2.6 * ESCALA_CASA  # m: desnível máximo dentro da pegada da casa (o patamar corta)
VIZINHO_M = 30.0 * ESCALA_CASA  # duas casas a menos disto nunca saem iguais
N_VARIANTES = 12
N_TONS = 4
ANEXOS = ("varanda", "cozinha", "celeiro", "horta", "cerca", "pote", "meda", "varal")

# ---------- estradas ----------
LARGURA = {"principal": 7.0, "secundaria": 5.0, "rua": 6.0, "beco": 2.5, "trilha": 3.0}
GRADE_MAX = 0.15  # rampa máxima do leito (15%, 8,5°)
GRADE_PROIBIDA = 0.30  # terreno mais íngreme que isto não recebe estrada
TALUDE_M = 3.0  # faixa de cada lado onde o leito se junta ao terreno
BORDA_M = 25.0  # estrada a pelo menos isto da borda da área
ANEL_M = 45.0  # as voltas por fora correm a esta distância da borda (D-114; 70 no mapa de 1 km)
# pontos de passagem (E, N da grade de 1965) das voltas por fora, do QG do VC ao dos EUA, pelo
# norte e pelo sul (D-114, mapa de 500 m: ao norte da ponta da vila e ao norte da trincheira sul)
ANEL_PONTOS = (
    [(269760, 1693095), (270030, 1693095)],
    [(269750, 1692690), (269890, 1692700), (270060, 1692700)],
)
BASE_FOLGA_M = 1.0  # a estrada do mapa passa a pelo menos isto da área de cada base


def _lin(a, b, t):
    return a + (b - a) * t


class Terreno:
    """Alturas (m) e classes da grade recortada, com amostra bilinear em studs."""

    def __init__(self, g: dict):
        self.g = g
        self.cell = g["cell"]
        self.ox, self.oz = g["ox"], g["oz"]
        self.h = (g["heights"].astype(float) - g["hoff"]) / 100.0
        self.cls = g["cls"]
        self.H, self.W = self.h.shape

    def rc(self, x, z):
        return (np.asarray(z) - self.oz) / self.cell - 0.5, (
            np.asarray(x) - self.ox
        ) / self.cell - 0.5

    def altura(self, x, z):
        """metros, bilinear entre centros de célula (como WorldData.heightAt)"""
        r, c = self.rc(x, z)
        r0, c0 = np.floor(r).astype(int), np.floor(c).astype(int)
        tr, tc = r - r0, c - c0

        def at(rr, cc):
            return self.h[np.clip(rr, 0, self.H - 1), np.clip(cc, 0, self.W - 1)]

        return (at(r0, c0) * (1 - tc) + at(r0, c0 + 1) * tc) * (1 - tr) + (
            at(r0 + 1, c0) * (1 - tc) + at(r0 + 1, c0 + 1) * tc
        ) * tr

    def classe(self, x, z):
        r = np.clip(np.floor((np.asarray(z) - self.oz) / self.cell).astype(int), 0, self.H - 1)
        c = np.clip(np.floor((np.asarray(x) - self.ox) / self.cell).astype(int), 0, self.W - 1)
        return self.cls[r, c]

    def centro(self, r, c):
        return self.ox + (c + 0.5) * self.cell, self.oz + (r + 0.5) * self.cell


# ---------- geometria ----------
def gira(u: float, v: float, ang: float) -> tuple[float, float]:
    """quadro da vila (u ao longo da rua, v de lado) -> deslocamento em studs (x, z) do mundo"""
    ca, sa = math.cos(ang), math.sin(ang)
    return (u * ca - v * sa) / STUD_M, (u * sa + v * ca) / STUD_M


def pegada(x, z, yaw, w, d, n=4):
    """pontos (studs) num retângulo w x d (m) centrado em (x, z), girado por yaw (Roblox)"""
    ca, sa = math.cos(yaw), math.sin(yaw)
    pts = []
    for i in range(n + 1):
        for j in range(n + 1):
            lx = (i / n - 0.5) * w / STUD_M
            lz = (j / n - 0.5) * d / STUD_M
            pts.append((x + lx * ca + lz * sa, z - lx * sa + lz * ca))
    return np.array(pts)


def yaw_de(ang: float) -> float:
    """rumo da rua no quadro do mundo -> giro Y do Roblox que leva o X do modelo ao longo da rua"""
    return -ang


# ---------- vila ----------
def _lotes(cx, cz, ang):
    """lotes (u, v) e especiais no quadro da vila; devolve listas em studs do mundo"""
    lotes, especiais = [], []
    for k in range(SLOTS):
        u = (k - (SLOTS - 1) / 2) * PASSO_U
        if any(abs(u - t) < PASSO_U / 2 for t in TRAVESSAS):
            continue
        praca = abs(u) <= PRACA_U
        for lado in (-1, 1):
            for fileira, vc in (
                ("frente", RUA_W / 2 + 1 + LOTE_D / 2),
                ("fundo", RUA_W / 2 + 1 + LOTE_D + 3 + LOTE_D / 2),
            ):
                if praca:
                    continue
                v = lado * vc
                # casa na frente do lote, virada para a rua
                vcasa = (
                    lado * (RUA_W / 2 + 1 + 1.5 + CASA_MAX / 2)
                    if fileira == "frente"
                    else lado * (RUA_W / 2 + 1 + LOTE_D + 3 + 1.5 + CASA_MAX / 2)
                )
                dx, dz = gira(u, vcasa, ang)
                lx, lz = gira(u, v, ang)
                lotes.append(
                    {
                        "u": u,
                        "v": v,
                        "lado": lado,
                        "fileira": fileira,
                        "x": cx + dx,
                        "z": cz + dz,
                        "lx": cx + lx,
                        "lz": cz + lz,
                    }
                )
    # pagode ao norte da praça e casa comunal ao sul (lado -1 = v negativo)
    vfundo = RUA_W / 2 + 1 + LOTE_D + 3 + LOTE_D / 2
    k = ESCALA_CASA
    for kind, lado, w, d in (("chua", -1, 16.0 * k, 12.0 * k), ("dinh", 1, 18.0 * k, 10.0 * k)):
        dx, dz = gira(0.0, lado * vfundo, ang)
        especiais.append({"kind": kind, "x": cx + dx, "z": cz + dz, "w": w, "d": d})
    dx, dz = gira(12.0 * k, -12.0 * k, ang)
    especiais.append({"kind": "poco", "x": cx + dx, "z": cz + dz, "w": 2.0, "d": 2.0})
    # bancas do mercado nas bordas da praça
    for u in (-14.0, -4.0, 6.0, 16.0):
        for lado in (-1, 1):
            if u == 16.0 and lado == -1:
                continue  # o poço
            dx, dz = gira(u * k, lado * 13.0 * k, ang)
            especiais.append({"kind": "banca", "x": cx + dx, "z": cz + dz, "w": 3.0, "d": 2.5})
    return lotes, especiais


def _avalia(t: Terreno, cx, cz, ang, dentro):
    lotes, _ = _lotes(cx, cz, ang)
    bons, corte = [], 0.0
    yaw = yaw_de(ang)
    for lote in lotes:
        p = pegada(lote["x"], lote["z"], yaw, CASA_MAX, CASA_MAX)
        h = t.altura(p[:, 0], p[:, 1])
        c = t.classe(p[:, 0], p[:, 1])
        rng = float(h.max() - h.min())
        if rng > CORTE_MAX or (c == 5).any() or not dentro(lote["x"], lote["z"]):
            continue
        bons.append(lote)
        corte += rng
    return bons, corte


def planeja_vila(t: Terreno, ing_local, dentro) -> dict:
    """procura centro e rumo da rua que deixam mais casas com menos corte"""
    melhor = None
    # D-115: passo de 7,5 m (era 15): com os lotes maiores a vila fica justa no setor
    for e in np.arange(VILA_E[0], VILA_E[1] + 1, 7.5):
        for n in np.arange(VILA_N[0], VILA_N[1] + 1, 7.5):
            cx, cz = ing_local(e, n)
            for deg in range(0, 180, 10):
                ang = math.radians(deg)
                bons, corte = _avalia(t, cx, cz, ang, dentro)
                nota = (len(bons), -corte)
                if melhor is None or nota > melhor[0]:
                    melhor = (nota, cx, cz, ang, bons)
    _, cx, cz, ang, bons = melhor
    _, especiais = _lotes(cx, cz, ang)
    yaw = yaw_de(ang)
    # variante, tom, escala e anexos: nenhuma casa igual a outra a menos de VIZINHO_M
    rnd = np.random.default_rng(1965)
    casas = []
    for lote in bons:
        viz = [
            c
            for c in casas
            if math.hypot(c["x"] - lote["x"], c["z"] - lote["z"]) * STUD_M < VIZINHO_M
        ]
        usadas_var = {c["variante"] for c in viz}
        assinaturas = {(c["variante"], c["tom"], c["anexos"]) for c in viz}
        livres = [v for v in range(1, N_VARIANTES + 1) if v not in usadas_var]
        for _ in range(200):
            variante = int(rnd.choice(livres)) if livres else int(rnd.integers(1, N_VARIANTES + 1))
            tom = int(rnd.integers(1, N_TONS + 1))
            anexos = int(rnd.integers(0, 1 << len(ANEXOS)))
            if (variante, tom, anexos) not in assinaturas:
                break
        escala = float(round(rnd.uniform(0.92, 1.08), 3))
        giro = (
            yaw + (math.pi if lote["lado"] < 0 else 0.0) + math.radians(float(rnd.uniform(-6, 6)))
        )
        casas.append(
            {
                "x": lote["x"],
                "z": lote["z"],
                "yaw": giro,
                "lx": lote["lx"],
                "lz": lote["lz"],
                "variante": variante,
                "tom": tom,
                "escala": escala,
                "anexos": anexos,
            }
        )
    # becos (pedestres): atrás das fileiras da frente, dos dois lados
    vb = RUA_W / 2 + 1 + LOTE_D + 1.5
    u0 = (SLOTS - 1) / 2 * PASSO_U + LOTE_W / 2
    becos = []
    for lado in (-1, 1):
        a = gira(-u0, lado * vb, ang)
        b = gira(u0, lado * vb, ang)
        becos.append([(cx + a[0], cz + a[1]), (cx + b[0], cz + b[1])])
    travessas = []
    for u in TRAVESSAS:
        a = gira(u, -(vb + LOTE_D + 1.5), ang)
        b = gira(u, vb + LOTE_D + 1.5, ang)
        travessas.append([(cx + a[0], cz + a[1]), (cx + b[0], cz + b[1])])
    ua = gira(-(u0 + 10), 0, ang)
    ub = gira(u0 + 10, 0, ang)
    rua = [(cx + ua[0], cz + ua[1]), (cx + ub[0], cz + ub[1])]
    return {
        "x": cx,
        "z": cz,
        "ang": ang,
        "yaw": yaw,
        "casas": casas,
        "especiais": especiais,
        "rua": rua,
        "becos": becos,
        "travessas": travessas,
    }


# ---------- estradas ----------
def custo_base(
    t: Terreno, casas_xz: list, vila: dict, dentro_borda, bloqueios: list | None = None
) -> np.ndarray:
    gy, gx = np.gradient(t.h, t.cell * STUD_M)
    grade = np.hypot(gx, gy)
    custo = 1.0 + 25.0 * np.clip(grade - 0.08, 0, None)
    custo[grade > GRADE_PROIBIDA] = np.inf
    custo[t.cls == 5] += 30.0
    rr, cc = np.indices(t.h.shape)
    xs, zs = t.ox + (cc + 0.5) * t.cell, t.oz + (rr + 0.5) * t.cell
    custo[~dentro_borda(xs, zs)] = np.inf
    # casas (com 5 m de folga) e lotes da vila: não passa
    for x, z, raio_m in casas_xz:
        d = np.hypot(xs - x, zs - z) * STUD_M
        custo[d < raio_m] = np.inf
    # rua da vila e travessas: caminho preferido
    for a, b in [vila["rua"]] + vila["travessas"]:
        d = _dist_seg(xs, zs, a, b) * STUD_M
        custo[d < 3.0] = 0.25
    # bases dos dois lados (2026-11-13): a estrada do mapa não entra; chega à entrada de cada uma
    for x0, x1, z0, z1 in bloqueios or []:
        m = BASE_FOLGA_M / STUD_M
        custo[(xs > x0 - m) & (xs < x1 + m) & (zs > z0 - m) & (zs < z1 + m)] = np.inf
    return custo


def _dist_seg(xs, zs, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    tt = np.clip(((xs - ax) * dx + (zs - az) * dz) / l2, 0, 1) if l2 > 0 else 0
    return np.hypot(ax + tt * dx - xs, az + tt * dz - zs)


def _cel(t: Terreno, x, z):
    r, c = t.rc(x, z)
    return int(np.clip(round(float(r)), 0, t.H - 1)), int(np.clip(round(float(c)), 0, t.W - 1))


def _livre(custo, rc):
    """célula transitável mais perto (o ponto forte pode cair em cima de uma casa)"""
    r, c = rc
    if np.isfinite(custo[r, c]):
        return rc
    for raio in range(1, 30):
        melhor = None
        for dr in range(-raio, raio + 1):
            for dc in range(-raio, raio + 1):
                rr, cc = r + dr, c + dc
                if (
                    0 <= rr < custo.shape[0]
                    and 0 <= cc < custo.shape[1]
                    and np.isfinite(custo[rr, cc])
                ):
                    d = dr * dr + dc * dc
                    if melhor is None or d < melhor[0]:
                        melhor = (d, (rr, cc))
        if melhor:
            return melhor[1]
    return rc


def _caminho(custo, a, b):
    mcp = MCP_Geometric(custo, fully_connected=True)
    mcp.find_costs([a], [b])
    return mcp.traceback(b)


def traca_estradas(
    t: Terreno, nos: dict, custo0: np.ndarray, vila: dict, ing_local, limites: tuple
) -> list:
    """principal (árvore geradora mínima entre QGs e pontos fortes) e voltas por fora"""
    nomes = list(nos)
    celulas = {k: _livre(custo0, _cel(t, *nos[k])) for k in nomes}
    # custo do par pelo terreno (MCP a partir de cada nó)
    n = len(nomes)
    dist = np.full((n, n), np.inf)
    for i, k in enumerate(nomes):
        mcp = MCP_Geometric(custo0, fully_connected=True)
        acc, _ = mcp.find_costs([celulas[k]])
        for j, k2 in enumerate(nomes):
            dist[i, j] = acc[celulas[k2]]
    usados, arestas = {nomes.index("QG_US")}, []
    while len(usados) < n:
        best = None
        for i in usados:
            for j in range(n):
                if j not in usados and (best is None or dist[i, j] < dist[best[0], best[1]]):
                    best = (i, j)
        usados.add(best[1])
        arestas.append(best)
    custo = custo0.copy()
    estrada = np.zeros(custo.shape, bool)
    trechos = []

    def roteia(a, b, kind):
        rota = _caminho(custo, a, b)
        atual = []
        for rc in rota:
            if estrada[rc]:
                if len(atual) >= 2:
                    atual.append(rc)
                    trechos.append((kind, atual))
                atual = [rc]
            else:
                atual.append(rc)
        if len(atual) >= 2:
            trechos.append((kind, atual))
        for rc in rota:
            estrada[rc] = True
            custo[rc] = min(custo[rc], 0.3)

    # rua da vila primeiro (vira parte da principal), depois a árvore, das arestas curtas às longas
    ra, rb = _livre(custo0, _cel(t, *vila["rua"][0])), _livre(custo0, _cel(t, *vila["rua"][1]))
    roteia(ra, rb, "rua")
    for i, j in sorted(arestas, key=lambda e: dist[e[0], e[1]]):
        roteia(celulas[nomes[i]], celulas[nomes[j]], "principal")
    # Voltas por fora: do QG do VC ao dos EUA pelo norte e pelo sul, numa faixa a ~70 m da borda.
    # Custo próprio: o terreno de sempre vezes a distância da faixa (a estrada principal não fica
    # barata aqui, senão a volta grudava nela e virava toco).
    rr, cc = np.indices(custo0.shape)
    xs, zs = t.ox + (cc + 0.5) * t.cell, t.oz + (rr + 0.5) * t.cell
    xa, xb, za, zb = limites
    borda = np.minimum.reduce([xs - xa, xb - xs, zs - za, zb - zs]) * STUD_M
    anel = custo0 * (1.0 + 3.0 * np.abs(borda - ANEL_M) / ANEL_M)
    custo_anel = np.where(estrada, np.minimum(anel, 1.0), anel)
    for e_n_lista in ANEL_PONTOS:
        pts = [celulas["QG_VC"]] + [
            _livre(custo0, _cel(t, *ing_local(e, n_))) for e, n_ in e_n_lista
        ]
        pts.append(celulas["QG_US"])
        for a, b in zip(pts, pts[1:], strict=False):
            rota = _caminho(custo_anel, a, b)
            atual = []
            for rc in rota:
                if estrada[rc]:
                    if len(atual) >= 2:
                        atual.append(rc)
                        trechos.append(("secundaria", atual))
                    atual = [rc]
                else:
                    atual.append(rc)
            if len(atual) >= 2:
                trechos.append(("secundaria", atual))
            for rc in rota:
                estrada[rc] = True
                custo_anel[rc] = min(custo_anel[rc], 1.0)
    return trechos


def suaviza(t: Terreno, trechos: list) -> list:
    """células -> polilinha suave com o leito (y) em rampa máxima de GRADE_MAX"""
    altura_estrada: dict = {}
    estradas = []
    for kind, cels in trechos:
        pts = np.array([t.centro(r, c) for r, c in cels], float)
        if len(pts) > 4:
            k = 5
            ker = np.ones(k) / k
            sx = np.convolve(np.pad(pts[:, 0], k // 2, mode="edge"), ker, mode="valid")
            sz = np.convolve(np.pad(pts[:, 1], k // 2, mode="edge"), ker, mode="valid")
            sx[0], sz[0], sx[-1], sz[-1] = pts[0, 0], pts[0, 1], pts[-1, 0], pts[-1, 1]
            pts = np.column_stack([sx, sz])
        idx = list(range(0, len(pts), 2))
        if idx[-1] != len(pts) - 1:
            idx.append(len(pts) - 1)
        pts = pts[idx]
        cels_ = [cels[min(i, len(cels) - 1)] for i in idx]
        y = t.altura(pts[:, 0], pts[:, 1]) / STUD_M
        if len(y) > 6:
            k = 7
            ker = np.ones(k) / k
            y = np.convolve(np.pad(y, k // 2, mode="edge"), ker, mode="valid")
        # pontas presas na estrada que já existe (junção sem degrau)
        fixos = {}
        for ponta in (0, len(pts) - 1):
            rc = cels_[ponta]
            if rc in altura_estrada:
                y[ponta] = altura_estrada[rc]
                fixos[ponta] = True
        seg = np.hypot(np.diff(pts[:, 0]), np.diff(pts[:, 1]))
        lim = seg * GRADE_MAX
        for _ in range(4):
            for i in range(1, len(y)):
                if i not in fixos:
                    y[i] = np.clip(y[i], y[i - 1] - lim[i - 1], y[i - 1] + lim[i - 1])
            for i in range(len(y) - 2, -1, -1):
                if i not in fixos:
                    y[i] = np.clip(y[i], y[i + 1] - lim[i], y[i + 1] + lim[i])
        for i, rc in enumerate(cels_):
            altura_estrada.setdefault(rc, float(y[i]))
        estradas.append({"kind": kind, "pts": np.column_stack([pts, y])})
    return estradas


# ---------- feições ----------
def _clip_segs(segs: np.ndarray, corredores: list, ncols: int) -> tuple[np.ndarray, int]:
    """corta cada segmento (x1,z1,x2,z2,...) onde ele passa dentro de algum corredor (a, b, meia)"""
    out, cortados = [], 0
    for row in segs:
        x1, z1, x2, z2 = row[:4]
        comp = math.hypot(x2 - x1, z2 - z1)
        n = max(2, int(comp / 2) + 1)
        ts = np.linspace(0, 1, n)
        xs, zs = x1 + (x2 - x1) * ts, z1 + (z2 - z1) * ts
        livre = np.ones(n, bool)
        for a, b, meia in corredores:
            livre &= _dist_seg(xs, zs, a, b) > meia
        if livre.all():
            out.append(row)
            continue
        cortados += 1
        i = 0
        while i < n:
            if not livre[i]:
                i += 1
                continue
            j = i
            while j + 1 < n and livre[j + 1]:
                j += 1
            if j > i and (ts[j] - ts[i]) * comp > 3:
                novo = row.copy()
                novo[0], novo[1] = xs[i], zs[i]
                novo[2], novo[3] = xs[j], zs[j]
                out.append(novo)
            i = j + 1
    arr = np.array(out, float).reshape(-1, ncols) if out else np.zeros((0, ncols))
    return arr, cortados


def limpa_feicoes(f: dict, estradas: list, vila: dict, bloqueios: list | None = None) -> dict:
    corredores = []
    for e in estradas:
        meia = (LARGURA[e["kind"]] / 2 + 1.5) / STUD_M
        p = e["pts"]
        for i in range(len(p) - 1):
            corredores.append(((p[i, 0], p[i, 1]), (p[i + 1, 0], p[i + 1, 1]), meia))
    # vila: lotes inteiros, praça, becos e travessas
    area = []
    for c in vila["casas"]:
        area.append(
            ((c["lx"], c["lz"]), (c["lx"], c["lz"]), (max(LOTE_W, LOTE_D) / 2 + 2) / STUD_M)
        )
    for s in vila["especiais"]:
        area.append(((s["x"], s["z"]), (s["x"], s["z"]), (max(s["w"], s["d"]) / 2 + 3) / STUD_M))
    area.append(((vila["x"], vila["z"]), (vila["x"], vila["z"]), (PRACA_U + 3) / STUD_M))
    for a, b in vila["becos"] + vila["travessas"]:
        area.append((a, b, (LARGURA["beco"] / 2 + 1) / STUD_M))
    # bases: o retângulo vira uma cápsula no eixo comprido (com 2 m de folga)
    for x0, x1, z0, z1 in bloqueios or []:
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        hx, hz = (x1 - x0) / 2, (z1 - z0) / 2
        meia = min(hx, hz) + 2 / STUD_M
        if hx >= hz:
            area.append(((cx - hx + hz, cz), (cx + hx - hz, cz), meia))
        else:
            area.append(((cx, cz - hz + hx), (cx, cz + hz - hx), meia))
    todos = corredores + area
    info = {}
    f["dikes"], info["diques_cortados"] = _clip_segs(f["dikes"], todos, 6)
    f["hedges"], info["sebes_cortadas"] = _clip_segs(f["hedges"], todos, 7)
    w = f["waters"]
    manter = []
    for x, z, _y, su, sv, _ang in w:
        r = math.hypot(su, sv) / 2
        fora = all(
            _dist_seg(np.array([x]), np.array([z]), a, b)[0] > meia + r * 0.7
            for a, b, meia in todos
        )
        manter.append(fora)
    manter = np.array(manter, bool)
    info["laminas_fora"] = int((~manter).sum())
    f["waters"] = w[manter]
    return info


# ---------- escrita ----------
def _num(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def escreve(vila: dict, estradas: list, head: str) -> None:
    linhas = [
        head + "-- Vila grande do centro (tools/vila_estradas.py). Studs e radianos.\n",
        "return {\n",
    ]
    linhas.append(f'\tname = "{VILA_NOME}",\n')
    linhas.append(
        f"\tx = {_num(vila['x'])}, z = {_num(vila['z'])}, yaw = {_num(vila['yaw'])}, "
        f"plazaHalf = {_num(PRACA_U / STUD_M)}, streetW = {_num(RUA_W / STUD_M)},\n"
    )
    linhas.append(
        f"\thouseMax = {_num(CASA_MAX / STUD_M)}, lotW = {_num(LOTE_W / STUD_M)}, "
        f"lotD = {_num(LOTE_D / STUD_M)}, houseScale = {_num(ESCALA_CASA)},\n"
    )
    linhas.append(
        f"\tattachNames = {{{', '.join(repr(a).replace(chr(39), chr(34)) for a in ANEXOS)}}},\n"
    )
    linhas.append(
        "\t-- casa: x, z, giro, variante (1..12), tom (1..4), escala, anexos (bits de attachNames),"
        " lote x, z\n"
    )
    linhas.append("\thouses = {\n")
    for c in vila["casas"]:
        linhas.append(
            "\t\t{ "
            + ", ".join(
                [
                    _num(c["x"]),
                    _num(c["z"]),
                    _num(c["yaw"]),
                    str(c["variante"]),
                    str(c["tom"]),
                    _num(c["escala"]),
                    str(c["anexos"]),
                    _num(c["lx"]),
                    _num(c["lz"]),
                ]
            )
            + " },\n"
        )
    linhas.append("\t},\n\tspecials = {\n")
    for s in vila["especiais"]:
        linhas.append(
            f'\t\t{{ kind = "{s["kind"]}", x = {_num(s["x"])}, z = {_num(s["z"])}, '
            f"w = {_num(s['w'] / STUD_M)}, d = {_num(s['d'] / STUD_M)} }},\n"
        )
    linhas.append(
        "\t},\n\t-- becos e travessas (a pé): pares de pontas x1, z1, x2, z2\n\tlanes = {\n"
    )
    for a, b in vila["becos"] + vila["travessas"]:
        linhas.append(f"\t\t{{ {_num(a[0])}, {_num(a[1])}, {_num(b[0])}, {_num(b[1])} }},\n")
    linhas.append("\t},\n}\n")
    (DATA / "Village.luau").write_text("".join(linhas), encoding="utf-8", newline="\n")

    out = [head + "-- Estradas de terra batida (tools/vila_estradas.py).\n"]
    out.append(
        "-- kind: principal | secundaria | rua | trilha; w = largura (studs);"
        " pts = x, z, y (leito) por vértice\n"
    )
    out.append("return {\n")
    for kind, w in LARGURA.items():
        out.append(f"\t-- {kind}: {w:g} m\n")
    larguras = ", ".join(f"{k} = {_num(w / STUD_M)}" for k, w in LARGURA.items())
    out.append(f"\twidth = {{ {larguras} }},\n")
    out.append(f"\tshoulder = {_num(TALUDE_M / STUD_M)}, gradeMax = {GRADE_MAX},\n\troads = {{\n")
    for e in estradas:
        p = e["pts"]
        flat = ",".join(_num(v) for v in p.ravel())
        out.append(f'\t\t{{ kind = "{e["kind"]}", pts = {{{flat}}} }},\n')
    out.append("\t},\n}\n")
    (DATA / "Roads.luau").write_text("".join(out), encoding="utf-8", newline="\n")


def estrada_reta(t: Terreno, a, b, kind: str, estradas: list) -> dict:
    """trecho reto de a até b (studs), com o leito em rampa máxima de GRADE_MAX; a ponta `a` presa
    na altura da estrada que já chega ali (a entrada da base)"""
    comp = math.hypot(b[0] - a[0], b[1] - a[1])
    n = max(2, int(comp / (2.0 / STUD_M)) + 1)
    s = np.linspace(0, 1, n)
    xs, zs = a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s
    y = t.altura(xs, zs) / STUD_M
    if len(y) > 6:
        k = 7
        y = np.convolve(np.pad(y, k // 2, mode="edge"), np.ones(k) / k, mode="valid")
    perto, melhor = None, 12.0 / STUD_M
    for e in estradas:
        p = e["pts"]
        d = np.hypot(p[:, 0] - a[0], p[:, 1] - a[1])
        i = int(np.argmin(d))
        if d[i] < melhor:
            perto, melhor = float(p[i, 2]), float(d[i])
    if perto is not None:
        y[0] = perto
    lim = comp / (n - 1) * GRADE_MAX
    for i in range(1, n):
        y[i] = np.clip(y[i], y[i - 1] - lim, y[i - 1] + lim)
    return {"kind": kind, "pts": np.column_stack([xs, zs, y])}


def aplica(
    g: dict,
    f: dict,
    ing_local,
    nos_ing: dict,
    setor3,
    bounds_ing,
    head: str,
    depois_da_vila=None,
    bases: list | None = None,
) -> tuple[dict, dict]:
    """vila + estradas sobre os dados já recortados; muda f (feições) e escreve Village e Roads.
    nos_ing: nome -> (E, N) dos QGs ("QG_US", "QG_VC") e dos pontos fortes; a praça da vila entra
    sozinha. setor3(x, z): o ponto (studs) cai no setor da vila. depois_da_vila(vila): chamado com a
    vila pronta, antes das estradas (o crop_world reduz o arrozal ali, pelas casas da vila).
    bases (2026-11-13): por base, {"no": "QG_US", "entrada": (x, z), "area": (x0, x1, z0, z1),
    "via": {"kind", "a", "b"}} em studs: a estrada do mapa chega à entrada (não ao meio do QG),
    não entra na área, e a via da base (rua dos EUA, trilha do VC) entra no Roads."""
    t = Terreno(g)
    e0, n0, e1, n1 = bounds_ing
    xa, za = ing_local(e0, n1)
    xb, zb = ing_local(e1, n0)
    vila = planeja_vila(t, ing_local, setor3)
    extra = depois_da_vila(vila) if depois_da_vila else {}
    borda = BORDA_M / STUD_M

    def dentro_borda(xs, zs):
        return (xs > xa + borda) & (xs < xb - borda) & (zs > za + borda) & (zs < zb - borda)

    # folga das casas até o EIXO da estrada: meia casa + meia estrada principal + 1,5 m (com 2,5 m o
    # leito de 7 m entrava 0,7 m na pegada das últimas casas da vila: varredura de 2026-11-12)
    folga = LARGURA["principal"] / 2 + 1.5
    casas = [(x, z, 4.0 + folga) for x, z in f["houses"][:, :2]]
    casas += [(c["x"], c["z"], CASA_MAX / 2 + folga) for c in vila["casas"]]
    casas += [
        (s["x"], s["z"], max(s["w"], s["d"]) / 2 + folga)
        for s in vila["especiais"]
        if s["kind"] in ("chua", "dinh")
    ]
    bloqueios = [b["area"] for b in bases or []]
    custo0 = custo_base(t, casas, vila, dentro_borda, bloqueios)
    nos = {k: ing_local(*v) for k, v in nos_ing.items()}
    for b in bases or []:
        nos[b["no"]] = b["entrada"]
    nos["vila"] = (vila["x"], vila["z"])
    trechos = traca_estradas(t, nos, custo0, vila, ing_local, (xa, xb, za, zb))
    estradas = suaviza(t, trechos)
    for b in bases or []:
        estradas.append(estrada_reta(t, b["via"]["a"], b["via"]["b"], b["via"]["kind"], estradas))
    info = limpa_feicoes(f, estradas, vila, bloqueios)
    escreve(vila, estradas, head)
    comp = {}
    for e in estradas:
        p = e["pts"]
        comp[e["kind"]] = comp.get(e["kind"], 0.0) + float(
            np.hypot(np.diff(p[:, 0]), np.diff(p[:, 1])).sum() * STUD_M
        )
    info.update(extra or {})
    info.update(
        casas_vila=len(vila["casas"]),
        rumo_rua_graus=round(math.degrees(vila["ang"]), 1),
        estradas={k: round(v) for k, v in comp.items()},
        trechos=len(estradas),
    )
    return info, vila
