"""Peças, materiais e móveis das casas da vila (`vila_casa_XX`) do VẠN TƯỜNG '65.

Roda dentro do Python do Blender. Tudo em METROS, Z para cima (como `comum.py` e `modelar.py`).
Mesma convenção dos assets das bases (`bases_comum.py`): a `Receita` e as peças simples foram
copiadas para cá, para não depender de um arquivo que outro agente está mexendo.

- FRENTE (porta principal) em -Y no Blender = +Z no GLB; no Roblox, depois do giro de 180° do
  importador (D-58), a frente fica em -Z (LookVector). Conferir no Studio.
- cada objeto tem `grupo` (um atlas de textura por grupo) e `no` (um nó do GLB = uma MeshPart);
- a colisão é feita de sólidos convexos simples (`Colisao_*`), separada das malhas visíveis: as
  paredes viram caixas (uma por pedaço entre vãos) e os móveis grandes, caixas baixas;
- o piso de terra batida (nền) fica a `PISO` m do chão e é plano; a porta tem vão livre de
  1,00 × 2,30 m (decisão do dono: o soldado do jogo tem 2,0 m), medido do piso à verga e entre os
  batentes.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
from modelar import Mat, rgb  # noqa: E402

PISO = 0.15  # altura do piso de terra batida acima do chão (m); PLACEHOLDER
PORTA_LARG = 1.00  # vão livre (decisão do dono)
PORTA_ALT = 2.30  # vão livre (decisão do dono)
BATENTE = 0.06  # batente de cada lado e verga (m)
periodo = N.periodo


# =============================================================== receita
class Receita:
    """Objetos altos (com grupo e nó), colisão e dados extras (portas, câmera da prévia)."""

    def __init__(self) -> None:
        self.objs: list[bpy.types.Object] = []
        self.colisao: list[dict] = []
        self.extras: dict = {"portas_m": [], "portas": []}

    def add(self, obj, grupo: str = "Casa", no: str | None = None):
        obj["grupo"] = grupo
        obj["no"] = no or grupo
        self.objs.append(obj)
        return obj

    def addv(self, objs, grupo: str = "Casa", no: str | None = None):
        for o in objs:
            self.add(o, grupo, no)
        return objs

    def _col(self, tipo, nome, pontos, bala, material, obs):
        self.colisao.append(
            {
                "nome": nome,
                "tipo": tipo,
                "pontos": [tuple(float(c) for c in p) for p in pontos],
                "bala": bala,
                "material": material,
                "obs": obs,
            }
        )

    def caixa(self, nome, centro, dim, bala="para", material="Wood", obs="", rot_z=0.0):
        cx, cy, cz = centro
        dx, dy, dz = dim
        r = Matrix.Rotation(rot_z, 3, "Z")
        pts = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    v = r @ Vector((sx * dx / 2, sy * dy / 2, sz * dz / 2))
                    pts.append((cx + v.x, cy + v.y, cz + v.z))
        self._col("caixa", nome, pts, bala, material, obs)

    def prisma(self, nome, pontos, bala="para", material="Earth", obs=""):
        """Sólido convexo (o fecho convexo dos pontos)."""
        self._col("prisma", nome, pontos, bala, material, obs)

    def marca(self) -> tuple[int, int, int]:
        return len(self.objs), len(self.colisao), len(self.extras["portas_m"])

    def transformar(self, desde: tuple[int, int, int], m: Matrix) -> None:
        """Aplica `m` (4x4) a tudo o que entrou depois de `desde` (= `marca()`): objetos,
        colisão e portas. Serve para montar um anexo na origem e pôr no lugar."""
        i_o, i_c, i_p = desde
        for o in self.objs[i_o:]:
            M.mover(o, m)
        for c in self.colisao[i_c:]:
            c["pontos"] = [tuple(m @ Vector(p)) for p in c["pontos"]]
        rot = m.to_3x3()
        for k in range(i_p, len(self.extras["portas_m"])):
            self.extras["portas_m"][k] = list(m @ Vector(self.extras["portas_m"][k]))
            n = rot @ Vector(self.extras["portas"][k]["normal_blender"])
            self.extras["portas"][k]["normal_blender"] = [round(x, 4) for x in n]


def lugar(pos=(0.0, 0.0, 0.0), rot_graus: float = 0.0) -> Matrix:
    p = (pos[0], pos[1], pos[2] if len(pos) > 2 else 0.0)
    return Matrix.Translation(Vector(p)) @ Matrix.Rotation(math.radians(rot_graus), 4, "Z")


# =============================================================== geometria (de bases_comum)
def gravar_uv_local(obj, f, semente: float = 0.0) -> None:
    """Grava o atributo `local` = f(co) -> (u, v, w) e `semente` (lidos pelo material)."""
    me = obj.data
    co = np.empty(len(me.vertices) * 3, np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    loc = np.array([f(Vector(p)) for p in co], np.float32).reshape(-1)
    for nome in ("local", "semente"):
        if nome in me.attributes:
            me.attributes.remove(me.attributes[nome])
    me.attributes.new("local", "FLOAT_VECTOR", "POINT").data.foreach_set("vector", loc)
    me.attributes.new("semente", "FLOAT", "POINT").data.foreach_set(
        "value", np.full(len(me.vertices), semente, np.float32)
    )


def bloco(nome, dim, centro=(0, 0, 0), mat=None, chanfro=0.0, segs=1, rot=None, local=True):
    """Caixa com chanfro opcional, girada (Euler XYZ, rad) e movida para `centro`. Com `local`,
    grava a coordenada da peça (o veio da madeira segue o maior lado)."""
    o = M.caixa(nome, dim, (0, 0, 0))
    if chanfro > 0:
        M.chanfrar(o, chanfro, segs)
    if local:
        eixo = int(np.argmax(dim))
        ordem = {0: (1, 2, 0), 1: (0, 2, 1), 2: (0, 1, 2)}[eixo]
        gravar_uv_local(o, lambda p: (p[ordem[0]], p[ordem[1]], p[ordem[2]]))
    m = Matrix.Translation(Vector(centro))
    if rot is not None:
        m = m @ Euler(rot, "XYZ").to_matrix().to_4x4()
    M.mover(o, m)
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 35)


def base_eixo(p0, p1, cima=(0, 0, 1)) -> Matrix:
    a, b = Vector(p0), Vector(p1)
    z = (b - a).normalized()
    up = Vector(cima)
    if abs(z.dot(up)) > 0.98:
        up = Vector((1, 0, 0)) if abs(z.x) < 0.9 else Vector((0, 1, 0))
    x = up.cross(z).normalized()
    y = z.cross(x).normalized()
    r = Matrix((x, y, z)).transposed().to_4x4()
    return Matrix.Translation(a) @ r


def viga(nome, p0, p1, larg, alt, mat=None, chanfro=0.0, cima=(0, 0, 1)):
    """Viga retangular de p0 a p1 (`local` com Z ao longo da viga, para o veio)."""
    comp = (Vector(p1) - Vector(p0)).length
    o = M.caixa(nome, (larg, alt, comp), (0, 0, comp / 2))
    if chanfro > 0:
        M.chanfrar(o, chanfro, 1)
    gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
    M.mover(o, base_eixo(p0, p1, cima))
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 35)


def tre(nome, p0, p1, r, mat=None, segs=6, r1=None, sem=0.0):
    """Vara de bambu (ou pau roliço) barata: tubo de 2 anéis, `local` com Z ao longo da vara."""
    a, b = Vector(p0), Vector(p1)
    o = M.tubo(nome, [a, b], [r, r1 if r1 is not None else r], segs)
    eixo = (b - a).normalized()
    ref = Vector((0, 0, 1)) if abs(eixo.z) < 0.95 else Vector((1, 0, 0))
    e1 = eixo.cross(ref).normalized()
    e2 = eixo.cross(e1)
    gravar_uv_local(o, lambda p: ((p - a).dot(e1), (p - a).dot(e2), (p - a).dot(eixo)), sem)
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 50)


def tubo_local(nome, pontos, r, mat=None, segs=6, achatar=1.0, sem=0.0):
    """Tubo por uma polilinha, com `local` = (x, y, distância ao longo)."""
    pts = [Vector(p) for p in pontos]
    o = M.tubo(nome, pts, r, segs, achatar=achatar)
    gravar_uv_local(o, lambda p: (p.x, p.y, p.z), sem)
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 55)


def grade(nome, f, nu, nv, fora=None):
    """Superfície paramétrica f(u, v) -> (x, y, z), u e v em [0, 1]."""
    bm = bmesh.new()
    vs = [[bm.verts.new(Vector(f(i / nu, j / nv))) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-6)
    bm.normal_update()
    if fora is not None and bm.faces:
        media = sum((fc.normal * fc.calc_area() for fc in bm.faces), Vector((0, 0, 0)))
        if media.dot(Vector(fora)) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    return M.de_bmesh(nome, bm)


def apagar_faces(obj, cond) -> int:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    fora = [f for f in bm.faces if cond(f.calc_center_median(), f.normal)]
    bmesh.ops.delete(bm, geom=fora, context="FACES")
    soltos = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=soltos, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(fora)


def sem_fundo(obj, z: float, tol: float = 0.012):
    """Tira as faces viradas para baixo encostadas em `z` (pé no chão: nunca aparecem)."""
    apagar_faces(obj, lambda c, n: n.z < -0.9 and abs(c.z - z) < tol)
    return obj


def cilindro(nome, r, h, centro=(0, 0, 0), mat=None, segs=12):
    o = M.torno(nome, [(0.0, 0.0), (r, 0.0), (r, h), (0.0, h)], segs=segs)
    gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
    M.mover(o, Matrix.Translation(Vector(centro) - Vector((0, 0, h / 2))))
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 40)


def torno_local(nome, perfil, segs=14, mat=None, fatiar=None, sem=0.0):
    o = M.torno(nome, perfil, segs=segs, fatiar=fatiar)
    gravar_uv_local(o, lambda p: (p.x, p.y, p.z), sem)
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 60)


# =============================================================== materiais
def mat_vach_dat(nome, base="#8b6b4a", escuro="#5e4630", claro="#a88a64", cal=None, exposta=0.35):
    """Vách đất: barro com palha picada batido sobre trama de bambu (ripas em pé e tiras
    deitadas). Rachaduras, reboco caído mostrando a trama, pé molhado de respingo e, com `cal`,
    caiação gasta por cima. `local` = (u ao longo da parede, z, w através)."""
    m = Mat(nome, rug=0.95)
    p = m.coord("local")
    u, z, _ = m.separar(p)
    manchas = m.ruido(p, 1.3, 5, 0.6)
    cor = m.rampa(manchas, [(0.25, rgb(escuro)), (0.55, rgb(base)), (0.85, rgb(claro))])
    palha = m.ruido(p, 38.0, 2, 0.5)
    cor = m.misturar(m.faixa(palha, 0.66, 0.74, 0.0, 0.45), cor, rgb("#c2ab7c"))
    rach = m.voronoi(m.mapear(p, (1.0, 1.6, 1.0)), 2.2, "DISTANCE_TO_EDGE")
    fenda = m.conta("MULTIPLY", m.faixa(rach, 0.03, 0.0), m.faixa(m.ruido(p, 1.8, 3), 0.42, 0.58))
    cor = m.misturar(m.conta("MULTIPLY", fenda, 0.85), cor, rgb("#33251a"))
    lim = 0.70 - 0.22 * exposta
    caido = m.faixa(m.ruido(m.mapear(p, (1, 1, 1), (3.1, 0, 0)), 0.9, 4, 0.55), lim, lim + 0.04)
    fu = m.conta("FRACT", m.conta("MULTIPLY", u, 9.0))
    estaca = m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fu, 0.5)), 0.32, 0.2)
    fz = m.conta("FRACT", m.conta("MULTIPLY", z, 16.0))
    tira = m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fz, 0.5)), 0.44, 0.3)
    trama = m.conta("MAXIMUM", m.conta("MULTIPLY", estaca, 0.7), tira)
    cor_trama = m.misturar(trama, rgb("#241c14"), rgb("#9c8658"))
    cor = m.misturar(caido, cor, cor_trama)
    if cal:
        sem_cal = m.faixa(m.ruido(m.mapear(p, (1, 1, 1), (0, 5, 0)), 1.1, 4), 0.56, 0.62)
        mascara = m.conta(
            "MULTIPLY", m.conta("SUBTRACT", 1.0, caido), m.conta("SUBTRACT", 1.0, sem_cal)
        )
        cal_cor = m.misturar(m.faixa(manchas, 0.3, 0.8, 0.0, 0.5), rgb(cal), rgb("#b3a994"))
        cor = m.misturar(m.conta("MULTIPLY", mascara, 0.92), cor, cal_cor)
    pe = m.conta(
        "MULTIPLY", m.faixa(z, 0.55, 0.12), m.faixa(m.ruido(p, 3.0, 3), 0.3, 0.6, 0.35, 0.9)
    )
    cor = m.misturar(pe, cor, rgb("#4a3826"))
    escorre = m.conta(
        "MULTIPLY",
        m.faixa(m.ruido(m.mapear(p, (14, 0.6, 14)), 1.0, 3), 0.55, 0.7),
        m.faixa(z, 1.4, 2.4),
    )
    cor = m.misturar(m.conta("MULTIPLY", escorre, 0.35), cor, rgb("#3e3428"))
    m.cor(cor)
    m.rug(0.95)
    altura = m.conta(
        "SUBTRACT",
        m.conta("ADD", manchas, m.conta("MULTIPLY", caido, m.conta("SUBTRACT", trama, 1.2))),
        m.conta("MULTIPLY", fenda, 1.5),
    )
    m.relevo(altura, 0.7, 0.012)
    m.relevo(palha, 0.25, 0.002)
    return m.m


def mat_phen(nome, claro="#b7a070", escuro="#86764f", cinza="#8f8a79", passo=0.032):
    """Phên/cót: tiras de bambu rachado trançadas em sarja 2/2 (u e z do `local`), frestas
    escuras, fibra ao longo de cada tira e acinzentado do tempo."""
    m = Mat(nome, rug=0.7)
    p = m.coord("local")
    u, z, _ = m.separar(p)
    i = m.conta("FLOOR", m.conta("MULTIPLY", u, 1 / passo))
    j = m.conta("FLOOR", m.conta("MULTIPLY", z, 1 / passo))
    fu = m.conta("FRACT", m.conta("MULTIPLY", u, 1 / passo))
    fz = m.conta("FRACT", m.conta("MULTIPLY", z, 1 / passo))
    sel = m.conta("MODULO", m.conta("ADD", m.conta("ADD", i, j), 400.0), 4.0)
    horiz = m.conta("LESS_THAN", sel, 2.0)
    borda_h = m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fz, 0.5)), 0.36, 0.5)
    borda_v = m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fu, 0.5)), 0.36, 0.5)
    borda = m.misturar_valor(horiz, borda_v, borda_h)
    fibra_h = m.ruido(m.mapear(p, (1.5, 45, 45)), 1.0, 5, 0.65)
    fibra_v = m.ruido(m.mapear(p, (45, 1.5, 45)), 1.0, 5, 0.65)
    fibra = m.misturar_valor(horiz, fibra_v, fibra_h)
    cor = m.rampa(fibra, [(0.3, rgb(escuro)), (0.7, rgb(claro))])
    tom = m.ruido(
        m.juntar_xyz(m.conta("MULTIPLY", i, 0.37), m.conta("MULTIPLY", j, 0.29), 0), 1.0, 1
    )
    cor = m.misturar(m.faixa(tom, 0.3, 0.7, 0.0, 0.3), cor, rgb("#6e6044"))
    tempo = m.faixa(m.ruido(p, 1.1, 3), 0.42, 0.7, 0.0, 0.7)
    cor = m.misturar(tempo, cor, rgb(cinza))
    cor = m.misturar(m.conta("MULTIPLY", borda, 0.85), cor, rgb("#2a2219"))
    pe = m.faixa(z, 0.45, 0.05)
    cor = m.misturar(m.conta("MULTIPLY", pe, 0.45), cor, rgb("#4a3c2a"))
    m.cor(cor)
    m.rug(m.misturar_valor(tempo, 0.62, 0.82))
    m.relevo(m.conta("SUBTRACT", 1.0, borda), 0.6, 0.003)
    m.relevo(fibra, 0.2, 0.0008)
    return m.m


def mat_gach(nome, reboco="#d4ccb7", escuro="#a59c88", tijolo="#94523a", exposto=0.3):
    """Tijolo com reboco de cal: reboco encardido (escorridos verticais), bolor no pé e, onde o
    reboco caiu, o tijolo em amarração (fiada de 0,065 m, tijolo de 0,22 m: PLACEHOLDER)."""
    m = Mat(nome, rug=0.9)
    p = m.coord("local")
    u, z, _ = m.separar(p)
    cor_r = m.rampa(m.ruido(p, 2.0, 4), [(0.3, rgb(escuro)), (0.7, rgb(reboco))])
    sujo = m.faixa(m.ruido(m.mapear(p, (8, 0.5, 8)), 1.0, 4), 0.45, 0.75, 0.0, 0.6)
    cor_r = m.misturar(sujo, cor_r, rgb("#857b6a"))
    pe = m.conta("MULTIPLY", m.faixa(z, 0.9, 0.15), m.faixa(m.ruido(p, 4.0, 3), 0.3, 0.6))
    cor_r = m.misturar(pe, cor_r, rgb("#4f5141"))
    fila = m.conta("FLOOR", m.conta("MULTIPLY", z, 1 / 0.065))
    fz = m.conta("FRACT", m.conta("MULTIPLY", z, 1 / 0.065))
    desl = m.conta("MULTIPLY", m.conta("MODULO", m.conta("ADD", fila, 400.0), 2.0), 0.5)
    uu = m.conta("ADD", m.conta("MULTIPLY", u, 1 / 0.22), desl)
    fu = m.conta("FRACT", uu)
    junta = m.conta(
        "MAXIMUM",
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fz, 0.5)), 0.38, 0.45),
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fu, 0.5)), 0.45, 0.48),
    )
    tom = m.ruido(m.juntar_xyz(m.conta("FLOOR", uu), m.conta("MULTIPLY", fila, 0.7), 0), 1.0, 1)
    cor_t = m.rampa(tom, [(0.25, rgb("#6e3a28")), (0.55, rgb(tijolo)), (0.8, rgb("#b0704c"))])
    cor_t = m.misturar(junta, cor_t, rgb("#a39a86"))
    lim = 0.70 - 0.2 * exposto
    sem_reboco = m.faixa(m.ruido(m.mapear(p, (1, 1, 1), (7, 0, 0)), 0.8, 4, 0.6), lim, lim + 0.03)
    cor = m.misturar(sem_reboco, cor_r, cor_t)
    m.cor(cor)
    alt = m.conta(
        "SUBTRACT",
        m.conta("MULTIPLY", m.conta("SUBTRACT", 1.0, sem_reboco), 1.0),
        m.conta("MULTIPLY", m.conta("MULTIPLY", junta, sem_reboco), 0.6),
    )
    m.relevo(alt, 0.6, 0.006)
    m.relevo(m.ruido(p, 60.0, 3), 0.15, 0.001)
    return m.m


def mat_trinh(nome, base="#9a7650", escuro="#6f5236", claro="#b48e64"):
    """Taipa (tường trình): terra socada em camadas de forma (0,5 m: PLACEHOLDER), estrias
    horizontais, pedrinhas, pé gasto pela chuva."""
    m = Mat(nome, rug=0.95)
    p = m.coord("local")
    _, z, _ = m.separar(p)
    camada = m.conta("FLOOR", m.conta("MULTIPLY", z, 2.0))
    tom = m.ruido(m.juntar_xyz(m.conta("MULTIPLY", camada, 1.7), 0.0, 0.0), 1.0, 1)
    cor = m.rampa(m.ruido(p, 1.6, 5), [(0.25, rgb(escuro)), (0.55, rgb(base)), (0.85, rgb(claro))])
    cor = m.misturar(m.faixa(tom, 0.3, 0.7, 0.0, 0.35), cor, rgb("#7d5c3d"))
    estria = m.onda(p, periodo(0.045), "Y", distorcao=2.0, detalhe=2.0)
    cor = m.misturar(m.conta("MULTIPLY", estria, 0.18), cor, rgb("#5a4330"), "MULTIPLY")
    fz = m.conta("FRACT", m.conta("MULTIPLY", z, 2.0))
    junta = m.faixa(m.conta("MINIMUM", fz, m.conta("SUBTRACT", 1.0, fz)), 0.03, 0.0)
    cor = m.misturar(m.conta("MULTIPLY", junta, 0.6), cor, rgb("#4b3828"))
    pedra = m.faixa(m.voronoi(p, 70.0, "F1"), 0.12, 0.05)
    pedra = m.conta("MULTIPLY", pedra, m.faixa(m.ruido(p, 9.0), 0.55, 0.62))
    cor = m.misturar(pedra, cor, rgb("#c2b8a2"))
    pe = m.conta("MULTIPLY", m.faixa(z, 0.6, 0.1), m.faixa(m.ruido(p, 3.0, 3), 0.3, 0.6, 0.3, 0.9))
    cor = m.misturar(pe, cor, rgb("#4c3a28"))
    m.cor(cor)
    alt = m.conta("SUBTRACT", m.conta("ADD", estria, pedra), m.conta("MULTIPLY", junta, 2.0))
    m.relevo(alt, 0.5, 0.008)
    return m.m


def mat_tabua(nome, claro="#7f6a50", escuro="#54412f", cinza="#7f786b", largura=0.24, gasto=0.6):
    """Tábuas em pé (vách ván): veio ao longo de z, frestas a cada `largura` m em u."""
    m = Mat(nome, rug=0.8)
    p = m.coord("local")
    u, z, _ = m.separar(p)
    veio = m.ruido(m.mapear(p, (55, 2.2, 55)), 1.5, 6, 0.65, distorcao=1.2)
    cor = m.rampa(veio, [(0.32, rgb(escuro)), (0.68, rgb(claro))])
    tab = m.conta("FLOOR", m.conta("MULTIPLY", u, 1 / largura))
    tom = m.ruido(m.juntar_xyz(m.conta("MULTIPLY", tab, 0.53), 0.0, 0.0), 1.0, 1)
    cor = m.misturar(m.faixa(tom, 0.3, 0.7, 0.0, 0.4), cor, rgb("#4a3a2a"))
    tempo = m.faixa(m.ruido(p, 2.0, 3), 0.4, 0.7, 0.0, gasto)
    cor = m.misturar(tempo, cor, rgb(cinza))
    fu = m.conta("FRACT", m.conta("MULTIPLY", u, 1 / largura))
    fresta = m.faixa(m.conta("MINIMUM", fu, m.conta("SUBTRACT", 1.0, fu)), 0.02, 0.006)
    cor = m.misturar(fresta, cor, rgb("#1c160f"))
    pe = m.faixa(z, 0.5, 0.05)
    cor = m.misturar(m.conta("MULTIPLY", pe, 0.5), cor, rgb("#3c3022"))
    m.cor(cor)
    m.relevo(m.conta("SUBTRACT", veio, m.conta("MULTIPLY", fresta, 2.0)), 0.4, 0.003)
    return m.m


def mat_go(nome, claro="#7d6549", escuro="#4f3c2b", cinza="#80796d", gasto=0.5, rug=0.8):
    """Madeira de poste, viga e móvel: veio ao longo do Z do `local` (o maior lado da peça)."""
    m = Mat(nome, rug=rug)
    p = m.coord("local")
    veio = m.ruido(m.mapear(p, (40, 40, 1.8)), 1.5, 6, 0.65, distorcao=1.1)
    cor = m.rampa(veio, [(0.3, rgb(escuro)), (0.7, rgb(claro))])
    tempo = m.faixa(m.ruido(m.coord("objeto"), 2.5, 3), 0.4, 0.7, 0.0, gasto)
    cor = m.misturar(tempo, cor, rgb(cinza))
    quina = m.faixa(m.pontudo(), 0.52, 0.6, 0.0, 0.4)
    cor = m.misturar(quina, cor, rgb("#a39478"))
    m.cor(cor)
    m.relevo(veio, 0.35, 0.002)
    return m.m


def mat_tre(nome, claro="#ad9a66", escuro="#7d6e45", cinza="#8e8975", entre_nos=0.32):
    """Bambu roliço (vara barata de `tre`): estrias ao longo do Z do `local`, nós escuros a cada
    `entre_nos` m, manchas de fungo e acinzentado."""
    m = Mat(nome, rug=0.55)
    p = m.coord("local")
    _, _, z = m.separar(p)
    s = m.semente()
    estria = m.ruido(m.mapear(p, (60, 60, 1.2)), 2.0, 5, 0.6)
    cor = m.rampa(estria, [(0.35, rgb(escuro)), (0.7, rgb(claro))])
    tempo = m.faixa(m.ruido(m.mapear(p, (4, 4, 0.8)), 2.0, 3), 0.45, 0.7, 0.0, 0.65)
    cor = m.misturar(tempo, cor, rgb(cinza))
    fz = m.conta("FRACT", m.conta("ADD", m.conta("MULTIPLY", z, 1 / entre_nos), s))
    no_ = m.faixa(m.conta("MINIMUM", fz, m.conta("SUBTRACT", 1.0, fz)), 0.05, 0.015)
    cor = m.misturar(m.conta("MULTIPLY", no_, 0.8), cor, rgb("#4e4329"))
    fungo = m.conta(
        "MULTIPLY", m.faixa(m.voronoi(p, 70.0), 0.08, 0.02), m.faixa(m.ruido(p, 6.0), 0.5, 0.65)
    )
    cor = m.misturar(fungo, cor, rgb("#3d3423"))
    m.cor(cor)
    m.rug(m.misturar_valor(tempo, 0.5, 0.75))
    m.relevo(m.conta("ADD", estria, no_), 0.3, 0.0015)
    return m.m


def mat_tranh(nome, tons=("#3d3424", "#6d6047", "#8e7e5d", "#a99670"), curso=0.24):
    """Palha (rạ de arroz ou capim tranh) do telhado: fibras descendo a água (v do `local`),
    cursos de amarração a cada `curso` m com sombra embaixo, remendos novos dourados, partes
    podres escuras e beiral mais escuro."""
    m = Mat(nome, rug=0.95)
    p = m.coord("local")
    _, v, _ = m.separar(p)
    fibra = m.ruido(m.mapear(p, (55, 1.8, 55)), 1.0, 8, 0.75, distorcao=0.3)
    fina = m.ruido(m.mapear(p, (220, 6, 220)), 1.0, 4, 0.6)
    cor = m.rampa(
        fibra,
        [(0.28, rgb(tons[0])), (0.45, rgb(tons[1])), (0.62, rgb(tons[2])), (0.8, rgb(tons[3]))],
    )
    cor = m.misturar(m.faixa(fina, 0.35, 0.7, 0.0, 0.3), cor, rgb("#3a3122"))
    cv = m.conta(
        "FRACT",
        m.conta(
            "ADD",
            m.conta("MULTIPLY", v, 1 / curso),
            m.conta("MULTIPLY", m.ruido(m.mapear(p, (2, 0.2, 2)), 1.0, 2), 0.6),
        ),
    )
    sombra = m.faixa(cv, 0.14, 0.0)
    cor = m.misturar(m.conta("MULTIPLY", sombra, 0.55), cor, rgb("#2a2318"))
    remendo = m.faixa(m.ruido(m.mapear(p, (1, 1, 1), (11, 0, 0)), 0.5, 2), 0.64, 0.7)
    cor_nova = m.rampa(fibra, [(0.3, rgb("#7d6a43")), (0.7, rgb("#b9a06a"))])
    cor = m.misturar(m.conta("MULTIPLY", remendo, 0.85), cor, cor_nova)
    podre = m.faixa(m.ruido(m.mapear(p, (1, 1, 1), (4, 0, 0)), 0.9, 3), 0.33, 0.24)
    cor = m.misturar(m.conta("MULTIPLY", podre, 0.8), cor, rgb("#3a3828"))
    beiral = m.faixa(v, 0.6, 0.0, 0.0, 0.5)
    cor = m.misturar(beiral, cor, rgb("#3a3020"))
    m.cor(cor)
    m.rug(0.95)
    m.relevo(fibra, 1.0, 0.01)
    m.relevo(fina, 0.5, 0.004)
    m.relevo(m.conta("MULTIPLY", sombra, -1.0), 0.5, 0.012)
    return m.m


def mat_la(nome, tons=("#4f4330", "#76664a", "#958463", "#aa9a78"), fila=0.13):
    """Lá dừa nước (nipa): fileiras de folhas dobradas (`fila` m ao longo de v) com a beirada
    de baixo de cada fileira em sombra, folíolos finos ao longo da água e acinzentado do sol."""
    m = Mat(nome, rug=0.85)
    p = m.coord("local")
    u, v, _ = m.separar(p)
    folio = m.ruido(m.mapear(p, (90, 2.5, 90)), 1.0, 5, 0.7)
    cor = m.rampa(
        folio,
        [(0.3, rgb(tons[0])), (0.48, rgb(tons[1])), (0.64, rgb(tons[2])), (0.8, rgb(tons[3]))],
    )
    fv = m.conta("FRACT", m.conta("MULTIPLY", v, 1 / fila))
    sombra = m.faixa(fv, 0.18, 0.0)
    cor = m.misturar(m.conta("MULTIPLY", sombra, 0.6), cor, rgb("#2b241a"))
    linha = m.faixa(
        m.conta(
            "ABSOLUTE", m.conta("SUBTRACT", m.conta("FRACT", m.conta("MULTIPLY", u, 40.0)), 0.5)
        ),
        0.47,
        0.5,
    )
    cor = m.misturar(m.conta("MULTIPLY", linha, 0.35), cor, rgb("#3a3123"))
    tempo = m.faixa(m.ruido(p, 0.8, 3), 0.45, 0.72, 0.0, 0.6)
    cor = m.misturar(tempo, cor, rgb("#8c877a"))
    beiral = m.faixa(v, 0.5, 0.0, 0.0, 0.45)
    cor = m.misturar(beiral, cor, rgb("#3a3120"))
    m.cor(cor)
    m.rug(m.misturar_valor(tempo, 0.8, 0.92))
    m.relevo(
        m.conta("ADD", m.conta("MULTIPLY", fv, 1.0), m.conta("MULTIPLY", folio, 0.4)), 0.7, 0.01
    )
    return m.m


def mat_ngoi(nome, telha="#94563c", escuro="#6e3d2a", claro="#ad6c48", passo_u=0.22, passo_v=0.27):
    """Telha de barro (ngói âm dương: canais e capas alternados ao longo de u, fiadas a cada
    `passo_v` m em v): cor por telha, líquen escuro e musgo perto do beiral."""
    m = Mat(nome, rug=0.82)
    p = m.coord("local")
    u, v, _ = m.separar(p)
    tid = m.conta("FLOOR", m.conta("MULTIPLY", u, 1 / passo_u))
    rid = m.conta("FLOOR", m.conta("MULTIPLY", v, 1 / passo_v))
    tom = m.ruido(
        m.juntar_xyz(m.conta("MULTIPLY", tid, 1.31), m.conta("MULTIPLY", rid, 2.17), 0.0), 1.0, 1
    )
    cor = m.rampa(tom, [(0.25, rgb(escuro)), (0.55, rgb(telha)), (0.8, rgb(claro))])
    grao = m.ruido(p, 40.0, 4)
    cor = m.misturar(m.faixa(grao, 0.5, 0.8, 0.0, 0.25), cor, rgb("#5a3424"))
    fv = m.conta("FRACT", m.conta("MULTIPLY", v, 1 / passo_v))
    degrau = m.faixa(fv, 0.08, 0.0)
    cor = m.misturar(m.conta("MULTIPLY", degrau, 0.6), cor, rgb("#2e1f17"))
    liquen = m.faixa(m.ruido(p, 1.4, 5), 0.56, 0.66)
    cor = m.misturar(m.conta("MULTIPLY", liquen, 0.8), cor, rgb("#3b3832"))
    musgo = m.conta("MULTIPLY", m.faixa(v, 1.2, 0.0), m.faixa(m.ruido(p, 3.0, 4), 0.45, 0.6))
    cor = m.misturar(m.conta("MULTIPLY", musgo, 0.7), cor, rgb("#545338"))
    cal = m.conta("MULTIPLY", m.faixa(m.ruido(p, 6.0, 3), 0.62, 0.7), 0.5)
    cor = m.misturar(cal, cor, rgb("#b8ad98"))
    m.cor(cor)
    m.rug(m.misturar_valor(liquen, 0.78, 0.92))
    m.relevo(m.conta("SUBTRACT", fv, m.conta("MULTIPLY", degrau, 1.5)), 0.4, 0.006)
    m.relevo(grao, 0.15, 0.001)
    return m.m


def mat_nen(nome, base="#6f5b46", escuro="#4e3f31", claro="#8a745c"):
    """Nền: chão de terra batida varrido (arcos), gasto escuro no caminho, rachas e cisco."""
    m = Mat(nome, rug=0.92)
    p = m.coord("objeto")
    cor = m.rampa(m.ruido(p, 0.9, 5), [(0.25, rgb(escuro)), (0.55, rgb(base)), (0.85, rgb(claro))])
    varrido = m.onda(m.mapear(p, (1, 1, 1)), periodo(0.05), "X", distorcao=6.0, detalhe=3.0)
    cor = m.misturar(m.conta("MULTIPLY", varrido, 0.12), cor, rgb("#3c3026"), "MULTIPLY")
    rach = m.faixa(m.voronoi(p, 1.6, "DISTANCE_TO_EDGE"), 0.012, 0.0)
    rach = m.conta("MULTIPLY", rach, m.faixa(m.ruido(p, 2.0), 0.5, 0.6))
    cor = m.misturar(rach, cor, rgb("#2e241b"))
    cisco = m.conta("MULTIPLY", m.faixa(m.ruido(p, 30.0, 2), 0.68, 0.74), 0.6)
    cor = m.misturar(cisco, cor, rgb("#a8915f"))
    m.cor(cor)
    m.relevo(m.conta("SUBTRACT", varrido, m.conta("MULTIPLY", rach, 3.0)), 0.25, 0.004)
    return m.m


def mat_dat(nome, terra="#6a5137", escuro="#4a3826", capim="#556035"):
    """Terra do monte do abrigo e do fogão: torrões, pedrinhas e capim ralo."""
    m = Mat(nome, rug=0.96)
    p = m.coord("objeto")
    cor = m.rampa(m.ruido(p, 2.0, 6), [(0.3, rgb(escuro)), (0.7, rgb(terra))])
    torrao = m.voronoi(p, 9.0, "F1")
    cor = m.misturar(m.faixa(torrao, 0.25, 0.5, 0.0, 0.3), cor, rgb("#33271b"))
    capim_m = m.faixa(m.ruido(p, 1.2, 4), 0.48, 0.62)
    fios = m.ruido(m.mapear(p, (40, 40, 6)), 1.0, 4)
    cor_c = m.misturar(m.faixa(fios, 0.35, 0.65), rgb(capim), rgb("#7a7a48"))
    cor = m.misturar(m.conta("MULTIPLY", capim_m, 0.85), cor, cor_c)
    m.cor(cor)
    m.relevo(m.conta("ADD", torrao, m.conta("MULTIPLY", fios, capim_m)), 0.6, 0.02)
    return m.m


def mat_luoi(nome, fio="#5b4a36", fundo="#1c1712", passo=0.035):
    """Rede de pesca amontoada ou pendurada (sem transparência: a malha fica escura entre os
    fios). Malha em losango (diagonais de u e v do `local`) e nós claros."""
    m = Mat(nome, rug=0.9)
    p = m.coord("local")
    u, v, _ = m.separar(p)
    a = m.conta("FRACT", m.conta("MULTIPLY", m.conta("ADD", u, v), 1 / passo))
    b = m.conta("FRACT", m.conta("MULTIPLY", m.conta("SUBTRACT", u, v), 1 / passo))
    la = m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", a, 0.5)), 0.38, 0.47)
    lb = m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", b, 0.5)), 0.38, 0.47)
    linha = m.conta("MAXIMUM", la, lb)
    no_ = m.conta("MULTIPLY", la, lb)
    cor = m.misturar(linha, rgb(fundo), rgb(fio))
    cor = m.misturar(m.conta("MULTIPLY", no_, 0.7), cor, rgb("#8a7756"))
    tom = m.faixa(m.ruido(p, 2.0, 3), 0.4, 0.7, 0.0, 0.4)
    cor = m.misturar(tom, cor, rgb("#3e3528"))
    m.cor(cor)
    m.relevo(linha, 0.8, 0.004)
    return m.m


def mat_liso(nome, cor, var="#000000", rug=0.7, escala=3.0, forca=0.15):
    """Cor com variação suave (louça, laca, bronze fosco, arroz, cinza)."""
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    c = m.misturar(m.faixa(m.ruido(p, escala, 4), 0.35, 0.7, 0.0, forca), rgb(cor), rgb(var))
    sujo = m.faixa(m.pontudo(), 0.47, 0.42, 0.0, 0.3)
    c = m.misturar(sujo, c, rgb("#2a241c"))
    m.cor(c)
    m.relevo(m.ruido(p, 80.0, 3), 0.1, 0.0006)
    return m.m


class Mats:
    """Materiais de uma casa (criados uma vez; as variações de cor vêm do catálogo)."""

    def __init__(self, sem: int = 0, **cores) -> None:
        r = np.random.default_rng(sem)

        def j(h, d=0.06):
            c = np.array([int(h[i : i + 2], 16) for i in (1, 3, 5)], np.float64)
            c = np.clip(c * (1 + r.uniform(-d, d)), 0, 255)
            return "#" + "".join(f"{int(x):02x}" for x in c)

        self.j = j
        self.nen = mat_nen("nen", j("#6f5b46"))
        self.go = mat_go("go", j("#7d6549"), j("#4f3c2b"))
        self.go_escuro = mat_go(
            "go_escuro", j("#5a4330"), "#33261b", "#5d564c", gasto=0.25, rug=0.65
        )
        self.tre = mat_tre("tre", j("#ad9a66"), j("#7d6e45"))
        self.phen = mat_phen("phen", j("#b7a070"), j("#86764f"))
        self.dat = mat_dat("dat")
        self.barro = N.mat_barro("barro_pote", j("#86563c"), j("#5a3826"))
        self.barro_escuro = N.mat_barro(
            "barro_escuro", "#4b3a30", "#2c221c", z_molhado=0.4, z_rim=0.9
        )
        self.luoi = mat_luoi("luoi")
        self.corda = N.mat_corda("corda")
        self.pano_verm = N.mat_pano("pano_verm", cor="#6e2620", desbotado="#83463a")
        self.pano_escuro = N.mat_pano("pano_escuro", cor="#2a2724", desbotado="#4a443c")
        self.esteira = mat_phen("esteira", "#c4b07c", "#9a8656", "#a49d86", passo=0.012)
        self.laca = mat_liso("laca", "#5a1d15", "#2e120d", rug=0.45)
        self.bronze = mat_liso("bronze", "#5f4d2e", "#46513f", rug=0.5)
        self.louca = mat_liso("louca", "#c9c3b2", "#7f8a96", rug=0.35)
        self.arroz = mat_liso("arroz", "#d6cbb0", "#a8996f", rug=0.9, escala=40.0, forca=0.5)
        self.cinza = mat_liso("cinza", "#2f2a26", "#5a544c", rug=0.95, escala=8.0, forca=0.6)
        self.ferro = mat_liso("ferro", "#3d3a36", "#5a4030", rug=0.6)
        self.pedra = mat_liso("pedra", "#7b766c", "#5d5a52", rug=0.85, escala=6.0, forca=0.5)
        self.resina = mat_phen("resina", "#3b3328", "#241f19", "#4a4337", passo=0.05)
        self.nonla = N.mat_nonla("nonla")
        self.juta = N.mat_juta("juta")


# =============================================================== paredes, portas e janelas
def peca(nome, o, ang, u0, u1, z0, z1, w0, w1, mat, chanfro=0.0, sem=0.0):
    """Caixa no referencial de uma parede: u ao longo (origem `o`, ângulo `ang` em Z), z para
    cima, w através. `local` = (u, z, w)."""
    obj = M.caixa(nome, (u1 - u0, w1 - w0, z1 - z0), ((u0 + u1) / 2, (w0 + w1) / 2, (z0 + z1) / 2))
    if chanfro > 0:
        M.chanfrar(obj, chanfro, 1)
    gravar_uv_local(obj, lambda p: (p.x, p.z, p.y), sem)
    M.mover(obj, Matrix.Translation((o[0], o[1], 0.0)) @ Matrix.Rotation(ang, 4, "Z"))
    M.material(obj, mat)
    return M.suave(obj, 35)


class Lado:
    """Uma parede reta: origem `o` (x, y), ângulo `ang`, comprimento `comp`, espessura `esp`.
    `dentro` = sinal de w que aponta para dentro da casa."""

    def __init__(self, o, ang, comp, esp, dentro=1.0):
        self.o, self.ang, self.comp, self.esp, self.dentro = o, ang, comp, esp, dentro

    def ponto(self, u, w=0.0, z=0.0) -> Vector:
        r = Matrix.Rotation(self.ang, 3, "Z")
        return Vector((self.o[0], self.o[1], 0.0)) + r @ Vector((u, w, z))

    def normal_fora(self) -> Vector:
        r = Matrix.Rotation(self.ang, 3, "Z")
        return r @ Vector((0.0, -self.dentro, 0.0))


def lados_ret(cx, cy, L, W, esp) -> dict[str, Lado]:
    """As 4 paredes de um retângulo L (X) × W (Y) por fora, centro (cx, cy). Frente e fundo
    vão de ponta a ponta; os lados ficam entre elas. u cresce para +X (frente/fundo) e +Y."""
    return {
        "frente": Lado((cx - L / 2, cy - W / 2 + esp / 2), 0.0, L, esp, 1.0),
        "fundo": Lado((cx - L / 2, cy + W / 2 - esp / 2), 0.0, L, esp, -1.0),
        "esq": Lado((cx - L / 2 + esp / 2, cy - W / 2 + esp), math.pi / 2, W - 2 * esp, esp, -1.0),
        "dir": Lado((cx + L / 2 - esp / 2, cy - W / 2 + esp), math.pi / 2, W - 2 * esp, esp, 1.0),
    }


def parede(
    rec,
    nome,
    lado: Lado,
    z0,
    z1,
    mat,
    vaos=(),
    col="Earth",
    bala="para",
    no="Paredes",
    grupo="Casa",
    chanfro=0.0,
    sem=0.0,
):
    """Parede do `lado` de z0 a z1 com vãos [(c, w, a0, a1)] (centro ao longo da parede,
    largura e alturas do vão). Cada pedaço sólido é uma caixa visível e uma de colisão."""
    pecas = []
    u = 0.0
    for c, w, a0, a1 in sorted(vaos, key=lambda a: a[0]):
        ua, ub = c - w / 2, c + w / 2
        if ua - u > 0.005:
            pecas.append((u, ua, z0, z1))
        if min(a0, z1) - z0 > 0.005:
            pecas.append((ua, ub, z0, min(a0, z1)))
        if z1 - max(a1, z0) > 0.005 and a0 < z1:
            pecas.append((ua, ub, max(a1, z0), z1))
        u = ub
    if lado.comp - u > 0.005:
        pecas.append((u, lado.comp, z0, z1))
    objs = []
    for i, (u0, u1, zz0, zz1) in enumerate(pecas):
        ob = peca(
            f"{nome}_{i}",
            lado.o,
            lado.ang,
            u0,
            u1,
            zz0,
            zz1,
            -lado.esp / 2,
            lado.esp / 2,
            mat,
            chanfro,
            sem,
        )
        rec.add(ob, grupo, no)
        objs.append(ob)
        c = lado.ponto((u0 + u1) / 2)
        rec.caixa(
            f"{nome}_{i}",
            (c.x, c.y, (zz0 + zz1) / 2),
            (u1 - u0, lado.esp, zz1 - zz0),
            bala,
            col,
            rot_z=lado.ang,
        )
    return objs


def vao_porta(t_centro: float, lado: Lado) -> tuple:
    """Vão de porta no meio + `t_centro` da parede: largura e altura com o batente."""
    c = lado.comp / 2 + t_centro
    return (c, PORTA_LARG + 2 * BATENTE, -1.0, PISO + PORTA_ALT + BATENTE)


def vao_janela(t_centro, lado: Lado, w=0.75, z0=1.05, z1=1.75) -> tuple:
    """Vão de janela (alturas a partir do chão de fora)."""
    return (lado.comp / 2 + t_centro, w, z0, z1)


def porta(
    rec,
    nome,
    lado: Lado,
    t_centro,
    mats: Mats,
    estilo="liep",
    mat_bat=None,
    lado_folha=1,
    registrar=True,
):
    """Batentes e verga (o vão livre fica 1,00 × 2,30 m) e a folha: 'liep' (painel de bambu
    trançado escorado do lado de fora), 'folhas' (duas folhas de madeira abertas para dentro,
    rente aos batentes) ou 'tabua' (uma folha de tábuas aberta para dentro). Registra a porta."""
    c = lado.comp / 2 + t_centro
    ua, ub = c - PORTA_LARG / 2 - BATENTE, c + PORTA_LARG / 2 + BATENTE
    e = lado.esp + 0.03
    zt = PISO + PORTA_ALT
    mb = mat_bat or mats.go
    objs = [
        peca(
            f"{nome}_bat_e",
            lado.o,
            lado.ang,
            ua,
            ua + BATENTE,
            0.0,
            zt + BATENTE,
            -e / 2,
            e / 2,
            mb,
        ),
        peca(
            f"{nome}_bat_d",
            lado.o,
            lado.ang,
            ub - BATENTE,
            ub,
            0.0,
            zt + BATENTE,
            -e / 2,
            e / 2,
            mb,
        ),
        peca(
            f"{nome}_verga",
            lado.o,
            lado.ang,
            ua - 0.1,
            ub + 0.1,
            zt,
            zt + BATENTE,
            -e / 2,
            e / 2,
            mb,
        ),
    ]
    for o in objs:
        rec.add(o, "Casa", "Paredes")
    for k, (u0, u1) in enumerate(((ua, ua + BATENTE), (ub - BATENTE, ub))):
        p = lado.ponto((u0 + u1) / 2)
        rec.caixa(
            f"{nome}_batente{k}",
            (p.x, p.y, (zt + BATENTE) / 2),
            (BATENTE, e, zt + BATENTE),
            "para",
            "Wood",
            rot_z=lado.ang,
        )
    din = lado.dentro
    eixo = (lado.ponto(1.0) - lado.ponto(0.0)).normalized()
    if estilo == "liep":
        # painel escorado na parede de fora, ao lado do vão (lado_folha = +1 direita, -1 esquerda)
        u0 = ub + 0.12 if lado_folha > 0 else ua - 0.12 - 1.05
        w_out = -din * (lado.esp / 2 + 0.005)
        w_b = w_out - din * 0.035
        f = peca(
            f"{nome}_liep",
            lado.o,
            lado.ang,
            u0,
            u0 + 1.05,
            0.02,
            2.2,
            min(w_out, w_b),
            max(w_out, w_b),
            mats.phen,
        )
        piv = lado.ponto(u0, w_out, 2.2)
        rot = Matrix.Rotation(0.12, 4, eixo)
        if (rot @ (lado.ponto(u0, w_out, 0.0) - piv)).dot(lado.normal_fora()) < 0:
            rot = Matrix.Rotation(-0.12, 4, eixo)
        M.mover(f, Matrix.Translation(piv) @ rot @ Matrix.Translation(-piv))
        rec.add(f, "Casa", "Paredes")
    elif estilo in ("folhas", "tabua"):
        # folha aberta a 90° para dentro, rente ao batente: fica fora do vão livre
        w_in = din * lado.esp / 2
        if estilo == "folhas":
            folhas = [(ua, PORTA_LARG / 2), (ub - 0.045, PORTA_LARG / 2)]
        else:
            folhas = [(ua if lado_folha < 0 else ub - 0.045, PORTA_LARG)]
        for k, (u0, larg) in enumerate(folhas):
            w0, w1 = sorted((w_in, w_in + din * larg))
            ob = peca(
                f"{nome}_folha{k}",
                lado.o,
                lado.ang,
                u0,
                u0 + 0.045,
                PISO + 0.01,
                zt - 0.01,
                w0,
                w1,
                mats.go_escuro,
            )
            rec.add(ob, "Casa", "Paredes")
    centro = lado.ponto(c, 0.0, PISO)
    rec.extras["portas_m"].append([centro.x, centro.y, centro.z])
    rec.extras["portas"].append(
        {
            "nome": nome,
            "largura_livre_m": PORTA_LARG,
            "altura_livre_m": PORTA_ALT,
            "normal_blender": [round(x, 4) for x in lado.normal_fora()],
            "interna": not registrar,
        }
    )
    return objs


def postes_parede(rec, nome, lado: Lado, H, mats: Mats, vaos=(), passo=1.6, r=0.05):
    """Postes de bambu por fora de uma parede de phên (cantos e a cada `passo` m, fora dos vãos)."""
    n = max(1, round(lado.comp / passo))
    w = -lado.dentro * (lado.esp / 2 + r * 0.8)
    for i in range(n + 1):
        u = lado.comp * i / n
        if any(abs(u - c) < w_ / 2 + 0.12 for c, w_, _, _ in vaos):
            continue
        a, b = lado.ponto(u, w, 0.0), lado.ponto(u, w, H + 0.05)
        rec.add(tre(f"{nome}_p{i}", a, b, r, mats.tre, segs=7, sem=i * 0.41), "Casa", "Estrutura")
    for zz in (0.35, H - 0.2):
        a, b = lado.ponto(0.0, w * 1.6, zz), lado.ponto(lado.comp, w * 1.6, zz)
        rec.add(tre(f"{nome}_rip{zz:.1f}", a, b, 0.028, mats.tre, segs=5), "Casa", "Estrutura")


def janela(
    rec, nome, lado: Lado, t_centro, mats: Mats, w=0.75, z0=1.05, z1=1.75, estilo="grade", aba=False
):
    """Moldura, barras (madeira quadrada em 'grade', bambu roliço em 'tre') e, com `aba`, o
    painel de bambu escorado aberto para fora. Colisão: uma caixa que só segura o jogador."""
    c = lado.comp / 2 + t_centro
    za, zb = z0, z1
    e = lado.esp + 0.02
    ob = []
    ob.append(
        peca(
            f"{nome}_peit",
            lado.o,
            lado.ang,
            c - w / 2 - 0.05,
            c + w / 2 + 0.05,
            za - 0.05,
            za,
            -e / 2,
            e / 2,
            mats.go,
        )
    )
    ob.append(
        peca(
            f"{nome}_verga",
            lado.o,
            lado.ang,
            c - w / 2 - 0.05,
            c + w / 2 + 0.05,
            zb,
            zb + 0.05,
            -e / 2,
            e / 2,
            mats.go,
        )
    )
    n = max(3, int(w / 0.11))
    for k in range(n):
        u = c - w / 2 + (k + 0.5) * w / n
        if estilo == "tre":
            a, b = lado.ponto(u, 0, za), lado.ponto(u, 0, zb)
            ob.append(tre(f"{nome}_b{k}", a, b, 0.016, mats.tre, segs=5, sem=k * 0.37))
        else:
            ob.append(
                peca(
                    f"{nome}_b{k}",
                    lado.o,
                    lado.ang,
                    u - 0.017,
                    u + 0.017,
                    za,
                    zb,
                    -0.017,
                    0.017,
                    mats.go,
                )
            )
    if aba:
        # painel de bambu articulado em cima, aberto 55° para fora e escorado numa vara
        wf = -lado.dentro * (lado.esp / 2 + 0.02)
        wb = wf - lado.dentro * 0.03
        painel = peca(
            f"{nome}_aba",
            lado.o,
            lado.ang,
            c - w / 2 - 0.08,
            c + w / 2 + 0.08,
            za - 0.05,
            zb + 0.12,
            min(wf, wb),
            max(wf, wb),
            mats.phen,
        )
        eixo = (lado.ponto(1.0) - lado.ponto(0.0)).normalized()
        piv = lado.ponto(c, wf, zb + 0.12)
        rot = Matrix.Rotation(math.radians(55), 4, eixo)
        if (rot @ (lado.ponto(c, wf, za) - piv)).dot(lado.normal_fora()) < 0:
            rot = Matrix.Rotation(-math.radians(55), 4, eixo)
        M.mover(painel, Matrix.Translation(piv) @ rot @ Matrix.Translation(-piv))
        ob.append(painel)
        ponta = piv + (rot @ (lado.ponto(c, wf, za - 0.05) - piv))
        pe = lado.ponto(c, wf, za - 0.08)
        ob.append(tre(f"{nome}_escora", pe, ponta, 0.014, mats.tre, segs=5))
    for o in ob:
        rec.add(o, "Casa", "Paredes")
    p = lado.ponto(c)
    rec.caixa(
        f"{nome}",
        (p.x, p.y, (za + zb) / 2),
        (w, lado.esp, zb - za),
        "passa",
        "Wood",
        "só segura o jogador (a bala passa pelas grades)",
        rot_z=lado.ang,
    )
    return ob


def nen(rec, nome, x0, y0, x1, y1, mats: Mats, h=PISO):
    """Piso de terra batida elevado (nền), com a beirada arredondada; colisão em caixa."""
    o = bloco(
        nome,
        (x1 - x0, y1 - y0, h),
        ((x0 + x1) / 2, (y0 + y1) / 2, h / 2),
        mats.nen,
        chanfro=0.04,
        segs=2,
    )
    sem_fundo(o, 0.0)
    rec.add(o, "Casa", "Piso")
    rec.caixa(nome, ((x0 + x1) / 2, (y0 + y1) / 2, h / 2), (x1 - x0, y1 - y0, h), "para", "Ground")
    return o


# =============================================================== telhados
def placa(nome, A, B, Cc, D, esp, tipo, mat, res=0.08, sem=0, franja=0.07):
    """Água de telhado sobre o quadrilátero A (beiral, esquerda), B (beiral, direita), C (topo,
    direita), D (topo, esquerda), bilinear (C = D faz triângulo). Espessura `esp` para baixo e
    relevo do `tipo` na face de cima: 'tranh' (palha), 'la' (nipa) ou 'ngoi' (telha). `local` =
    (u ao longo do beiral, v subindo a água, 0)."""
    A, B, Cc, D = (Vector(x) for x in (A, B, Cc, D))
    u_dir = (B - A).normalized()
    meio_b, meio_t = (A + B) / 2, (Cc + D) / 2
    nrm = (B - A).cross(D - A if (D - A).length > 1e-6 else Cc - A).normalized()
    if nrm.z < 0:
        nrm = -nrm
    v_dir = nrm.cross(u_dir).normalized()
    if v_dir.dot(meio_t - meio_b) < 0:
        v_dir = -v_dir
    Lu = max((B - A).length, (Cc - D).length)
    Lv = (meio_t - meio_b).length
    ru = 0.055 if tipo == "ngoi" else res
    rv = 0.09 if tipo == "ngoi" else res
    nu, nv = max(2, round(Lu / ru)), max(2, round(Lv / rv))

    def f(a, b):
        return (A.lerp(B, a)).lerp(D.lerp(Cc, a), b)

    obj = grade(nome, f, nu, nv, fora=nrm)
    M.solidificar(obj, esp, -1.0)
    rng = np.random.default_rng(sem)
    fase = float(rng.uniform(0, 100))

    def forma(co, n):
        rel = co - A
        a, b = rel.dot(u_dir), rel.dot(v_dir)
        cima = n.dot(nrm) > 0.3
        q = Vector((a * 1.3, b * 0.6, fase))
        d = 0.0
        if tipo == "ngoi":
            if cima:
                d = 0.028 * math.cos(2 * math.pi * a / 0.22) + 0.012 * ((b / 0.27) % 1.0)
                d += 0.006 * M.ruido(q * 3.0, sem)
            desl = nrm * d
            return desl
        if cima:
            camada = ((b / 0.24 + 0.25 * M.ruido(q * 2.0, sem)) % 1.0) * (
                0.05 if tipo == "tranh" else 0.035
            )
            fibra = 0.014 * M.ruido(Vector((a * 45, b * 2.5, fase)), sem + 1)
            tufo = (0.03 if tipo == "tranh" else 0.015) * M.fbm(q * 1.5, 3, sem + 2)
            d = camada + fibra + tufo
        else:
            d = 0.01 * M.fbm(q * 2.0, 2, sem + 3)
        desl = nrm * d
        borda = max(0.0, 1.0 - b / 0.15)
        if borda > 0 and franja > 0:
            fio = franja * (
                0.35 + 0.65 * (0.5 + 0.5 * M.ruido(Vector((a * 22, fase, 0.0)), sem + 4))
            )
            desl += -v_dir * fio * borda - nrm * 0.03 * borda
        return desl

    M.deslocar(obj, forma)
    gravar_uv_local(obj, lambda p: ((p - A).dot(u_dir), (p - A).dot(v_dir), 0.0), float(sem))
    M.material(obj, mat)
    return M.suave(obj, 70 if tipo != "ngoi" else 50), nrm


def _prisma_placa(rec, nome, cantos, nrm, esp, bala, material):
    pts = [tuple(Vector(c)) for c in cantos] + [tuple(Vector(c) - nrm * esp) for c in cantos]
    rec.prisma(nome, pts, bala, material)


def cumeeira(nome, p0, p1, tipo, mats_tel, r=0.15, sem=0):
    """Cumeeira (e espigões): rolo de palha amarrado ou fileira de telhas-capa com argamassa."""
    a, b = Vector(p0), Vector(p1)
    n = max(2, int((b - a).length / 0.25))
    pts = [a.lerp(b, i / n) for i in range(n + 1)]
    if tipo == "ngoi":
        o = tubo_local(nome, pts, r * 0.62, mats_tel, segs=8, achatar=0.75, sem=sem)
    else:
        o = tubo_local(nome, pts, r, mats_tel, segs=8, achatar=0.6, sem=sem)
        M.deslocar(o, lambda co, nn: 0.025 * M.fbm(co * 4.0, 3, sem + 9))
    gravar_uv_local(
        o, lambda p: ((p - a).dot((b - a).normalized()), 0.3 + (p.z - a.z), 0.0), float(sem)
    )
    return o


def telhado(
    rec,
    nome,
    L,
    W,
    h,
    hr,
    beiral,
    forma,
    tipo,
    esp,
    mat_tel,
    mats: Mats,
    beiral_oitao=0.35,
    sem=0,
    tesouras=(),
    mat_oitao=None,
    oitao_esp=0.15,
    col_oitao="Earth",
    m_lugar: Matrix | None = None,
    estrutura=True,
    grupo="Telhado",
):
    """Telhado sobre o retângulo de paredes L (X) × W (Y), centrado na origem e com a cumeeira
    ao longo de X (use `m_lugar` para mover/girar). `h` = topo da parede (a água passa 0,05 m
    acima da quina de fora), `hr` = cumeeira. `forma`: '4aguas' (espigões a 45°) ou '2aguas'
    (oitões em ±X, preenchidos com `mat_oitao`). Embaixo: frechal, cumeeira, terças e caibros de
    bambu e as tesouras (linha + pendural) nos X de `tesouras`."""
    marca = rec.marca()
    rec.extras.setdefault("telhados", []).append(
        {
            "nome": nome,
            "L": L,
            "W": W,
            "parede": h,
            "cumeeira": hr,
            "beiral": beiral,
            "forma": forma,
            "cobertura": tipo,
        }
    )
    s = (hr - (h + 0.05)) / (W / 2)
    bala = "passa" if tipo in ("tranh", "la") else "para"
    material = "Thatch" if tipo in ("tranh", "la") else "Tile"

    def planos_de(o, og):
        ze = hr - s * (W / 2 + o)
        if forma == "4aguas":
            r = max(0.0, (L - W) / 2)
            X, Y = L / 2 + o, W / 2 + o
            pl = [
                ((-X, -Y, ze), (X, -Y, ze), (r, 0, hr), (-r, 0, hr)),
                ((X, Y, ze), (-X, Y, ze), (-r, 0, hr), (r, 0, hr)),
                ((X, -Y, ze), (X, Y, ze), (r, 0, hr), (r, 0, hr)),
                ((-X, Y, ze), (-X, -Y, ze), (-r, 0, hr), (-r, 0, hr)),
            ]
            tp = [((-r, 0, hr), (r, 0, hr))] if r > 0.05 else []
            es = [((sx * X, sy * Y, ze), (sx * r, 0, hr)) for sx in (-1, 1) for sy in (-1, 1)]
        else:
            X, Y = L / 2 + og, W / 2 + o
            pl = [
                ((-X, -Y, ze), (X, -Y, ze), (X, 0, hr), (-X, 0, hr)),
                ((X, Y, ze), (-X, Y, ze), (-X, 0, hr), (X, 0, hr)),
            ]
            tp = [((-X, 0, hr), (X, 0, hr))]
            es = []
        return pl, tp, es

    planos, topo, espig = planos_de(beiral, beiral_oitao)
    # colisão só da parede para dentro (o beiral não segura quem passa embaixo), 0,06 m de espessura
    planos_col, _, _ = planos_de(0.03, 0.03)
    for k, (A, B, Cc, D) in enumerate(planos):
        ob, nrm = placa(f"{nome}_agua{k}", A, B, Cc, D, esp, tipo, mat_tel, sem=sem * 10 + k)
        rec.add(ob, grupo, "Telhado")
        Ac, Bc, Ccc, Dc = planos_col[k]
        cantos = [Ac, Bc, Ccc] if Vector(Ccc) == Vector(Dc) else [Ac, Bc, Ccc, Dc]
        _prisma_placa(rec, f"{nome}_agua{k}", cantos, nrm, 0.06, bala, material)
    rc = 0.15 if tipo != "ngoi" else 0.12
    for k, (p0, p1) in enumerate(topo + espig):
        a, b = Vector(p0) + Vector((0, 0, 0.02)), Vector(p1) + Vector((0, 0, 0.02))
        rec.add(
            cumeeira(f"{nome}_cum{k}", a, b, tipo, mat_tel, r=rc, sem=sem + k), grupo, "Telhado"
        )
    if forma == "2aguas" and mat_oitao is not None:
        for sx in (-1, 1):
            x = sx * (L / 2 - oitao_esp / 2)
            zt = hr - esp - 0.03
            yb = W / 2
            bm = bmesh.new()
            vs = []
            for dx in (-oitao_esp / 2, oitao_esp / 2):
                vs.append(
                    [
                        bm.verts.new((x + dx, -yb, h)),
                        bm.verts.new((x + dx, yb, h)),
                        bm.verts.new((x + dx, 0.0, zt)),
                    ]
                )
            bm.faces.new(vs[0][::-1])
            bm.faces.new(vs[1])
            for i in range(3):
                j = (i + 1) % 3
                bm.faces.new((vs[0][i], vs[0][j], vs[1][j], vs[1][i]))
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            ob = M.de_bmesh(f"{nome}_oitao{sx}", bm)
            gravar_uv_local(ob, lambda p: (p.y, p.z, p.x), float(sem))
            M.material(ob, mat_oitao)
            rec.add(M.suave(ob, 30), "Casa", "Paredes")
            rec.prisma(
                f"{nome}_oitao{sx}", [tuple(v.co) for v in ob.data.vertices], "para", col_oitao
            )
    if estrutura:
        # caibros de bambu sob cada água (seguem a água do beiral ao topo), terças e cumeeira
        for k, (A, B, Cc, D) in enumerate(planos):
            A, B, Cc, D = (Vector(x) for x in (A, B, Cc, D))
            nrm = (B - A).cross(D - A if (D - A).length > 1e-6 else Cc - A).normalized()
            if nrm.z < 0:
                nrm = -nrm
            off = -nrm * (esp + 0.035)
            n_c = max(2, int((B - A).length / 0.75))
            for i in range(1, n_c):
                t = i / n_c
                p0 = A.lerp(B, t).lerp(D.lerp(Cc, t), 0.12) + off
                p1 = A.lerp(B, t).lerp(D.lerp(Cc, t), 0.97) + off
                if (p1 - p0).length < 0.3:
                    continue
                rec.add(
                    tre(f"{nome}_caibro{k}_{i}", p0, p1, 0.03, mats.tre, segs=5, sem=i * 0.31),
                    "Casa",
                    "Estrutura",
                )
            if (D - Cc).length > 0.2:
                for t in (0.35, 0.68):
                    p0 = A.lerp(D, t) + off * 1.0 - nrm * 0.06
                    p1 = B.lerp(Cc, t) + off * 1.0 - nrm * 0.06
                    rec.add(
                        tre(f"{nome}_terca{k}_{t}", p0, p1, 0.035, mats.tre, segs=5, sem=t),
                        "Casa",
                        "Estrutura",
                    )
        for k, (p0, p1) in enumerate(topo):
            a = Vector(p0) - Vector((0, 0, esp + 0.12))
            b = Vector(p1) - Vector((0, 0, esp + 0.12))
            rec.add(viga(f"{nome}_cumeeira_viga{k}", a, b, 0.1, 0.12, mats.go), "Casa", "Estrutura")
        for sy in (-1, 1):
            a = Vector((-L / 2 + 0.1, sy * (W / 2 - 0.12), h - 0.06))
            b = Vector((L / 2 - 0.1, sy * (W / 2 - 0.12), h - 0.06))
            rec.add(viga(f"{nome}_frechal{sy}", a, b, 0.12, 0.12, mats.go), "Casa", "Estrutura")
        for k, x in enumerate(tesouras):
            zt = h - 0.06
            a = Vector((x, -W / 2 + 0.1, zt))
            b = Vector((x, W / 2 - 0.1, zt))
            rec.add(viga(f"{nome}_linha{k}", a, b, 0.11, 0.14, mats.go), "Casa", "Estrutura")
            zc = hr - esp - 0.14
            rec.add(
                viga(f"{nome}_pendural{k}", (x, 0, zt + 0.07), (x, 0, zc), 0.1, 0.1, mats.go),
                "Casa",
                "Estrutura",
            )
            for sy in (-1, 1):
                rec.add(
                    viga(
                        f"{nome}_perna{k}{sy}",
                        (x, sy * (W / 2 - 0.2), zt + 0.07),
                        (x, 0, zc - 0.05),
                        0.08,
                        0.1,
                        mats.go,
                    ),
                    "Casa",
                    "Estrutura",
                )
    if m_lugar is not None:
        rec.transformar(marca, m_lugar)


def agua_unica(
    rec,
    nome,
    x0,
    x1,
    y_alto,
    z_alto,
    y_baixo,
    z_baixo,
    esp,
    tipo,
    mat_tel,
    mats: Mats,
    sem=0,
    postes=(),
    mat_poste=None,
    grupo="Telhado",
):
    """Água única (puxado, varanda, cozinha): de y_alto/z_alto (encostada na parede) a
    y_baixo/z_baixo (beiral), de x0 a x1. `postes`: x dos postes no beiral (com viga)."""
    A = (x0, y_baixo, z_baixo)
    B = (x1, y_baixo, z_baixo)
    if y_baixo > y_alto:
        A, B = B, A
    Cc = (B[0], y_alto, z_alto)
    D = (A[0], y_alto, z_alto)
    ob, nrm = placa(f"{nome}_agua", A, B, Cc, D, esp, tipo, mat_tel, sem=sem)
    rec.add(ob, grupo, "Telhado")
    bala = "passa" if tipo in ("tranh", "la") else "para"
    # colisão rente à face de cima (0,05 m): quem passa embaixo do beiral da varanda não esbarra
    _prisma_placa(
        rec, f"{nome}_agua", [A, B, Cc, D], nrm, 0.05, bala, "Thatch" if bala == "passa" else "Tile"
    )
    if postes:
        dy = 0.25 if y_baixo < y_alto else -0.25
        yp = y_baixo + dy
        s = (z_alto - z_baixo) / abs(y_alto - y_baixo)
        zp = z_baixo + s * abs(dy) - esp - 0.08
        mp = mat_poste or mats.tre
        for k, x in enumerate(postes):
            if mp is mats.tre:
                rec.add(
                    tre(
                        f"{nome}_poste{k}",
                        (x, yp, 0.0),
                        (x, yp, zp),
                        0.055,
                        mp,
                        segs=7,
                        sem=k * 0.4,
                    ),
                    "Casa",
                    "Estrutura",
                )
            else:
                rec.add(
                    bloco(f"{nome}_poste{k}", (0.13, 0.13, zp), (x, yp, zp / 2), mp, chanfro=0.01),
                    "Casa",
                    "Estrutura",
                )
            rec.caixa(f"{nome}_poste{k}", (x, yp, zp / 2), (0.13, 0.13, zp), "para", "Wood")
        rec.add(
            viga(
                f"{nome}_viga",
                (min(postes) - 0.2, yp, zp + 0.05),
                (max(postes) + 0.2, yp, zp + 0.05),
                0.1,
                0.12,
                mats.go,
            ),
            "Casa",
            "Estrutura",
        )
        n_c = max(2, int(abs(x1 - x0) / 0.8))
        for i in range(1, n_c):
            x = x0 + (x1 - x0) * i / n_c
            za = z_alto - esp - 0.04
            zb = z_baixo + s * 0.1 - esp - 0.04
            rec.add(
                tre(
                    f"{nome}_caibro{i}",
                    (x, y_baixo + (0.1 if dy > 0 else -0.1), zb),
                    (x, y_alto, za),
                    0.028,
                    mats.tre,
                    segs=5,
                    sem=i * 0.29,
                ),
                "Casa",
                "Estrutura",
            )
    return ob


def poste(rec, nome, x, y, z1, mat, r=0.08, quadrado=True, base_pedra=None):
    """Poste/coluna de madeira (com sapata de pedra opcional) e a colisão."""
    if quadrado:
        o = bloco(nome, (2 * r, 2 * r, z1), (x, y, z1 / 2), mat, chanfro=0.012)
    else:
        o = cilindro(nome, r, z1, (x, y, z1 / 2), mat, segs=10)
    rec.add(o, "Casa", "Estrutura")
    if base_pedra is not None:
        s = torno_local(
            f"{nome}_sapata",
            [(0.0, 0.0), (r * 1.7, 0.0), (r * 1.6, 0.12), (r * 1.25, 0.2), (0.0, 0.2)],
            10,
            base_pedra,
        )
        M.mover(s, Matrix.Translation((x, y, 0.0)))
        rec.add(s, "Casa", "Estrutura")
    rec.caixa(nome, (x, y, z1 / 2), (2 * r, 2 * r, z1), "para", "Wood")
    return o


# =============================================================== móveis e objetos
def _colocar(objs, pos, rot):
    m = lugar(pos, rot)
    for o in objs:
        M.mover(o, m)
    return objs


def _col_local(rec, nome, pos, rot, centro, dim, bala="para", material="Wood"):
    r = Matrix.Rotation(math.radians(rot), 3, "Z")
    c = Vector((pos[0], pos[1], 0.0)) + r @ Vector(centro)
    rec.caixa(nome, tuple(c), dim, bala, material, rot_z=math.radians(rot))


def phan(rec, nome, pos, rot, mats: Mats, comp=1.9, larg=1.3, alt=0.45, esteira=True, sem=0):
    """Phản/bộ ván: cama de tábuas largas sobre pés (PLACEHOLDER: 1,9 × 1,3 × 0,45 m), com
    esteira enrolada e travesseiro de madeira."""
    z = PISO
    o = []
    n = 3
    for i in range(n):
        y = -larg / 2 + (i + 0.5) * larg / n
        o.append(
            bloco(
                f"{nome}_tab{i}",
                (comp, larg / n - 0.012, 0.045),
                (0, y, z + alt - 0.0225),
                mats.go_escuro,
                chanfro=0.006,
            )
        )
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                bloco(
                    f"{nome}_pe{sx}{sy}",
                    (0.09, 0.09, alt - 0.045),
                    (sx * (comp / 2 - 0.12), sy * (larg / 2 - 0.1), z + (alt - 0.045) / 2),
                    mats.go_escuro,
                )
            )
        o.append(
            bloco(
                f"{nome}_trav{sx}",
                (0.06, larg - 0.2, 0.08),
                (sx * (comp / 2 - 0.12), 0, z + alt - 0.11),
                mats.go_escuro,
            )
        )
    if esteira:
        e = cilindro(f"{nome}_esteira", 0.06, larg * 0.85, (0, 0, 0), mats.esteira, segs=10)
        M.mover(
            e,
            Matrix.Translation((-comp / 2 + 0.2, 0, z + alt + 0.06))
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        o.append(e)
        o.append(
            bloco(
                f"{nome}_trav_cab",
                (0.12, 0.3, 0.09),
                (-comp / 2 + 0.42, 0.25, z + alt + 0.045),
                mats.go,
                chanfro=0.015,
            )
        )
        o.append(
            bloco(
                f"{nome}_manta",
                (0.5, 0.42, 0.07),
                (comp / 2 - 0.35, -0.2, z + alt + 0.035),
                mats.pano_escuro,
                chanfro=0.025,
                segs=2,
            )
        )
    for ob in o:
        sem_fundo(ob, z)
    rec.addv(_colocar(o, pos, rot), "Mobilia", "Mobilia")
    _col_local(rec, nome, pos, rot, (0, 0, z + alt / 2), (comp, larg, alt))


def cho_tre(rec, nome, pos, rot, mats: Mats, comp=1.9, larg=1.0, alt=0.45, sem=0):
    """Chõng tre: catre de bambu (pés, travessas e ripas roliças) (PLACEHOLDER: 1,9 × 1,0 ×
    0,45 m)."""
    z = PISO
    o = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                tre(
                    f"{nome}_pe{sx}{sy}",
                    (sx * (comp / 2 - 0.06), sy * (larg / 2 - 0.05), z),
                    (sx * (comp / 2 - 0.06), sy * (larg / 2 - 0.05), z + alt + 0.04),
                    0.03,
                    mats.tre,
                    segs=6,
                )
            )
        o.append(
            tre(
                f"{nome}_lat{sx}",
                (-comp / 2, sx * (larg / 2 - 0.05), z + alt - 0.03),
                (comp / 2, sx * (larg / 2 - 0.05), z + alt - 0.03),
                0.028,
                mats.tre,
                segs=6,
            )
        )
        o.append(
            tre(
                f"{nome}_cab{sx}",
                (sx * (comp / 2 - 0.06), -larg / 2, z + alt - 0.06),
                (sx * (comp / 2 - 0.06), larg / 2, z + alt - 0.06),
                0.025,
                mats.tre,
                segs=6,
            )
        )
        o.append(
            tre(
                f"{nome}_bx{sx}",
                (sx * (comp / 2 - 0.06), -larg / 2 + 0.05, z + 0.14),
                (sx * (comp / 2 - 0.06), larg / 2 - 0.05, z + 0.14),
                0.02,
                mats.tre,
                segs=5,
            )
        )
    n = int(larg / 0.055)
    for i in range(n):
        y = -larg / 2 + 0.06 + i * (larg - 0.12) / max(1, n - 1)
        o.append(
            tre(
                f"{nome}_ripa{i}",
                (-comp / 2 + 0.02, y, z + alt),
                (comp / 2 - 0.02, y, z + alt),
                0.02,
                mats.tre,
                segs=5,
                sem=i * 0.23,
            )
        )
    o.append(
        bloco(
            f"{nome}_esteira",
            (comp * 0.8, larg * 0.8, 0.012),
            (0.05, 0, z + alt + 0.026),
            mats.esteira,
            local=True,
        )
    )
    rec.addv(_colocar(o, pos, rot), "Mobilia", "Mobilia")
    _col_local(rec, nome, pos, rot, (0, 0, z + alt / 2), (comp, larg, alt))


def ban_thap(rec, nome, pos, rot, mats: Mats, comp=0.9, larg=0.6, alt=0.4, cha=True, banquinhos=2):
    """Mesa baixa (PLACEHOLDER: 0,9 × 0,6 × 0,4 m) com bule e xícaras e banquinhos."""
    z = PISO
    o = [bloco(f"{nome}_tampo", (comp, larg, 0.04), (0, 0, z + alt - 0.02), mats.go, chanfro=0.008)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                bloco(
                    f"{nome}_pe{sx}{sy}",
                    (0.05, 0.05, alt - 0.04),
                    (sx * (comp / 2 - 0.06), sy * (larg / 2 - 0.06), z + (alt - 0.04) / 2),
                    mats.go,
                )
            )
    if cha:
        bule = torno_local(
            f"{nome}_bule",
            [
                (0.0, 0.0),
                (0.055, 0.0),
                (0.075, 0.04),
                (0.07, 0.085),
                (0.04, 0.11),
                (0.012, 0.125),
                (0.0, 0.13),
            ],
            12,
            mats.louca,
        )
        M.mover(bule, Matrix.Translation((0.1, 0.05, z + alt)))
        o.append(bule)
        o.append(
            tre(
                f"{nome}_bico",
                (0.17, 0.05, z + alt + 0.05),
                (0.23, 0.05, z + alt + 0.1),
                0.01,
                mats.louca,
                segs=5,
            )
        )
        for k, (x, y) in enumerate(((-0.12, 0.12), (-0.2, -0.05), (-0.05, -0.15))):
            xi = torno_local(
                f"{nome}_xic{k}",
                [(0.0, 0.0), (0.025, 0.0), (0.035, 0.045), (0.0, 0.045)],
                10,
                mats.louca,
            )
            M.mover(xi, Matrix.Translation((x, y, z + alt)))
            o.append(xi)
    for k in range(banquinhos):
        a = math.pi * k + 0.3
        bx, by = math.cos(a) * (comp / 2 + 0.3), math.sin(a) * 0.15
        o.append(
            bloco(f"{nome}_banco{k}", (0.3, 0.26, 0.03), (bx, by, z + 0.26), mats.go, chanfro=0.006)
        )
        for sx in (-1, 1):
            o.append(
                bloco(
                    f"{nome}_bpe{k}{sx}",
                    (0.03, 0.22, 0.245),
                    (bx + sx * 0.11, by, z + 0.1225),
                    mats.go,
                )
            )
    for ob in o:
        sem_fundo(ob, z)
    rec.addv(_colocar(o, pos, rot), "Mobilia", "Mobilia")
    _col_local(rec, nome, pos, rot, (0, 0, z + alt / 2), (comp, larg, alt))


def ban_tho(
    rec, nome, pos, rot, mats: Mats, comp=1.25, prof=0.55, alt=1.0, rico=False, painel=True
):
    """Bàn thờ: mesa alta dos ancestrais (PLACEHOLDER: 1,25 × 0,55 × 1,0 m) com toalha vermelha
    na frente, incensário, dois castiçais, tabuletas dos ancestrais num estrado, prato de frutas
    e, atrás e acima, uma tábua de honra lisa (sem texto). `rico`: armário-altar mais alto atrás."""
    z = PISO
    o = []
    o.append(
        bloco(
            f"{nome}_tampo",
            (comp, prof, 0.05),
            (0, 0, z + alt - 0.025),
            mats.laca if rico else mats.go_escuro,
            chanfro=0.008,
        )
    )
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                bloco(
                    f"{nome}_pe{sx}{sy}",
                    (0.07, 0.07, alt - 0.05),
                    (sx * (comp / 2 - 0.06), sy * (prof / 2 - 0.06), z + (alt - 0.05) / 2),
                    mats.go_escuro,
                )
            )
    o.append(
        bloco(
            f"{nome}_saia",
            (comp * 0.9, 0.015, 0.45),
            (0, -prof / 2 - 0.01, z + alt - 0.27),
            mats.pano_verm,
            local=True,
        )
    )
    o.append(bloco(f"{nome}_trav", (comp - 0.12, 0.05, 0.05), (0, 0, z + 0.18), mats.go_escuro))
    zt = z + alt
    est = bloco(
        f"{nome}_estrado",
        (0.5, 0.2, 0.08),
        (0, prof / 2 - 0.13, zt + 0.04),
        mats.laca,
        chanfro=0.006,
    )
    o.append(est)
    for k in range(3):
        o.append(
            bloco(
                f"{nome}_tabuleta{k}",
                (0.09, 0.025, 0.24),
                (-0.14 + 0.14 * k, prof / 2 - 0.13, zt + 0.08 + 0.12),
                mats.laca,
                chanfro=0.004,
            )
        )
    lu = torno_local(
        f"{nome}_incenso",
        [(0.0, 0.0), (0.06, 0.0), (0.075, 0.03), (0.08, 0.085), (0.07, 0.1), (0.0, 0.1)],
        12,
        mats.bronze,
    )
    M.mover(lu, Matrix.Translation((0, -0.05, zt)))
    o.append(lu)
    for k in range(3):
        o.append(
            tre(
                f"{nome}_vareta{k}",
                (-0.02 + 0.02 * k, -0.05, zt + 0.09),
                (-0.03 + 0.03 * k, -0.06, zt + 0.3),
                0.003,
                mats.laca,
                segs=4,
            )
        )
    for sx in (-1, 1):
        c = torno_local(
            f"{nome}_castical{sx}",
            [
                (0.0, 0.0),
                (0.05, 0.0),
                (0.04, 0.02),
                (0.015, 0.05),
                (0.012, 0.22),
                (0.035, 0.24),
                (0.015, 0.26),
                (0.0, 0.26),
            ],
            10,
            mats.bronze,
        )
        M.mover(c, Matrix.Translation((sx * 0.38, -0.05, zt)))
        o.append(c)
    prato = torno_local(
        f"{nome}_prato", [(0.0, 0.0), (0.06, 0.0), (0.13, 0.03), (0.0, 0.025)], 12, mats.louca
    )
    M.mover(prato, Matrix.Translation((0.23, 0.08, zt)))
    o.append(prato)
    for k in range(3):
        fr = M.superelipsoide(f"{nome}_fruta{k}", 0.04, 0.04, 0.04, 1.0, 1.0, 8, 5)
        gravar_uv_local(fr, lambda p: (p.x, p.y, p.z))
        M.mover(fr, Matrix.Translation((0.2 + 0.05 * (k - 1), 0.08 + 0.03 * (k % 2), zt + 0.06)))
        M.material(fr, mats.barro)
        o.append(M.suave(fr, 60))
    if rico:
        o.append(
            bloco(
                f"{nome}_armario",
                (comp + 0.2, 0.45, 1.6),
                (0, prof / 2 + 0.3, z + 0.8),
                mats.laca,
                chanfro=0.01,
            )
        )
        o.append(
            bloco(
                f"{nome}_arm_topo",
                (comp + 0.3, 0.5, 0.08),
                (0, prof / 2 + 0.3, z + 1.64),
                mats.go_escuro,
                chanfro=0.01,
            )
        )
    if painel:
        o.append(
            bloco(
                f"{nome}_painel",
                (1.1, 0.04, 0.38),
                (0, prof / 2 + (0.5 if rico else 0.06), z + 2.05),
                mats.laca,
                chanfro=0.008,
            )
        )
    for ob in o:
        sem_fundo(ob, z)
    rec.addv(_colocar(o, pos, rot), "Mobilia", "Mobilia")
    _col_local(
        rec,
        nome,
        pos,
        rot,
        (0, 0.1 if rico else 0, z + alt / 2),
        (comp + (0.2 if rico else 0), prof + (0.5 if rico else 0), alt),
    )


def chum(nome, pos, mats: Mats, alt=0.62, r=0.28, tampa="madeira", sem=0, z=None):
    """Lu/khạp: pote de barro de guardar arroz ou água (PLACEHOLDER na forma; altura de 0,59 a
    0,75 m: anúncios de antiquário, como o water_jar). Tampa de tábua ou de palha."""
    z = PISO if z is None else z
    rr = np.random.default_rng(sem)
    k = float(rr.uniform(0.9, 1.1))
    perfil = [
        (0.0, 0.0),
        (r * 0.6, 0.0),
        (r * 0.85, alt * 0.12),
        (r, alt * 0.45),
        (r * 0.92, alt * 0.75),
        (r * 0.62, alt * 0.94),
        (r * 0.66, alt),
        (r * 0.56, alt),
        (0.0, alt * 0.97),
    ]
    perfil = [(a * k, b) for a, b in perfil]
    o = [
        torno_local(
            f"{nome}_pote", perfil, 12, mats.barro_escuro if sem % 2 else mats.barro, sem=float(sem)
        )
    ]
    if tampa == "madeira":
        o.append(
            cilindro(f"{nome}_tampa", r * 0.72 * k, 0.03, (0, 0, alt + 0.015), mats.go, segs=12)
        )
    elif tampa == "palha":
        t = torno_local(
            f"{nome}_tampa",
            [(0.0, alt + 0.1), (r * 0.8 * k, alt - 0.01), (r * 0.7 * k, alt - 0.02), (0.0, alt)],
            12,
            mats.esteira,
        )
        o.append(t)
    for ob in o:
        M.mover(ob, Matrix.Translation((pos[0], pos[1], z)))
    sem_fundo(o[0], z)
    return o


def potes(rec, nome, pts, mats: Mats, alts=(0.62, 0.55, 0.7), sem=0, dentro=True):
    for i, (x, y) in enumerate(pts):
        a = alts[i % len(alts)]
        o = chum(
            f"{nome}{i}",
            (x, y),
            mats,
            alt=a,
            r=a * 0.45,
            tampa="madeira" if i % 2 == 0 else "palha",
            sem=sem + i,
            z=PISO if dentro else 0.0,
        )
        rec.addv(o, "Mobilia" if dentro else "Casa", "Mobilia" if dentro else "Anexos")
        rec.caixa(
            f"{nome}{i}",
            (x, y, (PISO if dentro else 0.0) + a / 2),
            (a * 0.85, a * 0.85, a),
            "para",
            "Ceramic",
        )


def bo_lua(rec, nome, pos, mats: Mats, r=0.45, alt=1.0):
    """Bồ lúa: tulha de bambu trançado com arroz (PLACEHOLDER: Ø 0,9 × 1,0 m)."""
    o = [
        torno_local(
            f"{nome}_tulha",
            [
                (0.0, 0.0),
                (r * 0.9, 0.0),
                (r, alt * 0.3),
                (r, alt * 0.85),
                (r * 0.94, alt),
                (r * 0.9, alt),
                (r * 0.9, alt - 0.08),
                (0.0, alt - 0.08),
            ],
            12,
            mats.phen,
        )
    ]
    o.append(cilindro(f"{nome}_arroz", r * 0.88, 0.05, (0, 0, alt - 0.07), mats.arroz, segs=12))
    o.append(M.suave(M.material(M.toro(f"{nome}_aro", r * 0.97, 0.02, 14, 5), mats.tre), 40))
    gravar_uv_local(o[-1], lambda p: (p.x, p.y, p.z))
    M.mover(o[-1], Matrix.Translation((0, 0, alt - 0.03)))
    for ob in o:
        M.mover(ob, Matrix.Translation((pos[0], pos[1], PISO)))
    rec.addv(o, "Mobilia", "Mobilia")
    rec.caixa(nome, (pos[0], pos[1], PISO + alt / 2), (2 * r, 2 * r, alt), "passa", "Bamboo")


def ferramentas(
    rec,
    nome,
    pos,
    rot,
    mats: Mats,
    arado=False,
    itens=("enxada", "ancinho", "nia", "ganh", "foice"),
    z=None,
):
    """Ferramentas de lavoura encostadas numa parede (a parede fica no +Y local; os objetos vão
    de x = 0 a ~2,5 m): enxada (cuốc), ancinho (cào), peneira de abanar (nia), vara de carga
    (đòn gánh) com dois cestos e foice (liềm) pendurada. Com `arado`, o arado de madeira (cày)
    no chão. Medidas: PLACEHOLDER."""
    z = PISO if z is None else z
    o = []
    if "enxada" in itens:
        o.append(
            tre(
                f"{nome}_cabo_enx",
                (0.0, -0.35, z + 0.02),
                (0.0, -0.05, z + 1.25),
                0.018,
                mats.go,
                segs=6,
            )
        )
        o.append(
            bloco(
                f"{nome}_lam_enx",
                (0.17, 0.02, 0.2),
                (0.0, -0.38, z + 0.12),
                mats.ferro,
                rot=(math.radians(-60), 0, 0),
            )
        )
    if "ancinho" in itens:
        o.append(
            tre(
                f"{nome}_cabo_anc",
                (0.35, -0.32, z + 0.02),
                (0.35, -0.05, z + 1.35),
                0.016,
                mats.tre,
                segs=6,
            )
        )
        o.append(bloco(f"{nome}_trav_anc", (0.42, 0.04, 0.04), (0.35, -0.33, z + 0.06), mats.go))
        for k in range(6):
            o.append(
                bloco(
                    f"{nome}_dente{k}",
                    (0.012, 0.012, 0.09),
                    (0.35 - 0.18 + k * 0.072, -0.35, z + 0.02),
                    mats.go,
                )
            )
    if "nia" in itens:
        nia = torno_local(
            f"{nome}_nia",
            [(0.0, 0.0), (0.42, 0.0), (0.45, 0.04), (0.43, 0.045), (0.0, 0.01)],
            12,
            mats.esteira,
        )
        M.mover(
            nia,
            Matrix.Translation((0.95, -0.12, z + 0.46))
            @ Matrix.Rotation(math.radians(-78), 4, "X"),
        )
        o.append(nia)
    if "ganh" in itens:
        o.append(
            tre(
                f"{nome}_ganh",
                (1.55, -0.4, z + 0.02),
                (1.55, -0.05, z + 1.55),
                0.022,
                mats.tre,
                segs=6,
            )
        )
        for k, dx in enumerate((1.85, 2.35)):
            c = torno_local(
                f"{nome}_cesto{k}",
                [
                    (0.0, 0.0),
                    (0.14, 0.0),
                    (0.2, 0.08),
                    (0.21, 0.25),
                    (0.18, 0.25),
                    (0.17, 0.08),
                    (0.0, 0.02),
                ],
                10,
                mats.phen,
            )
            M.mover(c, Matrix.Translation((dx, -0.32, z)))
            o.append(c)
    if "foice" in itens:
        f = M.tubo(
            f"{nome}_foice",
            [
                Vector((2.0 + 0.1 * math.cos(a), -0.03, z + 1.45 + 0.1 * math.sin(a)))
                for a in np.linspace(0.3, 2.8, 7)
            ],
            0.012,
            5,
            achatar=0.25,
        )
        gravar_uv_local(f, lambda p: (p.x, p.y, p.z))
        M.material(f, mats.ferro)
        o.append(f)
        o.append(
            tre(
                f"{nome}_cabo_foice",
                (1.9, -0.03, z + 1.48),
                (1.9, -0.03, z + 1.2),
                0.014,
                mats.go,
                segs=5,
            )
        )
    if arado:
        pts = [
            Vector((x, -0.75, z + h))
            for x, h in ((-0.4, 0.06), (0.2, 0.12), (0.8, 0.35), (1.4, 0.5))
        ]
        o.append(tubo_local(f"{nome}_arado", pts, 0.04, mats.go, segs=6))
        o.append(
            bloco(
                f"{nome}_relha",
                (0.3, 0.12, 0.05),
                (-0.5, -0.75, z + 0.04),
                mats.ferro,
                chanfro=0.01,
            )
        )
        o.append(
            tre(
                f"{nome}_rabica",
                (-0.3, -0.75, z + 0.05),
                (-0.65, -0.75, z + 0.85),
                0.025,
                mats.go,
                segs=6,
            )
        )
    for ob in o:
        sem_fundo(ob, z)
    rec.addv(_colocar(o, pos, rot), "Mobilia", "Mobilia")


def rede_pendurada(
    rec,
    nome,
    pos,
    rot,
    mats: Mats,
    comp=2.2,
    queda=1.4,
    z_vara=2.0,
    boias=True,
    grupo="Mobilia",
    no="Mobilia",
):
    """Rede de pesca pendurada numa vara de bambu (em dobras), com chumbadas na barra e boias de
    madeira. Medidas: PLACEHOLDER."""
    z = PISO if grupo == "Mobilia" else 0.0
    o = [
        tre(
            f"{nome}_vara",
            (-comp / 2 - 0.25, 0, z + z_vara),
            (comp / 2 + 0.25, 0, z + z_vara),
            0.03,
            mats.tre,
            segs=6,
        )
    ]

    def f(a, b):
        x = -comp / 2 + a * comp
        dobra = 0.06 * math.sin(a * comp * 9.0) * (0.3 + b)
        y = dobra + 0.04 * math.sin(a * 3.1 + b * 2.0)
        zz = z + z_vara - 0.02 - b * queda * (1 - 0.12 * math.sin(a * math.pi))
        return (x, y, zz)

    rede = grade(f"{nome}_rede", f, 28, 6)
    M.solidificar(rede, 0.012, 0.0)
    gravar_uv_local(rede, lambda p: (p.x, p.z, p.y))
    M.material(rede, mats.luoi)
    o.append(M.suave(rede, 60))
    if boias:
        for k in range(6):
            a = (k + 0.5) / 6
            x, y, zz = f(a, 1.0)
            o.append(cilindro(f"{nome}_chumbo{k}", 0.025, 0.06, (x, y, zz), mats.ferro, segs=6))
    rec.addv(_colocar(o, pos, rot), grupo, no)


def rede_monte(
    rec,
    nome,
    pos,
    rot,
    mats: Mats,
    larg=1.1,
    prof=0.8,
    alt=0.35,
    sem=0,
    grupo="Mobilia",
    no="Mobilia",
    z=None,
):
    """Monte de rede de pesca no chão (superelipsoide amassada, com boias por cima)."""
    z = PISO if z is None else z
    m = M.superelipsoide(f"{nome}_monte", larg / 2, prof / 2, alt, 0.8, 0.7, 18, 8)
    M.deslocar(m, lambda co, n: 0.06 * M.fbm(co * 3.0, 3, sem) + 0.02 * M.ruido(co * 12.0, sem + 2))
    apagar_faces(m, lambda c, n: c.z < -0.02)
    gravar_uv_local(m, lambda p: (p.x * 1.3 + p.z, p.y * 1.3 - p.z, 0.0))
    M.mover(m, Matrix.Translation((0, 0, z)))
    M.material(m, mats.luoi)
    o = [M.suave(m, 70)]
    rr = np.random.default_rng(sem)
    for k in range(5):
        a = rr.uniform(0, 2 * math.pi)
        o.append(
            cilindro(
                f"{nome}_boia{k}",
                0.04,
                0.09,
                (math.cos(a) * larg * 0.3, math.sin(a) * prof * 0.3, z + alt * 0.8),
                mats.go,
                segs=8,
            )
        )
    rec.addv(_colocar(o, pos, rot), grupo, no)


def nom(rec, nome, pos, mats: Mats, grupo="Mobilia", no="Mobilia", z=None, deitado=False):
    """Nơm: armadilha de pesca de bambu em sino (PLACEHOLDER: Ø 0,7 × 0,8 m)."""
    z = PISO if z is None else z
    o = torno_local(
        f"{nome}",
        [
            (0.0, 0.8),
            (0.07, 0.8),
            (0.1, 0.72),
            (0.2, 0.45),
            (0.34, 0.06),
            (0.36, 0.0),
            (0.33, 0.0),
            (0.31, 0.06),
            (0.17, 0.45),
            (0.07, 0.72),
            (0.0, 0.74),
        ],
        12,
        mats.phen,
    )
    if deitado:
        M.mover(
            o,
            Matrix.Translation((pos[0], pos[1], z + 0.36))
            @ Matrix.Rotation(math.radians(80), 4, "X")
            @ Matrix.Translation((0, 0, -0.4)),
        )
    else:
        M.mover(o, Matrix.Translation((pos[0], pos[1], z)))
    rec.add(o, grupo, no)


def bep(rec, nome, pos, rot, mats: Mats, grupo="Mobilia", no="Mobilia", z=None):
    """Bếp: fogão de barro (ông đầu rau: três pedras de barro em triângulo) sobre estrado de terra,
    panela de barro, cinza e lenha. Medidas: PLACEHOLDER."""
    z = PISO if z is None else z
    o = []
    est = bloco(
        f"{nome}_estrado", (1.0, 0.75, 0.12), (0, 0, z + 0.06), mats.dat, chanfro=0.04, segs=2
    )
    sem_fundo(est, z)
    o.append(est)
    o.append(cilindro(f"{nome}_cinza", 0.22, 0.012, (0.05, 0, z + 0.126), mats.cinza, segs=12))
    for k in range(3):
        a = math.radians(90 + 120 * k)
        p = Vector((0.05 + math.cos(a) * 0.15, math.sin(a) * 0.15, z + 0.12))
        d = torno_local(
            f"{nome}_dau{k}",
            [(0.0, 0.0), (0.08, 0.0), (0.075, 0.08), (0.05, 0.19), (0.0, 0.21)],
            10,
            mats.barro_escuro,
        )
        M.mover(
            d,
            Matrix.Translation(p)
            @ Matrix.Rotation(math.radians(12), 4, Vector((-math.sin(a), math.cos(a), 0))),
        )
        o.append(d)
    panela = torno_local(
        f"{nome}_panela",
        [
            (0.0, 0.0),
            (0.1, 0.0),
            (0.17, 0.06),
            (0.18, 0.12),
            (0.14, 0.17),
            (0.15, 0.19),
            (0.0, 0.19),
        ],
        14,
        mats.barro_escuro,
    )
    M.mover(panela, Matrix.Translation((0.05, 0, z + 0.3)))
    o.append(panela)
    for k in range(4):
        a = math.radians(-30 + 20 * k)
        o.append(
            tre(
                f"{nome}_lenha{k}",
                (0.55 + 0.05 * k, -0.25 + 0.15 * k, z + 0.03),
                (0.15 + 0.07 * k, -0.05 + 0.06 * k, z + 0.13),
                0.025 + 0.004 * k,
                mats.go,
                segs=5,
            )
        )
    for k in range(5):
        o.append(
            tre(
                f"{nome}_pilha{k}",
                (0.65, -0.55 + 0.06 * k, z + 0.03 + 0.045 * (k % 2)),
                (1.35, -0.5 + 0.05 * k, z + 0.03 + 0.045 * (k % 2)),
                0.03,
                mats.go,
                segs=5,
            )
        )
    rec.addv(_colocar(o, pos, rot), grupo, no)
    _col_local(rec, nome, pos, rot, (0, 0, z + 0.2), (1.0, 0.75, 0.4), "para", "Ground")


def thung_chai(rec, nome, pos, rot, mats: Mats, diam=1.9, encostado=True):
    """Thúng chai: barco-cesto redondo de bambu calafetado (PLACEHOLDER: Ø 1,9 m, 0,55 m de
    fundo), em pé encostado na parede."""
    r = diam / 2
    perfil = [
        (0.0, 0.0),
        (r * 0.55, 0.02),
        (r * 0.85, 0.12),
        (r * 0.98, 0.32),
        (r, 0.5),
        (r * 1.03, 0.55),
        (r * 0.99, 0.56),
        (r * 0.95, 0.5),
        (r * 0.94, 0.33),
        (r * 0.82, 0.15),
        (r * 0.53, 0.06),
        (0.0, 0.04),
    ]
    b = torno_local(f"{nome}_casco", perfil, 16, mats.resina)
    aro = M.toro(f"{nome}_aro", r * 1.02, 0.035, 16, 5)
    gravar_uv_local(aro, lambda p: (p.x, p.y, p.z))
    M.material(aro, mats.tre)
    M.mover(aro, Matrix.Translation((0, 0, 0.55)))
    o = [b, M.suave(aro, 40)]
    if encostado:
        m = (
            Matrix.Translation((0, 0, r + 0.02))
            @ Matrix.Rotation(math.radians(-75), 4, "X")
            @ Matrix.Translation((0, 0, -0.28))
        )
        for ob in o:
            M.mover(ob, m)
    rec.addv(_colocar(o, pos, rot), "Casa", "Anexos")
    _col_local(rec, nome, pos, rot, (0, 0.1, r), (diam, 0.6, diam), "passa", "Bamboo")


def ham_chu_a(
    rec,
    nome,
    pos,
    rot,
    mats: Mats,
    comp=1.5,
    larg=1.0,
    alt_monte=1.0,
    grupo="Casa",
    no="Anexos",
    z=0.0,
):
    """Hầm chữ A: abrigo antiaéreo da família, armação de bambu em A coberta de terra. A cova (1 a
    1,2 m de fundo, 1 m de largura, 1,5 m de comprimento: Báo Văn hóa, hầm chữ A) não foi
    modelada (precisa cavar o terreno); o monte de terra e a boca em A ficam acima do chão.
    A boca fica em -Y (gire com `rot`)."""
    o = []
    a, b = comp / 2 + 0.55, larg / 2 + 0.6
    h = 0.85
    w = 0.5
    yb = 0.15 - b - 0.1  # a boca em A fica um pouco à frente do pé do monte
    m = M.superelipsoide(f"{nome}_monte", a, b, alt_monte, 0.7, 0.8, 28, 14)
    M.deslocar(m, lambda co, n: 0.05 * M.fbm(co * 2.5, 3, 5) + 0.015 * M.ruido(co * 9.0, 6))
    apagar_faces(m, lambda c, n: c.z < -0.03)
    M.mover(m, Matrix.Translation((0, 0.15, z)))

    def no_tunel(c, n):
        t = (c.y - yb) / 0.9
        if t < -0.05 or t > 1.0:
            return False
        hh = h * (1 - 0.2 * t)
        ww = w * (1 - 0.2 * t)
        return c.z - z < hh * 0.98 and abs(c.x) < ww * (1 - (c.z - z) / hh) + 0.02

    apagar_faces(m, no_tunel)
    M.material(m, mats.dat)
    o.append(M.suave(m, 70))
    # boca: túnel curto escuro (faces para dentro) e as varas em A
    bm = bmesh.new()
    fr = [bm.verts.new((-w, yb, z)), bm.verts.new((w, yb, z)), bm.verts.new((0, yb, z + h))]
    fd = [
        bm.verts.new((-w * 0.8, yb + 0.9, z)),
        bm.verts.new((w * 0.8, yb + 0.9, z)),
        bm.verts.new((0, yb + 0.9, z + h * 0.8)),
    ]
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((fr[i], fd[i], fd[j], fr[j]))
    bm.faces.new((fd[2], fd[1], fd[0]))
    tun = M.de_bmesh(f"{nome}_tunel", bm)
    gravar_uv_local(tun, lambda p: (p.x, p.y, p.z))
    M.material(tun, mats.cinza)
    # faces viradas para dentro do túnel (quem olha pela boca vê as paredes)
    bm = bmesh.new()
    bm.from_mesh(tun.data)
    bm.normal_update()
    centro = Vector((0, yb + 0.45, z + h * 0.35))
    for f in bm.faces:
        if f.normal.dot(centro - f.calc_center_median()) < 0:
            f.normal_flip()
    bm.to_mesh(tun.data)
    bm.free()
    o.append(tun)
    for sx in (-1, 1):
        o.append(
            tre(
                f"{nome}_vara{sx}",
                (sx * (w + 0.05), yb - 0.05, z),
                (0, yb - 0.05, z + h + 0.12),
                0.035,
                mats.tre,
                segs=6,
            )
        )
        o.append(
            tre(
                f"{nome}_varab{sx}",
                (sx * (w * 0.8 + 0.05), yb + 0.9, z),
                (0, yb + 0.9, z + h * 0.8 + 0.1),
                0.03,
                mats.tre,
                segs=6,
            )
        )
    o.append(
        tre(
            f"{nome}_trav",
            (-w * 0.6, yb - 0.06, z + h * 0.42),
            (w * 0.6, yb - 0.06, z + h * 0.42),
            0.025,
            mats.tre,
            segs=5,
        )
    )
    for k in range(4):
        o.append(
            tre(
                f"{nome}_cobre{k}",
                (-0.3 + 0.2 * k, yb - 0.1, z + h + 0.02),
                (-0.3 + 0.2 * k, yb + 0.95, z + h * 0.82 + 0.05),
                0.025,
                mats.tre,
                segs=5,
            )
        )
    rec.addv(_colocar(o, pos, rot), grupo, no)
    r = Matrix.Rotation(math.radians(rot), 3, "Z")
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for zz in (z, z + alt_monte * 0.75):
                k = 1.0 if zz == z else 0.55
                pts.append(
                    tuple(
                        Vector((pos[0], pos[1], 0.0))
                        + r @ Vector((sx * a * k, 0.15 + sy * b * k, zz))
                    )
                )
    rec.prisma(nome, pts, "para", "Ground")
    return o


def cerca(rec, nome, pts, mats: Mats, alt=1.1, portao=None):
    """Cerca de bambu: postes a cada ~1,8 m, duas travessas e painel trançado (phên). `portao`
    = índice do trecho que fica aberto (passagem). Colisão: caixa fina (a bala passa)."""
    for k, (p0, p1) in enumerate(zip(pts[:-1], pts[1:], strict=True)):
        a, b = Vector((*p0, 0.0)), Vector((*p1, 0.0))
        comp = (b - a).length
        if portao is not None and k == portao:
            for q in (a, b):
                rec.add(
                    tre(
                        f"{nome}_portal{k}{q.x:.1f}",
                        q,
                        q + Vector((0, 0, alt + 0.35)),
                        0.05,
                        mats.tre,
                        segs=7,
                    ),
                    "Casa",
                    "Anexos",
                )
            continue
        ang = math.atan2(b.y - a.y, b.x - a.x)
        lado = Lado((a.x, a.y), ang, comp, 0.03)
        pan = peca(
            f"{nome}_painel{k}",
            lado.o,
            ang,
            0.05,
            comp - 0.05,
            0.08,
            alt,
            -0.015,
            0.015,
            mats.phen,
            sem=k,
        )
        rec.add(pan, "Casa", "Anexos")
        n = max(1, int(comp / 1.8))
        for i in range(n + 1):
            q = a.lerp(b, i / n)
            rec.add(
                tre(
                    f"{nome}_poste{k}_{i}",
                    q - Vector((0, 0, 0.0)),
                    q + Vector((0, 0, alt + 0.12)),
                    0.035,
                    mats.tre,
                    segs=6,
                    sem=i * 0.3,
                ),
                "Casa",
                "Anexos",
            )
        for zz in (0.35, alt - 0.1):
            p, q = lado.ponto(0, 0.03, zz), lado.ponto(comp, 0.03, zz)
            rec.add(tre(f"{nome}_trav{k}_{zz}", p, q, 0.022, mats.tre, segs=5), "Casa", "Anexos")
        c = lado.ponto(comp / 2)
        rec.caixa(
            f"{nome}{k}", (c.x, c.y, alt / 2), (comp, 0.08, alt), "passa", "Bamboo", rot_z=ang
        )


def jarro_agua(rec, nome, pos, mats: Mats, grupo="Casa", no="Anexos", z=0.0):
    """Chum nước na porta: pote d'água (0,7 m, como o water_jar) com tampa e cuia de coco."""
    o = chum(nome, pos, mats, alt=0.7, r=0.3, tampa="madeira", sem=3, z=z)
    cuia = torno_local(
        f"{nome}_cuia",
        [(0.0, 0.066), (0.03, 0.062), (0.052, 0.046), (0.064, 0.022), (0.066, 0.0), (0.0, 0.0)],
        10,
        mats.go_escuro,
    )
    M.mover(cuia, Matrix.Translation((pos[0] - 0.06, pos[1], z + 0.73)))
    o.append(cuia)
    o.append(
        tre(
            f"{nome}_cabo",
            (pos[0] - 0.1, pos[1], z + 0.75),
            (pos[0] - 0.42, pos[1] + 0.05, z + 0.76),
            0.009,
            mats.tre,
            segs=5,
        )
    )
    rec.addv(o, grupo, no)
    rec.caixa(nome, (pos[0], pos[1], z + 0.35), (0.6, 0.6, 0.7), "para", "Ceramic")


