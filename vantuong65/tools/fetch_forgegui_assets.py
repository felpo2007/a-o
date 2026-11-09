"""Baixa os modelos do ForgeGUI listados em assets/forgegui/manifest.json e confere o sha256.

Uso: uv run python tools/fetch_forgegui_assets.py   (a partir de vantuong65/)
"""

from __future__ import annotations

import hashlib
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "assets/forgegui"


def main() -> None:
    man = json.loads((ROOT / "manifest.json").read_text("utf-8"))
    for m in man["models"]:
        dst = ROOT / m["arquivo"]
        if dst.exists() and hashlib.sha256(dst.read_bytes()).hexdigest() == m["sha256"]:
            print("ok (já existe)", dst.name)
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(m["url"], timeout=120).read()
        digest = hashlib.sha256(data).hexdigest()
        if digest != m["sha256"]:
            raise SystemExit(f"sha256 diferente em {dst.name}: {digest}")
        dst.write_bytes(data)
        print("baixado", dst.name, len(data), "bytes")


if __name__ == "__main__":
    main()
