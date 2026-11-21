"""Base dos veículos (Tarefa C): geometria de chapa, lagarta e roda, materiais de pintura militar e
a montagem em partes nomeadas (Casco, Torre, Cano, Esteira_E, Roda_*, RotorPrincipal...).

Roda dentro do Python do Blender. Tudo em METROS, Z para cima e o nariz do veículo em +X (a
esquerda do veículo é +Y). Na exportação (`veiculos.py`) vira studs, Y para cima, nariz em +X do
GLB, como os modelos antigos do ForgeGUI (o importador do Roblox gira 180° em Y e o nariz fica
em -X, que é o referencial do `VehicleDrive.ART`).

Cada objeto entra numa parte com `Montagem.geo` (forma: vai para a malha do jogo e é a fonte do
bake) ou `Montagem.det` (detalhe só do bake: parafusos, solda, grade, estêncil). A malha do jogo
de cada parte é a própria geometria `geo` (sem redução: o modelo já é feito no orçamento), e a
textura sai do bake das peças `geo` + `det` com os materiais procedurais.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import modelar as M  # noqa: E402
from modelar import Mat, rgb  # noqa: E402


# =============================================================== geometria
def de_bm(nome: str, bm: bmesh.types.BMesh, normais: bool = True) -> bpy.types.Object:
    if normais:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return M.de_bmesh(nome, bm)


def loft(nome: str, aneis, tampa0: bool = True, tampa1: bool = True) -> bpy.types.Object:
    """Superfície por anéis fechados com o mesmo número de pontos (em ordem), tampas em n-gono."""
    bm = bmesh.new()
    vs = [[bm.verts.new(Vector(p)) for p in anel] for anel in aneis]
    n = len(vs[0])
    for a, b in zip(vs[:-1], vs[1:], strict=True):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if tampa0:
        bm.faces.new(list(reversed(vs[0])))
    if tampa1:
        bm.faces.new(vs[-1])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    return de_bm(nome, bm)


def superelipse(cx, cy, a, b, z, n=32, e=2.5, a0=0.0, a1=2 * math.pi):
    """Pontos (x, y, z) de uma superelipse |x/a|^e + |y/b|^e = 1, de a0 a a1 (sem repetir)."""
    out = []
    for k in range(n):
        t = a0 + (a1 - a0) * k / n
        c, s = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(c) ** (2 / e), c)
        y = b * math.copysign(abs(s) ** (2 / e), s)
        out.append((cx + x, cy + y, z))
    return out


def planta(z, x_tras, x_frente, meia, nariz, n_nariz=10, e=2.4, meia_tras=None):
    """Contorno em planta (anti-horário visto de cima) de um casco: traseira reta em `x_tras`,
    laterais em ±`meia` e frente arredondada (superelipse de profundidade `nariz`) até
    `x_frente`."""
    mt = meia if meia_tras is None else meia_tras
    pts = [(x_tras, -mt, z)]
    xc = x_frente - nariz
    pts.append((xc, -meia, z))
    for k in range(1, n_nariz):
        t = -math.pi / 2 + math.pi * k / n_nariz
        c, s = math.cos(t), math.sin(t)
        pts.append((xc + nariz * abs(c) ** (2 / e), meia * math.copysign(abs(s) ** (2 / e), s), z))
    pts.append((xc, meia, z))
    pts.append((x_tras, mt, z))
    return pts


def prisma(nome: str, poligono, eixo: str, a0: float, a1: float) -> bpy.types.Object:
    """Polígono 2D extrudado: eixo 'Y' -> pontos (x, z) de a0 a a1 em Y; eixo 'Z' -> pontos
    (x, y) de a0 a a1 em Z; eixo 'X' -> pontos (y, z)."""

    def p3(u, v, w):
        if eixo == "Y":
            return Vector((u, w, v))
        if eixo == "Z":
            return Vector((u, v, w))
        return Vector((w, u, v))

    bm = bmesh.new()
    a = [bm.verts.new(p3(u, v, a0)) for u, v in poligono]
    b = [bm.verts.new(p3(u, v, a1)) for u, v in poligono]
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    return de_bm(nome, bm)


def perfil_com_arcos(pontos, arcos, n=10):
    """Perfil lateral (x, z) com recortes de para-lama: `arcos` = [(x_centro, z_centro, raio)].
    Os pontos do perfil devem ir no sentido anti-horário; cada arco entra no trecho da base
    (z mínimo) que passa por baixo dele, como um semicírculo para dentro."""
    out = []
    zb = min(p[1] for p in pontos)
    for i, p in enumerate(pontos):
        out.append(p)
        q = pontos[(i + 1) % len(pontos)]
        if abs(p[1] - zb) < 1e-6 and abs(q[1] - zb) < 1e-6:
            dentro = sorted(
                [a for a in arcos if min(p[0], q[0]) < a[0] < max(p[0], q[0])],
                key=lambda a: a[0] if q[0] > p[0] else -a[0],
            )
            for xc, zc, r in dentro:
                h = zb - zc
                a0 = math.acos(max(-1.0, min(1.0, h / r)))
                ang = [(-a0 + 2 * a0 * k / n) for k in range(n + 1)]
                if q[0] < p[0]:
                    ang = ang[::-1]
                for a in ang:
                    out.append((xc + r * math.sin(a), zc + r * math.cos(a)))
    return out


def afinar(obj, z0: float, k: float, eixo_y0: float = 0.0):
    """Aproxima do meio (em Y) os vértices acima de z0: y -> y - sinal(y) * k * (z - z0)."""
    for v in obj.data.vertices:
        if v.co.z > z0:
            dy = v.co.y - eixo_y0
            v.co.y = eixo_y0 + math.copysign(max(0.0, abs(dy) - k * (v.co.z - z0)), dy)
    obj.data.update()
    return obj


def caixa(nome, dim, centro=(0, 0, 0), chanfro=0.0, rot=(0, 0, 0), segs=1):
    o = M.caixa(nome, dim, (0, 0, 0))
    if chanfro > 0:
        M.chanfrar(o, chanfro, segs, 30.0)
    return M.mover(o, M.matriz(centro, rot))


def cil(nome, p0, p1, r, segs=16, tampas=True, r1=None):
    """Cilindro (ou tronco de cone com `r1`) de p0 a p1."""
    p0, p1 = Vector(p0), Vector(p1)
    comp = (p1 - p0).length
    rr = r if r1 is None else r1
    perfil = [(0.0, 0.0), (r, 0.0), (rr, comp), (0.0, comp)] if tampas else [(r, 0.0), (rr, comp)]
    o = M.torno(nome, perfil, segs=segs)
    eixo = (p1 - p0).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(eixo).to_matrix().to_4x4()
    return M.mover(o, Matrix.Translation(p0) @ rot)


def torno_eixo(nome, perfil, eixo: str, centro, segs=16) -> bpy.types.Object:
    """Torno de (r, h) em volta de 'X', 'Y' ou 'Z', com o centro (h = 0) em `centro`."""
    o = M.torno(nome, perfil, segs=segs)
    if eixo == "Y":
        M.mover(o, Matrix.Rotation(-math.pi / 2, 4, "X"))
    elif eixo == "X":
        M.mover(o, Matrix.Rotation(math.pi / 2, 4, "Y"))
    return M.mover(o, Matrix.Translation(Vector(centro)))


def engrenagem(nome, r_pe, r_ponta, dentes, y0, y1, centro_xz, fase=0.0):
    """Roda dentada (motriz) no plano XZ, extrudada em Y."""
    pts = []
    for k in range(dentes):
        a = fase + 2 * math.pi * k / dentes
        d = 2 * math.pi / dentes
        for t, r in ((0.0, r_pe), (0.22, r_pe), (0.36, r_ponta), (0.64, r_ponta), (0.78, r_pe)):
            pts.append(
                (centro_xz[0] + r * math.cos(a + t * d), centro_xz[1] + r * math.sin(a + t * d))
            )
    return prisma(nome, pts, "Y", y0, y1)


def casco_convexo(pts2):
    """Envoltória convexa 2D (cadeia monotônica), anti-horária."""
    p = sorted(set(pts2))

    def cruz(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    baixo, cima = [], []
    for q in p:
        while len(baixo) >= 2 and cruz(baixo[-2], baixo[-1], q) <= 0:
            baixo.pop()
        baixo.append(q)
    for q in reversed(p):
        while len(cima) >= 2 and cruz(cima[-2], cima[-1], q) <= 0:
            cima.pop()
        cima.append(q)
    return baixo[:-1] + cima[:-1]


def laco(circulos, n: int, sag: float = 0.0, z_sag: float | None = None):
    """Laço da lagarta (lado de dentro) em volta dos círculos (x, z, r): `n` pontos igualmente
    espaçados, anti-horário no plano XZ, com a normal para fora. `sag` abaixa o ramo de cima entre
    os apoios (m), acima de `z_sag`."""
    amostras = []
    for x, z, r in circulos:
        for k in range(240):
            a = 2 * math.pi * k / 240
            amostras.append((round(x + r * math.cos(a), 6), round(z + r * math.sin(a), 6)))
    h = casco_convexo(amostras)
    h = np.array(h + [h[0]], np.float64)
    seg = np.linalg.norm(np.diff(h, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    total = s[-1]
    alvo = np.arange(n) * total / n
    x = np.interp(alvo, s, h[:, 0])
    z = np.interp(alvo, s, h[:, 1])
    pts = np.column_stack([x, z])
    if sag and z_sag is not None:
        apoios = sorted(c[0] for c in circulos if c[1] + c[2] > z_sag - 0.05)
        for i in range(n):
            if pts[i, 1] > z_sag:
                xs = [a for a in apoios]
                esq = max([a for a in xs if a <= pts[i, 0]], default=None)
                dir_ = min([a for a in xs if a >= pts[i, 0]], default=None)
                if esq is not None and dir_ is not None and dir_ > esq:
                    t = (pts[i, 0] - esq) / (dir_ - esq)
                    pts[i, 1] -= sag * math.sin(math.pi * t) * min(1.0, (dir_ - esq) / 1.2)
    tang = np.roll(pts, -1, axis=0) - np.roll(pts, 1, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True)
    normal = np.column_stack([tang[:, 1], -tang[:, 0]])  # anti-horário: para fora
    return pts, tang, normal, total


def faixa(nome, pts, normal, secao, y_centro: float) -> bpy.types.Object:
    """Faixa fechada ao longo do laço: `secao` = [(d, y)] (d = distância pela normal, para fora;
    y = lateral), polígono fechado. Um anel por ponto do laço."""
    bm = bmesh.new()
    aneis = []
    for (x, z), (nx, nz) in zip(pts, normal, strict=True):
        aneis.append([bm.verts.new((x + nx * d, y_centro + y, z + nz * d)) for d, y in secao])
    n = len(secao)
    for a, b in zip(aneis, aneis[1:] + aneis[:1], strict=True):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    return de_bm(nome, bm)


def fuselagem(nome, estacoes, n=36, tampa0=True, tampa1=True):
    """Loft de anéis no plano YZ: estacoes = [(x, topo, base, meia_largura, expoente)]."""
    aneis = []
    for x, top, bot, w, e in estacoes:
        zc, h = (top + bot) / 2, (top - bot) / 2
        anel = []
        for k in range(n):
            t = 2 * math.pi * k / n
            c, s = math.cos(t), math.sin(t)
            anel.append(
                (
                    x,
                    w * math.copysign(abs(c) ** (2 / e), c),
                    zc + h * math.copysign(abs(s) ** (2 / e), s),
                )
            )
        aneis.append(anel)
    return loft(nome, aneis, tampa0, tampa1)


def abrir_e_forrar(obj, regiao, janela, esp: float, nome: str):
    """Abre as faces `janela(centro, normal)` do casco (janela, porta) e devolve o forro de dentro:
    cópia das faces `regiao` (sem as janelas) com a normal para dentro, recuada `esp` m. Assim quem
    está dentro (piloto, tropa) vê o forro e o painel em vez do casco sumir (face única)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    jan = {f for f in bm.faces if janela(f.calc_center_median(), f.normal)}
    reg = [f for f in bm.faces if f not in jan and regiao(f.calc_center_median(), f.normal)]
    bm2 = bmesh.new()
    mapa = {}
    for f in reg:
        vs = []
        for v in f.verts:
            if v not in mapa:
                mapa[v] = bm2.verts.new(v.co)
            vs.append(mapa[v])
        bm2.faces.new(list(reversed(vs)))
    bm2.normal_update()
    for v in bm2.verts:
        v.co += v.normal * esp
    bmesh.ops.delete(bm, geom=list(jan), context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return de_bm(nome, bm2, normais=False)


def faixa_alternada(nome, pts, normal, secoes, y_centro: float) -> bpy.types.Object:
    """Como `faixa`, mas o anel i usa a seção secoes[i % len(secoes)] (garras da lagarta)."""
    bm = bmesh.new()
    aneis = []
    for i, ((x, z), (nx, nz)) in enumerate(zip(pts, normal, strict=True)):
        sec = secoes[i % len(secoes)]
        aneis.append([bm.verts.new((x + nx * d, y_centro + y, z + nz * d)) for d, y in sec])
    n = len(secoes[0])
    for a, b in zip(aneis, aneis[1:] + aneis[:1], strict=True):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    return de_bm(nome, bm)


def aplicar_local(obj):
    M.gravar_local(obj, 0.0)
    return obj


def pintar_por(obj, cond, mat_extra) -> bpy.types.Object:
    """Põe `mat_extra` (2º slot) nas faces em que cond(centro, normal) é verdade."""
    me = obj.data
    if len(me.materials) == 0:
        raise ValueError("pintar_por: objeto sem material base")
    me.materials.append(mat_extra)
    k = len(me.materials) - 1
    for f in me.polygons:
        if cond(f.center, f.normal):
            f.material_index = k
    return obj


class Lote:
    """Muitas caixas pequenas num objeto só (detalhe repetido: sapata, parafuso, ripa)."""

    def __init__(self, nome):
        self.nome = nome
        self.bm = bmesh.new()

    def caixa(self, dim, m: Matrix):
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        vs = r["verts"]
        bmesh.ops.scale(self.bm, vec=Vector(dim), verts=vs)
        bmesh.ops.transform(self.bm, matrix=m, verts=vs)

    def cil(self, r, h, m: Matrix, segs=8):
        res = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=r, depth=h
        )
        bmesh.ops.transform(self.bm, matrix=m, verts=res["verts"])

    def objeto(self):
        return de_bm(self.nome, self.bm)


