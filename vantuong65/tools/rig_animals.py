"""Divide o búfalo e a galinha em partes para animar o andar no cliente (D-77).

O modelo do ForgeGUI é uma malha só: o AnimalService só podia deslizar o bicho inteiro pelo chão.
Aqui cada triângulo vai para uma parte pelo centro dele, em studs, no espaço do GLB preparado:
- búfalo (olha para +X): 4 pernas (abaixo de ~40% da altura, divididas em frente/trás e
  esquerda/direita pelo centro das pernas), cabeça e pescoço (frente, acima das pernas) e corpo;
- galinha (olha para +Z): 2 pernas (abaixo de ~28% da altura), cabeça (frente e alto) e corpo.
A textura de cor (e a normal, se houver) é a mesma do modelo fosco já publicado; cada parte vira
um nó (Corpo, Cabeca, PernaFE, PernaFD, PernaTE, PernaTD), que o importador transforma em uma
MeshPart cada. O cliente (AnimalVisuals) gira pernas e cabeça em volta das juntas.

Saída: assets/animais/<chave>_rig.glb e uma prévia de lado e de cima (cores por parte), fora do Git.
Uso: uv run --group arte python tools/rig_animals.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from decimate_glb import accessor, read_glb  # noqa: E402
from prep_trees import Glb, node_matrix, normais  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
MODELOS = RAIZ / "assets" / "forgegui" / "models"
SAIDA = RAIZ / "assets" / "animais"

# frente: eixo (0 = X, 2 = Z) e sinal; pernas abaixo de `perna` da altura; cabeça na frente
# (`cabeca_frente` do comprimento) e acima de `cabeca_alto` da altura
ESPECIES = {
    "water_buffalo": {
        "arquivo": "bufalo_studs_fosco.glb",
        "frente": (0, 1),
        "perna": 0.40,
        "cabeca_frente": 0.26,
        "cabeca_alto": 0.22,
        "pernas": 4,
    },
    "chicken": {
        "arquivo": "galinha_studs_fosco.glb",
        "frente": (2, 1),
        "perna": 0.30,
        "cabeca_frente": 0.30,
        "cabeca_alto": 0.55,
        "pernas": 2,
    },
}
CORES = {
    "Corpo": (170, 160, 150),
    "Cabeca": (220, 80, 60),
    "PernaFE": (60, 140, 220),
    "PernaFD": (40, 200, 120),
    "PernaTE": (230, 200, 40),
    "PernaTD": (180, 60, 200),
}


def carregar(path: Path):
    js, blob = read_glb(path)
    # matriz do nó que tem a malha (escala e pivô do GLB preparado), aplicada nas posições
    m = np.eye(4)
    for n in js["nodes"]:
        if "mesh" in n:
            m = node_matrix(n)
        elif "matrix" in n or "scale" in n or "translation" in n:
            m = node_matrix(n) @ m
    pr = js["meshes"][0]["primitives"][0]
    pos = accessor(js, blob, pr["attributes"]["POSITION"]).astype(np.float64)
    pos = pos @ m[:3, :3].T + m[:3, 3]
    uv = accessor(js, blob, pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
    idx = accessor(js, blob, pr["indices"]).astype(np.int64).reshape(-1, 3)
    mat = js["materials"][pr["material"]]

    def imagem(chave: str) -> tuple[bytes, str] | None:
        t = (
            mat.get(chave)
            if chave == "normalTexture"
            else mat.get("pbrMetallicRoughness", {}).get(chave)
        )
        if not t:
            return None
        src = js["textures"][t["index"]]["source"]
        img = js["images"][src]
        bv = js["bufferViews"][img["bufferView"]]
        s = bv.get("byteOffset", 0)
        return blob[s : s + bv["byteLength"]], img.get("mimeType", "image/png")

    return pos, uv, idx, imagem("baseColorTexture"), imagem("normalTexture")


def dividir(pos, idx, cfg) -> np.ndarray:
    """Nome da parte de cada triângulo."""
    eixo, sinal = cfg["frente"]
    lado = 2 if eixo == 0 else 0
    c = pos[idx].mean(axis=1)
    lo, hi = pos.min(axis=0), pos.max(axis=0)
    h = hi[1] - lo[1]
    comp = hi[eixo] - lo[eixo]
    frente = c[:, eixo] * sinal
    fmax = hi[eixo] if sinal > 0 else -lo[eixo]
    cabeca = (frente > fmax - cfg["cabeca_frente"] * comp) & (
        c[:, 1] > lo[1] + cfg["cabeca_alto"] * h
    )
    nome = np.full(len(idx), "Corpo", dtype=object)
    nome[cabeca] = "Cabeca"
    # Pernas pelas canelas: os vértices do 15% de baixo dizem onde cada perna está no
    # comprimento. Pela mediana de toda a faixa baixa, o tufo do rabo (muito denso) puxava o corte
    # e a barriga entrava junto (prévia de 2026-11-11).
    vfrente = pos[:, eixo] * sinal
    baixo = pos[:, 1] < lo[1] + 0.15 * h
    fb = vfrente[baixo]
    meio = (fb.min() + fb.max()) / 2
    grupos = [("F", fb[fb > meio]), ("T", fb[fb <= meio])] if cfg["pernas"] == 4 else [("F", fb)]
    zona = c[:, 1] < lo[1] + cfg["perna"] * h
    for letra, g in grupos:
        a, b = g.min() - 0.35, g.max() + 0.35  # studs: a perna engrossa para cima
        sel = zona & (frente >= a) & (frente <= b) & ~cabeca
        if not sel.any():
            continue
        meio_l = np.median(c[sel, lado])
        for i in np.nonzero(sel)[0]:
            # esquerda do animal olhando para a frente: +Z quando a frente é +X; +X quando é +Z
            if eixo == 0:
                esq = c[i, lado] * sinal < meio_l * sinal
            else:
                esq = c[i, lado] * sinal > meio_l * sinal
            nome[i] = f"Perna{letra}{'E' if esq else 'D'}"
    return nome


def previa(pos, idx, nome, caminho: Path, eixo_frente: int) -> None:
    w = 900
    img = Image.new("RGB", (w * 2, w), (235, 232, 222))
    d = ImageDraw.Draw(img)
    lo, hi = pos.min(axis=0), pos.max(axis=0)
    lado = 2 if eixo_frente == 0 else 0
    esc = (w - 40) / max(hi - lo)
    for vista, (a, b, ox) in enumerate(((eixo_frente, 1, 0), (eixo_frente, lado, w))):
        ordem = np.argsort(pos[idx][:, :, lado if vista == 0 else 1].mean(axis=1))
        for i in ordem:
            t = pos[idx[i]]
            xs = 20 + ox + (t[:, a] - lo[a]) * esc
            ys = w - 20 - (t[:, b] - lo[b]) * esc
            d.polygon(list(zip(xs.tolist(), ys.tolist(), strict=True)), fill=CORES[nome[i]])
    img.save(caminho)


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    for chave, cfg in ESPECIES.items():
        pos, uv, idx, cor, nrm_tex = carregar(MODELOS / cfg["arquivo"])
        nome = dividir(pos, idx, cfg)
        previa(pos, idx, nome, SAIDA / f"{chave}_rig_previa.png", cfg["frente"][0])
        g = Glb()
        ti = g.texture(cor[0], cor[1]) if cor else None
        ni = g.texture(nrm_tex[0], nrm_tex[1]) if nrm_tex else None
        mi = g.material(chave, ti, ni, False)
        g.js["materials"][mi]["pbrMetallicRoughness"]["roughnessFactor"] = 0.9
        resumo = []
        for parte in CORES:
            sel = idx[nome == parte]
            if len(sel) == 0:
                continue
            usados, inv = np.unique(sel.reshape(-1), return_inverse=True)
            p, u = pos[usados], uv[usados]
            t = inv.reshape(-1, 3)
            n = normais(p, t)
            g.mesh(
                parte,
                p.astype(np.float32),
                n,
                u.astype(np.float32),
                t.reshape(-1).astype(np.uint32),
                mi,
            )
            resumo.append(f"{parte} {len(t)}")
        (SAIDA / f"{chave}_rig.glb").write_bytes(g.bytes())
        print(chave, ", ".join(resumo), "| caixa", np.round(pos.max(axis=0) - pos.min(axis=0), 2))


if __name__ == "__main__":
    main()
