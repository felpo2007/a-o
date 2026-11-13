"""Bases dos dois lados no mapa (lote de 2026-11-13): layouts do agente do Blender -> dados do jogo.

Lê assets/blender/bases/layout_us.json e layout_vc.json (posições relativas ao centro da base, em
studs, com chave, giro e nós) e o metricas.json de cada objeto (colisão por nó, extras como o pino
da cancela e as saídas de fumaça da cozinha). Escreve:
  src/ServerStorage/VT65Build/Data/Bases.luau  o que o jogo usa (ArtPlan, AssetLoader, MapLife,
                                               SpawnService, TrainingService)
  tools/bases_mapa.json                        o que o crop_world precisa para as estradas (entrada
                                               de cada base e a área ocupada), sem ler o Luau
assets/blender fica fora do Git: os dois arquivos gerados vão para o Git, e o resto do pipeline não
depende da pasta. Posições continuam relativas ao QG (MapConfig.HQ): se o QG mudar, a base vai
junto.

Uso (a partir de vantuong65/): uv run python tools/bases_dados.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BLENDER = ROOT / "assets/blender"
SAIDA = ROOT / "src/ServerStorage/VT65Build/Data/Bases.luau"
MAPA = ROOT / "tools/bases_mapa.json"
STUD = 0.28

# Peças com patamar aberto no terreno (PLATFORM no AssetLoader: barracas, bunker, garagem e baias).
# Na varredura (tools/varredura.luau) a concertina, o conex e as redes ficavam até 0,8 m enterrados
# de um lado, na rampa entre os patamares vizinhos: toda peça da base ganha o seu, menos as pequenas
# que assentam no chão mais baixo da pegada (estaca, placa, alvo, galão, pote, boca de túnel).
SEM_PATAMAR = {
    "tunnel_entrance",
    "rice_sack",
    "ammo_crate",
    "water_jar",
    "us_range_target",
    "vc_range_target",
    "us_range_sign",
    "us_jerrycans",
}
# distância do alvo de cada base (nó Silhueta com RangeTarget), do layout
ALVO_M = {"US": 25, "VC": 23}
LARGURA_TRILHA_M = 3.0


def n(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".") if abs(v) > 1e-9 else "0"


def metricas(chave: str) -> dict | None:
    p = BLENDER / chave / "metricas.json"
    return json.loads(p.read_text("utf-8")) if p.is_file() else None


def main() -> None:
    bases = {}
    for f, arq in (("US", "layout_us.json"), ("VC", "layout_vc.json")):
        bases[f] = json.loads((BLENDER / "bases" / arq).read_text("utf-8"))
    chaves = sorted({it["chave"] for b in bases.values() for it in b["itens"]})
    met = {k: metricas(k) for k in chaves}
    # casas únicas da vila (Blender, 2026-11-13): colisão por nó e a porta principal
    casas = [f"vila_casa_{i:02d}" for i in range(1, 13)]
    met_casa = {k: m for k in casas if (m := metricas(k))}

    out = [
        "--!strict\n",
        "-- GERADO por tools/bases_dados.py a partir dos layouts do Blender (assets/blender/bases)"
        " e do\n",
        "-- metricas.json de cada objeto. Não editar.\n",
        "-- Posições em studs a partir do QG da facção (MapConfig.HQ): +X leste, +Z sul. yaw: rad"
        " do\n",
        "-- CFrame.Angles(0, yaw, 0) = -rumo (a frente do modelo em -Z depois do importador,"
        " D-58:\n",
        "-- conferir no Studio). padded: patamar aberto no terreno. node: a placa que fica"
        ' ("" = todas).\n',
        '-- inside: id da peça que contém esta ("" = nenhuma; caixote e saco de arroz).\n',
        "return {\n",
    ]
    mapa = {}
    for f, b in bases.items():
        out.append(f"\t{f} = {{\n\t\titems = {{\n")
        for it in b["itens"]:
            campos = [
                f'key = "{it["chave"]}"',
                f'id = "{it["id"]}"',
                f"x = {n(it['x_studs'])}",
                f"z = {n(it['z_studs'])}",
                f"yaw = {math.radians(it['yaw_graus']):.4f}".rstrip("0").rstrip("."),
            ]
            # todos os campos em todo item (o tipo da tabela no --!strict); "" = sem
            pad = it["chave"] not in SEM_PATAMAR and not it.get("dentro_de")
            campos.append(f"padded = {'true' if pad else 'false'}")
            campos.append(f'node = "{it.get("no") or ""}"')
            campos.append(f'inside = "{it.get("dentro_de") or ""}"')
            out.append("\t\t\t{ " + ", ".join(campos) + " },\n")
        out.append("\t\t},\n")
        sp = b["pontos_de_spawn_studs"]
        out.append("\t\tspawns = { " + ", ".join(f"{n(x)}, {n(z)}" for x, z in sp) + " },\n")
        out.append("\t\tvehicles = {\n")
        for tipo, lista in b["veiculos_studs"].items():
            if tipo == "obs":
                continue
            nome = {"carros_na_garagem": "car", "carro": "car"}.get(tipo, tipo)
            for x, z in lista:
                out.append(f'\t\t\t{{ kind = "{nome}", x = {n(x)}, z = {n(z)} }},\n')
        out.append("\t\t},\n")
        a = b["area"]
        area = [a["x_min_m"] / STUD, a["x_max_m"] / STUD, a["z_min_m"] / STUD, a["z_max_m"] / STUD]
        out.append(
            "\t\tarea = { "
            f"minX = {n(area[0])}, maxX = {n(area[1])}, minZ = {n(area[2])}, maxZ = {n(area[3])}"
            " },\n"
        )
        if "estrada" in b:
            e = b["estrada"]
            via = {"kind": "rua", "a": e["de_studs"], "b": e["ate_studs"], "w": e["largura_m"]}
        else:
            e = b["trilha"]
            via = {"kind": "trilha", "a": e["de_studs"], "b": e["ate_studs"], "w": LARGURA_TRILHA_M}
        out.append(
            f'\t\t-- {via["kind"]} da base ({via["w"]:g} m): a ponta "a" é a entrada, onde chega a '
            "estrada do mapa\n"
            f'\t\troad = {{ kind = "{via["kind"]}", ax = {n(via["a"][0])}, az = {n(via["a"][1])}, '
            f"bx = {n(via['b'][0])}, bz = {n(via['b'][1])}, widthM = {via['w']:g} }},\n"
        )
        c = b["campo_de_tiro"]
        (x1, z1), (x2, z2) = c["linha_studs"]
        d = c["direcao"]
        dx, dz = (
            (0, 1)
            if "sul" in d
            else (1, 0)
            if "leste" in d
            else (0, -1)
            if "norte" in d
            else (-1, 0)
        )
        out.append(
            "\t\t-- linha de tiro da base (alvos do Blender a targetM; os de 100/200/300 m ficam"
            " no\n"
            "\t\t-- TrainingService, fora da base, na mesma direção)\n"
            f"\t\trange = {{ x1 = {n(x1)}, z1 = {n(z1)}, x2 = {n(x2)}, z2 = {n(z2)}, "
            f"dirX = {dx}, dirZ = {dz}, targetM = {ALVO_M[f]} }},\n"
        )
        out.append("\t},\n")
        mapa[f] = {"entrada_studs": via["a"], "area_studs": area, "via": via}

    # colisão por nó: "para" = a bala para (CanQuery); material = atributo Material
    out.append(
        "\t-- colisão de cada objeto: nó -> { stop = a bala para, material = atributo Material }\n"
    )
    out.append("\tnodes = {\n")
    todos = {**{k: met[k] for k in chaves}, **met_casa}
    for k, m in todos.items():
        if not m or not m.get("colisao"):
            continue
        out.append(f"\t\t{k} = {{\n")
        for col in m["colisao"]:
            stop = "true" if col["bala"] == "para" else "false"
            mat = col["material"] or ""
            out.append(f'\t\t\t["{col["no"]}"] = {{ stop = {stop}, material = "{mat}" }},\n')
        out.append("\t\t},\n")
    out.append("\t},\n")
    # extras: pino e eixo da cancela, saídas de fumaça da cozinha (studs no quadro do modelo)
    out.append("\t-- extras do metricas.json (studs no quadro do modelo, origem no meio da base)\n")
    out.append("\textras = {\n")
    for k in chaves:
        m = met[k]
        ex = (m or {}).get("extras") or {}
        campos = []
        if "cancela_pivo_studs" in ex:
            p = ex["cancela_pivo_studs"]
            campos.append(f"gatePivot = {{ {', '.join(n(v) for v in p)} }}")
            campos.append(f'gateAxis = "{ex["cancela_eixo_roblox"]}"')
        if "fumaca_saidas_studs" in ex:
            pts = ", ".join(
                "{ " + ", ".join(n(v) for v in p) + " }" for p in ex["fumaca_saidas_studs"]
            )
            campos.append(f"smoke = {{ {pts} }}")
        if campos:
            out.append(f"\t\t{k} = {{ {', '.join(campos)} }},\n")
    out.append("\t},\n")
    # porta principal de cada casa única (normal para fora, no quadro do modelo no Roblox): o plano
    # gira a casa para a porta olhar a rua
    out.append(
        "\t-- casas únicas da vila: normal para fora da porta principal (quadro do modelo, X e Z)\n"
    )
    out.append("\thouseDoors = {\n")
    for k, m in met_casa.items():
        portas = [p for p in m.get("portas") or [] if not p.get("interna")]
        if portas:
            nx, _, nz = portas[0]["normal_para_fora_roblox"]
            out.append(f"\t\t{k} = {{ {n(nx)}, {n(nz)} }},\n")
    out.append("\t},\n}\n")
    SAIDA.write_text("".join(out), encoding="utf-8", newline="\n")
    MAPA.write_text(json.dumps(mapa, ensure_ascii=False, indent=1), encoding="utf-8", newline="\n")

    # números para o ArtBudget (TRIS e DIMS, do metricas.json)
    print("-- TRIS")
    for k, m in todos.items():
        if m:
            print(f"\t{k} = {m['novo']['triangulos']},")
    print("-- DIMS")
    for k, m in todos.items():
        if m:
            dx_, dy_, dz_ = m["novo"]["dim_studs_xyz"]
            print(f"\t{k} = {{ {dx_}, {dy_}, {dz_} }},")
    print(f"gravado {SAIDA.relative_to(ROOT)} e {MAPA.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
