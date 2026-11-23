"""Registra os modelos dos mapas retangulares (D-243) no jogo a partir do que foi medido.

    uv run python tools/ret_registrar.py plano [chaves]   # upload_plan.json: o que falta
    uv run --env-file .env python tools/roblox_cloud.py upload-assets Models.ret_merc_
    uv run python tools/ret_registrar.py jogo             # ArtBudget e AssetIds

Modelo: `assets/blender/<chave>/<chave>.glb`. Os números saem de `metricas.json`; nada é digitado à
mão. Rodar de novo só atualiza os blocos marcados.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BLENDER = RAIZ / "assets" / "blender"
PLANO = RAIZ / "assets" / "upload_plan.json"
IDS = RAIZ / "assets" / "roblox_ids.json"
ORCA = RAIZ / "src" / "ServerScriptService" / "Modules" / "ArtBudget.luau"
ASSET = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "AssetIds.luau"
NOS = RAIZ / "src" / "ServerStorage" / "VT65Build" / "NosRet.luau"
INI = "-- D-243 (mapas retangulares): gerado por tools/ret_registrar.py"
FIM = "-- D-243 (fim)"
ANCORA = "-- D-232 (fim)"
FORA = {"ret_manequim", "ret_piloto_casa"}  # a cena de calibração não entra no mapa


def chaves() -> list[str]:
    return sorted(
        p.name
        for p in BLENDER.glob("ret_*")
        if p.name not in FORA
        and (p / "metricas.json").is_file()
        and (p / f"{p.name}.glb").is_file()
    )


def medida(chave: str) -> dict:
    return json.loads((BLENDER / chave / "metricas.json").read_text("utf-8"))["novo"]


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
        lista.append(
            {
                "key": k,
                "file": medida(c).get("arquivo") or f"assets/blender/{c}/{c}.glb",
                "assetType": "Model",
                "name": f"VT65 {c}"[:50],
                "description": "VAN TUONG 65 - mapas retangulares (Blender)",
            }
        )
        novos += 1
    final = json.dumps(dados, ensure_ascii=False, indent=1) + ("\n" if bruto.endswith("\n") else "")
    PLANO.write_bytes((final.replace("\n", "\r\n") if crlf else final).encode("utf-8"))
    print("novos no plano:", novos)


def bloco(texto: str, nl: str, depois: int, recuo: str, linhas: list[str]) -> str:
    """Troca (ou cria) o bloco logo depois da linha que contém a posição `depois`."""
    corpo = nl.join([f"{recuo}{INI}", *linhas, f"{recuo}{FIM}"]) + nl
    ini = texto.index(nl, depois) + len(nl)
    if texto[ini:].lstrip("\t").startswith(INI):
        fim = texto.index(FIM, ini)
        fim = texto.index(nl, fim) + len(nl)
        return texto[:ini] + corpo + texto[fim:]
    return texto[:ini] + corpo + texto[ini:]


def jogo() -> None:
    cs = chaves()
    texto = ORCA.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in texto else "\n"
    tipo = [f'\t{c} = "prop",' for c in cs]
    tris = [f"\t{c} = {medida(c)['triangulos']}," for c in cs]
    dims = [
        "\t{} = {{ {}, {}, {} }},".format(c, *[round(v, 2) for v in medida(c)["dim_studs_xyz"]])
        for c in cs
    ]
    # as três tabelas, de trás para frente: cada bloco entra depois do fim do bloco da D-232
    pos = [m.start() for m in re.finditer(re.escape(ANCORA), texto)]
    assert len(pos) >= 3, "tabelas do ArtBudget mudaram"
    for p, linhas in reversed(list(zip(pos[:3], (tipo, tris, dims), strict=True))):
        texto = bloco(texto, nl, p, "\t", linhas)
    ORCA.write_bytes(texto.encode("utf-8"))

    ids = json.loads(IDS.read_text("utf-8"))
    linhas = [f"\t\t{c} = {int(ids[f'Models.{c}'])}," for c in cs if f"Models.{c}" in ids]
    a = ASSET.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in a else "\n"
    a = bloco(a, nl, a.index(ANCORA), "\t\t", linhas)
    ASSET.write_bytes(a.encode("utf-8"))
    # a colisão de cada nó: a bala para ou atravessa, e o material do impacto
    saida = ["--!strict", "-- GERADO por tools/ret_registrar.py. Não editar.", "return {"]
    for c in cs:
        m = json.loads((BLENDER / c / "metricas.json").read_text("utf-8"))
        saida.append(f"\t{c} = {{")
        for col in m.get("colisao") or []:
            stop = "true" if col["bala"] == "para" else "false"
            saida.append(
                f'\t\t["{col["no"]}"] = {{ stop = {stop}, material = "{col["material"] or ""}" }},'
            )
        saida.append("\t},")
    saida.append("}")
    NOS.write_text("\n".join(saida) + "\n", "utf-8", newline="\n")
    print("ArtBudget:", len(cs), "modelos | AssetIds:", len(linhas))


if __name__ == "__main__":
    acao = sys.argv[1] if len(sys.argv) > 1 else ""
    if acao == "plano":
        plano(sys.argv[2:])
    elif acao == "jogo":
        jogo()
    else:
        raise SystemExit("uso: ret_registrar.py plano [chaves]|jogo")
