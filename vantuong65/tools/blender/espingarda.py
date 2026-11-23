"""Espingarda calibre 12 do VẠN TƯỜNG '65 (2026-11-13, pedido do dono: "faça a arma doze também").

A escolha é da frente de classes (tools/blender/ESPINGARDA.txt): Winchester Model 12 "Trench Gun"
(versão da Segunda Guerra), a espingarda dos fuzileiros na Coreia e no começo do Vietnã. Chave
`win12` (Shared/Weapons, AssetIds.Models, WeaponArt).

Modela no Blender e assa as texturas PBR com os mesmos materiais e o mesmo bake das outras armas do
Blender (tools/blender/armas.py, tools/faca), num atlas único de 1024 px:
- nogueira (coronha e telha com sulcos), aço fosfatizado fosco (caixa da culatra, cano, depósito,
  capa de calor perfurada com 4 fileiras de furos, adaptador de baioneta M1917), latão (conta de
  mira e cartucho M19);
- janela de ejeção na DIREITA da caixa da culatra e portinhola de carga EMBAIXO (bolsões de 5 a
  6 mm, com o fundo escuro), feitas com booleano exato do Blender.

Peças (nós do GLB; cada uma vira uma MeshPart no Roblox, com o nome do nó):
- "Arma": a arma inteira (a maior peça: o GunModel.fit põe nela os pontos);
- "Telha": a telha de nogueira com a luva de aço da ação e a barra da ação (corre no eixo do
  depósito: pontos `pump` e `pumpM`);
- "Culatra": a face do ferrolho vista na janela de ejeção (recua junto com a telha);
- "Gatilho": a lâmina do gatilho (gira em volta do pino, ponto `trigger`);
- "Cartucho": cartucho de latão M19 de 2 3/4 pol., guardado DENTRO do depósito (invisível): a
  animação de carga e o estojo ejetado usam cópias dele nos pontos `load` e `eject`.

Convenções (as de armas.py): metros, eixo do cano no eixo Y do Blender com a boca em -Y, Z para
cima, direita do atirador em -X (+X no Roblox). `pontos.json` em studs no referencial local da
MeshPart "Arma" (o importador gira o GLB 180° em Y e centra a peça na caixa dos vértices do nó),
relendo o GLB exportado. O tools/weapon_landmarks.py lê este arquivo; a mira (conta) é medida na
malha pelo tools/sight_align.py.

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/espingarda.py -- win12
    ... -- win12 --previa      (só a prévia do GLB exportado: assets/blender/arma_win12/_previa.png)

Medidas: as com fonte estão em `FONTES`; o resto é PLACEHOLDER (desenho de fotos, sem planta).
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
from mathutils import Matrix, Vector

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(RAIZ / "tools" / "faca"))
import armas  # noqa: E402
import comum  # noqa: E402
import materiais  # noqa: E402
import produzir as faca  # noqa: E402

M_POR_STUD = 0.28
CHAVE = "win12"
PASTA = "arma_win12"
MAT_MADEIRA, MAT_ACO, MAT_LATAO, MAT_ESCURO = 0, 1, 2, 3
NOS = ("Arma", "Telha", "Culatra", "Gatilho", "Cartucho")

FONTES = {
    "comprimento_total_m": "1.003 (39,5 pol.: modernfirearms.net, via ESPINGARDA.txt)",
    "comprimento_cano_m": "0.508 (20 pol., cilíndrico: modernfirearms.net)",
    "deposito": "6 + 1 na câmara (Wikipedia, Winchester Model 1912)",
    "capa_de_calor": "aço perfurado sobre ~3/4 do cano, 4 fileiras de furos (Wikipedia)",
    "ejecao_carga": "ejeção à direita, carga por baixo (ESPINGARDA.txt)",
    "cartucho": "M19 de latão, 12 x 2 3/4 pol. (American Rifleman, via ESPINGARDA.txt)",
    "puxada_m": "0.090 (PLACEHOLDER: o arquivo da frente de classes diz ~10 cm)",
    "comprimento_ate_gatilho_m": "0.356 (PLACEHOLDER: 14 pol., o padrão das coronhas da época)",
    "caixa_da_culatra": "PLACEHOLDER (0,196 m de comprido, 32 mm de largura; de fotos)",
    "telha": "PLACEHOLDER (0,20 m com 11 sulcos; de fotos)",
    "conta": "PLACEHOLDER (conta de latão de 4 mm sobre o anel do adaptador)",
}

L = 1.003
D_CULATRA = (0.316, 0.512)  # caixa da culatra (d da soleira)
Z_DEP = -0.0275  # eixo do depósito tubular
PUXADA = 0.090
D_TELHA = (0.606, 0.806)
D_GATILHO = 0.356


def log(*a) -> None:
    print("[ESPINGARDA]", *a, flush=True)


# ------------------------------------------------------------------ booleanos
def cortar(obj, cortadores, mat_base: int, mat_dentro: int | None = None, caixas=()) -> None:
    """Booleano exato (diferença) de `obj` com a união dos `cortadores` (apagados no fim). O
    booleano deixa um espaço de material vazio e zera os índices: todas as faces voltam a
    `mat_base`, e as que caem nas `caixas` (lo, hi) (paredes e fundo do corte) ficam
    `mat_dentro`."""
    if len(cortadores) > 1:
        comum.selecionar_so(cortadores[0], cortadores)
        with bpy.context.temp_override(
            active_object=cortadores[0], selected_editable_objects=cortadores
        ):
            bpy.ops.object.join()
    cut = cortadores[0]
    mod = obj.modifiers.new("corte", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cut
    comum.aplicar_modificadores(obj)
    bpy.data.objects.remove(cut)
    me = obj.data
    no = me.attributes.get("no")
    if no is None:
        no = me.attributes.new("no", "INT", "FACE")
    if me.attributes.get("dup") is None:
        me.attributes.new("dup", "INT", "FACE")
    me.materials.clear()
    me.polygons.foreach_set("material_index", np.full(len(me.polygons), mat_base, np.int32))
    if mat_dentro is None:
        return
    for p in me.polygons:
        c = p.center
        for lo, hi in caixas:
            if all(lo[i] - 1e-4 <= c[i] <= hi[i] + 1e-4 for i in range(3)):
                p.material_index = mat_dentro
                break


def caixa_obj(nome, lo, hi):
    """Caixa de corte (Blender: x, y, z) de lo a hi."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(
        bm, vec=Vector([h - lo_ for lo_, h in zip(lo, hi, strict=True)]), verts=bm.verts[:]
    )
    bmesh.ops.translate(
        bm, vec=Vector([(a + b) / 2 for a, b in zip(lo, hi, strict=True)]), verts=bm.verts[:]
    )
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def cilindro_radial(nome, d, ang, r_furo, r0, r1, k=10):
    """Cilindro de corte na direção radial ao eixo do cano (ângulo a partir do topo, + = esquerda
    do atirador, +X), de r0 a r1."""
    u = Vector((math.sin(ang), 0.0, math.cos(ang)))
    w = Vector((0.0, -1.0, 0.0))
    v = u.cross(w)
    bm = bmesh.new()
    aneis = []
    for rr in (r0, r1):
        base = Vector((0.0, -d, 0.0)) + u * rr
        aneis.append(
            [
                bm.verts.new(
                    base
                    + w * r_furo * math.cos(2 * math.pi * i / k)
                    + v * r_furo * math.sin(2 * math.pi * i / k)
                )
                for i in range(k)
            ]
        )
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((aneis[0][i], aneis[0][j], aneis[1][j], aneis[1][i]))
    bm.faces.new(list(reversed(aneis[0])))
    bm.faces.new(aneis[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def capa_de_calor() -> bpy.types.Object:
    """Capa de calor: arco de 270° (aberto embaixo, onde passa o depósito) em chapa de 1,2 mm, de
    d 0,530 a 0,900, com 4 fileiras de 11 furos de 8 mm."""
    d0, d1 = 0.530, 0.900
    a0, a1 = math.radians(-135), math.radians(135)
    n_arco = 30
    bm = bmesh.new()

    def raio(d: float, fora: bool) -> float:
        t = (d - d0) / (d1 - d0)
        ri = 0.0166 - 0.0006 * t
        return ri + (0.0012 if fora else 0.0)

    grade = {}
    for jd, d in enumerate((d0, d1)):
        for fora in (False, True):
            for i in range(n_arco + 1):
                a = a0 + (a1 - a0) * i / n_arco
                r = raio(d, fora)
                grade[(jd, fora, i)] = bm.verts.new((r * math.sin(a), -d, r * math.cos(a)))
    for i in range(n_arco):
        # fora e dentro ao longo do comprimento
        bm.faces.new(
            [
                grade[(0, True, i)],
                grade[(0, True, i + 1)],
                grade[(1, True, i + 1)],
                grade[(1, True, i)],
            ]
        )
        bm.faces.new(
            [
                grade[(0, False, i)],
                grade[(1, False, i)],
                grade[(1, False, i + 1)],
                grade[(0, False, i + 1)],
            ]
        )
        # pontas (anéis de chapa)
        for jd in (0, 1):
            bm.faces.new(
                [
                    grade[(jd, False, i)],
                    grade[(jd, False, i + 1)],
                    grade[(jd, True, i + 1)],
                    grade[(jd, True, i)],
                ]
            )
    for i in (0, n_arco):  # bordas de baixo do arco
        bm.faces.new(
            [grade[(0, False, i)], grade[(0, True, i)], grade[(1, True, i)], grade[(1, False, i)]]
        )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("capa")
    bm.to_mesh(me)
    bm.free()
    capa = bpy.data.objects.new("capa", me)
    bpy.context.scene.collection.objects.link(capa)
    furos = []
    for ang in (-80, -35, 35, 80):
        for k in range(11):
            d = 0.565 + k * 0.030
            furos.append(cilindro_radial("furo", d, math.radians(ang), 0.004, 0.012, 0.024))
    cortar(capa, furos, MAT_ACO)
    me = capa.data
    me.polygons.foreach_set("material_index", np.full(len(me.polygons), MAT_ACO, np.int32))
    for nm in ("no", "dup"):
        me.attributes[nm].data.foreach_set("value", np.zeros(len(me.polygons), np.int32))
    return capa


# ------------------------------------------------------------------ a arma
def win12() -> tuple[list, dict]:
    """Devolve os objetos (com atributos no/dup e índice de material) e os pontos (m)."""
    objs = []
    # ---------------- coronha de nogueira com semipunho de pistola e soleira de aço
    g = armas.Malha()
    coronha = [
        (0.006, -0.046, -0.172, 0.0210, 3.2),
        (0.100, -0.038, -0.152, 0.0220, 3.2),
        (0.190, -0.027, -0.122, 0.0210, 3.0),
        (0.235, -0.023, -0.105, 0.0190, 2.8),
        (0.262, -0.021, -0.100, 0.0172, 2.6),
        (0.285, -0.018, -0.092, 0.0168, 2.6),
        (0.300, -0.012, -0.070, 0.0168, 2.7),
        (0.312, -0.002, -0.050, 0.0162, 2.9),
        (0.320, 0.006, -0.042, 0.0156, 3.0),
    ]
    g.loft(armas.estacoes(coronha), MAT_MADEIRA)
    g.loft([(0.0, -0.047, -0.173, 0.0212, 3.2), (0.0062, -0.046, -0.172, 0.0210, 3.2)], MAT_ACO)
    # zarelho da coronha (embaixo, perto da soleira)
    g.caixa(-0.004, 0.004, 0.092, 0.112, -0.156, -0.150, MAT_ACO)
    g.tubo(
        [(0, 0.096, -0.156), (0, 0.098, -0.168), (0, 0.106, -0.168), (0, 0.108, -0.156)],
        0.0018,
        MAT_ACO,
        k=8,
    )
    # ---------------- cano (com a alma), depósito e tampa do depósito
    g.torno(
        [
            (0.495, 0.0145),
            (0.535, 0.0145),
            (0.560, 0.0135),
            (0.750, 0.0116),
            (0.950, 0.0106),
            (L, 0.0106),
            (L, 0.0093),
            (L - 0.03, 0.0093),
        ],
        0,
        0,
        MAT_ACO,
        k=28,
        cap0=MAT_ACO,
        cap1=MAT_ESCURO,
    )
    g.torno([(0.505, 0.0115), (0.975, 0.0115)], 0, Z_DEP, MAT_ACO, k=20, cap0=MAT_ACO, cap1=MAT_ACO)
    g.torno(
        [(0.975, 0.0119), (0.990, 0.0119), (0.993, 0.0095)],
        0,
        Z_DEP,
        MAT_ACO,
        k=20,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    # ---------------- adaptador de baioneta M1917: anel do cano, anel do depósito, alma, ressalto
    # da baioneta e zarelho; a conta de latão no topo do anel do cano
    g.torno([(0.955, 0.0142), (0.990, 0.0142)], 0, 0, MAT_ACO, k=24, cap0=MAT_ACO, cap1=MAT_ACO)
    g.torno([(0.955, 0.0135), (0.975, 0.0135)], 0, Z_DEP, MAT_ACO, k=20, cap0=MAT_ACO, cap1=MAT_ACO)
    g.caixa(-0.006, 0.006, 0.955, 0.985, -0.030, -0.008, MAT_ACO)
    g.caixa(-0.0035, 0.0035, 0.940, 0.988, -0.0445, -0.0375, MAT_ACO)  # ressalto da baioneta
    g.tubo(
        [(0, 0.950, -0.044), (0, 0.952, -0.054), (0, 0.962, -0.054), (0, 0.964, -0.044)],
        0.0018,
        MAT_ACO,
        k=8,
    )
    g.cilindro_z(0.0, 0.983, 0.0138, 0.0150, 0.0012, MAT_LATAO, k=8)
    g.esfera(0.0, 0.983, 0.0162, 0.0020, MAT_LATAO, seg=12, an=8)
    # ---------------- capa de calor: abraçadeiras de trás e da frente (a chapa furada vem à parte)
    for da, db in ((0.524, 0.540), (0.893, 0.907)):
        g.torno([(da, 0.0186), (db, 0.0186)], 0, 0, MAT_ACO, k=28, cap0=MAT_ACO, cap1=MAT_ACO)
    # ---------------- caixa da culatra (os bolsões da ejeção e da carga saem no booleano)
    rc = armas.Malha()
    rc.loft(
        [
            (D_CULATRA[0], 0.006, -0.040, 0.0150, 3.0),
            (0.326, 0.015, -0.040, 0.0158, 3.5),
            (0.340, 0.019, -0.040, 0.0158, 3.5),
            (D_CULATRA[1], 0.019, -0.040, 0.0158, 3.5),
        ],
        MAT_ACO,
        k=32,
    )
    # parafuso de desmontagem (lado esquerdo) e a trava de pino na frente do guarda-mato
    g.cilindro_x(0.0150, 0.0175, 0.330, -0.020, 0.0035, MAT_ACO)
    g.cilindro_x(-0.0175, 0.0175, 0.402, -0.044, 0.0030, MAT_ACO)
    # guarda-mato (fora do booleano: peça que cruza a caixa confunde o lado de dentro)
    g.tubo(
        [
            (0, 0.333, -0.040),
            (0, 0.337, -0.064),
            (0, 0.352, -0.075),
            (0, 0.382, -0.071),
            (0, 0.396, -0.052),
            (0, 0.400, -0.040),
        ],
        0.0034,
        MAT_ACO,
        achatar=0.6,
    )
    # ---------------- telha (nó 1): nogueira com 11 sulcos, luva de aço e barra da ação
    t0, t1 = D_TELHA
    secs = [(t0, -0.0165, -0.047, 0.0160, 2.6, 0.0), (t0 + 0.006, -0.0148, -0.051, 0.0195, 2.6)]
    for k in range(11):
        c = 0.632 + k * 0.0148
        for dd, sulco in ((-0.0032, False), (-0.0024, True), (0.0024, True), (0.0032, False)):
            if sulco:
                secs.append((c + dd, -0.0148, -0.0492, 0.0177, 2.6))
            else:
                secs.append((c + dd, -0.0148, -0.051, 0.0195, 2.6))
    secs += [(t1 - 0.006, -0.0148, -0.051, 0.0195, 2.6), (t1, -0.0165, -0.047, 0.0160, 2.6)]
    # o centro da seção é o meio entre topo e base; o eixo do depósito fica dentro da madeira
    g.loft(secs, MAT_MADEIRA, no=1, k=22)
    g.torno(
        [(0.545, 0.0129), (t0 + 0.004, 0.0129)],
        0,
        Z_DEP,
        MAT_ACO,
        no=1,
        k=20,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    g.caixa(0.0108, 0.0128, 0.470, 0.560, Z_DEP - 0.004, Z_DEP + 0.004, MAT_ACO, no=1)
    # ---------------- culatra (nó 3): a face do ferrolho dentro da janela de ejeção
    g.caixa(-0.0113, -0.0099, 0.431, 0.494, -0.0105, 0.0105, MAT_ACO, no=3)
    g.caixa(-0.0118, -0.0112, 0.440, 0.452, -0.0035, 0.0035, MAT_ACO, no=3)  # extrator
    # ---------------- gatilho (nó 2)
    g.tubo(
        [
            (0, D_GATILHO + 0.002, -0.041),
            (0, D_GATILHO, -0.052),
            (0, D_GATILHO - 0.004, -0.063),
            (0, D_GATILHO - 0.010, -0.068),
        ],
        0.0032,
        MAT_ACO,
        no=2,
        k=8,
        achatar=0.55,
    )
    # ---------------- cartucho M19 (nó 4): dentro do depósito, logo à frente da caixa da culatra
    c0 = 0.516
    g.torno(
        [
            (c0, 0.0111),
            (c0 + 0.0016, 0.0111),
            (c0 + 0.0019, 0.0101),
            (c0 + 0.0615, 0.0101),
            (c0 + 0.0635, 0.0086),
        ],
        0,
        Z_DEP,
        MAT_LATAO,
        no=4,
        k=16,
        cap0=MAT_LATAO,
        cap1=MAT_LATAO,
    )
    corpo = g.objeto("win12")
    receptor = rc.objeto("receptor")
    ejecao = ((-0.030, -0.497, -0.0115), (-0.0098, -0.428, 0.0115))
    carga = ((-0.0112, -0.488, -0.060), (0.0112, -0.405, -0.035))
    cortar(
        receptor,
        [caixa_obj("janela", *ejecao), caixa_obj("portinhola", *carga)],
        MAT_ACO,
        MAT_ESCURO,
        caixas=[(ejecao[0], (-0.0098 + 1e-4, ejecao[1][1], ejecao[1][2])), carga],
    )
    capa = capa_de_calor()
    objs = [corpo, receptor, capa]
    pontos = {
        "muzzle": (0.0, L, 0.0),
        # mira: alça = topo de trás da caixa da culatra; massa = topo da conta (sight_align mede)
        "sight": (0.0, 0.340, 0.019),
        "front": (0.0, 0.983, 0.0182),
        # mão direita no delgado (7 cm atrás do gatilho, como a M70); esquerda na luva da ação, no
        # limite de 0,26 m do teste da F5 (D-59): a telha de verdade começa 5 cm à frente
        "grip": (0.0, 0.286, -0.052),
        "support": (0.0, 0.538, -0.034),
        "telha": (0.0, (t0 + t1) / 2, Z_DEP - 0.004),
        "pump": (0.0, (t0 + t1) / 2, Z_DEP),
        "eject": (-0.0158, 0.462, 0.0),
        "load": (0.0, 0.446, -0.040),
        "trigger": (0.0, D_GATILHO + 0.002, -0.041),
        "eyeM": 0.12,
        "pumpM": PUXADA,
        "comprimento_m": L,
    }
    return objs, pontos


# ------------------------------------------------------------------ materiais
def latao(nome: str):
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    n = materiais.Nos(mat)
    p = n.P()
    manchas = n.mapa(n.ruido(p, 0.25, 3.0, 0.6), 0.35, 0.7)
    base = n.rgb(0.42, 0.27, 0.085)
    escuro = n.rgb(0.20, 0.12, 0.04)
    cor = n.mix(n.mul(manchas, 0.55), base, escuro)
    rug = n.add(0.36, n.mul(manchas, 0.2))
    alt = n.mul(n.ruido(p, 3.0, 2.0), 0.004)
    return mat, n.finalizar(cor, rug, 0.9, alt)


def escuro(nome: str):
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    n = materiais.Nos(mat)
    p = n.P()
    v = n.mapa(n.ruido(p, 0.5, 2.0), 0.3, 0.7)
    cor = n.mix(v, n.rgb(0.010, 0.010, 0.009), n.rgb(0.022, 0.021, 0.018))
    return mat, n.finalizar(cor, 0.7, 0.25, None)


def materiais_win12() -> dict:
    return {
        "madeira": armas.madeira("madeira_win12", (0.055, 0.025, 0.011), (0.17, 0.085, 0.04), 0.2),
        "aco": materiais.criar("aco"),  # fosfato cinza-esverdeado fosco (como as facas e armas)
        "latao": latao("latao_win12"),
        "escuro": escuro("escuro_win12"),
    }


# ------------------------------------------------------------------ pontos
def medir(pontos: dict, caminho: Path) -> dict:
    nos = faca.ler_nos(caminho)
    R = nos["Arma"] * np.array([-1.0, 1.0, -1.0])
    lo, hi = R.min(axis=0), R.max(axis=0)
    c = (lo + hi) / 2
    chaves = (
        "muzzle",
        "sight",
        "front",
        "grip",
        "support",
        "telha",
        "pump",
        "eject",
        "load",
        "trigger",
    )
    out = {k: armas.para_roblox(pontos[k], c) for k in chaves}
    v = R - c
    out["lowX"] = round(float(v[:, 0].min() - out["grip"][0]), 4)
    out["lengthM"] = round(float(hi[2] - lo[2]) * M_POR_STUD, 4)
    out["eyeM"] = pontos["eyeM"]
    out["pumpM"] = pontos["pumpM"]
    out["forward"] = "-Z"
    out["tamanho"] = [round(float(x), 4) for x in hi - lo]
    gs = np.array(out["support"]) - np.array(out["grip"])
    out["_conferencia"] = {
        "boca_vs_vertice_mais_a_frente": round(out["muzzle"][2] - float(lo[2] - c[2]), 4),
        "comprimento_ficha_m": pontos["comprimento_m"],
        "apoio_ao_punho_m": round(float(np.linalg.norm(gs)) * M_POR_STUD, 4),
        "telha_ao_punho_m": round(
            float(np.linalg.norm(np.array(out["telha"]) - np.array(out["grip"]))) * M_POR_STUD, 4
        ),
        "nos": {
            k: [
                round(float(x), 4)
                for x in (p * np.array([-1, 1, -1])).max(0) - (p * np.array([-1, 1, -1])).min(0)
            ]
            for k, p in nos.items()
        },
    }
    return out


# ------------------------------------------------------------------ prévia do GLB
def previa(caminho_glb: Path, saida: Path) -> None:
    """`_previa.png`: o GLB exportado (o que vai para o Roblox), face única, em 3 vistas: lado
    direito (janela de ejeção), 3/4 da frente pela esquerda e de cima (linha de visada)."""
    import apresentar as A
    import comparar as K

    cena = comum.cena_vazia()
    K.configurar(cena, 48)
    cena.cycles.device = "CPU"
    cena.cycles.denoiser = "OPENIMAGEDENOISE"
    cena.render.resolution_x, cena.render.resolution_y = 1600, 520
    nos = A.importar_nos(caminho_glb)
    for o in nos.values():
        K.face_unica(o)
    pts = K.pontos(list(nos.values()), 8000)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    ctr = (lo + hi) / 2
    paineis = []
    vistas = (
        ("direita", (math.radians(90), 0, math.radians(-90)), (-1.5, 0, 0), 1.08),
        ("esquerda", (math.radians(72), 0, math.radians(50)), None, 1.0),
        ("cima", (0.0, 0.0, math.radians(-90)), (0, 0, 1.5), 1.08),
    )
    for nome, rot, desl, folga in vistas:
        cd = bpy.data.cameras.new(nome)
        cam = bpy.data.objects.new(nome, cd)
        cena.collection.objects.link(cam)
        cam.rotation_euler = rot
        if desl is None:
            cd.type = "PERSP"
            cd.lens = 50
            cd.sensor_width = 36
            dirv = Matrix(cam.rotation_euler.to_matrix()) @ Vector((0, 0, 1))
            cam.location = Vector(ctr.tolist()) + dirv * 1.45
        else:
            cd.type = "ORTHO"
            cd.ortho_scale = float(hi[1] - lo[1]) * folga
            cam.location = (float(ctr[0]) + desl[0], float(ctr[1]), float(ctr[2]) + desl[2])
        cena.camera = cam
        s = K.sol(130.0)
        paineis.append(K.renderizar(saida.parent / f"_previa_{nome}.png"))
        bpy.data.objects.remove(s)
        bpy.data.objects.remove(cam)
    sep = 6
    h, w = paineis[0].shape[:2]
    total = np.ones((3 * h + 2 * sep, w, 4), np.float32)
    total[..., :3] = 0.08
    for i, p in enumerate(paineis):
        y0 = (2 - i) * (h + sep)
        total[y0 : y0 + h] = p
    img = bpy.data.images.new("previa", w, total.shape[0], alpha=False)
    comum.gravar_pixels(img, total)
    comum.salvar_imagem(img, saida, "PNG")
    for nome in ("direita", "esquerda", "cima"):
        f = saida.parent / f"_previa_{nome}.png"
        if f.is_file():
            f.unlink()
    log("prévia", saida)


# ------------------------------------------------------------------ produção
def produzir() -> dict:
    t0 = time.time()
    cena = faca.cena_cpu()
    objs, pontos = win12()
    mats = materiais_win12()
    for o in objs:
        # sem materials.clear(): ele zera o material_index das faces
        for nome in ("madeira", "aco", "latao", "escuro"):
            o.data.materials.append(mats[nome][0])
    comum.selecionar_so(objs[0], objs)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs):
        bpy.ops.object.join()
    obj = objs[0]
    faca.triangular_e_vivas(obj, set())
    comum.selecionar_so(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")
    uso = faca.empacotar(obj)
    partes = {
        nome: faca.extrair(obj, nome, lambda no, dup, i=i: no == i) for i, nome in enumerate(NOS)
    }
    bpy.data.objects.remove(obj)
    alvos = [partes[n] for n in NOS]
    # o cartucho fica dentro do depósito: no bake ele vai para longe (senão sai preto de oclusão)
    longe = Matrix.Translation((0.4, 0.0, 0.0))
    partes["Cartucho"].data.transform(longe)
    cena.world.light_settings.distance = 0.012
    bk = faca.assar(cena, alvos, mats)
    partes["Cartucho"].data.transform(longe.inverted())
    pasta = comum.SAIDA / PASTA
    texturas, info = faca.compor(bk["imgs"], comum.TRABALHO / PASTA)
    caminho = pasta / f"{PASTA}.glb"
    exp = comum.exportar_glb([(n, partes[n]) for n in NOS], caminho, texturas, metal=True)
    pts = medir(pontos, caminho)
    tris = {n: len(comum.arrays_malha(partes[n])[3]) // 3 for n in NOS}
    (pasta / "pontos.json").write_text(
        json.dumps(pts, ensure_ascii=False, indent=1) + "\n", "utf-8"
    )
    met = {
        "chave": CHAVE,
        "nome": "Winchester Model 12 Trench Gun (calibre 12, cano de 20 pol., capa de calor)",
        "triangulos": tris,
        "triangulos_total": sum(tris.values()),
        "textura_px": faca.TEX,
        "mb": exp["mb"],
        "uso_uv": uso,
        "texturas": info,
        "bake_s": bk["tempos"],
        "medidas_reais": FONTES,
        "comprimento_m": pts["lengthM"],
        "pecas": {
            "Arma": "a arma inteira (pontos do WeaponArt)",
            "Telha": "corre para trás pumpM (m) no eixo do depósito: +Z local da Arma",
            "Culatra": "recua junto com a telha (o mesmo curso)",
            "Gatilho": "gira em volta do ponto trigger (eixo X da Arma)",
            "Cartucho": "dentro do depósito (escondido); copiar para load/eject na animação",
        },
    }
    comum.gravar_json(pasta / "metricas.json", met)
    log(json.dumps({**met, "pontos": pts}, ensure_ascii=False), f"total {time.time() - t0:.0f} s")
    return met


def main() -> None:
    a = comum.argumentos()
    if "--montar" in a:
        # só a peça montada com os materiais procedurais, de lado (conferir a forma antes do bake)
        faca.cena_cpu()
        objs, _ = win12()
        mats = materiais_win12()
        for o in objs:
            # sem materials.clear(): ele zera o material_index das faces
            for nome in ("madeira", "aco", "latao", "escuro"):
                o.data.materials.append(mats[nome][0])
        armas.previa(objs, comum.TRABALHO / PASTA / "montada.png")
        return
    if "--previa" in a:
        previa(comum.SAIDA / PASTA / f"{PASTA}.glb", comum.SAIDA / PASTA / "_previa.png")
        return
    produzir()


if __name__ == "__main__":
    main()
