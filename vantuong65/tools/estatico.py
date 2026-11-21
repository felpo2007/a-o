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

D-168: as construções de peças do MapLife (pagode, casa comunal, bancas, serraria, cais...) vêm em
linhas `B` (Part, WedgePart ou CornerWedgePart com o CFrame inteiro, o material e a cor). O modelo
se chama `Vila_<tipo>` e o pivô é o centro da base (MapLife.villagePart), que o AssetLoader procura.

D-169: casa que se repete vem em linha `I <chave> <x> <y> <z> <giro> <escala>`, uma instância do
molde de mesma chave (o primeiro `M` dela nos arquivos de `assets/estatico`). As casas únicas da
vila são clones do mesmo modelo, sem tinta: só mudam o pivô, o giro em Y e a escala.

D-235: a expansão (`expansao.txt`) entra só com as malhas visíveis. A colisão, as luzes e o piso que
some de longe ficam no modelo do jogo (`Map.Art.ExpansaoColisao`), porque a rampa da escada e as
águas do telhado virariam blocos com `CollisionFidelity = Box`.

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
BLOCOS = {"Part", "WedgePart", "CornerWedgePart"}  # D-168: peças comuns aceitas nas linhas B
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
        elif tipo == "I":
            # D-169: instância de um molde (resolvida em `instanciar`, depois de ler os arquivos)
            chave, x, y, z, giro, escala = campos
            if chave in SO_EM_JOGO:
                raise SystemExit(f"{caminho.name}:{n}: {chave} depende do jogo rodando (MapLife)")
            modelos.append(
                {
                    "chave": chave,
                    "pivo": [float(x), float(y), float(z)],
                    "giro": float(giro),
                    "escala": float(escala),
                    "instancia": True,
                    "filhos": [],
                }
            )
            atual, alvo, peca = None, None, None
        elif tipo == "B":
            assert atual is not None and alvo is not None, f"linha {n}: B fora de modelo"
            if len(campos) != 22:
                raise SystemExit(f"{caminho.name}:{n}: linha B com {len(campos)} campos (eram 22)")
            classe, forma, nome = campos[:3]
            num = [float(v) for v in campos[3:18]]
            marcas, material, mat_enum, rgb = campos[18:]
            if classe not in BLOCOS:
                raise SystemExit(f"{caminho.name}:{n}: peça {classe} fora de {sorted(BLOCOS)}")
            peca = {
                "nome": nome,
                "classe": classe,
                "forma": None if forma == "-" else forma,
                "pos": num[0:3],
                "rot": [num[3:6], num[6:9], num[9:12]],
                "tamanho": num[12:15],
                "marcas": "" if marcas == "-" else marcas,
                "material": None if material == "-" else material,
                "mat_roblox": mat_enum,
                "cor": [float(v) for v in rgb.split(",")],
            }
            alvo["filhos"].append(peca)
            peca = None  # S e C são só de peça de malha
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


def _girar(x: float, z: float, graus: float) -> tuple[float, float]:
    """O vetor (x, z) girado como CFrame.Angles(0, graus, 0) (linhas [[c,0,s],[0,1,0],[-s,0,c]])."""
    r = math.radians(graus)
    c, s = math.cos(r), math.sin(r)
    return c * x + s * z, -s * x + c * z


def _copiar_no(n: dict, molde: dict, inst: dict) -> dict:
    """D-169: o filho do molde levado para a instância (pivô, giro em Y e escala)."""
    if "classe" in n:
        raise SystemExit(f"molde {molde['chave']}: peça comum (linha B) em molde não é aceita")
    if "malha" not in n:
        return {"nome": n["nome"], "filhos": [_copiar_no(f, molde, inst) for f in n["filhos"]]}
    k = inst["escala"] / molde["escala"]
    px, py, pz = (n["pos"][i] - molde["pivo"][i] for i in range(3))
    lx, lz = _girar(px, pz, -molde["giro"])
    wx, wz = _girar(lx * k, lz * k, inst["giro"])
    p = dict(n)
    p["pos"] = [
        round(inst["pivo"][0] + wx, 4),
        round(inst["pivo"][1] + py * k, 4),
        round(inst["pivo"][2] + wz, 4),
    ]
    p["giro"] = round(n["giro"] - molde["giro"] + inst["giro"], 4)
    p["tamanho"] = [round(v * k, 4) for v in n["tamanho"]]
    p["escala"] = inst["escala"]
    return p


def instanciar(modelos: list[dict], moldes: dict[str, dict]) -> list[dict]:
    """D-169: troca cada linha I pelo molde da mesma chave, levado ao pivô dela."""
    out = []
    for m in modelos:
        if not m.get("instancia"):
            out.append(m)
            continue
        molde = moldes.get(m["chave"])
        if molde is None:
            raise SystemExit(f"instância de {m['chave']} sem molde em assets/estatico")
        novo = {k: m[k] for k in ("chave", "pivo", "giro", "escala")}
        novo["filhos"] = [_copiar_no(f, molde, m) for f in molde["filhos"]]
        out.append(novo)
    return out


