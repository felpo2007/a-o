"""Seções do RELATORIO.md para os veículos em partes (Tarefa C) e o ghillie v2 (Tarefa D).

Chamado por `relatorio.py` (só a biblioteca padrão). Números dos `metricas.json` de
`veiculos.py`, `tools/ghillie2.py` e `comparar.py`/`ghillie2.py`; veredictos = leitura das imagens.
"""

from __future__ import annotations

import json
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
SAIDA = RAIZ / "assets" / "blender"

VEICULOS = ["m48a3", "ontos", "lvtp5", "uh34d", "m151", "m35", "peugeot403"]

# chave -> (vencedor, onde o novo perdeu / observação). Preenchido olhando comparacao.png.
VEREDICTOS_V: dict[str, tuple[str, str]] = {
    "m48a3": (
        "novo (por pouco)",
        "o antigo tem mais tralha moldada (sacos e caixas no cesto, a .50 por cima da cúpula); no "
        "novo a .50 fica na cúpula M1 como de fábrica e a lagarta de perto é mais lisa",
    ),
    "ontos": (
        "novo (forma e peças)",
        "o antigo tem mais detalhe moldado na chapa (dobradiças, alças, grades); o novo segue as "
        "medidas e ângulos da afvdatabase, mas a chapa é lisa e o casco parece mais largo e baixo",
    ),
    "lvtp5": (
        "novo (forma e peças)",
        "sem os corrimãos e as alças do teto que o antigo tem; lateral lisa",
    ),
    "uh34d": (
        "antigo (no visual)",
        "o novo tem as medidas da ficha (rotor de 17 m, 4 pás, cauda com rotor de 4 pás), as peças "
        "móveis, cabine e porão com forro e só 4,8 mil tri, mas a fuselagem é mais lisa (sem "
        "molduras de janela nem portinholas) e o antigo, mesmo fora de escala, convence mais de "
        "perto",
    ),
    "m151": (
        "novo (não existe hoje)",
        "rodas e capô um pouco quadrados; o vidro do para-brisa tem manchas de poeira fortes "
        "demais",
    ),
    "m35": (
        "novo (não existe hoje)",
        "cabine e grade simples; caçamba só com os arcos (sem a lona)",
    ),
    "peugeot403": (
        "novo (não existe hoje)",
        "carroceria mais quadrada que a do 403 (cantos de 7 cm); as medidas da picape são da perua "
        "(PLACEHOLDER); poeira forte no capô",
    ),
}
VEREDICTO_GHILLIE: tuple[str, str] = (
    "v2",
    "Cobre tronco, braços e pernas com tiras e folhas em 3 camadas e esconde a silhueta; na 1ª "
    "pessoa a v1 punha capim na frente da câmera e a v2 não põe nada. Onde perde: a cabeça só tem "
    "capuz em cima, dos lados e atrás (regra do rosto + caixa da v1), então de frente o rosto "
    "fica à "
    "mostra; a tira de juta do arrozal parece palha lisa de longe; 2,4x os triângulos da v1",
)
NOTAS = """
## Tarefas C e D: o que subir

Nada foi subido. Prontos para o `assets/upload_plan.json` (GLB em studs, Y para cima, pivô na
base, nariz em +X do GLB como os antigos; os veículos têm metal só no aço das lascas e da lagarta:
NÃO passar pelo `tools/matte_glb.py`):

- trocar o ID: `m48a3`, `ontos`, `lvtp5`, `uh34d` (`assets/blender/<chave>/<chave>.glb`);
- novos: `m151`, `m35` (EUA) e `peugeot403` (VC);
- ghillie: `assets/blender/ghillie/ghillie.glb` no lugar de `AssetIds.Accessories.ghillie`, e
  `assets/ghillie/ghillie2_arroz.png`, `ghillie2_selva.png`, `ghillie2_bambu.png` no lugar de
  `AssetIds.Images.ghillie_rice`, `ghillie_jungle`, `ghillie_bamboo`. O `Skins.GHILLIE` não muda
  (mesmas caixas); só os `tris` informativos ficam velhos.

## Tarefas C e D: o que o código precisa (não feito: o pedido proibia editar Luau)

1. `VehicleDrive.ART`: colar a tabela acima no mesmo commit da troca do ID. Sem ela o código
   escala os números velhos por Size/box (a conferência acima diz onde isso erra).
2. Modelo em partes: o "Casco" é a maior peça (as 2 âncoras minúsculas deixam a caixa dele igual
   à do veículo inteiro), então `mainPart`, `meshRel` e `scale` continuam certos. O
   `VehicleService` hoje solda TODAS as peças na ArtRoot; para animar:
   - `Torre`: Motor6D Casco→Torre, giro em Y no pivô; `Cano`: Motor6D Torre→Cano, giro no eixo
     lateral (Z do referencial do ART) no munhão;
   - `Roda_*`: giro no eixo lateral, ω = v / r (raios na tabela `track.circles` e nas rodas dos
     carros); rodas da frente dos carros também esterçam em Y no pivô; `Volante` gira no eixo da
     coluna;
   - `Esteira_E/D`: malha parada; as faixas animadas do `VehicleFx` continuam por cima (zIn/zOut
     novos) ou o código esconde as faixas e aceita a lagarta parada;
   - UH-34D: `RotorPrincipal` (cubo) gira em Y; `Pa_1..Pa_4` (a mesma malha 4 vezes) precisam ser
     soldadas no cubo; `RotorCauda` gira no eixo lateral; o disco e as pás de peça do
     `VehicleFx` ficam só para o desfoque em alta rotação;
   - `Escotilha_*`: dobradiça no pivô (a do UH-34D, `Escotilha_Porta`, corre em X);
     `Escotilha_Rampa` do LVTP-5 gira no eixo lateral da dobradiça de baixo.
   Os pivôs vão como translação de cada nó do GLB; se o importador não puser no PivotOffset, os
   valores estão na tabela "Nomes das partes" e em `metricas.json` (`novo.partes`).
3. Carros novos em `Vehicles.SPECS` (tipo novo "wheeled": o `VehicleDrive` hoje só tem lagarta e
   anfíbio, e o carro precisa de esterço nas rodas da frente):
   - `m151` (US): 1.100 kg em ordem de marcha, 71 hp, 3,37 × 1,63 × 1,80 m (Wikipedia M151 MUTT);
     velocidade máxima sem fonte (PLACEHOLDER); motorista, carona e 2 atrás;
   - `m35` (US): 6.750 kg vazio com guincho, REO OA-331 de 127 hp, 93 km/h no infobox (90 km/h no
     texto) (Wikipedia M35); motorista, carona e 12 na caçamba;
   - `peugeot403` (VC): 1,5 L de 58–65 hp (Wikipedia Peugeot 403); massa e velocidade sem fonte
     (PLACEHOLDER); motorista, carona e 6 sob a lona.
4. Lados: "só os EUA têm carros, tanques e helicóptero; o Vietnã só tem carros". Hoje o
   `VehicleService` usa `MapConfig.HQ.US` para todos os depósitos: precisa de depósitos por lado
   (US: lvtp5, m48a3, ontos, uh34d, m151, m35; VC: peugeot403 no `MapConfig.HQ.VC`) e de recusar
   o assento a quem é do outro lado (`Vehicles.SPECS[..].faction`).
5. `ArtBudget`: `KIND` "hero" para m151, m35 e peugeot403 e os `TRIS` novos (tabela acima;
   instâncias contadas); `AssetIds.Models` com as chaves novas.
6. Giro e frente REAIS dos GLB (conferido nos nós: as `Roda_F*` têm x > 0 e a `Roda_*E` e o
   `Volante` têm z < 0): frente = +X do GLB, em cima = +Y, esquerda (lado do motorista) = −Z do
   GLB, pivô no centro da caixa no chão. É a mesma convenção dos 4 blindados antigos: depois do
   giro de 180° em Y do importador a frente fica em −X e a esquerda em +Z da MeshPart, e o
   `ART_YAW` do chassi é −90° (frente do chassi = −Z), o mesmo que o agente de veículos estimou
   para os carros. Os nomes das rodas são os que o código dos carros já usa (`Roda_FE`, `Roda_FD`,
   `Roda_TE`, `Roda_TD`; no M35 `Roda_T1E/T1D/T2E/T2D`).
7. UH-34D: os 8 assentos de passageiro que o `VehicleService` cria (±W·0,25 com W = 4,0 m)
   caem fora da fuselagem nova (1,68 m de largura): trazer para ±0,5 m (o olho já está no ART
   `riders`). No UH-34D e no Peugeot o olho do motorista fica DENTRO da cabine fechada: de dentro a
   casca some (face única) e aparecem o forro, o painel, o banco e o volante; não é preciso pôr o
   olho para fora como nos blindados.
8. Soldado de 2,0 m: os olhos do ART são pontos fixos (não dependem do corpo). Para a cabeça de
   um soldado de 2 m, os olhos sentados sobem ~0,11 m (coluna "soldado de 2,0 m" acima); onde a
   folga ao teto fica negativa, manter o olho atual (ele se encolhe) ou baixar o assento. As
   escotilhas que não passam ombros de 0,53 m estão marcadas; as medidas delas são PLACEHOLDER.

## Tarefas C e D: limites (o que NÃO foi medido)

- Tudo é render do Blender. Parte dos bakes foi feita na CPU (o dono estava jogando: `VT65_CPU=1`,
  4 linhas, prioridade ociosa) ou com o bake leve (`VT65_BAKE_RAPIDO=1`: 1 amostra nos mapas de
  material e a oclusão em meia resolução com 32 amostras, ampliada e borrada), porque 3 a 4
  Blenders de outros agentes rodavam juntos e a oclusão de um atlas chegou a 22 min. Com a GPU
  livre dá para refazer tudo com mais amostras: `uv run python tools/blender/lote.py --tarefa V`.
- Nada foi aberto no Studio: o importador do Roblox com nós em várias peças, os pivôs (translação
  do nó) e a instância de malha (rodas e pás) não foram conferidos lá.
- A pintura é procedural (olive drab com lascas, poeira e lama): o tom exato do USMC de 1965 e
  as marcações (números e cor) são PLACEHOLDER onde está dito.
"""


