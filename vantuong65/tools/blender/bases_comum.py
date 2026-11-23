"""Peças, materiais e colisão das bases iniciais (Tarefa C: base dos EUA em Chu Lai e do VC).

Roda dentro do Python do Blender. Tudo em METROS, Z para cima (como `comum.py` e `modelar.py`).
Convenção dos assets das bases:
- a FRENTE (porta, entrada, lado que olha a estrada) fica em -Y no Blender. No GLB isso é +Z; o
  importador do Roblox gira o modelo 180° em Y (D-58), então no jogo a frente fica em -Z (o
  LookVector do modelo). Conferir no Studio, como manda a D-58;
- cada objeto da receita tem `grupo` (um atlas de textura por grupo) e `no` (um nó do GLB, que vira
  uma MeshPart no Roblox). Vários nós podem dividir o mesmo atlas;
- a colisão é feita de sólidos convexos simples (`Receita.caixa`, `Receita.prisma`), exportados como
  nós `Colisao_<nome>` (o código os deixa invisíveis) e listados no metricas.json. Zonas de toque
  (estacas punji) saem como `Zona_<nome>`.
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
import comum as C  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
from modelar import Mat, rgb  # noqa: E402

FONTE_SIMBOLO = Path("C:/Windows/Fonts/seguisym.ttf")
FONTE_PLACA = Path("C:/Windows/Fonts/bahnschrift.ttf")
FONTE_NEGRITO = Path("C:/Windows/Fonts/arialbd.ttf")
FONTE_ESTENCIL = M.FONTE_ESTENCIL
periodo = N.periodo
suave_passo = N.suave_passo


def usar_cuda(cena) -> str:
    """Cycles na GPU por CUDA. Com o driver atual o OptiX aparece na lista de dispositivos mas
    falha ao iniciar ("driver too old") e o Cycles cai para a CPU sem avisar (`comum.usar_gpu`
    escolhe o OptiX primeiro)."""
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "CUDA"
    except TypeError:
        cena.cycles.device = "CPU"
        return "CPU"
    prefs.get_devices()
    if not any(d.type == "CUDA" for d in prefs.devices):
        cena.cycles.device = "CPU"
        return "CPU"
    for d in prefs.devices:
        d.use = d.type == "CUDA"
    cena.cycles.device = "GPU"
    return "CUDA"


# =============================================================== receita
class Receita:
    """Objetos altos (com grupo e nó), colisão e dados extras (pivôs, saídas de fumaça)."""

    def __init__(self) -> None:
        self.objs: list[bpy.types.Object] = []
        self.baixos: list[bpy.types.Object] = []
        self.colisao: list[dict] = []
        self.extras: dict = {}

    def add(self, obj, grupo: str = "Principal", no: str | None = None):
        obj["grupo"] = grupo
        obj["no"] = no or grupo
        self.objs.append(obj)
        return obj

    def addv(self, objs, grupo: str = "Principal", no: str | None = None):
        for o in objs:
            self.add(o, grupo, no)
        return objs

    # Malha baixa feita à mão. A redução automática destrói peça fina (lona e chapa de 1 cm: as
    # duas faces se cruzam e sobram furos e faces viradas) e monte de centenas de sacos (cacos):
    # para essas, a receita dá a malha baixa e marca as altas como `substituido` (elas só entram
    # no bake, que passa o detalhe para o mapa de normais).
    def baixo(self, obj, grupo: str = "Principal", no: str | None = None):
        obj["grupo"] = grupo
        obj["no"] = no or grupo
        self.baixos.append(obj)
        return obj

    def substituir(self, objs):
        for o in objs:
            o["substituido"] = True
        return objs

    def fixo(self, obj, grupo: str = "Principal", no: str | None = None):
        """A própria peça é a malha baixa (sem redução): chapa ondulada, pano fino."""
        self.add(obj, grupo, no)
        obj["substituido"] = True
        copia = C.copiar(obj, obj.name + "_baixo")
        self.baixo(copia, grupo, no)
        return obj

    def baixo_caixas(self, caixas, grupo: str, no: str | None = None, chanfro=0.04):
        """Malha baixa de caixas [(lo, hi)] (paredes de sacos): chanfro leve, uma divisão."""
        for lo, hi in caixas:
            dim = [b - a for a, b in zip(lo, hi, strict=True)]
            centro = [(a + b) / 2 for a, b in zip(lo, hi, strict=True)]
            o = M.caixa("baixo_caixa", dim, centro, cortes=1)
            M.chanfrar(o, min(chanfro, min(dim) * 0.3), 1)
            self.baixo(o, grupo, no)

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
        """Caixa de colisão (centro e dimensões em m); `rot_z` gira em volta de Z (rad)."""
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

    def caixa_lim(self, nome, lo, hi, bala="para", material="Wood", obs=""):
        centro = [(a + b) / 2 for a, b in zip(lo, hi, strict=True)]
        dim = [b - a for a, b in zip(lo, hi, strict=True)]
        self.caixa(nome, centro, dim, bala, material, obs)

    def prisma(self, nome, pontos, bala="para", material="Earth", obs=""):
        """Sólido convexo (o fecho convexo dos pontos)."""
        self._col("prisma", nome, pontos, bala, material, obs)

    def zona(self, nome, lo, hi, obs=""):
        """Zona de toque sem colisão (ex.: estacas punji)."""
        pts = [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
        self._col("zona", nome, pts, "passa", "", obs)


# =============================================================== geometria
def bloco(nome, dim, centro=(0, 0, 0), mat=None, chanfro=0.0, segs=1, rot=None, cortes=0):
    """Caixa com chanfro opcional, girada (Euler XYZ, rad) e movida para `centro`."""
    o = M.caixa(nome, dim, (0, 0, 0), cortes=cortes)
    if chanfro > 0:
        M.chanfrar(o, chanfro, segs)
    m = Matrix.Translation(Vector(centro))
    if rot is not None:
        m = m @ Euler(rot, "XYZ").to_matrix().to_4x4()
    M.mover(o, m)
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 35)


def base_eixo(p0, p1, cima=(0, 0, 1)) -> Matrix:
    """Matriz que leva o eixo Z local para a direção p0->p1 (Y local o mais perto de `cima`)."""
    a, b = Vector(p0), Vector(p1)
    z = (b - a).normalized()
    up = Vector(cima)
    if abs(z.dot(up)) > 0.98:
        up = Vector((1, 0, 0)) if abs(z.x) < 0.9 else Vector((0, 1, 0))
    x = up.cross(z).normalized()
    y = z.cross(x).normalized()
    r = Matrix((x, y, z)).transposed().to_4x4()
    return Matrix.Translation(a) @ r


def viga(nome, p0, p1, larg, alt, mat=None, chanfro=0.003, cima=(0, 0, 1), cortes=0):
    """Viga retangular de p0 a p1 (largura no X local, altura no Y local ~ para cima)."""
    comp = (Vector(p1) - Vector(p0)).length
    o = M.caixa(nome, (larg, alt, comp), (0, 0, comp / 2), cortes=cortes)
    if chanfro > 0:
        M.chanfrar(o, chanfro, 1)
    M.mover(o, base_eixo(p0, p1, cima))
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 35)


def vara(nome, p0, p1, r0, r1=None, mat=None, segs=10, n=2, tampar=True):
    """Pau roliço de p0 a p1 (raio r0 -> r1)."""
    a, b = Vector(p0), Vector(p1)
    pts = [a.lerp(b, float(t)) for t in np.linspace(0.0, 1.0, n)]
    raios = [float(x) for x in np.linspace(r0, r1 if r1 is not None else r0, n)]
    o = M.tubo(nome, pts, raios, segs, tampar=tampar)
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 50)


def bambu(nome, p0, p1, r0, r1=None, mat=None, sem=0, entre_nos=0.35, segs=10):
    o = M.bambu(nome, p0, p1, r0, r1 if r1 is not None else r0 * 0.85, entre_nos, segs, sem)
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 50)


def corda(nome, p0, p1, flecha=0.0, r=0.006, mat=None, n=8, segs=5):
    """Corda de p0 a p1 com barriga (`flecha` m no meio)."""
    a, b = Vector(p0), Vector(p1)
    pts = []
    for t in np.linspace(0.0, 1.0, n):
        t = float(t)
        pts.append(a.lerp(b, t) - Vector((0, 0, flecha * 4 * t * (1 - t))))
    o = M.tubo(nome, pts, r, segs)
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 60)


def grade(nome, f, nu, nv, fora=None):
    """Superfície paramétrica: f(u, v) -> (x, y, z), u e v em [0, 1]. Com `fora` (vetor), as faces
    são viradas para que a normal média aponte para esse lado."""
    bm = bmesh.new()
    vs = [[bm.verts.new(Vector(f(i / nu, j / nv))) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            q = (vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1])
            if len({id(v) for v in q}) < 4:
                continue
            bm.faces.new(q)
    bm.normal_update()
    if fora is not None and bm.faces:
        media = sum((fc.normal * fc.calc_area() for fc in bm.faces), Vector((0, 0, 0)))
        if media.dot(Vector(fora)) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    return M.de_bmesh(nome, bm)


def apagar_faces(obj, cond) -> int:
    """Apaga as faces cujo centro satisfaz `cond(Vector)`."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    fora = [f for f in bm.faces if cond(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=fora, context="FACES")
    soltos = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=soltos, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(fora)


