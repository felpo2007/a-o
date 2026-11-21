"""Registra os modelos da expansão (D-232) no jogo a partir do que foi medido.

    uv run --group arte python tools/expansao_registrar.py plantas # pé em Y = 0, cor, métricas
    uv run python tools/expansao_registrar.py plano [chaves]  # upload_plan.json: o que falta
    uv run --env-file .env python tools/roblox_cloud.py upload-assets Models.exp_
    uv run python tools/expansao_registrar.py jogo    # ArtBudget e AssetIds, com os números medidos

Construção: `assets/blender/<chave>/<chave>_trim.glb`. Planta: `assets/blender/<chave>/<chave>.glb`.
Os números saem de `metricas.json`; nada é digitado à mão. Rodar de novo só atualiza os blocos.

Planta: as raízes e o pé da rocha descem abaixo de Y = 0 no Blender. O jogo apoia o FUNDO da caixa
no chão e o tronco (TreeTrunks) conta a partir do pivô no pé, então `plantas` sobe o modelo até o
fundo ficar em Y = 0 e guarda quanto subiu em `afunda_studs`; o ArtBudget.BASE_SINK enterra.
A folha é puxada para a cor média da mata antiga (no Studio, as copas novas saíam claras demais).
"""

from __future__ import annotations

import io
import json
import re
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from decimate_glb import read_glb  # noqa: E402
from troncos import contornos, madeira  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
BLENDER = RAIZ / "assets" / "blender"
M = 0.28
PLANO = RAIZ / "assets" / "upload_plan.json"
IDS = RAIZ / "assets" / "roblox_ids.json"
ORCA = RAIZ / "src" / "ServerScriptService" / "Modules" / "ArtBudget.luau"
ASSET = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "AssetIds.luau"
PLANTAS = ("exp_figueira", "exp_arvore_a", "exp_arvore_b", "exp_rocha", "exp_samambaia")
INI = "-- D-232 (expansão): gerado por tools/expansao_registrar.py"
FIM = "-- D-232 (fim)"
# cor média da folha no jogo (RGB): a das árvores do Poly Haven (93, 101, 34), um pouco mais escura
# porque as copas novas têm menos sombra entre os cartões
FOLHA_ALVO = (74.0, 82.0, 30.0)


def chaves() -> list[str]:
    return sorted(p.name for p in BLENDER.glob("exp_*") if (p / "metricas.json").is_file())


def medida(chave: str) -> dict:
    return json.loads((BLENDER / chave / "metricas.json").read_text("utf-8"))["novo"]


def arquivo(chave: str) -> str:
    nome = f"{chave}.glb" if chave in PLANTAS else f"{chave}_trim.glb"
    return f"assets/blender/{chave}/{nome}"


def grava_glb(caminho: Path, js: dict, blob: bytes) -> None:
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * (-len(jb) % 4)
    bb = blob + b"\0" * (-len(blob) % 4)
    caminho.write_bytes(
        struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(jb) + 8 + len(bb))
        + struct.pack("<I4s", len(jb), b"JSON")
        + jb
        + struct.pack("<I4s", len(bb), b"BIN\x00")
        + bb
    )


