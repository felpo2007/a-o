"""Arte fixa no arquivo do place, para o SLIM (D-155).

O SLIM do Roblox (cenário mais leve à distância) só vale para modelo SALVO no place, com
`LevelOfDetail = SLIM`, e com o Team Create ligado (D-154). A nossa arte é posta pelo AssetLoader
quando o jogo abre, então um conjunto de teste é copiado do jogo rodando
(tools/estatico_copiar.luau, no Studio pelo MCP) para `assets/estatico/<conjunto>.txt`, e este
script gera:
- `src/Workspace/Estatico/<n>_<chave>.model.json`: um modelo do Rojo por objeto, já assentado e
  tingido, com `LevelOfDetail = SLIM` (o valor 4: o Lune 0.8 não conhece o nome, mas o Rojo grava o
  número e o Lune passa adiante sem ler), `ModelStreamingMode = Atomic` e os atributos
  `VT65Estatico` e `VT65Chave`. O tools/bake_place.luau põe esses modelos em `Map.Art` com o nome da
  chave;
- `src/ServerScriptService/Modules/StaticArt.luau`: chave e pivô de cada um. O AssetLoader não põe a
  cópia que cairia no mesmo lugar.

Peça de malha criada fora do Studio não traz a colisão calculada (PhysicsData):
- as peças que colidem vão com `CollisionFidelity = Box`. A colisão das casas do Blender já é feita
  de caixas (`Colisao_*`); objeto do gerador com colisão de forma (cabana aberta) vira bloco;
- a luz do Roblox usa essa forma para a sombra de dentro. Testado no Studio: a casa fixa saiu com o
  interior claro, e a do AssetLoader, escuro. Com `Hull` calculado pelo Studio, escurece; com `Box`,
  não.

Por isso o conjunto só entra no place quando estiver em `assets/estatico/ativos.json` (lista de
nomes sem o .txt). Ligue depois do Team Create, para o teste do SLIM.

Uso: uv run python tools/estatico.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
ENTRADA = RAIZ / "assets" / "estatico"
SAIDA = RAIZ / "src" / "Workspace" / "Estatico"
MODULO = RAIZ / "src" / "ServerScriptService" / "Modules" / "StaticArt.luau"
SLIM = 4  # Enum.ModelLevelOfDetail.SLIM
# chaves que dependem do jogo rodando (MapLife.baseInstance): toque das estacas, escada TrussPart,
# fumaça da cozinha do VC e a cancela que gira. Elas ficam com o AssetLoader.
SO_EM_JOGO = {"vc_punji", "us_watchtower", "vila_casa_09", "vc_hoang_cam_kitchen", "us_gate"}


def orientacao(giro: float) -> list[list[float]]:
    """CFrame.Angles(0, giro, 0) em linhas."""
    r = math.radians(giro)
    c, s = round(math.cos(r), 6), round(math.sin(r), 6)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def cframe(x: float, y: float, z: float, giro: float) -> dict:
    return {"position": [x, y, z], "orientation": orientacao(giro)}


def ler(caminho: Path) -> list[dict]:
    modelos: list[dict] = []
    atual: dict | None = None
    nos: dict[str, dict] = {}
    alvo: dict | None = None
    peca: dict | None = None
    for n, linha in enumerate(caminho.read_text("utf-8").splitlines(), 1):
        if not linha.strip():
            continue
        tipo, _, resto = linha.partition(" ")
        campos = resto.split(" ")
        if tipo == "X":
            raise SystemExit(f"{caminho.name}:{n}: fora do previsto: {resto}")
        if tipo == "M":
            chave, x, y, z, giro, escala = campos
            if chave in SO_EM_JOGO:
                raise SystemExit(f"{caminho.name}:{n}: {chave} depende do jogo rodando (MapLife)")
            atual = {
                "chave": chave,
                "pivo": [float(x), float(y), float(z)],
                "giro": float(giro),
                "escala": float(escala),
                "filhos": [],
            }
            modelos.append(atual)
            nos = {"": atual}
            alvo, peca = atual, None
        elif tipo == "N":
            assert atual is not None, f"linha {n}: N antes de M"
            caminho_no = resto
            pai, _, nome = caminho_no.rpartition("/")
            no = {"nome": nome, "filhos": []}
            nos[pai]["filhos"].append(no)
            nos[caminho_no] = no
            alvo, peca = no, None
        elif tipo == "P":
            assert atual is not None and alvo is not None, f"linha {n}: P fora de modelo"
            nome, malha, x, y, z, giro, sx, sy, sz, marcas, material = campos
            peca = {
                "nome": nome,
                "malha": malha,
                "pos": [float(x), float(y), float(z)],
                "giro": float(giro),
                "tamanho": [float(sx), float(sy), float(sz)],
                "marcas": "" if marcas == "-" else marcas,
                "material": None if material == "-" else material,
                "escala": atual["escala"],
            }
            alvo["filhos"].append(peca)
        elif tipo == "S":
            assert peca is not None, f"linha {n}: S sem peça"
            cor, normal, rug, metal, alfa, rgb = campos
            peca["sa"] = {"cor": cor, "normal": normal, "rug": rug, "metal": metal, "alfa": alfa}
            peca["sa_cor"] = [float(v) for v in rgb.split(",")]
        elif tipo == "C":
            assert peca is not None, f"linha {n}: C sem peça"
            peca["cor"] = [float(v) for v in resto.split(",")]
        else:
            raise SystemExit(f"{caminho.name}:{n}: linha desconhecida {tipo!r}")
    return modelos


def atributos(valores: dict) -> dict:
    """Atributos no formato que o Rojo 7.4 grava: tipados, dentro de Properties (no topo do
    .model.json ele aceita e ignora em silêncio, conferido no Lune)."""
    tipado = {}
    for k, v in valores.items():
        if isinstance(v, bool):
            tipado[k] = {"Bool": v}
        elif isinstance(v, str):
            tipado[k] = {"String": v}
        else:
            raise SystemExit(f"atributo {k}: tipo {type(v).__name__} sem formato")
    return {"Attributes": tipado}


def rojo_peca(p: dict) -> dict:
    m = p["marcas"]
    colide = "c" in m
    props: dict = {
        "MeshId": f"rbxassetid://{p['malha']}",
        # o importador cria a peça no tamanho da malha; o modelo foi escalado por `escala`
        "InitialSize": [round(v / p["escala"], 4) for v in p["tamanho"]],
        "Size": p["tamanho"],
        "CFrame": {"CFrame": cframe(*p["pos"], p["giro"])},
        "Anchored": True,
        "CanCollide": colide,
        "CanQuery": "q" in m,
        "CanTouch": "h" in m,
        "CastShadow": "s" in m,
        "Transparency": 1 if "t" in m else 0,
        "CollisionFidelity": "Box" if colide else "Default",
    }
    if "cor" in p:
        props["Color"] = p["cor"]
    if p["material"]:
        props["Attributes"] = atributos({"Material": p["material"]})
    no: dict = {"Name": p["nome"], "ClassName": "MeshPart", "Properties": props}
    if "sa" in p:
        sa = p["sa"]
        sp: dict = {"AlphaMode": sa["alfa"]}
        for campo, chave in (
            ("ColorMap", "cor"),
            ("NormalMap", "normal"),
            ("RoughnessMap", "rug"),
            ("MetalnessMap", "metal"),
        ):
            if sa[chave]:
                sp[campo] = f"rbxassetid://{sa[chave]}"
        if p["sa_cor"] != [1.0, 1.0, 1.0]:
            # tinta das casas (AssetLoader.tintModel): não testada no Rojo 7.4; recusa até testar
            raise SystemExit(f"{p['nome']}: SurfaceAppearance.Color fora do branco")
        sa_no = {"Name": "SurfaceAppearance", "ClassName": "SurfaceAppearance", "Properties": sp}
        no["Children"] = [sa_no]
    return no


def rojo_no(n: dict) -> dict:
    filhos = [rojo_no(f) if "malha" not in f else rojo_peca(f) for f in n["filhos"]]
    return {"Name": n["nome"], "ClassName": "Model", "Children": filhos}


def rojo_modelo(m: dict) -> dict:
    filhos = [rojo_no(f) if "malha" not in f else rojo_peca(f) for f in m["filhos"]]
    return {
        "ClassName": "Model",
        "Properties": {
            "LevelOfDetail": {"Enum": SLIM},
            "ModelStreamingMode": "Atomic",
            "WorldPivotData": {"OptionalCFrame": cframe(*m["pivo"], m["giro"])},
            "Attributes": atributos({"VT65Estatico": True, "VT65Chave": m["chave"]}),
        },
        "Children": filhos,
    }


def pecas(n: dict) -> int:
    return sum(pecas(f) if "malha" not in f else 1 for f in n["filhos"])


def main() -> None:
    # só os conjuntos ligados em ativos.json entram no place: sem o Team Create o SLIM não é gerado
    # e a cópia fixa só traria a diferença de luz por dentro (D-155)
    ativos = json.loads((ENTRADA / "ativos.json").read_text("utf-8"))
    modelos: list[dict] = []
    for nome in ativos:
        modelos += ler(ENTRADA / f"{nome}.txt")
    for arq in sorted(ENTRADA.glob("*.txt")):
        ler(arq)  # confere também os desligados
    SAIDA.mkdir(parents=True, exist_ok=True)
    (SAIDA / ".gitkeep").write_text("", "utf-8")
    for velho in SAIDA.glob("*.model.json"):
        velho.unlink()
    for i, m in enumerate(modelos, 1):
        arq = SAIDA / f"{i:02d}_{m['chave']}.model.json"
        arq.write_text(json.dumps(rojo_modelo(m), ensure_ascii=False, indent=1) + "\n", "utf-8")
    ls = [
        "--!strict",
        "-- GERADO por tools/estatico.py (D-155). Não edite à mão: rode o script de novo.",
        "-- Arte fixa no arquivo do place (SLIM): chave e pivô de cada modelo de",
        "-- src/Workspace/Estatico. O AssetLoader não põe a cópia de mesma chave cujo pivô cai a",
        "-- menos de StaticArt.TOL studs (e devolve a fixa no lugar).",
        "",
        "export type Entry = { key: string, x: number, y: number, z: number }",
        "",
        "local StaticArt = {}",
        "StaticArt.TOL = 1",
    ]
    if modelos:
        ls.append("StaticArt.items = {")
        for m in modelos:
            x, y, z = m["pivo"]
            ls.append(f'\t{{ key = "{m["chave"]}", x = {x}, y = {y}, z = {z} }},')
        ls.append("} :: { Entry }")
    else:
        ls.append("StaticArt.items = {} :: { Entry }")  # o formato do StyLua para a lista vazia
    ls += ["", "return StaticArt", ""]
    MODULO.write_text("\n".join(ls), encoding="utf-8", newline="\n")
    total = sum(pecas(m) for m in modelos)
    print(f"{len(ativos)} conjuntos ligados: {len(modelos)} modelos fixos, {total} peças")


if __name__ == "__main__":
    main()
