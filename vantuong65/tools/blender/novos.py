"""Etapa B1 (Tarefa B): assets novos e realistas feitos do zero no Blender (bpy).

Para a chave pedida:
1. a receita (`receita_<chave>`) modela a peça cheia (alta) em metros, com material PBR
   procedural (ruído, Voronoi, ondas, bump; estêncil e letreiro como malha colada) e devolve os
   objetos; letreiros/estênceis só entram no bake (`so_bake`);
2. a malha do jogo sai da alta como nos refeitos: pré-redução, limpeza (faces escondidas),
   redução com alvo pela tolerância de desvio (`comum.escolher_alvo`), UV nova e bake
   (`comum.produzir`): cor, normal, rugosidade, metal (só nas granadas) e oclusão;
3. o GLB vai para `assets/blender/<chave>/<chave>.glb` (studs, Y para cima, base no chão);
4. a versão "peças" de hoje (as Parts de `MapLife.luau` / `GrenadeArt.luau`, com as mesmas
   medidas e cores, cor lisa) vira `_trabalho/<chave>/<chave>_pecas.glb` para a comparação.
   Quando não há versão no jogo, é uma hipótese em peças (dito no rótulo e no metricas.json).

Medidas: cada receita tem `MEDIDAS` com a fonte; o que não tem fonte é PLACEHOLDER.

Uso:
    blender -b --factory-startup -P tools/blender/novos.py -- <chave>
    blender -b --factory-startup -P tools/blender/novos.py -- <chave> --previa [azimute]
        (só a prévia da peça alta, em Cycles na CPU: `_trabalho/<chave>/previa_alta_<az>.png`)
"""

from __future__ import annotations

import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import glb  # noqa: E402
import modelar as M  # noqa: E402
from modelar import Mat, rgb  # noqa: E402

PRE_REDUCAO = 60000  # a alta passa disto antes da limpeza (a busca de faces escondidas é lenta)
STUD = C.M_POR_STUD