def gradua_folhas(js: dict, blob: bytes) -> bytes:
    """Leva a textura das malhas Folhas* à FOLHA_ALVO (uma vez: marca em asset.extras)."""
    from PIL import Image

    feitos: set[int] = set()
    for me in js["meshes"]:
        if not me.get("name", "").startswith("Folhas"):
            continue
        for pr in me["primitives"]:
            pbr = js["materials"][pr["material"]]["pbrMetallicRoughness"]
            img = js["textures"][pbr["baseColorTexture"]["index"]]["source"]
            if img in feitos:
                continue
            feitos.add(img)
            bv = js["bufferViews"][js["images"][img]["bufferView"]]
            ini, tam = bv.get("byteOffset", 0), bv["byteLength"]
            a = np.array(Image.open(io.BytesIO(blob[ini : ini + tam])).convert("RGBA"), float)
            ganho = np.array(FOLHA_ALVO) / a[a[..., 3] > 128][:, :3].mean(axis=0)
            a[..., :3] = np.clip(a[..., :3] * ganho, 0, 255)
            saida = io.BytesIO()
            Image.fromarray(a.astype(np.uint8), "RGBA").save(saida, "PNG", optimize=True)
            png = saida.getvalue()
            novo = png + b"\0" * ((tam - len(png)) % 4)  # mantém o alinhamento do que vem depois
            blob = blob[:ini] + novo + blob[ini + tam :]
            bv["byteLength"] = len(png)
            for o in js["bufferViews"]:
                if o is not bv and o.get("byteOffset", 0) > ini:
                    o["byteOffset"] += len(novo) - tam
    js["buffers"][0]["byteLength"] = len(blob)
    js["asset"].setdefault("extras", {})["vt65_folha"] = 1
    return blob


def plantas() -> None:
    """Fundo do modelo em Y = 0, cor da folha (idempotente) e metricas.json medido no GLB."""
    for c in PLANTAS:
        g = BLENDER / c / f"{c}.glb"
        caminho = BLENDER / c / "metricas.json"
        antes = json.loads(caminho.read_text("utf-8")) if caminho.is_file() else {}
        afunda = float(antes.get("afunda_studs", 0.0))
        if c != "exp_rocha":
            js, blob = read_glb(g)
            if not js["asset"].get("extras", {}).get("vt65_folha"):
                blob = gradua_folhas(js, blob)
                grava_glb(g, js, blob)
        v, f = madeira(g, None)
        y0 = float(v[:, 1].min())
        if abs(y0) > 1e-3:
            js, blob = read_glb(g)
            for i in js["scenes"][js.get("scene", 0)]["nodes"]:
                n = js["nodes"][i]
                assert "matrix" not in n, f"{c}: nó raiz com matriz"
                t = list(n.get("translation", [0, 0, 0]))
                t[1] -= y0
                n["translation"] = t
            grava_glb(g, js, blob)
            afunda -= y0
            v, f = madeira(g, None)
        if c in ("exp_rocha", "exp_samambaia"):
            pe = v[v[:, 1] < afunda + 0.1 / M]
            raio = float(np.hypot(pe[:, 0], pe[:, 2]).max())
        else:
            vm, fm = madeira(g, "Madeira")
            raio = max(r for _, _, r in contornos(vm, fm, afunda + 0.05 / M))
        dim = v.max(axis=0) - v.min(axis=0)
        met = {
            "novo": {
                "triangulos": int(len(f)),
                "dim_studs_xyz": [round(float(x), 2) for x in dim],
            },
            "raio_base": round(raio, 2),
            "afunda_studs": round(afunda, 3),
        }
        caminho.write_text(json.dumps(met, indent=1) + "\n", "utf-8")
        print(c, met["novo"]["triangulos"], met["novo"]["dim_studs_xyz"], met["raio_base"], afunda)


def plano(so: list[str]) -> None:
    bruto = PLANO.read_bytes().decode("utf-8")
    crlf = "\r\n" in bruto
    dados = json.loads(bruto)
    lista = (
        dados if isinstance(dados, list) else next(v for v in dados.values() if isinstance(v, list))
    )
    tem = {e["key"] for e in lista}
    novos = 0
    for c in chaves():
        k = f"Models.{c}"
        if k in tem or (so and c not in so):
            continue
        assert (RAIZ / arquivo(c)).is_file(), f"falta {arquivo(c)}"
        lista.append(
            {
                "key": k,
                "file": arquivo(c),
                "assetType": "Model",
                "name": f"VT65 {c}"[:50],
                "description": "VAN TUONG 65 - expansao da Vila e do Arrozal (Blender)",
            }
        )
        novos += 1
    final = json.dumps(dados, ensure_ascii=False, indent=1) + ("\n" if bruto.endswith("\n") else "")
    PLANO.write_bytes((final.replace("\n", "\r\n") if crlf else final).encode("utf-8"))
    print("novos no plano:", novos)