def fundir(obj, dist=0.002):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def cilindro(nome, r, h, centro=(0, 0, 0), mat=None, segs=24, eixo="Z"):
    o = M.torno(nome, [(0.0, 0.0), (r, 0.0), (r, h), (0.0, h)], segs=segs, eixo=eixo)
    if eixo == "Z":
        M.mover(o, Matrix.Translation(Vector(centro) - Vector((0, 0, h / 2))))
    elif eixo == "X":
        M.mover(o, Matrix.Translation(Vector(centro) - Vector((h / 2, 0, 0))))
    else:
        M.mover(o, Matrix.Translation(Vector(centro) - Vector((0, h / 2, 0))))
    if mat is not None:
        M.material(o, mat)
    return M.suave(o, 40)


def girar_z(objs, ang, centro=(0, 0, 0)):
    c = Vector(centro)
    m = Matrix.Translation(c) @ Matrix.Rotation(ang, 4, "Z") @ Matrix.Translation(-c)
    for o in objs:
        M.mover(o, m)
    return objs


def mover_todos(objs, desl):
    m = Matrix.Translation(Vector(desl))
    for o in objs:
        M.mover(o, m)
    return objs


def gravar_uv_local(obj, f) -> None:
    """Grava o atributo `local` = f(co) -> (u, v, w) (coordenada da peça para o material)."""
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
        "value", np.zeros(len(me.vertices), np.float32)
    )