def fmt(n: float, casas: int = 0) -> str:
    s = f"{n:,.{casas}f}"
    return s.replace(",", "X").replace(".", ",").replace("X", ".")


def ler(chave: str) -> dict | None:
    arq = SAIDA / chave / "metricas.json"
    return json.loads(arq.read_text("utf-8")) if arq.is_file() else None


def luau_num(x: float) -> str:
    s = f"{x:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def luau_vec(v) -> str:
    return "{ " + ", ".join(luau_num(x) for x in v) + " }"


def bloco_art(chave: str, art: dict) -> list[str]:
    """Tabela ART pronta para colar no `VehicleDrive.ART` (referencial da malha nova)."""
    ln = [f"\t{chave} = {{", f"\t\tbox = {luau_vec(art['box'])},"]
    if "track" in art:
        t = art["track"]
        cs = ", ".join(luau_vec(c) for c in t["circles"])
        ln += [
            "\t\ttrack = {",
            f"\t\t\tzIn = {luau_num(t['zIn'])},",
            f"\t\t\tzOut = {luau_num(t['zOut'])},",
            f"\t\t\tcircles = {{ {cs} }},",
            f"\t\t\tbars = {t['bars']},",
            "\t\t},",
        ]
    if art.get("exhaust"):
        ln.append(f"\t\texhaust = {{ {', '.join(luau_vec(e) for e in art['exhaust'])} }},")
    for k in ("rotor", "tail"):
        if k in art:
            r = art[k]
            ln.append(
                f"\t\t{k} = {{ x = {luau_num(r['x'])}, y = {luau_num(r['y'])}, "
                f"z = {luau_num(r['z'])}, r = {luau_num(r['r'])} }},"
            )
    if art.get("eyes"):
        ln.append("\t\teyes = {")
        for s, v in art["eyes"].items():
            ln.append(f"\t\t\t{s} = {luau_vec(v)},")
        ln.append("\t\t},")
    if "riders" in art:
        r = art["riders"]
        ln.append(
            f"\t\triders = {{ x0 = {luau_num(r['x0'])}, dx = {luau_num(r['dx'])}, "
            f"y = {luau_num(r['y'])}, z = {luau_num(r['z'])} }},"
        )
    ln.append("\t},")
    return ln