def nonla_pendurado(rec, nome, pos, rot, mats: Mats, z=1.6):
    """Nón lá (Ø 0,40 × 0,19 m: medidas do conical_hat) pendurado na parede."""
    h = M.torno(f"{nome}", [(0.0, 0.19), (0.2, 0.0), (0.198, -0.004), (0.0, 0.183)], segs=18)
    M.material(h, mats.nonla)
    M.mover(
        h, Matrix.Translation((0, -0.05, PISO + z)) @ Matrix.Rotation(math.radians(-80), 4, "X")
    )
    rec.addv(_colocar([M.suave(h, 50)], pos, rot), "Mobilia", "Mobilia")


def sacos(rec, nome, pts, mats: Mats, z=None):
    """Sacos de arroz de juta (0,45 × 0,34 × 0,25 m: rice_sack, PLACEHOLDER)."""
    z = PISO if z is None else z
    for k, (x, y, rz) in enumerate(pts):
        s = M.superelipsoide(f"{nome}{k}", 0.24, 0.17, 0.13, 0.35, 0.4, 16, 8)
        M.deslocar(s, lambda co, n, k=k: 0.012 * M.fbm(co * 8.0, 2, k))
        gravar_uv_local(s, lambda p: (p.x, p.y, p.z), float(k))
        M.mover(s, Matrix.Translation((x, y, z + 0.12)) @ Matrix.Rotation(math.radians(rz), 4, "Z"))
        M.material(s, mats.juta)
        rec.add(M.suave(s, 70), "Mobilia", "Mobilia")


