"""Sobe as animações do soldado (assets/mocap/soldado/<clipe>.rbxm) pela Open Cloud e grava os IDs.

A API de Assets do Open Cloud aceita o tipo "Animation" em .rbxm/.rbxmx (content type
model/x-rbxm), conferido em create.roblox.com/docs/cloud/guides/usage-assets (2026-11-11). A mesma
página avisa que .rbxm editado fora do Studio "might not upload or function": o .rbxm daqui sai do
Lune (tools/anim/kfs.luau), então confira a primeira no Studio antes de subir todas.

- Criador: o mesmo dos outros assets (cloud.json). Animação só toca no jogo do dono dela.
- Chave: ROBLOX_API_KEY no ambiente (permissão de escrita de Assets), nunca no código:
    uv run --env-file .env python tools/anim/subir.py             # sobe o que falta
    uv run python tools/anim/subir.py --simular                    # só mostra o plano
- IDs: assets/mocap/soldado/ids.json e SoldierAnims.luau (troca o `id = 0` de cada clipe).
  Com os quatro de pé (parado, andar, trote, correr) com ID, o jogo passa a usar as animações.
"""

from __future__ import annotations

import json
import re
import sys
import time
import uuid
from pathlib import Path

AQUI = Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI.parent))

import roblox_cloud as rc  # noqa: E402

RAIZ = AQUI.parents[1]
DIR = RAIZ / "assets" / "mocap" / "soldado"
IDS = DIR / "ids.json"
LUAU = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "SoldierAnims.luau"
CLIPES = [
    "parado",
    "andar",
    "trote",
    "correr",
    "agachado",
    "agachado_andar",
    "deitado",
    "rastejar",
    "recarregar",
    "granada",
    # corpo a corpo (D-94)
    "faca_saque",
    "faca_estocada",
    "faca_lado",
    "faca_guardar",
    "baioneta",
]
DESC = (
    "VAN TUONG 65: soldado com fuzil. Captura de movimento da CMU Graphics Lab Motion Capture "
    "Database (mocap.cs.cmu.edu), financiada pela NSF EIA-0196217."
)


def upload_animation(path: Path, name: str, creator: dict) -> str:
    req = {
        "assetType": "Animation",
        "displayName": name[:50],
        "description": DESC,
        "creationContext": {"creator": creator},
    }
    b = uuid.uuid4().hex
    body = (
        (
            f'--{b}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'
            f"{json.dumps(req)}\r\n"
            f"--{b}\r\nContent-Disposition: form-data; "
            f'name="fileContent"; filename="{path.name}"\r\n'
            "Content-Type: model/x-rbxm\r\n\r\n"
        ).encode()
        + path.read_bytes()
        + f"\r\n--{b}--\r\n".encode()
    )
    op = rc.request(
        "POST",
        f"{rc.API}/assets/v1/assets",
        body,
        {"Content-Type": f"multipart/form-data; boundary={b}"},
    )
    path_op = op.get("path") or op.get("operationId")
    for _ in range(60):
        if op.get("done"):
            break
        time.sleep(2)
        op = rc.request("GET", f"{rc.API}/assets/v1/{path_op}")
    asset_id = (op.get("response") or {}).get("assetId")
    if not asset_id:
        raise RuntimeError(f"sem assetId: {json.dumps(op)[:400]}")
    return str(asset_id)


def write_luau(ids: dict[str, str]) -> None:
    s = LUAU.read_text("utf-8")
    for name, v in ids.items():
        s = re.sub(rf"(\b{name}\s*=\s*\{{\s*id\s*=\s*)\d+", rf"\g<1>{int(v)}", s, count=1)
    LUAU.write_text(s, "utf-8", newline="\n")  # .luau com LF (o StyLua confere)


def main(simular: bool, so: list[str]) -> None:
    """`so`: só estes clipes (subir um primeiro para ver se o Roblox aceita o .rbxm do Lune)."""
    ids = json.loads(IDS.read_text("utf-8")) if IDS.exists() else {}
    falta = [n for n in CLIPES if n not in ids and (not so or n in so)]
    for n in falta:
        f = DIR / f"{n}.rbxm"
        print(
            ("subiria" if simular else "subindo"),
            n,
            f.name,
            f.stat().st_size if f.exists() else "AUSENTE",
        )
    if simular:
        return
    creator = rc.cfg()["creator"]
    for n in falta:
        f = DIR / f"{n}.rbxm"
        if not f.exists():
            print("pulando (sem .rbxm):", n)
            continue
        try:
            ids[n] = upload_animation(f, f"VT65 soldado {n}", creator)
            print("ok", n, ids[n])
            IDS.write_text(json.dumps(ids, indent=1), "utf-8")
        except (RuntimeError, OSError) as e:
            print("FALHA", n, e)
    write_luau(ids)
    print(f"{len(ids)} IDs em {IDS.name}; SoldierAnims.luau atualizado")


if __name__ == "__main__":
    args = sys.argv[1:]
    main("--simular" in args, [a for a in args if not a.startswith("--")])