def quadro(origem, x, y, z) -> Matrix:
    """Matriz 4x4 com colunas x, y, z (eixos locais) e a origem."""
    m = Matrix.Identity(4)
    for i, v in enumerate((Vector(x), Vector(y), Vector(z))):
        m[0][i], m[1][i], m[2][i] = v.x, v.y, v.z
    m.translation = Vector(origem)
    return m


# =============================================================== materiais
def _borda(m: Mat, raio: float):
    """Máscara de quina pelo nó Bevel (independe da densidade da malha): 0 no plano, 1 na quina."""
    bev = m.no("ShaderNodeBevel", samples=8)
    bev.inputs["Radius"].default_value = raio
    geo = m.no("ShaderNodeNewGeometry")
    d = m.no("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    m.nt.links.new(bev.outputs["Normal"], d.inputs[0])
    m.nt.links.new(geo.outputs["True Normal"], d.inputs[1])
    return m.faixa(d.outputs["Value"], 0.985, 0.85)


def _nz(m: Mat):
    return m.separar(m.no("ShaderNodeNewGeometry").outputs["Normal"])[2]


def mat_pintura(
    nome: str,
    cor: str = "#56583a",
    clara: str = "#6f6f4f",
    poeira: str = "#9b8466",
    lama: str = "#6b4630",
    z_lama: float = 0.9,
    lama_forca: float = 1.0,
    desgaste: float = 0.5,
    fundido: float = 0.0,
    escala: float = 1.0,
    poeira_forca: float = 1.0,
    oleo: tuple | None = None,
    rug: float = 0.68,
):
    """Aço pintado (olive drab fosco) usado no Vietnã: variação de retoque, desbotado de sol no que
    olha para cima, poeira de laterita no plano, lama avermelhada embaixo, escorrido escuro nas
    paredes, sujeira nas frestas (AO), tinta lascada nas quinas mostrando o primer e o aço (metal),
    casca de fundição (`fundido` > 0: casco e torre fundidos) e mancha de óleo opcional
    (`oleo` = (x, y, raio))."""
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    ps = m.mapear(p, (escala, escala, escala))
    _, _, z = m.separar(p)
    nz = _nz(m)
    # base: retoques e manchas de tinta
    var = m.ruido(ps, 0.9, 4, 0.55)
    base = m.misturar(m.faixa(var, 0.32, 0.7, 0.0, 0.6), rgb(cor), rgb("#43452c"))
    fino = m.ruido(ps, 14.0, 5, 0.6)
    base = m.misturar(m.faixa(fino, 0.4, 0.75, 0.0, 0.18), base, rgb(clara))
    # desbotado de sol (topo)
    sol = m.conta(
        "MULTIPLY", m.faixa(nz, 0.35, 0.95), m.faixa(m.ruido(ps, 2.2, 3), 0.3, 0.7, 0.35, 0.8)
    )
    cor_ = m.misturar(sol, base, rgb(clara))
    # escorrido vertical nas paredes
    esc = m.ruido(m.mapear(ps, (9, 9, 0.6)), 3.0, 4, 0.5)
    parede = m.faixa(m.conta("ABSOLUTE", nz), 0.55, 0.2)
    escorre = m.conta("MULTIPLY", m.faixa(esc, 0.55, 0.72, 0.0, 0.6), parede)
    cor_ = m.misturar(escorre, cor_, rgb("#2f3020"))
    # sujeira nas frestas
    ao = m.oclusao(0.12, 8)
    fresta = m.faixa(ao, 0.75, 0.25, 0.0, 0.65)
    cor_ = m.misturar(fresta, cor_, rgb("#2b2618"))
    # poeira de laterita no plano
    pmask = m.conta(
        "MULTIPLY",
        m.faixa(nz, 0.45, 0.85),
        m.faixa(m.ruido(ps, 1.6, 5, 0.6), 0.28, 0.6, 0.3, min(1.0, 0.95 * poeira_forca)),
    )
    pmask = m.conta("MAXIMUM", pmask, m.conta("MULTIPLY", fresta, 0.6 * poeira_forca), limitar=True)
    cor_ = m.misturar(pmask, cor_, rgb(poeira))
    # lama embaixo: respingos (voronoi) + crosta perto do chão
    resp = m.faixa(m.voronoi(m.mapear(ps, (1, 1, 1.6)), 7.0, "F1"), 0.16, 0.05)
    nuvem = m.faixa(m.ruido(ps, 3.0, 5, 0.6), 0.25, 0.5)
    altura = m.faixa(z, z_lama, z_lama * 0.35)
    lama_m = m.conta("MULTIPLY", altura, m.conta("MAXIMUM", nuvem, resp))
    lama_m = m.conta("MULTIPLY", lama_m, lama_forca, limitar=True)
    cor_lama = m.misturar(m.ruido(ps, 8.0, 3), rgb(lama), rgb("#87603f"))
    cor_ = m.misturar(lama_m, cor_, cor_lama)
    # óleo
    if oleo:
        d = m.no("ShaderNodeVectorMath", operation="DISTANCE")
        m._set(d.inputs[0], m.juntar_xyz(m.separar(p)[0], m.separar(p)[1], 0.0))
        d.inputs[1].default_value = (oleo[0], oleo[1], 0.0)
        om = m.conta(
            "MULTIPLY",
            m.faixa(d.outputs["Value"], oleo[2], oleo[2] * 0.3),
            m.faixa(m.ruido(ps, 4.0, 4), 0.35, 0.6),
        )
        cor_ = m.misturar(m.conta("MULTIPLY", om, 0.8), cor_, rgb("#1d1b14"))
    # lascas nas quinas: primer (vermelho-óxido escuro) e aço
    quina = _borda(m, 0.012)
    risco = m.faixa(m.ruido(ps, 26.0, 6, 0.7), 0.62 - 0.14 * desgaste, 0.7)
    lasca = m.conta("MULTIPLY", quina, risco)
    lasca = m.conta(
        "MAXIMUM",
        lasca,
        m.conta("MULTIPLY", m.faixa(m.ruido(ps, 40.0, 6, 0.7), 0.74, 0.79), desgaste),
    )
    lasca = m.conta("MULTIPLY", lasca, m.conta("SUBTRACT", 1.0, lama_m), limitar=True)
    aco = m.faixa(m.ruido(ps, 60.0, 3), 0.4, 0.6)
    nu = m.misturar(aco, rgb("#3c2b22"), rgb("#76746c"))
    cor_ = m.misturar(lasca, cor_, nu)
    m.cor(cor_)
    rg = m.misturar_valor(pmask, rug, 0.92)
    rg = m.misturar_valor(lama_m, rg, 0.88)
    rg = m.misturar_valor(lasca, rg, 0.45)
    m.rug(rg)
    m.metal(m.conta("MULTIPLY", lasca, aco))
    if fundido > 0:
        m.relevo(m.ruido(ps, 9.0, 6, 0.7), 0.25 * fundido, 0.004)
        m.relevo(m.ruido(ps, 70.0, 3), 0.15 * fundido, 0.001)
    else:
        m.relevo(m.ruido(ps, 120.0, 2), 0.05, 0.0003)
    m.relevo(m.conta("MULTIPLY", lama_m, m.ruido(ps, 30.0, 4)), 0.4, 0.004)
    m.relevo(m.conta("MULTIPLY", lasca, -1.0), 0.25, 0.0008)
    return m.m


def mat_aviao(
    nome,
    cor="#4b5539",
    clara="#66704f",
    escuro="#353d29",
    passo_x=0.55,
    passo_z=0.42,
    painel=0.6,
    z_lama=0.5,
    fuligem: tuple | None = None,
    rug=0.62,
):
    """Alumínio pintado de helicóptero (Field Green fosco): linhas de painel (cavernas a cada
    `passo_x` e longarinas a cada `passo_z`), filas de rebites junto delas, desbotado de sol,
    escorrido de óleo, tinta gasta nas quinas (alumínio claro, metal), poeira embaixo e fuligem do
    escapamento (`fuligem` = (x, y, z, raio))."""
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    x, y, z = m.separar(p)
    nz = _nz(m)
    var = m.ruido(p, 0.8, 4, 0.55)
    cor_ = m.misturar(m.faixa(var, 0.35, 0.68, 0.0, 0.5), rgb(cor), rgb(escuro))
    sol = m.conta(
        "MULTIPLY", m.faixa(nz, 0.3, 0.95), m.faixa(m.ruido(p, 1.5, 3), 0.3, 0.7, 0.3, 0.75)
    )
    cor_ = m.misturar(sol, cor_, rgb(clara))

    def linhas(c, passo):
        u = m.conta("FRACT", m.conta("MULTIPLY", c, 1 / passo))
        return m.conta("MULTIPLY", m.conta("MINIMUM", u, m.conta("SUBTRACT", 1.0, u)), passo)

    dx = linhas(x, passo_x)
    dz = linhas(z, passo_z)
    lin = m.conta("MAXIMUM", m.faixa(dx, 0.003, 0.0009), m.faixa(dz, 0.003, 0.0009))
    lin = m.conta("MULTIPLY", lin, painel)
    cor_ = m.misturar(m.conta("MULTIPLY", lin, 0.7), cor_, rgb("#22261a"))
    # rebites: fileira a 12 mm de cada linha, um a cada 4,5 cm
    rx = m.conta(
        "MULTIPLY",
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", dx, 0.012)), 0.0045, 0.002),
        m.faixa(linhas(z, 0.045), 0.0045, 0.002),
    )
    rz = m.conta(
        "MULTIPLY",
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", dz, 0.012)), 0.0045, 0.002),
        m.faixa(linhas(x, 0.045), 0.0045, 0.002),
    )
    reb = m.conta("MAXIMUM", rx, rz)
    # escorrido de óleo e sujeira
    esc = m.ruido(m.mapear(p, (10, 10, 0.7)), 3.0, 4, 0.5)
    parede = m.faixa(m.conta("ABSOLUTE", nz), 0.6, 0.2)
    cor_ = m.misturar(
        m.conta("MULTIPLY", m.faixa(esc, 0.6, 0.74, 0.0, 0.5), parede), cor_, rgb("#2a2a1d")
    )
    ao = m.oclusao(0.1, 8)
    cor_ = m.misturar(m.faixa(ao, 0.75, 0.25, 0.0, 0.6), cor_, rgb("#262418"))
    pmask = m.conta(
        "MULTIPLY",
        m.faixa(z, z_lama, z_lama * 0.2),
        m.faixa(m.ruido(p, 3.0, 5, 0.6), 0.35, 0.6, 0.1, 0.8),
    )
    cor_ = m.misturar(pmask, cor_, rgb("#8e7558"))
    if fuligem:
        d = m.no("ShaderNodeVectorMath", operation="DISTANCE")
        m._set(d.inputs[0], m.juntar_xyz(x, m.conta("ABSOLUTE", y), z))
        d.inputs[1].default_value = fuligem[:3]
        fm = m.conta(
            "MULTIPLY",
            m.faixa(d.outputs["Value"], fuligem[3], fuligem[3] * 0.2),
            m.faixa(m.ruido(m.mapear(p, (0.6, 1, 1.6)), 3.0, 4), 0.3, 0.6, 0.4, 1.0),
        )
        cor_ = m.misturar(fm, cor_, rgb("#151410"))
    quina = _borda(m, 0.01)
    lasca = m.conta("MULTIPLY", quina, m.faixa(m.ruido(p, 30.0, 6, 0.7), 0.58, 0.68))
    cor_ = m.misturar(lasca, cor_, rgb("#9c9c94"))
    m.cor(cor_)
    m.metal(m.conta("MULTIPLY", lasca, 0.9))
    m.rug(m.misturar_valor(lasca, m.misturar_valor(pmask, rug, 0.9), 0.4))
    m.relevo(m.conta("MULTIPLY", lin, -1.0), 0.35, 0.0012)
    m.relevo(reb, 0.25, 0.0008)
    m.relevo(m.ruido(p, 120.0, 2), 0.04, 0.0003)
    return m.m


def mat_aco_sujo(nome, cor="#4a4741", lama="#6b4630", z_lama=0.5, rug=0.5, brilho_contato=False):
    """Aço nu engraxado e enlameado (lagarta, pino, mola): metal, lama embaixo e poeira."""
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    _, _, z = m.separar(p)
    v = m.ruido(p, 18.0, 5)
    cor_ = m.misturar(m.faixa(v, 0.3, 0.7, 0.0, 0.5), rgb(cor), rgb("#2a2622"))
    fer = m.faixa(m.ruido(p, 6.0, 5, 0.6), 0.52, 0.72, 0.0, 0.7)
    cor_ = m.misturar(fer, cor_, rgb("#5b3a24"))
    ao = m.oclusao(0.06, 8)
    lm = m.conta(
        "MAXIMUM",
        m.faixa(ao, 0.8, 0.3),
        m.conta("MULTIPLY", m.faixa(z, z_lama, 0.0), m.faixa(m.ruido(p, 5.0, 4), 0.3, 0.55)),
    )
    cor_ = m.misturar(lm, cor_, m.misturar(m.ruido(p, 12.0), rgb(lama), rgb("#8a6646")))
    met = m.conta("MULTIPLY", m.conta("SUBTRACT", 1.0, lm), m.conta("SUBTRACT", 1.0, fer))
    if brilho_contato:
        quina = _borda(m, 0.006)
        cor_ = m.misturar(
            m.conta("MULTIPLY", quina, m.conta("SUBTRACT", 1.0, lm)), cor_, rgb("#9a978e")
        )
    m.cor(cor_)
    m.metal(m.conta("MULTIPLY", met, 0.85))
    m.rug(m.misturar_valor(lm, rug, 0.9))
    m.relevo(m.conta("MULTIPLY", lm, m.ruido(p, 40.0, 4)), 0.5, 0.003)
    m.relevo(m.ruido(p, 200.0, 2), 0.1, 0.0003)
    return m.m


def mat_borracha(nome, cor="#232220", poeira="#8c7458", z_lama=0.5):
    m = Mat(nome, rug=0.85)
    p = m.coord("objeto")
    _, _, z = m.separar(p)
    cor_ = m.misturar(m.faixa(m.ruido(p, 20.0, 4), 0.4, 0.7, 0.0, 0.3), rgb(cor), rgb("#3a3631"))
    ao = m.oclusao(0.05, 8)
    pm = m.conta(
        "MAXIMUM",
        m.faixa(ao, 0.85, 0.35, 0.0, 0.7),
        m.conta(
            "MULTIPLY", m.faixa(z, z_lama, 0.0), m.faixa(m.ruido(p, 6.0, 4), 0.3, 0.6, 0.2, 0.9)
        ),
    )
    cor_ = m.misturar(pm, cor_, rgb(poeira))
    m.cor(cor_)
    m.rug(0.9)
    m.relevo(m.ruido(p, 150.0, 3), 0.12, 0.0004)
    return m.m


def mat_vidro(nome, cor="#1b2328", rug=0.12):
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    pz = m.faixa(m.ruido(p, 6.0, 4), 0.45, 0.7, 0.0, 0.5)
    m.cor(m.misturar(pz, rgb(cor), rgb("#6f6650")))
    m.rug(m.misturar_valor(pz, rug, 0.7))
    return m.m


def mat_lona(nome, cor="#5f5d40", clara="#7d7656", z_lama=0.6, rug=0.93):
    """Lona de algodão (capa do mantelete, cobertura da caçamba): dobras, desbotado e sujeira."""
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    _, _, z = m.separar(p)
    nz = _nz(m)
    dobra = m.ruido(m.mapear(p, (3, 3, 8)), 2.5, 5, 0.55, distorcao=0.6)
    cor_ = m.misturar(m.faixa(dobra, 0.3, 0.7), rgb(cor), rgb(clara))
    cor_ = m.misturar(m.conta("MULTIPLY", m.faixa(nz, 0.3, 0.9), 0.5), cor_, rgb("#8c8564"))
    ao = m.oclusao(0.1, 8)
    cor_ = m.misturar(m.faixa(ao, 0.8, 0.3, 0.0, 0.6), cor_, rgb("#3a3423"))
    lm = m.conta(
        "MULTIPLY", m.faixa(z, z_lama, z_lama * 0.3), m.faixa(m.ruido(p, 4.0, 4), 0.35, 0.6)
    )
    cor_ = m.misturar(lm, cor_, rgb("#6e4a32"))
    m.cor(cor_)
    m.relevo(dobra, 0.6, 0.01)
    m.relevo(m.onda(p, 2 * math.pi / (20 * 0.003), "DIAGONAL"), 0.08, 0.0003)
    return m.m


def mat_estencil(nome, cor="#d9c56a", fundo="#56583a", gasto=0.45):
    """Tinta de estêncil gasta (amarelo dos fuzileiros): falha onde gastou mostra a pintura."""
    m = Mat(nome, rug=0.6)
    p = m.coord("objeto")
    falha = m.faixa(m.ruido(p, 55.0, 6, 0.7), 0.6 - 0.2 * gasto, 0.7 - 0.2 * gasto)
    pon = m.faixa(m.ruido(p, 6.0, 3), 0.55, 0.75, 0.0, 0.6)
    c = m.misturar(m.conta("MAXIMUM", falha, m.conta("MULTIPLY", pon, gasto)), rgb(cor), rgb(fundo))
    m.cor(c)
    return m.m


def mat_simples(nome, cor, rug=0.7, metal=0.0):
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    m.cor(m.misturar(m.faixa(m.ruido(p, 20.0, 3), 0.4, 0.7, 0.0, 0.25), rgb(cor), rgb("#262420")))
    m.metal(metal)
    return m.m


def letreiro(corpo, altura, mat, pos, normal, fonte=M.FONTE_ESTENCIL, inclina=0.0, giro=0.0):
    """Estêncil plano (malha de texto) numa face: `normal` em '-Y', '+Y', '-X', '+X' ou '+Z'.
    `inclina` gira em volta do eixo horizontal da face (chapa inclinada), `giro` em volta da
    normal."""
    t = M.texto_malha(corpo, altura, fonte)
    rot = {
        "-Y": Matrix.Rotation(math.pi / 2, 4, "X"),
        "+Y": Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"),
        "-X": Matrix.Rotation(-math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"),
        "+X": Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"),
        "+Z": Matrix.Rotation(-math.pi / 2, 4, "Z"),
    }[normal]
    M.mover(t, Matrix.Rotation(giro, 4, "Z"))
    M.mover(t, Matrix.Rotation(inclina, 4, "X"))
    M.mover(t, Matrix.Translation(Vector(pos)) @ rot)
    M.material(t, mat)
    return t


# =============================================================== montagem em partes
class Montagem:
    """Partes nomeadas do veículo.

    - `geo(parte, obj, mat)`: forma (malha do jogo e fonte do bake);
    - `det(parte, obj, mat)`: só no bake (normal e cor);
    - `pivo(parte, xyz)`: ponto de giro (m); sem pivô, o centro da caixa da parte;
    - `atlas(parte, nome)`: textura em que a parte entra (padrão: 'a');
    - `instancia(nome, de, pivo, giro_z180)`: nó que reusa a malha de `de` (roda igual em outro
      lugar); `espelho(nome, de)`: cópia espelhada em Y (lagarta da direita), mesma UV.
    """

    def __init__(self):
        self.partes: dict[str, dict] = {}
        self.instancias: list[dict] = []
        self.espelhos: list[dict] = []
        self.mats: dict[str, bpy.types.Material] = {}
        self.ext: dict[str, float] = {}  # extrusão do bake por atlas (m); padrão 0,02

    def _p(self, parte):
        return self.partes.setdefault(
            parte, {"geo": [], "det": [], "pivo": None, "atlas": "a", "limpar": True}
        )

    def mat(self, chave, fabrica, *a, **k):
        if chave not in self.mats:
            self.mats[chave] = fabrica(chave, *a, **k)
        return self.mats[chave]

    def geo(self, parte, obj, mat=None, suave=35.0):
        if mat is not None:
            M.material(obj, mat)
        C.suavizar(obj, suave)
        self._p(parte)["geo"].append(obj)
        return obj

    def det(self, parte, obj, mat=None, suave=40.0):
        if mat is not None:
            M.material(obj, mat)
        C.suavizar(obj, suave)
        self._p(parte)["det"].append(obj)
        return obj

    def pivo(self, parte, xyz):
        self._p(parte)["pivo"] = Vector(xyz)

    def atlas(self, parte, nome):
        self._p(parte)["atlas"] = nome

    def sem_limpeza(self, parte):
        self._p(parte)["limpar"] = False

    def instancia(self, nome, de, pivo, giro_z180=False, angulo_z=None):
        """`angulo_z` (graus) gira a cópia em volta do eixo Z que passa pelo pivô."""
        ang = 180.0 if giro_z180 else angulo_z
        self.instancias.append({"nome": nome, "de": de, "pivo": Vector(pivo), "giro": ang})

    def espelho(self, nome, de):
        self.espelhos.append({"nome": nome, "de": de})

    def todos(self):
        out = []
        for p in self.partes.values():
            out += p["geo"] + p["det"]
        return out