def tabela() -> list[str]:
    linhas = [
        "| veículo | antigo: tri · MB · textura | novo: tri · MB · texturas | medidas do novo (m) "
        "| silhueta (IoU) | vencedor | onde o novo perdeu |",
        "|---|---|---|---|---|---|---|",
    ]
    for k in VEICULOS:
        m = ler(k)
        if not m:
            linhas.append(f"| {k} | — | não feito | | | | |")
            continue
        a, n = m.get("antigo", {}), m["novo"]
        if m["tipo"] == "refeito":
            tx = a["texturas_px"]["cor"][0]
            ant = f"{fmt(a['triangulos'])} · {fmt(a['mb'], 1)} · {tx} (1 malha)"
        else:
            ant = "não existe no jogo"
        nov = (
            f"{fmt(n['triangulos'])} · {fmt(n['mb'], 1)} · {n['texturas']} x "
            f"{n['texturas_px']['cor'][0]} ({len(n['partes'])} nós)"
        )
        dims = " × ".join(fmt(x, 2) for x in n["dim_m_xyz"])
        iou = m.get("comparacao", {}).get("silhueta_iou", [])
        iou_t = " / ".join(fmt(x, 2) for x in iou) if m["tipo"] == "refeito" else "—"
        v, obs = VEREDICTOS_V.get(k, ("?", ""))
        linhas.append(f"| {m['nome']} (`{k}`) | {ant} | {nov} | {dims} | {iou_t} | {v} | {obs} |")
    return linhas