# ---------------------------------------------------------------- telhado de palha
def palha_placa(
    nome,
    origem,
    eixo_u,
    eixo_v,
    Lu,
    Lv,
    esp=0.12,
    res=0.06,
    sem=0,
    curso=0.22,
    franja=0.07,
    mat=None,
):
    """Placa de palha (folha de palmeira/capim) num retângulo inclinado: `origem` no beiral,
    `eixo_u` ao longo do beiral (Lu) e `eixo_v` subindo a água (Lv). Camadas a cada `curso` m
    (cada uma cobre a de baixo), fibras ao longo da água, beiral desfiado (`franja`). Grava
    `local` = (u, v, 0)."""
    o0, u, v = Vector(origem), Vector(eixo_u).normalized(), Vector(eixo_v).normalized()
    nrm = u.cross(v).normalized()
    if nrm.z < 0:
        nrm = -nrm
    nu, nv = max(2, round(Lu / res)), max(2, round(Lv / res))

    def f(a, b):
        return o0 + u * (a * Lu) + v * (b * Lv)

    obj = grade(nome, f, nu, nv, fora=nrm)
    M.solidificar(obj, esp, -1.0)
    rng = np.random.default_rng(sem)
    fase = rng.uniform(0, 100)

    def forma(co, n):
        rel = co - o0
        a, b = rel.dot(u), rel.dot(v)
        q = Vector((a * 1.3, b * 0.6, fase))
        cima = n.dot(nrm) > 0.3
        d = 0.0
        if cima:
            camada = ((b / curso + 0.25 * M.ruido(q * 2.0, sem)) % 1.0) * 0.05
            fibra = 0.016 * M.ruido(Vector((a * 45, b * 2.5, fase)), sem + 1)
            fibra += 0.008 * M.ruido(Vector((a * 120, b * 6, fase)), sem + 5)
            tufo = 0.03 * M.fbm(q * 1.5, 3, sem + 2)
            d = camada + fibra + tufo
        else:
            d = 0.012 * M.fbm(q * 2.0, 2, sem + 3) + 0.006 * M.ruido(
                Vector((a * 40, b * 3, fase)), sem
            )
        desl = nrm * d
        # beiral desfiado (pontas das folhas penduradas) e laterais/cumeeira irregulares
        borda = max(0.0, 1.0 - b / 0.15)
        if borda > 0:
            fio = franja * (
                0.35 + 0.65 * (0.5 + 0.5 * M.ruido(Vector((a * 22, fase, 0.0)), sem + 4))
            )
            desl += -v * fio * borda - nrm * 0.035 * borda
        lado = max(0.0, 1.0 - min(a, Lu - a) / 0.12)
        if lado > 0:
            desl += (
                u * (0.05 * M.ruido(Vector((b * 9, fase, 1.0)), sem + 6) * lado) - nrm * 0.02 * lado
            )
        topo = max(0.0, 1.0 - (Lv - b) / 0.1)
        if topo > 0:
            desl += v * (0.04 * M.ruido(Vector((a * 9, fase, 2.0)), sem + 7) * topo)
        return desl

    M.deslocar(obj, forma)
    gravar_uv_local(obj, lambda p: ((p - o0).dot(u), (p - o0).dot(v), 0.0))
    if mat is not None:
        M.material(obj, mat)
    return M.suave(obj, 70)


# ---------------------------------------------------------------- chapa ondulada
def chapa_ondulada(
    nome,
    origem,
    eixo_u,
    eixo_v,
    Lu,
    Lv,
    passo=0.068,
    prof=0.013,
    esp=0.0015,
    mat=None,
    nv=1,
    sem=0,
    comp_v=None,
):
    """Chapa de aço ondulada: retângulo com origem num canto, ondas atravessando `eixo_u` (Lu) e
    correndo ao longo de `eixo_v` (Lv). Zigue-zague de 2 pontos por onda (com sombreamento suave
    lê como senoide), espessura `esp` (as duas faces aparecem). `comp_v(a)` (a em [0, 1] ao longo
    de u) troca Lv por um comprimento variável (oitão triangular)."""
    o0, u, v = Vector(origem), Vector(eixo_u).normalized(), Vector(eixo_v).normalized()
    nrm = u.cross(v).normalized()
    if nrm.z < -0.01 or (abs(nrm.z) <= 0.01 and nrm.dot(Vector((0, -1, 0))) < 0):
        nrm = -nrm
    nu = max(2, round(Lu / passo * 2))
    rng = np.random.default_rng(sem)
    torto = rng.uniform(-0.004, 0.004)

    def f(a, b):
        i = round(a * nu)
        h = prof / 2 * (1 if i % 2 else -1)
        lv = comp_v(a) if comp_v is not None else Lv
        return o0 + u * (a * Lu) + v * (b * lv) + nrm * (h + torto * math.sin(b * math.pi))

    obj = grade(nome, f, nu, nv, fora=nrm)
    M.solidificar(obj, esp, 0.0)
    if mat is not None:
        M.material(obj, mat)
    return M.suave(obj, 60)


# ---------------------------------------------------------------- sacos de areia
SACO = {"L": 0.50, "W": 0.28, "H": 0.17, "passo_z": 0.115, "pe": 0.045}


def sacos_linha(p0, p1, z0, fiadas, fileiras=1, sem=0, pular=None, seg=(16, 8), recuo=0.0):
    """Sacos de areia deitados de comprido ao longo de p0->p1 (no plano), em amarração (fiadas
    alternadas deslocadas meio saco). `fileiras` lado a lado formam a espessura; `pular(s0, s1, z,
    r)` (trecho do saco ao longo da linha, altura do centro, fileira) devolve True para tirar o saco
    (porta, seteira); `recuo` m por fiada inclina a face (talude).
    Saco cheio de 0,50 x 0,28 x ~0,12 m (o mesmo da `sandbag_wall`: PLACEHOLDER)."""
    a = Vector((p0[0], p0[1], 0.0))
    b = Vector((p1[0], p1[1], 0.0))
    d = b - a
    comp = d.length
    ux = d.normalized()
    uy = Vector((-ux.y, ux.x, 0.0))
    ang = math.atan2(ux.y, ux.x)
    L, W, H = SACO["L"], SACO["W"], SACO["H"]
    rng = np.random.default_rng(sem)
    objs = []
    for k in range(fiadas):
        z = z0 + SACO["pe"] + SACO["passo_z"] * k
        desl = L / 2 if k % 2 else 0.0
        pos = []
        s = desl + L / 2
        if desl > 0:
            pos.append((L / 4, L / 2))  # meio saco na ponta
        while s + L / 2 <= comp + 0.02:
            pos.append((s, L))
            s += L
        # o que sobra na outra ponta vira um saco mais curto (sem buraco na ponta da parede)
        resto = comp - (s - L / 2)
        if resto > 0.12:
            pos.append((comp - resto / 2, min(L, resto)))
        for r in range(fileiras):
            off = (r - (fileiras - 1) / 2) * W - recuo * k
            for s, comp_saco in pos:
                if pular is not None and pular(s - comp_saco / 2, s + comp_saco / 2, z, r):
                    continue
                semente = int(rng.integers(0, 10**6))
                saco = N.saco(
                    "saco",
                    comp_saco - 0.012,
                    W - 0.006,
                    H,
                    semente,
                    pescoco=0.03 if (comp_saco == L and rng.random() < 0.5) else 0.0,
                    seg=seg,
                    caroco=0.003,
                    rugas=0.8,
                )
                vira = math.pi if rng.random() < 0.5 else 0.0
                m = M.matriz(
                    a
                    + ux * (s + rng.uniform(-0.012, 0.012))
                    + uy * (off + rng.uniform(-0.01, 0.01))
                    + Vector((0, 0, z)),
                    (
                        rng.uniform(-0.025, 0.025),
                        rng.uniform(-0.025, 0.025),
                        ang + vira + rng.uniform(-0.04, 0.04),
                    ),
                )
                objs.append(M.mover(saco, m))
    return objs


