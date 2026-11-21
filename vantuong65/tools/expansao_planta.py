"""Planta anotada da expansão (D-232) sobre a carta aérea do mapa.

lune run tools/expansao_planta.luau build/expansao_planta.json
uv run --group arte python tools/expansao_planta.py build/expansao_planta.json testes/lote104
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parent.parent
AEREO = RAIZ / "assets" / "carta" / "aereo_previa.jpg"
M = 0.28
PX_M = 5
LEGENDA_PX = 520

NOMES = {
    "exp_palafita_a": "Palafita com depósito embaixo",
    "exp_palafita_b": "Palafita com varanda",
    "exp_casas_ligadas": "Duas casas ligadas",
    "exp_casa_vala": "Casa à beira da vala",
    "exp_carroca": "Abrigo da carroça e potes",
    "exp_abrigo": "Abrigo semienterrado",
    "exp_trincheira": "Trincheira com toras",
    "exp_prancha": "Prancha sobre a vala",
    "exp_celeiro": "Celeiro com interior",
    "exp_patio": "Pátio de secagem",
    "exp_galpao": "Galpão aberto",
    "exp_deposito": "Depósito elevado",
    "exp_telheiro": "Telheiro de ferramentas",
    "exp_casa_verde": "Casa verde com horta",
    "exp_ruina": "Ruína queimada",
    "exp_comporta": "Comporta e casa de manutenção",
    "exp_passarela": "Passarela sobre o canal",
    "exp_muro": "Muro baixo",
}
TITULOS = {"Vila": "VILA", "Arrozais": "ARROZAL"}


def fonte(tam: int) -> ImageFont.ImageFont:
    for nome in ("arialbd.ttf", "arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(nome, tam)
        except OSError:
            continue
    return ImageFont.load_default()


def desenha(nome: str, d: dict, limites: list[float], aereo: Image.Image, saida: Path) -> None:
    raio = d["raio"]
    lado = 2 * raio * PX_M
    min_x, max_x, min_z, max_z = limites
    aw, ah = aereo.size

    def uv(x: float, z: float) -> tuple[int, int]:
        return (
            int((x - min_x) / (max_x - min_x) * aw),
            int((z - min_z) / (max_z - min_z) * ah),
        )

    a = uv(d["x"] - raio / M, d["z"] - raio / M)
    b = uv(d["x"] + raio / M, d["z"] + raio / M)
    fundo = aereo.crop((*a, *b)).resize((lado, lado), Image.BICUBIC).convert("RGBA")
    camada = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    dr = ImageDraw.Draw(camada)

    def px(x: float, z: float) -> tuple[float, float]:
        return ((x + raio) * PX_M, (z + raio) * PX_M)

    def caixa(p: dict, preenche, contorno, largura: int) -> None:
        ca, sa = math.cos(p["giro"]), math.sin(p["giro"])
        cantos = []
        for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            lx, lz = sx * p["hx"], sz * p["hz"]
            cantos.append(px(p["x"] + lx * ca + lz * sa, p["z"] - lx * sa + lz * ca))
        dr.polygon(cantos, fill=preenche)
        dr.line([*cantos, cantos[0]], fill=contorno, width=largura)

    for m in range(-raio + raio % 20, raio + 1, 20):
        q = (m + raio) * PX_M
        dr.line((q, 0, q, lado), fill=(255, 255, 255, 34))
        dr.line((0, q, lado, q), fill=(255, 255, 255, 34))
    for p in d["antigas"]:
        caixa(p, (255, 255, 255, 34), (255, 255, 255, 170), 1)
    for x, z, r in d["nascer"]:
        c = px(x, z)
        q = r * PX_M
        dr.ellipse((c[0] - q, c[1] - q, c[0] + q, c[1] + q), outline=(120, 210, 255, 230), width=2)
    c = px(0, 0)
    q = 35 * PX_M
    dr.ellipse((c[0] - q, c[1] - q, c[0] + q, c[1] + q), outline=(255, 70, 70, 255), width=4)
    for bc in d["becos"]:
        pts = [px(bc[i], bc[i + 1]) for i in range(0, len(bc) - 1, 2)]
        dr.line(pts, fill=(255, 214, 90, 235), width=int(2.5 * PX_M), joint="curve")
    for ct in d["cortes"]:
        pts = [px(p[0], p[1]) for p in ct["pts"]]
        dr.line(pts, fill=(50, 150, 255, 245), width=max(4, int(ct["largura"] * PX_M)))
    for x, z in d["plantas"]:
        c = px(x, z)
        dr.ellipse((c[0] - 3, c[1] - 3, c[0] + 3, c[1] + 3), fill=(90, 255, 130, 200))

    # numera por modelo: repetições (trincheira, muro) dividem o número
    ordem: list[str] = []
    for p in d["novas"]:
        if p["k"] in NOMES and p["k"] not in ordem:
            ordem.append(p["k"])
    f_num = fonte(25)
    miudos = [p for p in d["novas"] if p["k"] not in NOMES]  # potes, cercas, varais, hortas
    for p in d["novas"]:
        if p["k"] in NOMES:
            caixa(p, (255, 122, 26, 120), (255, 170, 60, 255), 3)
    for p in miudos:
        c = px(p["x"], p["z"])
        dr.ellipse((c[0] - 6, c[1] - 6, c[0] + 6, c[1] + 6), fill=(255, 160, 60, 255))
    for p in d["novas"]:
        if p["k"] not in NOMES:
            continue
        c = px(p["x"], p["z"])
        t = str(ordem.index(p["k"]) + 1)
        dr.ellipse((c[0] - 18, c[1] - 18, c[0] + 18, c[1] + 18), fill=(20, 18, 14, 235))
        dr.text(c, t, font=f_num, fill=(255, 220, 150, 255), anchor="mm")

    img = Image.new("RGB", (lado + LEGENDA_PX, lado), (24, 22, 18))
    img.paste(Image.alpha_composite(fundo, camada).convert("RGB"), (0, 0))
    leg = ImageDraw.Draw(img)
    x0 = lado + 34
    y = 34
    leg.text(
        (x0, y), f"{TITULOS.get(nome, nome)}: O QUE ENTROU", font=fonte(32), fill=(245, 232, 200)
    )
    y += 62
    f = fonte(23)
    for i, k in enumerate(ordem):
        n = sum(1 for p in d["novas"] if p["k"] == k)
        texto = NOMES.get(k, k) + (f" (x{n})" if n > 1 else "")
        leg.ellipse((x0, y - 2, x0 + 34, y + 32), fill=(255, 122, 26))
        leg.text((x0 + 17, y + 15), str(i + 1), font=f, fill=(20, 18, 14), anchor="mm")
        leg.text((x0 + 48, y + 3), texto, font=f, fill=(235, 226, 205))
        y += 44
    y += 16
    for cor, texto in (
        ((255, 214, 90), "Caminho novo"),
        ((50, 150, 255), "Vala ou canal novo"),
        ((255, 160, 60), f"Objetos de quintal ({len(miudos)})"),
        ((90, 255, 130), f"Planta nova ({len(d['plantas'])})"),
        ((255, 255, 255), f"Construção antiga, intacta ({len(d['antigas'])})"),
        ((255, 70, 70), "Área de captura (35 m), intacta"),
        ((120, 210, 255), "Círculo de nascer, intacto"),
    ):
        leg.rectangle((x0, y + 6, x0 + 34, y + 22), fill=cor)
        leg.text((x0 + 48, y), texto, font=f, fill=(235, 226, 205))
        y += 38
    leg.text(
        (x0, lado - 44), "Grade de 20 m. Norte para cima.", font=fonte(20), fill=(170, 160, 140)
    )
    saida.parent.mkdir(parents=True, exist_ok=True)
    img.save(saida, quality=90)
    print(saida, len(d["novas"]), "novas |", len(d["plantas"]), "plantas")


def main() -> None:
    dados = json.loads(Path(sys.argv[1]).read_text("utf-8"))
    pasta = Path(sys.argv[2])
    aereo = Image.open(AEREO).convert("RGB")
    for nome, d in dados["setores"].items():
        desenha(nome, d, dados["bounds"], aereo, pasta / f"planta_{nome.lower()}.jpg")


if __name__ == "__main__":
    main()
