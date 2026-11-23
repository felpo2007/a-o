"""Planta do povoado da Vila (D-255): quatro setores, 45 a 55 construções, ruas e vielas.

Confere sobreposição, distância das ruas e o centro de captura, desenha a planta e grava o módulo
`Shared/VilaPovoado.luau`. Posições em metros a partir do centro do Objetivo C (X leste, Z sul).
`giro` é o do Roblox: a frente do modelo (-Y do Blender) olha para (-sen, -cos).

    uv run --group arte python tools/vila_plano.py            # confere e desenha
    (o módulo do jogo sai de tools/vila_piloto_plano.py --gravar; este plano é o da expansão)
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parents[1]
SAIDA = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "VilaPovoado.luau"
PLANTA = RAIZ / "testes" / "lote122" / "planta.png"

RUAS = (
    ((-50, 49), (-23, 23), (-5, 5), (-1, 0)),
    ((-1, 0), (-2, 9), (-2, 18), (-1, 36), (-1, 80)),
    ((-1, 0), (8, -5), (17, -13), (35, -31), (60, -56)),
    ((8, -4), (17, -1), (26, 0), (53, 0), (85, 0)),
)
# caminhos estreitos entre os quintais: a segunda rota de cada bairro
VIELAS = (
    ((-14, -30), (-24, -33), (-31, -47), (-47, -50)),
    ((-14, -30), (-3, -33), (12, -47), (21, -66)),
    ((-44, -25), (-55, -22), (-62, -34)),
    ((-27, 30), (-37, 38), (-38, 55), (-23, 74), (-1, 78)),
    ((-38, 55), (-55, 60)),
    ((12, 44), (20, 56), (33, 60), (46, 52), (58, 26), (60, 8)),
    ((33, 60), (37, 78), (55, 82)),
    ((62, -3), (82, -22), (90, -42)),
    ((76, 3), (79, 22), (72, 44), (58, 52)),
    ((35, -31), (50, -44), (72, -56)),
)
SETORES = {
    "centro": (214, 170, 92),
    "bairro": (120, 170, 110),
    "campo": (170, 150, 90),
    "guerra": (190, 90, 70),
}
# pegada medida na montagem (X, Z em metros), para o que ainda não tem metricas.json
PEGADAS = {
    "ret_pov_chua": (23.4, 20.0),
    "ret_pov_mercado": (17.0, 11.2),
    "ret_pov_banca_d": (4.5, 3.5),
    "ret_pov_banca_e": (4.5, 3.5),
    "ret_pov_banca_f": (4.5, 3.5),
    "ret_pov_banca_g": (4.5, 3.5),
    "ret_pov_escola": (24.9, 10.5),
    "ret_pov_escola_ala": (15.9, 10.2),
    "ret_pov_mercearia": (8.8, 6.8),
    "ret_pov_cha": (9.2, 8.4),
    "ret_pov_pho": (9.8, 7.2),
    "ret_pov_alfaiate": (8.2, 6.5),
    "ret_pov_barbearia": (5.5, 5.6),
    "ret_pov_carpintaria": (11.8, 11.1),
    "ret_pov_ferraria": (8.4, 6.7),
    "ret_pov_laterita": (10.9, 11.4),
    "ret_pov_patio": (12.5, 12.5),
    "ret_pov_abandonada": (10.1, 6.8),
    "ret_pov_armazem": (16.3, 10.1),
    "ret_pov_bufalos": (8.2, 5.5),
    "ret_pov_galinheiro": (8.2, 5.4),
    "ret_pov_cestos": (7.6, 6.0),
    "ret_pov_moinho": (9.2, 6.7),
    "ret_pov_medico": (10.1, 7.8),
    "ret_pov_santuario": (5.2, 4.3),
    "ret_pov_poco": (4.6, 4.0),
    "ret_pov_cemiterio": (12.8, 10.0),
    "ret_pov_lavagem": (9.6, 6.9),
    "ret_pov_destruida": (10.7, 7.4),
    "ret_pov_guarda": (6.6, 7.6),
    "ret_pov_defensiva": (11.6, 7.8),
    "ret_pov_armazem_ruina": (13.3, 8.3),
    "ret_pov_socorro": (7.8, 5.4),
    "ret_pov_barricada": (13.3, 3.3),
    "ret_pov_esconderijo": (5.5, 4.6),
    "vila_casa_01": (13, 14),
    "vila_casa_03": (14, 11),
    "vila_casa_04": (12, 13),
    "vila_casa_05": (9, 13),
    "vila_casa_06": (14, 11),
    "vila_casa_08": (11, 11),
    "vila_casa_09": (12, 14),
    "vila_casa_10": (14, 14),
}
# o que já existe e fica onde está (sobrados da expansão e a arte fixa do place)
FICA = (
    ("exp_sobrado_a", -30, -62, 180, 18, 13),
    ("exp_sobrado_a", -10, -98, 180, 18, 13),
    ("exp_sobrado_d", -50, -98, 180, 18, 13),
    ("exp_sobrado_c", -76, -20, 2, 17, 13),
    ("exp_sobrado_b", -78, 44, 91, 18, 12),
    ("exp_casas_ligadas", -62, -63, 168, 15, 8),
    ("exp_palafita_a", -84, -60, 180, 10, 13),
    ("exp_casa_vala", -100, -8, 0, 8, 7),
)
POSTO = ("ret_vila_posto", -1.5, 47, 0, 17.5, 4.3)
TORRE = ("ret_vila_torre", 30, -11, 90, 5.1, 9.9)


def virado(x, z, alvo_x, alvo_z):
    """O giro que deixa a frente olhando para o alvo, de 5 em 5 graus."""
    return round(math.degrees(math.atan2(-(alvo_x - x), -(alvo_z - z))) / 5) * 5


def linha_bancas() -> list[tuple]:
    """O mercado: duas fileiras de bancas de frente uma para a outra, com corredor estreito."""
    cx, cz = -32.8, -3.2
    d = (-0.7071, 0.7071)  # ao longo da rua
    n = (0.7071, 0.7071)  # para a rua
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
    out = []
    k = 0
    for fila, (dist, giro) in enumerate(((9.6, -135), (15.3, 45))):
        for s in (-8.55, -2.85, 2.85, 8.55):
            x = round(cx + n[0] * dist + d[0] * s, 2)
            z = round(cz + n[1] * dist + d[1] * s, 2)
            out.append((f"Banca {k + 1}", tipos[k], x, z, giro, "centro", "banca"))
            k += 1
        _ = fila
    return out


PLANO: list[tuple] = [
    # ---- centro: os marcos, o mercado e as lojas da rua principal
    ("Casa comunitária (đình)", "ret_vila_dinh", -18, -18, -135, "centro", "marco"),
    ("Pagode", "ret_pov_chua", 24.5, 24, 45, "centro", "marco"),
    ("Mercado central", "ret_pov_mercado", -32.8, -3.2, -135, "centro", "marco"),
    *linha_bancas(),
    ("Escola", "ret_pov_escola", 50, -22, 180, "centro", "marco"),
    ("Escola, ala", "ret_pov_escola_ala", 69, -17.5, 90, "centro", "marco"),
    ("Poço comunitário", "ret_pov_poco", -5.5, -15, -135, "centro", "casa"),
    ("Santuário de antepassados", "ret_pov_santuario", 3, -20, -150, "centro", "casa"),
    ("Casa do chefe da aldeia", "vila_casa_03", -44, -15, -135, "centro", "casa"),
    ("Mercearia", "ret_pov_mercearia", -9.8, 24.6, -90, "centro", "casa"),
    ("Casa de chá", "ret_pov_cha", -10.8, 35.6, -90, "centro", "casa"),
    ("Restaurante de phở", "ret_pov_pho", 48, 7.6, 0, "centro", "casa"),
    ("Alfaiataria", "ret_pov_alfaiate", 58.4, 7, 0, "centro", "casa"),
    ("Barbearia", "ret_pov_barbearia", 66.6, 6.4, 0, "centro", "casa"),
    ("Oficina de bicicletas", "ret_merc_oficina", 75, 7.5, 0, "centro", "casa"),
    # ---- bairros: ao norte e a sudoeste, irregulares, com quintal e viela
    ("Casa laterítica", "ret_pov_laterita", 6, -42, -130, "bairro", "casa"),
    ("Casa com pátio interno", "ret_pov_patio", -15, -47, 165, "bairro", "casa"),
    ("Casa de madeira com telhas", "vila_casa_06", -40, -40, -150, "bairro", "casa"),
    ("Casa de taipa e telha", "vila_casa_10", -58, -39, 150, "bairro", "casa"),
    ("Casa sobre esteios", "ret_vila_palafita_a", 22, -61, -140, "bairro", "casa"),
    ("Casa de família pobre", "vila_casa_05", 3, -63, -160, "bairro", "casa"),
    ("Casa de taipa", "ret_vila_terra", -14, -76, 170, "bairro", "casa"),
    ("Casa laterítica antiga", "ret_pov_laterita", -32, 48, 65, "bairro", "casa"),
    ("Casa sobre esteios pequena", "ret_vila_palafita_b", -49, 34, 120, "bairro", "casa"),
    ("Casa meio tijolo", "vila_casa_08", -54, 58, 75, "bairro", "casa"),
    ("Casa com jirau", "vila_casa_09", -21, 62, 95, "bairro", "casa"),
    ("Casa de taipa em L", "vila_casa_04", -38, 74, 20, "bairro", "casa"),
    ("Residência abandonada", "ret_pov_abandonada", -68, 26, 105, "bairro", "casa"),
    ("Posto de atendimento", "ret_pov_medico", 15, 57, 80, "bairro", "casa"),
    ("Casa sobre esteios", "ret_vila_palafita_b", 12, 73, 95, "bairro", "casa"),
    # ---- periferia agrícola: ao nordeste e ao sul, junto das plantações
    ("Armazém de arroz", "ret_pov_armazem", 40, -49, -135, "campo", "marco"),
    ("Carpintaria", "ret_pov_carpintaria", 73, -42, -115, "campo", "casa"),
    ("Ferraria", "ret_pov_ferraria", 92, -28, -100, "campo", "casa"),
    ("Descascador de arroz", "ret_pov_moinho", 33, -76, -160, "campo", "casa"),
    ("Oficina de cestos", "ret_pov_cestos", 13, -84, 170, "campo", "casa"),
    ("Galinheiro e chiqueiro", "ret_pov_galinheiro", 56, -78, -150, "campo", "casa"),
    ("Casa de agricultor", "vila_casa_01", 44, 70, 20, "campo", "casa"),
    ("Celeiro do agricultor", "ret_comp_celeiro", 62, 72, -60, "campo", "casa"),
    ("Abrigo de búfalos", "ret_pov_bufalos", 31, 84, -10, "campo", "casa"),
    ("Galpão de ferramentas", "exp_telheiro", 50, 88, 10, "campo", "casa"),
    ("Secagem de arroz", "exp_patio", 27, 68, 40, "campo", "casa"),
    ("Área de lavagem", "ret_pov_lavagem", -14, 85, 85, "campo", "casa"),
    ("Cemitério tradicional", "ret_pov_cemiterio", -62, 80, 40, "campo", "casa"),
    # ---- área afetada pela guerra: a entrada leste, por onde vem o ataque
    ("Barricada com guarita", "ret_pov_barricada", 90, -10.5, -90, "guerra", "casa"),
    ("Posto de guarda", "ret_pov_guarda", 85.6, 7.8, -80, "guerra", "casa"),
    ("Casa destruída", "ret_pov_destruida", 97, 15, -110, "guerra", "casa"),
    ("Casa queimada", "exp_ruina", 74, 24, -40, "guerra", "casa"),
    ("Casa fortificada", "ret_pov_defensiva", 96, 33, -115, "guerra", "casa"),
    ("Armazém abandonado", "ret_pov_armazem_ruina", 80, 47, -130, "guerra", "casa"),
    ("Posto de socorro", "ret_pov_socorro", 61, 28, -60, "guerra", "casa"),
    ("Abrigo de proteção civil", "exp_abrigo", 64, 42, -35, "guerra", "casa"),
    ("Entrada disfarçada", "ret_pov_esconderijo", 88, 25, -70, "guerra", "casa"),
]


def pegada(key: str) -> tuple[float, float]:
    arq = RAIZ / "assets" / "blender" / key / "metricas.json"
    if arq.is_file():
        d = json.loads(arq.read_text("utf-8"))["novo"].get("dim_m_xyz")
        if d and d[0] > 0:
            return float(d[0]), float(d[2])
    return PEGADAS[key]


def cantos(x, z, giro, lx, lz, folga=0.0):
    a = math.radians(giro)
    dx, dz = (math.cos(a), -math.sin(a)), (math.sin(a), math.cos(a))
    hx, hz = lx / 2 + folga, lz / 2 + folga
    return [
        (x + sx * hx * dx[0] + sz * hz * dz[0], z + sx * hx * dx[1] + sz * hz * dz[1])
        for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))
    ]


def batem(p, q) -> bool:
    """Eixos separadores de dois retângulos."""
    for poli in (p, q):
        for i in range(4):
            a, b = poli[i], poli[(i + 1) % 4]
            n = (b[1] - a[1], a[0] - b[0])
            pa = [n[0] * c[0] + n[1] * c[1] for c in p]
            qa = [n[0] * c[0] + n[1] * c[1] for c in q]
            if max(pa) <= min(qa) or max(qa) <= min(pa):
                return False
    return True


def dist_via(x, z, vias) -> float:
    melhor = 1e9
    for via in vias:
        for a, b in zip(via[:-1], via[1:], strict=True):
            ux, uz = b[0] - a[0], b[1] - a[1]
            t = max(0.0, min(1.0, ((x - a[0]) * ux + (z - a[1]) * uz) / (ux * ux + uz * uz)))
            melhor = min(melhor, math.hypot(x - a[0] - t * ux, z - a[1] - t * uz))
    return melhor


def conferir() -> list[str]:
    problemas = []
    fixos = [(f[0], cantos(f[1], f[2], f[3], f[4], f[5])) for f in (*FICA, POSTO, TORRE)]
    itens = []
    for nome, key, x, z, giro, _setor, classe in PLANO:
        lx, lz = pegada(key)
        folga = 0.15 if classe == "banca" else 0.6
        itens.append((nome, cantos(x, z, giro, lx, lz, folga), key, x, z, lx, lz, giro, classe))
    for i, a in enumerate(itens):
        for b in itens[i + 1 :]:
            if batem(a[1], b[1]):
                problemas.append(f"bate: {a[0]} x {b[0]}")
        for f, c in fixos:
            if batem(a[1], c):
                problemas.append(f"bate no que fica: {a[0]} x {f}")
        amostras = cantos(a[3], a[4], a[7], a[5], a[6])
        for k in range(4):
            p, q = amostras[k], amostras[(k + 1) % 4]
            amostras.append(((p[0] + q[0]) / 2, (p[1] + q[1]) / 2))
        d = min(dist_via(p[0], p[1], RUAS) for p in amostras)
        if d < 3.4:
            problemas.append(f"na rua ({d:.1f} m): {a[0]}")
        c = min(math.hypot(p[0], p[1]) for p in amostras)
        if c < 11.5:
            problemas.append(f"no centro da captura ({c:.1f} m): {a[0]}")
    return problemas


def desenhar() -> None:
    e = 6
    r = 125
    im = Image.new("RGB", (2 * r * e, 2 * r * e), (66, 80, 50))
    dr = ImageDraw.Draw(im)
    fonte = ImageFont.truetype(r"C:\Windows\Fonts\arial.ttf", 11)

    def px(p):
        return ((p[0] + r) * e, (p[1] + r) * e)

    for via in RUAS:
        dr.line([px(p) for p in via], fill=(150, 120, 86), width=int(7 * e))
    for via in VIELAS:
        dr.line([px(p) for p in via], fill=(122, 104, 74), width=int(2.4 * e))
    dr.ellipse([px((-12, -12)), px((12, 12))], outline=(240, 220, 120), width=3)
    for f in (*FICA, POSTO, TORRE):
        dr.polygon([px(c) for c in cantos(f[1], f[2], f[3], f[4], f[5])], fill=(96, 96, 96))
    for nome, key, x, z, giro, setor, classe in PLANO:
        lx, lz = pegada(key)
        c = cantos(x, z, giro, lx, lz)
        dr.polygon([px(p) for p in c], fill=SETORES[setor], outline=(30, 26, 20))
        a = math.radians(giro)
        f = (x - math.sin(a) * lz / 2, z - math.cos(a) * lz / 2)
        dr.line([px((x, z)), px(f)], fill=(30, 26, 20), width=2)
        if classe != "banca":
            dr.text(px((x - 6, z - 1)), nome[:20], fill=(10, 10, 10), font=fonte)
    PLANTA.parent.mkdir(parents=True, exist_ok=True)
    im.save(PLANTA)


def gravar() -> None:
    lin = [
        "--!strict",
        "-- GERADO por tools/vila_plano.py (D-255). Não editar: mude a planta e rode de novo.",
        "-- Posições em metros a partir do centro do Objetivo C.",
        "return {",
        "\tCONSTRUCOES = {",
    ]
    for nome, key, x, z, giro, setor, classe in PLANO:
        lx, lz = pegada(key)
        lin.append(
            f'\t\t{{ nome = "{nome}", key = "{key}", x = {x}, z = {z}, giro = {giro}, '
            f'setor = "{setor}", classe = "{classe}", lx = {round(lx, 2)}, lz = {round(lz, 2)} }},'
        )
    lin += ["\t},", "\tVIELAS = {"]
    for via in VIELAS:
        lin.append("\t\t{ " + ", ".join(f"{{ {p[0]}, {p[1]} }}" for p in via) + " },")
    lin += ["\t},", "}", ""]
    SAIDA.write_text("\n".join(lin), "utf-8", newline="\n")


def principal() -> None:
    problemas = conferir()
    desenhar()
    por = {s: sum(1 for p in PLANO if p[5] == s and p[6] != "banca") for s in SETORES}
    bancas = sum(1 for p in PLANO if p[6] == "banca")
    print("construções:", sum(por.values()), por, "| bancas do mercado:", bancas)
    print("modelos diferentes:", len({p[1] for p in PLANO}))
    print("problemas:", len(problemas))
    for t in problemas:
        print(" -", t)
    if "--gravar" in sys.argv:
        # D-255: VilaPovoado agora sai de vila_piloto_plano.py, em outro formato
        raise SystemExit("use tools/vila_piloto_plano.py --gravar")
        if problemas:
            raise SystemExit("planta com problemas: não gravei")
        gravar()
        print("gravado", SAIDA.name)


if __name__ == "__main__":
    principal()
