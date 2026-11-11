"""Automação Open Cloud do VAN TUONG '65: sobe assets, cria passes/produtos e publica o place.

A chave NÃO fica aqui nem no Git: o proxy da sessão injeta o cabeçalho `x-api-key` nas
chamadas a apis.roblox.com (credencial salva no ambiente). Localmente, defina ROBLOX_API_KEY.
Configuração não secreta em cloud.json (universeId, placeId, creator).

Uso (a partir de vantuong65/):
  uv run python tools/roblox_cloud.py upload-assets      # ForgeGUI -> Roblox; gera AssetIds.luau
  uv run python tools/roblox_cloud.py create-store       # passes e produtos que faltam -> Commerce
  uv run python tools/roblox_cloud.py create-store PASS_KIT_VETERAN ...   # só estas chaves
  uv run python tools/roblox_cloud.py publish-place      # publica place/VanTuong65.rbxl
  uv run python tools/roblox_cloud.py all

Endpoints: Assets API v1 e Place Publishing (documentados); Game Passes/Developer Products
seguem a referência Open Cloud de 2025-26 e são registrados por completo no log na 1ª execução.
"""

from __future__ import annotations

import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://apis.roblox.com"
IDS_FILE = ROOT / "assets/roblox_ids.json"
PLAN = ROOT / "assets/upload_plan.json"


def cfg() -> dict:
    p = ROOT / "cloud.json"
    if not p.exists():
        raise SystemExit("crie cloud.json a partir de cloud.example.json")
    return json.loads(p.read_text("utf-8"))


def headers(extra: dict | None = None) -> dict:
    # valor real vem do proxy (ou de ROBLOX_API_KEY localmente)
    h = {"x-api-key": os.environ.get("ROBLOX_API_KEY", "injetado-pelo-proxy")}
    h.update(extra or {})
    return h


def request(method: str, url: str, body: bytes | None = None, hdrs: dict | None = None) -> dict:
    req = urllib.request.Request(url, data=body, method=method, headers=headers(hdrs))
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            txt = r.read().decode("utf-8") or "{}"
            return json.loads(txt)
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {url} -> HTTP {e.code}: {msg[:600]}") from e


