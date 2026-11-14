"""Monta `assets/blender/RELATORIO.md` a partir dos `metricas.json` do lote e dos veredictos.

Roda fora do Blender (só a biblioteca padrão):
    uv run python tools/blender/relatorio.py

Os números vêm todos dos `metricas.json` (gravados por refazer.py, novos.py e comparar.py). Os
veredictos (`VEREDICTOS`) são a leitura das imagens de comparação pelos critérios do dono:
mais bonito, mais gráfico, mais funcional e menos pesado — nessa ordem de peso, com o gráfico
em primeiro.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
SAIDA = RAIZ / "assets" / "blender"

sys.path.insert(0, str(AQUI))
from lote import TAREFA_A, TAREFA_B  # noqa: E402

# chave -> (vencedor, onde o novo perdeu / observação). Preenchido olhando comparacao.png.
VEREDICTOS: dict[str, tuple[str, str]] = {
    # Tarefa A
    "hut_thatch": ("novo", "pontas das varas do telhado um pouco mais grossas"),
    "hut_veranda": ("novo", "franja do beiral um pouco mais rala; janelas menos nítidas"),
    "hut_kitchen": ("novo", "uma sombra mais escura num painel do telhado da frente"),
    "house_tile": ("novo", "porta e veneziana um pouco menos nítidas"),
    "granary": ("novo", "pernas do jirau um pouco mais escuras"),
    "well": ("novo", "praticamente igual"),
    "shrine": ("novo", "telhas um pouco menos nítidas"),
    "grave_mound": ("novo", "capim do pé do muro mais ralo"),
    "vc_bunker": ("novo", "folhas penduradas na boca mais ralas"),
    "sandbags": ("novo", "praticamente igual"),
    "bamboo_fence": (
        "antigo (por pouco)",
        "uma ripa do meio sai rachada e com um entalhe escuro no pé (ripas finas e soltas "
        "perdem forma na redução); de longe, empata",
    ),
    "trench_section": (
        "antigo",
        "folhas de cima com manchas escuras e a cobertura de troncos do meio com vãos",
    ),
    "tunnel_entrance": ("novo", "praticamente igual"),
    "spider_hole": ("novo", "uma mancha escura pequena ao lado da tampa"),
    "log_bridge": ("novo", "um pouco mais escura; ponta do corrimão mais fina"),
    "rice_patch": (
        "antigo",
        "folhas mais escuras e manchadas: folha fina de face única não assa bem (normal e "
        "oclusão dos dois lados se misturam)",
    ),
    # Tarefa B
    "water_jar": (
        "novo",
        "perde só no peso (2 mil tri + textura 1024 contra 3 peças lisas)",
    ),
    "straw_stack": (
        "novo",
        "camadas de palha regulares demais (parece colmeia de perto); 5 mil tri contra 4 peças",
    ),
    "grenade_m26": ("novo", "bordas da alavanca com dentinhos escuros (chapa fina)"),
    "grenade_stick": ("novo", "veio do cabo parece mancha, não veio"),
    "smoke_m18": ("novo", "a alavanca dobra no topo como uma aba larga demais"),
    "ammo_crate": ("novo", "o estêncil não foi conferido num caixote real (PLACEHOLDER)"),
    "rice_sack": (
        "novo",
        "frestas pretas num canto (a dobra fina da orelha da costura abre com a redução)",
    ),
    "clay_lamp": (
        "novo",
        "o pé parece grande e o bico é discreto: forma sem referência (PLACEHOLDER)",
    ),
    "sandbag_wall": (
        "novo",
        "84 sacos em 8 mil tri: cada saco tem quinas vistas de perto; pontinhos escuros",
    ),
    "conical_hat": ("novo", "claro e limpo demais; um risco escuro numa face; sem a fita"),
    "bamboo_clothesline": (
        "novo",
        "roupa preta quase sem leitura de dobra; furinhos na camisa",
    ),
}
# texto final do relatório (o que não ficou bom e por quê, limites da comparação)
NOTAS = """
## O que subir (quando o dono decidir)

Nada foi subido. Os GLB vencedores estão em `assets/blender/<chave>/<chave>.glb`, prontos (studs,
Y para cima, pivô na base, metal 0; nas granadas o metal vem só da textura):

- trocar pelo novo (13 refeitos): hut_thatch, hut_veranda, hut_kitchen, house_tile, granary,
  well, shrine, grave_mound, vc_bunker, sandbags, tunnel_entrance, spider_hole, log_bridge;
