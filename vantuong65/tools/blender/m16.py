"""Fuzil M16 do VẠN TƯỜNG '65 (lote 31, D-146; pedido do dono: "cadê a arma M4", com a foto de um
M16 de guarda-mão triangular, alça de transporte e quebra-chamas de três dentes).

O M4 é de 1994; a foto é o M16 da Guerra do Vietnã (XM16E1/M16A1, 1965–67), que é o que se modela
aqui. Chave `m16` (Shared/Weapons, AssetIds.Models, WeaponArt).

Modela no Blender e assa as texturas PBR com o mesmo bake das outras armas do Blender
(tools/blender/armas.py, espingarda.py), num atlas único de 1024 px:
- plástico preto (coronha fixa A1, punho e guarda-mão triangular com nervuras);
- alumínio anodizado preto-acinzentado (receptores, alça de transporte, carregador, anel delta);
- aço fosfatizado fosco (cano, base de massa em "A", quebra-chamas, gatilho, pinos).

Mira (o que o olho vê): alça de anel grande (5 mm) no fundo da alça de transporte, entre duas
orelhas; a alça de transporte é um canal (dois trilhos com o vão no meio), então a linha de visada
passa por dentro dele até a massa, um poste fino entre as orelhas da base em "A". Linha de visada a
ZS acima do eixo do cano.

Convenções (as de armas.py): metros, eixo do cano no eixo Y do Blender com a boca em -Y, Z para
cima, direita do atirador em -X (+X no Roblox). Um nó só, "Arma". `pontos.json` em studs no
referencial local da MeshPart (o importador gira o GLB 180° em Y e centra a peça na caixa dos
vértices), relendo o GLB exportado; o tools/weapon_landmarks.py lê este arquivo (a mira é a da
construção: o centro do anel e a ponta do poste).

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/m16.py -- m16
    ... -- m16 --montar   (só a forma, com os materiais procedurais, sem o bake)
    ... -- m16 --previa   (prévia do GLB exportado: assets/blender/arma_m16/_previa.png)

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
import espingarda  # noqa: E402  (material escuro e a prévia do GLB)
import materiais  # noqa: E402
import produzir as faca  # noqa: E402

M_POR_STUD = 0.28
CHAVE = "m16"
PASTA = "arma_m16"
MAT_PLASTICO, MAT_ANOD, MAT_ACO, MAT_ESCURO = 0, 1, 2, 3

FONTES = {
    "comprimento_total_m": "0.99 (39 pol. com o quebra-chamas: wiki:M16_rifle, M16/M16A1)",
    "comprimento_cano_m": "0.508 (20 pol.: wiki:M16_rifle)",
    "raio_de_visada_m": "0.502 (19,75 pol. do M16A1; PLACEHOLDER sem conferir no manual)",
    "carregador": "20 tiros, reto (wiki:M16_rifle; o de 30 é de 1970)",
    "linha_de_visada_m": "0.066 (PLACEHOLDER: ~2,6 pol. acima do eixo do cano, de fotos)",
    "alca": "PLACEHOLDER (alça de anel no fundo da alça de transporte; anel grande de 5 mm)",
    "massa": "PLACEHOLDER (poste na base em 'A', com as duas orelhas)",
    "guarda_mao": "PLACEHOLDER (triangular do M16/M16A1, nervurado, de fotos)",
    "receptor_inferior": "PLACEHOLDER (punho, guarda-mato e poço do carregador de fotos)",
}

L = 0.993  # da soleira à boca (ponta dos dentes do quebra-chamas)
ZS = 0.066  # linha de visada acima do eixo do cano
D_ALCA = 0.2775  # anel da alça (d da soleira)
D_MASSA = D_ALCA + 0.502  # poste da massa (raio de visada do M16A1)
HG = (0.480, 0.755)  # guarda-mão
AZ_HG = -0.004  # eixo do guarda-mão (um pouco abaixo do cano)
POCO = (0.356, 0.432)  # poço do carregador


def log(*a) -> None:
    print("[M16]", *a, flush=True)


def lados(a: float, b: float):
    """As duas peças simétricas (esquerda e direita) entre |x| = a e |x| = b."""
    return ((a, b), (-b, -a))


def m16() -> tuple[list, dict]:
    g = armas.Malha()
    # ---------------- coronha fixa A1 (plástico) com a soleira de alumínio e o zarelho de baixo
    coronha = [
        (0.008, 0.022, -0.112, 0.0205, 4.0),
        (0.030, 0.022, -0.108, 0.0210, 4.0),
        (0.120, 0.021, -0.078, 0.0200, 3.6),
        (0.200, 0.020, -0.050, 0.0185, 3.2),
        (0.240, 0.019, -0.034, 0.0175, 3.0),
        (0.258, 0.018, -0.030, 0.0165, 3.0),
    ]
    g.loft(armas.estacoes(coronha), MAT_PLASTICO)
    g.loft([(0.0, 0.023, -0.113, 0.0212, 4.0), (0.0085, 0.023, -0.113, 0.0212, 4.0)], MAT_ANOD)
    g.tubo(
        [(0, 0.060, -0.096), (0, 0.062, -0.108), (0, 0.078, -0.106), (0, 0.080, -0.092)],
        0.0018,
        MAT_ACO,
        k=8,
    )
    # ---------------- receptor inferior (alumínio): corpo, poço do carregador, pinos e comandos
    g.loft(
        [
            (0.255, 0.006, -0.026, 0.0125, 6.0),
            (0.268, 0.006, -0.032, 0.0125, 6.0),
            (0.446, 0.006, -0.032, 0.0125, 6.0),
            (0.456, 0.006, -0.012, 0.0125, 6.0),
        ],
        MAT_ANOD,
        k=24,
    )
    g.loft(
        [(POCO[0], -0.026, -0.062, 0.0148, 6.0), (POCO[1], -0.026, -0.062, 0.0148, 6.0)],
        MAT_ANOD,
        k=24,
    )
    g.cilindro_x(-0.0136, 0.0136, 0.448, -0.004, 0.0028, MAT_ACO)  # pino de articulação
    g.cilindro_x(-0.0136, 0.0136, 0.264, -0.002, 0.0028, MAT_ACO)  # pino de desmontagem
    g.caixa(0.0125, 0.0143, 0.292, 0.306, -0.013, -0.006, MAT_ACO)  # seletor (esquerda)
    g.caixa(0.0140, 0.0150, 0.285, 0.313, -0.011, -0.007, MAT_ACO)
    g.cilindro_x(-0.0152, -0.0125, 0.350, -0.018, 0.0035, MAT_ACO)  # retém do carregador
    g.caixa(0.0125, 0.0145, 0.364, 0.376, -0.022, -0.006, MAT_ACO)  # retém do ferrolho
    # punho de pistola (plástico), guarda-mato e gatilho
    # (meia largura 11,5 mm; frente-trás 1,5 vez isso, com a barriga do dedo médio)
    g.tubo(
        [
            (0, 0.303, -0.026),
            (0, 0.295, -0.052),
            (0, 0.287, -0.080),
            (0, 0.279, -0.106),
            (0, 0.275, -0.120),
        ],
        0.0115,
        MAT_PLASTICO,
        k=16,
        achatar=1.5,
    )
    g.tubo(
        [
            (0, 0.309, -0.031),
            (0, 0.310, -0.052),
            (0, 0.320, -0.059),
            (0, 0.346, -0.059),
            (0, 0.354, -0.051),
            (0, 0.356, -0.031),
        ],
        0.0045,
        MAT_ANOD,
        k=10,
        achatar=0.4,
    )
    g.tubo(
        [(0, 0.332, -0.030), (0, 0.331, -0.040), (0, 0.327, -0.050)],
        0.0030,
        MAT_ACO,
        k=10,
        achatar=0.5,
    )
    # carregador reto de 20 (alumínio) com a base
    g.caixa(-0.0118, 0.0118, POCO[0] + 0.006, POCO[1] - 0.006, -0.118, -0.030, MAT_ANOD)
    g.caixa(-0.0130, 0.0130, POCO[0] + 0.004, POCO[1] - 0.004, -0.123, -0.117, MAT_ANOD)
    # ---------------- receptor superior (alumínio): corpo, porca do cano, tampa da janela de
    # ejeção (direita), assistente do ferrolho em gota e a alavanca de manejo em T
    g.loft(
        [(0.255, 0.034, 0.004, 0.0140, 6.0), (0.470, 0.034, 0.004, 0.0140, 6.0)],
        MAT_ANOD,
        k=24,
    )
    g.torno(
        [(0.460, 0.0160), (0.474, 0.0160)], 0, 0.0, MAT_ANOD, k=24, cap0=MAT_ANOD, cap1=MAT_ANOD
    )
    g.caixa(-0.0151, -0.0139, 0.345, 0.420, 0.010, 0.027, MAT_ESCURO)  # tampa da janela
    g.caixa(-0.0157, -0.0150, 0.357, 0.409, 0.017, 0.0195, MAT_ESCURO)  # nervura da tampa
    g.torno(
        [(0.290, 0.0055), (0.322, 0.0055), (0.322, 0.0042)],
        -0.0165,
        0.022,
        MAT_ANOD,
        k=14,
        cap1=MAT_ANOD,
    )
    g.esfera(-0.0165, 0.287, 0.022, 0.0068, MAT_ANOD, seg=12, an=8)  # botão em gota
    g.caixa(-0.020, 0.020, 0.249, 0.257, 0.023, 0.032, MAT_ANOD)  # T da alavanca de manejo
    g.caixa(-0.0040, 0.0040, 0.255, 0.264, 0.023, 0.032, MAT_ANOD)
    # ---------------- alça de transporte (alumínio): base da alça de mira atrás, dois trilhos com
    # o vão no meio (a linha de visada passa por dentro) e a perna da frente
    g.caixa(-0.0115, 0.0115, 0.262, 0.300, 0.034, 0.056, MAT_ANOD)  # base da alça de mira
    # D-246 (dono: "volte a mira da m16 antiga"): desfaz a limpeza do D-236
    for x0, x1 in lados(0.0080, 0.0110):  # orelhas da alça de mira
        g.caixa(x0, x1, 0.268, 0.290, 0.056, 0.080, MAT_ANOD)
    for x0, x1 in lados(0.0045, 0.0105):  # trilhos da alça de transporte
        g.caixa(x0, x1, 0.298, 0.437, 0.052, 0.070, MAT_ANOD)
    g.caixa(-0.0105, 0.0105, 0.418, 0.437, 0.034, 0.052, MAT_ANOD)  # perna da frente
    g.cilindro_x(-0.0162, -0.0115, 0.283, 0.047, 0.0060, MAT_ANOD)  # botão de deriva (direita)
    # o anel da alça (5 mm de furo) e a haste que o prende à base
    g.torno(
        [
            (D_ALCA - 0.0015, 0.0025),
            (D_ALCA - 0.0015, 0.0056),
            (D_ALCA + 0.0015, 0.0056),
            (D_ALCA + 0.0015, 0.0025),
            (D_ALCA - 0.0015, 0.0025),
        ],
        0,
        ZS,
        MAT_ACO,
        k=24,
    )
    g.caixa(-0.0035, 0.0035, D_ALCA - 0.0015, D_ALCA + 0.0015, 0.056, ZS - 0.0050, MAT_ACO)
    # ---------------- anel delta, guarda-mão triangular nervurado (plástico) e a capa da frente
    g.torno(
        [(HG[0] - 0.014, 0.0288), (HG[0] - 0.004, 0.0288), (HG[0] + 0.001, 0.0262)],
        0,
        AZ_HG,
        MAT_ANOD,
        k=28,
        cap0=MAT_ANOD,
        cap1=MAT_ANOD,
    )

    def hg_sec(d: float, fundo: bool) -> tuple:
        t = (d - HG[0]) / (HG[1] - HG[0])
        hw = 0.0235 - 0.0040 * t
        top = 0.024 - 0.003 * t
        bot = -0.032 + 0.004 * t
        if fundo:  # vale entre duas nervuras
            hw -= 0.0013
            top -= 0.0013
            bot += 0.0010
        return (d, top, bot, hw, 2.4)

    secs = [hg_sec(HG[0], True)]
    passo = (HG[1] - HG[0] - 0.024) / 11
    for k in range(11):
        c = HG[0] + 0.012 + passo * (k + 0.5)
        for dd, fundo in ((-0.45, True), (-0.18, False), (0.18, False), (0.45, True)):
            secs.append(hg_sec(c + dd * passo, fundo))
    secs.append(hg_sec(HG[1], True))
    g.loft(secs, MAT_PLASTICO, k=28)
    g.torno(
        [(HG[1] - 0.002, 0.0205), (HG[1] + 0.008, 0.0205), (HG[1] + 0.010, 0.0140)],
        0,
        AZ_HG,
        MAT_ANOD,
        k=24,
        cap0=MAT_ANOD,
        cap1=MAT_ANOD,
    )
    # ---------------- cano (aço), base de massa em "A" com o poste e as orelhas, ressalto da
    # baioneta e o zarelho da frente
    g.torno(
        [(0.470, 0.0100), (0.766, 0.0092), (0.950, 0.0084)],
        0,
        0.0,
        MAT_ACO,
        k=24,
        cap0=MAT_ACO,
        cap1=MAT_ACO,
    )
    fm = D_MASSA
    anel = [(fm - 0.013, 0.0128), (fm + 0.016, 0.0128)]
    g.torno(anel, 0, 0.0, MAT_ACO, k=24, cap0=MAT_ACO, cap1=MAT_ACO)
    # torre do "A": larga embaixo, estreita em cima
    g.loft(
        [
            (fm - 0.018, 0.013, 0.006, 0.0062, 6.0),
            (fm - 0.006, 0.044, 0.006, 0.0062, 6.0),
            (fm + 0.007, 0.044, 0.006, 0.0062, 6.0),
            (fm + 0.016, 0.013, 0.006, 0.0062, 6.0),
        ],
        MAT_ACO,
        k=20,
    )
    for x0, x1 in lados(0.0058, 0.0084):  # orelhas da massa
        g.caixa(x0, x1, fm - 0.0065, fm + 0.0065, 0.040, 0.074, MAT_ACO)
    g.caixa(-0.0009, 0.0009, fm - 0.002, fm + 0.002, 0.044, ZS, MAT_ACO)  # poste
    g.caixa(-0.0045, 0.0045, fm + 0.004, fm + 0.033, -0.024, -0.008, MAT_ACO)  # baioneta
    g.tubo(
        [
            (0, fm - 0.006, -0.012),
            (0, fm - 0.005, -0.030),
            (0, fm + 0.011, -0.030),
            (0, fm + 0.012, -0.024),
        ],
        0.0018,
        MAT_ACO,
        k=8,
    )
    # ---------------- quebra-chamas de três dentes (o do M16 de 1965)
    corpo = [(0.940, 0.0112), (0.954, 0.0112)]
    g.torno(corpo, 0, 0.0, MAT_ACO, k=20, cap0=MAT_ACO, cap1=MAT_ESCURO)
    for ang in (90, 210, 330):
        a = math.radians(ang)
        x, z = 0.0086 * math.cos(a), 0.0086 * math.sin(a)
        g.tubo([(x, 0.953, z), (x, L, z)], 0.0024, MAT_ACO, k=8)
    obj = g.objeto("m16")
    pontos = {
        "muzzle": (0.0, L, 0.0),
        "sight": (0.0, D_ALCA, ZS),
        "front": (0.0, D_MASSA, ZS),
        # mão direita no punho de pistola; a esquerda embaixo do guarda-mão, a ~0,24 m do punho
        # (limite de 0,26 m do teste da F5, D-59)
        "grip": (0.0, 0.290, -0.068),
        "support": (0.0, 0.530, -0.034),
        "eyeM": 0.09,
        "comprimento_m": L,
    }
    return [obj], pontos


# ------------------------------------------------------------------ materiais
def plastico_m16(nome: str):
    """Plástico preto liso, levemente fosco, com o pó das dobras."""
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    n = materiais.Nos(mat)
    p = n.P()
    v = n.mapa(n.ruido(p, 0.6, 2.0), 0.3, 0.7)
    cor = n.mix(v, n.rgb(0.016, 0.016, 0.017), n.rgb(0.030, 0.030, 0.031))
    sujo = n.mapa(n.oclusao(2.5), 0.95, 0.55)
    cor = n.mix(n.mul(sujo, 0.45), cor, n.rgb(0.030, 0.027, 0.021))
    alt = n.mul(n.ruido(p, 4.0, 2.0), 0.0015)
    return mat, n.finalizar(cor, 0.58, 0.0, alt)


def anodizado(nome: str):
    """Alumínio anodizado preto-acinzentado, com o brilho baixo do metal e o pó das dobras."""
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    n = materiais.Nos(mat)
    p = n.P()
    v = n.mapa(n.ruido(p, 0.9, 2.0), 0.3, 0.7)
    cor = n.mix(v, n.rgb(0.022, 0.023, 0.025), n.rgb(0.040, 0.041, 0.044))
    sujo = n.mapa(n.oclusao(2.5), 0.95, 0.55)
    cor = n.mix(n.mul(sujo, 0.4), cor, n.rgb(0.028, 0.026, 0.022))
    alt = n.mul(n.ruido(p, 3.0, 2.0), 0.001)
    return mat, n.finalizar(cor, 0.46, 0.35, alt)


def materiais_m16() -> dict:
    return {
        "plastico": plastico_m16("plastico_m16"),
        "anodizado": anodizado("anodizado_m16"),
        "aco": materiais.criar("aco"),
        "escuro": espingarda.escuro("escuro_m16"),
    }


ORDEM = ("plastico", "anodizado", "aco", "escuro")


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
    objs, pontos = m16()
    mats = materiais_m16()
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
        "nome": "M16 (XM16E1/M16A1, 1965–67): guarda-mão triangular, alça de transporte, "
        "quebra-chamas de três dentes, carregador de 20",
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
        objs, _ = m16()
        mats = materiais_m16()
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