def sacos_juntar(objs, nome, mat):
    if not objs:
        return None
    o = M.juntar(objs, nome)
    M.material(o, mat)
    return M.suave(o, 80)


# =============================================================== materiais novos
def mat_lona(nome, cor="#56593b", sol="#807b5d", lama="#5a4a35", costura_m=0.92, eixo="Y"):
    """Lona de algodão verde-oliva: variação, desbotado do sol no alto, manchas d'água, barro
    respingado no pé e costuras dos panos (a cada `costura_m`)."""
    m = Mat(nome, rug=0.88)
    p = m.coord("objeto")
    x, y, z = m.separar(p)
    var = m.ruido(p, 1.2, 4)
    cor_ = m.misturar(m.faixa(var, 0.3, 0.75, 0.0, 0.35), rgb(cor), rgb("#3e4128"))
    desb = m.conta(
        "MULTIPLY",
        m.faixa(z, 1.4, 3.2, 0.0, 0.7),
        m.faixa(m.ruido(p, 0.8, 3), 0.3, 0.7, 0.6, 1.0),
    )
    cor_ = m.misturar(desb, cor_, rgb(sol))
    mancha = m.faixa(m.ruido(p, 2.2, 6, 0.65), 0.6, 0.68)
    cor_ = m.misturar(m.conta("MULTIPLY", mancha, 0.45), cor_, rgb("#38392a"))
    respingo = m.conta(
        "MULTIPLY", m.faixa(z, 0.5, 0.02), m.faixa(m.ruido(p, 14.0, 5), 0.4, 0.62, 0.3, 1.0)
    )
    cor_ = m.misturar(respingo, cor_, rgb(lama))
    coord = y if eixo == "Y" else x
    u = m.conta("FRACT", m.conta("MULTIPLY", coord, 1 / costura_m))
    dist = m.conta("MULTIPLY", m.conta("MINIMUM", u, m.conta("SUBTRACT", 1.0, u)), costura_m)
    cost = m.faixa(dist, 0.014, 0.004)
    cor_ = m.misturar(m.conta("MULTIPLY", cost, 0.55), cor_, rgb("#3a3b28"))
    m.cor(cor_)
    m.rug(m.misturar_valor(mancha, 0.9, 0.82))
    m.relevo(m.conta("ADD", m.conta("MULTIPLY", cost, -1.0), m.ruido(p, 7.0, 4)), 0.25, 0.003)
    return m.m


def mat_zinco(nome, ferrugem=0.45, metal_max=0.55):
    """Aço galvanizado ondulado velho: flor do zinco, oxidação branca e escorridos de ferrugem.
    Metal limitado a `metal_max` (o zinco velho é fosco)."""
    m = Mat(nome, rug=0.5)
    p = m.coord("objeto")
    flor = m.voronoi(p, 30.0)
    base = m.misturar(m.faixa(flor, 0.1, 0.5), rgb("#7a7f7e"), rgb("#8f9391"))
    tom = m.faixa(m.ruido(p, 0.7, 3), 0.3, 0.7, 0.0, 0.5)
    base = m.misturar(tom, base, rgb("#6c6f6b"))
    oxid = m.faixa(m.ruido(p, 7.0, 5, 0.6), 0.58, 0.72, 0.0, 0.35)
    base = m.misturar(oxid, base, rgb("#a3a59d"))
    ferr = m.conta(
        "MULTIPLY",
        m.faixa(m.ruido(m.mapear(p, (1.5, 26, 1.5)), 2.0, 5), 0.52, 0.68),
        ferrugem,
    )
    mancha = m.conta("MULTIPLY", m.faixa(m.ruido(p, 6.0, 5), 0.64, 0.72), ferrugem)
    ferr = m.conta("MAXIMUM", ferr, mancha, limitar=True)
    marrom = m.misturar(m.faixa(m.ruido(p, 20.0), 0.3, 0.7), rgb("#64391f"), rgb("#8d5630"))
    m.cor(m.misturar(ferr, base, marrom))
    mt = m.conta("SUBTRACT", metal_max, m.conta("MAXIMUM", ferr, m.conta("MULTIPLY", oxid, 0.6)))
    m.metal(m.conta("MAXIMUM", mt, 0.0))
    m.rug(m.misturar_valor(ferr, 0.55, 0.88))
    m.relevo(m.ruido(p, 90.0, 3), 0.08, 0.0003)
    return m.m