def fontes() -> list[str]:
    out = []
    for k in VEICULOS:
        m = ler(k)
        if not m:
            continue
        out.append(f"- **{m['nome']}**:")
        for nome, (val, fonte) in m["medidas_reais"].items():
            vtxt = "" if val is None else f" = {val}"
            out.append(f"  - {nome}{vtxt}: {fonte}")
    return out


def partes() -> list[str]:
    out = [
        "| veículo | nós no GLB (tri) | pivôs que o código usa (studs, referencial do ART) |",
        "|---|---|---|",
    ]
    for k in VEICULOS:
        m = ler(k)
        if not m:
            continue
        ps = m["novo"]["partes"]
        nos = ", ".join(
            f"`{n}` ({p['triangulos']}{' = ' + p['instancia_de'] if 'instancia_de' in p else ''})"
            for n, p in ps.items()
        )
        piv = "; ".join(
            f"{n} {luau_vec(p['pivo_studs_roblox'])}"
            for n, p in ps.items()
            if any(n.startswith(x) for x in ("Torre", "Cano", "Rotor", "Escotilha", "Volante"))
        )
        out.append(f"| {k} | {nos} | {piv or '—'} |")
    return out


EIXOS = {
    "Roda": "gira no eixo lateral (Z do ART); as da frente (F) também esterçam em Y",
    "Porta": "dobradiça vertical (Y) na borda da frente; abre para fora",
    "Tampa_Traseira": "dobradiça lateral (Z) embaixo; abre para baixo",
    "ParaBrisa": "dobradiça lateral (Z) na base; rebate para a frente sobre o capô",
    "Volante": "gira no eixo da coluna (inclinada; ver o docstring da receita)",
}