def ruong(rec, nome, pos, rot, mats: Mats):
    """Rương: arca de madeira com ferragens (PLACEHOLDER: 0,9 × 0,5 × 0,5 m)."""
    z = PISO
    o = [
        bloco(f"{nome}_caixa", (0.9, 0.5, 0.45), (0, 0, z + 0.25), mats.go_escuro, chanfro=0.01),
        bloco(f"{nome}_tampa", (0.94, 0.54, 0.06), (0, 0, z + 0.5), mats.go_escuro, chanfro=0.012),
    ]
    for sx in (-1, 1):
        o.append(bloco(f"{nome}_pe{sx}", (0.1, 0.5, 0.05), (sx * 0.35, 0, z + 0.025), mats.go))
        o.append(
            bloco(f"{nome}_cinta{sx}", (0.04, 0.545, 0.47), (sx * 0.3, 0, z + 0.26), mats.ferro)
        )
    for ob in o:
        sem_fundo(ob, z)
    rec.addv(_colocar(o, pos, rot), "Mobilia", "Mobilia")
    _col_local(rec, nome, pos, rot, (0, 0, z + 0.27), (0.94, 0.54, 0.53))


def cadeiras_mesa(rec, nome, pos, rot, mats: Mats):
    """Mesa de chá alta com duas cadeiras de madeira (casa de quem tinha mais; PLACEHOLDER)."""
    z = PISO
    o = [bloco(f"{nome}_tampo", (1.0, 0.65, 0.04), (0, 0, z + 0.76), mats.go_escuro, chanfro=0.008)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                bloco(
                    f"{nome}_pe{sx}{sy}",
                    (0.055, 0.055, 0.74),
                    (sx * 0.44, sy * 0.27, z + 0.37),
                    mats.go_escuro,
                )
            )
    o.append(bloco(f"{nome}_trav", (0.85, 0.04, 0.05), (0, 0, z + 0.15), mats.go_escuro))
    for k, sx in enumerate((-1, 1)):
        cx = sx * 0.85
        o.append(
            bloco(
                f"{nome}_assento{k}",
                (0.45, 0.45, 0.04),
                (cx, 0, z + 0.46),
                mats.go_escuro,
                chanfro=0.006,
            )
        )
        for px in (-1, 1):
            for py in (-1, 1):
                hh = 0.44 if px != sx else 0.95
                o.append(
                    bloco(
                        f"{nome}_cpe{k}{px}{py}",
                        (0.04, 0.04, hh),
                        (cx + px * 0.19, py * 0.19, z + hh / 2),
                        mats.go_escuro,
                    )
                )
        o.append(
            bloco(
                f"{nome}_encosto{k}",
                (0.03, 0.4, 0.3),
                (cx + sx * 0.19, 0, z + 0.78),
                mats.go_escuro,
            )
        )
    for ob in o:
        sem_fundo(ob, z)
    rec.addv(_colocar(o, pos, rot), "Mobilia", "Mobilia")
    _col_local(rec, nome, pos, rot, (0, 0, z + 0.4), (2.1, 0.65, 0.8))