def mat_terra(nome, claro="#a58f6c", escuro="#6c5940", capim=0.35, escala=1.0):
    """Terra arenosa/laterita com pedrinhas, sulcos de chuva e capim no que é quase plano."""
    m = Mat(nome, rug=0.96)
    p = m.coord("objeto")
    var = m.ruido(p, 1.5 * escala, 5, 0.6)
    cor = m.rampa(var, [(0.3, rgb(escuro)), (0.7, rgb(claro))])
    pedra = m.faixa(m.voronoi(p, 26.0 * escala), 0.07, 0.02)
    mancha = m.faixa(m.ruido(p, 6.0 * escala, 4, 0.6), 0.45, 0.7, 0.0, 0.45)
    cor = m.misturar(mancha, cor, rgb("#5b4a35"))
    cor = m.misturar(m.conta("MULTIPLY", pedra, 0.85), cor, rgb("#8e877c"))
    seixo = m.faixa(m.voronoi(p, 70.0 * escala), 0.05, 0.015)
    cor = m.misturar(m.conta("MULTIPLY", seixo, 0.6), cor, rgb("#b0a690"))
    sulco = m.faixa(m.ruido(m.mapear(p, (14, 14, 1.2)), 2.0, 4), 0.62, 0.72)
    cor = m.misturar(m.conta("MULTIPLY", sulco, 0.55), cor, rgb("#4a3b2b"))
    nz = m.separar(m.no("ShaderNodeNewGeometry").outputs["Normal"])[2]
    tufos = m.conta(
        "MULTIPLY",
        m.faixa(m.ruido(p, 3.0, 5), 0.48, 0.62),
        m.conta("MULTIPLY", m.faixa(nz, 0.3, 0.8), capim),
    )
    verde = m.misturar(m.faixa(m.ruido(p, 40.0), 0.3, 0.7), rgb("#4f5a2c"), rgb("#79783f"))
    cor = m.misturar(tufos, cor, verde)
    m.cor(cor)
    m.relevo(var, 0.35, 0.02)
    m.relevo(m.conta("MULTIPLY", pedra, 1.0), 0.5, 0.005)
    m.relevo(seixo, 0.4, 0.003)
    m.relevo(m.ruido(p, 60.0, 3), 0.2, 0.002)
    return m.m


def mat_sape(nome, claro="#b6a272", escuro="#54472f", verde=0.15):
    """Cobertura de folha de palmeira/capim seco (usa `local`: u ao longo do beiral, v subindo a
    água): fibras ao longo da água, camadas, cinza do tempo e algumas folhas mais novas."""
    m = Mat(nome, rug=0.92)
    p = m.coord("local")
    po = m.coord("objeto")
    _, v, _ = m.separar(p)
    fibra = m.ruido(m.mapear(p, (60, 2.0, 60)), 1.0, 8, 0.75, distorcao=0.4)
    fina = m.ruido(m.mapear(p, (220, 6, 220)), 1.0, 4, 0.6)
    cor = m.rampa(
        fibra,
        [(0.28, rgb(escuro)), (0.45, rgb("#86734f")), (0.6, rgb(claro)), (0.78, rgb("#d0bf92"))],
    )
    cor = m.misturar(m.faixa(fina, 0.3, 0.7, 0.0, 0.5), cor, rgb("#3c3324"))
    curso = m.conta("FRACT", m.conta("MULTIPLY", v, 1 / 0.22))
    sombra = m.faixa(curso, 0.0, 0.3, 0.45, 1.0)
    cor = m.misturar(m.conta("SUBTRACT", 1.0, sombra), cor, rgb("#2a231a"))
    tempo = m.faixa(m.ruido(po, 1.0, 4), 0.45, 0.72, 0.0, 0.55)
    cor = m.misturar(tempo, cor, rgb("#8c8676"))
    nova = m.conta("MULTIPLY", m.faixa(m.ruido(po, 2.5, 3), 0.6, 0.7), verde)
    cor = m.misturar(nova, cor, rgb("#6c6e42"))
    m.cor(cor)
    m.rug(0.93)
    m.relevo(fibra, 0.9, 0.01)
    m.relevo(fina, 0.5, 0.003)
    m.relevo(curso, 0.4, 0.015)
    return m.m


def mat_am2(nome):
    """Esteira AM-2: alumínio com revestimento antiderrapante cinza-escuro (PLACEHOLDER de cor),
    gasto nas quinas mostrando o alumínio e manchas de óleo."""
    m = Mat(nome, rug=0.82)
    p = m.coord("objeto")
    grao = m.voronoi(p, 380.0)
    base = m.misturar(m.faixa(m.ruido(p, 2.0, 4), 0.3, 0.7), rgb("#55524b"), rgb("#6a665d"))
    pisado = m.faixa(m.ruido(p, 0.6, 3), 0.55, 0.75, 0.0, 0.5)
    base = m.misturar(pisado, base, rgb("#7b7c78"))
    # sem a curvatura de vértice: numa placa chanfrada de poucos vértices ela dá "quina" na placa
    # inteira (a esteira saía toda clara e de metal, espelhando o céu)
    risco = m.faixa(m.ruido(p, 140.0, 5, 0.7), 0.55, 0.65)
    gasto = m.conta("MULTIPLY", risco, 0.5)
    cor = m.misturar(gasto, base, rgb("#a9aaa8"))
    oleo = m.faixa(m.ruido(p, 1.3, 5), 0.68, 0.74)
    cor = m.misturar(m.conta("MULTIPLY", oleo, 0.7), cor, rgb("#262522"))
    poeira = m.faixa(m.ruido(p, 4.0, 4), 0.55, 0.72, 0.0, 0.45)
    cor = m.misturar(poeira, cor, rgb("#9a876a"))
    m.cor(cor)
    m.metal(0.0)
    m.rug(m.misturar_valor(gasto, m.misturar_valor(oleo, 0.9, 0.5), 0.55))
    m.relevo(grao, 0.25, 0.0008)
    return m.m


