"""Construções novas do Arrozal (D-232). Metros, Z para cima, frente (porta principal) em -Y.

Mesmo caminho das casas da vila: `Receita` com os grupos `Telhado`, `Casa` e `Mobilia`. O grupo Casa
só usa materiais com faixa na trim sheet; reboco ocre, parede verde, parede queimada, carvão e grãos
ficam no atlas `Mobilia` (nó `Mobilia`: o nó `Paredes` é só do grupo Casa).

Paredes de reboco próprio: a parede de verdade (caixa + colisão) fica no grupo Casa, com a faixa de
reboco por dentro, e a face de fora é uma "pele" de uma face no atlas Mobilia. Assim o atlas guarda
só o que se vê de fora.

Chão externo em Z = 0. `exp_comporta` e `exp_passarela` descem até o fundo do canal (Z = -1,25 e
-1,2) e o pipeline normaliza o Z mínimo para 0: o deslocamento sai no relatório.
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_comum as E  # noqa: E402
import modelar as M  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from modelar import Mat, rgb  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402


def _atlas(tel, mob, teto_tel, teto_mob, teto_casa):
    """O atlas do grupo Casa é descartado na passagem para a trim: sai pequeno e sem redução."""
    return {
        "Telhado": {"tex": tel, "teto": teto_tel, "amostras_ao": 32},
        "Mobilia": {"tex": mob, "teto": teto_mob, "amostras_ao": 32},
        "Casa": {"tex": 256, "teto": teto_casa, "amostras_ao": 8},
    }


ATLAS_CELEIRO = _atlas(1024, 1024, 1500, 6500, 6000)
ATLAS_CASA = _atlas(512, 512, 2400, 3800, 5500)
ATLAS_PEQUENO = _atlas(512, 512, 1200, 1800, 3000)


# =============================================================== materiais
def mat_ocre(nome, exposto=0.8):
    return V.mat_gach(nome, reboco="#cdab5f", escuro="#97793f", tijolo="#94523a", exposto=exposto)


def mat_verde(nome):
    return V.mat_gach(nome, reboco="#b6cf9b", escuro="#879d78", tijolo="#8f5a42", exposto=0.55)


def mat_chapa_placa(nome, x0, passo, ferrugens, zinco="#7d807e"):
    """Telhado de chapas pintado direto na placa lisa: uma chapa a cada `passo` m em X a partir de
    `x0`, cada uma com a sua ferrugem (`ferrugens`, 0 = zinco quase novo, 1 = toda enferrujada),
    emenda escura entre elas e a onda (período de 0,11 m) no relevo."""
    m = Mat(nome, rug=0.75)
    p = m.coord("objeto")
    x, y, z = m.separar(p)
    s = m.conta("DIVIDE", m.conta("SUBTRACT", x, x0), passo)
    k = m.conta("FLOOR", s)
    fs = m.conta("FRACT", s)
    n = len(ferrugens)
    no_r = m.no("ShaderNodeValToRGB")
    no_r.color_ramp.interpolation = "CONSTANT"
    el = no_r.color_ramp.elements
    el.remove(el[1])
    el[0].position = 0.0
    el[0].color = (ferrugens[0], ferrugens[0], ferrugens[0], 1.0)
    for i in range(1, n):
        e = el.new(i / n)
        e.color = (ferrugens[i], ferrugens[i], ferrugens[i], 1.0)
    m._set(no_r.inputs["Factor"], m.conta("DIVIDE", m.conta("ADD", k, 0.5), float(n)))
    a = no_r.outputs["Color"]
    # o ruído muda de chapa para chapa: a mancha não continua na vizinha
    q = m.juntar_xyz(m.conta("ADD", x, m.conta("MULTIPLY", k, 3.7)), y, z)
    base = m.misturar(m.faixa(m.ruido(q, 0.9, 4), 0.35, 0.65), rgb("#666a69"), rgb(zinco))
    verm = m.rampa(
        m.ruido(q, 7.0, 5, 0.6),
        [(0.3, rgb("#40231a")), (0.55, rgb("#6c3822")), (0.8, rgb("#8e502e"))],
    )
    escorrido = m.ruido(m.mapear(q, (7.0, 0.7, 7.0)), 1.0, 4, 0.6)
    soma = m.conta(
        "ADD",
        m.conta("MULTIPLY", m.ruido(q, 1.5, 5, 0.6), 0.7),
        m.conta("MULTIPLY", escorrido, 0.3),
    )
    faixa = m.no("ShaderNodeMapRange", clamp=True)
    faixa.interpolation_type = "SMOOTHSTEP"
    m._set(faixa.inputs["Value"], soma)
    m._set(faixa.inputs["From Min"], m.conta("SUBTRACT", 0.62, m.conta("MULTIPLY", a, 0.3)))
    m._set(faixa.inputs["From Max"], m.conta("SUBTRACT", 0.7, m.conta("MULTIPLY", a, 0.24)))
    faixa.inputs["To Min"].default_value = 0.0
    faixa.inputs["To Max"].default_value = 1.0
    cor = m.misturar(faixa.outputs["Result"], base, verm)
    onda = m.conta("SINE", m.conta("MULTIPLY", x, 2 * math.pi / 0.11))
    cor = m.misturar(m.faixa(onda, 0.0, -1.0, 0.0, 0.16), cor, rgb("#17120f"))
    emenda = m.faixa(m.conta("MINIMUM", fs, m.conta("SUBTRACT", 1.0, fs)), 0.0, 0.025, 0.75, 0.0)
    m.cor(m.misturar(emenda, cor, rgb("#17120f")))
    m.relevo(onda, 0.7, 0.012)
    m.relevo(m.ruido(q, 40.0, 3), 0.1, 0.0008)
    return m.m


def chapas_na_placa(rec, nome, x0, x1, regra):
    """Tira as chapas onduladas de `exp_comum` e pinta as chapas na placa lisa. A placa também é
    fonte do bake e fica na frente dos raios: as chapas `so_bake`, 2 cm acima dela, saíam só em
    riscos no atlas. `regra(lado, k)` dá a ferrugem da chapa k de cada água."""
    padrao = re.compile(rf"^{re.escape(nome)}_ch(?:-?\d+_)?\d+")
    for o in [o for o in rec.objs if o.get("so_bake") and padrao.match(o.name)]:
        rec.objs.remove(o)
        bpy.data.objects.remove(o)
    n = max(2, round((x1 - x0) / 1.1))
    passo = (x1 - x0) / n
    primeiro = None
    for o in rec.objs:
        achou = re.match(rf"^{re.escape(nome)}_placa(-?\d+)?$", o.name)
        if not achou:
            continue
        lado = int(achou.group(1) or 0)
        mat = mat_chapa_placa(f"chapa_{nome}{lado}", x0, passo, [regra(lado, k) for k in range(n)])
        M.material(o, mat)
        primeiro = primeiro or mat
    for o in rec.objs:
        if o.name == f"{nome}_capa":
            M.material(o, primeiro)


def mat_tijolo(nome):
    """Tijolo quase todo à mostra, com restos de reboco."""
    return V.mat_gach(nome, reboco="#b9ae98", escuro="#8d8270", tijolo="#a2583c", exposto=3.0)


def mat_queimado(nome):
    """Reboco e tijolo depois do incêndio: fuligem forte no alto e em línguas subindo dos vãos."""
    m = Mat(nome, rug=0.95)
    p = m.coord("local")
    u, z, _ = m.separar(p)
    cor_r = m.rampa(m.ruido(p, 2.2, 4), [(0.3, rgb("#5b4f3d")), (0.7, rgb("#8f7c5c"))])
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
    cor_t = m.rampa(tom, [(0.25, rgb("#40261c")), (0.55, rgb("#6e4230")), (0.8, rgb("#8a5a42"))])
    cor_t = m.misturar(junta, cor_t, rgb("#5e574c"))
    sem_reboco = m.faixa(m.ruido(m.mapear(p, (1, 1, 1), (7, 0, 0)), 0.9, 4, 0.6), 0.5, 0.53)
    cor = m.misturar(sem_reboco, cor_r, cor_t)
    alto = m.faixa(z, 0.5, 2.3, 0.15, 0.95)
    linguas = m.ruido(m.mapear(p, (3.0, 0.45, 3.0)), 1.0, 5, 0.6)
    soma = m.conta("ADD", m.conta("MULTIPLY", linguas, 0.8), m.conta("MULTIPLY", alto, 0.5))
    fuligem = m.faixa(soma, 0.52, 0.76)
    cor = m.misturar(fuligem, cor, rgb("#171412"))
    m.cor(cor)
    m.rug(m.misturar_valor(fuligem, 0.92, 0.75))
    alt = m.conta("SUBTRACT", m.conta("SUBTRACT", 1.0, sem_reboco), m.conta("MULTIPLY", junta, 0.5))
    m.relevo(alt, 0.5, 0.006)
    m.relevo(m.ruido(p, 50.0, 3), 0.2, 0.0015)
    return m.m


def mat_carvao(nome):
    """Madeira carbonizada: placas escuras separadas por fendas, com cinza nas quinas."""
    m = Mat(nome, rug=0.82)
    p = m.coord("local")
    fenda = m.faixa(
        m.voronoi(m.mapear(p, (16, 16, 5)), 1.0, "DISTANCE_TO_EDGE"), 0.0, 0.06, 1.0, 0.0
    )
    base = m.rampa(m.ruido(p, 7.0, 4), [(0.3, rgb("#120f0d")), (0.75, rgb("#2e2823"))])
    cor = m.misturar(fenda, base, rgb("#050404"))
    cinza = m.faixa(m.ruido(p, 3.0, 4), 0.62, 0.74, 0.0, 0.55)
    cor = m.misturar(cinza, cor, rgb("#6a655d"))
    m.cor(cor)
    m.relevo(m.conta("SUBTRACT", 1.0, fenda), 0.8, 0.01)
    return m.m


def mat_graos(nome):
    m = Mat(nome, rug=0.9)
    p = m.coord("objeto")
    grao = m.ruido(p, 130.0, 3, 0.6)
    cor = m.rampa(grao, [(0.32, rgb("#8d6f37")), (0.55, rgb("#c4a35c")), (0.78, rgb("#e2cc8e"))])
    tom = m.faixa(m.ruido(p, 4.0, 3), 0.35, 0.7, 0.0, 0.4)
    m.cor(m.misturar(tom, cor, rgb("#a4854a")))
    m.relevo(grao, 0.7, 0.006)
    return m.m


# =============================================================== paredes
def pedacos(comp, z0, z1, vaos):
    """Os mesmos pedaços de `V.parede`: (u0, u1, z0, z1) entre os vãos."""
    saida = []
    u = 0.0
    for c, w, a0, a1 in sorted(vaos, key=lambda a: a[0]):
        ua, ub = c - w / 2, c + w / 2
        if ua - u > 0.005:
            saida.append((u, ua, z0, z1))
        if min(a0, z1) - z0 > 0.005:
            saida.append((ua, ub, z0, min(a0, z1)))
        if z1 - max(a1, z0) > 0.005 and a0 < z1:
            saida.append((ua, ub, max(a1, z0), z1))
        u = ub
    if comp - u > 0.005:
        saida.append((u, comp, z0, z1))
    return saida


def pele(nome, lado: V.Lado, u0, u1, z0, z1, mat, off=0.006, sem=0.0):
    """Face única por fora da parede, com `local` = (u, z, sem) como a parede."""
    w = -lado.dentro * (lado.esp / 2 + off)
    a, b = lado.ponto(u0, w, z0), lado.ponto(u1, w, z0)
    c, d = lado.ponto(u1, w, z1), lado.ponto(u0, w, z1)
    ob = V.grade(
        nome, lambda s, t: tuple(a.lerp(b, s).lerp(d.lerp(c, s), t)), 1, 1, fora=lado.normal_fora()
    )
    eixo = (lado.ponto(1.0) - lado.ponto(0.0)).normalized()
    o = lado.ponto(0.0)
    V.gravar_uv_local(ob, lambda p: ((p - o).dot(eixo), p.z, sem), sem)
    M.material(ob, mat)
    return ob


def peles(rec, nome, lados, vaos, H, mat, z0=0.0, off=0.006):
    """A pele de cada parede (nas pontas, cobre a quina das paredes vizinhas)."""
    for j, (k, lado) in enumerate(lados.items()):
        ext = (lado.esp if k in ("esq", "dir") else 0.0) + off
        for i, (u0, u1, a, b) in enumerate(pedacos(lado.comp, z0, H, vaos[k])):
            ua = u0 - ext if u0 < 1e-3 else u0
            ub = u1 + ext if u1 > lado.comp - 1e-3 else u1
            rec.add(
                pele(f"{nome}_{k}{i}", lado, ua, ub, a, b, mat, off, sem=j * 3.7),
                "Mobilia",
                "Mobilia",
            )


def oitao_reboco(rec, nome, L, W, h, hr, mat, esp=0.18, cx=0.0, cy=0.0):
    """Empena de reboco nos dois lados (±X): prisma triangular, com a colisão igual."""
    for sx in (-1, 1):
        x = cx + sx * (L / 2 - esp / 2)
        bm = bmesh.new()
        pts = [(cy - W / 2, h), (cy + W / 2, h), (cy, hr)]
        vs = [[bm.verts.new((x + d, y, z)) for y, z in pts] for d in (-esp / 2, esp / 2)]
        bm.faces.new(vs[0][::-1])
        bm.faces.new(vs[1])
        for i in range(3):
            j = (i + 1) % 3
            bm.faces.new((vs[0][i], vs[0][j], vs[1][j], vs[1][i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        ob = M.de_bmesh(f"{nome}{sx}", bm)
        V.gravar_uv_local(ob, lambda p: (p.y, p.z, p.x), float(sx))
        M.material(ob, mat)
        rec.add(M.suave(ob, 30), "Mobilia", "Mobilia")
        rec.prisma(f"{nome}{sx}", [tuple(v.co) for v in ob.data.vertices], "para", "Brick")


def trecho(rec, nome, lado: V.Lado, u0, u1, h0, h1, mat, z0=0.0, col="Brick", sem=0.0):
    """Pedaço de parede de u0 a u1 com o topo inclinado (h0 -> h1): visual e colisão iguais."""
    e = lado.esp / 2
    cantos = [
        (u0, -e, z0),
        (u1, -e, z0),
        (u1, e, z0),
        (u0, e, z0),
        (u0, -e, h0),
        (u1, -e, h1),
        (u1, e, h1),
        (u0, e, h0),
    ]
    bm = bmesh.new()
    vs = [bm.verts.new(c) for c in cantos]
    for f in ((3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = M.de_bmesh(nome, bm)
    V.gravar_uv_local(ob, lambda p: (p.x, p.z, p.y), sem)
    M.mover(ob, Matrix.Translation((lado.o[0], lado.o[1], 0.0)) @ Matrix.Rotation(lado.ang, 4, "Z"))
    M.material(ob, mat)
    rec.add(M.suave(ob, 35), "Mobilia", "Mobilia")
    colisao_trecho(rec, nome, lado, u0, u1, h0, h1, z0, col)


def colisao_trecho(rec, nome, lado: V.Lado, u0, u1, h0, h1, z0=0.0, col="Brick"):
    """Sólido de colisão de um pedaço de parede com o topo inclinado."""
    e = lado.esp / 2
    cantos = [(u, w, z) for u, h in ((u0, h0), (u1, h1)) for w in (-e, e) for z in (z0, h)]
    rec.prisma(nome, [tuple(lado.ponto(a, b, c)) for a, b, c in cantos], "para", col)


def enx_xz(rec, nome, p0, p1, y, mats, larg=0.15, prof=0.07):
    """Viga aparente numa parede no plano XZ (frente e fundo); p = (x, z)."""
    rec.add(
        V.viga(nome, (p0[0], y, p0[1]), (p1[0], y, p1[1]), prof, larg, mats.go_escuro),
        "Casa",
        "Estrutura",
    )


def enx_yz(rec, nome, p0, p1, x, mats, larg=0.15, prof=0.07):
    """Viga aparente numa parede no plano YZ (empenas); p = (y, z)."""
    em_pe = abs(p1[0] - p0[0]) < 1e-6
    a, b = (larg, prof) if em_pe else (prof, larg)
    rec.add(
        V.viga(nome, (x, p0[0], p0[1]), (x, p1[0], p1[1]), a, b, mats.go_escuro),
        "Casa",
        "Estrutura",
    )


def registrar_porta(rec, nome, centro, larg, alt, normal, interna=False):
    """Abertura sem `V.porta` (portão, brecha): entra na lista de portas do metricas."""
    rec.extras["portas_m"].append([float(c) for c in centro])
    rec.extras["portas"].append(
        {
            "nome": nome,
            "largura_livre_m": larg,
            "altura_livre_m": alt,
            "normal_blender": [float(c) for c in normal],
            "interna": interna,
        }
    )


def folha_portao(rec, nome, x0, x1, y, z0, z1, van, mats, fora=-1.0):
    """Folha de portão de tábuas aberta e deitada na parede, com travessas e mão-francesa."""
    ob = V.peca(f"{nome}_tab", (x0, y), 0.0, 0.0, x1 - x0, z0, z1, -0.03, 0.03, van)
    rec.add(ob, "Casa", "Paredes")
    yo = y + fora * 0.05
    zs = (z0 + 0.1, (z0 + z1) / 2, z1 - 0.1)
    for k, z in enumerate(zs):
        rec.add(
            V.viga(f"{nome}_tr{k}", (x0, yo, z), (x1, yo, z), 0.05, 0.14, mats.go_escuro),
            "Casa",
            "Estrutura",
        )
    for k, (a, b) in enumerate(((zs[0], zs[1]), (zs[2], zs[1]))):
        rec.add(
            V.viga(f"{nome}_dg{k}", (x0, yo, a), (x1, yo, b), 0.05, 0.13, mats.go_escuro),
            "Casa",
            "Estrutura",
        )
    rec.caixa(nome, ((x0 + x1) / 2, y, (z0 + z1) / 2), (x1 - x0, 0.1, z1 - z0), "para", "Wood")


def venezianas(rec, nome, lado: V.Lado, t, w, z0, z1, mats):
    """Duas folhas de janela abertas e encostadas na parede de fora."""
    c = lado.comp / 2 + t
    wa, wb = sorted((-lado.dentro * (lado.esp / 2 + 0.015), -lado.dentro * (lado.esp / 2 + 0.05)))
    for s in (-1, 1):
        u0, u1 = sorted((c + s * (w / 2 + 0.07), c + s * (w + 0.07)))
        rec.add(
            V.peca(
                f"{nome}{s}", lado.o, lado.ang, u0, u1, z0 - 0.05, z1 + 0.05, wa, wb, mats.go_escuro
            ),
            "Casa",
            "Paredes",
        )


# =============================================================== móveis leves
def achatar(ob, z=0.0):
    """Encosta no plano `z` os vértices que passaram para baixo dele."""
    for v in ob.data.vertices:
        if v.co.z < z:
            v.co.z = z
    ob.data.update()


def saco(rec, nome, x, y, z, rz, mats, sem=0):
    s = M.superelipsoide(nome, 0.31, 0.21, 0.135, 0.42, 0.45, 10, 4)
    M.deslocar(s, lambda co, n, k=sem: 0.014 * M.fbm(co * 7.0, 2, k))
    V.gravar_uv_local(s, lambda p: (p.x, p.y, p.z), float(sem))
    achatar(s, -0.125)  # o pé do saco fica em `z`, sem descer no chão
    M.mover(s, Matrix.Translation((x, y, z + 0.125)) @ Matrix.Rotation(math.radians(rz), 4, "Z"))
    M.material(s, mats.juta)
    rec.add(M.suave(s, 70), "Mobilia", "Mobilia")


def pilha_sacos(rec, nome, cx, cy, rot, nx, ny, camadas, mats, z=0.0, sem=0):
    """Pilha em amarração (cada camada desencontrada meio saco) com uma caixa de colisão."""
    r = Matrix.Rotation(math.radians(rot), 3, "Z")
    px, py, pz = 0.62, 0.43, 0.225
    k = 0
    for c in range(camadas):
        n = nx - (c % 2)
        for j in range(ny):
            for i in range(n):
                q = r @ Vector(((i - (n - 1) / 2) * px, (j - (ny - 1) / 2) * py, 0.0))
                saco(
                    rec,
                    f"{nome}{k}",
                    cx + q.x,
                    cy + q.y,
                    z + c * pz,
                    rot + 7.0 * math.sin(k * 2.1 + sem),
                    mats,
                    sem=sem + k,
                )
                k += 1
    alt = camadas * pz + 0.05
    rec.caixa(
        nome,
        (cx, cy, z + alt / 2),
        (nx * px, ny * py + 0.02, alt),
        "para",
        "Fabric",
        rot_z=math.radians(rot),
    )


def cesto(rec, nome, x, y, z, r, alt, mats, cheio=False, col=True, sem=0):
    perfil = [
        (0.0, 0.0),
        (r * 0.74, 0.0),
        (r * 0.96, alt * 0.3),
        (r, alt * 0.78),
        (r * 1.04, alt),
        (r * 0.95, alt),
        (r * 0.9, alt * 0.84),
        (0.0, alt * 0.82),
    ]
    o = [V.torno_local(f"{nome}_c", perfil, 10, mats.esteira, sem=float(sem))]
    if cheio:
        o.append(V.cilindro(f"{nome}_g", r * 0.9, 0.04, (0, 0, alt * 0.87), mats.arroz, segs=10))
    for ob in o:
        M.mover(ob, Matrix.Translation((x, y, z)))
    rec.addv(o, "Mobilia", "Mobilia")
    if col:
        rec.caixa(nome, (x, y, z + alt / 2), (2 * r, 2 * r, alt), "passa", "Bamboo")


def rolo_corda(rec, nome, pos, mats, R=0.2, eixo="Y"):
    o = M.toro(nome, R, 0.035, 12, 5)
    V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
    M.material(o, mats.corda)
    rot = Matrix.Rotation(math.pi / 2, 4, "X" if eixo == "Y" else "Y")
    M.mover(o, Matrix.Translation(pos) @ rot)
    rec.add(M.suave(o, 50), "Mobilia", "Mobilia")


def bancada(rec, nome, pos, rot, mats, comp=2.4, larg=0.8, alt=0.86, z=0.0):
    """Bancada de trabalho: 3 tábuas no tampo, pés, travessas e prateleira baixa."""
    o = []
    n = 3
    for k in range(n):
        y = -larg / 2 + (k + 0.5) * larg / n
        o.append(
            V.bloco(
                f"{nome}_t{k}",
                (comp + 0.03 * math.sin(k * 2.0), larg / n - 0.008, 0.05),
                (0, y, z + alt - 0.025),
                mats.go if k % 2 else mats.go_escuro,
            )
        )
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                V.bloco(
                    f"{nome}_p{sx}{sy}",
                    (0.08, 0.08, alt - 0.05),
                    (sx * (comp / 2 - 0.12), sy * (larg / 2 - 0.08), z + (alt - 0.05) / 2),
                    mats.go_escuro,
                )
            )
        o.append(
            V.bloco(
                f"{nome}_ta{sx}",
                (0.06, larg - 0.1, 0.07),
                (sx * (comp / 2 - 0.12), 0, z + 0.25),
                mats.go,
            )
        )
    o.append(V.bloco(f"{nome}_prat", (comp - 0.3, larg * 0.6, 0.03), (0, 0, z + 0.27), mats.go))
    rec.addv(V._colocar(o, pos, rot), "Casa", "Anexos")
    V._col_local(rec, nome, pos, rot, (0, 0, z + alt / 2), (comp, larg, alt))


def banco(rec, nome, pos, rot, mats, comp=1.7, z=0.0):
    o = [V.bloco(f"{nome}_t", (comp, 0.32, 0.05), (0, 0, z + 0.43), mats.go)]
    for sx in (-1, 1):
        x = sx * (comp / 2 - 0.18)
        o.append(V.bloco(f"{nome}_p{sx}", (0.07, 0.28, 0.41), (x, 0, z + 0.205), mats.go_escuro))
    o.append(V.bloco(f"{nome}_tr", (comp - 0.42, 0.05, 0.06), (0, 0, z + 0.18), mats.go_escuro))
    rec.addv(V._colocar(o, pos, rot), "Casa", "Anexos")
    V._col_local(rec, nome, pos, rot, (0, 0, z + 0.23), (comp, 0.34, 0.46))


def roda(nome, x, y, z, R, mats):
    """Roda de madeira no plano YZ (eixo em X): aro, 3 raios e cubo."""
    o = []
    aro = M.toro(f"{nome}_aro", R, 0.032, 14, 4)
    V.gravar_uv_local(aro, lambda p: (p.x, p.y, p.z))
    M.material(aro, mats.go_escuro)
    o.append(M.suave(aro, 50))
    for k in range(3):
        a = k * math.pi / 3
        d = Vector((math.cos(a) * R, math.sin(a) * R, 0.0))
        o.append(V.viga(f"{nome}_r{k}", -d, d, 0.035, 0.035, mats.go))
    o.append(V.cilindro(f"{nome}_cubo", 0.07, 0.12, (0, 0, 0), mats.go_escuro, segs=8))
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    for ob in o:
        M.mover(ob, m)
    return o


def carroca(rec, nome, pos, rot, mats, carga=True, z=0.0):
    """Carroça de mão: caixa de tábuas sobre 2 rodas, varais para -Y e 2 pés de descanso."""
    o = []
    zc = z + 0.52
    for k in range(4):
        x = -0.45 + 0.3 * k
        o.append(V.bloco(f"{nome}_f{k}", (0.285, 1.6, 0.04), (x, 0, zc), mats.go))
    for sx in (-1, 1):
        for k, zz in enumerate((0.14, 0.32)):
            o.append(
                V.bloco(
                    f"{nome}_lat{sx}{k}",
                    (0.035, 1.6, 0.14),
                    (sx * 0.62, 0, zc + zz),
                    mats.go_escuro if k else mats.go,
                )
            )
        o.append(
            V.viga(
                f"{nome}_varal{sx}",
                (sx * 0.42, 0.8, zc - 0.05),
                (sx * 0.42, -1.75, z + 0.2),
                0.06,
                0.07,
                mats.go_escuro,
            )
        )
        o.append(
            V.bloco(
                f"{nome}_pe{sx}", (0.06, 0.06, 0.5), (sx * 0.42, -0.72, z + 0.25), mats.go_escuro
            )
        )
        o.extend(roda(f"{nome}_roda{sx}", sx * 0.72, 0.15, z + 0.415, 0.38, mats))
    for sy in (-1, 1):
        o.append(
            V.bloco(f"{nome}_tp{sy}", (1.25, 0.035, 0.3), (0, sy * 0.8, zc + 0.2), mats.go_escuro)
        )
    o.append(
        V.tre(f"{nome}_eixo", (-0.76, 0.15, z + 0.415), (0.76, 0.15, z + 0.415), 0.03, mats.go)
    )
    rec.addv(V._colocar(o, pos, rot), "Casa", "Anexos")
    V._col_local(rec, nome, pos, rot, (0, 0.0, z + 0.45), (1.5, 1.85, 0.9))
    if carga:
        r = Matrix.Rotation(math.radians(rot), 3, "Z")
        for k, (dx, dy, dz, rz) in enumerate(
            (
                (-0.22, -0.32, 0.56, 8),
                (0.25, -0.3, 0.56, -6),
                (0.0, 0.32, 0.56, 88),
                (0.04, -0.28, 0.78, 14),
            )
        ):
            q = r @ Vector((dx, dy, 0.0))
            saco(
                rec,
                f"{nome}_saco{k}",
                pos[0] + q.x,
                pos[1] + q.y,
                z + dz,
                rot + rz,
                mats,
                sem=k + 5,
            )


def entulho(rec, nome, x, y, a, b, h, mat, z=0.0, sem=0, tijolos=6, col=True, monte=None):
    """Monte de entulho: cinza irregular e facetada (`monte`), tijolos soltos, pedaços de parede
    caídos e colisão baixa."""
    rr = np.random.default_rng(sem + 100)
    m = M.superelipsoide(f"{nome}_monte", a, b, h, 0.85, 0.9, 16, 7)
    M.deslocar(
        m,
        lambda co, n, k=sem: 0.05 * M.fbm(co * 3.2, 3, k) + 0.045 * M.fbm(co * 11.0, 2, k + 7),
    )
    V.apagar_faces(m, lambda c, n: c.z < -0.02)
    achatar(m)
    V.gravar_uv_local(m, lambda p: (p.x, p.z + 0.4, p.y), float(sem))
    M.mover(m, Matrix.Translation((x, y, z)))
    M.material(m, monte or mat)
    rec.add(M.suave(m, 28), "Mobilia", "Mobilia")

    def no_monte(alt):
        ang = float(rr.uniform(0, 2 * math.pi))
        d = float(rr.uniform(0.2, 0.9))
        # altura da superfície do monte nesse raio: o tijolo fica por cima da cinza
        topo = h * max(0.0, 1 - d * d) ** 0.45
        q = (x + a * d * math.cos(ang), y + b * d * math.sin(ang), z + topo + alt)
        return q, (float(rr.uniform(-0.5, 0.5)), float(rr.uniform(-0.5, 0.5)), ang)

    for k in range(tijolos * 2):
        q, rot = no_monte(0.04)
        rec.add(V.bloco(f"{nome}_t{k}", (0.22, 0.11, 0.065), q, mat, rot=rot), "Mobilia", "Mobilia")
    for k in range(max(2, tijolos // 2)):
        q, rot = no_monte(0.06)
        s = float(rr.uniform(0.18, 0.38)) * min(1.0, a / 0.6)
        d = (s, s * float(rr.uniform(0.6, 1.0)), float(rr.uniform(0.07, 0.14)))
        rec.add(V.bloco(f"{nome}_p{k}", d, q, mat, rot=rot), "Mobilia", "Mobilia")
    if col:
        k = 0.55
        pts = [(x + sx * a * 0.9, y + sy * b * 0.9, z) for sx in (-1, 1) for sy in (-1, 1)]
        pts += [(x + sx * a * k, y + sy * b * k, z + h * 0.8) for sx in (-1, 1) for sy in (-1, 1)]
        rec.prisma(nome, pts, "para", "Brick")


# =============================================================== 1. celeiro
def _enxaimel_oitao(rec, nome, x, W, H, hr, mats, y_porta=None):
    """Enxaimel de uma empena: postes, frechal, travessa e o desenho do triângulo."""
    Hv, zm = H - 0.09, 1.25
    a, b = -W / 2 + 0.08, W / 2 - 0.08
    for k, y in enumerate((a, -1.55, 1.55, b)):
        if y_porta is not None and abs(y - y_porta) < 0.75:
            continue
        enx_yz(rec, f"{nome}_p{k}", (y, 0.0), (y, H), x, mats)
    enx_yz(rec, f"{nome}_fre", (a, Hv), (b, Hv), x, mats)
    if y_porta is None:
        enx_yz(rec, f"{nome}_m", (a, zm), (b, zm), x, mats)
    else:
        enx_yz(rec, f"{nome}_m0", (a, zm), (y_porta - 0.62, zm), x, mats)
        enx_yz(rec, f"{nome}_m1", (y_porta + 0.62, zm), (b, zm), x, mats)
    enx_yz(rec, f"{nome}_rei", (0.0, H), (0.0, hr - 0.22), x, mats)
    z_s = hr - (hr - H) * 2.3 / (W / 2) - 0.1
    for s in (-1, 1):
        enx_yz(rec, f"{nome}_st{s}", (s * 2.3, H), (s * 2.3, z_s), x, mats)
        enx_yz(rec, f"{nome}_d{s}", (s * 3.4, H), (0.0, hr - 0.75), x, mats)
        enx_yz(rec, f"{nome}_e{s}", (0.0, H), (s * 2.3, z_s - 0.05), x, mats)


def receita_exp_celeiro():
    """O marco do Arrozal: celeiro de reboco ocre com enxaimel aparente, telhado de chapa
    remendada, portão largo aberto na frente, porta lateral, janelas de ripas e, por dentro,
    pilares, pilhas de sacos, cestos, carroça de mão e bancada, com corredores livres."""
    rec = V.Receita()
    mats = Mats(61)
    L, W, H, esp, hr = 15.0, 9.0, 3.6, 0.22, 6.0
    xg, lg, hg = 2.3, 3.6, 3.0  # portão: centro em X, vão livre e topo do vão
    dentro = V.mat_gach("gach", exposto=0.2)
    ocre = mat_ocre("reboco_ocre")
    van = V.mat_tabua("van")
    jan = {"w": 1.05, "z0": 1.45, "z1": 2.25, "estilo": "grade"}
    lados, vaos = VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        dentro,
        [{"lado": "esq", "t": -2.4, "estilo": "tabua", "folha": 1}],
        [
            {"lado": "frente", "t": -5.55, **jan},
            {"lado": "fundo", "t": -5.55, **jan},
            {"lado": "fundo", "t": 0.0, **jan},
            {"lado": "fundo", "t": 5.55, **jan},
            {"lado": "dir", "t": 0.0, **jan},
            {"lado": "esq", "t": 2.2, **jan},
        ],
        col="Brick",
        sem=61,
        vaos_extra={"frente": [(L / 2 + xg, lg + 0.28, -1.0, hg + 0.12)]},
    )
    peles(rec, "pele", lados, vaos, H, ocre)
    oitao_reboco(rec, "oitao", L, W, H, hr - 0.1, ocre, esp)
    # portão: batentes, verga e as duas folhas abertas contra a parede
    y_fr = -W / 2 + esp / 2
    for s in (-1, 1):
        x = xg + s * (lg / 2 + 0.07)
        dim = (0.14, esp + 0.1, hg + 0.12)
        rec.add(
            V.bloco(f"port_bat{s}", dim, (x, y_fr, dim[2] / 2), mats.go_escuro, chanfro=0.01),
            "Casa",
            "Paredes",
        )
        rec.caixa(f"port_bat{s}", (x, y_fr, dim[2] / 2), dim, "para", "Wood")
    dim = (lg + 0.5, esp + 0.1, 0.16)
    rec.add(V.bloco("port_verga", dim, (xg, y_fr, hg + 0.04), mats.go_escuro), "Casa", "Paredes")
    rec.caixa("port_verga", (xg, y_fr, hg + 0.04), dim, "para", "Wood")
    registrar_porta(rec, "portao", (xg, y_fr, PISO), lg, round(hg - 0.04 - PISO, 2), (0, -1, 0))
    yl = -W / 2 - 0.11
    folha_portao(
        rec, "folha_e", xg - lg / 2 - 0.14 - 1.8, xg - lg / 2 - 0.14, yl, 0.04, hg - 0.05, van, mats
    )
    folha_portao(
        rec, "folha_d", xg + lg / 2 + 0.14, xg + lg / 2 + 0.14 + 1.8, yl, 0.04, hg - 0.05, van, mats
    )
    # enxaimel
    Hv, zm = H - 0.09, 1.25
    A, Bx = -L / 2 + 0.08, L / 2 - 0.08
    esq_g, dir_g = xg - lg / 2 - 0.14, xg + lg / 2 + 0.14
    yf, yb = -W / 2 - 0.03, W / 2 + 0.03
    frente = [
        ((A, 0.0), (A, H)),
        ((Bx, 0.0), (Bx, H)),
        ((-3.7, 0.0), (-3.7, H)),
        ((A, Hv), (Bx, Hv)),
        ((A, zm), (esq_g, zm)),
        ((dir_g, zm), (Bx, zm)),
        ((A, 0.14), (esq_g, 0.14)),
        ((dir_g, 0.14), (Bx, 0.14)),
        ((-3.7, zm), (-2.1, Hv)),
        ((esq_g, zm), (-1.7, Hv)),
        ((dir_g + 1.85, zm), (dir_g + 1.85, Hv)),
        ((Bx, zm), (dir_g + 1.95, Hv)),
    ]
    for k, (p, q) in enumerate(frente):
        enx_xz(rec, f"enx_f{k}", p, q, yf, mats)
    fundo = [
        ((A, 0.0), (A, H)),
        ((Bx, 0.0), (Bx, H)),
        ((-3.7, 0.0), (-3.7, H)),
        ((3.7, 0.0), (3.7, H)),
        ((A, Hv), (Bx, Hv)),
        ((A, zm), (Bx, zm)),
        ((A, 0.14), (Bx, 0.14)),
        ((-3.7, zm), (-2.0, Hv)),
        ((3.7, zm), (2.0, Hv)),
    ]
    for k, (p, q) in enumerate(fundo):
        enx_xz(rec, f"enx_b{k}", p, q, yb, mats)
    _enxaimel_oitao(rec, "enx_e", -L / 2 - 0.03, W, H, hr, mats, y_porta=-2.4)
    _enxaimel_oitao(rec, "enx_d", L / 2 + 0.03, W, H, hr, mats)
    # estrutura interna: 3 pilares no eixo, linhas, pendurais e pernas
    for k, x in enumerate((-3.7, 0.0, 3.7)):
        V.poste(rec, f"pilar{k}", x, 0.0, H - 0.15, mats.go_escuro, r=0.13, base_pedra=mats.pedra)
        rec.add(
            V.viga(
                f"linha{k}",
                (x, -W / 2 + esp, H - 0.06),
                (x, W / 2 - esp, H - 0.06),
                0.14,
                0.18,
                mats.go_escuro,
            ),
            "Casa",
            "Estrutura",
        )
        rec.add(
            V.viga(f"pendural{k}", (x, 0, H + 0.03), (x, 0, hr - 0.14), 0.12, 0.12, mats.go),
            "Casa",
            "Estrutura",
        )
        for s in (-1, 1):
            rec.add(
                V.viga(
                    f"perna{k}{s}",
                    (x, s * (W / 2 - 0.2), H + 0.03),
                    (x, 0, hr - 0.16),
                    0.1,
                    0.13,
                    mats.go,
                ),
                "Casa",
                "Estrutura",
            )
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.45, mats, sem=61, ferrugem=0.8, beiral_oitao=0.38)

    def chapa_celeiro(lado, k):
        if (lado < 0 and k in (2, 3, 4, 5)) or (lado > 0 and k in (7, 8, 9)):
            return 0.14
        return 1.0 if (k * 5 + lado) % 3 else 0.82

    chapas_na_placa(rec, "tel", -L / 2 - 0.38, L / 2 + 0.38, chapa_celeiro)
    # interior: corredor em T livre entre o portão, a porta lateral e o fundo
    pilha_sacos(rec, "sacos_a", -5.0, 3.72, 0, 5, 2, 3, mats, z=PISO, sem=1)
    pilha_sacos(rec, "sacos_b", 3.9, 3.72, 0, 4, 2, 3, mats, z=PISO, sem=40)
    pilha_sacos(rec, "sacos_c", 6.6, -1.5, 90, 3, 2, 2, mats, z=PISO, sem=70)
    bancada(rec, "bancada", (-1.0, 3.84), 0, mats, comp=2.8, larg=0.75, z=PISO)
    cesto(rec, "cesto_b", -1.6, 3.82, PISO + 0.86, 0.2, 0.26, mats, cheio=True, col=False, sem=3)
    carroca(rec, "carroca", (-2.0, -1.1), 25, mats, z=PISO)
    for k, (x, y, r, a) in enumerate(
        ((-6.8, -3.75, 0.33, 0.62), (-6.15, -3.85, 0.28, 0.5), (-5.6, -3.82, 0.3, 0.72))
    ):
        cesto(rec, f"cesto{k}", x, y, PISO, r, a, mats, cheio=k != 1, sem=k + 10)
    rolo_corda(rec, "corda", (3.7, -0.16, 1.75), mats)
    # do lado de fora, junto do portão
    cesto(rec, "cesto_f0", -2.9, -4.74, 0.0, 0.2, 0.42, mats, cheio=True, sem=21)
    cesto(rec, "cesto_f1", -2.42, -4.74, 0.0, 0.17, 0.32, mats, sem=22)
    VC.camera(rec, (4.2, -3.6, PISO + 1.9), (-2.8, 2.8, PISO + 0.6))
    return rec


# =============================================================== 2. galpão
def receita_exp_galpao():
    """Telheiro aberto de trabalho: pilares de madeira com mãos-francesas, cobertura de chapa,
    bancadas compridas, cestos e sacos. Sem paredes."""
    rec = V.Receita()
    mats = Mats(62)
    L, W, H, hr = 9.0, 5.0, 3.05, 3.95
    xs = (-4.3, -1.45, 1.45, 4.3)
    ys = (-2.3, 2.3)
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            V.poste(rec, f"pil{i}{j}", x, y, H - 0.06, mats.go, r=0.095, base_pedra=mats.pedra)
        rec.add(
            V.viga(
                f"linha{i}", (x, -2.42, H - 0.02), (x, 2.42, H - 0.02), 0.11, 0.15, mats.go_escuro
            ),
            "Casa",
            "Estrutura",
        )
        for s in (-1, 1):
            rec.add(
                V.viga(
                    f"mf_y{i}{s}", (x, s * 2.3, 2.32), (x, s * 1.62, H - 0.08), 0.07, 0.09, mats.go
                ),
                "Casa",
                "Estrutura",
            )
    for j, y in enumerate(ys):
        rec.add(
            V.viga(
                f"frechal{j}", (-4.5, y, H - 0.06), (4.5, y, H - 0.06), 0.12, 0.14, mats.go_escuro
            ),
            "Casa",
            "Estrutura",
        )
        for i, x in enumerate(xs):
            for s in (-1, 1):
                if abs(x + s * 0.7) > 4.45:
                    continue
                rec.add(
                    V.viga(
                        f"mf_x{i}{j}{s}",
                        (x, y, 2.32),
                        (x + s * 0.7, y, H - 0.1),
                        0.07,
                        0.09,
                        mats.go,
                    ),
                    "Casa",
                    "Estrutura",
                )
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.42, mats, sem=62, ferrugem=0.45, beiral_oitao=0.36)
    chapas_na_placa(
        rec,
        "tel",
        -L / 2 - 0.36,
        L / 2 + 0.36,
        lambda lado, k: 0.95 if (k * 3 + lado) % 5 == 0 else 0.42,
    )
    # bancadas compridas (corredor de ~1,9 m entre elas) e carga
    bancada(rec, "banc_a", (-1.3, 1.62), 0, mats, comp=4.2, larg=0.85)
    bancada(rec, "banc_b", (1.6, -1.2), 0, mats, comp=3.6, larg=0.85)
    banco(rec, "banco", (-1.6, 0.88), 0, mats, comp=1.8)
    cesto(rec, "c_a", -2.4, 1.6, 0.86, 0.22, 0.26, mats, cheio=True, col=False, sem=1)
    cesto(rec, "c_b", 0.3, 1.62, 0.86, 0.18, 0.2, mats, col=False, sem=2)
    cesto(rec, "c_c", 2.5, -1.2, 0.86, 0.2, 0.24, mats, cheio=True, col=False, sem=3)
    pilha_sacos(rec, "sacos", 3.45, 1.55, 90, 3, 2, 2, mats, sem=5)
    for k, (x, y, r, a) in enumerate(((-3.75, -1.8, 0.32, 0.66), (-3.15, -1.95, 0.27, 0.5))):
        cesto(rec, f"cesto{k}", x, y, 0.0, r, a, mats, cheio=k == 0, sem=k + 10)
    saco(rec, "saco_b", 0.7, -1.2, 0.86, 8, mats, sem=31)
    rolo_corda(rec, "corda_a", (-4.3, -2.42, 1.55), mats, eixo="Y")
    rolo_corda(rec, "corda_b", (1.45, 2.42, 1.6), mats, R=0.17, eixo="Y")
    VC.camera(rec, (-4.1, -2.9, 2.0), (2.0, 1.1, 0.75))
    return rec


# =============================================================== 3. depósito elevado
def receita_exp_deposito():
    """Depósito de tábua e palha sobre esteios, com patamar, escada de mão (colisão em rampa),
    porta e sacos por dentro."""
    rec = V.Receita()
    mats = Mats(63)
    Hp = 1.1
    L, W, H, esp, hr = 3.2, 3.0, 2.62, 0.07, 4.3
    van = V.mat_tabua("van")
    palha = V.mat_tranh("tranh")
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        van,
        [{"lado": "frente", "t": 0.25, "estilo": "tabua", "folha": 1}],
        [{"lado": "dir", "t": 0.0, "w": 0.7, "z0": 1.15, "z1": 1.75, "estilo": "tre"}],
        col="Wood",
        sem=63,
        nen_rets=[],
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        hr,
        0.34,
        "2aguas",
        "tranh",
        0.22,
        palha,
        mats,
        beiral_oitao=0.28,
        sem=63,
        mat_oitao=van,
        oitao_esp=esp,
        col_oitao="Wood",
    )
    pilha_sacos(rec, "sacos_a", -0.55, 1.05, 0, 3, 2, 3, mats, z=PISO, sem=2)
    pilha_sacos(rec, "sacos_b", 1.15, -0.1, 90, 2, 2, 2, mats, z=PISO, sem=20)
    cesto(rec, "cesto", -1.12, -0.95, PISO, 0.27, 0.52, mats, cheio=True, sem=4)
    rec.transformar(marca, V.lugar((0.0, 0.0, Hp)))
    z = Hp + PISO
    yv = -W / 2 - 1.25  # beira do patamar
    E.piso_tabuas(
        rec, "piso", -L / 2 - 0.05, -W / 2, L / 2 + 0.05, W / 2, z, mats, largura=0.36, sem=1
    )
    E.piso_tabuas(
        rec, "patamar", -L / 2 - 0.05, yv, L / 2 + 0.05, -W / 2, z, mats, largura=0.36, sem=2
    )
    E.barrotes(rec, "barrote", -L / 2, yv, L / 2, W / 2, z, mats, passo=1.05)
    E.pilotis(
        rec,
        "esteio",
        [(x, y) for x in (-L / 2, 0.0, L / 2) for y in (yv + 0.06, -W / 2, W / 2)],
        z - 0.14,
        mats,
        r=0.1,
    )
    for k, y in enumerate((yv + 0.06, -W / 2, W / 2)):
        rec.add(
            V.viga(
                f"madre{k}",
                (-L / 2 - 0.08, y, z - 0.27),
                (L / 2 + 0.08, y, z - 0.27),
                0.1,
                0.13,
                mats.go_escuro,
            ),
            "Casa",
            "Estrutura",
        )
    # guarda-corpo do patamar, com a passagem da escada no lado -X
    E.guarda_corpo(rec, "gc_frente", (-L / 2, yv + 0.03), (L / 2, yv + 0.03), z, mats, passo=0.8)
    E.guarda_corpo(rec, "gc_dir", (L / 2, yv + 0.03), (L / 2, -W / 2), z, mats, passo=0.8)
    # escada de mão: sobe em X até a ponta do patamar
    ym = (yv - W / 2) / 2
    # a base da rampa fica em 0,1 (a colisão tem 0,1 de espessura e não desce abaixo do chão)
    E.escada(
        rec, "escada", (-L / 2 - 1.42, ym, 0.1), (-L / 2 - 0.02, ym, z), 0.98, mats, corrimao=False
    )
    cesto(rec, "cesto_b0", 0.75, 0.55, 0.0, 0.3, 0.6, mats, sem=8)
    cesto(rec, "cesto_b1", -0.2, 0.25, 0.0, 0.26, 0.48, mats, cheio=True, sem=9)
    VC.camera(rec, (0.55, -1.15, z + 1.55), (-0.5, 1.1, z + 0.55))
    return rec


# =============================================================== 4. casa verde
def receita_exp_casa_verde():
    """Casa simples de reboco verde desbotado sobre embasamento de pedra: telha remendada com
    uma chapa, varanda de colunas com degraus, portas e janelas de madeira, jarras e 2 ambientes."""
    rec = V.Receita()
    mats = Mats(64)
    Hp = 0.30
    L, W, H, esp, hr = 7.4, 5.0, 3.3, 0.18, 5.1
    yv = -W / 2 - 1.7  # beira da varanda
    cal = V.mat_vach_dat("vach_cal", cal="#d6cdb8", exposta=0.25)
    verde = mat_verde("reboco_verde")
    ngoi = V.mat_ngoi("ngoi")
    van = V.mat_tabua("van")
    jan = {"w": 0.95, "z0": 1.12, "z1": 2.05, "estilo": "grade"}
    marca = rec.marca()
    lados, vaos = VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        cal,
        [
            {"lado": "frente", "t": -0.4, "estilo": "folhas"},
            {"lado": "fundo", "t": 2.0, "estilo": "tabua", "folha": -1},
        ],
        [
            {"lado": "frente", "t": -2.45, **jan},
            {"lado": "frente", "t": 2.05, **jan},
            {"lado": "fundo", "t": -1.8, **jan},
            {"lado": "esq", "t": 0.0, **jan},
            {"lado": "dir", "t": 0.0, **jan},
        ],
        col="Earth",
        sem=64,
        nen_rets=[(-L / 2 - 0.2, yv, L / 2 + 0.2, W / 2 + 0.2)],
    )
    peles(rec, "pele", lados, vaos, H, verde)
    venezianas(rec, "ven_a", lados["frente"], -2.45, 0.95, 1.12, 2.05, mats)
    venezianas(rec, "ven_b", lados["frente"], 2.05, 0.95, 1.12, 2.05, mats)
    div = V.Lado((0.9, -W / 2 + esp), math.pi / 2, W - 2 * esp, 0.1, 1.0)
    V.parede(
        rec,
        "divisoria",
        div,
        0.0,
        H,
        cal,
        [(3.05, 1.12, -1.0, PISO + 2.36)],
        "Earth",
        "para",
        sem=65,
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        hr,
        0.45,
        "2aguas",
        "ngoi",
        0.12,
        ngoi,
        mats,
        beiral_oitao=0.38,
        sem=64,
        tesouras=(-1.6, 1.6),
        mat_oitao=van,
        oitao_esp=0.08,
        col_oitao="Wood",
    )
    # remendo de chapa na água da frente
    s = (hr - (H + 0.05)) / (W / 2)
    xa, xb, ya, yb = -3.45, -1.55, -2.72, -0.62
    chapa = mat_chapa_placa("chapa_remendo", xa, (xb - xa) / 2, [0.42, 0.68])
    z0, z1 = hr - s * abs(ya) + 0.08, hr - s * abs(yb) + 0.08
    rec.add(
        E.placa_lisa(
            "remendo_placa", (xa, ya, z0), (xb, ya, z0), (xb, yb, z1), (xa, yb, z1), chapa
        ),
        "Telhado",
        "Telhado",
    )
    V.agua_unica(
        rec,
        "var",
        -L / 2 - 0.2,
        L / 2 + 0.2,
        -W / 2 - 0.02,
        3.0,
        -W / 2 - 1.85,
        2.74,
        0.1,
        "ngoi",
        ngoi,
        mats,
        sem=641,
        postes=(-3.55, -1.3, 0.5, 3.55),
        mat_poste=mats.go_escuro,
    )
    # sala (x < 0,9): altar, mesa, arca; quarto (x > 0,9): catre, arca, potes
    yi = W / 2 - esp
    V.ban_tho(rec, "altar", (-1.5, yi - 0.36), 0, mats)
    V.ban_thap(rec, "mesa", (-2.0, -0.5), 0, mats)
    V.ruong(rec, "arca", (0.32, 1.1), 90, mats)
    V.potes(rec, "lu", [(-3.2, 1.9), (-3.2, 1.35)], mats, sem=65)
    V.phan(rec, "phan", (2.55, -1.42), 0, mats)
    V.ruong(rec, "arca2", (3.25, 0.65), 90, mats)
    V.nonla_pendurado(rec, "nonla", (-0.3, yi), 0, mats)
    # varanda
    V.jarro_agua(rec, "jarra_a", (-3.1, yv + 0.42), mats, z=PISO)
    V.jarro_agua(rec, "jarra_b", (3.1, yv + 0.42), mats, z=PISO)
    cesto(rec, "cesto_v", -2.3, -W / 2 - 0.38, PISO, 0.27, 0.42, mats, sem=6)
    banco(rec, "banco_v", (2.05, -W / 2 - 0.3), 0, mats, comp=1.5, z=PISO)
    rec.transformar(marca, V.lugar((0.0, 0.0, Hp)))
    # embasamento de pedra e degraus (a colisão dos degraus é uma rampa)
    x0, x1, y0, y1 = -L / 2 - 0.25, L / 2 + 0.25, yv - 0.05, W / 2 + 0.25
    dim = (x1 - x0, y1 - y0, Hp)
    c = ((x0 + x1) / 2, (y0 + y1) / 2, Hp / 2)
    rec.add(V.bloco("plinto", dim, c, mats.pedra, chanfro=0.02), "Casa", "Piso")
    rec.caixa("plinto", c, dim, "para", "Concrete")
    xd, ld = -0.4, 2.0
    for k, (ya_, yb_, h) in enumerate(((y0 - 0.62, y0 - 0.31, 0.16), (y0 - 0.31, y0, 0.31))):
        d = (ld, yb_ - ya_, h)
        rec.add(
            V.bloco(f"degrau{k}", d, (xd, (ya_ + yb_) / 2, h / 2), mats.pedra, chanfro=0.015),
            "Casa",
            "Piso",
        )
    a, b = xd - ld / 2, xd + ld / 2
    rec.prisma(
        "degraus_rampa",
        [
            (a, y0 - 0.64, 0.0),
            (b, y0 - 0.64, 0.0),
            (a, y0 + 0.02, Hp + PISO),
            (b, y0 + 0.02, Hp + PISO),
            (a, y0 + 0.02, 0.0),
            (b, y0 + 0.02, 0.0),
        ],
        "para",
        "Concrete",
    )
    VC.camera(rec, (0.6, -1.65, Hp + PISO + 1.6), (-2.4, 1.7, Hp + PISO + 0.75))
    return rec


# =============================================================== 5. ruína
def receita_exp_ruina():
    """Casa queimada: paredes de tijolo e reboco enegrecidas com partes caídas, vigas
    carbonizadas, um pedaço do telhado ainda em pé e entulho. Portas e brechas passáveis."""
    rec = V.Receita()
    mats = Mats(65)
    L, W, esp = 7.8, 5.6, 0.24
    queim = mat_queimado("queimado")
    carvao = mat_carvao("carvao")
    ngoi = V.mat_ngoi("ngoi", telha="#7d4c37", escuro="#3c2a22", claro="#94603f")
    V.nen(rec, "nen", -L / 2 - 0.15, -W / 2 - 0.15, L / 2 + 0.15, W / 2 + 0.15, mats)
    lados = V.lados_ret(0.0, 0.0, L, W, esp)
    fr, fu_, es, di = lados["frente"], lados["fundo"], lados["esq"], lados["dir"]
    # frente: porta com verga em u 1,55..2,75 e brecha em u 4,7..6,2
    for i, (a, b, h0, h1) in enumerate(
        (
            (0.0, 0.85, 2.55, 2.85),
            (0.85, 1.55, 2.85, 2.72),
            (2.75, 3.7, 2.78, 2.6),
            (3.7, 4.7, 2.6, 1.5),
            (6.2, 7.0, 1.3, 2.45),
            (7.0, 7.8, 2.45, 2.72),
        )
    ):
        trecho(rec, f"fr{i}", fr, a, b, h0, h1, queim, sem=1.0)
    trecho(rec, "fr_verga", fr, 1.55, 2.75, 2.76, 2.72, queim, z0=2.5, sem=1.0)
    p = fr.ponto(2.15, 0.0, PISO)
    registrar_porta(rec, "porta_frente", (p.x, p.y, PISO), 1.2, 2.35, (0, -1, 0))
    p = fr.ponto(5.45, 0.0, PISO)
    registrar_porta(rec, "brecha_frente", (p.x, p.y, PISO), 1.5, 2.6, (0, -1, 0))
    # fundo: janela em u 1,6..2,4 e vão de porta caído em u 5,1..6,4
    for i, (a, b, h0, h1, z0) in enumerate(
        (
            (0.0, 1.6, 2.4, 2.75, 0.0),
            (1.6, 2.4, 1.0, 1.0, 0.0),
            (1.6, 2.4, 2.62, 2.75, 1.78),
            (2.4, 3.6, 2.75, 2.2, 0.0),
            (3.6, 5.1, 2.2, 1.05, 0.0),
            (6.4, 7.8, 2.3, 2.6, 0.0),
        )
    ):
        trecho(rec, f"fu{i}", fu_, a, b, h0, h1, queim, z0=z0, sem=2.0)
    p = fu_.ponto(5.75, 0.0, PISO)
    registrar_porta(rec, "brecha_fundo", (p.x, p.y, PISO), 1.3, 2.6, (0, 1, 0))
    # esquerda: quase toda caída, com brecha em u 1,9..3,2
    for i, (a, b, h0, h1) in enumerate(
        ((0.0, 0.9, 2.3, 1.15), (0.9, 1.9, 1.15, 0.55), (3.2, 4.2, 0.7, 1.6), (4.2, 5.12, 1.6, 2.4))
    ):
        trecho(rec, f"es{i}", es, a, b, h0, h1, queim, sem=3.0)
    p = es.ponto(2.55, 0.0, PISO)
    registrar_porta(rec, "brecha_esq", (p.x, p.y, PISO), 1.3, 2.6, (-1, 0, 0))
    # direita: em pé, com a janela
    for i, (a, b, h0, h1, z0) in enumerate(
        (
            (0.0, 2.15, 2.6, 2.78, 0.0),
            (2.15, 2.95, 1.0, 1.0, 0.0),
            (2.15, 2.95, 2.7, 2.72, 1.78),
            (2.95, 5.12, 2.72, 2.42, 0.0),
        )
    ):
        trecho(rec, f"di{i}", di, a, b, h0, h1, queim, z0=z0, sem=4.0)
    # tesouras e vigas carbonizadas (o que sobrou)
    zr = 4.05

    def viga(nome, a, b, lg=0.13, h=0.15):
        rec.add(V.viga(nome, a, b, lg, h, carvao), "Mobilia", "Mobilia")

    # cada tesoura fica onde as duas paredes ainda chegam à altura da linha (2,4 m ou mais)
    for k, x in enumerate((-2.9, -0.8, 3.2)):
        viga(f"linha{k}", (x, -W / 2 + 0.1, 2.5), (x, W / 2 - 0.1, 2.5), 0.14, 0.17)
        viga(f"rei{k}", (x, 0, 2.5), (x, 0, zr - 0.05), 0.12, 0.12)
        for s in (-1, 1):
            if k == 0 and s == -1:
                viga("perna_que", (x, s * 2.65, 2.62), (x + 0.18, s * 1.25, 3.25))
                continue
            viga(f"perna{k}{s}", (x, s * 2.65, 2.62), (x, 0, zr))
    viga("cumeeira", (-3.35, 0, zr), (3.5, 0, zr), 0.14, 0.15)
    for k, (s, t, xa, xb) in enumerate(
        ((1, 0.5, -3.5, 3.45), (-1, 0.5, -0.95, 3.45), (1, 0.15, -0.95, 3.5))
    ):
        y = s * 2.65 * (1 - t)
        z = 2.62 + (zr - 2.62) * t + 0.08
        viga(f"terca{k}", (xa, y, z), (xb, y, z), 0.09, 0.1)
    for k, (x, s, t) in enumerate(
        ((-1.4, 1, 0.8), (-2.0, -1, 1.0), (3.55, -1, 0.7), (3.55, 1, 0.9))
    ):
        p0 = Vector((x, s * 2.75, 2.66))
        p1 = p0.lerp(Vector((x, 0, zr + 0.02)), t)
        viga(f"caibro{k}", tuple(p0), tuple(p1), 0.07, 0.08)
    # viga que caiu, apoiada na parede do fundo e no chão (com colisão inclinada)
    a, b = Vector((-1.15, 2.5, 2.2)), Vector((-1.75, 0.55, PISO + 0.08))
    viga("caida", tuple(a), tuple(b), 0.16, 0.18)
    rec.prisma(
        "caida",
        [
            tuple(q + Vector((dx, 0, dz)))
            for q in (a, b)
            for dx in (-0.1, 0.1)
            for dz in (-0.1, 0.1)
        ],
        "para",
        "Wood",
    )
    a, b = (1.25, -0.95, PISO + 0.09), (2.9, -0.35, PISO + 0.09)
    viga("chao", a, b, 0.18, 0.17)
    rec.caixa(
        "chao",
        ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, PISO + 0.09),
        (1.76, 0.2, 0.18),
        "para",
        "Wood",
        rot_z=math.atan2(b[1] - a[1], b[0] - a[0]),
    )
    # pedaço do telhado que resistiu, na água de trás do lado +X
    A = (1.65, W / 2 + 0.35, 2.48)
    Bb = (L / 2 + 0.05, W / 2 + 0.35, 2.48)
    Cc = (L / 2 + 0.05, 0.95, 3.56)
    D = (1.65, 0.95, 3.56)
    ob, nrm = V.placa("telha", A, Bb, Cc, D, 0.1, "ngoi", ngoi, sem=650)
    rec.add(ob, "Telhado", "Telhado")
    V._prisma_placa(rec, "telha", [A, Bb, Cc, D], nrm, 0.06, "para", "Tile")
    # entulho (corredores de pelo menos 1,2 m ligando as aberturas)
    entulho(rec, "ent_a", -2.85, 1.65, 0.8, 0.72, 0.42, queim, PISO, 1, 7, monte=carvao)
    entulho(rec, "ent_b", 3.0, 1.45, 0.62, 0.62, 0.34, queim, PISO, 2, 6, monte=carvao)
    entulho(rec, "ent_c", -3.05, -1.8, 0.62, 0.6, 0.3, queim, PISO, 3, 5, monte=carvao)
    entulho(
        rec, "ent_d", 3.25, -2.05, 0.42, 0.42, 0.22, carvao, z=PISO, sem=4, tijolos=3, col=False
    )
    # entulho que caiu para fora, ao pé das partes baixas (baixo, sem bloquear as brechas)
    entulho(rec, "ent_f", 1.15, -W / 2 - 0.36, 0.42, 0.25, 0.14, queim, 0.0, 5, 3, False, carvao)
    entulho(rec, "ent_g", -L / 2 - 0.3, -1.45, 0.24, 0.5, 0.14, queim, 0.0, 6, 2, False, carvao)
    VC.camera(rec, (0.1, -2.1, PISO + 1.65), (-1.0, 1.9, PISO + 0.9))
    return rec


# =============================================================== 6. comporta
def _volante(rec, nome, x, y, z, R, mats):
    """Volante de ferro horizontal (só visual)."""
    aro = M.toro(f"{nome}_aro", R, 0.024, 16, 4)
    V.gravar_uv_local(aro, lambda p: (p.x, p.y, p.z))
    M.material(aro, mats.ferro)
    o = [M.suave(aro, 50)]
    for k in range(3):
        a = k * math.pi / 3 + 0.3
        d = Vector((math.cos(a) * R, math.sin(a) * R, 0.0))
        o.append(V.viga(f"{nome}_r{k}", -d, d, 0.028, 0.028, mats.ferro))
    o.append(V.cilindro(f"{nome}_cubo", 0.06, 0.09, (0, 0, 0), mats.ferro, segs=8))
    for ob in o:
        M.mover(ob, Matrix.Translation((x, y, z)))
    rec.addv(o, "Casa", "Anexos")


def receita_exp_comporta():
    """Casa de manutenção de reboco ocre e telha cinza na margem norte, com cais, e a comporta de
    alvenaria que atravessa o canal: 3 pilares, 2 guilhotinas de tábuas, volantes de ferro (só
    visuais) e a passarela com corrimão de margem a margem em Y. Canal em Y de -3,4 a 0."""
    rec = V.Receita()
    mats = Mats(66)
    y_s, y_n = -3.4, 0.0
    z_fundo, z_base = -1.2, -1.25
    z_deck = 0.12
    xs = 2.7
    # --- casa
    L, W, H, esp, hr = 4.8, 2.6, 2.85, 0.18, 4.05
    cx, cy = -2.75, 1.98
    dentro = V.mat_gach("gach", exposto=0.2)
    ocre = mat_ocre("reboco_ocre", exposto=0.9)
    cinza = V.mat_ngoi("ngoi_cinza", telha="#5b5f60", escuro="#3d4042", claro="#787c7c")
    lados, vaos = VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        dentro,
        [{"lado": "frente", "t": -1.2, "estilo": "tabua", "folha": -1}],
        [
            {"lado": "frente", "t": 0.75, "w": 1.25, "z0": 1.1, "z1": 2.0, "estilo": "grade"},
            {"lado": "dir", "t": 0.0, "w": 0.8, "z0": 1.15, "z1": 1.9, "estilo": "grade"},
        ],
        col="Brick",
        cx=cx,
        cy=cy,
        sem=66,
        nen_rets=[(cx - L / 2 - 0.12, cy - W / 2 - 0.12, cx + L / 2 + 0.12, cy + W / 2 + 0.12)],
    )
    peles(rec, "pele", lados, vaos, H, ocre)
    oitao_reboco(rec, "oitao", L, W, H, hr - 0.06, ocre, esp, cx, cy)
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        hr,
        0.18,
        "2aguas",
        "ngoi",
        0.1,
        cinza,
        mats,
        beiral_oitao=0.28,
        sem=66,
        tesouras=(0.0,),
        m_lugar=V.lugar((cx, cy, 0.0)),
    )
    yi = cy + W / 2 - esp
    bancada(rec, "bancada", (cx + 0.95, yi - 0.34), 0, mats, comp=2.3, larg=0.62, z=PISO)
    V.ferramentas(rec, "ferr", (cx - 2.0, yi - 0.02), 0, mats, itens=("enxada", "ancinho", "foice"))
    pilha_sacos(rec, "sacos", cx + 1.75, cy - 0.55, 90, 2, 1, 2, mats, z=PISO, sem=3)
    cesto(rec, "cesto", cx - 1.95, cy - 0.72, PISO, 0.27, 0.46, mats, sem=6)
    # --- cais da margem norte (o corredor em frente da casa)
    xa, xb = -5.4, xs - 1.1
    xm, lq = (xa + xb) / 2, xb - xa
    d = (lq, 0.62, 0.14)
    c = (xm, -0.31, -0.05)
    rec.add(V.bloco("cais_laje", d, c, mats.pedra, chanfro=0.012), "Casa", "Piso")
    rec.caixa("cais_laje", c, d, "para", "Concrete")
    d = (lq, 0.24, 1.18)
    c = (xm, -0.5, z_base + 0.59)
    rec.add(V.bloco("cais_muro", d, c, mats.pedra), "Casa", "Piso")
    rec.caixa("cais_muro", c, d, "para", "Concrete")
    E.guarda_corpo(rec, "gc_cais", (xa + 0.05, -0.56), (xb, -0.56), 0.02, mats, passo=1.1)
    # --- comporta: 3 pilares de alvenaria, com os ressaltos das guias acima do tabuleiro
    x0p, x1p = xs - 1.1, xs + 0.95
    xg = xs + 0.68  # plano das guilhotinas
    pilares = (y_s + 0.1, (y_s + y_n) / 2, y_n + 0.03)
    for k, y in enumerate(pilares):
        d = (x1p - x0p, 0.4, z_deck - 0.06 - z_base)
        c = ((x0p + x1p) / 2, y, (z_deck - 0.06 + z_base) / 2)
        rec.add(V.bloco(f"pilar{k}", d, c, mats.pedra, chanfro=0.015), "Casa", "Estrutura")
        rec.caixa(f"pilar{k}", c, d, "para", "Concrete")
        d = (x1p - xs - 0.47, 0.42, 1.0)
        c = ((xs + 0.47 + x1p) / 2, y, z_deck + 0.44)
        rec.add(V.bloco(f"guia{k}", d, c, mats.pedra, chanfro=0.015), "Casa", "Estrutura")
        rec.caixa(f"guia{k}", c, d, "para", "Concrete")
    # soleira de fundo (entre os pilares), abaixo da água
    ya_s, yb_s = y_s - 0.1, y_n + 0.23
    d = (x1p - x0p, yb_s - ya_s, 0.1)
    c = ((x0p + x1p) / 2, (ya_s + yb_s) / 2, z_fundo)
    rec.add(V.bloco("soleira", d, c, mats.pedra), "Casa", "Estrutura")
    # guilhotinas de tábua (a água passa por baixo), travessas, fusos e volantes
    van = V.mat_tabua("van")
    for k in range(2):
        y0, y1 = pilares[k] + 0.2, pilares[k + 1] - 0.2
        ym, ln = (y0 + y1) / 2, y1 - y0
        h = 1.45
        ob = V.peca(f"guilh{k}", (xg, y0), math.pi / 2, 0.0, ln, 0.0, h, -0.045, 0.045, van)
        M.mover(ob, Matrix.Translation((0, 0, -0.78)))
        rec.add(ob, "Casa", "Anexos")
        rec.caixa(f"guilh{k}", (xg, ym, -0.78 + h / 2), (0.09, ln, h), "para", "Wood")
        for j, z in enumerate((-0.68, -0.2, 0.28, 0.6)):
            rec.add(
                V.viga(
                    f"guilh{k}_t{j}",
                    (xg - 0.06, y0, z),
                    (xg - 0.06, y1, z),
                    0.04,
                    0.11,
                    mats.go_escuro,
                ),
                "Casa",
                "Anexos",
            )
        rec.add(
            V.viga(
                f"trave{k}", (xg, y0 - 0.2, 1.0), (xg, y1 + 0.2, 1.0), 0.2, 0.14, mats.go_escuro
            ),
            "Casa",
            "Anexos",
        )
        rec.add(
            V.tre(f"fuso{k}", (xg, ym, 0.62), (xg, ym, 1.42), 0.03, mats.ferro, segs=6),
            "Casa",
            "Anexos",
        )
        _volante(rec, f"vol{k}", xg, ym, 1.3, 0.3, mats)
    # passarela: tabuleiro de margem a margem, corrimãos com a saída para o cais aberta
    y0d, y1d = y_s - 0.1, y_n + 0.36
    E.piso_tabuas(rec, "deck", xs - 1.1, y0d, xs + 0.42, y1d, z_deck, mats, largura=0.34, sem=4)
    yg = y0d + 0.04  # o montante do corrimão não passa da ponta do tabuleiro
    E.guarda_corpo(rec, "gc_oeste", (xs - 1.07, yg), (xs - 1.07, -0.62), z_deck, mats, passo=0.95)
    E.guarda_corpo(rec, "gc_leste", (xs + 0.39, yg), (xs + 0.39, y1d), z_deck, mats, passo=0.95)
    VC.camera(rec, (cx - 1.6, cy - 0.7, PISO + 1.6), (cx + 1.4, cy + 0.65, PISO + 0.7))
    return rec


# =============================================================== 7. telheiro
def receita_exp_telheiro():
    """Abrigo de ferramentas em meia-água de chapa, com parede de tábuas no fundo, e um cercado
    de animais de bambu com cobertura de palha, cocho e portão aberto."""
    rec = V.Receita()
    mats = Mats(67)
    van = V.mat_tabua("van")
    palha = V.mat_tranh("tranh")
    x0, x1 = -3.3, 0.3
    yt, yf = 1.9, -1.9  # fundo (parede) e frente (aberta)
    fundo = V.Lado((x0, yt), 0.0, x1 - x0, 0.07, -1.0)
    V.parede(rec, "fundo", fundo, 0.0, 3.08, van, (), "Wood", "para", sem=67)
    esq = V.Lado((x0, yf + 0.9), math.pi / 2, yt - yf - 0.9, 0.06, -1.0)
    V.parede(rec, "lado", esq, 0.0, 1.3, van, (), "Wood", "para", sem=68)
    for k, x in enumerate((x0 + 0.05, (x0 + x1) / 2, x1 - 0.05)):
        V.poste(rec, f"p_f{k}", x, yf, 2.56, mats.go, r=0.08, base_pedra=mats.pedra)
    for k, x in enumerate((x0 + 0.05, x1 - 0.05)):
        V.poste(rec, f"p_b{k}", x, yt - 0.08, 3.05, mats.go, r=0.07)
    rec.add(
        V.viga("frechal", (x0 - 0.15, yf, 2.56), (x1 + 0.15, yf, 2.56), 0.11, 0.13, mats.go_escuro),
        "Casa",
        "Estrutura",
    )
    for k, x in enumerate((x0 + 0.05, x1 - 0.05)):
        rec.add(
            V.viga(f"caibro{k}", (x, yf - 0.1, 2.6), (x, yt, 3.1), 0.08, 0.11, mats.go),
            "Casa",
            "Estrutura",
        )
        rec.add(
            V.viga(f"mf{k}", (x, yf, 2.05), (x, yf + 0.65, 2.68), 0.06, 0.08, mats.go),
            "Casa",
            "Estrutura",
        )
    E.telhado_varanda(
        rec, "tel", x0 - 0.2, x1 + 0.2, yt + 0.02, 3.16, yf - 0.42, 2.62, mats, sem=67
    )
    chapas_na_placa(rec, "tel", x0 - 0.2, x1 + 0.2, lambda _lado, k: 0.2 if k == 1 else 0.92)
    bancada(rec, "bancada", (-0.85, 1.42), 0, mats, comp=2.0, larg=0.62)
    V.ferramentas(
        rec, "ferr", (-3.2, yt - 0.05), 0, mats, itens=("enxada", "ancinho", "foice"), z=0.03
    )
    cesto(rec, "c_a", -2.7, -0.25, 0.0, 0.3, 0.55, mats, cheio=True, sem=3)
    cesto(rec, "c_b", -2.85, 0.42, 0.0, 0.25, 0.42, mats, sem=4)
    cesto(rec, "c_c", -0.45, 1.4, 0.86, 0.17, 0.2, mats, col=False, sem=5)
    rolo_corda(rec, "corda", (x1 - 0.05, yf - 0.08, 1.7), mats)
    # cercado: cerca de bambu com o portão aberto no lado de -X
    a, b, c_, d_ = 0.85, 3.3, -1.7, 1.75
    V.cerca(
        rec,
        "cerca",
        [(a, -0.15), (a, d_), (b, d_), (b, c_), (a, c_), (a, -1.45), (a, -0.15)],
        mats,
        alt=1.1,
        portao=5,
    )
    registrar_porta(rec, "portao_cercado", (a, -0.8, 0.0), 1.2, 2.3, (-1, 0, 0))
    V.agua_unica(
        rec,
        "palha_c",
        a - 0.15,
        b + 0.12,
        d_ + 0.2,
        2.62,
        0.0,
        2.25,
        0.14,
        "tranh",
        palha,
        mats,
        sem=67,
    )
    for k, (x, y, z) in enumerate(((a, d_, 2.54), (b, d_, 2.54), (a, 0.1, 2.2), (b, 0.1, 2.2))):
        rec.add(
            V.tre(f"p_c{k}", (x, y, 0), (x, y, z), 0.05, mats.tre, segs=6, sem=k), "Casa", "Anexos"
        )
        rec.caixa(f"p_c{k}", (x, y, z / 2), (0.1, 0.1, z), "passa", "Bamboo")
    for k, y in enumerate((d_, 0.1)):
        z = 2.5 if k == 0 else 2.18
        rec.add(
            V.tre(f"t_c{k}", (a - 0.1, y, z), (b + 0.1, y, z), 0.04, mats.tre, segs=6),
            "Casa",
            "Anexos",
        )
    cocho = V.bloco("cocho", (1.3, 0.34, 0.24), (2.2, 1.42, 0.12), mats.go_escuro, chanfro=0.03)
    V.sem_fundo(cocho, 0.0)
    rec.add(cocho, "Casa", "Anexos")
    rec.caixa("cocho", (2.2, 1.42, 0.12), (1.3, 0.34, 0.24), "para", "Wood")
    feno = M.superelipsoide("feno", 0.62, 0.48, 0.22, 0.8, 0.9, 10, 5)
    M.deslocar(feno, lambda co, n: 0.04 * M.fbm(co * 6.0, 3, 9))
    V.apagar_faces(feno, lambda c, n: c.z < -0.02)
    achatar(feno)
    V.gravar_uv_local(feno, lambda p: (p.x, p.y, p.z))
    M.mover(feno, Matrix.Translation((2.55, 0.25, 0.0)))
    M.material(feno, mats.esteira)
    rec.add(M.suave(feno, 60), "Mobilia", "Mobilia")
    VC.camera(rec, (-0.55, -1.45, 1.7), (-2.5, 1.65, 0.8))
    return rec


# =============================================================== 8. pátio
def camada_graos(nome, x0, y0, x1, y1, z, mat, nx=10, ny=7, sem=0):
    """Grãos espalhados: uma grade com relevo baixo, que morre na borda."""

    def f(u, v):
        x = x0 + (x1 - x0) * u
        y = y0 + (y1 - y0) * v
        borda = min(1.0, 4.0 * min(u, 1 - u, v, 1 - v))
        h = borda * (0.03 + 0.022 * M.fbm(Vector((x * 1.5, y * 1.5, sem)), 3, sem))
        return (x, y, z + max(0.0, h))

    ob = V.grade(nome, f, nx, ny, fora=Vector((0, 0, 1)))
    V.gravar_uv_local(ob, lambda p: (p.x, p.y, p.z), float(sem))
    M.material(ob, mat)
    return M.suave(ob, 60)


def receita_exp_patio():
    """Conjunto de pátio, baixo: esteira de secar grãos com grãos, rodo de madeira, 2 bancos,
    carroça de mão, cestos e pilha de sacos. A esteira não tem colisão (dá para pisar)."""
    rec = V.Receita()
    mats = Mats(68)
    graos = mat_graos("graos")
    x0, x1, y0, y1 = -2.75, 1.45, -1.2, 1.9
    est = V.bloco(
        "esteira",
        (x1 - x0, y1 - y0, 0.02),
        ((x0 + x1) / 2, (y0 + y1) / 2, 0.012),
        mats.esteira,
    )
    V.sem_fundo(est, 0.002)
    rec.add(est, "Casa", "Piso")
    for k, (a, b) in enumerate(
        (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0)))
    ):
        rec.add(
            V.tre(f"borda{k}", (*a, 0.022), (*b, 0.022), 0.022, mats.tre, segs=5),
            "Casa",
            "Piso",
        )
    rec.add(
        camada_graos("graos", x0 + 0.1, y0 + 0.1, x1 - 0.1, y1 - 0.1, 0.027, graos, sem=4),
        "Mobilia",
        "Mobilia",
    )
    # rodo de madeira largado sobre a esteira
    a, b = Vector((-0.1, 0.1, 0.075)), Vector((1.75, -0.75, 0.33))
    rec.add(V.tre("rodo_cabo", tuple(a), tuple(b), 0.018, mats.go, segs=6), "Casa", "Anexos")
    ang = math.atan2((b - a).y, (b - a).x) + math.pi / 2
    rec.add(
        V.bloco("rodo_lamina", (0.66, 0.035, 0.11), tuple(a), mats.go_escuro, rot=(0.0, 0.0, ang)),
        "Casa",
        "Anexos",
    )
    banco(rec, "banco_a", (-1.0, -2.45), 4, mats, comp=2.0)
    banco(rec, "banco_b", (3.35, 2.1), 82, mats, comp=1.7)
    carroca(rec, "carroca", (2.75, -1.25), -32, mats)
    pilha_sacos(rec, "sacos", -3.3, -1.95, 90, 3, 2, 2, mats, sem=6)
    for k, (x, y, r, a_, ch) in enumerate(
        (
            (-3.55, 1.1, 0.32, 0.56, True),
            (-3.42, 1.85, 0.27, 0.46, False),
            (-3.6, 2.5, 0.22, 0.34, True),
            (1.2, 2.55, 0.25, 0.4, True),
        )
    ):
        cesto(rec, f"cesto{k}", x, y, 0.0, r, a_, mats, cheio=ch, sem=k + 3)
    VC.camera(rec, (-0.4, -3.0, 2.3), (0.0, 0.7, 0.1))
    return rec


# =============================================================== 9. passarela
def receita_exp_passarela():
    """Passarela de tábuas sobre apoios de madeira, 9 × 1,5 m, levemente arqueada: pontas em
    Z = 0,15, vão central plano em Z = 0,62. Colisão: 2 rampas e o vão central. Os apoios do
    meio descem até o fundo do canal (Z = -1,2)."""
    rec = V.Receita()
    mats = Mats(69)
    X, Yd = 4.48, 0.68  # as tábuas inclinadas passam 1 cm da ponta: a pegada fica em 9 m
    z_ponta, z_meio, x_meio = 0.15, 0.62, 1.9
    incl = math.atan2(z_meio - z_ponta, X - x_meio)

    def zt(x):
        ax = abs(x)
        if ax <= x_meio:
            return z_meio
        return z_ponta + (z_meio - z_ponta) * (X - ax) / (X - x_meio)

    # tábuas (atravessadas, com pequenas diferenças)
    n = 33
    passo = 2 * X / n
    for k in range(n):
        x = -X + (k + 0.5) * passo
        ang = 0.0 if abs(x) <= x_meio else (-incl if x < 0 else incl)
        desl = 0.03 * math.sin(k * 2.7)
        rec.add(
            V.bloco(
                f"tab{k}",
                (passo - 0.012, 2 * Yd + 0.05 * math.sin(k * 1.3), 0.05),
                (x, desl, zt(x) - 0.025),
                mats.go if k % 3 else mats.go_escuro,
                rot=(0.0, ang, 0.0),
            ),
            "Casa",
            "Piso",
        )
    # longarinas e colisão: duas rampas e o vão plano
    pts = [(-X, z_ponta), (-x_meio, z_meio), (x_meio, z_meio), (X, z_ponta)]
    for j, y in enumerate((-0.52, 0.0, 0.52)):
        for k in range(3):
            (xa, za), (xb, zb) = pts[k], pts[k + 1]
            rec.add(
                V.viga(
                    f"long{j}{k}",
                    (xa, y, za - 0.12),
                    (xb, y, zb - 0.12),
                    0.09,
                    0.15,
                    mats.go_escuro,
                ),
                "Casa",
                "Estrutura",
            )
    for k in range(3):
        (xa, za), (xb, zb) = pts[k], pts[k + 1]
        cantos = [
            (x_, sy * Yd, z_ - dz)
            for (x_, z_) in ((xa, za), (xb, zb))
            for sy in (-1, 1)
            for dz in (0.0, 0.12)
        ]
        rec.prisma(f"tabuleiro{k}", cantos, "para", "Wood")
    # apoios: cavaletes nas margens e dentro do canal
    for i, (x, z_pe) in enumerate(((-3.3, -0.12), (-1.55, -1.2), (1.55, -1.2), (3.3, -0.12))):
        topo = zt(x) - 0.2
        for s in (-1, 1):
            c = (x, s * 0.56, (topo + z_pe) / 2)
            d = (0.15, 0.15, topo - z_pe)
            rec.add(V.bloco(f"ap{i}{s}", d, c, mats.go_escuro, chanfro=0.012), "Casa", "Estrutura")
            rec.caixa(f"ap{i}{s}", c, d, "para", "Wood")
        rec.add(
            V.viga(
                f"trav{i}", (x, -0.72, topo + 0.02), (x, 0.72, topo + 0.02), 0.14, 0.13, mats.go
            ),
            "Casa",
            "Estrutura",
        )
        if z_pe < -0.5:
            for s in (-1, 1):
                rec.add(
                    V.tre(
                        f"xis{i}{s}",
                        (x + 0.05, s * 0.56, z_pe + 0.1),
                        (x + 0.05, -s * 0.56, topo - 0.12),
                        0.035,
                        mats.tre,
                        segs=5,
                    ),
                    "Casa",
                    "Estrutura",
                )
    # corrimão de cada lado, seguindo o arco
    xs_c = (-4.3, -3.1, -1.9, -0.65, 0.65, 1.9, 3.1, 4.3)
    for s in (-1, 1):
        y = s * 0.7
        alt = 0.96
        for k, x in enumerate(xs_c):
            z = zt(x)
            rec.add(
                V.viga(
                    f"mont{s}_{k}", (x, y, z - 0.1), (x, y, z + alt), 0.06, 0.06, mats.go_escuro
                ),
                "Casa",
                "Estrutura",
            )
        for k in range(len(xs_c) - 1):
            xa, xb = xs_c[k], xs_c[k + 1]
            za, zb = zt(xa), zt(xb)
            for h, r in ((alt, 0.03), (alt * 0.52, 0.02)):
                rec.add(
                    V.tre(
                        f"corr{s}_{k}_{int(h * 100)}",
                        (xa, y, za + h),
                        (xb, y, zb + h),
                        r,
                        mats.tre,
                        segs=5,
                    ),
                    "Casa",
                    "Estrutura",
                )
            rec.prisma(
                f"corrimao{s}_{k}",
                [
                    (x_, y + sy * 0.04, z_ + h)
                    for x_, z_ in ((xa, za), (xb, zb))
                    for sy in (-1, 1)
                    for h in (0.0, 1.0)
                ],
                "passa",
                "Bamboo",
            )
    VC.camera(rec, (-4.2, -1.0, 1.75), (1.4, 0.15, 0.55))
    return rec


# =============================================================== 10. muro
def parede_degraus(nome, lado: V.Lado, alturas, passo, mat):
    """Parede de topo em degraus numa malha só: colunas separadas têm faces coincidentes entre si,
    e o bake sai preto nelas."""
    comp = passo * len(alturas)
    contorno = [(0.0, 0.0), (comp, 0.0)]
    for k in range(len(alturas) - 1, -1, -1):
        h = alturas[k]
        if k == len(alturas) - 1 or alturas[k + 1] != h:
            contorno.append(((k + 1) * passo, h))
        if k == 0 or alturas[k - 1] != h:
            contorno.append((k * passo, h))
    e = lado.esp / 2
    bm = bmesh.new()
    frente = [bm.verts.new((u, -e, z)) for u, z in contorno]
    tras = [bm.verts.new((u, e, z)) for u, z in contorno]
    bm.faces.new(frente)
    bm.faces.new(tras[::-1])
    for i in range(len(contorno)):
        j = (i + 1) % len(contorno)
        bm.faces.new((frente[i], tras[i], tras[j], frente[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    ob = M.de_bmesh(nome, bm)
    V.gravar_uv_local(ob, lambda p: (p.x, p.z, p.y))
    M.mover(ob, Matrix.Translation((lado.o[0], lado.o[1], 0.0)) @ Matrix.Rotation(lado.ang, 4, "Z"))
    M.material(ob, mat)
    return M.suave(ob, 35)


def receita_exp_muro():
    """Trecho de muro baixo de tijolo gasto, 4 × 0,45 × 0,9 m, com partes caídas."""
    rec = V.Receita()
    mats = Mats(70)
    tijolo = mat_tijolo("tijolo_gasto")
    esp = 0.40
    lado = V.Lado((-2.0, 0.0), 0.0, 4.0, esp, 1.0)
    d = (4.0, 0.45, 0.1)
    c = (0.0, 0.0, 0.05)
    base = V.bloco("base", d, c, mats.pedra, chanfro=0.018)
    V.sem_fundo(base, 0.0)
    rec.add(base, "Casa", "Piso")
    rec.caixa("base", c, d, "para", "Concrete")
    perfil = (
        (0.0, 0.5, 0.34, 0.62),
        (0.5, 1.3, 0.62, 0.84),
        (1.3, 1.85, 0.84, 0.46),
        (1.85, 2.45, 0.26, 0.2),
        (2.45, 3.2, 0.48, 0.86),
        (3.2, 3.62, 0.86, 0.66),
        (3.62, 4.0, 0.66, 0.34),
    )
    rr = np.random.default_rng(70)
    for i, (a, b, h0, h1) in enumerate(perfil):
        colisao_trecho(rec, f"m{i}", lado, a, b, h0, h1)

    def topo(u):
        for a, b, h0, h1 in perfil:
            if a <= u <= b:
                return h0 + (h1 - h0) * (u - a) / (b - a)
        return perfil[-1][3]

    # o visual sobe em degraus de tijolo; o topo cai no meio de uma fiada (sem listra de argamassa)
    fiada = 0.065
    n = round(4.0 / 0.22)
    passo = 4.0 / n
    alturas = []
    for k in range(n):
        h = topo((k + 0.5) * passo) + 0.05 * math.sin(k * 2.3)
        alturas.append((min(13, max(2, math.floor(h / fiada))) + 0.5) * fiada)
    rec.add(parede_degraus("muro", lado, alturas, passo, tijolo), "Mobilia", "Mobilia")
    for k, h in enumerate(alturas):
        u0, u1 = k * passo, (k + 1) * passo
        if rr.random() < 0.6 or h > 0.84:
            continue
        # tijolo solto: cabe inteiro no topo da coluna (encostar na vizinha sai preto no bake)
        q = lado.ponto((u0 + u1) / 2, float(rr.uniform(-0.05, 0.05)), h + 0.025)
        rec.add(
            V.bloco(
                f"f{k}",
                (0.18, 0.1, 0.06),
                tuple(q),
                tijolo,
                rot=(0.0, 0.0, float(rr.uniform(-0.2, 0.2))),
            ),
            "Mobilia",
            "Mobilia",
        )
    VC.camera(rec, (-1.6, -2.4, 1.2), (0.3, 0.0, 0.35))
    return rec


# =============================================================== catálogo
_FONTES = ["navy67", "dono"]

CASAS: dict[str, dict] = {
    "exp_celeiro": {
        "nome": "celeiro do Arrozal",
        "tipo": "reboco ocre com enxaimel, chapa remendada, portão largo e interior de depósito",
        "fontes": _FONTES,
        "atlas": ATLAS_CELEIRO,
    },
    "exp_galpao": {
        "nome": "telheiro aberto de trabalho",
        "tipo": "pilares de madeira, cobertura de chapa, bancadas, cestos e sacos",
        "fontes": _FONTES,
        "atlas": ATLAS_PEQUENO,
    },
    "exp_deposito": {
        "nome": "depósito elevado",
        "tipo": "tábua e palha sobre esteios, escada de mão, sacos por dentro",
        "fontes": _FONTES,
        "atlas": ATLAS_PEQUENO,
    },
    "exp_casa_verde": {
        "nome": "casa verde",
        "tipo": "reboco verde desbotado, telha remendada, varanda, 2 ambientes",
        "fontes": _FONTES,
        "atlas": ATLAS_CASA,
    },
    "exp_ruina": {
        "nome": "casa queimada",
        "tipo": "tijolo e reboco enegrecidos, vigas carbonizadas, entulho",
        "fontes": _FONTES,
        "atlas": ATLAS_CASA,
    },
    "exp_comporta": {
        "nome": "comporta e casa de manutenção",
        "tipo": "reboco ocre, telha cinza, alvenaria, guilhotinas, volantes e passarela",
        "fontes": _FONTES,
        "atlas": ATLAS_CASA,
    },
    "exp_telheiro": {
        "nome": "abrigo de ferramentas e cercado",
        "tipo": "meia-água de chapa, parede de tábuas, cercado de bambu com palha",
        "fontes": _FONTES,
        "atlas": ATLAS_PEQUENO,
    },
    "exp_patio": {
        "nome": "conjunto de pátio",
        "tipo": "esteira com grãos, rodo, bancos, carroça, cestos e sacos",
        "fontes": _FONTES,
        "atlas": ATLAS_PEQUENO,
    },
    "exp_passarela": {
        "nome": "passarela de pedestres",
        "tipo": "tábuas e corrimão sobre apoios de madeira, levemente arqueada",
        "fontes": _FONTES,
        "atlas": ATLAS_PEQUENO,
    },
    "exp_muro": {
        "nome": "muro baixo de tijolo",
        "tipo": "tijolo gasto com partes caídas",
        "fontes": _FONTES,
        "atlas": ATLAS_PEQUENO,
    },
}
