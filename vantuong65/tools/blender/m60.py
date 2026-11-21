"""M60 do VẠN TƯỜNG '65 (D-170; pedido do dono: "a mira da m60 está horrível").

A M60 do gerador (ForgeGUI) era uma malha só, com a alça de mira em três dentes grossos: mirando,
o dente do meio ficava fora da linha da massa e tapava o alvo (o sight_align.py usava o modo
"topo", rente a um dos dentes). Esta é a M60 de 1965 feita no Blender como a SKS e o M16
(tools/blender/sks.py, tools/blender/m16.py), com a mira desenhada para ser vista:

- alça de folha com furo (a do manual: "rear sight aperture", FM 23-67; aqui um anel numa haste
  fina, para ver em volta), atrás da tampa de alimentação, com o botão de elevação à esquerda e o
  de deriva à direita;
- massa em lâmina numa base alta sobre o cano, perto do quebra-chamas;
- entre as duas nada sobe até a linha de visada (tampa, alça de transporte e bipé ficam abaixo).

Convenções (as de armas.py): metros, eixo do cano no eixo Y do Blender com a boca em -Y, Z para
cima, direita do atirador em -X (+X no Roblox). Um nó só, "Arma". `pontos.json` em studs no
referencial local da MeshPart; o tools/weapon_landmarks.py lê este arquivo (a mira é a da
construção: o centro do furo da folha e a ponta da lâmina).

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/m60.py -- m60
    ... -- m60 --montar   (só a forma, com os materiais procedurais, sem o bake)
    ... -- m60 --previa   (prévia do GLB exportado: assets/blender/arma_m60/_previa.png)

Medidas: as com fonte estão em `FONTES`; o resto é PLACEHOLDER (desenho de fotos, sem planta).
"""

from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(RAIZ / "tools" / "faca"))
import armas  # noqa: E402
import comum  # noqa: E402
import espingarda  # noqa: E402  (prévia do GLB e latão)
import m16  # noqa: E402  (plástico preto)
import produzir as faca  # noqa: E402
import sks  # noqa: E402  (aço oxidado)

M_POR_STUD = 0.28
CHAVE = "m60"
PASTA = "arma_m60"
MAT_PLASTICO, MAT_ACO, MAT_ESCURO, MAT_LATAO = 0, 1, 2, 3

FONTES = {
    "comprimento_total_m": "1.105 (wiki:M60_machine_gun)",
    "comprimento_cano_m": "0.560 (wiki:M60_machine_gun)",
    "alca": "folha com furo numa base de encaixe com mola, dobra para a frente (FM 23-67, 1964)",
    "massa": "lâmina: centrar a lâmina no furo da alça (FM 3-22.68)",
    "furo_da_alca_m": "PLACEHOLDER (11 mm, mais largo que o real para aparecer no celular)",
    "linha_de_visada_m": "PLACEHOLDER (0,070 m acima do eixo do cano, de fotos)",
    "raio_de_visada_m": "PLACEHOLDER (~0,70 m, de fotos)",
    "posicao_da_alca": "PLACEHOLDER (atrás da tampa de alimentação, sobre o punho, de fotos)",
}

L = 1.105  # da soleira à boca
ZS = 0.070  # linha de visada acima do eixo do cano
D_ALCA = 0.300  # furo da folha da alça (d da soleira)
D_MASSA = 1.000  # lâmina da massa
# raio do furo da alça (11 mm: no Studio o de 7 mm, a 12 cm do olho, mal mostrava o alvo)
FURO = 0.0055
ANEL = 0.0080  # raio de fora do anel
LAMINA_MEIA = 0.0025  # meia largura da lâmina (5 mm: a de 2,4 mm sumia na tela do celular)
CORONHA_D0 = 0.014  # a soleira de aço e o apoio de ombro dobrado ficam atrás disto


def log(*a) -> None:
    print("[M60]", *a, flush=True)


def lados(a: float, b: float):
    """As duas peças simétricas (esquerda e direita) entre |x| = a e |x| = b."""
    return ((a, b), (-b, -a))


