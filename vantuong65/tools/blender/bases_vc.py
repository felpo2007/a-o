"""Receitas da base do VC (acampamento na mata, Quảng Ngãi, 1965). Catálogo, medidas e fontes em
`bases.py`; peças e materiais em `bases_comum.py`. Metros, Z para cima, frente em -Y."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bases_comum as B  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
from bases_comum import Mat, Receita, corda, grade, rgb, vara  # noqa: E402

INCLINACAO = math.radians(38)  # folha de palmeira: mínimo 1:1,5 (~34°), melhor 45° (FAO)


def mat_folhagem(nome):
    """Folhas verdes cortadas (camuflagem): manchas de folha, verde-escuro a amarelado."""
    m = Mat(nome, rug=0.6)
    p = m.coord("objeto")
    cel = m.voronoi(p, 28.0, saida="Color")
    c = m.rampa(
        m.separar(cel)[0],
        [
            (0.0, rgb("#2c3b1d")),
            (0.4, rgb("#3f5427")),
            (0.75, rgb("#56662f")),
            (1.0, rgb("#6e6f39")),
        ],
    )
    seca = m.faixa(m.ruido(p, 4.0, 4), 0.6, 0.72, 0.0, 0.6)
    m.cor(m.misturar(seca, c, rgb("#7a6a3e")))
    m.relevo(m.voronoi(p, 28.0), 0.5, 0.004)
    return m.m


def mat_punji(nome):
    """Bambu rachado das estacas, com a ponta tostada no fogo (TC 5-31: endurecida em brasa)."""
    m = Mat(nome, rug=0.6)
    p = m.coord("objeto")
    _, _, z = m.separar(p)
    est = m.ruido(m.mapear(p, (40, 40, 1.5)), 2.0, 5)
    cor = m.rampa(est, [(0.3, rgb("#8a7b4c")), (0.7, rgb("#b4a46d"))])
    tosta = m.faixa(z, 0.18, 0.34)
    cor = m.misturar(tosta, cor, rgb("#2a1f15"))
    terra = m.faixa(z, 0.06, 0.0)
    m.cor(m.misturar(terra, cor, rgb("#4a3a28")))
    m.relevo(est, 0.2, 0.0006)
    return m.m


def amarra(r, p, raio, mat, grupo, eixo="Z", voltas=3):
    """Amarração de cipó/corda em volta de um pau (algumas voltas de toro)."""
    for k in range(voltas):
        t = M.toro("amarra", raio + 0.006, 0.0045, 16, 5)
        rot = {
            "Z": Matrix.Identity(4),
            "X": Matrix.Rotation(math.pi / 2, 4, "Y"),
            "Y": Matrix.Rotation(math.pi / 2, 4, "X"),
        }[eixo]
        d = {"Z": Vector((0, 0, 0.011)), "X": Vector((0.011, 0, 0)), "Y": Vector((0, 0.011, 0))}[
            eixo
        ]
        M.mover(
            t,
            Matrix.Translation(Vector(p) + d * (k - (voltas - 1) / 2))
            @ rot
            @ Matrix.Rotation(0.15 * (k - 1), 4, "X"),
        )
        r.add(M.material(t, mat), grupo)


# =============================================================== abrigos
def receita_vc_lean_to():
    """Abrigo de uma água (lean-to) de bambu e folha de palmeira: 4 x 2 m de planta (relatório da
    CIA: cabanas de ~4 x 2 x 1,5 m), alto na frente (2,1 m) e baixo atrás (0,6 m), inclinação de
    ~37° (FAO: folha de palmeira ≥ 1:1,5), jirau de dormir (sạp) de ripas de bambu e uma parede
    lateral de palha. Alturas, jirau e parede: PLACEHOLDER."""
    r = Receita()
    bam = N.mat_bambu("bambu_lt")
    sape = B.mat_sape("sape_lt")
    cip = N.mat_corda("cipo_lt", "#7d6a45")
    esteira = N.mat_juta("esteira", "#c4ad78", "#8f7a4e", "#6e5d40", trama_m=0.01, z_sujo=0.0)
    rng = np.random.default_rng(101)
    hf, hb = 2.5, 0.85  # frente de 2,5 m: vão ≥ 2,3 m para o soldado de 2,0 m
    tg = (hf - hb) / 2.0
    for i, x in enumerate((-1.9, 0.0, 1.9)):
        r.add(
            B.bambu(
                "poste_f",
                (x, -1.0, 0),
                (x + rng.uniform(-0.02, 0.02), -1.0, hf + 0.06),
                0.045,
                mat=bam,
                sem=i,
            ),
            "Abrigo",
        )
        r.add(
            B.bambu("poste_t", (x, 1.0, 0), (x, 1.0, hb + 0.05), 0.04, mat=bam, sem=10 + i),
            "Abrigo",
        )
        r.caixa(f"PosteF{i}", (x, -1.0, hf / 2), (0.1, 0.1, hf), "passa", "Bamboo")
        r.caixa(f"PosteT{i}", (x, 1.0, hb / 2), (0.1, 0.1, hb), "passa", "Bamboo")
        amarra(r, (x, -1.0, hf - 0.02), 0.045, cip, "Abrigo")
    r.add(B.bambu("viga_f", (-2.15, -1.0, hf), (2.15, -1.0, hf), 0.04, mat=bam, sem=21), "Abrigo")
    r.add(B.bambu("viga_t", (-2.15, 1.0, hb), (2.15, 1.0, hb), 0.04, mat=bam, sem=22), "Abrigo")

    def z_caibro(y):
        return hb + 0.08 + (1.0 - y) * tg

    for k, x in enumerate(np.linspace(-2.05, 2.05, 8)):
        x = float(x)
        r.add(
            B.bambu(
                "caibro",
                (x, 1.3, z_caibro(1.3)),
                (x, -1.38, z_caibro(-1.38)),
                0.028,
                mat=bam,
                sem=30 + k,
            ),
            "Abrigo",
        )
    esp = 0.12
    yb, yf = 1.32, -1.4
    z0 = z_caibro(yb) + 0.03 + esp
    v = Vector((0, yf - yb, (yb - yf) * tg))
    r.add(
        B.palha_placa(
            "telhado", (-2.3, yb, z0), (1, 0, 0), v, 4.6, v.length, esp=esp, sem=5, mat=sape
        ),
        "Abrigo",
    )
    zb0, zf0 = z_caibro(yb) + 0.03, z_caibro(yf) + 0.03
    r.prisma(
        "Telhado",
        [
            (-2.3, yb, zb0),
            (2.3, yb, zb0),
            (-2.3, yf, zf0),
            (2.3, yf, zf0),
            (-2.3, yb, zb0 + esp),
            (2.3, yb, zb0 + esp),
            (-2.3, yf, zf0 + esp),
            (2.3, yf, zf0 + esp),
        ],
        "passa",
        "Thatch",
    )
    # parede lateral de palha (lado -X)
    lado = B.palha_placa(
        "parede",
        (-2.0, 1.05, 0.02),
        (0, -1, 0),
        (0, 0, 1),
        2.1,
        hf,
        esp=0.08,
        sem=6,
        curso=0.25,
        mat=sape,
    )
    B.apagar_faces(lado, lambda c: c.z > z_caibro(c.y) - 0.02)
    r.add(lado, "Abrigo")
    r.caixa_lim("Parede", (-2.1, -1.05, 0), (-1.95, 1.05, hf), "passa", "Thatch")
    # jirau (sạp) de ripas de bambu a 0,42 m
    for x in (-1.7, 1.7):
        for y in (-0.1, 0.85):
            r.add(
                B.bambu("pe_sap", (x, y, 0), (x, y, 0.42), 0.035, mat=bam, sem=int(40 + x + y * 3)),
                "Abrigo",
            )
    for y in (-0.1, 0.85):
        r.add(
            B.bambu(
                "trave_sap", (-1.85, y, 0.40), (1.85, y, 0.40), 0.03, mat=bam, sem=int(50 + y * 4)
            ),
            "Abrigo",
        )
    for k in range(15):
        y = -0.12 + k * 0.069
        rip = vara("ripa", (-1.8, y, 0.445), (1.8, y, 0.445), 0.027, mat=bam, segs=6)
        M.mover(
            rip,
            Matrix.Translation((0, y, 0.445))
            @ Matrix.Diagonal((1, 1, 0.35, 1))
            @ Matrix.Translation((0, -y, -0.445)),
        )
        r.add(rip, "Abrigo")
    r.caixa("Jirau", (0, 0.37, 0.23), (3.6, 1.05, 0.46), "passa", "Bamboo")
    # esteira enrolada (chiếu)
    rolo = vara("chieu", (-1.4, 0.7, 0.53), (-0.3, 0.7, 0.53), 0.065, mat=esteira, segs=14)
    r.add(rolo, "Abrigo")
    return r


def receita_vc_hoang_cam_kitchen():
    """Cozinha com fogão Hoàng Cầm (bếp Hoàng Cầm; inventado por Hoàng Cầm, cozinheiro da Divisão
    308, na campanha de Hòa Bình, 1951-52): fornalha de barro com 2 panelas de ferro sob um
    abrigo de palha de duas águas; atrás, o duto de fumaça enterrado (2,5 m até a câmara 1, de
    0,8 m; 3 m até a câmara 2; 3 ramais de 4 m: vi.wikipedia, Bếp Hoàng Cầm) aparece como montes
    baixos cobertos de folhas. Abrigo e fornalha: PLACEHOLDER."""
    r = Receita()
    bam = N.mat_bambu("bambu_coz")
    sape = B.mat_sape("sape_coz")
    cip = N.mat_corda("cipo_coz", "#7d6a45")
    barro = N.mat_barro("barro_coz", "#7a5a40", "#4e3a2a", z_molhado=0.04, z_rim=0.3)
    ferro = B.mat_ferro_fundido("panela")
    folhas = B.mat_folhas_chao("folhas_duto")
    lenha = N.mat_madeira("lenha", "#7a6448", "#4f3e2b", "#6f6658", eixo="Z")
    # abrigo de duas águas, cumeeira em Y (frente aberta)
    hr = 2.9  # passagem de 1,5 m com 2,3 m livres na frente aberta
    run = 1.5
    he = hr - run * math.tan(INCLINACAO)
    for y in (-1.3, 1.3):
        r.add(
            B.bambu("poste_cum", (0, y, 0), (0, y, hr + 0.05), 0.05, mat=bam, sem=int(60 + y)),
            "Cozinha",
        )
        r.caixa(
            f"PosteCum{'F' if y < 0 else 'T'}", (0, y, hr / 2), (0.12, 0.12, hr), "passa", "Bamboo"
        )
        amarra(r, (0, y, hr - 0.03), 0.05, cip, "Cozinha")
    for sx in (-1, 1):
        for y in (-1.3, 0.0, 1.3):
            r.add(
                B.bambu(
                    "poste_beiral",
                    (sx * 1.4, y, 0),
                    (sx * 1.4, y, he + 0.04),
                    0.04,
                    mat=bam,
                    sem=int(70 + sx * 3 + y),
                ),
                "Cozinha",
            )
            r.caixa(
                f"PosteBeiral{sx}{int(y * 10)}",
                (sx * 1.4, y, he / 2),
                (0.1, 0.1, he),
                "passa",
                "Bamboo",
            )
        r.add(
            B.bambu(
                "viga_beiral",
                (sx * 1.4, -1.6, he),
                (sx * 1.4, 1.6, he),
                0.035,
                mat=bam,
                sem=80 + sx,
            ),
            "Cozinha",
        )
    r.add(B.bambu("cumeeira", (0, -1.7, hr), (0, 1.7, hr), 0.04, mat=bam, sem=83), "Cozinha")
    for k, y in enumerate(np.linspace(-1.55, 1.55, 6)):
        for sx in (-1, 1):
            r.add(
                B.bambu(
                    "caibro",
                    (sx * 1.75, float(y), he - 0.35 * math.tan(INCLINACAO)),
                    (0, float(y), hr + 0.03),
                    0.026,
                    mat=bam,
                    sem=90 + k * 2 + sx,
                ),
                "Cozinha",
            )
    esp = 0.11
    for sx in (-1, 1):
        x_e = sx * 1.8
        z_e = he - 0.4 * math.tan(INCLINACAO) + 0.04 + esp
        u = Vector((0, sx, 0))
        v = Vector((-sx * math.cos(INCLINACAO), 0, math.sin(INCLINACAO)))
        o = Vector((x_e, -sx * 1.75, z_e))
        r.add(
            B.palha_placa(
                "telhado", o, u, v, 3.5, 1.8 / math.cos(INCLINACAO), esp=esp, sem=7 + sx, mat=sape
            ),
            "Cozinha",
        )
        pts = []
        for z_off in (0.0, esp):
            for y in (-1.75, 1.75):
                pts += [(x_e, y, z_e - esp + z_off), (0.0, y, hr + 0.04 + z_off)]
        r.prisma(f"Telhado{'Dir' if sx > 0 else 'Esq'}", pts, "passa", "Thatch")
    # fornalha de barro com 2 bocas e panelas de ferro
    forn = M.caixa("fornalha", (1.25, 0.75, 0.34), (0, 0, 0.17), cortes=4)
    M.chanfrar(forn, 0.08, 3)
    M.deslocar(forn, lambda co, n: 0.012 * M.fbm(co * 6, 3, 5))
    M.mover(forn, Matrix.Translation((0, 0.35, 0)))
    r.add(M.material(M.suave(forn, 60), barro), "Cozinha")
    r.caixa("Fornalha", (0, 0.35, 0.18), (1.25, 0.75, 0.36), "para", "Earth")
    for k, x in enumerate((-0.32, 0.32)):
        perfil = [
            (0.0, 0.0),
            (0.1, 0.005),
            (0.17, 0.04),
            (0.2, 0.1),
            (0.205, 0.17),
            (0.215, 0.18),
            (0.215, 0.19),
            (0.19, 0.19),
            (0.185, 0.12),
            (0.0, 0.11),
        ]
        pan = M.torno("panela", perfil, segs=32, fatiar=0.03)
        M.mover(pan, Matrix.Translation((x, 0.35, 0.22)))
        r.add(M.material(M.suave(pan, 60), ferro), "Cozinha")
        if k == 0:
            tampa = M.torno(
                "tampa",
                [(0.0, 0.03), (0.12, 0.02), (0.2, 0.0), (0.21, 0.0), (0.21, 0.01), (0.0, 0.045)],
                segs=32,
            )
            M.mover(tampa, Matrix.Translation((x, 0.35, 0.41)))
            r.add(M.material(M.suave(tampa, 60), ferro), "Cozinha")
    boca = B.mat_tinta_lisa("boca_fornalha", "#120d0a", 0.95, 0.2)
    for x in (-0.32, 0.32):
        b_ = M.superelipsoide("boca", 0.12, 0.01, 0.08, 0.5, 0.5, 16, 8)
        M.mover(b_, Matrix.Translation((x, -0.03, 0.12)))
        r.add(N.so_bake(M.material(b_, boca)), "Cozinha")
        for k in range(2):
            t = vara(
                "tico",
                (x - 0.05 + 0.1 * k, -0.05, 0.1),
                (x - 0.12 + 0.24 * k, -0.6, 0.03),
                0.025,
                0.02,
                lenha,
                8,
            )
            r.add(t, "Cozinha")
    # lenha empilhada e jirau de bambu com cuias
    for k in range(7):
        y = -0.45 + (k % 4) * 0.09
        z = 0.04 + (k // 4) * 0.075
        r.add(vara("lenha", (-1.25, y, z), (-0.55, y + 0.03, z), 0.038, 0.034, lenha, 8), "Cozinha")
    r.caixa("Lenha", (-0.9, -0.3, 0.1), (0.75, 0.45, 0.2), "passa", "Wood")
    for x in (0.75, 1.25):
        for y in (0.75, 1.1):
            r.add(
                B.bambu(
                    "pe_jirau",
                    (x, y, 0),
                    (x, y, 0.85),
                    0.025,
                    mat=bam,
                    sem=int(110 + x * 4 + y * 7),
                ),
                "Cozinha",
            )
    for z in (0.45, 0.85):
        for k in range(6):
            y = 0.72 + k * 0.08
            r.add(vara("ripa_j", (0.7, y, z), (1.3, y, z), 0.016, mat=bam, segs=6), "Cozinha")
    cuia = N.mat_coco("cuia_coz")
    for x in (0.85, 1.15):
        c = M.torno(
            "cuia",
            [
                (0.0, 0.0),
                (0.05, 0.005),
                (0.075, 0.035),
                (0.08, 0.06),
                (0.072, 0.06),
                (0.068, 0.04),
                (0.0, 0.01),
            ],
            segs=20,
        )
        M.mover(c, Matrix.Translation((x, 0.9, 0.87)))
        r.add(M.material(M.suave(c, 60), cuia), "Cozinha")
    r.caixa("Jirau", (1.0, 0.92, 0.43), (0.6, 0.45, 0.86), "passa", "Bamboo")
    # duto enterrado: montes de terra com folhas (câmaras de 0,8 m; dutos de 0,25-0,30 m)
    segs = [((0.0, 0.72), (0.0, 3.0), 0.42, 0.07)]
    camaras = [((0.0, 3.6), 0.9, 0.14), ((0.0, 7.0), 0.9, 0.14)]
    segs.append(((0.0, 4.2), (0.0, 6.4), 0.42, 0.07))
    saidas = []
    for ang in (-32.0, 0.0, 32.0):
        a = math.radians(ang)
        p1 = (4.0 * math.sin(a), 7.4 + 4.0 * math.cos(a))
        segs.append(((0.0, 7.6), p1, 0.32, 0.05))
        saidas.append([p1[0], p1[1], 0.05])

    def altura(x, y):
        h = 0.0
        for (ax, ay), (bx, by), w, hh in segs:
            dx, dy = bx - ax, by - ay
            t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
            d = math.hypot(x - ax - t * dx, y - ay - t * dy)
            h = max(h, hh * max(0.0, 1 - (d / w) ** 2))
        for (cx, cy), w, hh in camaras:
            d = math.hypot(x - cx, y - cy)
            h = max(h, hh * max(0.0, 1 - (d / w) ** 2))
        return h

    X0, X1, Y0, Y1 = -2.6, 2.6, 0.55, 11.55

    def f(a, b):
        x = X0 + a * (X1 - X0)
        y = Y0 + b * (Y1 - Y0)
        h = altura(x, y)
        if h > 0.003:
            h += 0.015 * M.fbm(Vector((x * 3, y * 3, 0.5)), 3, 9)
        return (x, y, max(0.0, h))

    duto = grade("duto", f, round((X1 - X0) / 0.08), round((Y1 - Y0) / 0.1), fora=(0, 0, 1))
    B.apagar_faces(duto, lambda c: c.z < 0.006)
    r.add(M.material(M.suave(duto, 70), folhas), "Duto")
    galho = N.mat_madeira("galho", "#5f4c37", "#3e3125", "#5a5248", eixo="Z")
    for (cx, cy), _, _ in camaras:
        for k in range(5):
            a = k * 0.7 + 0.3
            p0 = (cx + 0.5 * math.cos(a), cy + 0.5 * math.sin(a), 0.03)
            p1 = (cx - 0.5 * math.cos(a + 0.3), cy - 0.5 * math.sin(a + 0.3), 0.13)
            r.add(vara("galho", p0, p1, 0.015, 0.008, galho, 6), "Duto")
    r.extras["fumaca_saidas_m"] = saidas
    return r


def receita_vc_hammock():
    """Rede de náilon (tecido de paraquedas, verde; AWM REL43477, c. 1965) entre dois paus de
    bambu, com o pano (tăng) de náilon esticado numa corda por cima. Comprimentos: PLACEHOLDER."""
    r = Receita()
    bam = N.mat_bambu("bambu_rede")
    nylon = B.mat_nylon("nylon_rede", "#55613e", "#3a432b")
    lona = B.mat_nylon("tang", "#4a5737", "#323b26")
    cor_ = N.mat_corda("corda_rede", "#8f8466")
    for i, x in enumerate((-1.6, 1.6)):
        r.add(B.bambu("pau", (x, 0, 0), (x, 0, 1.95), 0.05, mat=bam, sem=120 + i), "Rede")
        r.caixa(f"Pau{i}", (x, 0, 0.975), (0.12, 0.12, 1.95), "passa", "Bamboo")

    def pano(a, b):
        q = -1 + 2 * a
        v = -1 + 2 * b
        w = 0.34 * max(0.0, 1 - q * q) ** 0.6 + 0.02
        zc = 1.18 - 0.48 * (1 - q * q)
        z = zc + 0.2 * v * v * max(0.0, 1 - q * q) ** 0.8
        return (1.1 * q, v * w, z)

    rede = grade("rede", pano, 30, 10, fora=(0, 0, -1))
    M.deslocar(rede, lambda co, n: 0.008 * M.fbm(co * 6, 3, 3))
    M.solidificar(rede, 0.003, 0.0)
    r.fixo(M.material(M.suave(rede, 60), nylon), "Rede")  # pano fino: sem redução
    for s in (-1, 1):
        r.add(corda("corda", (s * 1.1, 0, 1.18), (s * 1.6, 0, 1.55), 0.02, 0.008, cor_, 6), "Rede")
        r.add(corda("cumeeira", (s * 1.6, 0, 1.88), (0, 0, 1.86), 0.0, 0.005, cor_, 3), "Rede")
        for k in range(3):
            t = M.toro("volta", 0.055, 0.006, 16, 5)
            M.mover(t, Matrix.Translation((s * 1.6, 0, 1.53 + k * 0.012)))
            r.add(M.material(t, cor_), "Rede")
    # pano (tăng): duas abas a 40° a partir da corda, cantos amarrados em estacas
    for sy in (-1, 1):

        def aba(a, b, sy=sy):
            x = -1.45 + a * 2.9
            d = b * 1.05
            sag = 0.04 * math.sin(math.pi * a) * math.sin(math.pi * b)
            return (
                x,
                sy * d * math.cos(math.radians(40)),
                1.87 - d * math.sin(math.radians(40)) - sag,
            )

        o = grade("tang", aba, 16, 6, fora=(0, sy, 1))
        M.solidificar(o, 0.002, 0.0)
        r.fixo(M.material(M.suave(o, 55), lona), "Rede")
        for x in (-1.45, 1.45):
            p0 = (
                x,
                sy * 1.05 * math.cos(math.radians(40)),
                1.87 - 1.05 * math.sin(math.radians(40)),
            )
            p1 = (x * 1.15, sy * 1.6, 0.05)
            r.add(corda("espia", p0, p1, 0.01, 0.003, cor_, 5, 4), "Rede")
            r.add(
                B.bambu(
                    "estaca",
                    (p1[0], p1[1], 0.0),
                    (p1[0], p1[1], 0.22),
                    0.012,
                    mat=bam,
                    sem=int(130 + x + sy),
                ),
                "Rede",
            )
    r.caixa("Rede", (0, 0, 0.95), (2.2, 0.6, 0.55), "passa", "Canvas")
    return r


def receita_vc_weapon_rack():
    """Armeiro de bambu em cavalete (pernas em X amarradas, travessa de cima para encostar as
    armas e travessa de baixo com cravelhas para as coronhas). Sem fonte: PLACEHOLDER."""
    r = Receita()
    bam = N.mat_bambu("bambu_arm")
    cip = N.mat_corda("cipo_arm", "#7d6a45")
    for i, x in enumerate((-0.95, 0.95)):
        r.add(
            B.bambu("perna", (x, -0.38, 0), (x, 0.18, 1.22), 0.03, mat=bam, sem=140 + i), "Armeiro"
        )
        r.add(
            B.bambu(
                "perna", (x + 0.03, 0.38, 0), (x + 0.03, -0.18, 1.22), 0.03, mat=bam, sem=142 + i
            ),
            "Armeiro",
        )
        amarra(r, (x + 0.015, 0.0, 0.83), 0.035, cip, "Armeiro", "X")
    r.add(
        B.bambu("travessa_alta", (-1.15, 0.0, 1.06), (1.15, 0.0, 1.06), 0.03, mat=bam, sem=145),
        "Armeiro",
    )
    r.add(
        B.bambu("travessa_baixa", (-1.1, -0.3, 0.2), (1.1, -0.3, 0.2), 0.028, mat=bam, sem=146),
        "Armeiro",
    )
    for k in range(9):
        x = -0.88 + k * 0.22
        r.add(vara("cravelha", (x, -0.3, 0.12), (x, -0.3, 0.32), 0.012, mat=bam, segs=6), "Armeiro")
        r.add(
            vara("cravelha_a", (x, -0.03, 1.06), (x, -0.12, 1.2), 0.01, mat=bam, segs=6), "Armeiro"
        )
    r.caixa("Armeiro", (0, 0, 0.62), (2.3, 0.8, 1.24), "passa", "Bamboo")
    return r


def receita_vc_range_target():
    """Alvo de treino de palha amarrada num pau de bambu, com braço de travessa: tronco e cabeça de
    palha (nó `Silhueta`, centro a ~1,2 m como o TrainingService). Sem fonte: PLACEHOLDER."""
    r = Receita()
    bam = N.mat_bambu("bambu_alvo")
    palha = N.mat_palha("palha_alvo")
    cor_ = N.mat_corda("amarra_alvo", "#8a7a52")
    r.add(B.bambu("pau", (0, 0.06, 0), (0, 0.06, 1.78), 0.025, mat=bam, sem=150), "Alvo", "Suporte")
    r.add(
        B.bambu("braco", (-0.34, 0.08, 1.42), (0.34, 0.08, 1.42), 0.018, mat=bam, sem=151),
        "Alvo",
        "Suporte",
    )
    perfil = [
        (0.0, 0.0),
        (0.12, 0.0),
        (0.17, 0.05),
        (0.19, 0.15),
        (0.2, 0.32),
        (0.19, 0.5),
        (0.2, 0.6),
        (0.17, 0.68),
        (0.06, 0.74),
        (0.0, 0.74),
    ]
    tronco = M.torno("tronco", perfil, segs=32, fatiar=0.03)
    M.mover(tronco, Matrix.Diagonal((1.0, 0.62, 1.0, 1.0)))
    M.deslocar(
        tronco,
        lambda co, n: (
            0.012 * M.ruido(Vector((co.x * 40, co.y * 40, co.z * 3)), 3)
            + 0.01 * M.fbm(co * 8, 2, 4)
        ),
    )
    M.mover(tronco, Matrix.Translation((0, 0.0, 0.76)))
    r.add(M.material(M.suave(tronco, 70), palha), "Alvo", "Silhueta")
    cab = M.superelipsoide("cabeca", 0.1, 0.085, 0.115, 0.9, 0.9, 24, 12)
    M.deslocar(cab, lambda co, n: 0.008 * M.ruido(Vector((co.x * 50, co.y * 50, co.z * 5)), 5))
    M.mover(cab, Matrix.Translation((0, 0.0, 1.6)))
    r.add(M.material(M.suave(cab, 70), palha), "Alvo", "Silhueta")
    for z, rr in ((0.86, 0.16), (1.32, 0.18), (1.5, 0.07)):
        t = M.toro("amarra", rr, 0.008, 24, 5)
        M.mover(t, Matrix.Translation((0, 0, z)) @ Matrix.Diagonal((1.0, 0.65, 1.0, 1.0)))
        r.add(M.material(t, cor_), "Alvo", "Suporte")
    r.caixa("Pau", (0, 0.06, 0.89), (0.06, 0.06, 1.78), "passa", "Bamboo")
    return r


def receita_vc_range_rest():
    """Apoio de tiro de bambu (vara deitada em dois cavaletes em X, a 0,6 m) para atirar de joelho.
    Sem fonte: PLACEHOLDER."""
    r = Receita()
    bam = N.mat_bambu("bambu_apoio")
    cip = N.mat_corda("cipo_apoio", "#7d6a45")
    for i, x in enumerate((-1.4, 1.4)):
        r.add(
            B.bambu("perna", (x - 0.22, 0.0, 0), (x + 0.12, 0.0, 0.78), 0.03, mat=bam, sem=160 + i),
            "Apoio",
        )
        r.add(
            B.bambu(
                "perna", (x + 0.22, 0.03, 0), (x - 0.12, 0.03, 0.78), 0.03, mat=bam, sem=162 + i
            ),
            "Apoio",
        )
        amarra(r, (x, 0.015, 0.52), 0.035, cip, "Apoio", "Y")
    r.add(B.bambu("vara", (-1.7, 0.015, 0.6), (1.7, 0.015, 0.6), 0.032, mat=bam, sem=165), "Apoio")
    r.caixa("Apoio", (0, 0.015, 0.33), (3.4, 0.12, 0.66), "passa", "Bamboo")
    return r


def receita_vc_car_shelter():
    """Abrigo de palha para carro: duas águas sobre postes de bambu, fundo fechado de palha, frente
    aberta e galhos de camuflagem no telhado. Vão livre de 5,6 x 3,2 m e 2,3 m no beiral: cabem o
    GAZ-69 (3,85 x 1,75 x 1,95 m), o Citroën Traction Avant (4,65 x 1,79 x 1,54 m) e o Willys M38
    (3,38 x 1,57 x 1,88 m com capota) (Wikipedia). O VC de Quảng Ngãi com carro em 1965: sem fonte
    (pedido do dono). Medidas do abrigo: PLACEHOLDER."""
    r = Receita()
    bam = N.mat_bambu("bambu_carro")
    sape = B.mat_sape("sape_carro")
    cip = N.mat_corda("cipo_carro", "#7d6a45")
    folha = mat_folhagem("camuflagem")
    galho = N.mat_madeira("galho_c", "#5f4c37", "#3e3125", "#5a5248", eixo="Z")
    he = 2.55  # vão livre de 2,5 m sob o frechal
    run = 1.7 + 0.35
    hr = he + 1.7 * math.tan(INCLINACAO)
    for sx in (-1, 1):
        for y in (-2.8, 0.0, 2.8):
            r.add(
                B.bambu(
                    "poste",
                    (sx * 1.7, y, 0),
                    (sx * 1.7, y, he + 0.05),
                    0.06,
                    mat=bam,
                    sem=int(170 + sx * 4 + y),
                ),
                "Abrigo",
            )
            r.caixa(
                f"Poste{sx}{int(y * 10)}",
                (sx * 1.7, y, he / 2),
                (0.14, 0.14, he),
                "passa",
                "Bamboo",
            )
            amarra(r, (sx * 1.7, y, he - 0.03), 0.06, cip, "Abrigo")
        r.add(
            B.bambu(
                "frechal", (sx * 1.7, -3.1, he), (sx * 1.7, 3.1, he), 0.045, mat=bam, sem=180 + sx
            ),
            "Abrigo",
        )
    for y in (-2.8, 2.8):
        r.add(
            B.bambu("poste_cum", (0, y, 0), (0, y, hr + 0.05), 0.06, mat=bam, sem=int(185 + y)),
            "Abrigo",
        )
        r.caixa(
            f"PosteCum{'F' if y < 0 else 'T'}", (0, y, hr / 2), (0.14, 0.14, hr), "passa", "Bamboo"
        )
    r.add(B.bambu("cumeeira", (0, -3.2, hr), (0, 3.2, hr), 0.05, mat=bam, sem=188), "Abrigo")
    for k, y in enumerate(np.linspace(-3.0, 3.0, 9)):
        for sx in (-1, 1):
            r.add(
                B.bambu(
                    "caibro",
                    (sx * 2.05, float(y), he - 0.35 * math.tan(INCLINACAO)),
                    (0, float(y), hr + 0.04),
                    0.03,
                    mat=bam,
                    sem=190 + 2 * k + sx,
                ),
                "Abrigo",
            )
    esp = 0.12
    for sx in (-1, 1):
        x_e = sx * (run + 0.05)
        z_e = he - (run - 1.7 + 0.05) * math.tan(INCLINACAO) + 0.05 + esp
        u = Vector((0, sx, 0))
        v = Vector((-sx * math.cos(INCLINACAO), 0, math.sin(INCLINACAO)))
        o = Vector((x_e, -sx * 3.3, z_e))
        r.add(
            B.palha_placa(
                "telhado",
                o,
                u,
                v,
                6.6,
                (run + 0.05) / math.cos(INCLINACAO),
                esp=esp,
                sem=17 + sx,
                mat=sape,
            ),
            "Abrigo",
        )
        pts = []
        for z_off in (0.0, esp):
            for y in (-3.3, 3.3):
                pts += [(x_e, y, z_e - esp + z_off), (0.0, y, hr + 0.05 + z_off)]
        r.prisma(f"Telhado{'Dir' if sx > 0 else 'Esq'}", pts, "passa", "Thatch")
    # fundo de palha (+Y), com o oitão
    fundo = B.palha_placa(
        "fundo",
        (1.85, 2.95, 0.02),
        (-1, 0, 0),
        (0, 0, 1),
        3.7,
        hr,
        esp=0.08,
        sem=19,
        curso=0.25,
        mat=sape,
    )
    B.apagar_faces(fundo, lambda c: c.z > hr - abs(c.x) * math.tan(INCLINACAO) - 0.03)
    r.add(fundo, "Abrigo")
    r.caixa_lim("Fundo", (-1.85, 2.9, 0), (1.85, 3.05, he), "passa", "Thatch")
    # galhos de camuflagem no telhado
    rng = np.random.default_rng(17)
    for k in range(6):
        sx = 1 if k % 2 else -1
        y = -2.4 + k * 0.95 + rng.uniform(-0.2, 0.2)
        d = rng.uniform(0.6, 1.3)
        x = sx * (d * math.cos(INCLINACAO) * 0.9 + 0.2)
        z = hr - abs(x) * math.tan(INCLINACAO) + esp + 0.08
        moita = M.superelipsoide("moita", 0.55, 0.35, 0.12, 0.8, 0.9, 20, 10)
        M.deslocar(
            moita, lambda co, n, k=k: 0.06 * M.fbm(co * 5, 3, k) + 0.02 * M.ruido(co * 25, k)
        )
        M.mover(moita, M.matriz((x, y, z), (0, sx * INCLINACAO, rng.uniform(-0.6, 0.6))))
        r.add(M.material(M.suave(moita, 70), folha), "Abrigo")
        r.add(
            vara(
                "galho",
                (x - sx * 0.5, y + 0.2, z - 0.25),
                (x + sx * 0.3, y - 0.3, z + 0.1),
                0.02,
                0.01,
                galho,
                6,
            ),
            "Abrigo",
        )
    return r


def receita_vc_punji():
    """Canteiro de estacas punji (2 x 1 m): bambu rachado com ponta afiada e tostada no fogo,
    cravado no chão e coberto de folhas (TC 5-31, 1967; MACV P-3300/5: estacas no chão cobertas
    de capim). Comprimento e espaçamento das estacas: PLACEHOLDER (0,25-0,45 m). A cova (0,46 x
    0,46 x 0,30 m no TC 5-31) pede escavar o terreno no código."""
    r = Receita()
    folhas = B.mat_folhas_chao("folhas_punji")
    est = mat_punji("punji")
    rng = np.random.default_rng(190)

    def chao(a, b):
        x = -1.05 + a * 2.1
        y = -0.55 + b * 1.1
        borda = max(abs(x) / 1.05, abs(y) / 0.55)
        z = 0.025 * (1 - borda**4) + 0.008 * M.fbm(Vector((x * 6, y * 6, 1.0)), 3, 2)
        return (x, y, max(0.0, z))

    tapete = grade("folhas", chao, 42, 22, fora=(0, 0, 1))
    B.apagar_faces(tapete, lambda c: (abs(c.x) / 1.05) ** 2 + (abs(c.y) / 0.55) ** 2 > 1.0)
    r.add(M.material(M.suave(tapete, 60), folhas), "Punji")
    for i in range(9):
        for j in range(5):
            x = -0.88 + i * 0.22 + rng.uniform(-0.05, 0.05)
            y = -0.4 + j * 0.2 + rng.uniform(-0.05, 0.05)
            if (x / 1.0) ** 2 + (y / 0.5) ** 2 > 1.0:
                continue
            h = rng.uniform(0.25, 0.45)
            inc = math.radians(rng.uniform(12, 35))
            az = math.radians(rng.uniform(-25, 25))
            topo = Vector(
                (
                    math.sin(az) * math.sin(inc) * h,
                    -math.cos(az) * math.sin(inc) * h,
                    math.cos(inc) * h,
                )
            )
            p0 = Vector((x, y, 0.004))
            o = M.tubo(
                "estaca", [p0, p0 + topo * 0.6, p0 + topo], [0.013, 0.011, 0.0006], 4, achatar=0.35
            )
            r.add(M.material(M.suave(o, 40), est), "Punji")
    r.zona(
        "Punji",
        (-1.0, -0.5, 0.0),
        (1.0, 0.5, 0.45),
        obs="sem colisão; toque = estaca (dano no código)",
    )
    return r
