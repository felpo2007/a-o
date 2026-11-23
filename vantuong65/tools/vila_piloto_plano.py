"""Setor piloto da Vila (D-255): cerca de 88 x 88 m em volta do Objetivo C, com densidade final.

A planta completa de 51 construções fica em `vila_plano.py`, para a expansão depois da aprovação.
Aqui cada rua tem frente de loja, cada casa tem quintal, e a cena e as plantas saem de regras
conferidas contra construções, ruas, vielas e a lagoa. Grava `Shared/VilaPovoado.luau`.

    uv run --group arte python tools/vila_piloto_plano.py            # confere e desenha
    uv run --group arte python tools/vila_piloto_plano.py --gravar   # e grava o módulo do jogo
"""

# ruff: noqa: E501
from __future__ import annotations

import math
import random
import sys

from PIL import Image, ImageDraw, ImageFont
from vila_plano import PLANTA, POSTO, RUAS, SAIDA, batem, cantos, dist_via, pegada

MEIO = 46.0  # metade do lado do setor
LAGOA = {"x": -27.0, "z": 40.0, "a": 10.5, "b": 5.6, "giro": 45.0}
VIELAS = (
    ((-3, -13), (3, -27), (2, -33), (-5, -35), (-20, -33), (-30, -29), (-38, -32)),
    ((2, -33), (15, -35), (20, -44)),
    ((-30, -29), (-40, -12), (-44, 4)),
    ((27, -12), (35, -15), (43, -14)),
    ((12, 3), (8, 7), (5, 16)),
    ((33, 4), (43, 18), (42, 30)),
    ((5, 30), (6, 44)),
    ((-13, 12), (-17, 25), (-15, 31), (-17, 44)),
    ((-34, 13), (-42, 12), (-44, 30)),
)


def rua(s, t):
    """Ponto na rua nordeste: s ao longo dela a partir de (17, -13), t para o noroeste."""
    return round(17 + 0.7071 * s - 0.7071 * t, 2), round(-13 - 0.7071 * s - 0.7071 * t, 2)


def bancas() -> list[tuple]:
    cx, cz = -32.8, -3.2
    d, n = (-0.7071, 0.7071), (0.7071, 0.7071)
    tipos = (
        "ret_merc_banca_a",
        "ret_pov_banca_d",
        "ret_merc_banca_b",
        "ret_pov_banca_f",
        "ret_merc_banca_c",
        "ret_pov_banca_g",
        "ret_pov_banca_e",
        "ret_pov_banca_d",
    )
    out, k = [], 0
    for dist, giro in ((9.3, -135), (14.9, 45)):
        for s in (-8.55, -2.85, 2.85, 8.55):
            x = round(cx + n[0] * dist + d[0] * s, 2)
            z = round(cz + n[1] * dist + d[1] * s, 2)
            out.append((f"Banca {k + 1}", tipos[k], x, z, giro, "centro", "banca", ""))
            k += 1
    return out