def carros() -> list[str]:
    """Nomes claros para o agente de veículos: rodas e portas dos carros (pivô, eixo, tamanho)."""
    out = [
        "Convenção: `F`/`T` = frente/trás, `E`/`D` = esquerda/direita do veículo (esquerda = +Z no "
        "referencial do ART = lado do motorista nos três), `T1`/`T2` = 1º e 2º eixo de trás do "
        "M35. "
        "Raio = metade da maior medida da peça.",
        "",
        "| carro | peça | pivô (studs, ART) | raio / tamanho (studs) | movimento |",
        "|---|---|---|---|---|",
    ]
    for k in ("m151", "m35", "peugeot403"):
        m = ler(k)
        if not m:
            continue
        for n, p in m["novo"]["partes"].items():
            if n == "Casco":
                continue
            d = p.get("dim_studs")
            if d is None:
                tam = "—"
            elif n.startswith("Roda"):
                tam = f"r = {luau_num(max(d[0], d[1]) / 2)}"
            else:
                tam = luau_vec(d)
            mov = next((v for pre, v in EIXOS.items() if n.startswith(pre)), "")
            out.append(f"| {k} | `{n}` | {luau_vec(p['pivo_studs_roblox'])} | {tam} | {mov} |")
    out += [
        "",
        "Sem portas: o M151 é aberto (só o `ParaBrisa` rebate). No Peugeot a porta é a chapa de "
        "baixo (a janela fica na cabine) e, aberta, mostra a lateral do corpo, não um vão (o "
        "interior não foi "
        "modelado além de painel, banco e volante).",
    ]
    return out


def conferencia() -> list[str]:
    out = []
    for k in VEICULOS:
        m = ler(k)
        if not m:
            continue
        c = m["conferencia"]
        out.append(f"- **{k}**")
        olhos = c["olhos_novos"]
        if olhos:
            itens = []
            for s, o in olhos.items():
                lugar = "dentro da cabine/porão" if o["dentro_da_malha"] else "fora da malha"
                h = o["altura_sobre_o_casco_m"]
                itens.append(
                    f"{s}: {lugar}, {fmt(h, 2) if h is not None else '—'} m acima do que está "
                    "embaixo"
                )
            out.append(f"  - olhos novos (ART novo): {'; '.join(itens)}")
        velhos = c["olhos_de_hoje_escalados"]
        if velhos:
            ruins = [s for s, o in velhos.items() if o["dentro_da_malha"]]
            out.append(
                "  - olhos de hoje, escalados pelo código (Size nova / box velha): "
                + (
                    f"caem DENTRO da malha nova: {', '.join(ruins)} (casco some)"
                    if ruins
                    else "nenhum cai dentro da malha"
                )
            )
        ass = c["assentos_do_chassi"]
        if ass:
            fora = [a["assento"] for a in ass if not a["cai_sobre_o_casco"]]
            out.append(
                f"  - {len(ass)} assentos do VehicleService (topo do chassi): "
                + (f"fora do casco: {', '.join(fora)}" if fora else "todos em cima do casco novo")
            )
        s2 = c.get("soldado_2m", {})
        if s2.get("olhos"):
            itens = []
            for s, o in s2["olhos"].items():
                f = o["folga_cabeca_ao_teto_m"]
                if f is None:
                    itens.append(
                        f"{s}: sem teto em cima (cabeça fora da escotilha ou carro aberto)"
                    )
                else:
                    itens.append(
                        f"{s}: folga da cabeça ao teto {fmt(f, 2)} m{' (BATE)' if f < 0 else ''}"
                    )
            out.append(
                "  - soldado de 2,0 m (olho a 0,90 m do assento, cabeça 0,12 m acima): "
                + "; ".join(itens)
            )
        if s2.get("escotilhas"):
            itens = [
                f"{n} {fmt(e['abertura_m'][0], 2)}×{fmt(e['abertura_m'][1], 2)} m "
                f"({'passa' if e['passa_ombros_de_2m'] else 'NÃO passa'})"
                for n, e in s2["escotilhas"].items()
            ]
            out.append(f"  - escotilhas x ombros de 0,53 m: {'; '.join(itens)}")
    return out