def mat_aco_ferrugem(nome, cor="#77705f", ferrugem=0.6):
    """Aço nu ou de pintura gasta, com ferrugem (esteira M8A1, ferragens)."""
    m = Mat(nome, rug=0.6)
    p = m.coord("objeto")
    base = m.misturar(m.faixa(m.ruido(p, 3.0, 4), 0.3, 0.7), rgb(cor), rgb("#47433c"))
    ferr = m.conta("MULTIPLY", m.faixa(m.ruido(p, 5.0, 6, 0.65), 0.5, 0.66), ferrugem)
    marrom = m.misturar(m.faixa(m.ruido(p, 30.0), 0.3, 0.7), rgb("#5a3420"), rgb("#83502c"))
    m.cor(m.misturar(ferr, base, marrom))
    m.metal(m.conta("MULTIPLY", m.conta("SUBTRACT", 1.0, ferr), 0.25))  # aço velho, fosco
    m.rug(m.misturar_valor(ferr, 0.55, 0.85))
    m.relevo(m.ruido(p, 60.0, 4), 0.15, 0.0008)
    return m.m


def mat_borracha(nome):
    m = Mat(nome, rug=0.86)
    p = m.coord("objeto")
    _, _, z = m.separar(p)
    cor = m.misturar(m.faixa(m.ruido(p, 8.0, 4), 0.3, 0.7), rgb("#1f1e1c"), rgb("#2c2a27"))
    barro = m.conta("MULTIPLY", m.faixa(z, 0.25, 0.0), m.faixa(m.ruido(p, 10.0), 0.4, 0.6, 0.4, 1))
    m.cor(m.misturar(barro, cor, rgb("#5a4a36")))
    m.relevo(m.ruido(p, 120.0, 3), 0.2, 0.0006)
    return m.m


def mat_madeira_pintada(nome, tinta="#d8d4c6", gasto=1.0):
    """Madeira pintada (placa, cancela, guarita): a tinta gasta nas quinas mostra a madeira."""
    m = Mat(nome, rug=0.7)
    p = m.coord("objeto")
    veio = m.ruido(m.mapear(p, (2.0, 80, 80)), 1.5, 6, 0.65, distorcao=1.0)
    madeira = m.rampa(veio, [(0.3, rgb("#6f5234")), (0.7, rgb("#9c7a52"))])
    var = m.ruido(p, 6.0, 4)
    cor_t = m.misturar(m.faixa(var, 0.3, 0.75, 0.0, 0.18), rgb(tinta), rgb("#3b3a32"))
    quina = m.faixa(m.pontudo(), 0.52, 0.58)
    lasca = m.faixa(m.ruido(p, 50.0, 6, 0.7), 0.54, 0.62)
    g = m.conta("MULTIPLY", m.conta("MULTIPLY", quina, lasca), gasto)
    cor = m.misturar(g, cor_t, madeira)
    poeira = m.faixa(m.ruido(p, 4.0, 3), 0.55, 0.75, 0.0, 0.3)
    m.cor(m.misturar(poeira, cor, rgb("#8a7c60")))
    m.rug(m.misturar_valor(g, 0.62, 0.85))
    m.relevo(veio, 0.18, 0.0012)
    return m.m


def mat_compensado(nome, claro="#b49c74", escuro="#8a7150"):
    """Compensado/tábua nova clara (guarita, mesa de mapa, piso do strongback)."""
    return N.mat_madeira(nome, claro, escuro, "#9a917f", rug=0.78)


def mat_tinta_lisa(nome, cor, rug=0.6, var=0.12):
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    m.cor(m.misturar(m.faixa(m.ruido(p, 5.0, 4), 0.3, 0.7, 0.0, var), rgb(cor), rgb("#2a2a26")))
    m.relevo(m.ruido(p, 200.0, 2), 0.05, 0.0002)
    return m.m


def mat_bandeira_eua(nome, H, F):
    """Listras e cantão pela Executive Order 10834 (proporções); as estrelas são malha (so_bake).
    Coordenada `local`: x ao longo do batente (0 no mastro), z de 0 (baixo) a H (alto)."""
    m = Mat(nome, rug=0.82)
    p = m.coord("local")
    x, _, z = m.separar(p)
    faixa_i = m.conta("FLOOR", m.conta("MULTIPLY", z, 13.0 / H))
    par = m.conta("SUBTRACT", 1.0, m.conta("MODULO", faixa_i, 2.0))
    vermelho, branco, azul = rgb("#b22234"), rgb("#f2efe6"), rgb("#3c3b6e")
    listras = m.misturar(par, branco, vermelho)
    cantao = m.conta(
        "MULTIPLY",
        m.conta("LESS_THAN", x, 0.76 * H),
        m.conta("GREATER_THAN", z, H - 0.5385 * H),
    )
    cor = m.misturar(cantao, listras, azul)
    po = m.coord("objeto")
    sujo = m.faixa(m.ruido(po, 3.0, 4), 0.5, 0.75, 0.0, 0.25)
    cor = m.misturar(sujo, cor, rgb("#6e6a5a"))
    m.cor(cor)
    m.relevo(m.ruido(m.mapear(po, (3, 40, 3)), 2.0, 3), 0.15, 0.002)
    return m.m


def mat_bandeira_usmc(nome):
    m = Mat(nome, rug=0.82)
    po = m.coord("objeto")
    cor = m.misturar(
        m.faixa(m.ruido(po, 3.0, 4), 0.3, 0.7, 0.0, 0.25), rgb("#a3172a"), rgb("#6b1220")
    )
    m.cor(cor)
    m.relevo(m.ruido(m.mapear(po, (3, 40, 3)), 2.0, 3), 0.15, 0.002)
    return m.m