# nome, modelo, x, z, giro, setor, classe, quintal ("" sem cerca, "bambu" ou "muro")
CONSTRUCOES: list[tuple] = [
    ("Casa comunitária", "ret_vila_dinh", -19, -19, -135, "centro", "marco", ""),
    ("Pagode", "ret_pov_chua", 25, 25.5, 45, "centro", "marco", ""),
    ("Mercado central", "ret_pov_mercado", -32.8, -3.2, -135, "centro", "marco", ""),
    *bancas(),
    ("Poço comunitário", "ret_pov_poco", -5.5, -13.5, -135, "centro", "casa", ""),
    ("Santuário de antepassados", "ret_pov_santuario", 5, -24, -135, "centro", "casa", ""),
    ("Barbearia", "ret_pov_barbearia", *rua(-1.6, 7.1), -135, "centro", "casa", ""),
    ("Alfaiataria", "ret_pov_alfaiate", *rua(6.4, 7.35), -135, "centro", "casa", "bambu"),
    ("Mercearia", "ret_pov_mercearia", *rua(16.0, 7.45), -135, "centro", "casa", "bambu"),
    ("Casa de chá", "ret_pov_cha", *rua(26.2, 8.0), -135, "centro", "casa", "bambu"),
    ("Restaurante de phở", "ret_pov_pho", 29.5, -7.4, 180, "centro", "casa", ""),
    ("Oficina de bicicletas", "ret_merc_oficina", 40, -7.5, 180, "centro", "casa", ""),
    ("Ferraria", "ret_pov_ferraria", *rua(27.8, -7.2), 45, "centro", "casa", "bambu"),
    ("Torre de vigia", "ret_vila_torre", 31.6, -18.4, 135, "centro", "casa", ""),
    ("Casa sobre esteios", "ret_vila_palafita_b", 41.5, 11, 0, "bairro", "casa", "bambu"),
    ("Casa de taipa", "ret_vila_terra", 14, 41, 135, "bairro", "casa", "bambu"),
    ("Posto de atendimento", "ret_pov_medico", -9.7, 25.4, -90, "bairro", "casa", "bambu"),
    ("Casa laterítica", "ret_pov_laterita", -10.8, 37.6, -90, "bairro", "casa", ""),
    ("Casa sobre esteios grande", "ret_vila_palafita_a", -43, 23, -135, "bairro", "casa", "bambu"),
    ("Casa do chefe da aldeia", "vila_casa_03", -41, -24, -120, "bairro", "casa", "muro"),
    ("Casa com pátio interno", "ret_pov_patio", -12, -43, 170, "bairro", "casa", ""),
    ("Casa laterítica antiga", "ret_pov_laterita", 8, -40, -150, "bairro", "casa", ""),
    ("Casa de taipa do norte", "ret_vila_terra", -30, -38, 160, "bairro", "casa", "bambu"),
    ("Casa destruída", "ret_pov_destruida", 21.5, -47, -140, "guerra", "casa", ""),
    ("Oficina de cestos", "ret_pov_cestos", 45.5, -17.5, 75, "bairro", "casa", ""),
]
PASSARELAS = (
    ("ret_vila_passarela", -29.4, 42.4, 45),
    ("ret_vila_passarela", -25.2, 38.2, 45),
)
CENA = (
    ("ret_pov_d_cestos", 1.0),
    ("ret_pov_d_potes", 1.1),
    ("ret_pov_d_lenha", 1.7),
    ("ret_pov_d_feno", 1.25),
    ("ret_pov_d_varal", 2.3),
    ("ret_pov_d_cestos", 1.0),
    ("ret_pov_d_horta", 2.4),
    ("ret_pov_d_potes", 1.1),
    ("ret_pov_d_esteira", 2.4),
    ("ret_pov_d_lenha", 1.7),
)


# o que fica livre na frente dos marcos (largura, profundidade em metros): a fachada precisa
# ser vista da rua, sem moita nem coqueiro na frente
ADROS = {"Pagode": (12.0, 13.0), "Casa comunitária": (9.0, 6.0)}


CAMERAS = ((-1.5, 66), (-3, 30), (13, -27), (36, -2.5), (-27, 27), (8.5, 9.5))


def na_lagoa(x, z, folga=0.0) -> bool:
    a = math.radians(LAGOA["giro"])
    dx, dz = x - LAGOA["x"], z - LAGOA["z"]
    u = dx * math.cos(a) - dz * math.sin(a)
    v = dx * math.sin(a) + dz * math.cos(a)
    return (u / (LAGOA["a"] + folga)) ** 2 + (v / (LAGOA["b"] + folga)) ** 2 < 1


def dentro_ret(x, z, q, folga) -> bool:
    a = math.radians(q["giro"])
    dx, dz = x - q["x"], z - q["z"]
    u = dx * math.cos(a) - dz * math.sin(a)
    v = dx * math.sin(a) + dz * math.cos(a)
    return abs(u) < q["lx"] / 2 + folga and abs(v) < q["lz"] / 2 + folga