- manter o antigo: bamboo_fence (por pouco), trench_section e rice_patch;
- novos (11): water_jar, straw_stack, grenade_m26, grenade_stick, smoke_m18, ammo_crate,
  rice_sack, clay_lamp, sandbag_wall, conical_hat, bamboo_clothesline.

Eles não precisam do `tools/matte_glb.py` (já saem foscos). Para usar: pôr no
`assets/upload_plan.json`, `uv run --env-file .env python tools/roblox_cloud.py upload-assets`,
registrar os IDs (`AssetIds.luau`, `roblox_ids.json`), o `manifest.json` e o `ArtBudget.luau`.
Os novos precisam de código no jogo para aparecer (hoje o pote, a meda, a lamparina, os sacos, o
caixote e as granadas são Parts em `MapLife.luau`/`GrenadeArt.luau`); isso não foi feito porque
o pedido proibia editar Luau.

## Como foi feito

- Refeitos (`tools/blender/refazer.py`): limpeza (duplicados, degenerados, faces internas e
  escondidas), redução (dissolução planar + colapso) para o menor alvo entre 40, 55, 75 e 100% da
  meta da classe cujo desvio fica na tolerância (média ≤ 0,05%, p95 ≤ 0,15% e p99 ≤ 0,3% da
  diagonal), UV nova (ilhas que quase não aparecem ganham menos texels), bake do original (cor,
  normal, rugosidade e oclusão; a oclusão escurece a cor porque o Roblox não tem canal de
  oclusão), metal = 0 e GLB em studs, Y para cima.
- Novos (`tools/blender/novos.py` + `modelar.py`): modelagem em bpy (torno, superelipsoide,
  tubos, bambu com nós, pano dobrado, estêncil como malha), material PBR procedural (ruído,
  Voronoi, ondas, bump), malha alta reduzida e assada pelo mesmo caminho dos refeitos. Metal só
  onde é aço nas granadas (espoleta, anel, pino e o aço da tinta gasta).
- Comparação (`tools/blender/comparar.py`): Cycles, 64 amostras com denoise, céu do jogo + sol a
  45°, face única (como MeshPart sem DoubleSided), 2 ângulos, mesmo enquadramento. O antigo usa
  as texturas reduzidas a 1024 como o Roblox faz. "Silhueta (IoU)" = sobreposição das
  silhuetas (1 = iguais).
- Lote: `uv run python tools/blender/lote.py` (tudo), `--tarefa A|B`, `--chaves a,b`,
  `--pular-feitos`, `--so-comparar`. Ele espera outro Blender liberar a GPU antes de cada etapa.
  Este relatório: `uv run python tools/blender/relatorio.py`.

## Consertos feitos no caminho (o que estava errado na 1ª rodada)

- Tolerância de desvio: a 1ª versão aceitava 2 mil triângulos na casa de palha e 1 mil no túmulo,
  com varas quebradas e telhas rachadas. Hoje o alvo começa em 40% da meta e a tolerância é 3x
  mais apertada.
- Normais do gerador: as normais de canto do ForgeGUI são suavizadas por cima de quinas de 90°
  (na parede da casa de telha elas tombam até 80°). O bake de oclusão seguia essas normais e as
  paredes saíam pretas (casa de telha, telhado da cozinha, boca do bunker). A fonte do bake agora
  sombreia pelo ângulo das faces.
- Gaiola do bake: os raios saem de uma gaiola por vértice, numa cópia separada nas costuras da UV
  (com extrusão única, o raio pegava a cor do saco vizinho nas frestas).
- Faces de costas: faces altas viradas contra o baixo (invisíveis no Roblox) saem do bake.

## Limites desta comparação (o que NÃO foi medido)

- Tudo é render do Blender. Nada foi aberto no Studio nem subido para o Roblox (regra do pedido):
  o importador do Roblox, o LOD automático e a luz do jogo podem mudar o resultado.
- Custo real no jogo (fps, memória de textura no cliente) não foi medido. "Menos pesado" aqui é
  triângulos, MB do GLB e tamanho da textura.
- A versão "peças" dos novos é uma aproximação no Blender das Parts de `MapLife.luau` e
  `GrenadeArt.luau` (mesmas medidas e cores, cor lisa, sem os materiais do Roblox como Slate e
  Fabric). Os triângulos dela são da aproximação, não da Part do Roblox (uma Part custa pouco e
  não conta no `ArtBudget`). Chapéu e varal não existem no jogo: a versão em peças é hipótese.