def m60() -> tuple[list, dict]:
    g = armas.Malha()
    # ---------------- coronha reta (plástico) com a soleira de aço e o apoio de ombro dobrado
    coronha = [
        (CORONHA_D0, 0.030, -0.106, 0.0210, 3.0),
        (0.060, 0.032, -0.099, 0.0210, 3.0),
        (0.150, 0.033, -0.080, 0.0195, 2.8),
        (0.230, 0.032, -0.058, 0.0180, 2.6),
        (0.264, 0.030, -0.046, 0.0172, 2.6),
    ]
    g.loft(armas.estacoes(coronha), MAT_PLASTICO)
    g.loft(
        [(0.006, 0.031, -0.108, 0.0215, 3.0), (CORONHA_D0, 0.031, -0.108, 0.0215, 3.0)],
        MAT_ACO,
        k=24,
    )
    g.caixa(-0.0150, 0.0150, 0.000, 0.006, -0.096, 0.024, MAT_ACO)  # apoio de ombro dobrado
    g.cilindro_x(-0.0160, 0.0160, 0.004, -0.098, 0.0040, MAT_ACO)  # dobradiça do apoio
    g.tubo(
        [(0, 0.120, -0.086), (0, 0.122, -0.100), (0, 0.142, -0.098), (0, 0.144, -0.084)],
        0.0018,
        MAT_ACO,
        k=8,
    )
    # ---------------- caixa da culatra (aço): corpo, tampa de alimentação, trinco, bandeja à
    # esquerda (+X), janela de ejeção embaixo à direita e a alavanca de manejo
    g.loft(
        [(0.258, 0.030, -0.044, 0.0190, 6.0), (0.560, 0.030, -0.044, 0.0190, 6.0)],
        MAT_ACO,
        k=24,
    )
    g.loft(
        [
            (0.332, 0.044, 0.026, 0.0200, 4.0),
            (0.342, 0.051, 0.026, 0.0210, 4.0),
            (0.512, 0.051, 0.026, 0.0210, 4.0),
            (0.522, 0.045, 0.026, 0.0200, 4.0),
        ],
        MAT_ACO,
        k=24,
    )
    g.caixa(-0.0100, 0.0100, 0.322, 0.334, 0.030, 0.047, MAT_ACO)  # trinco da tampa
    g.caixa(-0.0165, -0.0100, 0.324, 0.332, 0.040, 0.046, MAT_ACO)  # alavanca do trinco
    for x0, x1 in lados(0.0190, 0.0215):  # dobradiça da tampa na frente
        g.caixa(x0, x1, 0.506, 0.522, 0.026, 0.040, MAT_ACO)
    g.caixa(0.0190, 0.0330, 0.440, 0.502, 0.004, 0.026, MAT_ACO)  # bandeja de alimentação
    g.caixa(-0.0198, -0.0186, 0.440, 0.500, -0.034, -0.008, MAT_ESCURO)  # janela de ejeção
    g.caixa(-0.0330, -0.0190, 0.470, 0.482, -0.012, 0.000, MAT_ACO)  # alavanca de manejo
    g.esfera(-0.0340, 0.476, -0.006, 0.0055, MAT_ACO, seg=12, an=8)
    # ---------------- alça de folha: base de encaixe atrás do trinco, botões de elevação
    # (esquerda) e de deriva (direita), a folha e o anel do furo no alto dela. Feita de jogo: a
    # folha real envolve o furo numa placa; no Studio, a 12 cm do olho, a placa preta tapava o
    # meio da tela, e o anel numa haste fina (como o do M16) deixa ver em volta
    g.caixa(-0.0140, 0.0140, 0.285, 0.318, 0.030, 0.040, MAT_ACO)
    g.cilindro_x(0.0140, 0.0240, 0.300, 0.038, 0.0065, MAT_ACO, k=20)  # elevação
    g.cilindro_x(-0.0220, -0.0140, 0.300, 0.036, 0.0050, MAT_ACO, k=16)  # deriva
    g.caixa(-0.0055, 0.0055, D_ALCA - 0.0015, D_ALCA + 0.0015, 0.040, ZS - FURO - 0.0015, MAT_ACO)
    g.torno(
        [
            (D_ALCA - 0.0020, FURO),
            (D_ALCA - 0.0020, ANEL),
            (D_ALCA + 0.0020, ANEL),
            (D_ALCA + 0.0020, FURO),
            (D_ALCA - 0.0020, FURO),
        ],
        0,
        ZS,
        MAT_ACO,
        k=28,
    )
    # ---------------- cano (aço), luva na frente da caixa, guarda-mão (plástico) embaixo do cano
    g.torno([(0.546, 0.0200), (0.578, 0.0200)], 0, 0.0, MAT_ACO, k=24, cap0=MAT_ACO, cap1=MAT_ACO)
    g.torno(
        [(0.560, 0.0130), (0.700, 0.0125), (0.980, 0.0115), (1.040, 0.0112)],
        0,
        0.0,
        MAT_ACO,
        k=24,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    guarda = [(0.566, 0.006, -0.058, 0.0255, 3.0)]
    for i in range(7):  # nervuras do guarda-mão
        c = 0.585 + i * 0.026
        guarda += [
            (c - 0.006, 0.006, -0.058, 0.0255, 3.0),
            (c - 0.004, 0.005, -0.056, 0.0242, 3.0),
            (c + 0.004, 0.005, -0.056, 0.0242, 3.0),
            (c + 0.006, 0.006, -0.058, 0.0255, 3.0),
        ]
    guarda.append((0.776, 0.004, -0.052, 0.0240, 3.0))
    g.loft(guarda, MAT_PLASTICO, k=24)
    # alça de transporte: braçadeira no cano e o arco dobrado para a esquerda (+X), abaixo da
    # linha de visada
    g.torno([(0.588, 0.0158), (0.606, 0.0158)], 0, 0.0, MAT_ACO, k=20, cap0=MAT_ACO, cap1=MAT_ACO)
    g.tubo(
        [
            (0.014, 0.590, 0.008),
            (0.048, 0.586, 0.016),
            (0.062, 0.602, 0.020),
            (0.062, 0.660, 0.020),
            (0.050, 0.676, 0.016),
            (0.016, 0.604, 0.008),
        ],
        0.0042,
        MAT_ACO,
        k=10,
    )
    # cilindro de gases embaixo do cano, ligação ao cano e o bipé dobrado para trás
    g.torno(
        [(0.770, 0.0115), (0.905, 0.0115)], 0, -0.030, MAT_ACO, k=16, cap0=MAT_ACO, cap1=MAT_ACO
    )
    g.caixa(-0.0080, 0.0080, 0.888, 0.904, -0.030, 0.000, MAT_ACO)
    g.caixa(-0.0130, 0.0130, 0.895, 0.917, -0.046, -0.020, MAT_ACO)  # cabeça do bipé
    for s in (1.0, -1.0):
        g.tubo(
            [(0.010 * s, 0.906, -0.046), (0.018 * s, 0.800, -0.064), (0.020 * s, 0.650, -0.068)],
            0.0045,
            MAT_ACO,
            k=8,
        )
        g.caixa(0.012 * s - 0.006, 0.012 * s + 0.006, 0.632, 0.652, -0.076, -0.062, MAT_ACO)
    # ---------------- massa: braçadeira no cano, base alta e a lâmina até a linha de visada
    g.torno(
        [(D_MASSA - 0.013, 0.0145), (D_MASSA + 0.013, 0.0145)],
        0,
        0.0,
        MAT_ACO,
        k=20,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    g.loft(
        [
            (D_MASSA - 0.012, 0.014, 0.008, 0.0055, 6.0),
            (D_MASSA - 0.006, 0.052, 0.008, 0.0055, 6.0),
            (D_MASSA + 0.006, 0.052, 0.008, 0.0055, 6.0),
            (D_MASSA + 0.012, 0.014, 0.008, 0.0055, 6.0),
        ],
        MAT_ACO,
        k=20,
    )
    g.caixa(-LAMINA_MEIA, LAMINA_MEIA, D_MASSA - 0.004, D_MASSA + 0.004, 0.050, ZS, MAT_ACO)
    # ---------------- quebra-chamas: colar, seis barras e o anel da boca (oco)
    g.torno(
        [(1.036, 0.0150), (1.048, 0.0150)], 0, 0.0, MAT_ACO, k=20, cap0=MAT_ACO, cap1=MAT_ESCURO
    )
    for i in range(6):
        a = math.radians(30 + 60 * i)
        x, z = 0.0122 * math.cos(a), 0.0122 * math.sin(a)
        g.tubo([(x, 1.046, z), (x, L - 0.006, z)], 0.0026, MAT_ACO, k=6)
    g.torno(
        [
            (L - 0.008, 0.0095),
            (L - 0.008, 0.0150),
            (L, 0.0150),
            (L, 0.0095),
            (L - 0.008, 0.0095),
        ],
        0,
        0.0,
        MAT_ACO,
        k=20,
    )
    # ---------------- punho de pistola (plástico), guarda-mato e gatilho
    g.tubo(
        [
            (0, 0.340, -0.040),
            (0, 0.333, -0.066),
            (0, 0.325, -0.094),
            (0, 0.318, -0.122),
            (0, 0.316, -0.130),
        ],
        0.0125,
        MAT_PLASTICO,
        k=16,
        achatar=1.5,
    )
    g.tubo(
        [
            (0, 0.352, -0.044),
            (0, 0.353, -0.062),
            (0, 0.362, -0.070),
            (0, 0.396, -0.070),
            (0, 0.404, -0.060),
            (0, 0.405, -0.044),
        ],
        0.0050,
        MAT_ACO,
        k=10,
        achatar=0.4,
    )
    g.tubo(
        [(0, 0.376, -0.043), (0, 0.374, -0.054), (0, 0.369, -0.063)],
        0.0032,
        MAT_ACO,
        k=10,
        achatar=0.5,
    )
    # ---------------- pedaço da fita de munição saindo da bandeja (esquerda), caindo em arco
    x, z, ang = 0.040, 0.014, 0.0
    for _ in range(6):
        g.torno(
            [(0.452, 0.0060), (0.494, 0.0058), (0.499, 0.0043), (0.504, 0.0040)],
            x,
            z,
            MAT_LATAO,
            k=10,
            cap0=MAT_LATAO,
        )
        g.torno(
            [(0.504, 0.0040), (0.520, 0.0036), (0.531, 0.0010)],
            x,
            z,
            MAT_LATAO,
            k=10,
            cap1=MAT_LATAO,
        )
        g.caixa(x - 0.0050, x + 0.0050, 0.470, 0.484, z - 0.0068, z - 0.0052, MAT_ACO)  # elo
        ang += math.radians(16)
        x += 0.0122 * math.cos(ang)
        z -= 0.0122 * math.sin(ang)
    obj = g.objeto("m60")
    pontos = {
        "muzzle": (0.0, L, 0.0),
        "sight": (0.0, D_ALCA, ZS),
        "front": (0.0, D_MASSA, ZS),
        # mão direita no punho de pistola, 10 cm abaixo do cano (lote 7: rente à caixa, a mão
        # tapava meia tela mirando); a esquerda embaixo do guarda-mão, logo à frente da caixa (a
        # ~0,25 m do punho: limite de 0,26 m do teste da F5, D-59). Olho a 12 cm do furo (o
        # mínimo do teste das armas para metralhadora)
        "grip": (0.0, 0.323, -0.102),
        "support": (0.0, 0.572, -0.058),
        "eyeM": 0.12,
        "comprimento_m": L,
    }
    return [obj], pontos


# ------------------------------------------------------------------ materiais
def materiais_m60() -> dict:
    return {
        "plastico": m16.plastico_m16("plastico_m60"),
        "aco": sks.oxidado("aco_m60"),
        "escuro": espingarda.escuro("escuro_m60"),
        "latao": espingarda.latao("latao_m60"),
    }


ORDEM = ("plastico", "aco", "escuro", "latao")


# ------------------------------------------------------------------ pontos
def medir(pontos: dict, caminho: Path) -> dict:
    nos = faca.ler_nos(caminho)
    R = nos["Arma"] * np.array([-1.0, 1.0, -1.0])
    lo, hi = R.min(axis=0), R.max(axis=0)
    c = (lo + hi) / 2
    out = {
        k: armas.para_roblox(pontos[k], c) for k in ("muzzle", "sight", "front", "grip", "support")
    }
    v = R - c
    out["lowX"] = round(float(v[:, 0].min() - out["grip"][0]), 4)
    out["lengthM"] = round(float(hi[2] - lo[2]) * M_POR_STUD, 4)
    out["eyeM"] = pontos["eyeM"]
    out["forward"] = "-Z"
    out["tamanho"] = [round(float(x), 4) for x in hi - lo]
    gs = np.array(out["support"]) - np.array(out["grip"])
    out["_conferencia"] = {
        "boca_vs_vertice_mais_a_frente": round(out["muzzle"][2] - float(lo[2] - c[2]), 4),
        "comprimento_ficha_m": pontos["comprimento_m"],
        "apoio_ao_punho_m": round(float(np.linalg.norm(gs)) * M_POR_STUD, 4),
        "linha_de_visada_m": ZS,
        "raio_de_visada_m": round(D_MASSA - D_ALCA, 4),
    }
    return out


# ------------------------------------------------------------------ produção
def produzir() -> dict:
    t0 = time.time()
    cena = faca.cena_cpu()
    objs, pontos = m60()
    mats = materiais_m60()
    obj = objs[0]
    # sem materials.clear(): ele zera o material_index das faces
    for nome in ORDEM:
        obj.data.materials.append(mats[nome][0])
    faca.triangular_e_vivas(obj, set())
    comum.selecionar_so(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")
    uso = faca.empacotar(obj)
    arma = faca.extrair(obj, "Arma", lambda no, dup: no == 0)
    bpy.data.objects.remove(obj)
    cena.world.light_settings.distance = 0.012
    bk = faca.assar(cena, [arma], mats)
    pasta = comum.SAIDA / PASTA
    texturas, info = faca.compor(bk["imgs"], comum.TRABALHO / PASTA)
    caminho = pasta / f"{PASTA}.glb"
    exp = comum.exportar_glb([("Arma", arma)], caminho, texturas, metal=True)
    pts = medir(pontos, caminho)
    tris = len(comum.arrays_malha(arma)[3]) // 3
    (pasta / "pontos.json").write_text(
        json.dumps(pts, ensure_ascii=False, indent=1) + "\n", "utf-8"
    )
    met = {
        "chave": CHAVE,
        "nome": "M60 (1965): alça de folha com furo, massa em lâmina, bipé dobrado, fita de "
        "munição",
        "triangulos": tris,
        "textura_px": faca.TEX,
        "mb": exp["mb"],
        "uso_uv": uso,
        "texturas": info,
        "bake_s": bk["tempos"],
        "medidas_reais": FONTES,
        "comprimento_m": pts["lengthM"],
    }
    comum.gravar_json(pasta / "metricas.json", met)
    log(json.dumps({**met, "pontos": pts}, ensure_ascii=False), f"total {time.time() - t0:.0f} s")
    return met


def main() -> None:
    a = comum.argumentos()
    if "--montar" in a:
        # só a peça montada com os materiais procedurais, de lado (conferir a forma antes do bake)
        faca.cena_cpu()
        objs, _ = m60()
        mats = materiais_m60()
        for nome in ORDEM:
            objs[0].data.materials.append(mats[nome][0])
        armas.previa(objs, comum.TRABALHO / PASTA / "montada.png")
        return
    if "--previa" in a:
        espingarda.previa(comum.SAIDA / PASTA / f"{PASTA}.glb", comum.SAIDA / PASTA / "_previa.png")
        return
    produzir()


if __name__ == "__main__":
    main()