def secao_ghillie() -> list[str]:
    m = ler("ghillie")
    if not m:
        return ["## Tarefa D: ghillie v2", "", "não feito", ""]
    a, n = m["antigo"], m["novo"]
    v, obs = VEREDICTO_GHILLIE
    linhas = [
        "## Tarefa D: camuflagem de mato v2 (ghillie)",
        "",
        "Imagens: `assets/blender/ghillie/comparacao.png` (v1 × v2, frente e costas), "
        "`variantes.png` (arrozal, mata, bambu na mesma malha) e `primeira_pessoa.png` (câmera de "
        "1ª pessoa com o corpo escondido).",
        "",
        f"Total: v1 {fmt(a['triangulos'])} tri, textura {a['texturas_px']['cor'][0]} px, "
        f"{fmt(a['mb'], 2)} MB → v2 {fmt(n['triangulos'])} tri, "
        f"textura {n['texturas_px']['cor'][0]} px, "
        f"{fmt(n['mb'], 2)} MB. Vencedor: {v}. {obs}",
        "",
        "| peça | v1 tri | v2 tri | cartões v2 (manta / tira / tufo) | caixa igual à v1 |",
        "|---|---|---|---|---|",
    ]
    for nome, p in n["por_peca"].items():
        c = p["cartoes"]
        ok = m["encaixe_v1"][nome]["ok"]
        linhas.append(
            f"| Ghillie_{nome} | {a['por_peca'].get(nome, '—')} | {p['triangulos']} | "
            f"{c['manta']} / {c['tira']} / {c['tufo']} | {'sim' if ok else 'NÃO'} |"
        )
    fp = m["primeira_pessoa_vertices_no_campo"]
    linhas += [
        "",
        f"- 1ª pessoa: vértices da v2 dentro do campo de visão (FOV 70° + 15° de folga, 16:9): "
        f"centro da cabeça {sum(fp['centro_da_cabeca'].values())}, "
        f"olho {sum(fp['olho'].values())}.",
        "- Texturas novas: "
        + ", ".join(f"`{t}`" for t in n["texturas"])
        + " (RGBA, recorte no alfa; "
        "o canto de cima à esquerda é transparente: é onde ficam as âncoras).",
        "",
    ]
    return linhas


def secoes() -> list[str]:
    corpo = [
        "## Tarefa C: veículos em partes (pedido de 2026-11-11)",
        "",
        "Refeitos do zero no Blender (`tools/blender/veiculos.py` + `veic_<chave>.py`), com "
        "medidas de fonte, pintura com desgaste, lama e poeira de laterita assadas, e as partes "
        "móveis em nós separados com nome. Imagens em `assets/blender/<chave>/comparacao.png` "
        "(esquerda = hoje; nos "
        "carros novos, um boneco de 1,75 m para escala).",
        "",
        *tabela(),
        "",
        "### Nomes das partes",
        "",
        *partes(),
        "",
        "### Carros: rodas, portas e tampas (para o agente de veículos)",
        "",
        *carros(),
        "",
        "### Conferência dos assentos e dos olhos",
        "",
        *conferencia(),
        "",
        "### Tabela ART nova (colar no `VehicleDrive.ART`)",
        "",
        "Referencial da malha nova: studs, centro da caixa, nariz em −X, esquerda em +Z.",
        "",
        "```lua",
    ]
    for k in VEICULOS:
        m = ler(k)
        if m:
            corpo += bloco_art(k, m["art_novo"])
    corpo += ["```", "", "### Fontes das medidas", "", *fontes(), ""]
    corpo += secao_ghillie()
    return corpo