def chuong_heo(rec, nome, pos, rot, mats: Mats, mat_tel, larg=2.2, prof=1.8):
    """Chuồng heo: chiqueiro baixo de bambu com cobertura de palha de uma água e cocho de tronco
    (PLACEHOLDER: 2,2 × 1,8 m)."""
    marca = rec.marca()
    for sx in (-1, 1):
        for sy in (-1, 1):
            hh = 1.5 if sy > 0 else 1.1
            rec.add(
                tre(
                    f"{nome}_poste{sx}{sy}",
                    (sx * larg / 2, sy * prof / 2, 0),
                    (sx * larg / 2, sy * prof / 2, hh),
                    0.045,
                    mats.tre,
                    segs=6,
                ),
                "Casa",
                "Anexos",
            )
    for k, zz in enumerate((0.25, 0.5, 0.75)):
        for x0, y0, x1, y1 in ((-1, -1, 1, -1), (1, -1, 1, 1), (-1, -1, -1, 1)):
            rec.add(
                tre(
                    f"{nome}_ripa{k}{x0}{y0}{x1}",
                    (x0 * larg / 2, y0 * prof / 2, zz),
                    (x1 * larg / 2, y1 * prof / 2, zz),
                    0.025,
                    mats.tre,
                    segs=5,
                    sem=k,
                ),
                "Casa",
                "Anexos",
            )
    agua_unica(
        rec,
        f"{nome}_tel",
        -larg / 2 - 0.25,
        larg / 2 + 0.25,
        prof / 2 + 0.2,
        1.58,
        -prof / 2 - 0.3,
        1.08,
        0.16,
        "tranh",
        mat_tel,
        mats,
        sem=31,
    )
    cocho = bloco(f"{nome}_cocho", (1.0, 0.3, 0.2), (0.2, -0.3, 0.1), mats.go_escuro, chanfro=0.03)
    sem_fundo(cocho, 0.0)
    rec.add(cocho, "Casa", "Anexos")
    rec.transformar(marca, lugar((pos[0], pos[1], 0.0), rot))
    _col_local(rec, nome, pos, rot, (0, 0, 0.5), (larg, prof, 1.0), "passa", "Bamboo")


def varal_redes(rec, nome, pos, rot, mats: Mats, comp=3.2):
    """Giá phơi lưới: dois cavaletes em X de bambu e a vara com a rede secando (PLACEHOLDER)."""
    marca = rec.marca()
    for sx in (-1, 1):
        x = sx * comp / 2
        for sy in (-1, 1):
            rec.add(
                tre(
                    f"{nome}_cav{sx}{sy}",
                    (x, sy * 0.5, 0),
                    (x, -sy * 0.12, 2.0),
                    0.035,
                    mats.tre,
                    segs=6,
                ),
                "Casa",
                "Anexos",
            )
    rede_pendurada(
        rec,
        f"{nome}_rede",
        (0, 0),
        0,
        mats,
        comp=comp - 0.4,
        queda=1.25,
        z_vara=1.85,
        grupo="Casa",
        no="Anexos",
    )
    rec.transformar(marca, lugar((pos[0], pos[1], 0.0), rot))
