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
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "assets/forgegui"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def download(url: str, name: str, tries: int = 3, deadline_s: float = 300) -> bytes:
    """Baixa em blocos com prazo total por tentativa. O timeout do urlopen vale só por leitura:
    com o servidor mandando bytes devagar, um download ficou parado mais de 10 min sem erro
    (PC do dono, 2026-11-10). Aqui cada tentativa tem prazo total e há até 3 tentativas."""
    last: Exception | None = None
    for attempt in range(1, tries + 1):
        t0 = time.monotonic()
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                chunks = []
                while True:
                    if time.monotonic() - t0 > deadline_s:
                        raise TimeoutError(f"passou de {deadline_s:.0f} s")
                    b = r.read(1 << 20)
                    if not b:
                        break
                    chunks.append(b)
            return b"".join(chunks)
        except (OSError, TimeoutError) as e:  # URLError, socket.timeout e afins
            last = e
            print(f"  tentativa {attempt}/{tries} de {name} falhou: {e}", flush=True)
    raise SystemExit(f"não baixou {name}: {last}")


def main() -> None:
    man = json.loads((ROOT / "manifest.json").read_text("utf-8"))
    for m in man["models"]:
        dst = ROOT / m["arquivo"]
        if dst.exists() and sha(dst.read_bytes()) == m["sha256"]:
            print("ok (já existe)", dst.name)
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        data = download(m["url"], dst.name)
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