def mat_mapa(nome):
    """Carta topográfica genérica (curvas de nível, quadrícula, mata e rio) em papel; não copia
    nenhuma carta real."""
    m = Mat(nome, rug=0.8)
    p = m.coord("objeto")
    x, y, _ = m.separar(p)
    alt = m.ruido(p, 6.0, 5, 0.55)
    curva = m.conta("FRACT", m.conta("MULTIPLY", alt, 22.0))
    linha = m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", curva, 0.5)), 0.46, 0.5)
    papel = rgb("#d9d0b0")
    mata = m.faixa(m.ruido(p, 4.0, 4), 0.5, 0.56)
    cor = m.misturar(m.conta("MULTIPLY", mata, 0.7), papel, rgb("#a8bb86"))
    cor = m.misturar(m.conta("MULTIPLY", linha, 0.8), cor, rgb("#9a6a3c"))
    qx = m.faixa(
        m.conta(
            "ABSOLUTE", m.conta("SUBTRACT", m.conta("FRACT", m.conta("MULTIPLY", x, 10.0)), 0.5)
        ),
        0.48,
        0.495,
    )
    qy = m.faixa(
        m.conta(
            "ABSOLUTE", m.conta("SUBTRACT", m.conta("FRACT", m.conta("MULTIPLY", y, 10.0)), 0.5)
        ),
        0.48,
        0.495,
    )
    cor = m.misturar(m.conta("MAXIMUM", qx, qy), cor, rgb("#4a5a8a"))
    rio = m.faixa(
        m.conta("ABSOLUTE", m.conta("SUBTRACT", m.ruido(m.mapear(p, (0.5, 3, 3)), 2.0, 2), 0.5)),
        0.012,
        0.004,
    )
    cor = m.misturar(rio, cor, rgb("#4c7fb4"))
    m.cor(cor)
    m.rug(0.75)
    return m.m


def mat_nylon(nome, cor="#4f5c3b", escuro="#36402a"):
    """Náilon de paraquedas/lona plástica verde (rede e pano do VC)."""
    m = Mat(nome, rug=0.55)
    p = m.coord("objeto")
    c = m.misturar(m.faixa(m.ruido(p, 3.0, 4), 0.3, 0.7, 0.0, 0.5), rgb(cor), rgb(escuro))
    sujo = m.faixa(m.ruido(p, 6.0, 5), 0.6, 0.72, 0.0, 0.4)
    m.cor(m.misturar(sujo, c, rgb("#5b4d37")))
    m.relevo(m.ruido(p, 12.0, 3), 0.2, 0.002)
    return m.m


def mat_folhas_chao(nome):
    """Chão de folhas secas e galhinhos (mata), com terra aparecendo."""
    m = Mat(nome, rug=0.9)
    p = m.coord("objeto")
    cel = m.voronoi(p, 22.0, saida="Color")
    folha = m.rampa(
        m.separar(cel)[0],
        [
            (0.0, rgb("#3f3324")),
            (0.35, rgb("#5e4a33")),
            (0.7, rgb("#76603f")),
            (1.0, rgb("#4f5230")),
        ],
    )
    terra = m.faixa(m.ruido(p, 3.0, 5), 0.6, 0.7)
    cor = m.misturar(terra, folha, rgb("#3f3226"))
    m.cor(cor)
    m.relevo(m.voronoi(p, 22.0), 0.6, 0.006)
    m.relevo(m.ruido(p, 50.0, 4), 0.3, 0.002)
    return m.m


def mat_ferro_fundido(nome):
    m = Mat(nome, rug=0.75)
    p = m.coord("objeto")
    c = m.misturar(m.faixa(m.ruido(p, 20.0, 5), 0.3, 0.7), rgb("#1a1918"), rgb("#2e2b28"))
    fulig = m.faixa(m.ruido(p, 8.0, 4), 0.55, 0.7, 0.0, 0.6)
    m.cor(m.misturar(fulig, c, rgb("#0d0c0b")))
    m.relevo(m.ruido(p, 150.0, 3), 0.3, 0.0006)
    return m.m


def mat_estrela(nome="estrela_branca"):
    m = Mat(nome, rug=0.82)
    m.cor(rgb("#f2efe6"))
    return m.m


# =============================================================== peças prontas
def catre(nome, comp=1.90, larg=0.68, alt=0.43, sem=0, mat_madeira=None, mat_lona_=None):
    """Catre dobrável de campanha (PLACEHOLDER: 1,90 x 0,68 x 0,43 m): longarinas de madeira,
    pernas em X e lona com barriga. Deitado ao longo de Y, centrado na origem."""
    mw = mat_madeira or N.mat_madeira("catre_madeira", "#9b8058", "#6d5538", "#8b7f6a")
    ml = mat_lona_ or mat_lona("catre_lona", "#5b5d40", "#6f6c52")
    pecas = []
    for sx in (-1, 1):
        x = sx * (larg / 2 - 0.02)
        pecas.append(vara(f"{nome}_long", (x, -comp / 2, alt), (x, comp / 2, alt), 0.018, mat=mw))
    for y in (-comp / 2 + 0.05, comp / 2 - 0.05):
        pecas.append(
            vara(
                f"{nome}_trav",
                (-larg / 2 + 0.02, y, alt - 0.02),
                (larg / 2 - 0.02, y, alt - 0.02),
                0.012,
                mat=mw,
            )
        )
    for y in (-comp / 2 + 0.12, 0.0, comp / 2 - 0.12):
        for sx in (-1, 1):
            pecas.append(
                viga(
                    f"{nome}_perna",
                    (sx * (larg / 2 - 0.03), y - 0.12, 0.0),
                    (sx * (larg / 2 - 0.03), y + 0.12, alt - 0.01),
                    0.025,
                    0.018,
                    mw,
                )
            )

    def lona_f(u, v):
        x = -larg / 2 + 0.02 + u * (larg - 0.04)
        y = -comp / 2 + 0.02 + v * (comp - 0.04)
        bar = 0.045 * math.sin(math.pi * u) * math.sin(math.pi * v) ** 0.3
        return (x, y, alt + 0.012 - bar)

    leito = grade(f"{nome}_leito", lona_f, 10, 24, fora=(0, 0, 1))
    M.solidificar(leito, 0.004, -1.0)
    pecas.append(M.material(M.suave(leito, 50), ml))
    return pecas