class Setor:
    def __init__(self) -> None:
        self.ret = []
        for nome, key, x, z, giro, setor, classe, quintal in CONSTRUCOES:
            lx, lz = pegada(key)
            self.ret.append(
                {
                    "nome": nome,
                    "key": key,
                    "x": x,
                    "z": z,
                    "giro": giro,
                    "setor": setor,
                    "classe": classe,
                    "quintal": quintal,
                    "lx": lx,
                    "lz": lz,
                }
            )
        self.cena, self.plantas, self.cercas = [], [], []
        self.pontos_cerca: list[tuple] = []
        self.fixos = [
            {"x": POSTO[1], "z": POSTO[2], "giro": POSTO[3], "lx": POSTO[4], "lz": POSTO[5]}
        ]

    def no_adro(self, x, z, folga=0.0) -> bool:
        for q in self.ret:
            if q["nome"] not in ADROS:
                continue
            larg, prof = ADROS[q["nome"]]
            a = math.radians(q["giro"])
            dx, dz = x - q["x"], z - q["z"]
            u = dx * math.cos(a) - dz * math.sin(a)
            v = dx * math.sin(a) + dz * math.cos(a)
            borda = q["lz"] / 2
            if abs(u) < larg / 2 + folga and -borda - prof - folga < v < -borda + folga:
                return True
        return False

    def livre(self, x, z, r, rua_min=3.7, viela_min=1.5) -> bool:
        if max(abs(x), abs(z)) > MEIO or math.hypot(x, z) < 9.5 + r:
            return False
        if self.no_adro(x, z, r):
            return False
        if dist_via(x, z, RUAS) < rua_min + r or dist_via(x, z, VIELAS) < viela_min + r:
            return False
        if na_lagoa(x, z, r + 0.6):
            return False
        if any(dentro_ret(x, z, q, r + 0.25) for q in (*self.ret, *self.fixos)):
            return False
        if any(math.hypot(x - a, z - b) < r + 0.3 for a, b in self.pontos_cerca):
            return False
        return not any(math.hypot(x - c["x"], z - c["z"]) < r + c["r"] for c in self.cena)

    def livre_cerca(self, x, z) -> bool:
        if max(abs(x), abs(z)) > MEIO + 1 or dist_via(x, z, RUAS) < 3.5:
            return False
        if self.no_adro(x, z, 0.2):
            return False
        if dist_via(x, z, VIELAS) < 1.25 or na_lagoa(x, z, 0.4):
            return False
        return not any(dentro_ret(x, z, q, 0.12) for q in (*self.ret, *self.fixos))

    def por_cena(self) -> None:
        rr = random.Random(1965)
        k = 0
        for q in self.ret:
            if q["classe"] != "casa":
                continue
            a = math.radians(q["giro"])
            ca, sa = math.cos(a), math.sin(a)
            hx, hz = q["lx"] / 2, q["lz"] / 2
            pontos = [(-1, 0.45), (1, 0.45), (-0.5, 2), (0.5, 2), (-1, -0.6), (1, -0.6)]
            rr.shuffle(pontos)
            postas = 0
            for su, sv in pontos:
                if postas >= 3:
                    break
                key, r = CENA[k % len(CENA)]
                if key == "ret_pov_d_feno" and math.hypot(q["x"], q["z"]) < 32:
                    k += 1  # meda de palha é coisa da beira da vila
                    key, r = CENA[k % len(CENA)]
                if sv == 2:
                    u, v = su * hx, hz + r + 0.55
                else:
                    u, v = su * (hx + r + 0.55), sv * hz
                x = q["x"] + u * ca + v * sa
                z = q["z"] - u * sa + v * ca
                if self.livre(x, z, r):
                    giro = q["giro"] + (90 if sv != 2 else 0) + rr.choice((-8, 0, 7, 180))
                    self.cena.append(
                        {"key": key, "x": round(x, 2), "z": round(z, 2), "giro": giro, "r": r}
                    )
                    postas += 1
                    k += 1

    def mais_cena(self, alvo=64) -> None:
        """Depois das regras por casa, enche os fundos e as beiras com o que ainda couber."""
        rr = random.Random(1967)
        k, tent = 3, 0
        while len(self.cena) < alvo and tent < 9000:
            tent += 1
            x, z = rr.uniform(-MEIO, MEIO), rr.uniform(-MEIO, MEIO)
            if not self.perto(x, z, 3.6):
                continue
            key, r = CENA[k % len(CENA)]
            if key == "ret_pov_d_feno" and math.hypot(x, z) < 30:
                k += 1
                continue
            if self.livre(x, z, r, 4.0, 1.5):
                giro = rr.randrange(0, 360, 15)
                self.cena.append(
                    {"key": key, "x": round(x, 2), "z": round(z, 2), "giro": giro, "r": r}
                )
                k += 1

    def por_cercas(self) -> None:
        for q in self.ret:
            if not q["quintal"]:
                continue
            key = "ret_pov_d_muro" if q["quintal"] == "muro" else "ret_vila_cerca"
            a = math.radians(q["giro"])
            ca, sa = math.cos(a), math.sin(a)
            hx, hz = q["lx"] / 2 + 1.9, q["lz"] / 2 + 2.0

            def w(u, v, q=q, ca=ca, sa=sa):
                return q["x"] + u * ca + v * sa, q["z"] - u * sa + v * ca

            for p0, p1 in (
                ((-hx, -hz * 0.1), (-hx, hz)),
                ((-hx, hz), (-1.6, hz)),
                ((1.6, hz), (hx, hz)),
                ((hx, hz), (hx, -hz * 0.1)),
            ):
                x0, z0 = w(*p0)
                x1, z1 = w(*p1)
                ux, uz = x1 - x0, z1 - z0
                comp = math.hypot(ux, uz)
                n = max(1, int(comp / 4))
                for i in range(n):
                    f = (i + 0.5) / n
                    x, z = x0 + ux * f, z0 + uz * f
                    ok = all(
                        self.livre_cerca(x + ux / comp * s, z + uz / comp * s)
                        for s in (-1.9, 0.0, 1.9)
                    )
                    if ok:
                        giro = round(math.degrees(math.atan2(-uz, ux)), 1)
                        for s in (-1.5, 0.0, 1.5):
                            self.pontos_cerca.append((x + ux / comp * s, z + uz / comp * s))
                        self.cercas.append(
                            {"key": key, "x": round(x, 2), "z": round(z, 2), "giro": giro}
                        )

    def perto(self, x, z, m) -> bool:
        return any(dentro_ret(x, z, q, m) for q in self.ret)

    def por_plantas(self) -> None:
        rr = random.Random(1966)
        regras = (
            ("ret_pov_p_arvore_a", 6, 2.2, 14.0, 1.0, False),
            ("ret_pov_p_arvore_b", 7, 2.0, 11.0, 1.0, False),
            ("ret_pov_p_coqueiro_a", 10, 1.1, 9.0, 1.0, False),
            ("ret_pov_p_coqueiro_b", 10, 1.1, 8.0, 1.0, False),
            ("bamboo_clump", 7, 2.0, 11.0, 0.8, False),
            ("banana", 34, 1.2, 3.8, 1.0, True),
            ("ret_pov_p_arbusto_a", 44, 0.8, 2.6, 1.0, True),
            ("elephant_grass", 18, 0.9, 3.4, 0.75, False),
            ("ret_pov_p_arbusto_b", 44, 0.6, 2.2, 1.0, True),
        )
        for key, total, r, gap, esc, junto in regras:
            postas, tent = 0, 0
            while postas < total and tent < total * 90:
                tent += 1
                x, z = rr.uniform(-MEIO, MEIO), rr.uniform(-MEIO, MEIO)
                if junto and not (self.perto(x, z, 5.5) or na_lagoa(x, z, 3.6)):
                    continue
                if not self.livre(x, z, r, 3.9, 1.6):
                    continue
                if any(math.hypot(x - a, z - b) < r + 2.4 for a, b in CAMERAS):
                    continue  # a comparação usa sempre as mesmas câmeras: nada na lente
                if any(
                    p["key"] == key and math.hypot(x - p["x"], z - p["z"]) < gap
                    for p in self.plantas
                ):
                    continue
                if any(math.hypot(x - p["x"], z - p["z"]) < r + p["r"] * 0.6 for p in self.plantas):
                    continue
                self.plantas.append(
                    {
                        "key": key,
                        "x": round(x, 2),
                        "z": round(z, 2),
                        "giro": rr.randrange(360),
                        "escala": round(esc * rr.uniform(0.85, 1.2), 2),
                        "r": r,
                    }
                )
                postas += 1

    def problemas(self) -> list[str]:
        out = []
        itens = [
            (
                q,
                cantos(
                    q["x"],
                    q["z"],
                    q["giro"],
                    q["lx"],
                    q["lz"],
                    0.12 if q["classe"] == "banca" else 0.3,
                ),
            )
            for q in self.ret
        ]
        for i, (a, ca) in enumerate(itens):
            for b, cb in itens[i + 1 :]:
                if batem(ca, cb):
                    out.append(f"bate: {a['nome']} x {b['nome']}")
            pts = cantos(a["x"], a["z"], a["giro"], a["lx"], a["lz"])
            for k in range(4):
                p, q = pts[k], pts[(k + 1) % 4]
                pts.append(((p[0] + q[0]) / 2, (p[1] + q[1]) / 2))
            d = min(dist_via(p[0], p[1], RUAS) for p in pts)
            if d < 3.3:
                out.append(f"na rua ({d:.1f} m): {a['nome']}")
            c = min(math.hypot(p[0], p[1]) for p in pts)
            if c < 10.5:
                out.append(f"no centro ({c:.1f} m): {a['nome']}")
            if any(
                batem(ca, cantos(f["x"], f["z"], f["giro"], f["lx"], f["lz"])) for f in self.fixos
            ):
                out.append(f"bate no posto: {a['nome']}")
            if any(na_lagoa(p[0], p[1], 0.4) for p in pts):
                out.append(f"na lagoa: {a['nome']}")
        return out

    def desenhar(self) -> None:
        e, r = 13, 50
        im = Image.new("RGB", (2 * r * e, 2 * r * e), (66, 80, 50))
        dr = ImageDraw.Draw(im)
        fonte = ImageFont.truetype(r"C:\Windows\Fonts\arial.ttf", 13)

        def px(p):
            return ((p[0] + r) * e, (p[1] + r) * e)

        dr.rectangle([px((-MEIO, -MEIO)), px((MEIO, MEIO))], outline=(235, 225, 180), width=2)
        for via in RUAS:
            dr.line([px(p) for p in via], fill=(150, 120, 86), width=int(6.4 * e))
        for via in VIELAS:
            dr.line([px(p) for p in via], fill=(122, 104, 74), width=int(2.2 * e))
        pts = []
        a = math.radians(LAGOA["giro"])
        for k in range(32):
            t = k / 32 * 2 * math.pi
            u, v = LAGOA["a"] * math.cos(t), LAGOA["b"] * math.sin(t)
            pts.append(
                px(
                    (
                        LAGOA["x"] + u * math.cos(a) + v * math.sin(a),
                        LAGOA["z"] - u * math.sin(a) + v * math.cos(a),
                    )
                )
            )
        dr.polygon(pts, fill=(70, 110, 120))
        for p in self.plantas:
            c = (44, 92, 40) if p["key"] != "exp_samambaia" else (70, 120, 60)
            q = max(0.5, p["r"])
            dr.ellipse([px((p["x"] - q, p["z"] - q)), px((p["x"] + q, p["z"] + q))], fill=c)
        for c in self.cena:
            q = c["r"] * 0.7
            dr.rectangle(
                [px((c["x"] - q, c["z"] - q)), px((c["x"] + q, c["z"] + q))], fill=(180, 150, 90)
            )
        for c in self.cercas:
            cor = (170, 90, 60) if c["key"] == "ret_pov_d_muro" else (205, 190, 120)
            q = cantos(c["x"], c["z"], c["giro"], 4.0, 0.25)
            dr.polygon([px(p) for p in q], fill=cor)
        cores = {"centro": (214, 170, 92), "bairro": (150, 190, 130), "guerra": (190, 90, 70)}
        for q in self.ret:
            dr.polygon(
                [px(p) for p in cantos(q["x"], q["z"], q["giro"], q["lx"], q["lz"])],
                fill=cores[q["setor"]],
                outline=(30, 26, 20),
            )
            a = math.radians(q["giro"])
            f = (q["x"] - math.sin(a) * q["lz"] / 2, q["z"] - math.cos(a) * q["lz"] / 2)
            dr.line([px((q["x"], q["z"])), px(f)], fill=(30, 26, 20), width=2)
            if q["classe"] != "banca":
                dr.text(
                    px((q["x"] - 4, q["z"] - 0.6)), q["nome"][:18], fill=(10, 10, 10), font=fonte
                )
        PLANTA.parent.mkdir(parents=True, exist_ok=True)
        im.save(PLANTA.with_name("planta_piloto.png"))

    def gravar(self) -> None:
        lin = [
            "--!strict",
            "-- GERADO por tools/vila_piloto_plano.py (D-255). Não editar: mude a planta e rode de novo.",
            "-- Setor piloto da Vila. Posições em metros a partir do centro do Objetivo C.",
            "return {",
            f"\tMEIO = {MEIO},",
            f"\tLAGOA = {{ x = {LAGOA['x']}, z = {LAGOA['z']}, a = {LAGOA['a']}, b = {LAGOA['b']}, giro = {LAGOA['giro']} }},",
            "\tCONSTRUCOES = {",
        ]
        for q in self.ret:
            lin.append(
                f'\t\t{{ nome = "{q["nome"]}", key = "{q["key"]}", x = {q["x"]}, z = {q["z"]}, '
                f'giro = {q["giro"]}, setor = "{q["setor"]}", classe = "{q["classe"]}", '
                f"lx = {round(q['lx'], 2)}, lz = {round(q['lz'], 2)} }},"
            )
        lin += ["\t},", "\tPASSARELAS = {"]
        for key, x, z, giro in PASSARELAS:
            lin.append(f'\t\t{{ key = "{key}", x = {x}, z = {z}, giro = {giro} }},')
        for nome, lista in (("CENA", self.cena), ("CERCAS", self.cercas)):
            lin += ["\t},", f"\t{nome} = {{"]
            for c in lista:
                lin.append(
                    f'\t\t{{ key = "{c["key"]}", x = {c["x"]}, z = {c["z"]}, giro = {c["giro"]} }},'
                )
        lin += ["\t},", "\tPLANTAS = {"]
        for p in self.plantas:
            lin.append(
                f'\t\t{{ key = "{p["key"]}", x = {p["x"]}, z = {p["z"]}, giro = {p["giro"]}, escala = {p["escala"]} }},'
            )
        lin += ["\t},", "\tVIELAS = {"]
        for via in VIELAS:
            lin.append("\t\t{ " + ", ".join(f"{{ {p[0]}, {p[1]} }}" for p in via) + " },")
        lin += ["\t},", "}", ""]
        SAIDA.write_text("\n".join(lin), "utf-8", newline="\n")


def principal() -> None:
    s = Setor()
    s.por_cercas()
    s.por_cena()
    s.mais_cena()
    s.por_plantas()
    p = s.problemas()
    s.desenhar()
    casas = [q for q in s.ret if q["classe"] != "banca"]
    print(
        f"construções: {len(casas)}, modelos {len({q['key'] for q in casas})}, "
        f"bancas: {len(s.ret) - len(casas)}, cena: {len(s.cena)}, cercas: {len(s.cercas)}, "
        f"plantas: {len(s.plantas)}"
    )
    print("problemas:", len(p))
    for t in p:
        print(" -", t)
    if "--gravar" in sys.argv:
        if p:
            raise SystemExit("planta com problemas: não gravei")
        s.gravar()
        print("gravado", SAIDA.name)


if __name__ == "__main__":
    principal()