def suave_passo(a: float, b: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def periodo(p: float) -> float:
    """Escala da textura de ondas (Blender) para um período `p` em metros."""
    return 2 * math.pi / (20 * p)


# =============================================================== materiais
def mat_barro(nome: str, base="#86563c", escuro="#5a3826", z_molhado=0.16, z_rim=0.66):
    """Barro cozido sem vidrado: manchas, grão, base molhada e com limo, eflorescência branca,
    escorridos sob a boca e anéis do torno no relevo."""
    m = Mat(nome, rug=0.88)
    p = m.coord("objeto")
    _, _, z = m.separar(p)
    manchas = m.ruido(p, 7.0, 6, 0.6)
    cor = m.rampa(manchas, [(0.3, rgb(escuro)), (0.72, rgb(base))])
    grao = m.ruido(p, 55.0, 4, 0.5)
    cor = m.misturar(m.faixa(grao, 0.6, 0.8, 0, 0.18), cor, rgb("#a07a5e"))
    encardido = m.faixa(m.ruido(p, 2.5, 4), 0.35, 0.7, 0.0, 0.5)
    cor = m.misturar(encardido, cor, rgb("#4e3a2c"))
    molhado = m.conta(
        "MULTIPLY",
        m.faixa(z, z_molhado + 0.07, z_molhado - 0.03),
        m.faixa(m.ruido(p, 5.0, 3), 0.3, 0.6, 0.55, 1.0),
    )
    cor = m.misturar(molhado, cor, rgb("#7a7a7a"), "MULTIPLY")
    limo = m.conta("MULTIPLY", m.faixa(z, 0.06, 0.0), m.faixa(m.ruido(p, 12.0, 4), 0.42, 0.62))
    cor = m.misturar(limo, cor, rgb("#4c5130"))
    eflor = m.conta(
        "MULTIPLY",
        m.faixa(m.ruido(m.mapear(p, (6, 6, 1.4)), 1.0, 5), 0.6, 0.74),
        m.conta("MULTIPLY", m.faixa(z, 0.08, 0.2), m.faixa(z, z_rim - 0.1, z_rim - 0.25)),
    )
    cor = m.misturar(m.conta("MULTIPLY", eflor, 0.55), cor, rgb("#bcb09d"))
    escorrido = m.conta(
        "MULTIPLY",
        m.faixa(m.ruido(m.mapear(p, (45, 45, 1.6)), 1.0, 3), 0.55, 0.7),
        m.faixa(z, z_rim - 0.35, z_rim - 0.02),
    )
    cor = m.misturar(m.conta("MULTIPLY", escorrido, 0.5), cor, rgb("#6e6e6e"), "MULTIPLY")
    m.cor(cor)
    m.rug(m.misturar_valor(molhado, 0.9, 0.62))
    aneis = m.onda(p, periodo(0.011), "Z", distorcao=1.5, detalhe=2.0)
    m.relevo(aneis, 0.18, 0.0012)
    m.relevo(m.ruido(p, 320.0, 3), 0.12, 0.0008)
    return m.m


def mat_madeira(
    nome: str,
    claro="#8a7a62",
    escuro="#5b4a37",
    cinza="#857f74",
    largura_tabua: float | None = None,
    eixo: str = "X",
    rug: float = 0.82,
):
    """Madeira velha: veio esticado no eixo da tábua, acinzentado do tempo e fresta entre
    tábuas (a cada `largura_tabua` m, na direção perpendicular ao eixo, no plano XY)."""
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    x, y, _ = m.separar(p)
    esc = (2.5, 70, 70) if eixo == "X" else (70, 2.5, 70)
    veio = m.ruido(m.mapear(p, esc), 1.5, 6, 0.65, distorcao=1.2)
    cor = m.rampa(veio, [(0.32, rgb(escuro)), (0.68, rgb(claro))])
    tempo = m.faixa(m.ruido(p, 3.0, 3), 0.4, 0.65, 0.0, 0.7)
    cor = m.misturar(tempo, cor, rgb(cinza))
    altura = veio
    if largura_tabua:
        coord = y if eixo == "X" else x
        u = m.conta("FRACT", m.conta("MULTIPLY", coord, 1 / largura_tabua))
        borda = m.conta(
            "MULTIPLY", m.conta("MINIMUM", u, m.conta("SUBTRACT", 1.0, u)), largura_tabua
        )
        fresta = m.faixa(borda, 0.0022, 0.0006)
        cor = m.misturar(fresta, cor, rgb("#1e1812"))
        altura = m.conta("SUBTRACT", veio, m.conta("MULTIPLY", fresta, 2.0))
    m.cor(cor)
    m.relevo(altura, 0.35, 0.002)
    return m.m


def mat_coco(nome: str):
    m = Mat(nome, rug=0.72)
    p = m.coord("objeto")
    fibra = m.ruido(m.mapear(p, (8, 8, 90)), 3.0, 6, 0.7)
    m.cor(m.rampa(fibra, [(0.3, rgb("#2f1f14")), (0.7, rgb("#5a3d27"))]))
    m.relevo(fibra, 0.5, 0.001)
    return m.m


def mat_bambu(nome: str, claro="#b0a46e", escuro="#857849", cinza="#8f8a76", rug=0.55):
    """Bambu seco: estrias ao longo da vara (atributo `local`, eixo Z), manchas de fungo, nós
    (quinas) mais escuros e acinzentado do tempo."""
    m = Mat(nome, rug=rug)
    p = m.coord("local")
    estria = m.ruido(m.mapear(p, (60, 60, 1.2)), 2.0, 5, 0.6)
    cor = m.rampa(estria, [(0.35, rgb(escuro)), (0.7, rgb(claro))])
    tempo = m.faixa(m.ruido(m.mapear(p, (4, 4, 0.8)), 2.0, 3), 0.45, 0.7, 0.0, 0.65)
    cor = m.misturar(tempo, cor, rgb(cinza))
    fungo = m.faixa(m.voronoi(p, 90.0), 0.08, 0.02)
    fungo = m.conta("MULTIPLY", fungo, m.faixa(m.ruido(p, 6.0), 0.5, 0.65))
    cor = m.misturar(fungo, cor, rgb("#3d3423"))
    no = m.faixa(m.pontudo(), 0.53, 0.6, 0.0, 0.6)
    cor = m.misturar(no, cor, rgb("#5d5232"))
    m.cor(cor)
    m.rug(m.misturar_valor(tempo, rug, 0.75))
    m.relevo(estria, 0.25, 0.0008)
    return m.m


def mat_palha(nome: str):
    """Palha de arroz da meda: fibras escorrendo na vertical, dourado por baixo do cinza do
    tempo, pé escuro (umidade) e tufos."""
    m = Mat(nome, rug=0.92)
    p = m.coord("objeto")
    _, _, z = m.separar(p)
    fibra = m.ruido(m.mapear(p, (70, 70, 2.2)), 1.0, 8, 0.75, distorcao=0.3)
    fina = m.ruido(m.mapear(p, (260, 260, 7)), 1.0, 4, 0.6)
    cor = m.rampa(
        fibra,
        [
            (0.3, rgb("#4a3c25")),
            (0.45, rgb("#93784a")),
            (0.6, rgb("#b5975a")),
            (0.75, rgb("#d2b978")),
        ],
    )
    cor = m.misturar(m.faixa(fina, 0.35, 0.7, 0.0, 0.35), cor, rgb("#3f3322"))
    tempo = m.conta(
        "MULTIPLY", m.faixa(m.ruido(p, 1.2, 4), 0.48, 0.72, 0.0, 0.6), m.faixa(z, 0.5, 1.5)
    )
    cinza = m.misturar(m.faixa(fina, 0.3, 0.7), rgb("#77705f"), rgb("#9a927d"))
    cor = m.misturar(tempo, cor, cinza)
    pe = m.conta("MULTIPLY", m.faixa(z, 0.45, 0.02), m.faixa(m.ruido(p, 4.0), 0.3, 0.6, 0.6, 1.0))
    cor = m.misturar(pe, cor, rgb("#463c2c"))
    tufo = m.voronoi(m.mapear(p, (1, 1, 0.35)), 9.0, "SMOOTH_F1")
    m.cor(cor)
    m.rug(0.93)
    m.relevo(fibra, 1.0, 0.012)
    m.relevo(fina, 0.6, 0.004)
    m.relevo(tufo, 0.3, 0.02)
    return m.m


def mat_tinta(
    nome: str,
    cor="#4e5233",
    metal_cor="#77766f",
    desgaste: float = 0.55,
    rug_tinta: float = 0.55,
    ferrugem: bool = False,
    escala: float = 250.0,
):
    """Aço pintado (tinta = não metal) com a tinta gasta nas quinas mostrando o aço (metal) ou a
    ferrugem (não metal), casca de laranja da pintura e sujeira nas frestas."""
    m = Mat(nome, rug=rug_tinta)
    p = m.coord("objeto")
    var = m.ruido(p, escala * 0.08, 4)
    tinta = m.misturar(m.faixa(var, 0.3, 0.7, 0.0, 0.25), rgb(cor), rgb("#2e301f"))
    quina = m.faixa(m.pontudo(), 0.515, 0.56)
    risco = m.faixa(m.ruido(p, escala, 6, 0.7), 0.5 + 0.12 * (1 - desgaste), 0.62)
    gasto = m.conta("MULTIPLY", quina, risco)
    gasto = m.conta("MAXIMUM", gasto, m.conta("MULTIPLY", risco, 0.25 * desgaste), limitar=True)
    if ferrugem:
        nu = m.misturar(m.ruido(p, escala * 0.5), rgb("#5e3a22"), rgb("#7b4a26"))
    else:
        nu = rgb(metal_cor)
    m.cor(m.misturar(gasto, tinta, nu))
    m.rug(m.misturar_valor(gasto, rug_tinta, 0.75 if ferrugem else 0.38))
    if not ferrugem:
        m.metal(gasto)
    m.relevo(m.ruido(p, escala * 1.6, 2), 0.06, 0.0002)
    return m.m


def mat_aco(nome: str, cor="#8a8880", rug=0.42, escala=300.0):
    m = Mat(nome, rug=rug)
    p = m.coord("objeto")
    v = m.ruido(p, escala, 4)
    m.cor(m.misturar(m.faixa(v, 0.35, 0.7, 0, 0.3), rgb(cor), rgb("#4c4a45")))
    m.metal(1.0)
    m.rug(m.faixa(v, 0.2, 0.8, rug - 0.08, rug + 0.12))
    return m.m


def mat_estencil(nome: str, cor="#d8d0b4", fundo="#4f5636", gasto=0.35, escala=180.0):
    """Tinta de estêncil (malha colada): onde gastou, mostra a cor de fundo."""
    m = Mat(nome, rug=0.72)
    p = m.coord("objeto")
    falha = m.faixa(m.ruido(p, escala, 6, 0.7), 0.62 - 0.2 * gasto, 0.72 - 0.2 * gasto)
    m.cor(m.misturar(falha, rgb(cor), rgb(fundo)))
    return m.m


def mat_caixote(nome: str, tinta="#4e5535"):
    """Madeira pintada de verde-oliva: veio sob a tinta, tinta gasta nas quinas e riscos
    mostrando a madeira crua, sujeira."""
    m = Mat(nome, rug=0.72)
    p = m.coord("objeto")
    veio = m.ruido(m.mapear(p, (2.0, 80, 80)), 1.5, 6, 0.65, distorcao=1.0)
    madeira = m.rampa(veio, [(0.3, rgb("#7c5b3a")), (0.7, rgb("#a98257"))])
    var = m.ruido(p, 9.0, 4)
    cor_tinta = m.misturar(m.faixa(var, 0.3, 0.75, 0.0, 0.3), rgb(tinta), rgb("#363b23"))
    quina = m.faixa(m.pontudo(), 0.52, 0.58)
    lasca = m.faixa(m.ruido(p, 60.0, 6, 0.7), 0.52, 0.6)
    risco = m.faixa(m.ruido(m.mapear(p, (1, 30, 30)), 4.0, 2), 0.7, 0.74)
    gasto = m.conta("MAXIMUM", m.conta("MULTIPLY", quina, lasca), risco, limitar=True)
    cor = m.misturar(gasto, cor_tinta, madeira)
    poeira = m.faixa(m.ruido(p, 5.0, 3), 0.55, 0.75, 0.0, 0.35)
    cor = m.misturar(poeira, cor, rgb("#8a7f63"))
    m.cor(cor)
    m.rug(m.misturar_valor(gasto, 0.68, 0.85))
    m.relevo(veio, 0.22, 0.0015)
    m.relevo(m.conta("MULTIPLY", gasto, -1.0), 0.3, 0.0006)
    return m.m


def mat_juta(
    nome: str,
    claro="#a68e62",
    escuro="#6f5d3f",
    sujeira="#5d4c35",
    trama_m=0.007,
    listras: bool = False,
    z_sujo: float = 0.25,
):
    """Juta (aniagem): trama em 3 eixos do saco (atributo `local`), fibras, variação por saco
    (`semente`), terra embaixo (coordenada do objeto) e, no saco de arroz, duas listras azuis
    desbotadas."""
    m = Mat(nome, rug=0.93)
    p = m.coord("local")
    pw = m.coord("objeto")
    _, ly, _ = m.separar(p)
    _, _, z = m.separar(pw)
    esc = periodo(trama_m)
    wx = m.onda(p, esc, "X", perfil="TRI")
    wy = m.onda(p, esc, "Y", perfil="TRI")
    wz = m.onda(p, esc, "Z", perfil="TRI")
    trama = m.conta(
        "MAXIMUM",
        m.conta("MULTIPLY", wx, wy),
        m.conta("MAXIMUM", m.conta("MULTIPLY", wx, wz), m.conta("MULTIPLY", wy, wz)),
    )
    fibra = m.ruido(p, 140.0, 8, 0.72)
    cor = m.rampa(fibra, [(0.32, rgb(escuro)), (0.68, rgb(claro))])
    cor = m.misturar(m.conta("MULTIPLY", trama, 0.35), cor, rgb("#5a4a30"), "MULTIPLY")
    s = m.semente()
    por_saco = m.ruido(m.juntar_xyz(m.conta("MULTIPLY", s, 0.37), 0.0, 0.0), 1.0, 1)
    cor = m.misturar(m.faixa(por_saco, 0.3, 0.7, 0.0, 0.45), cor, rgb("#8c7a58"))
    if listras:
        ay = m.conta("ABSOLUTE", ly)
        listra = m.conta(
            "MULTIPLY",
            m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", ay, 0.06)), 0.0065, 0.004),
            m.faixa(m.ruido(p, 40.0, 5), 0.3, 0.6, 0.2, 0.6),
        )
        cor = m.misturar(listra, cor, rgb("#5d6772"))
    suja = m.conta(
        "MULTIPLY", m.faixa(z, z_sujo, 0.0), m.faixa(m.ruido(pw, 6.0, 4), 0.35, 0.65, 0.3, 1.0)
    )
    cor = m.misturar(suja, cor, rgb(sujeira))
    m.cor(cor)
    m.rug(0.94)
    m.relevo(trama, 0.45, 0.0012)
    m.relevo(fibra, 0.3, 0.0008)
    return m.m


def mat_corda(nome: str, cor="#9b8a62"):
    m = Mat(nome, rug=0.9)
    p = m.coord("objeto")
    fio = m.onda(p, periodo(0.006), "DIAGONAL", distorcao=1.0)
    m.cor(m.misturar(m.conta("MULTIPLY", fio, 0.4), rgb(cor), rgb("#4d4330"), "MULTIPLY"))
    m.relevo(fio, 0.5, 0.001)
    return m.m


def mat_pano(nome: str, cor="#2a2724", desbotado="#47423b", xadrez: str | None = None):
    """Algodão tingido (preto de áo bà ba, marrom) ou xadrez de khăn rằn (UV do pano)."""
    m = Mat(nome, rug=0.95)
    uv = m.coord("uv")
    p = m.coord("objeto")
    if xadrez:
        ch = m.no("ShaderNodeTexChecker")
        m._set(ch.inputs["Vector"], uv)
        ch.inputs["Scale"].default_value = 28.0
        ch.inputs["Color1"].default_value = rgb(xadrez)
        ch.inputs["Color2"].default_value = rgb(cor)
        base = ch.outputs["Color"]
    else:
        base = rgb(cor)
    sol = m.faixa(m.ruido(p, 4.0, 4), 0.4, 0.7, 0.0, 0.6)
    c = m.misturar(sol, base, rgb(desbotado))
    trama = m.ruido(m.mapear(uv, (1, 1, 1)), 900.0, 2)
    m.cor(c)
    m.relevo(trama, 0.15, 0.0005)
    return m.m


def mat_oleo(nome: str):
    m = Mat(nome, rug=0.3)
    m.cor(rgb("#3a2511"))
    return m.m


def mat_nonla(nome: str):
    """Folha de palmeira do nón lá: folhas sobrepostas em gomos (ângulo), nervuras radiais,
    linha de costura branca nos 16 aros; por dentro, os aros de bambu mais escuros."""
    m = Mat(nome, rug=0.55)
    p = m.coord("objeto")
    x, y, z = m.separar(p)
    vm = m.no("ShaderNodeVectorMath", operation="LENGTH")
    m._set(vm.inputs[0], m.juntar_xyz(x, y, 0.0))
    r = vm.outputs["Value"]
    ang = m.gradiente(p, "RADIAL")
    gomo_n = 72.0
    gomo = m.conta(
        "FRACT",
        m.conta(
            "ADD", m.conta("MULTIPLY", ang, gomo_n), m.conta("MULTIPLY", m.ruido(p, 20.0), 0.25)
        ),
    )
    id_gomo = m.conta("FLOOR", m.conta("MULTIPLY", ang, gomo_n))
    var_gomo = m.ruido(m.juntar_xyz(m.conta("MULTIPLY", id_gomo, 0.71), 0.0, 0.0), 1.0, 1)
    nervura = m.ruido(
        m.juntar_xyz(m.conta("MULTIPLY", ang, 900.0), m.conta("MULTIPLY", r, 6.0), 0.0), 1.0, 4
    )
    cor = m.rampa(nervura, [(0.3, rgb("#c5b383")), (0.7, rgb("#ddd1a6"))])
    cor = m.misturar(m.faixa(var_gomo, 0.3, 0.7, 0.0, 0.5), cor, rgb("#c9bc7d"))
    passo = 0.2 / 16
    u = m.conta("FRACT", m.conta("MULTIPLY", r, 1 / passo))
    dist = m.conta("MINIMUM", u, m.conta("SUBTRACT", 1.0, u))
    linha = m.faixa(dist, 0.07, 0.025)
    ponto = m.conta("FRACT", m.conta("MULTIPLY", m.conta("MULTIPLY", ang, 2 * math.pi / 0.005), r))
    ponto = m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", ponto, 0.5)), 0.32, 0.22)
    costura = m.conta("MULTIPLY", linha, ponto)
    nz = m.separar(m.no("ShaderNodeNewGeometry").outputs["Normal"])[2]
    dentro = m.faixa(nz, -0.05, -0.3)
    aro = m.conta("MULTIPLY", m.faixa(dist, 0.16, 0.08), dentro)
    cor = m.misturar(
        m.conta("MULTIPLY", costura, m.conta("SUBTRACT", 1.0, dentro)), cor, rgb("#e2dac4")
    )
    cor = m.misturar(aro, cor, rgb("#8b7a50"))
    sujo = m.conta("MULTIPLY", m.faixa(r, 0.16, 0.2), m.faixa(m.ruido(p, 25.0), 0.4, 0.7, 0.2, 0.7))
    cor = m.misturar(sujo, cor, rgb("#9c8a62"))
    m.cor(cor)
    altura = m.conta("ADD", m.conta("MULTIPLY", gomo, 0.6), m.conta("MULTIPLY", costura, 0.5))
    altura = m.conta("ADD", altura, m.conta("MULTIPLY", aro, 1.2))
    m.relevo(altura, 0.35, 0.0012)
    m.relevo(nervura, 0.12, 0.0004)
    return m.m


# =============================================================== receitas
def so_bake(obj):
    obj["so_bake"] = True
    return obj


def letreiro_plano(corpo, altura, mat, pos, normal: str, fonte=M.FONTE_ESTENCIL, rot_z=0.0):
    """Estêncil plano numa face: `normal` é '-Y', '+Y', '-X' ou '+X'."""
    t = M.texto_malha(corpo, altura, fonte)
    rot = {
        "-Y": Matrix.Rotation(math.pi / 2, 4, "X"),
        "+Y": Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"),
        "-X": Matrix.Rotation(-math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"),
        "+X": Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"),
    }[normal]
    M.mover(t, Matrix.Translation(Vector(pos)) @ rot @ Matrix.Rotation(rot_z, 4, "Z"))
    M.material(t, mat)
    return so_bake(t)


def receita_water_jar():
    """Chum: pote d'água de barro com tampa de tábuas e cuia de coco (gáo dừa) em cima."""
    perfil = [
        (0.0, 0.004),
        (0.158, 0.0),
        (0.180, 0.010),
        (0.212, 0.060),
        (0.250, 0.150),
        (0.282, 0.260),
        (0.298, 0.360),
        (0.300, 0.420),
        (0.288, 0.495),
        (0.262, 0.560),
        (0.232, 0.610),
        (0.210, 0.640),
        (0.194, 0.660),
        (0.193, 0.672),
        (0.206, 0.682),
        (0.209, 0.696),
        (0.201, 0.706),
        (0.181, 0.706),
        (0.172, 0.695),
        (0.170, 0.650),
        (0.0, 0.640),
    ]
    corpo = M.torno("pote", perfil, segs=72, fatiar=0.025)
    rng_base = 3

    def torto(co, n):
        if n.z < -0.7:
            return 0.0
        a = math.atan2(co.y, co.x)
        lobo = 0.0035 * math.sin(3 * a + 0.7) * min(1.0, co.z / 0.3)
        return lobo + 0.0025 * M.fbm(co * 6, 3, rng_base)

    M.deslocar(corpo, torto)
    M.material(M.suave(corpo, 70), mat_barro("barro"))
    tampa = M.torno(
        "tampa",
        [(0.0, 0.704), (0.214, 0.704), (0.216, 0.712), (0.214, 0.726), (0.0, 0.726)],
        segs=64,
    )
    M.material(
        M.suave(tampa, 40),
        mat_madeira("tampa", "#7a6d5c", "#4a3c2e", "#77726a", largura_tabua=0.072),
    )
    travessa = M.caixa("travessa", (0.34, 0.045, 0.024), (0.0, 0.0, 0.738))
    M.chanfrar(travessa, 0.004, 2)
    M.mover(travessa, Matrix.Rotation(math.pi / 2, 4, "Z"))
    M.material(M.suave(travessa, 40), mat_madeira("travessa", eixo="Y"))
    cuia = M.torno(
        "cuia",
        [
            (0.0, 0.066),
            (0.03, 0.062),
            (0.052, 0.046),
            (0.064, 0.022),
            (0.066, 0.0),
            (0.061, 0.0),
            (0.059, 0.02),
            (0.047, 0.041),
            (0.027, 0.056),
            (0.0, 0.060),
        ],
        segs=40,
        fatiar=0.01,
    )
    M.deslocar(cuia, lambda co, n: 0.0015 * M.fbm(co * 30, 3, 7))
    # cuia de boca para baixo na metade -X da tampa (a travessa corre em Y no meio); o cabo
    # sai pela borda e fica para fora do pote
    M.mover(cuia, M.matriz((-0.105, 0.03, 0.726), (0.0, 0.0, 0.3)))
    M.material(M.suave(cuia, 60), mat_coco("coco"))
    cabo = M.bambu(
        "cabo",
        (-0.150, 0.035, 0.735),
        (-0.46, 0.06, 0.733),
        0.009,
        0.008,
        entre_nos=0.16,
        segs=10,
        sem=11,
    )
    M.material(M.suave(cabo, 50), mat_bambu("bambu_cabo"))
    return [corpo, tampa, travessa, cuia, cabo]


def receita_straw_stack():
    """Đống rơm: meda de palha de arroz em volta de um mastro de bambu, com capuz de palha
    amarrado no alto."""
    perfil = [
        (0.0, 0.0),
        (0.84, 0.0),
        (0.93, 0.10),
        (0.97, 0.40),
        (0.95, 0.80),
        (0.87, 1.18),
        (0.72, 1.52),
        (0.52, 1.80),
        (0.32, 2.00),
        (0.15, 2.12),
        (0.05, 2.17),
        (0.0, 2.18),
    ]
    corpo = M.torno("meda", perfil, segs=160, fatiar=0.02)

    def palha(co, n):
        if n.z < -0.7:
            return 0.0
        q = Vector((co.x * 2.2, co.y * 2.2, co.z * 0.9))
        tufo = 0.04 * M.fbm(q, 4, 1)
        # fios em pé: ruído esticado na vertical (cristas que descem pela meda)
        fio = 0.016 * M.ruido(Vector((co.x * 30, co.y * 30, co.z * 2.5)), 2)
        fio += 0.007 * M.ruido(Vector((co.x * 90, co.y * 90, co.z * 6)), 6)
        # camadas: cada volta de palha (≈ 0,26 m) cobre a de baixo, como telha
        camada = 0.022 * ((co.z / 0.26 + 0.25 * M.ruido(q * 1.5, 8)) % 1.0)
        camada *= suave_passo(0.05, 0.25, co.z)
        beiral = 0.03 * math.exp(-(((co.z - 0.42) / 0.07) ** 2))
        cai = Vector((0, 0, -0.02 * max(0.0, M.fbm(q * 2, 2, 3))))
        return n * (tufo + fio + camada + beiral) + cai

    M.deslocar(corpo, palha)
    M.material(M.suave(corpo, 80), mat_palha("palha"))
    capuz = M.torno(
        "capuz",
        [
            (0.0, 2.02),
            (0.30, 2.02),
            (0.27, 2.12),
            (0.18, 2.27),
            (0.08, 2.42),
            (0.03, 2.50),
            (0.0, 2.51),
        ],
        segs=64,
        fatiar=0.03,
    )
    M.deslocar(capuz, lambda co, n: 0.02 * M.fbm(Vector((co.x * 6, co.y * 6, co.z * 1.5)), 3, 4))
    M.material(M.suave(capuz, 80), mat_palha("palha_capuz"))
    amarra = M.toro("amarra", 0.12, 0.012, 32, 8)
    M.mover(amarra, Matrix.Translation((0, 0, 2.30)))
    M.material(M.suave(amarra, 60), mat_corda("corda"))
    mastro = M.bambu(
        "mastro", (0.0, 0.0, 1.9), (0.02, 0.01, 2.82), 0.034, 0.028, entre_nos=0.32, segs=14, sem=5
    )
    M.material(M.suave(mastro, 50), mat_bambu("bambu_mastro"))
    return [corpo, capuz, amarra, mastro]


PERFIL_M26 = [
    (0.0, 0.0),
    (0.0055, 0.0003),
    (0.0095, 0.0018),
    (0.0175, 0.0062),
    (0.0236, 0.0140),
    (0.0272, 0.0260),
    (0.0284, 0.0380),
    (0.0286, 0.0432),
    (0.0290, 0.0440),
    (0.0286, 0.0448),
    (0.0281, 0.0520),
    (0.0262, 0.0600),
    (0.0229, 0.0680),
    (0.0185, 0.0750),
    (0.0142, 0.0800),
    (0.0126, 0.0830),
    (0.0, 0.0830),
]


def receita_grenade_m26():
    """Granada M26 (de pé): corpo de limão com a emenda no meio, espoleta M204, alavanca, anel e
    pino; verde-oliva com letreiro amarelo."""
    corpo = M.torno("corpo", PERFIL_M26, segs=48, fatiar=0.003)
    M.material(M.suave(corpo, 60), mat_tinta("tinta_m26", escala=900.0))
    espoleta = M.torno(
        "espoleta",
        [
            (0.0, 0.0825),
            (0.0118, 0.0825),
            (0.0118, 0.0905),
            (0.0108, 0.0915),
            (0.0102, 0.0968),
            (0.0086, 0.0990),
            (0.0, 0.0992),
        ],
        segs=32,
    )
    M.material(M.suave(espoleta, 45), mat_aco("aco_espoleta", "#8c8a78", 0.45, 900.0))
    caixa_perc = M.caixa("percussor", (0.010, 0.013, 0.009), (0.0085, 0.0, 0.0925))
    M.chanfrar(caixa_perc, 0.0008, 1)
    M.material(caixa_perc, mat_aco("aco_percussor", "#86847a", 0.45, 900.0))
    raio = M.raio_do_perfil(PERFIL_M26[:-1])
    pts = [(0.004, 0.0, 0.0985), (0.012, 0.0, 0.0975), (0.0158, 0.0, 0.0915)]
    for z in np.linspace(0.088, 0.036, 9):
        pts.append((raio(z) + 0.0016, 0.0, float(z)))
    pts.append((raio(0.033) + 0.0028, 0.0, 0.0325))
    alavanca = M.tubo("alavanca", pts, 0.0078, segs=8, achatar=0.11)
    M.material(M.suave(alavanca, 50), mat_tinta("tinta_alavanca", "#545839", escala=900.0))
    # anel no plano que contém o pino (Y), caído para baixo; passa pela ponta do pino
    anel = M.toro("anel", 0.0115, 0.00115, 32, 6)
    M.mover(anel, M.matriz((-0.004, 0.0238, 0.0905), (0.0, math.radians(70), 0.0)))
    M.material(M.suave(anel, 60), mat_aco("aco_anel", "#9b9a95", 0.32, 900.0))
    pino = M.tubo("pino", [(-0.002, 0.0, 0.0905), (-0.004, 0.0128, 0.0905)], 0.0009, 6)
    M.material(pino, mat_aco("aco_pino", "#9b9a95", 0.32, 900.0))
    amarelo = mat_estencil("letreiro_m26", "#c9a62f", "#4e5233", gasto=0.2, escala=900.0)
    letras = []
    for corpo_txt, z0, alt in (
        ("GRENADE HAND", 0.0515, 0.0038),
        ("FRAG M26", 0.0455, 0.0038),
        ("LOT 23-65", 0.0335, 0.0030),
    ):
        t = M.texto_malha(corpo_txt, alt, M.FONTE_LETREIRO)
        M.enrolar(t, raio, z0, ang0=math.pi, folga=0.00025)
        letras.append(so_bake(M.material(t, amarelo)))
    return [corpo, espoleta, caixa_perc, alavanca, anel, pino, *letras]


def receita_grenade_stick():
    """Granada de cabo do padrão chinês (deitada ao longo de X): cabeça de ferro pintada com a
    solda no meio, colar de aço, cabo de madeira e tampa de rosca na ponta."""
    cabeca = M.torno(
        "cabeca",
        [
            (0.0, 0.0),
            (0.0165, 0.0),
            (0.0235, 0.0025),
            (0.0272, 0.0085),
            (0.0275, 0.036),
            (0.0280, 0.0375),
            (0.0275, 0.039),
            (0.0275, 0.066),
            (0.0245, 0.0735),
            (0.0185, 0.0795),
            (0.0165, 0.0815),
            (0.0, 0.0815),
        ],
        segs=40,
        fatiar=0.004,
    )
    M.material(
        M.suave(cabeca, 50),
        mat_tinta("tinta_cabeca", "#3f4232", desgaste=0.8, ferrugem=True, escala=700.0),
    )
    colar = M.torno(
        "colar",
        [(0.0, 0.080), (0.0168, 0.080), (0.0168, 0.0905), (0.0145, 0.092), (0.0, 0.092)],
        segs=32,
    )
    M.material(M.suave(colar, 45), mat_aco("aco_colar", "#6d6b64", 0.5, 700.0))
    cabo = M.torno(
        "cabo",
        [(0.0, 0.0915), (0.0132, 0.0915), (0.0126, 0.150), (0.0122, 0.199), (0.0, 0.199)],
        segs=24,
        fatiar=0.01,
    )
    M.material(
        M.suave(cabo, 45), mat_madeira("cabo", "#a5804f", "#7a5734", "#8f7a5e", eixo="Z", rug=0.7)
    )
    tampa = M.torno(
        "tampa",
        [(0.0, 0.1985), (0.0138, 0.1985), (0.0140, 0.209), (0.0122, 0.2125), (0.0, 0.2128)],
        segs=24,
    )
    M.material(M.suave(tampa, 45), mat_aco("aco_tampa", "#5f5d57", 0.55, 700.0))
    pecas = [cabeca, colar, cabo, tampa]
    # deitada: a ponta do cabo desce até a tampa encostar no chão junto com a cabeça
    incl = math.asin((0.0275 - 0.0140) / 0.205)
    m = Matrix.Rotation(incl, 4, "Y") @ Matrix.Rotation(math.pi / 2, 4, "Y")
    for o in pecas:
        M.mover(o, m)
    return pecas


def receita_smoke_m18():
    """Fumaça M18 (deitada ao longo de X): lata com frisos nas pontas, 4 furos de saída, espoleta
    M201A1 com alavanca e anel; verde-oliva, topo e letreiro na cor da fumaça (amarelo)."""
    perfil = [
        (0.0, 0.0),
        (0.0300, 0.0),
        (0.0326, 0.0018),
        (0.0326, 0.0062),
        (0.0318, 0.0072),
        (0.0320, 0.0085),
        (0.0320, 0.1105),
        (0.0318, 0.1118),
        (0.0326, 0.1128),
        (0.0326, 0.1176),
        (0.0302, 0.1200),
        (0.0130, 0.1200),
        (0.0, 0.1200),
    ]
    lata = M.torno("lata", perfil, segs=48, fatiar=0.006)
    M.material(M.suave(lata, 45), mat_tinta("tinta_lata", "#4b5133", escala=700.0))
    topo = M.torno(
        "topo", [(0.0, 0.1196), (0.0298, 0.1196), (0.0298, 0.1203), (0.0, 0.1203)], segs=48
    )
    M.material(topo, mat_tinta("tinta_topo", "#c4a137", desgaste=0.4, escala=700.0))
    so_bake(topo)
    furos = []
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        f = M.torno(
            f"furo{k}", [(0.0, 0.1204), (0.0042, 0.1204), (0.0042, 0.1206), (0.0, 0.1206)], segs=16
        )
        M.mover(f, Matrix.Translation((0.021 * math.cos(a), 0.021 * math.sin(a), 0.0)))
        M.material(f, mat_oleo("furo"))
        furos.append(so_bake(f))
    espoleta = M.torno(
        "espoleta",
        [
            (0.0, 0.1195),
            (0.0108, 0.1195),
            (0.0108, 0.137),
            (0.0094, 0.140),
            (0.0088, 0.1455),
            (0.0, 0.146),
        ],
        segs=32,
    )
    M.material(M.suave(espoleta, 45), mat_aco("aco_m201", "#8a8878", 0.45, 700.0))
    pts = [(0.003, 0.0, 0.1455), (0.0115, 0.0, 0.1445), (0.0150, 0.0, 0.138), (0.0345, 0.0, 0.120)]
    for z in np.linspace(0.112, 0.052, 6):
        pts.append((0.0338, 0.0, float(z)))
    pts.append((0.0350, 0.0, 0.048))
    alavanca = M.tubo("alavanca", pts, 0.0075, segs=8, achatar=0.12)
    M.material(M.suave(alavanca, 50), mat_tinta("tinta_alavanca18", "#565a3a", escala=700.0))
    anel = M.toro("anel", 0.0115, 0.00115, 32, 6)
    M.mover(anel, M.matriz((-0.004, 0.0236, 0.134), (0.0, math.radians(70), 0.0)))
    M.material(M.suave(anel, 60), mat_aco("aco_anel18", "#9b9a95", 0.32, 700.0))
    pino = M.tubo("pino", [(-0.002, 0.0, 0.134), (-0.004, 0.0126, 0.134)], 0.0009, 6)
    M.material(pino, mat_aco("aco_pino18", "#9b9a95", 0.32, 700.0))
    amarelo = mat_estencil("letreiro_m18", "#c4a137", "#4b5133", gasto=0.25, escala=700.0)
    letras = []
    for txt, z0, alt in (
        ("GRENADE, HAND", 0.088, 0.0062),
        ("SMOKE YELLOW", 0.074, 0.0062),
        ("M18", 0.058, 0.0075),
    ):
        t = M.texto_malha(txt, alt, M.FONTE_LETREIRO)
        M.enrolar(t, lambda z: 0.0320, z0, ang0=math.pi / 2, folga=0.0003)
        letras.append(so_bake(M.material(t, amarelo)))
    pecas = [lata, topo, *furos, espoleta, alavanca, anel, pino, *letras]
    # deitada ao longo de X, com a alavanca para cima e o letreiro virado para -Y (frente)
    m = Matrix.Rotation(math.pi, 4, "X") @ Matrix.Rotation(math.pi / 2, 4, "Y")
    for o in pecas:
        M.mover(o, m)
    return pecas


def receita_ammo_crate():
    """Caixote de munição de madeira (padrão chinês, 7,62 x 39): tábuas com fresta, travessas,
    tampa pregada, alças de corda nas cabeceiras e estêncil."""
    Lx, Ly, Hc = 0.56, 0.336, 0.29
    mat = mat_caixote("caixote")
    pecas = []

    def tabua(nome, dim, centro, chanfro=0.0025):
        b = M.caixa(nome, dim, centro, cortes=1)
        M.chanfrar(b, chanfro, 2)
        M.deslocar(b, lambda co, n: 0.0006 * M.ruido(co * 40, len(pecas)))
        pecas.append(M.material(M.suave(b, 35), mat))
        return b

    tabua("fundo", (Lx - 0.004, Ly - 0.004, 0.018), (0, 0, 0.009))
    for s in (-1, 1):
        y = s * (Ly / 2 - 0.009)
        for k, (z0, z1) in enumerate(((0.018, 0.153), (0.155, Hc))):
            tabua(f"lado{s}{k}", (Lx, 0.018, z1 - z0 - 0.002), (0, y, (z0 + z1) / 2))
        x = s * (Lx / 2 - 0.011)
        tabua(f"cabeceira{s}", (0.022, Ly - 0.036, Hc - 0.018), (x, 0, (0.018 + Hc) / 2))
        for t in (-1, 1):
            tabua(
                f"sarrafo{s}{t}", (0.02, 0.05, Hc - 0.01), (s * (Lx / 2 + 0.01), t * 0.105, Hc / 2)
            )
    for k in range(3):
        y = -Ly / 2 + Ly / 6 + k * Ly / 3
        tabua(f"tampa{k}", (Lx + 0.004, Ly / 3 - 0.003, 0.02), (0, y, Hc + 0.01))
    for s in (-1, 1):
        tabua(f"travessa{s}", (0.032, Ly + 0.004, 0.018), (s * 0.19, 0, Hc + 0.029))
    prego = mat_aco("prego", "#3a3833", 0.6, 400.0)
    for s in (-1, 1):
        for x in (-0.25, 0.25, -0.08, 0.08):
            for z in (0.06, 0.22):
                pg = M.torno(
                    "prego", [(0.0, 0.0), (0.0022, 0.0), (0.0022, 0.0006), (0.0, 0.0009)], segs=8
                )
                M.mover(
                    pg,
                    Matrix.Translation((x, s * (Ly / 2), z))
                    @ Matrix.Rotation(-s * math.pi / 2, 4, "X"),
                )
                pecas.append(M.material(pg, prego))
    # alças de corda: entram pelos furos dos dois sarrafos de cada cabeceira e pendem no meio
    corda = mat_corda("corda_alca", "#8f7f58")
    for s in (-1, 1):
        pts = []
        for t in np.linspace(-1.0, 1.0, 21):
            curva = 1 - t * t
            pts.append((s * (Lx / 2 + 0.012 + 0.016 * curva), 0.105 * t, 0.235 - 0.05 * curva))
        alca = M.tubo("alca", pts, 0.0065, 8)
        pecas.append(M.material(M.suave(alca, 60), corda))
    tinta = mat_estencil("estencil", "#ddd6bd", "#4e5535", gasto=0.4)
    for s, normal in ((-1, "-Y"), (1, "+Y")):
        y = s * (Ly / 2 + 0.0004)
        pecas.append(letreiro_plano("7.62", 0.058, tinta, (0, y, 0.215), normal))
        pecas.append(letreiro_plano("1440", 0.034, tinta, (0, y, 0.12), normal))
        pecas.append(letreiro_plano("56-65  311", 0.02, tinta, (0, y, 0.07), normal))
    for s, normal in ((-1, "-X"), (1, "+X")):
        pecas.append(letreiro_plano("1440", 0.026, tinta, (s * (Lx / 2 + 0.0004), 0, 0.12), normal))
    tampa_txt = letreiro_plano("7.62", 0.05, tinta, (0, 0, Hc + 0.0204), "-Y")
    M.mover(
        tampa_txt,
        Matrix.Translation((0, 0, Hc + 0.0204))
        @ Matrix.Rotation(-math.pi / 2, 4, "X")
        @ Matrix.Translation((0, 0, -(Hc + 0.0204))),
    )
    pecas.append(tampa_txt)
    return pecas


def saco(
    nome,
    L,
    W,
    H,
    sem,
    pescoco=0.0,
    orelhas=0.0,
    achatar=0.4,
    rugas=1.0,
    seg=(64, 32),
    caroco=0.004,
):
    """Saco cheio deitado (eixo maior em X): almofada achatada embaixo e em cima pelo peso,
    pontas costuradas mais finas, `orelhas` (cantos da costura) ou `pescoco` amarrado;
    `caroco` = amplitude dos caroços do enchimento (m)."""
    a, b, c = L / 2, W / 2, H / 2
    obj = M.superelipsoide(nome, a, b, c, e1=0.55, e2=0.22, seg_u=seg[0], seg_v=seg[1])
    rng = np.random.default_rng(sem)
    torce = rng.uniform(-0.25, 0.25)

    def forma(co, n):
        x, y, z = co.x, co.y, co.z
        u = x / a
        if z < -c * achatar:
            z = -c * achatar + (z + c * achatar) * 0.22
        if z > c * 0.72:
            z = c * 0.72 + (z - c * 0.72) * 0.55
        t = suave_passo(0.5, 1.0, abs(u))
        z *= 1 - 0.5 * t
        y *= 1 + 0.05 * t
        if orelhas and u > 0:
            e = suave_passo(0.7, 1.0, u) * suave_passo(0.55, 1.0, abs(y) / b)
            x += orelhas * e
            z *= 1 - 0.55 * e
        if pescoco and u > 0:
            s = suave_passo(0.78, 1.0, u)
            y *= 1 - 0.78 * s
            z *= 1 - 0.72 * s
            x += pescoco * s
        z += torce * 0.02 * u * y / b
        p = Vector((x, y, z))
        d = 0.0035 * rugas * M.fbm(p * 22, 4, sem)
        d += 0.0022 * rugas * M.ruido(Vector((x * 5, y * 70, z * 70)), sem + 1)
        d += caroco * M.fbm(p * 7, 2, sem + 2)
        return (p - co) + n * d

    M.deslocar(obj, forma)
    M.gravar_local(obj, float(sem))
    return obj


def receita_rice_sack():
    """Saco de arroz de juta cheio, deitado, com as orelhas da costura e duas listras."""
    s = saco(
        "saco_arroz",
        0.45,
        0.34,
        0.25,
        4,
        orelhas=0.022,
        achatar=0.45,
        rugas=1.7,
        seg=(96, 48),
        caroco=0.009,
    )
    M.material(M.suave(s, 80), mat_juta("juta_arroz", listras=True, z_sujo=0.06))
    return [s]


def receita_clay_lamp():
    """Lamparina de barro de pé (đèn dầu): copo com bico beliscado, pavio, alça e óleo."""
    perfil = [
        (0.0, 0.0),
        (0.040, 0.0),
        (0.0435, 0.0035),
        (0.039, 0.010),
        (0.024, 0.019),
        (0.0165, 0.032),
        (0.0165, 0.047),
        (0.022, 0.054),
        (0.038, 0.059),
        (0.051, 0.066),
        (0.0555, 0.0725),
        (0.0548, 0.0785),
        (0.0512, 0.0805),
        (0.0468, 0.0770),
        (0.031, 0.0690),
        (0.0, 0.0665),
    ]
    corpo = M.torno("lamparina", perfil, segs=64, fatiar=0.004)

    def bico(co, n):
        a = math.atan2(co.y, co.x)
        # bico: a borda puxada para fora e para cima na frente (+X), beliscada dos lados
        g = math.exp(-((a / 0.36) ** 2)) * suave_passo(0.056, 0.076, co.z)
        r = math.hypot(co.x, co.y)
        aperto = math.exp(-(((abs(a) - 0.5) / 0.14) ** 2)) * suave_passo(0.058, 0.076, co.z)
        dr = 0.022 * g - 0.009 * aperto
        dz = 0.006 * g
        k = (r + dr) / max(r, 1e-6)
        feito_a_mao = 0.0007 * M.fbm(co * 80, 3, 9)
        return Vector((co.x * (k - 1), co.y * (k - 1), dz)) + n * feito_a_mao

    M.deslocar(corpo, bico)
    M.material(M.suave(corpo, 70), mat_barro_lamp())
    # óleo: disco de verdade (entra na malha), do raio da parede de dentro na altura do nível
    oleo = M.torno(
        "oleo", [(0.0, 0.0688), (0.0316, 0.0688), (0.0316, 0.0694), (0.0, 0.0694)], segs=48
    )
    M.material(oleo, mat_oleo("oleo"))
    pavio = M.tubo(
        "pavio",
        [(0.010, 0.0, 0.0696), (0.035, 0.0, 0.0735), (0.060, 0.0, 0.0805), (0.0755, 0.0, 0.0872)],
        [0.0022, 0.0025, 0.0024, 0.0016],
        8,
    )
    pm = Mat("pavio", rug=0.95)
    pz = pm.separar(pm.coord("objeto"))[0]
    pm.cor(pm.misturar(pm.faixa(pz, 0.055, 0.066), rgb("#cbbf9e"), rgb("#1a1511")))
    pm.relevo(pm.onda(pm.coord("objeto"), periodo(0.003), "X", distorcao=2.0), 0.4, 0.0004)
    M.material(M.suave(pavio, 60), pm.m)
    # alça em laço atrás (-X): sai da borda e volta ao bojo (curva de Bézier no plano XZ)
    p0, p1, p2, p3 = (-0.051, 0.0775), (-0.080, 0.081), (-0.078, 0.057), (-0.046, 0.0615)
    laco = []
    for t in np.linspace(0.0, 1.0, 16):
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        z = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        laco.append((x, 0.0, z))
    alca = M.tubo("alca", laco, 0.0032, 10)
    M.material(M.suave(alca, 60), mat_barro_lamp("barro_alca"))
    return [corpo, oleo, pavio, alca]


def mat_barro_lamp(nome="barro_lamparina"):
    """Barro da lamparina: o barro do pote mais a fuligem perto do bico e o óleo escorrido."""
    m = Mat(nome, rug=0.85)
    p = m.coord("objeto")
    x, y, z = m.separar(p)
    manchas = m.ruido(p, 60.0, 6, 0.6)
    cor = m.rampa(manchas, [(0.3, rgb("#5b3824")), (0.72, rgb("#7f5238"))])
    cor = m.misturar(m.faixa(m.ruido(p, 400.0, 3), 0.58, 0.78, 0, 0.3), cor, rgb("#c08e66"))
    d = m.no("ShaderNodeVectorMath", operation="DISTANCE")
    m._set(d.inputs[0], p)
    d.inputs[1].default_value = (0.068, 0.0, 0.085)
    fuligem = m.conta(
        "MULTIPLY", m.faixa(d.outputs["Value"], 0.05, 0.004), m.faixa(m.ruido(p, 90.0), 0.3, 0.6)
    )
    cor = m.misturar(fuligem, cor, rgb("#17120e"))
    oleo = m.conta(
        "MULTIPLY",
        m.faixa(m.ruido(m.mapear(p, (220, 220, 25)), 1.0, 3), 0.55, 0.68),
        m.conta("MULTIPLY", m.faixa(x, 0.02, 0.05), m.faixa(z, 0.03, 0.07)),
    )
    cor = m.misturar(m.conta("MULTIPLY", oleo, 0.7), cor, rgb("#3a2414"))
    m.cor(cor)
    m.rug(m.misturar_valor(oleo, 0.86, 0.35))
    m.relevo(m.ruido(p, 900.0, 3), 0.15, 0.0003)
    m.relevo(m.onda(p, periodo(0.0025), "Z", distorcao=1.0), 0.12, 0.0003)
    return m.m


def receita_sandbag_wall():
    """Parede de sacos de areia de 1,5 m de altura e 2 m de frente: fiadas alternadas de
    comprido (2 fileiras) e de cabeça (atravessadas), frente com recuo por fiada (talude), meios
    sacos nas pontas e pescoço amarrado para trás ou para os lados."""
    L, W, H = 0.50, 0.28, 0.135
    n_fiadas = 12
    passo = 1.5 / n_fiadas
    recuo = 0.011
    rng = np.random.default_rng(65)
    sacos = []
    sem = 100
    for k in range(n_fiadas):
        zc = passo * k + passo / 2
        comp = 1.0 - 0.025 * k / n_fiadas
        frente = -0.135 + recuo * k
        if k % 2 == 0:
            if k % 4 == 0:
                xs = [(-0.75, L), (-0.25, L), (0.25, L), (0.75, L)]
            else:
                xs = [(-0.875, L / 2), (-0.5, L), (0.0, L), (0.5, L), (0.875, L / 2)]
            for y in (frente, 0.135):
                for x, comp_saco in xs:
                    sem += 1
                    s = saco(
                        "saco",
                        comp_saco - 0.01,
                        W,
                        H * comp,
                        sem,
                        pescoco=0.035 if comp_saco == L else 0.0,
                    )
                    vira = math.pi if rng.random() < 0.5 else 0.0
                    m = M.matriz(
                        (x + rng.uniform(-0.012, 0.012), y + rng.uniform(-0.01, 0.01), zc),
                        (
                            rng.uniform(-0.02, 0.02),
                            rng.uniform(-0.02, 0.02),
                            vira + rng.uniform(-0.04, 0.04),
                        ),
                    )
                    sacos.append(M.mover(s, m))
        else:
            yc = (frente + 0.135) / 2
            for i in range(7):
                sem += 1
                s = saco("saco", L, W - 0.006, H * comp, sem, pescoco=0.035)
                x = -0.84 + i * 0.28
                m = M.matriz(
                    (x + rng.uniform(-0.01, 0.01), yc + rng.uniform(-0.015, 0.015), zc),
                    (
                        rng.uniform(-0.02, 0.02),
                        rng.uniform(-0.02, 0.02),
                        math.pi / 2 + rng.uniform(-0.05, 0.05),
                    ),
                )
                sacos.append(M.mover(s, m))
    parede = M.juntar(sacos, "parede")
    M.material(
        M.suave(parede, 80), mat_juta("juta_areia", "#a3916a", "#6c5c40", "#5a4a33", z_sujo=0.35)
    )
    return [parede]


def receita_conical_hat():
    """Nón lá: cone de folha de palmeira sobre 16 aros, aro de bambu na borda (de borda no chão).
    Sem a fita do queixo (ficaria embaixo, pendurada no chão)."""
    R, Hh, esp = 0.200, 0.190, 0.004
    n = 24
    # casca fechada: borda de fora -> ápice por fora -> ápice por dentro -> borda de dentro ->
    # de volta à borda de fora (o furinho do ápice fica coberto pela `ponta`)
    fora = [(R * (1 - t), 0.006 + (Hh - 0.006) * (t**0.97)) for t in np.linspace(0, 0.992, n)]
    dentro = [(max(0.0007, r - esp * 1.05), z - esp) for r, z in reversed(fora)]
    borda = (R - 0.0015, 0.0025)
    perfil = [borda, *fora, *dentro, (R - esp - 0.0015, 0.0025), borda]
    chapeu = M.torno("nonla", perfil, segs=96)
    M.deslocar(chapeu, lambda co, nn: 0.0009 * M.fbm(co * 18, 3, 21))
    M.material(M.suave(chapeu, 50), mat_nonla("folha"))
    aro = M.toro("aro", R - 0.0015, 0.0042, 96, 8)
    M.mover(aro, Matrix.Translation((0, 0, 0.0042)))
    M.material(M.suave(aro, 60), mat_bambu("bambu_aro", "#b3a77a", "#8e8256"))
    ponta = M.torno("ponta", [(0.0, Hh - 0.004), (0.004, Hh - 0.004), (0.0, Hh + 0.0012)], segs=16)
    M.material(ponta, mat_nonla("folha_ponta"))
    return [chapeu, aro, ponta]


def pano(nome, largura, pende, x0, z_vara, r_vara, sem, pernas=False, bainha=0.0):
    """Pano dobrado sobre a vara: retângulo de `largura` (X) que passa por cima da vara e cai
    `pende` m de cada lado, com dobras verticais, peso nas pontas e bainha irregular. Com
    `pernas`, a parte de baixo se divide em duas (calça)."""
    rc = r_vara + 0.003
    arco = math.pi * rc
    total = 2 * pende + arco
    nu, nv = max(8, int(largura / 0.012)), max(16, int(total / 0.012))
    rng = np.random.default_rng(sem)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grade = {}
    for i in range(nu + 1):
        for j in range(nv + 1):
            u = -largura / 2 + largura * i / nu
            s = -total / 2 + total * j / nv
            if abs(s) <= arco / 2:
                ang = s / rc
                y, z = rc * math.sin(ang), z_vara + rc * math.cos(ang)
                cai = 0.0
            else:
                cai = abs(s) - arco / 2
                y = math.copysign(rc + 0.02 * cai, s)
                z = z_vara - cai
            onda = (0.012 + 0.02 * min(1.0, cai / 0.3)) * math.sin(
                u * 2 * math.pi / 0.11
                + rng.uniform(0, 0.4)
                + 1.3 * M.ruido(Vector((u * 9, s * 3, sem)))
            )
            y += math.copysign(1, s if s != 0 else 1) * 0.6 * onda * min(1.0, cai / 0.15)
            corte = bainha * M.ruido(Vector((u * 12, sem, 0.0)))
            if cai > pende - 0.02 + corte:
                continue
            if pernas and cai > pende * 0.45 and abs(u) < 0.035:
                continue
            grade[(i, j)] = bm.verts.new((x0 + u + 0.004 * onda, y, z))
    for i in range(nu):
        for j in range(nv):
            q = [grade.get(k) for k in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            if None in q:
                continue
            f = bm.faces.new(q)
            for lp, (a, b) in zip(
                f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)), strict=True
            ):
                lp[uvl].uv = (a / nu * largura / 0.5, b / nv * total / 0.5)
    obj = M.de_bmesh(nome, bm)
    M.solidificar(obj, 0.0025, 0.0)
    return obj


def receita_bamboo_clothesline():
    """Varal de bambu: vara de 3,2 m em cima de dois cavaletes em X amarrados com corda, com
    camisa preta (áo bà ba), calça escura e um khăn rằn (lenço xadrez) pendurados."""
    pecas = []
    bam = mat_bambu("bambu_varal")
    z_cruz = 1.70
    for sx in (-1, 1):
        x = sx * 1.45
        for sy in (-1, 1):
            topo = 2.0
            xp = x + sy * 0.022  # as duas pernas passam uma do lado da outra no cruzamento
            b = M.bambu(
                f"perna{sx}{sy}",
                (xp, sy * 0.35, 0.0),
                (xp, -sy * 0.06, topo),
                0.024,
                0.019,
                entre_nos=0.33,
                segs=12,
                sem=30 + sx * 3 + sy,
            )
            pecas.append(M.material(M.suave(b, 50), bam))
        for k in range(4):
            amarra = M.toro("amarra", 0.05, 0.005, 24, 6)
            M.mover(
                amarra,
                Matrix.Translation((x, 0.0, z_cruz - 0.03 + k * 0.012))
                @ Matrix.Rotation(math.radians(8 * (k - 1.5)), 4, "X"),
            )
            pecas.append(M.material(M.suave(amarra, 60), mat_corda("corda_varal", "#8d7c56")))
    vara = M.bambu(
        "vara",
        (-1.62, 0.0, z_cruz + 0.045),
        (1.62, 0.0, z_cruz + 0.05),
        0.022,
        0.019,
        entre_nos=0.35,
        segs=12,
        sem=40,
    )
    pecas.append(M.material(M.suave(vara, 50), bam))
    zv, rv = z_cruz + 0.047, 0.021
    camisa = pano("camisa", 0.56, 0.44, -0.62, zv, rv, 1, bainha=0.02)
    M.material(M.suave(camisa, 60), mat_pano("pano_preto", "#252220", "#3e3a34"))
    calca = pano("calca", 0.44, 0.80, 0.25, zv, rv, 2, pernas=True, bainha=0.015)
    M.material(M.suave(calca, 60), mat_pano("pano_marrom", "#2e2923", "#4a4237"))
    lenco = pano("lenco", 0.30, 0.55, 0.92, zv, rv, 3, bainha=0.01)
    M.material(M.suave(lenco, 60), mat_pano("pano_xadrez", "#1c1b19", "#3a3631", "#d6d1c3"))
    pecas += [camisa, calca, lenco]
    return pecas


# =============================================================== versão em peças (hoje)
def _rbx(x, y, z):
    """Posição do Roblox (studs, Y em cima) -> Blender (m, Z em cima)."""
    return Vector((x * STUD, -z * STUD, y * STUD))


def p_bloco(dim, pos, rot=(0, 0, 0)):
    o = M.caixa("bloco", (dim[0] * STUD, dim[2] * STUD, dim[1] * STUD))
    return M.mover(o, Matrix.Translation(_rbx(*pos)) @ M.matriz((0, 0, 0), rot))


def p_cilindro(comp, diam, pos, em_pe=False, segs=24):
    """Cilindro do Roblox (eixo X); `em_pe` = CFrame.Angles(0, 0, pi/2)."""
    o = M.torno(
        "cil",
        [(0, 0), (diam * STUD / 2, 0), (diam * STUD / 2, comp * STUD), (0, comp * STUD)],
        segs=segs,
    )
    M.mover(o, Matrix.Translation((0, 0, -comp * STUD / 2)))
    if not em_pe:
        M.mover(o, Matrix.Rotation(math.pi / 2, 4, "Y"))
    return M.mover(o, Matrix.Translation(_rbx(*pos)))


def p_bola(dims, pos):
    """Bola (Part Ball usa o menor lado) ou SpecialMesh Sphere (elipsoide do tamanho)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.5)
    o = bpy.context.active_object
    M.mover(o, Matrix.Diagonal((dims[0] * STUD, dims[2] * STUD, dims[1] * STUD, 1.0)))
    return M.mover(o, Matrix.Translation(_rbx(*pos)))


CORES_LUAU = {
    "CLAY": "#965638",
    "CLAY_DARK": "#70402a",
    "STRAW": "#ba9c5c",
    "BAMBOO": "#a49260",
    "SACK": "#c4b48c",
    "CRATE": "#4e5434",
    "OLIVE": "#4a5030",
    "IRON": "#3a3a36",
    "WOOD": "#82603c",
    "AGUA": "#3a423a",
    "TAMPA18": "#c4c4ba",
}


def pecas_water_jar():
    d = 2.3
    return [
        ("Pote", p_bola((d, d, d), (0, d * 0.42, 0)), "CLAY", 0.8),
        ("Boca", p_cilindro(0.45, 1.5, (0, d * 0.88, 0), True), "CLAY_DARK", 0.8),
        ("Agua", p_cilindro(0.05, 1.2, (0, d * 0.88 + 0.2, 0), True), "AGUA", 0.1),
    ]


def pecas_straw_stack():
    out = []
    top = 0.0
    for d, cy in ((6.4, 0.55), (4.2, 2.6), (2.4, 4.2)):
        out.append(("Palha", p_bola((d, d, d), (0, cy, 0)), "STRAW", 0.95))
        top = cy + d / 2
    out.append(("Mastro", p_bloco((0.25, top + 1.2, 0.25), (0, (top + 1.2) / 2, 0)), "BAMBOO", 0.8))
    return out


def pecas_grenade_m26():
    k = 1 / STUD
    c = 0.0425 * k
    return [
        ("Corpo", p_bola((0.057 * k, 0.085 * k, 0.057 * k), (0, c, 0)), "OLIVE", 0.5),
        ("Espoleta", p_cilindro(0.022 * k, 0.022 * k, (0, c + 0.05 * k, 0), True), "IRON", 0.4),
        (
            "Alavanca",
            p_bloco(
                (0.008 * k, 0.075 * k, 0.016 * k),
                (0.032 * k, c + 0.012 * k, 0),
                (0, math.radians(8), 0),
            ),
            "IRON",
            0.4,
        ),
    ]


def pecas_grenade_stick():
    k = 1 / STUD
    c = 0.0275 * k
    return [
        ("Cabeca", p_cilindro(0.09 * k, 0.055 * k, (-0.05 * k, c, 0)), "IRON", 0.4),
        ("Cabo", p_cilindro(0.16 * k, 0.026 * k, (0.075 * k, c, 0)), "WOOD", 0.7),
        ("Tampa", p_cilindro(0.01 * k, 0.03 * k, (0.158 * k, c, 0)), "IRON", 0.4),
    ]


def pecas_smoke_m18():
    k = 1 / STUD
    c = 0.03 * k
    return [
        ("Lata", p_cilindro(0.145 * k, 0.06 * k, (0, c, 0)), "OLIVE", 0.5),
        ("Tampa", p_cilindro(0.012 * k, 0.061 * k, (0.07 * k, c, 0)), "TAMPA18", 0.5),
    ]


def pecas_ammo_crate():
    return [("Caixote", p_bloco((2.0, 1.1, 1.2), (0, 0.55, 0)), "CRATE", 0.75)]


def pecas_rice_sack():
    return [("SacoDeArroz", p_bloco((1.6, 0.9, 1.2), (0, 0.45, 0)), "SACK", 0.95)]


def pecas_clay_lamp():
    return [("Lamparina", p_bloco((0.45, 0.3, 0.45), (0, 0.15, 0)), "CLAY", 0.8)]


def pecas_conical_hat():
    k = 1 / STUD
    out = []
    for i, (d, h) in enumerate(((0.40, 0.05), (0.29, 0.05), (0.18, 0.05), (0.07, 0.04))):
        out.append(
            ("Aba", p_cilindro(h * k, d * k, (0, (0.05 * i + h / 2) * k, 0), True), "STRAW", 0.9)
        )
    return out


def pecas_bamboo_clothesline():
    k = 1 / STUD
    out = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            b = p_cilindro(2.0 * k, 0.045 * k, (0, 0, 0), True, segs=12)
            M.mover(
                b,
                Matrix.Translation((sx * 1.45, 0, 1.0))
                @ Matrix.Rotation(sy * math.atan2(0.41, 2.0), 4, "X"),
            )
            out.append(("Perna", b, "BAMBOO", 0.7))
    out.append(("Vara", p_cilindro(3.24 * k, 0.042 * k, (0, 1.745 * k, 0), segs=12), "BAMBOO", 0.7))
    for x, w, h, cor in (
        (-0.62, 0.56, 0.44, "IRON"),
        (0.25, 0.44, 0.80, "WOOD"),
        (0.92, 0.30, 0.55, "SACK"),
    ):
        out.append(
            ("Pano", p_bloco((w * k, h * k, 0.06 * k), (x * k, (1.70 - h / 2) * k, 0)), cor, 0.95)
        )
    return out


def exportar_pecas(partes, caminho: Path) -> dict:
    """GLB da versão em peças: cada peça com cor lisa (baseColorFactor), sem textura."""
    g = glb.Glb()
    tris = 0
    for nome, obj, cor, rug in partes:
        lin = rgb(CORES_LUAU[cor])
        mi = g.material(nome, None, rugosidade=rug, cor_fator=lin)
        obj.data.update()
        p, n, t, idx = C.arrays_malha(obj)
        p, n, t = glb.de_blender(p, n, t)
        g.mesh(nome, p, n, None, idx, mi)
        tris += len(idx) // 3
    caminho.parent.mkdir(parents=True, exist_ok=True)
    data = g.bytes()
    caminho.write_bytes(data)
    return {"triangulos": tris, "mb": round(len(data) / 2**20, 3), "pecas": len(partes)}


# =============================================================== catálogo
NOVOS: dict[str, dict] = {
    "water_jar": {
        "nome": "pote d'água de barro (chum) com tampa",
        "classe": "prop",
        "suave": 70,
        "pecas": "MapLife.luau jar() (s = 1)",
        "medidas": {
            "altura_pote_m": [
                0.706,
                "anúncios de antiquário de jarras d'água vietnamitas "
                "(1stdibs, Chairish): 59-75 cm; escolhido dentro da faixa",
            ],
            "diametro_max_m": [0.60, "mesmas fontes: 41-64 cm; o jar() do jogo usa 0,64 m"],
            "tampa_cuia": [None, "PLACEHOLDER: tampa de tábuas Ø 0,43 m e cuia de coco Ø 0,13 m"],
        },
    },
    "straw_stack": {
        "nome": "meda de palha (đống rơm) com mastro",
        "classe": "prop",
        "suave": 80,
        "pecas": "MapLife.luau strawStack() (s = 1)",
        "medidas": {
            "diametro_m": [1.94, "PLACEHOLDER (o strawStack() do jogo usa 1,79 m)"],
            "altura_meda_m": [2.18, "PLACEHOLDER"],
            "altura_mastro_m": [2.82, "PLACEHOLDER (o do jogo vai a 1,85 m)"],
        },
    },
    "grenade_m26": {
        "nome": "granada M26",
        "classe": "pequeno",
        "suave": 55,
        "metal": True,
        "forca_ao": 0.35,
        "pecas": "GrenadeArt.luau (M26)",
        "medidas": {
            "diametro_m": [0.057, "Wikipedia, M26 grenade: 57 mm (2 1/4 pol)"],
            "altura_m": [0.099, "Wikipedia, M26 grenade: 99 mm (3 7/8 pol)"],
            "letreiro": [None, "PLACEHOLDER: texto e lote do letreiro amarelo"],
        },
    },
    "grenade_stick": {
        "nome": "granada de cabo chinesa",
        "classe": "pequeno",
        "suave": 50,
        "metal": True,
        "forca_ao": 0.35,
        "pecas": "GrenadeArt.luau (VC)",
        "medidas": {
            "comprimento_m": [
                0.213,
                "Type 67: ~20-21 cm (Wikipedia e anúncios da IMA, "
                "8 a 8 1/4 pol); o modelo de 1965 exato não foi achado",
            ],
            "diametro_cabeca_m": [0.055, "GrenadeArt.luau (D-77), sem fonte: PLACEHOLDER"],
        },
    },
    "smoke_m18": {
        "nome": "lata de fumaça M18",
        "classe": "pequeno",
        "suave": 45,
        "metal": True,
        "forca_ao": 0.35,
        "pecas": "GrenadeArt.luau (smoke)",
        "medidas": {
            "diametro_m": [0.064, "Wikipedia, M18 smoke grenade: 2,5 pol (64 mm)"],
            "comprimento_m": [0.146, "Wikipedia, M18 smoke grenade: 5,75 pol (146 mm, anos 60)"],
            "cor_fumaca": [None, "amarela (escolha; o topo e o letreiro seguem a cor)"],
        },
    },
    "ammo_crate": {
        "nome": "caixote de munição de madeira com estêncil",
        "classe": "prop",
        "suave": 35,
        "pecas": "MapLife.luau crates() (um caixote)",
        "medidas": {
            "corpo_m": [
                [0.56, 0.336, 0.31],
                "PLACEHOLDER: o caixote do jogo (2,0 x 1,2 x 1,1 studs); travessas e alças "
                "por fora",
            ],
            "estencil": [
                None,
                "PLACEHOLDER: '7.62 / 1440 / 56-65 311' não foi conferido num caixote real",
            ],
        },
    },
    "rice_sack": {
        "nome": "saco de arroz de juta",
        "classe": "pequeno",
        "suave": 80,
        "pecas": "MapLife.luau sacks() (um saco)",
        "medidas": {
            "saco_m": [
                [0.45, 0.34, 0.25],
                "PLACEHOLDER: o saco do jogo (1,6 x 1,2 x 0,9 studs = 0,45 x 0,34 x 0,25 m)",
            ],
        },
    },
    "clay_lamp": {
        "nome": "lamparina de barro",
        "classe": "pequeno",
        "suave": 70,
        "forca_ao": 0.45,
        "pecas": "MapLife.luau lamp() (só o corpo; o nicho e a chama ficam no jogo)",
        "medidas": {
            "copo_m": [
                [0.112, 0.087],
                "PLACEHOLDER: Ø do copo e altura; a lamparina do jogo tem 0,126 x 0,084 m",
            ],
        },
    },
    "sandbag_wall": {
        "nome": "parede de sacos de areia de 1,5 m",
        # 84 sacos: no teto de prop (5 mil) cada saco ficava com ~60 triângulos e quinas; é uma
        # obra de fortificação de 2 x 1,5 m, então vai na meta de construção (8 mil)
        "classe": "construcao",
        "suave": 80,
        "comparar_com": "assets/forgegui/models/sacos_areia_studs_fosco.glb",
        "rotulo_antigo": "ANTIGO (sandbags do jogo, 0,67 m)",
        "medidas": {
            "altura_m": [1.5, "pedido do dono (interpretado como altura; 2 m de frente)"],
            "saco_vazio_m": [[0.36, 0.66], "Wikipedia, Sandbag: 14 x 26 pol, o tamanho mais comum"],
            "saco_cheio_m": [[0.5, 0.28, 0.135], "PLACEHOLDER: o saco de 14 x 26 pol cheio a ~3/4"],
        },
    },
    "conical_hat": {
        "nome": "chapéu cônico (nón lá)",
        "classe": "pequeno",
        "suave": 50,
        "pecas": "hipótese: o jogo não tem nón lá (cilindros empilhados; o Roblox não tem cone)",
        "rotulo_antigo": "PEÇAS (hipótese; não existe no jogo)",
        "medidas": {
            "diametro_m": [0.40, "anúncio de nón lá tradicional de 16 aros (40 cm)"],
            "altura_m": [0.19, "anúncio (16 x 8 pol ≈ 40 x 20 cm); 16 aros: vietnamtourism.com"],
        },
    },
    "bamboo_clothesline": {
        "nome": "varal de bambu",
        "classe": "prop",
        "suave": 55,
        "pecas": "hipótese: o jogo não tem varal (cilindros e blocos)",
        "rotulo_antigo": "PEÇAS (hipótese; não existe no jogo)",
        "medidas": {
            "vara_m": [3.24, "PLACEHOLDER"],
            "altura_m": [2.0, "PLACEHOLDER (vara a 1,75 m)"],
        },
    },
}


# =============================================================== pipeline
def normalizar(objs) -> None:
    """Centro da caixa em X/Y na origem e Z mínimo = 0 (todos juntos)."""
    los, his = zip(*(C.caixa(o) for o in objs), strict=True)
    lo, hi = np.min(los, axis=0), np.max(his, axis=0)
    t = Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    for o in objs:
        M.mover(o, t)


def previa_alta(altos, caminho: Path, azimute: float = 40.0) -> None:
    """Prévia da peça alta (materiais procedurais) em Cycles na CPU, sem tocar na GPU: serve para
    conferir forma e material enquanto outro render ocupa a placa."""
    import comparar as K

    cena = bpy.context.scene
    K.configurar(cena, 24)
    cena.cycles.device = "CPU"
    cena.cycles.denoiser = "OPENIMAGEDENOISE"
    cena.render.resolution_percentage = 60
    piso = C.chao(z=0.0)
    piso.data.materials.append(K.material_chao())
    pts = np.concatenate([K.pontos([o], 1500) for o in altos])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    K.camera(lo, hi, azimute, pts)
    K.sol(azimute + 70.0)
    cena.render.filepath = str(caminho)
    bpy.ops.render.render(write_still=True)


def juntar_copias(objs, nome):
    copias = [C.copiar(o, f"{nome}_{i}") for i, o in enumerate(objs)]
    return M.juntar(copias, nome) if len(copias) > 1 else copias[0]


def main() -> None:
    a = C.argumentos()
    chave = a[0]
    cfg = NOVOS[chave]
    classe = C.CLASSES[cfg["classe"]]
    tex = classe["tex"]
    t0 = time.time()
    cena = C.cena_vazia()
    C.preparar_bake(cena)
    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    pasta.mkdir(parents=True, exist_ok=True)
    trab.mkdir(parents=True, exist_ok=True)

    altos = globals()[f"receita_{chave}"]()
    normalizar(altos)
    if "--previa" in a:
        az = float(a[a.index("--previa") + 1]) if len(a) > a.index("--previa") + 1 else 40.0
        previa_alta(altos, trab / f"previa_alta_{int(az)}.png", az)
        C.log("ok", chave, "prévia da alta", sum(C.triangulos(o) for o in altos), "tri")
        return
    geo = [o for o in altos if not o.get("so_bake")]
    alto_ref = juntar_copias(geo, "alto_ref")
    tris_alto = C.triangulos(alto_ref)
    C.log("alta", chave, tris_alto, "triângulos em", len(altos), "objetos")
    base = C.copiar(alto_ref, "base")
    if tris_alto > PRE_REDUCAO:
        C.reduzir(base, PRE_REDUCAO, planar_graus=0.5)
    limpeza = C.limpar(base, escondidas=True, n_dir=96)
    C.log("limpeza", limpeza)
    baixo, tentativas = C.escolher_alvo(base, classe["teto"])
    C.normais_para_fora(baixo)
    C.suavizar(baixo, cfg.get("suave", 60))
    n_ilhas = C.desdobrar(baixo, margem=4 / tex)
    # desvio contra a base limpa (sem as faces escondidas, que o baixo não tem de propósito)
    d = C.desvio(baixo, base, n=20000)
    C.log("desvio final", d)
    diag = C.diagonal(alto_ref)
    medidas_alto = C.medidas(alto_ref)
    bpy.data.objects.remove(base)
    bpy.data.objects.remove(alto_ref)

    saida = pasta / f"{chave}.glb"
    res = C.produzir(
        cena,
        baixo,
        altos,
        tex,
        trab,
        saida,
        chave,
        forca_ao=cfg.get("forca_ao", 0.6),
        metal=cfg.get("metal", False),
    )
    exp = res["exportacao"]

    # versão de hoje para a comparação
    if "comparar_com" in cfg:
        arq = C.RAIZ / cfg["comparar_com"]
        antigo = {
            "arquivo": cfg["comparar_com"],
            "rotulo": cfg["rotulo_antigo"],
            "triangulos": glb.triangulos(arq),
            "texturas_px": {"cor": [4096, 4096]},
            "mb": round(arq.stat().st_size / 2**20, 3),
            "fonte": "GLB do jogo (ForgeGUI)",
        }
    else:
        for o in list(bpy.data.objects):
            o.hide_render = True
        partes = globals()[f"pecas_{chave}"]()
        arq = trab / f"{chave}_pecas.glb"
        info = exportar_pecas(partes, arq)
        antigo = {
            "arquivo": f"assets/blender/_trabalho/{chave}/{arq.name}",
            "rotulo": cfg.get("rotulo_antigo", "PEÇAS (Roblox, cor lisa)"),
            "triangulos": info["triangulos"],
            "pecas": info["pecas"],
            "mb": info["mb"],
            "fonte": cfg["pecas"],
            "obs": "aproximação: cor lisa, sem as texturas de material do Roblox; os triângulos "
            "são da aproximação no Blender, não da Part do Roblox",
        }
    metricas = pasta / "metricas.json"
    if metricas.is_file():
        metricas.unlink()
    C.gravar_json(
        metricas,
        {
            "chave": chave,
            "tipo": "novo",
            "nome": cfg["nome"],
            "classe": cfg["classe"],
            "meta_triangulos": classe["teto"],
            "medidas_reais": cfg["medidas"],
            "antigo": antigo,
            "alta": {"triangulos": tris_alto, "objetos": len(altos), **medidas_alto},
            "novo": {
                "arquivo": f"assets/blender/{chave}/{saida.name}",
                "triangulos": exp["triangulos"],
                "triangulos_glb": glb.triangulos(saida),
                "texturas_px": res["texturas_px"],
                "mb": exp["mb"],
                "uso_uv": C.uso_uv(baixo),
                "ilhas_uv": n_ilhas,
                **C.medidas(baixo),
            },
            "desvio_m": d,
            "diagonal_m": round(diag, 3),
            "limpeza": limpeza,
            "tolerancia_fracao_diagonal": C.TOLERANCIA,
            "tentativas": tentativas,
            "bake": res["bake"],
            "tempo_total_s": round(time.time() - t0, 1),
        },
    )
    C.log("ok", chave, exp, "em", round(time.time() - t0, 1), "s")


if __name__ == "__main__":
    main()