def manta_dobrada(nome, dim, centro, mat, sem=0):
    o = M.caixa(nome, dim, (0, 0, 0), cortes=3)
    M.chanfrar(o, min(dim) * 0.35, 3)
    M.deslocar(o, lambda co, n: 0.004 * M.fbm(co * 18, 3, sem))
    M.mover(o, Matrix.Translation(Vector(centro)))
    return M.material(M.suave(o, 60), mat)


def saco_de_lona(nome, comp, r, centro, rot_z, mat, sem=0):
    """Saco de lona (sea bag) deitado ao longo de Y, achatado embaixo pelo peso; `centro` é o
    centro do saco."""
    perfil = [
        (0.0, 0.0),
        (r * 0.6, 0.0),
        (r * 0.95, 0.04),
        (r, 0.12),
        (r, comp - 0.12),
        (r * 0.8, comp - 0.04),
        (r * 0.25, comp),
        (0.0, comp),
    ]
    o = M.torno(nome, perfil, segs=16, fatiar=0.06)
    M.mover(o, Matrix.Translation((0, 0, -comp / 2)))
    M.mover(o, Matrix.Rotation(math.pi / 2, 4, "X"))
    M.mover(o, Matrix.Diagonal((1.0, 1.0, 0.8, 1.0)))
    M.deslocar(o, lambda co, n: 0.012 * M.fbm(co * 6, 3, sem))
    M.mover(o, Matrix.Translation(Vector(centro)) @ Matrix.Rotation(rot_z, 4, "Z"))
    return M.material(M.suave(o, 60), mat)


def tambor(nome, centro, mat, deitado=False, rot_z=0.0, sem=0, R=0.292, H=0.876):
    """Tambor de 55 galões: Ø 0,584 x 0,876 m por fora (Wikipedia, Drum (container)), bordas
    enroladas em cima e embaixo e dois aros de rolagem."""
    perfil = [
        (0.0, 0.0),
        (R - 0.02, 0.0),
        (R - 0.004, 0.006),
        (R, 0.016),
        (R - 0.006, 0.024),
    ]
    for zc in (H * 0.33, H * 0.67):
        perfil += [
            (R - 0.006, zc - 0.03),
            (R + 0.004, zc - 0.012),
            (R + 0.004, zc + 0.012),
            (R - 0.006, zc + 0.03),
        ]
    perfil += [
        (R - 0.006, H - 0.024),
        (R, H - 0.016),
        (R - 0.004, H - 0.006),
        (R - 0.02, H - 0.004),
        (R - 0.022, H - 0.012),
        (0.0, H - 0.012),
    ]
    o = M.torno(nome, perfil, segs=40, fatiar=0.05)
    rng = np.random.default_rng(sem)
    amassado = rng.uniform(0.0, 0.01)
    fase = rng.uniform(0, 6.28)
    M.deslocar(
        o,
        lambda co, n: (
            -amassado
            * max(0.0, math.cos(math.atan2(co.y, co.x) - fase)) ** 6
            * math.sin(math.pi * min(1, co.z / H))
        ),
    )
    tampas = []
    for dx, dy, rr in ((0.17, 0.0, 0.03), (-0.17, 0.0, 0.016)):
        t = M.torno(
            nome + "_bujao",
            [
                (0.0, H - 0.012),
                (rr, H - 0.012),
                (rr, H + 0.006),
                (rr * 0.8, H + 0.012),
                (0.0, H + 0.012),
            ],
            segs=12,
        )
        M.mover(t, Matrix.Translation((dx, dy, 0)))
        tampas.append(t)
    objs = [o, *tampas]
    for t in objs:
        M.material(t, mat)
        M.suave(t, 45)
    if deitado:
        m = (
            Matrix.Translation(Vector(centro) + Vector((0, 0, R)))
            @ Matrix.Rotation(rot_z, 4, "Z")
            @ Matrix.Rotation(math.pi / 2, 4, "Y")
            @ Matrix.Translation((0, 0, -H / 2))
        )
    else:
        m = Matrix.Translation(Vector(centro)) @ Matrix.Rotation(rot_z, 4, "Z")
    for t in objs:
        M.mover(t, m)
    return objs


def letreiro(corpo, altura, mat, pos, normal="-Y", fonte=FONTE_ESTENCIL, rot=0.0):
    """Texto plano (so_bake) numa face plana voltada para `normal`."""
    return N.letreiro_plano(corpo, altura, mat, pos, normal, fonte, rot)


def texto_no_plano(corpo, altura, mat, matriz_, fonte=FONTE_PLACA):
    """Texto virado malha, posto por uma matriz (o texto nasce no plano XY, olhando +Z)."""
    t = M.texto_malha(corpo, altura, fonte)
    M.mover(t, matriz_)
    M.material(t, mat)
    return N.so_bake(t)


def estrela(diametro, mat, matriz_):
    """Estrela de 5 pontas (glifo ★ da Segoe UI Symbol) com o diâmetro pedido."""
    t = M.texto_malha("\u2605", 0.1, FONTE_SIMBOLO)
    lo, hi = C.caixa(t)
    c = (lo + hi) / 2
    esc = diametro / max(hi[0] - lo[0], hi[1] - lo[1])
    M.mover(t, Matrix.Scale(esc, 4) @ Matrix.Translation((-c[0], -c[1], 0.0)))
    M.mover(t, matriz_)
    M.material(t, mat)
    return N.so_bake(t)