- Medidas sem fonte estão marcadas PLACEHOLDER no `metricas.json` de cada novo (`medidas_reais`).
- Nenhum asset foi ligado ao jogo: `manifest.json`, `ArtBudget.luau`, `AssetIds.luau` e o
  `AssetLoader` estão como estavam. Para usar um novo: subir o GLB, registrar no manifest e no
  `ArtBudget` (os novos refeitos ficam abaixo das metas de 5 e 8 mil) e trocar a chave no
  `AssetLoader`/`MapLife`.
"""


def fmt(n: float, casas: int = 0) -> str:
    s = f"{n:,.{casas}f}"
    return s.replace(",", "X").replace(".", ",").replace("X", ".")


def ler(chave: str) -> dict | None:
    arq = SAIDA / chave / "metricas.json"
    return json.loads(arq.read_text("utf-8")) if arq.is_file() else None


def tabela_a() -> list[str]:
    linhas = [
        "| asset | antigo: tri · MB | novo: tri · MB · textura | desvio p95 / p99 (mm) "
        "| silhueta (IoU) | vencedor | onde o novo perdeu |",
        "|---|---|---|---|---|---|---|",
    ]
    for k in TAREFA_A:
        m = ler(k)
        if not m:
            linhas.append(f"| {k} | — | não feito | | | | |")
            continue
        a, n, d = m["antigo"], m["novo"], m["desvio_m"]
        iou = m.get("comparacao", {}).get("silhueta_iou", [])
        v, obs = VEREDICTOS.get(k, ("?", ""))
        linhas.append(
            f"| {k} | {fmt(a['triangulos'])} · {fmt(a['mb'], 1)} "
            f"| {fmt(n['triangulos'])} · {fmt(n['mb'], 1)} · {n['texturas_px']['cor'][0]} "
            f"| {fmt(d['p95_m'] * 1000, 1)} / {fmt(d['p99_m'] * 1000, 1)} "
            f"| {' / '.join(fmt(x, 3) for x in iou)} | {v} | {obs} |"
        )
    return linhas


def tabela_b() -> list[str]:
    linhas = [
        "| asset | novo: tri · MB · textura | medidas (m) e fonte | hoje (peças) | vencedor "
        "| observação |",
        "|---|---|---|---|---|---|",
    ]
    for k in TAREFA_B:
        m = ler(k)
        if not m:
            linhas.append(f"| {k} | não feito | | | | |")
            continue
        n, a = m["novo"], m["antigo"]
        dims = " × ".join(fmt(x, 3) for x in n["dim_m_xyz"])
        fontes = "; ".join(
            f"{chave}: {v[1]}" if v[0] is None else f"{chave} = {v[0]} ({v[1]})"
            for chave, v in m["medidas_reais"].items()
        )
        hoje = f"{a.get('pecas', '—')} peças" if a.get("pecas") else "GLB do jogo"
        hoje += f", {fmt(a['triangulos'])} tri"
        v, obs = VEREDICTOS.get(k, ("?", ""))
        linhas.append(
            f"| {m['nome']} (`{k}`) | {fmt(n['triangulos'])} · {fmt(n['mb'], 2)} · "
            f"{n['texturas_px']['cor'][0]} | {dims} — {fontes} | {hoje} | {v} | {obs} |"
        )
    return linhas


def main() -> None:
    corpo = [
        "# Linha de produção no Blender: refeitos e novos",
        "",
        "Gerado por `tools/blender/relatorio.py` a partir dos `metricas.json`. Imagens em "
        "`assets/blender/<chave>/comparacao.png` (linha = ângulo; esquerda = hoje, direita = "
        "novo; Cycles, céu do jogo + sol de 45°, face única como no Roblox).",
        "",
        "Medidas de x × y × z: largura (X) × altura (Y) × profundidade (Z), em metros "
        "(1 stud = 0,28 m).",
        "",
        "## Tarefa A: refeitos (antigo do ForgeGUI × novo do Blender)",
        "",
        *tabela_a(),
        "",
        "## Tarefa B: novos do zero (versão de peças de hoje × novo)",
        "",
        *tabela_b(),
        "",
    ]
    if NOTAS:
        corpo += [NOTAS.strip(), ""]
    import relatorio_veiculos

    corpo += relatorio_veiculos.secoes()
    if relatorio_veiculos.NOTAS:
        corpo += [relatorio_veiculos.NOTAS.strip()]
    (SAIDA / "RELATORIO.md").write_text("\n".join(corpo) + "\n", "utf-8")
    print("ok", SAIDA / "RELATORIO.md")


if __name__ == "__main__":
    main()
