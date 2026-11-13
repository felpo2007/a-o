"""Peças de modelagem e de material procedural para os assets novos (Tarefa B).

Roda dentro do Python do Blender. Tudo em METROS, Z para cima (como `comum.py`).

Geometria:
- `torno`: sólido de revolução de um perfil (r, z) em volta de Z;
- `superelipsoide`: saco/almofada (base dos sacos de areia e do saco de arroz);
- `tubo`: tubo ao longo de uma polilinha (alavanca, corda, alça);
- `bambu`: vara com nós; `toro`, `caixa`, `deslocar` (ruído de mathutils, por vértice);
- `texto_malha` e `enrolar`: estêncil e letreiro (texto virado malha, colado na superfície).
Cada peça grava o atributo `local` (coordenada da peça antes de mover) e `semente` (número da
peça): o material lê os dois para a trama do tecido seguir cada saco e a cor variar por peça.

Material (`Mat`): Principled com nós procedurais (ruído, Voronoi, ondas, rampa, bump). O bake
(`comum.produzir`) assa a Base Color como emissão, a normal (com o bump), a rugosidade e o metal.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector, noise

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402

FONTE_ESTENCIL = Path("C:/Windows/Fonts/STENCIL.TTF")
FONTE_LETREIRO = Path("C:/Windows/Fonts/bahnschrift.ttf")


# ---------------------------------------------------------------- objetos e atributos
def objeto(nome: str, me: bpy.types.Mesh) -> bpy.types.Object:
    return C.nova_colecao_objeto(bpy.data.objects.new(nome, me))


def de_bmesh(nome: str, bm: bmesh.types.BMesh) -> bpy.types.Object:
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    return objeto(nome, me)


def gravar_local(obj: bpy.types.Object, semente: float = 0.0) -> None:
    """Atributos por vértice: `local` (posição atual, antes de mover a peça) e `semente`."""
    me = obj.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    for nome in ("local", "semente"):
        if nome in me.attributes:
            me.attributes.remove(me.attributes[nome])
    me.attributes.new("local", "FLOAT_VECTOR", "POINT").data.foreach_set("vector", co)
    s = np.full(len(me.vertices), semente, np.float32)
    me.attributes.new("semente", "FLOAT", "POINT").data.foreach_set("value", s)


def mover(obj: bpy.types.Object, m: Matrix) -> bpy.types.Object:
    obj.data.transform(m)
    obj.data.update()
    return obj


def matriz(pos=(0, 0, 0), rot=(0, 0, 0), escala=None) -> Matrix:
    """Mover, girar (Euler XYZ, rad) e escalar."""
    return Matrix.LocRotScale(
        Vector(pos), Euler(rot, "XYZ"), Vector(escala) if escala is not None else None
    )


def juntar(objs: list[bpy.types.Object], nome: str) -> bpy.types.Object:
    """Junta os objetos num só (o primeiro fica); os materiais são mantidos por face."""
    C.selecionar_so(objs[0], objs)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs):
        bpy.ops.object.join()
    objs[0].name = nome
    return objs[0]


def suave(obj: bpy.types.Object, angulo: float = 50.0) -> bpy.types.Object:
    C.suavizar(obj, angulo)
    return obj


def material(obj: bpy.types.Object, mat: bpy.types.Material) -> bpy.types.Object:
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


# ---------------------------------------------------------------- geometria
def torno(
    nome: str,
    perfil: list[tuple[float, float]],
    segs: int = 48,
    eixo: str = "Z",
    fatiar: float | None = None,
) -> bpy.types.Object:
    """Sólido de revolução. `perfil`: [(r, z)] em ordem; r ≈ 0 numa ponta vira polo. Com
    `fatiar`, os trechos do perfil maiores que isso são subdivididos (mais anéis)."""
    pts = [perfil[0]]
    for a, b in zip(perfil[:-1], perfil[1:], strict=True):
        if fatiar:
            n = max(1, math.ceil(math.dist(a, b) / fatiar))
            for k in range(1, n + 1):
                t = k / n
                pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        else:
            pts.append(b)
    bm = bmesh.new()
    aneis: list[list] = []
    for r, z in pts:
        if r <= 1e-6:
            aneis.append([bm.verts.new((0.0, 0.0, z))])
        else:
            aneis.append(
                [
                    bm.verts.new(
                        (
                            r * math.cos(2 * math.pi * i / segs),
                            r * math.sin(2 * math.pi * i / segs),
                            z,
                        )
                    )
                    for i in range(segs)
                ]
            )
    for a, b in zip(aneis[:-1], aneis[1:], strict=True):
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    obj = de_bmesh(nome, bm)
    if eixo == "X":
        mover(obj, Matrix.Rotation(math.pi / 2, 4, "Y"))
    elif eixo == "Y":
        mover(obj, Matrix.Rotation(-math.pi / 2, 4, "X"))
    return obj


def caixa(nome: str, dim, centro=(0, 0, 0), cortes: int = 0) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    if cortes:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cortes, use_grid_fill=True)
    bmesh.ops.scale(bm, vec=Vector(dim), verts=bm.verts[:])
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts[:])
    return de_bmesh(nome, bm)


def toro(nome: str, R: float, r: float, seg_maior: int = 32, seg_menor: int = 8, arco=None):
    """Toro no plano XY em volta da origem. `arco` = (a0, a1) rad faz só um pedaço (aberto)."""
    a0, a1 = arco if arco else (0.0, 2 * math.pi)
    fechado = arco is None
    n = seg_maior if fechado else seg_maior + 1
    bm = bmesh.new()
    aneis = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / seg_maior
        c, s = math.cos(a), math.sin(a)
        aneis.append(
            [
                bm.verts.new(
                    (
                        (R + r * math.cos(2 * math.pi * k / seg_menor)) * c,
                        (R + r * math.cos(2 * math.pi * k / seg_menor)) * s,
                        r * math.sin(2 * math.pi * k / seg_menor),
                    )
                )
                for k in range(seg_menor)
            ]
        )
    pares = list(zip(aneis[:-1], aneis[1:], strict=True))
    if fechado:
        pares.append((aneis[-1], aneis[0]))
    for a, b in pares:
        for k in range(seg_menor):
            j = (k + 1) % seg_menor
            bm.faces.new((a[k], b[k], b[j], a[j]))
    if not fechado:
        for anel in (aneis[0], aneis[-1]):
            bm.faces.new(anel)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return de_bmesh(nome, bm)


def tubo(nome: str, pontos, raio, segs: int = 8, tampar: bool = True, achatar: float = 1.0):
    """Tubo ao longo de uma polilinha 3D. `raio`: número ou lista (um por ponto). `achatar` < 1
    deixa a seção elíptica (fita)."""
    pts = [Vector(p) for p in pontos]
    raios = raio if isinstance(raio, list | tuple) else [raio] * len(pts)
    bm = bmesh.new()
    aneis = []
    u = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if u is None:
            ref = Vector((0, 0, 1)) if abs(t.z) < 0.95 else Vector((1, 0, 0))
            u = t.cross(ref).normalized()
        else:
            # transporte paralelo: o u anterior projetado no plano normal ao novo tangente
            u = (u - t * u.dot(t)).normalized()
        v = t.cross(u).normalized()
        aneis.append(
            [
                bm.verts.new(
                    p
                    + u * math.cos(2 * math.pi * k / segs) * raios[i]
                    + v * math.sin(2 * math.pi * k / segs) * raios[i] * achatar
                )
                for k in range(segs)
            ]
        )
    for a, b in zip(aneis[:-1], aneis[1:], strict=True):
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((a[k], a[j], b[j], b[k]))
    if tampar:
        bm.faces.new(list(reversed(aneis[0])))
        bm.faces.new(aneis[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return de_bmesh(nome, bm)


def bambu(nome: str, p0, p1, r0: float, r1: float, entre_nos: float = 0.3, segs: int = 12, sem=0):
    """Vara de bambu de p0 a p1, afinando de r0 a r1, com nós (anel mais grosso) a cada
    `entre_nos` m (com variação). O atributo `local` tem o eixo da vara em Z."""
    a, b = Vector(p0), Vector(p1)
    comp = (b - a).length
    rng = np.random.default_rng(sem)
    nos = []
    z = entre_nos * rng.uniform(0.4, 1.0)
    while z < comp - 0.04:
        nos.append(z)
        z += entre_nos * rng.uniform(0.85, 1.15)
    perfil = [(0.0, 0.0), (r0 * 0.92, 0.0), (r0, 0.004)]
    for zn in nos:
        r = r0 + (r1 - r0) * zn / comp
        perfil += [(r, zn - 0.012), (r * 1.07, zn - 0.003), (r * 1.07, zn + 0.003)]
        perfil += [(r, zn + 0.012)]
    perfil += [(r1, comp - 0.004), (r1 * 0.9, comp), (0.0, comp)]
    obj = torno(nome, perfil, segs=segs, fatiar=0.08)
    gravar_local(obj, float(sem))
    eixo = (b - a).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(eixo).to_matrix().to_4x4()
    torcao = Matrix.Rotation(rng.uniform(0, 2 * math.pi), 4, "Z")
    return mover(obj, Matrix.Translation(a) @ rot @ torcao)


def superelipsoide(
    nome: str,
    a: float,
    b: float,
    c: float,
    e1: float = 0.5,
    e2: float = 0.3,
    seg_u: int = 48,
    seg_v: int = 24,
) -> bpy.types.Object:
    """Superelipsoide com semieixos a (X), b (Y), c (Z): e1 = quadratura vertical, e2 =
    horizontal (0 = caixa, 1 = elipsoide)."""

    def cs(w, m):
        cw = math.cos(w)
        return math.copysign(abs(cw) ** m, cw)

    def sn(w, m):
        sw = math.sin(w)
        return math.copysign(abs(sw) ** m, sw)

    bm = bmesh.new()
    base = bm.verts.new((0, 0, -c))
    topo = bm.verts.new((0, 0, c))
    aneis = []
    for j in range(1, seg_v):
        phi = -math.pi / 2 + math.pi * j / seg_v
        aneis.append(
            [
                bm.verts.new(
                    (
                        a * cs(phi, e1) * cs(2 * math.pi * i / seg_u, e2),
                        b * cs(phi, e1) * sn(2 * math.pi * i / seg_u, e2),
                        c * sn(phi, e1),
                    )
                )
                for i in range(seg_u)
            ]
        )
    for i in range(seg_u):
        k = (i + 1) % seg_u
        bm.faces.new((base, aneis[0][k], aneis[0][i]))
        bm.faces.new((topo, aneis[-1][i], aneis[-1][k]))
    for r0, r1 in zip(aneis[:-1], aneis[1:], strict=True):
        for i in range(seg_u):
            k = (i + 1) % seg_u
            bm.faces.new((r0[i], r0[k], r1[k], r1[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return de_bmesh(nome, bm)


def subdividir(obj: bpy.types.Object, niveis: int = 1, simples: bool = False):
    m = obj.modifiers.new("sub", "SUBSURF")
    m.levels = m.render_levels = niveis
    if simples:
        m.subdivision_type = "SIMPLE"
    C.aplicar_modificadores(obj)
    return obj


def chanfrar(obj: bpy.types.Object, largura: float, segs: int = 2, angulo: float = 40.0):
    m = obj.modifiers.new("bevel", "BEVEL")
    m.width = largura
    m.segments = segs
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angulo)
    m.harden_normals = False
    C.aplicar_modificadores(obj)
    return obj


def solidificar(obj: bpy.types.Object, espessura: float, deslocamento: float = 0.0):
    m = obj.modifiers.new("solid", "SOLIDIFY")
    m.thickness = espessura
    m.offset = deslocamento
    m.use_even_offset = True
    C.aplicar_modificadores(obj)
    return obj


def deslocar(obj: bpy.types.Object, f) -> bpy.types.Object:
    """Desloca cada vértice pela normal: `f(co, normal)` devolve o quanto (m) ou um Vector
    (deslocamento livre)."""
    me = obj.data
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    novos = []
    for v in bm.verts:
        d = f(v.co.copy(), v.normal.copy())
        novos.append(v.co + (d if isinstance(d, Vector) else v.normal * d))
    for v, p in zip(bm.verts, novos, strict=True):
        v.co = p
    bm.to_mesh(me)
    bm.free()
    me.update()
    return obj


def fbm(p: Vector, oitavas: int = 4, base: int = 0) -> float:
    """Ruído fractal em [-1, 1] aproximadamente (Perlin do mathutils)."""
    return noise.fractal(p + Vector((base * 17.3, base * 5.1, base * 11.7)), 0.6, 2.0, oitavas)


def ruido(p: Vector, base: int = 0) -> float:
    return noise.noise(p + Vector((base * 17.3, base * 5.1, base * 11.7)))


# ---------------------------------------------------------------- texto
def texto_malha(
    corpo: str, altura: float, fonte: Path = FONTE_ESTENCIL, alinhar: str = "CENTER"
) -> bpy.types.Object:
    """Texto virado malha no plano XY (altura das maiúsculas ≈ `altura`), centrado."""
    cur = bpy.data.curves.new("txt", "FONT")
    cur.body = corpo
    if fonte.is_file():
        cur.font = bpy.data.fonts.load(str(fonte), check_existing=True)
    cur.size = altura / 0.72
    cur.align_x = alinhar
    cur.align_y = "CENTER"
    cur.fill_mode = "BOTH"
    tmp = bpy.data.objects.new("txt", cur)
    bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cur)
    obj = objeto(f"texto_{corpo[:8]}", me)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    return obj


def enrolar(obj: bpy.types.Object, raio_em, z0: float, ang0: float = 0.0, folga: float = 0.0003):
    """Cola um texto do plano XY na lateral de um sólido de revolução em volta de Z: x vira
    ângulo (arco no raio local), y vira altura a partir de z0. `raio_em(z)` dá o raio do sólido."""
    me = obj.data
    for v in me.vertices:
        x, y = v.co.x, v.co.y
        z = z0 + y
        r = raio_em(z) + folga
        a = ang0 + x / r
        v.co = Vector((r * math.cos(a), r * math.sin(a), z))
    me.update()
    return obj


def raio_do_perfil(perfil):
    """Função r(z) por interpolação de um perfil (r, z) monotônico em z (só a parte externa)."""
    zs = np.array([p[1] for p in perfil])
    rs = np.array([p[0] for p in perfil])
    ordem = np.argsort(zs)

    def f(z: float) -> float:
        return float(np.interp(z, zs[ordem], rs[ordem]))

    return f


# ---------------------------------------------------------------- material
def rgb(h: str, a: float = 1.0) -> tuple[float, float, float, float]:
    """Cor sRGB em hex -> RGBA linear (o que o Blender guarda nos nós)."""
    h = h.lstrip("#")
    c = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = C.srgb_para_linear(np.array(c))
    return (float(lin[0]), float(lin[1]), float(lin[2]), a)


class Mat:
    """Material procedural com atalhos para os nós. Entradas aceitam número, cor ou saída de nó."""

    def __init__(self, nome: str, rug: float = 0.8):
        self.m = C.novo_material(nome)
        self.nt = self.m.node_tree
        self.pr = next(n for n in self.nt.nodes if n.type == "BSDF_PRINCIPLED")
        self.pr.inputs["Metallic"].default_value = 0.0
        self.pr.inputs["Roughness"].default_value = rug
        self._normal = None
        self._coord: dict = {}

    # ligações
    def _set(self, sock, val) -> None:
        if isinstance(val, bpy.types.NodeSocket):
            self.nt.links.new(val, sock)
        elif isinstance(val, tuple | list):
            sock.default_value = val if len(val) == len(sock.default_value) else (*val, 1.0)
        else:
            sock.default_value = val

    def no(self, tipo: str, **props):
        n = self.nt.nodes.new(tipo)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def coord(self, tipo: str = "local"):
        """Vetor de coordenada: 'local' (atributo da peça), 'objeto' ou 'uv'."""
        if tipo in self._coord:
            return self._coord[tipo]
        if tipo == "local":
            s = self.no("ShaderNodeAttribute", attribute_name="local").outputs["Vector"]
        else:
            tc = self.no("ShaderNodeTexCoord")
            s = tc.outputs["Object" if tipo == "objeto" else "UV"]
        self._coord[tipo] = s
        return s

    def semente(self):
        return self.no("ShaderNodeAttribute", attribute_name="semente").outputs["Factor"]

    def mapear(self, vec, escala=(1, 1, 1), desloc=(0, 0, 0)):
        m = self.no("ShaderNodeMapping")
        self._set(m.inputs["Vector"], vec)
        m.inputs["Scale"].default_value = escala
        m.inputs["Location"].default_value = desloc
        return m.outputs["Vector"]

    def ruido(self, vec, escala, detalhe=4.0, rug=0.55, distorcao=0.0, saida="Factor"):
        n = self.no("ShaderNodeTexNoise", noise_dimensions="3D")
        self._set(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = escala
        n.inputs["Detail"].default_value = detalhe
        n.inputs["Roughness"].default_value = rug
        n.inputs["Distortion"].default_value = distorcao
        return n.outputs[saida]

    def voronoi(self, vec, escala, feature="F1", saida="Distance", aleat=1.0):
        n = self.no("ShaderNodeTexVoronoi", feature=feature)
        self._set(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = escala
        n.inputs["Randomness"].default_value = aleat
        return n.outputs[saida]

    def onda(self, vec, escala, direcao="X", distorcao=0.0, detalhe=0.0, perfil="SIN"):
        n = self.no(
            "ShaderNodeTexWave", wave_type="BANDS", bands_direction=direcao, wave_profile=perfil
        )
        self._set(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = escala
        n.inputs["Distortion"].default_value = distorcao
        n.inputs["Detail"].default_value = detalhe
        return n.outputs["Factor"]

    def gradiente(self, vec, tipo="RADIAL"):
        n = self.no("ShaderNodeTexGradient", gradient_type=tipo)
        self._set(n.inputs["Vector"], vec)
        return n.outputs["Factor"]

    def separar(self, vec):
        n = self.no("ShaderNodeSeparateXYZ")
        self._set(n.inputs["Vector"], vec)
        return n.outputs["X"], n.outputs["Y"], n.outputs["Z"]

    def juntar_xyz(self, x, y, z):
        n = self.no("ShaderNodeCombineXYZ")
        for s, v in zip(n.inputs, (x, y, z), strict=True):
            self._set(s, v)
        return n.outputs["Vector"]

    def conta(self, op: str, a, b=0.0, c=None, limitar=False):
        n = self.no("ShaderNodeMath", operation=op, use_clamp=limitar)
        self._set(n.inputs[0], a)
        self._set(n.inputs[1], b)
        if c is not None:
            self._set(n.inputs[2], c)
        return n.outputs[0]

    def faixa(self, x, de0, de1, para0=0.0, para1=1.0, suave=True):
        n = self.no("ShaderNodeMapRange", clamp=True)
        if suave:
            n.interpolation_type = "SMOOTHSTEP"
        self._set(n.inputs["Value"], x)
        n.inputs["From Min"].default_value = de0
        n.inputs["From Max"].default_value = de1
        n.inputs["To Min"].default_value = para0
        n.inputs["To Max"].default_value = para1
        return n.outputs["Result"]

    def rampa(self, fac, pontos: list[tuple[float, tuple]]):
        n = self.no("ShaderNodeValToRGB")
        el = n.color_ramp.elements
        while len(el) > len(pontos):
            el.remove(el[-1])
        while len(el) < len(pontos):
            el.new(0.5)
        for e, (pos, cor) in zip(el, pontos, strict=True):
            e.position = pos
            e.color = cor
        self._set(n.inputs["Factor"], fac)
        return n.outputs["Color"]

    def misturar(self, fac, a, b, modo: str = "MIX"):
        n = self.no("ShaderNodeMix", data_type="RGBA", blend_type=modo, clamp_result=True)
        ent = [s for s in n.inputs if s.type == "RGBA"]
        self._set(n.inputs["Factor"], fac)
        self._set(ent[0], a)
        self._set(ent[1], b)
        return next(s for s in n.outputs if s.type == "RGBA")

    def misturar_valor(self, fac, a, b):
        n = self.no("ShaderNodeMix", data_type="FLOAT", clamp_result=True)
        ent = [s for s in n.inputs if s.type == "VALUE" and s.name in ("A", "B")]
        self._set(n.inputs["Factor"], fac)
        self._set(ent[0], a)
        self._set(ent[1], b)
        return next(s for s in n.outputs if s.type == "VALUE")

    def pontudo(self):
        """Pointiness (Cycles): > 0,5 em quina, < 0,5 em fresta."""
        return self.no("ShaderNodeNewGeometry").outputs["Pointiness"]

    def oclusao(self, distancia: float, amostras: int = 8):
        n = self.no("ShaderNodeAmbientOcclusion", samples=amostras)
        n.inputs["Distance"].default_value = distancia
        return n.outputs["AO"]

    # saídas do Principled
    def cor(self, v) -> Mat:
        self._set(self.pr.inputs["Base Color"], v)
        return self

    def rug(self, v) -> Mat:
        self._set(self.pr.inputs["Roughness"], v)
        return self

    def metal(self, v) -> Mat:
        self._set(self.pr.inputs["Metallic"], v)
        return self

    def relevo(self, altura, forca: float, distancia: float) -> Mat:
        """Bump encadeado (cada chamada soma um relevo ao anterior)."""
        b = self.no("ShaderNodeBump")
        b.inputs["Strength"].default_value = forca
        b.inputs["Distance"].default_value = distancia
        self._set(b.inputs["Height"], altura)
        if self._normal is not None:
            self.nt.links.new(self._normal, b.inputs["Normal"])
        self._normal = b.outputs["Normal"]
        self.nt.links.new(self._normal, self.pr.inputs["Normal"])
        return self
