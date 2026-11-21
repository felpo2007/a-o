"""SKS do VẠN TƯỜNG '65 (lote 31, D-146; pedido do dono: "a mira da arma SKS está ruim").

A SKS do gerador (ForgeGUI) era uma malha só: mirando, a linha de visada batia na tampa e na
alavanca do ferrolho, e nem o entalhe nem a massa apareciam limpos. Esta é a carabina Tipo 56
chinesa (a SKS do VC: coronha de madeira avermelhada, baioneta de espigão dobrada embaixo do cano,
carregador fixo de 10), feita no Blender como o M16 (tools/blender/m16.py) e as outras armas do
Blender (tools/blender/armas.py), com a mira desenhada para ser vista: o entalhe em U no fim da
folha da alça tangente, à frente da caixa da culatra, e a massa (poste) dentro do capuz redondo.

Convenções (as de armas.py): metros, eixo do cano no eixo Y do Blender com a boca em -Y, Z para
cima, direita do atirador em -X (+X no Roblox). Um nó só, "Arma". `pontos.json` em studs no
referencial local da MeshPart; o tools/weapon_landmarks.py lê este arquivo (a mira é a da
construção: o fundo do entalhe e a ponta do poste).

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/sks.py -- sks
    ... -- sks --montar   (só a forma, com os materiais procedurais, sem o bake)
    ... -- sks --previa   (prévia do GLB exportado: assets/blender/arma_sks/_previa.png)

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
import espingarda  # noqa: E402  (prévia do GLB)
import materiais  # noqa: E402
import produzir as faca  # noqa: E402

M_POR_STUD = 0.28
CHAVE = "sks"
PASTA = "arma_sks"
MAT_MADEIRA, MAT_ACO, MAT_ESCURO = 0, 1, 2

FONTES = {
    "comprimento_total_m": "1.020 (wiki:SKS, com a baioneta dobrada)",
    "comprimento_cano_m": "0.520 (wiki:SKS)",
    "carregador": "10 tiros, fixo, carregado por clipe (wiki:SKS)",
    "raio_de_visada_m": "PLACEHOLDER (~0,475 m, de fotos)",
    "linha_de_visada_m": "PLACEHOLDER (0,034 m acima do eixo do cano, de fotos)",
    "baioneta": "Tipo 56 chinesa: espigão dobrado embaixo do cano (wiki:SKS, variantes chinesas)",
    "coronha": "PLACEHOLDER (perfil desenhado de fotos da Tipo 56)",
}

L = 1.020  # da soleira à boca
# linha de visada acima do eixo do cano: tudo entre a alça e a massa (telha de cima, tubo de gases,
# braçadeira) fica abaixo dela, e a tampa da culatra 15 mm abaixo (no Studio a 0,028 a telha subia
# até a linha e a tampa enchia a metade de baixo da mira)
ZS = 0.034
D_ALCA = 0.526  # fundo do entalhe (fim de trás da folha da alça)
D_MASSA = 0.990  # poste da massa, dentro do capuz
# meia largura do entalhe (4,4 mm, mais largo que o real: no Studio o de 2,6 mm saía com ~6 px) e
# do poste (2,4 mm)
ENTALHE_MEIA = 0.0022
POSTE_MEIA = 0.0012


def log(*a) -> None:
    print("[SKS]", *a, flush=True)


def lados(a: float, b: float):
    """As duas peças simétricas (esquerda e direita) entre |x| = a e |x| = b."""
    return ((a, b), (-b, -a))


def sks() -> tuple[list, dict]:
    g = armas.Malha()
    # ---------------- coronha inteiriça de madeira: soleira, pescoço com meia empunhadura de
    # pistola, leito da caixa da culatra e a telha de baixo até a braçadeira
    coronha = [
        (0.006, -0.030, -0.148, 0.0205, 3.4),
        (0.120, -0.022, -0.118, 0.0195, 3.0),
        (0.215, -0.013, -0.080, 0.0170, 2.8),
        (0.250, -0.010, -0.074, 0.0155, 2.6),
        (0.285, -0.007, -0.078, 0.0155, 2.6),
        (0.312, -0.004, -0.062, 0.0160, 2.6),
        (0.330, -0.001, -0.036, 0.0175, 3.0),
        (0.530, -0.001, -0.034, 0.0175, 3.0),
        (0.560, -0.003, -0.030, 0.0160, 3.0),
        (0.775, -0.005, -0.025, 0.0140, 3.0),
    ]
    g.loft(armas.estacoes(coronha), MAT_MADEIRA)
    g.loft([(0.0, -0.031, -0.149, 0.0210, 3.4), (0.006, -0.031, -0.149, 0.0210, 3.4)], MAT_ACO)
    # ---------------- caixa da culatra (aço) com a tampa redonda, o ferrolho e a alavanca à direita
    g.loft(
        [(0.322, 0.014, -0.022, 0.0128, 5.0), (0.528, 0.014, -0.022, 0.0128, 5.0)],
        MAT_ACO,
        k=24,
    )
    g.loft(
        [
            (0.330, 0.004, 0.004, 0.0122, 2.4),
            (0.336, 0.019, 0.004, 0.0122, 2.4),
            (0.512, 0.019, 0.004, 0.0122, 2.4),
            (0.516, 0.004, 0.004, 0.0122, 2.4),
        ],
        MAT_ACO,
        k=24,
    )
    g.caixa(-0.0133, -0.0127, 0.430, 0.508, 0.000, 0.013, MAT_ESCURO)  # janela de ejeção
    g.cilindro_x(-0.034, -0.012, 0.452, 0.006, 0.0042, MAT_ACO)  # alavanca do ferrolho
    g.esfera(-0.036, 0.452, 0.006, 0.0062, MAT_ACO, seg=12, an=8)
    g.cilindro_x(-0.016, -0.012, 0.524, 0.010, 0.0035, MAT_ACO)  # alavanca de desmontagem
    # guarda-mato (aço) com a trava, gatilho e o carregador fixo
    g.tubo(
        [
            (0, 0.336, -0.030),
            (0, 0.337, -0.050),
            (0, 0.347, -0.058),
            (0, 0.392, -0.058),
            (0, 0.400, -0.048),
            (0, 0.401, -0.030),
        ],
        0.0050,
        MAT_ACO,
        k=10,
        achatar=0.4,
    )
    g.tubo(
        [(0, 0.368, -0.026), (0, 0.366, -0.038), (0, 0.361, -0.048)],
        0.0030,
        MAT_ACO,
        k=10,
        achatar=0.5,
    )
    g.loft(
        [
            (0.404, -0.026, -0.060, 0.0120, 5.0),
            (0.412, -0.026, -0.072, 0.0120, 5.0),
            (0.468, -0.026, -0.074, 0.0120, 5.0),
            (0.482, -0.026, -0.064, 0.0120, 5.0),
        ],
        MAT_ACO,
        k=24,
    )
    # ---------------- cano (aço), alça tangente à frente da caixa da culatra, tubo de gases com a
    # telha de cima (madeira), braçadeira, bloco de gases e a massa com capuz na boca
    g.torno(
        [(0.520, 0.0118), (0.600, 0.0108), (0.800, 0.0098), (L, 0.0086)],
        0,
        0.0,
        MAT_ACO,
        k=24,
        cap0=MAT_ACO,
        cap1=MAT_ESCURO,
    )
    g.caixa(-0.0115, 0.0115, D_ALCA - 0.004, 0.578, 0.004, 0.021, MAT_ACO)  # base da alça
    g.caixa(-0.0090, 0.0090, D_ALCA, 0.572, 0.021, 0.026, MAT_ACO)  # folha
    g.caixa(-0.0105, 0.0105, 0.541, 0.553, 0.020, 0.028, MAT_ACO)  # cursor da folha
    for x0, x1 in lados(ENTALHE_MEIA, 0.0090):  # orelhas do entalhe
        g.caixa(x0, x1, D_ALCA, D_ALCA + 0.004, 0.021, ZS + 0.0045, MAT_ACO)
    g.caixa(-ENTALHE_MEIA, ENTALHE_MEIA, D_ALCA, D_ALCA + 0.004, 0.021, ZS, MAT_ACO)
    g.torno(
        [(0.575, 0.0070), (0.842, 0.0070)], 0, 0.018, MAT_ACO, k=16, cap0=MAT_ACO, cap1=MAT_ACO
    )
    g.loft(
        [
            (0.582, 0.025, 0.010, 0.0122, 2.6),
            (0.600, 0.027, 0.010, 0.0124, 2.6),
            (0.760, 0.026, 0.010, 0.0118, 2.6),
            (0.772, 0.024, 0.010, 0.0114, 2.6),
        ],
        MAT_MADEIRA,
        k=24,
    )
    g.loft(
        [(0.772, 0.030, -0.028, 0.0150, 3.0), (0.786, 0.030, -0.028, 0.0150, 3.0)],
        MAT_ACO,
        k=24,
    )
    g.loft(
        [(0.826, 0.027, -0.012, 0.0105, 3.0), (0.858, 0.027, -0.012, 0.0105, 3.0)],
        MAT_ACO,
        k=20,
    )
    g.torno([(D_MASSA - 0.016, 0.0118), (D_MASSA + 0.012, 0.0118)], 0, 0.0, MAT_ACO, k=20)
    g.caixa(-0.0050, 0.0050, D_MASSA - 0.012, D_MASSA + 0.008, 0.008, 0.020, MAT_ACO)
    # capuz redondo em volta do poste (o olho vê o poste no meio de um anel)
    zc = ZS - 0.004
    g.torno(
        [
            (D_MASSA - 0.009, 0.0098),
            (D_MASSA - 0.009, 0.0118),
            (D_MASSA + 0.008, 0.0118),
            (D_MASSA + 0.008, 0.0098),
            (D_MASSA - 0.009, 0.0098),
        ],
        0,
        zc,
        MAT_ACO,
        k=24,
    )
    g.caixa(-POSTE_MEIA, POSTE_MEIA, D_MASSA - 0.002, D_MASSA + 0.002, 0.018, ZS, MAT_ACO)  # poste
    # ---------------- baioneta de espigão dobrada embaixo do cano (dobradiça perto da boca)
    g.caixa(-0.0060, 0.0060, 0.940, 0.962, -0.024, -0.008, MAT_ACO)
    g.torno(
        [(0.660, 0.0006), (0.700, 0.0034), (0.950, 0.0040)],
        0,
        -0.030,
        MAT_ACO,
        k=12,
        cap1=MAT_ACO,
    )
    obj = g.objeto("sks")
    pontos = {
        "muzzle": (0.0, L, 0.0),
        "sight": (0.0, D_ALCA, ZS),
        "front": (0.0, D_MASSA, ZS),
        # mão direita no pescoço da coronha; a esquerda logo à frente do carregador, a ~0,25 m do
        # punho (limite de 0,26 m do teste da F5, D-59)
        "grip": (0.0, 0.300, -0.050),
        "support": (0.0, 0.548, -0.034),
        "eyeM": 0.26,
        "comprimento_m": L,
    }
    return [obj], pontos


# ------------------------------------------------------------------ materiais
def oxidado(nome: str):
    """Aço oxidado preto (azulado gasto), com brilho baixo e o pó das dobras. Metal 0,3 e
    rugosidade 0,5: com 0,6/0,42 o Roblox refletia o céu e a culatra saía cinza-clara na mira."""
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    n = materiais.Nos(mat)
    p = n.P()
    v = n.mapa(n.ruido(p, 0.8, 2.0), 0.3, 0.7)
    cor = n.mix(v, n.rgb(0.018, 0.019, 0.021), n.rgb(0.036, 0.036, 0.039))
    sujo = n.mapa(n.oclusao(2.5), 0.95, 0.55)
    cor = n.mix(n.mul(sujo, 0.4), cor, n.rgb(0.028, 0.024, 0.019))
    alt = n.mul(n.ruido(p, 3.0, 2.0), 0.001)
    return mat, n.finalizar(cor, 0.5, 0.3, alt)


def materiais_sks() -> dict:
    return {
        # madeira avermelhada das Tipo 56 chinesas
        "madeira": armas.madeira("madeira_sks", (0.075, 0.026, 0.010), (0.21, 0.085, 0.035), 0.25),
        "aco": oxidado("aco_sks"),
        "escuro": espingarda.escuro("escuro_sks"),
    }


ORDEM = ("madeira", "aco", "escuro")


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
    objs, pontos = sks()
    mats = materiais_sks()
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
        "nome": "SKS (carabina Tipo 56 chinesa): coronha de madeira, baioneta de espigão dobrada, "
        "carregador fixo de 10",
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
        objs, _ = sks()
        mats = materiais_sks()
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
