"""Etapa A1 (Tarefa A): refaz no Blender um asset antigo do ForgeGUI e assa o original no novo.

Para a chave pedida:
1. importa o original (`assets/forgegui/models/<arquivo>.glb`, com a textura ORM do gerador) e
   passa para metros;
2. limpeza (`comum.limpar`): vértices duplicados e soltos, faces degeneradas, duplicadas,
   internas e escondidas (que não enxergam o lado de fora). A fonte do bake perde as normais de
   canto do gerador (suavizadas por cima de quinas de 90°) e passa a sombrear pelo ângulo;
3. retopologia por redução (dissolução planar + colapso). O alvo é o MENOR da lista de tentativas
   (40, 55, 75 ou 100% do teto da classe) cujo desvio fica na tolerância (`comum.TOLERANCIA`:
   média ≤ 0,05%, p95 ≤ 0,15% e p99 ≤ 0,3% da diagonal da caixa). Sem nenhuma, fica o teto;
4. UV nova (projeção inteligente + empacotamento côncavo), com menos texels para o que quase não
   aparece (frestas, contatos, pé no chão);
5. bake do original para o novo (Cycles, GPU), numa cópia separada nas costuras da UV, com raios
   saindo de uma gaiola por vértice e sem as faces de costas (`comum.produzir`): cor,
   normal (tangente, OpenGL), oclusão ambiente (com o chão) e rugosidade. A rugosidade vem do
   canal G da ORM do gerador, remapeada para a faixa do material do asset (palha, terra,
   madeira, barro, lona) e um pouco mais alta nas frestas; o metal fica 0 (canal B = 0,
   metallicFactor 0);
6. a oclusão escurece a cor (o Roblox não tem canal de oclusão) e o GLB sai em studs, Y para cima
   (`assets/blender/<chave>/<chave>.glb`), com as métricas em `metricas.json`.

Uso:
    blender -b --factory-startup -P tools/blender/refazer.py -- <chave> [--alvo N]
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import glb  # noqa: E402

# chave do jogo -> arquivo do original (sem .glb), classe (meta de triângulos) e faixa de
# rugosidade dos materiais que dominam o asset
ANTIGOS: dict[str, dict] = {
    "hut_thatch": {"arquivo": "casa_palha_studs", "classe": "construcao", "rug": (0.72, 0.97)},
    "hut_veranda": {"arquivo": "casa_varanda_studs", "classe": "construcao", "rug": (0.70, 0.97)},
    "hut_kitchen": {"arquivo": "cozinha_studs", "classe": "construcao", "rug": (0.72, 0.97)},
    # alvenaria de quinas vivas: sombreamento do novo com aresta viva a partir de 30°
    "house_tile": {
        "arquivo": "casa_telha_studs",
        "classe": "construcao",
        "rug": (0.60, 0.92),
        "suave": 30.0,
    },
    "granary": {"arquivo": "celeiro_studs", "classe": "construcao", "rug": (0.70, 0.97)},
    "well": {"arquivo": "poco_studs", "classe": "prop", "rug": (0.62, 0.92)},
    "shrine": {"arquivo": "altar_studs", "classe": "prop", "rug": (0.55, 0.90)},
    "grave_mound": {"arquivo": "tumulo_studs", "classe": "prop", "rug": (0.85, 1.00)},
    "vc_bunker": {"arquivo": "bunker_vc_studs", "classe": "construcao", "rug": (0.80, 1.00)},
    "sandbags": {"arquivo": "sacos_areia_studs", "classe": "prop", "rug": (0.82, 0.98)},
    "bamboo_fence": {"arquivo": "cerca_bambu_studs", "classe": "prop", "rug": (0.45, 0.80)},
    "trench_section": {
        "arquivo": "trincheira_secao_studs",
        "classe": "construcao",
        "rug": (0.80, 1.00),
    },
    "tunnel_entrance": {"arquivo": "entrada_tunel_studs", "classe": "prop", "rug": (0.80, 1.00)},
    "spider_hole": {"arquivo": "toca_aranha_studs", "classe": "prop", "rug": (0.80, 1.00)},
    "log_bridge": {"arquivo": "ponte_troncos_studs", "classe": "construcao", "rug": (0.62, 0.92)},
    # folha densa: com a oclusão a 0,5 e rugosidade de 0,4 o arroz saía quase preto e brilhando
    "rice_patch": {
        "arquivo": "arroz_canteiro_studs",
        "classe": "prop",
        "rug": (0.55, 0.92),
        "forca_ao": 0.25,
    },
}

FORCA_AO = 0.5  # quanto a oclusão escurece a cor (0 = nada, 1 = tudo); por asset: "forca_ao"
FRESTA_RUG = 0.08  # rugosidade a mais onde a oclusão é total


def imagem_ligada(sock) -> bpy.types.Image | None:
    """Primeira imagem rio acima de uma entrada de nó."""
    pilha = [sock]
    while pilha:
        s = pilha.pop()
        for lk in s.links:
            n = lk.from_node
            if n.type == "TEX_IMAGE" and n.image:
                return n.image
            pilha.extend(i for i in n.inputs if i.is_linked)
    return None


def material_alto(obj: bpy.types.Object, rug: tuple[float, float]) -> dict:
    """Refaz o material do original para o bake: cor, normal e rugosidade (G da ORM remapeado
    para a faixa do material); metal 0."""
    mat0 = obj.active_material
    pr0 = next(n for n in mat0.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    cor = imagem_ligada(pr0.inputs["Base Color"])
    orm = imagem_ligada(pr0.inputs["Roughness"])
    nrm = imagem_ligada(pr0.inputs["Normal"])
    mat = C.novo_material("alto")
    nt = mat.node_tree
    pr = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    pr.inputs["Metallic"].default_value = 0.0
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = cor
    nt.links.new(tc.outputs["Color"], pr.inputs["Base Color"])
    if orm is not None:
        to = nt.nodes.new("ShaderNodeTexImage")
        to.image = orm
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.clamp = True
        mr.inputs["From Min"].default_value = 0.3
        mr.inputs["From Max"].default_value = 0.95
        mr.inputs["To Min"].default_value = rug[0]
        mr.inputs["To Max"].default_value = rug[1]
        nt.links.new(to.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], pr.inputs["Roughness"])
    else:
        pr.inputs["Roughness"].default_value = sum(rug) / 2
    if nrm is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = nrm
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], pr.inputs["Normal"])
    obj.data.materials.clear()
    obj.data.materials.append(mat)

    def px(i):
        return list(i.size) if i else None

    return {"cor": px(cor), "orm": px(orm), "normal": px(nrm)}


def main() -> None:
    a = C.argumentos()
    chave = a[0]
    forcado = int(a[a.index("--alvo") + 1]) if "--alvo" in a else None
    cfg = ANTIGOS[chave]
    classe = C.CLASSES[cfg["classe"]]
    tex = classe["tex"]
    t0 = time.time()
    cena = C.cena_vazia()
    C.preparar_bake(cena)
    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    pasta.mkdir(parents=True, exist_ok=True)

    fonte = C.MODELOS / f"{cfg['arquivo']}.glb"
    fosco = C.MODELOS / f"{cfg['arquivo']}_fosco.glb"
    alto = C.importar_glb(fonte)
    alto.name = "alto"
    tris_orig = C.triangulos(alto)
    medidas_antigas = C.medidas(alto)
    medidas_antigas["uso_uv"] = C.uso_uv(alto)
    tex_orig = material_alto(alto, cfg["rug"])
    # o alto (fonte do bake) fica com tudo; a base do novo perde também as faces escondidas.
    # Sem elas no alto, os raios do bake atravessavam as frestas e a cor saía preta.
    C.limpar(alto, escondidas=False)
    # As normais de canto do gerador são suavizadas por cima de quinas de 90°: na parede da casa
    # de telha elas tombam até 80° (para o chão embaixo, para o céu em cima). O bake de oclusão
    # usa essa normal e a parede saía preta. A fonte do bake passa a sombrear pelo ângulo das
    # faces (aresta viva acima de 30°); a textura normal do gerador continua por cima (detalhe).
    C.tirar_normais_custom(alto)
    C.suavizar(alto, 30.0)
    base = C.copiar(alto, "base")
    limpeza = C.limpar(base, escondidas=True)
    C.log("limpeza", limpeza)
    diag = C.diagonal(base)

    baixo, tentativas = C.escolher_alvo(base, classe["teto"], forcado)
    C.suavizar(baixo, cfg.get("suave", 66.0))
    n_ilhas = C.desdobrar(baixo, margem=4 / tex)
    d = C.desvio(baixo, base, n=20000)
    C.log("desvio final", d)
    bpy.data.objects.remove(base)

    # ------------------------------------------------------------------ bake e GLB
    saida = pasta / f"{chave}.glb"
    res = C.produzir(
        cena, baixo, [alto], tex, trab, saida, chave, cfg.get("forca_ao", FORCA_AO), FRESTA_RUG
    )
    exp = res["exportacao"]
    novo_medidas = C.medidas(baixo)
    metricas = pasta / "metricas.json"
    if metricas.is_file():
        metricas.unlink()  # métricas velhas (outra versão do pipeline) não se misturam
    C.gravar_json(
        metricas,
        {
            "chave": chave,
            "tipo": "refeito",
            "classe": cfg["classe"],
            "meta_triangulos": classe["teto"],
            "antigo": {
                "arquivo_jogo": f"assets/forgegui/models/{fosco.name}",
                "arquivo_original": f"assets/forgegui/models/{fonte.name}",
                "triangulos": tris_orig,
                "triangulos_glb": glb.triangulos(fosco),
                "texturas_px": {k: v for k, v in tex_orig.items() if v},
                "texturas_no_roblox_px": 1024,
                "mb": round(fosco.stat().st_size / 2**20, 3),
                **medidas_antigas,
            },
            "novo": {
                "arquivo": f"assets/blender/{chave}/{saida.name}",
                "triangulos": exp["triangulos"],
                "triangulos_glb": glb.triangulos(saida),
                "texturas_px": res["texturas_px"],
                "mb": exp["mb"],
                "uso_uv": C.uso_uv(baixo),
                "ilhas_uv": n_ilhas,
                **novo_medidas,
            },
            "desvio_m": d,
            "diagonal_m": round(diag, 3),
            "limpeza": limpeza,
            "tolerancia_fracao_diagonal": C.TOLERANCIA,
            "tentativas": tentativas,
            "bake": {**res["bake"], "rugosidade_faixa": list(cfg["rug"])},
            "tempo_total_s": round(time.time() - t0, 1),
        },
    )
    C.log("ok", chave, exp, "em", round(time.time() - t0, 1), "s")


if __name__ == "__main__":
    main()
