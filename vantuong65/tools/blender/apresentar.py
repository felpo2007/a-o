"""Etapa C2: render de apresentação dos assets das bases (`comparacao.png`, 2 ângulos).

Mesma luz, câmera e face única do `comparar.py` (céu do jogo + sol de 45°, Cycles). Não há versão
antiga para comparar, então as colunas são:
- esquerda: o asset como sai do GLB (só os nós visuais);
- direita: os sólidos de colisão (`Colisao_*`, vermelho translúcido) e as zonas de toque
  (`Zona_*`, amarelo), com a casca (lona, telhado) escondida para ver o interior.
Linha = ângulo (frente-esquerda e trás-direita). Nós no mesmo lugar (placas de distância) são
espalhados em X só para a imagem.

Uso:
    blender -b --factory-startup -P tools/blender/apresentar.py -- <chave> [--amostras N]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bases_comum as B  # noqa: E402
import comparar as K  # noqa: E402
import comum as C  # noqa: E402


def importar_nos(caminho: Path) -> dict[str, bpy.types.Object]:
    """Importa o GLB e devolve {nome do nó: objeto} em metros, transformações aplicadas."""
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(caminho))
    novos = [o for o in bpy.data.objects if o not in antes]
    saida = {}
    for o in novos:
        if o.type != "MESH":
            continue
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy() if o.data.users > 1 else o.data
        o.data.transform(Matrix.Scale(C.M_POR_STUD, 4) @ mw)
        o.matrix_world = Matrix.Identity(4)
        saida[o.name.split(".")[0]] = o
    for o in novos:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    return saida


def material_vista(nome: str, cor, alfa: float) -> bpy.types.Material:
    m = C.novo_material(nome)
    pr = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    pr.inputs["Base Color"].default_value = (*cor, 1.0)
    pr.inputs["Alpha"].default_value = alfa
    pr.inputs["Emission Color"].default_value = (*cor, 1.0)
    pr.inputs["Emission Strength"].default_value = 0.35
    pr.inputs["Roughness"].default_value = 0.6
    return m


def chao_leve() -> bpy.types.Material:
    """Terra arenosa com manchas e grão (2 ruídos, sem relevo)."""
    m = B.Mat("chao_apresentacao", rug=0.97)
    p = m.coord("objeto")
    cor = m.rampa(
        m.ruido(p, 0.9, 3, 0.55),
        [(0.3, B.rgb("#6b5a42")), (0.55, B.rgb("#8d7a5b")), (0.75, B.rgb("#a08d6c"))],
    )
    grao = m.ruido(p, 28.0, 2)
    cor = m.misturar(m.faixa(grao, 0.35, 0.7, 0.0, 0.35), cor, B.rgb("#5a4b37"))
    m.cor(cor)
    return m.m


def fmt(n: float, casas: int = 0) -> str:
    s = f"{n:,.{casas}f}"
    return s.replace(",", "X").replace(".", ",").replace("X", ".")


def main() -> None:
    a = C.argumentos()
    chave = a[0]
    amostras = int(a[a.index("--amostras") + 1]) if "--amostras" in a else 64
    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    trab.mkdir(parents=True, exist_ok=True)
    met = json.loads((pasta / "metricas.json").read_text("utf-8"))
    cena = C.cena_vazia()
    K.configurar(cena, amostras)
    if "--cpu" in a:
        # sem GPU (o dono joga no mesmo PC): Cycles na CPU com 4 threads
        cena.cycles.device = "CPU"
        cena.cycles.denoiser = "OPENIMAGEDENOISE"
        cena.render.threads_mode = "FIXED"
        cena.render.threads = 4
    elif "--cpu-todos" in a:
        # CPU com todas as threads (o driver NVIDIA 556.29 não deixa o Blender 5.3 usar a placa)
        cena.cycles.device = "CPU"
        cena.cycles.denoiser = "OPENIMAGEDENOISE"
    else:
        C.log("dispositivo do render:", B.usar_cuda(cena))
        cena.cycles.denoiser = "OPENIMAGEDENOISE"  # o denoiser OptiX falha com o driver atual
    piso = C.chao(tamanho=400.0, z=0.0)
    # chão com textura de terra (o chão liso marrom do comparar parecia "terra sem textura"), leve:
    # o mat_terra completo (Voronoi e 3 relevos) deixava cada quadro 8x mais lento
    piso.data.materials.append(chao_leve())
    nos = importar_nos(C.RAIZ / met["novo"]["arquivo"])
    visuais = {n: o for n, o in nos.items() if not n.startswith(("Colisao", "Zona"))}
    colisao = {n: o for n, o in nos.items() if n.startswith(("Colisao", "Zona"))}
    if met.get("extras", {}).get("mesmo_lugar"):
        for i, o in enumerate(visuais.values()):
            o.data.transform(Matrix.Translation((i * 0.9, 0, 0)))
    for o in visuais.values():
        K.face_unica(o)
    m_col = material_vista("colisao_vista", (0.9, 0.06, 0.04), 0.38)
    m_zona = material_vista("zona_vista", (0.95, 0.75, 0.05), 0.38)
    for n, o in colisao.items():
        o.data.materials.clear()
        o.data.materials.append(m_zona if n.startswith("Zona") else m_col)
        o.visible_shadow = False
    casca = [visuais[n] for n in met.get("casca", []) if n in visuais]
    pts = K.pontos(list(visuais.values()), 8000)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    diag = float(np.linalg.norm(hi - lo))
    K.ELEVACAO = 30.0 if (hi[2] - lo[2]) < 0.25 * diag else 22.0
    nv = met["novo"]
    tex = " + ".join(f"{t}" for t in nv.get("texturas_lista", [])) + " px"
    rot_esq = f"NOVO (Blender) — {fmt(nv['triangulos'])} tri · {tex} · {fmt(nv['mb'], 2)} MB"
    n_col = sum(1 for n in colisao if n.startswith("Colisao"))
    n_zona = len(colisao) - n_col
    rot_dir = f"COLISÃO: {n_col} sólido{'s' if n_col != 1 else ''}"
    if n_zona:
        rot_dir += f" + {n_zona} zona de toque (amarelo)"
    if casca:
        rot_dir += f" · sem {', '.join(met['casca']).lower()} (interior)"
    paineis = []
    for k, az in enumerate(K.AZIMUTES):
        cam, dist = K.camera(lo, hi, az, pts)
        s = K.sol(az + 70.0)
        d_txt = min(dist * 0.4, 1.0)
        tam = d_txt * 0.024
        x_txt = -d_txt * 36 / K.LENTE_MM / 2 + tam * 0.6
        y_txt = d_txt * 36 * K.ALT / K.LARG / K.LENTE_MM / 2 - tam * 1.6
        linha = []
        for j, rotulo in enumerate((rot_esq, rot_dir)):
            for o in colisao.values():
                o.hide_render = j == 0
            for o in casca:
                o.hide_render = j == 1
            txt = K.texto(cam, rotulo, x_txt, y_txt, d_txt, tam)
            linha.append(K.renderizar(trab / f"apresenta_{k}_{j}.png"))
            for o in txt:
                bpy.data.objects.remove(o)
        bpy.data.objects.remove(cam)
        bpy.data.objects.remove(s)
        paineis.append(linha)
    sep = 6
    h, w = K.ALT, K.LARG
    total = np.ones((2 * h + sep, 2 * w + sep, 4), np.float32)
    total[..., :3] = 0.08
    for i, linha in enumerate(paineis):
        for j, p in enumerate(linha):
            y0 = (1 - i) * (h + sep)
            x0 = j * (w + sep)
            total[y0 : y0 + h, x0 : x0 + w] = p
    out = bpy.data.images.new("comparacao", total.shape[1], total.shape[0], alpha=False)
    C.gravar_pixels(out, total)
    C.salvar_imagem(out, pasta / "comparacao.png", "PNG")
    C.gravar_json(
        pasta / "metricas.json",
        {
            "comparacao": {
                "imagem": f"assets/blender/{chave}/comparacao.png",
                "colunas": ["asset (nós visuais)", "colisão e zonas, sem a casca"],
                "angulos_azimute_graus": list(K.AZIMUTES),
                "elevacao_graus": K.ELEVACAO,
                "amostras_cycles": amostras,
            }
        },
    )
    del piso
    C.log("ok", chave, "apresentação")


if __name__ == "__main__":
    main()
