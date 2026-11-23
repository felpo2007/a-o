"""Gera docs/ASSET_MANIFEST.md a partir do que foi medido (prompt V5, §22). Nada é digitado à mão.

Lê assets/blender/<chave>/metricas.json, assets/roblox_ids.json e as listas de Shared/VilaPiloto.
Uso (de vantuong65/): uv run python tools/manifesto_assets.py
"""

from __future__ import annotations

import json
import re
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
BLENDER = RAIZ / "assets" / "blender"


def usos() -> dict[str, int]:
    """Quantas cópias fixas de cada modelo a área piloto usa (o mesmo MeshId)."""
    t = (RAIZ / "src/ReplicatedStorage/Shared/VilaPiloto.luau").read_text("utf-8")
    n: dict[str, int] = {}
    for k in re.findall(r'para = "(\w+)"', t):
        n[k] = n.get(k, 0) + 1
    for k in re.findall(r'P\("(\w+)"', t):
        n[k] = n.get(k, 0) + 1
    n["ret_vila_poca"] = len(re.findall(r"\bpoca\(-?\d", t))
    return n


def principal() -> None:
    ids = json.loads((RAIZ / "assets/roblox_ids.json").read_text("utf-8"))
    n = usos()
    linhas = [
        "# Manifesto de assets: área piloto da Vila",
        "",
        "Gerado por `tools/manifesto_assets.py`.",
        "Tamanhos, triângulos e colisões saem do `metricas.json`.",
        "Trechos de cerca, trilhas e folhas têm a contagem final no log do jogo.",
        "",
        "| Chave | Asset ID | Dimensões (m) | Triângulos | Colisões | Trim sheet | Cópias fixas |",
        "|---|---|---|---:|---:|---|---:|",
    ]
    total = 0
    for pasta in sorted(BLENDER.glob("ret_vila_*")):
        arq = pasta / "metricas.json"
        if not arq.is_file():
            continue
        m = json.loads(arq.read_text("utf-8"))
        novo = m["novo"]
        d = novo.get("dim_m_xyz") or [0, 0, 0]
        tris = int(novo["triangulos"])
        total += tris
        trim = "sim" if "trim" in m else "não"
        chave = pasta.name
        linhas.append(
            f"| `{chave}` | {ids.get('Models.' + chave, '-')} | "
            f"{d[0]:.1f} × {d[1]:.1f} × {d[2]:.1f} | {tris} | {len(m.get('colisao') or [])} | "
            f"{trim} | {n.get(chave, 0)} |"
        )
    linhas += [
        "",
        f"Soma de uma cópia de cada modelo: {total} triângulos.",
        "",
        "- **RenderFidelity:** `Automatic` (padrão), sem `Precise`.",
        "- **SLIM:** ainda não. O SLIM só é gerado para modelos no arquivo do place,",
        "  e o piloto é montado em tempo de jogo enquanto não for aprovado.",
        "  Depois da aprovação ele entra na arte fixa.",
        "- **Teste em jogo:** resultados em `docs/QA_RESULTS.md`.",
        "",
    ]
    (RAIZ / "docs").mkdir(exist_ok=True)
    (RAIZ / "docs" / "ASSET_MANIFEST.md").write_text("\n".join(linhas), "utf-8", newline="\n")
    print("ok", len(linhas) - 14, "modelos", total, "triângulos")


if __name__ == "__main__":
    principal()