def bloco(texto: str, nl: str, ancora: str, linhas: list[str]) -> str:
    """Troca o bloco D-232 logo depois da linha da âncora (ou cria)."""
    corpo = nl.join([f"\t{INI}", *linhas, f"\t{FIM}"]) + nl
    i = texto.index(ancora)
    fim_ancora = texto.index(nl, i) + len(nl)
    if texto[fim_ancora:].lstrip("\t").startswith(INI):
        fim = texto.index(FIM, fim_ancora)
        fim = texto.index(nl, fim) + len(nl)
        return texto[:fim_ancora] + corpo + texto[fim:]
    return texto[:fim_ancora] + corpo + texto[fim_ancora:]


def jogo() -> None:
    cs = chaves()
    texto = ORCA.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in texto else "\n"
    tipo = [f'\t{c} = "{"veg" if c in PLANTAS else "prop"}",' for c in cs]
    tris = [f"\t{c} = {medida(c)['triangulos']}," for c in cs]
    dims = [
        "\t{} = {{ {}, {}, {} }},".format(c, *[round(v, 2) for v in medida(c)["dim_studs_xyz"]])
        for c in cs
    ]
    raios = [
        f"\t{c} = {json.loads((BLENDER / c / 'metricas.json').read_text('utf-8'))['raio_base']},"
        for c in cs
        if c in PLANTAS
    ]
    # âncoras: a linha da vila_casa_10 em cada tabela, na ordem do arquivo
    pos = [m.start() for m in re.finditer(r"\tvila_casa_10 = ", texto)]
    assert len(pos) >= 3, "tabelas do ArtBudget mudaram"
    for ancora, linhas in reversed(
        (
            (r'\tvila_casa_10 = "prop",', tipo),
            (r"\tvila_casa_10 = \d+,", tris),
            (r"\tvila_casa_10 = \{", dims),
        )
    ):
        m = re.search(ancora, texto)
        texto = bloco(texto, nl, m.group(0), linhas)
    if raios:
        texto = bloco(texto, nl, "\trice_patch = 1.5,", raios)
        afundar = []
        for c in cs:
            if c in PLANTAS:
                m = json.loads((BLENDER / c / "metricas.json").read_text("utf-8"))
                h = m["novo"]["dim_studs_xyz"][1]
                afundar.append(
                    f"\t{c} = {{ frac = {round(m['afunda_studs'] / h, 5)}, height = {h} }},"
                )
        texto = bloco(texto, nl, "ArtBudget.BASE_SINK = {", afundar)
    ORCA.write_bytes(texto.encode("utf-8"))

    ids = json.loads(IDS.read_text("utf-8"))
    linhas = [f"\t\t{c} = {int(ids[f'Models.{c}'])}," for c in cs if f"Models.{c}" in ids]
    a = ASSET.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in a else "\n"
    m = re.search(r"\t\tvila_casa_10 = \d+,", a)
    fim = a.index(nl, m.start()) + len(nl)
    corpo = nl.join([f"\t\t{INI}", *linhas, f"\t\t{FIM}"]) + nl
    if a[fim:].lstrip("\t").startswith(INI):
        fim2 = a.index(FIM, fim)
        fim2 = a.index(nl, fim2) + len(nl)
        a = a[:fim] + corpo + a[fim2:]
    else:
        a = a[:fim] + corpo + a[fim:]
    ASSET.write_bytes(a.encode("utf-8"))
    print("ArtBudget:", len(cs), "modelos | AssetIds:", len(linhas))


if __name__ == "__main__":
    acao = sys.argv[1] if len(sys.argv) > 1 else ""
    if acao == "plantas":
        plantas()
    elif acao == "plano":
        plano(sys.argv[2:])
    elif acao == "jogo":
        jogo()
    else:
        raise SystemExit("uso: expansao_registrar.py plantas|plano [chaves]|jogo")
