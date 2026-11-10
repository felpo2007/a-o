"""Baixa os modelos do ForgeGUI listados em assets/forgegui/manifest.json e confere o sha256.

Modelos com "reducao_local" (remesh do ForgeGUI em outcome_unknown, D-45): baixa o original,
confere o sha256 de origem e refaz a redução com tools/decimate_glb.py (determinística para a
mesma versão do pymeshlab, fixada no grupo "arte").

Uso: uv run --group arte python tools/fetch_forgegui_assets.py   (a partir de vantuong65/)
"""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "assets/forgegui"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    man = json.loads((ROOT / "manifest.json").read_text("utf-8"))
    for m in man["models"]:
        dst = ROOT / m["arquivo"]
        if dst.exists() and sha(dst.read_bytes()) == m["sha256"]:
            print("ok (já existe)", dst.name)
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(m["url"], timeout=120).read()
        red = m.get("reducao_local")
        want = red["sha256_origem"] if red else m["sha256"]
        if sha(data) != want:
            raise SystemExit(f"sha256 diferente em {dst.name}: {sha(data)}")
        if not red:
            dst.write_bytes(data)
            print("baixado", dst.name, len(data), "bytes")
            continue
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from decimate_glb import run  # precisa do grupo "arte"

        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "origem.glb"
            src.write_bytes(data)
            r = run(src, dst, red["faces"])
        got = sha(dst.read_bytes())
        if got != m["sha256"]:
            # outra versão do pymeshlab: a malha muda um pouco; a contagem é o que importa
            print(f"aviso: {dst.name} reduzido com sha256 diferente ({r['tris']} triângulos)")
        else:
            print("reduzido", dst.name, r["tris"], "triângulos")


if __name__ == "__main__":
    main()