def multipart(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    b = uuid.uuid4().hex
    out = bytearray()
    for k, v in fields.items():
        out += f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    for k, path in files.items():
        ctype = {
            ".glb": "model/gltf-binary",
            ".mp3": "audio/mpeg",
            ".png": "image/png",
            ".jpg": "image/jpeg",
        }.get(path.suffix, mimetypes.guess_type(path.name)[0] or "application/octet-stream")
        out += (
            f'--{b}\r\nContent-Disposition: form-data; name="{k}"; filename="{path.name}"\r\n'
            f"Content-Type: {ctype}\r\n\r\n"
        ).encode()
        out += path.read_bytes() + b"\r\n"
    out += f"--{b}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={b}"


def load_ids() -> dict:
    return json.loads(IDS_FILE.read_text("utf-8")) if IDS_FILE.exists() else {}


def save_ids(ids: dict) -> None:
    IDS_FILE.write_text(json.dumps(ids, ensure_ascii=False, indent=1), "utf-8")


def upload_asset(path: Path, asset_type: str, name: str, creator: dict, desc: str = "") -> str:
    req = {
        "assetType": asset_type,
        "displayName": name[:50],
        "description": desc or "VAN TUONG 65 (ForgeGUI)",
        "creationContext": {"creator": creator},
    }
    body, ctype = multipart({"request": json.dumps(req)}, {"fileContent": path})
    op = request("POST", f"{API}/assets/v1/assets", body, {"Content-Type": ctype})
    path_op = op.get("path") or op.get("operationId")
    for _ in range(60):
        if op.get("done"):
            break
        time.sleep(2)
        op = request("GET", f"{API}/assets/v1/{path_op}")
    resp = op.get("response") or {}
    asset_id = resp.get("assetId")
    if not asset_id:
        raise RuntimeError(f"upload sem assetId: {json.dumps(op)[:400]}")
    return str(asset_id)


def write_asset_ids(ids: dict) -> None:
    """Regrava src/ReplicatedStorage/Shared/AssetIds.luau trocando 0 pelos IDs publicados."""
    p = ROOT / "src/ReplicatedStorage/Shared/AssetIds.luau"
    s = p.read_text("utf-8")
    for key, v in ids.items():
        group, field = key.split(".", 1)
        s = re.sub(
            rf"(\b{group} = \{{.*?\b{field} = )\d+",
            rf"\g<1>{int(v)}",
            s,
            count=1,
            flags=re.S,
        )
    p.write_text(s, "utf-8")


def cmd_upload_assets() -> None:
    c = cfg()
    plan = json.loads(PLAN.read_text("utf-8"))
    ids = load_ids()
    for item in plan:
        key, rel, atype = item["key"], item["file"], item["assetType"]
        if key in ids:
            continue
        f = ROOT / rel
        if not f.exists():
            print("pulando (arquivo ausente):", rel)
            continue
        try:
            ids[key] = upload_asset(
                f, atype, item.get("name", key), c["creator"], item.get("description", "")
            )
            print("ok", key, ids[key])
            save_ids(ids)
        except (RuntimeError, OSError) as e:  # registra e segue para os demais
            print("FALHA", key, e)
    write_asset_ids(ids)
    print(f"{len(ids)} IDs em {IDS_FILE.name}; AssetIds.luau atualizado")


KIT_DESC = {
    "PASS_KIT_VETERAN": (
        "Equipamento nível 1 nos dois lados: +2 carregadores, cantil extra e estojo de socorro "
        "reforçado. Também sai de graça no posto 5 ou com créditos ganhos jogando."
    ),
    "PASS_KIT_ELITE": (
        "Equipamento nível 2 (inclui o Veterano): colete antiestilhaço e fumaça extra (EUA), "
        "granada e fumaça extras (VC). Também sai de graça no posto 7 ou com créditos."
    ),
}


def cmd_create_store(only: set[str] | None = None) -> None:
    """Cria passes e produtos que faltam. `only`: só estas chaves (ex.: itens de jogo da D-72)."""
    c = cfg()
    u = c["universeId"]
    ids = load_ids()
    passes = [
        ("PASS_USMC_1965", "Uniformes USMC 1965", "marketing/gamepass_usmc_1965_v2.jpg", 149),
        ("PASS_VC_1965", "Uniformes Força Principal 1965", "marketing/gamepass_vc_1965.jpg", 149),
        ("PASS_UNIT", "Passe de Unidade", "marketing/gamepass_unidade.jpg", 299),
        ("PASS_SUPPORTER", "Apoiador — Dossiê Starlite", "marketing/gamepass_apoiador.jpg", 99),
        # itens de jogo (decisão do dono, 2026-11-11, D-72); preços = Commerce.suggestedRobux
        ("PASS_KIT_VETERAN", "Kit Veterano", "marketing/gamepass_kit_veterano.jpg", 149),
        ("PASS_KIT_ELITE", "Kit de Elite", "marketing/gamepass_kit_elite.jpg", 299),
    ]
    for key, name, img, price in passes:
        if f"store.{key}" in ids or (only is not None and key not in only):
            continue
        body, ctype = multipart(
            {
                "name": name,
                "description": KIT_DESC.get(key, "Só visual/apoio. Sem vantagem."),
                "isForSale": "true",
                "price": str(price),
            },
            {"imageFile": ROOT / "assets/forgegui" / img},
        )
        url = f"{API}/game-passes/v1/universes/{u}/game-passes"
        r = request("POST", url, body, {"Content-Type": ctype})
        print("resposta pass", key, json.dumps(r)[:300])
        gid = r.get("gamePassId") or r.get("id")
        if gid:
            ids[f"store.{key}"] = str(gid)
            save_ids(ids)
    products = [
        ("PRODUCT_TIP_SMALL", "Apoiar o desenvolvimento", 25, "Sem recompensa em jogo."),
        ("PRODUCT_TIP_LARGE", "Apoiar o desenvolvimento (grande)", 100, "Sem recompensa em jogo."),
        (
            "PRODUCT_RESPAWN_INPLACE",
            "Renascer onde caiu",
            25,
            "Volta a campo onde você caiu, na mesma espera do spawn normal, sem inimigo a menos "
            "de 100 m. Se não der na hora, fica guardado para a próxima queda.",
        ),
    ]
    for key, name, price, desc in products:
        if f"store.{key}" in ids or (only is not None and key not in only):
            continue
        url = f"{API}/developer-products/v2/universes/{u}/developer-products"
        fields = {
            "name": name,
            "description": desc,
            "price": str(price),
            "isForSale": "true",
        }
        body, ctype = multipart(fields, {})
        try:
            r = request("POST", url, body, {"Content-Type": ctype})
        except RuntimeError as e:
            # alguns ambientes aceitam só JSON: tenta de novo nesse formato
            if "HTTP 415" not in str(e) and "HTTP 400" not in str(e):
                raise
            payload = dict(fields, price=price, isForSale=True)
            r = request(
                "POST", url, json.dumps(payload).encode(), {"Content-Type": "application/json"}
            )
        print("resposta produto", key, json.dumps(r)[:300])
        pid = r.get("productId") or r.get("id")
        if pid:
            ids[f"store.{key}"] = str(pid)
            save_ids(ids)
    # grava os IDs no catálogo
    p = ROOT / "src/ReplicatedStorage/Shared/Commerce.luau"
    s = p.read_text("utf-8")
    for k, v in ids.items():
        if k.startswith("store."):
            s = re.sub(rf"(\t{k[6:]} = )\d+", rf"\g<1>{int(v)}", s, count=1)
    p.write_text(s, "utf-8")
    print("Commerce.IDS atualizado")


def cmd_publish_place() -> None:
    c = cfg()
    rbxl = ROOT / "place/VanTuong65.rbxl"
    u, pid = c["universeId"], c["placeId"]
    url = f"{API}/universes/v1/{u}/places/{pid}/versions?versionType=Published"
    r = request("POST", url, rbxl.read_bytes(), {"Content-Type": "application/octet-stream"})
    print("publicado:", r)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd == "upload-assets":
        cmd_upload_assets()
    elif cmd == "create-store":
        # create-store [CHAVE ...]: sem chaves cria tudo o que falta
        cmd_create_store(set(sys.argv[2:]) or None)
    elif cmd == "publish-place":
        cmd_publish_place()
    elif cmd == "all":
        cmd_upload_assets()
        cmd_create_store()
        print("reconstrua o place (rojo build + lune bake) e rode publish-place")
    else:
        print(__doc__)
