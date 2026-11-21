"""Imagens de catálogo do jogo (D-222 a D-229): do PNG ao `AssetIds.Catalogo`.

Sobem como tipo Image: o ID serve direto na ImageLabel, sem resolver decal no servidor.

    uv run python tools/catalogo_imagens.py plano
    uv run --env-file .env python tools/roblox_cloud.py upload-assets Catalogo.
    uv run python tools/catalogo_imagens.py ids

`plano` acrescenta ao `assets/upload_plan.json` o que ainda não está lá. `ids` regrava o grupo
`Catalogo` do `AssetIds.luau` com o que já tem ID no `assets/roblox_ids.json`. Imagem refeita:
tire a chave `Catalogo.<nome>` do `roblox_ids.json` antes de subir (ele só sobe o que falta).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PLANO = RAIZ / "assets" / "upload_plan.json"
IDS = RAIZ / "assets" / "roblox_ids.json"
LUAU = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "AssetIds.luau"

# pasta, padrão do arquivo, prefixo da chave
GRUPOS = (
    ("assets/ui/armas", "*.png", "arma_"),
    ("assets/ui/equip", "*.png", "equip_"),
    ("assets/ui/classes", "*.png", "classe_"),
    ("assets/ui/times", "*.png", "time_"),
    ("assets/ui/premios", "*.png", "premio_"),
    ("assets/ui/skins", "*.png", "acab_"),
    ("assets/ui/horarios", "*.png", "hora_"),
    ("assets/ui/lobby", "lobby_*.png", ""),
    ("assets/carta", "aereo_??.png", ""),
)


def plano() -> None:
    bruto = PLANO.read_bytes().decode("utf-8")
    crlf = "\r\n" in bruto
    dados = json.loads(bruto)
    lista = (
        dados if isinstance(dados, list) else next(v for v in dados.values() if isinstance(v, list))
    )
    tem = {e["key"] for e in lista}
    novos = 0
    for pasta, padrao, prefixo in GRUPOS:
        for arq in sorted((RAIZ / pasta).glob(padrao)):
            nome = prefixo + arq.stem
            chave = "Catalogo." + nome
            if chave in tem:
                continue
            lista.append(
                {
                    "key": chave,
                    "file": arq.relative_to(RAIZ).as_posix(),
                    "assetType": "Image",
                    "name": ("VT65 " + nome.replace("_", " "))[:50],
                    "description": "VAN TUONG 65 - imagem de catalogo",
                }
            )
            tem.add(chave)
            novos += 1
    final = json.dumps(dados, ensure_ascii=False, indent=1) + ("\n" if bruto.endswith("\n") else "")
    PLANO.write_bytes((final.replace("\n", "\r\n") if crlf else final).encode("utf-8"))
    print(
        "novos no plano:",
        novos,
        "| total do catálogo:",
        sum(k.startswith("Catalogo.") for k in tem),
    )


def ids() -> None:
    todos = json.loads(IDS.read_text(encoding="utf-8"))
    grupo = {k.split(".", 1)[1]: int(v) for k, v in todos.items() if k.startswith("Catalogo.")}
    texto = LUAU.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in texto else "\n"
    ini = texto.index("\tCatalogo = {")
    abre = texto.index("{", ini)
    fecha = texto.index("}", abre)
    corpo = "".join(f"\t\t{k} = {v},{nl}" for k, v in sorted(grupo.items()))
    LUAU.write_bytes((texto[: abre + 1] + nl + corpo + "\t" + texto[fecha:]).encode("utf-8"))
    print("Catalogo no AssetIds:", len(grupo))


if __name__ == "__main__":
    acao = sys.argv[1] if len(sys.argv) > 1 else ""
    if acao == "plano":
        plano()
    elif acao == "ids":
        ids()
    else:
        raise SystemExit("uso: catalogo_imagens.py plano|ids")