def _desloca(n: dict, d: list[float]) -> dict:
    """Cópia da peça ou do submodelo levada por `d` (construção de peças, sem escala)."""
    if not folha(n):
        return {"nome": n["nome"], "filhos": [_desloca(f, d) for f in n["filhos"]]}
    p = dict(n)
    p["pos"] = [round(n["pos"][i] + d[i], 4) for i in range(3)]
    return p


def ajustar(modelos: list[dict], ajuste: dict[str, dict]) -> list[dict]:
    """D-236: leva cada casa ao novo pivô e à escala (tools/casas_escala.luau), sem recopiar."""
    out = []
    for m in modelos:
        x, y, z = m["pivo"]
        a = ajuste.get(f"{m['chave']}|{x:.3f}|{y:.3f}|{z:.3f}")
        if a is None:
            out.append(m)
            continue
        if a.get("fora"):
            continue  # anexo que ficou sem lugar ao lado da casa maior
        novo = {
            "chave": m["chave"],
            "pivo": [a["x"], a["y"], a["z"]],
            "giro": m["giro"],
            "escala": round(m["escala"] * a["f"], 5),
        }
        if abs(a["f"] - 1) < 1e-6:
            d = [a["x"] - x, a["y"] - y, a["z"] - z]
            novo["filhos"] = [_desloca(f, d) for f in m["filhos"]]
        else:
            novo["filhos"] = [_copiar_no(f, m, novo) for f in m["filhos"]]
        out.append(novo)
    return out


def moldes_de(arquivos: list[Path]) -> dict[str, dict]:
    """O primeiro M de cada chave, na ordem dos arquivos."""
    moldes: dict[str, dict] = {}
    for arq in arquivos:
        for m in ler(arq):
            if not m.get("instancia"):
                moldes.setdefault(m["chave"], m)
    return moldes


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


def rojo_bloco(p: dict) -> dict:
    """D-168: peça comum. O CFrame vai inteiro (linhas da matriz, como no `orientacao`)."""
    m = p["marcas"]
    props: dict = {
        "Size": p["tamanho"],
        "CFrame": {"CFrame": {"position": p["pos"], "orientation": p["rot"]}},
        "Anchored": True,
        "CanCollide": "c" in m,
        "CanQuery": "q" in m,
        "CanTouch": "h" in m,
        "CastShadow": "s" in m,
        "Transparency": 1 if "t" in m else 0,
        "Material": p["mat_roblox"],
        "Color": p["cor"],
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
    }
    if p["classe"] == "Part" and p["forma"]:
        props["Shape"] = p["forma"]
    if p["material"]:
        props["Attributes"] = atributos({"Material": p["material"]})
    return {"Name": p["nome"], "ClassName": p["classe"], "Properties": props}


def folha(f: dict) -> bool:
    """Peça (de malha ou comum), não submodelo."""
    return "malha" in f or "classe" in f


def rojo_filho(f: dict) -> dict:
    if "classe" in f:
        return rojo_bloco(f)
    return rojo_peca(f) if "malha" in f else rojo_no(f)


def rojo_no(n: dict) -> dict:
    filhos = [rojo_filho(f) for f in n["filhos"]]
    return {"Name": n["nome"], "ClassName": "Model", "Children": filhos}


def rojo_modelo(m: dict) -> dict:
    filhos = [rojo_filho(f) for f in m["filhos"]]
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
    return sum(1 if folha(f) else pecas(f) for f in n["filhos"])


def main() -> None:
    # só os conjuntos ligados em ativos.json entram no place: sem o Team Create o SLIM não é gerado
    # e a cópia fixa só traria a diferença de luz por dentro (D-155)
    ativos = json.loads((ENTRADA / "ativos.json").read_text("utf-8"))
    modelos: list[dict] = []
    for nome in ativos:
        modelos += ler(ENTRADA / f"{nome}.txt")
    for arq in sorted(ENTRADA.glob("*.txt")):
        ler(arq)  # confere também os desligados
    # D-169: os moldes vêm primeiro dos ligados (na ordem de ativos.json), depois dos outros
    arquivos = [ENTRADA / f"{nome}.txt" for nome in ativos] + sorted(ENTRADA.glob("*.txt"))
    modelos = instanciar(modelos, moldes_de(arquivos))
    arq_ajuste = ENTRADA / "ajuste_casas.json"
    if arq_ajuste.exists():
        modelos = ajustar(modelos, json.loads(arq_ajuste.read_text("utf-8")))
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
