"""Touceira de bambu sem o disco marrom da base (pedido do dono, 2026-11-12).

O `bambu_touceira_studs_fosco.glb` (ForgeGUI, o que o jogo usa) tem um disco de terra marrom de
~4,4 m, de 0,26 a 0,45 m do chão (uma peça solta de 28 faces). Os colmos e as folhas secas da
base nascem em cima dele. Esta ferramenta:
1. tira o disco (peça solta com mais de 1 m² de face horizontal e topo abaixo de 0,6 m);
2. leva ao chão o que nascia em cima dele: peça baixa (< 1,2 m de altura) desce inteira; colmo
   alto tem o pé esticado até o chão (os 0,6 m de baixo, em rampa), para sair direto do chão;
3. mantém o resto como está: mesma malha, UV, normais, texturas, materiais, nós e pivô.

Sem redução nem rebake: a touceira é de cartões finos (folhas e colmos), que a redução e o
rebake dos refeitos estragam (o `rice_patch` perdeu para o antigo por isso).

Roda fora do Blender:
    uv run python tools/blender/bambu_sem_disco.py
Saída: `assets/blender/bamboo_clump/bamboo_clump.glb` e `metricas.json` (a comparação sai do
`comparar_chao.py`).
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

import numpy as np

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
ORIGEM = RAIZ / "assets" / "forgegui" / "models" / "bambu_touceira_studs_fosco.glb"
PASTA = RAIZ / "assets" / "blender" / "bamboo_clump"
STUD = 0.28
DISCO_AREA_M2 = 1.0
DISCO_TOPO_M = 0.6
PECA_BAIXA_M = 1.2
FAIXA_PE_M = 0.6


def ler_glb(caminho: Path):
    data = caminho.read_bytes()
    n_js = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20 : 20 + n_js])
    off = 20 + n_js
    n_bin = struct.unpack_from("<I", data, off)[0]
    binario = data[off + 8 : off + 8 + n_bin]
    return js, binario


def acessor(js, binario, i):
    a = js["accessors"][i]
    v = js["bufferViews"][a["bufferView"]]
    tipo = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a["componentType"]]
    comp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    ini = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = np.frombuffer(binario, tipo, a["count"] * comp, ini)
    return arr.reshape(-1, comp) if comp > 1 else arr.copy()


def escrever_glb(js, views: list[bytes], caminho: Path) -> int:
    corpo = b""
    for i, dados in enumerate(views):
        corpo += b"\x00" * ((-len(corpo)) % 4)
        js["bufferViews"][i]["byteOffset"] = len(corpo)
        js["bufferViews"][i]["byteLength"] = len(dados)
        corpo += dados
    corpo += b"\x00" * ((-len(corpo)) % 4)
    js["buffers"] = [{"byteLength": len(corpo)}]
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((-len(jb)) % 4)
    total = 12 + 8 + len(jb) + 8 + len(corpo)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    caminho.write_bytes(
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(jb), b"JSON")
        + jb
        + struct.pack("<I4s", len(corpo), b"BIN\x00")
        + corpo
    )
    return total


def pecas_soltas(pos_m: np.ndarray, tri: np.ndarray) -> np.ndarray:
    """Peça solta de cada vértice (vértices na mesma posição contam como o mesmo)."""
    chave = np.round(pos_m / 1e-4).astype(np.int64)
    _, unico = np.unique(chave, axis=0, return_inverse=True)
    unico = unico.reshape(-1)
    pai = np.arange(unico.max() + 1)

    def raiz(a):
        while pai[a] != a:
            pai[a] = pai[pai[a]]
            a = pai[a]
        return a

    for t in tri:
        a, b, c = (raiz(unico[k]) for k in t)
        pai[b] = a
        pai[raiz(c)] = a
    return np.array([raiz(u) for u in unico])


def main() -> None:
    js, binario = ler_glb(ORIGEM)
    prim = js["meshes"][0]["primitives"][0]
    i_pos, i_idx = prim["attributes"]["POSITION"], prim["indices"]
    pos = acessor(js, binario, i_pos).astype(np.float64)
    idx = acessor(js, binario, i_idx).astype(np.int64)
    tri = idx.reshape(-1, 3)
    # transformação do nó pai (ForgeGUIExplicitTransform): posição local -> studs -> metros
    mtx = next(n["matrix"] for n in js["nodes"] if "matrix" in n)
    esc, desl_y = mtx[0], mtx[13]
    assert abs(mtx[5] - esc) < 1e-6 and abs(mtx[10] - esc) < 1e-6 and mtx[12] == mtx[14] == 0
    pos_m = (pos * esc + np.array([0.0, desl_y, 0.0])) * STUD
    peca = pecas_soltas(pos_m, tri)
    # área horizontal por peça (glTF: Y para cima)
    a, b, c = pos_m[tri[:, 0]], pos_m[tri[:, 1]], pos_m[tri[:, 2]]
    cruz = np.cross(b - a, c - a)
    area = 0.5 * np.linalg.norm(cruz, axis=1)
    ny = np.abs(cruz[:, 1]) / np.maximum(np.linalg.norm(cruz, axis=1), 1e-12)
    peca_tri = peca[tri[:, 0]]
    disco = set()
    for p in np.unique(peca_tri):
        sel = peca_tri == p
        ah = float(area[sel & (ny > 0.7)].sum())
        vs = np.unique(tri[sel])
        if ah > DISCO_AREA_M2 and pos_m[vs, 1].max() < DISCO_TOPO_M:
            disco.add(int(p))
    assert disco, "o disco não foi achado"
    tira = np.isin(peca_tri, list(disco))
    disco_info = {
        "faces": int(tira.sum()),
        "area_m2": round(float(area[tira].sum()), 2),
        "altura_m": [
            round(float(pos_m[np.unique(tri[tira]), 1].min()), 3),
            round(float(pos_m[np.unique(tri[tira]), 1].max()), 3),
        ],
    }
    tri_novo = tri[~tira]
    # leva ao chão o que nascia em cima do disco
    usados = np.unique(tri_novo)
    novo_m = pos_m.copy()
    descidas = esticadas = 0
    for p in np.unique(peca[usados]):
        vs = usados[peca[usados] == p]
        h0, h1 = pos_m[vs, 1].min(), pos_m[vs, 1].max()
        if not (0.005 < h0 < DISCO_TOPO_M):
            continue
        if h1 - h0 < PECA_BAIXA_M:
            novo_m[vs, 1] -= h0
            descidas += 1
        else:
            t = np.clip((pos_m[vs, 1] - h0) / FAIXA_PE_M, 0.0, 1.0)
            novo_m[vs, 1] -= h0 * (1.0 - t)
            esticadas += 1
    novo_local = (novo_m / STUD - np.array([0.0, desl_y, 0.0])) / esc
    # novo GLB: posições e índices trocados, o resto byte a byte
    texturas = []
    for im in js.get("images", []):
        v = js["bufferViews"][im["bufferView"]]
        ini = v.get("byteOffset", 0)
        texturas.append(tamanho_imagem(binario[ini : ini + 64 * 1024]))
    views = []
    for v in js["bufferViews"]:
        ini = v.get("byteOffset", 0)
        views.append(binario[ini : ini + v["byteLength"]])
    acc_pos, acc_idx = js["accessors"][i_pos], js["accessors"][i_idx]
    views[acc_pos["bufferView"]] = novo_local.astype(np.float32).tobytes()
    acc_pos["min"] = [float(x) for x in novo_local[usados].min(axis=0)]
    acc_pos["max"] = [float(x) for x in novo_local[usados].max(axis=0)]
    tipo_idx = np.uint16 if acc_idx["componentType"] == 5123 else np.uint32
    views[acc_idx["bufferView"]] = tri_novo.reshape(-1).astype(tipo_idx).tobytes()
    acc_idx["count"] = int(tri_novo.size)
    js["asset"]["generator"] = js["asset"].get("generator", "") + " + VT65 bambu_sem_disco.py"
    saida = PASTA / "bamboo_clump.glb"
    total = escrever_glb(js, views, saida)

    def dims(p_m, vs):
        lo, hi = p_m[vs].min(axis=0), p_m[vs].max(axis=0)
        return [round(float(x), 3) for x in hi - lo], round(float(lo[1]), 3)

    d0, base0 = dims(pos_m, np.unique(tri))
    d1, base1 = dims(novo_m, usados)
    metricas = {
        "chave": "bamboo_clump",
        "tipo": "refeito",
        "classe": "veg",
        "classe_artbudget": "veg (≥ 8.000 triângulos: MIN_VEG da D-66; teto 20 mil)",
        "pedido": "sem o disco marrom da base; colmos saindo direto do chão (dono, 2026-11-12)",
        "metodo": "edição do GLB do jogo: tira a peça do disco e leva ao chão o que nascia em "
        "cima dele; sem redução nem rebake (cartões finos), mesma UV, normais e texturas",
        "antigo": {
            "arquivo_jogo": f"assets/forgegui/models/{ORIGEM.name}",
            "triangulos": int(len(tri)),
            "texturas_px": {"cor": texturas[0] if texturas else None},
            "mb": round(ORIGEM.stat().st_size / 2**20, 3),
            "dim_m_xyz": [d0[0], d0[1], d0[2]],
            "base_y_m": base0,
        },
        "novo": {
            "arquivo": f"assets/blender/bamboo_clump/{saida.name}",
            "triangulos": int(len(tri_novo)),
            "triangulos_glb": int(len(tri_novo)),
            "texturas_px": {"cor": texturas[0] if texturas else None, "todas": texturas},
            "mb": round(total / 2**20, 3),
            "dim_m_xyz": [d1[0], d1[1], d1[2]],
            "base_y_m": base1,
        },
        "disco_removido": disco_info,
        "pecas_descidas_ate_o_chao": descidas,
        "colmos_com_o_pe_esticado": esticadas,
        "faixa_do_pe_m": FAIXA_PE_M,
    }
    (PASTA / "metricas.json").write_text(
        json.dumps(metricas, ensure_ascii=False, indent=1) + "\n", "utf-8"
    )
    print(json.dumps({k: metricas[k] for k in ("disco_removido", "novo")}, ensure_ascii=False))
    print("peças descidas", descidas, "colmos esticados", esticadas)


def tamanho_imagem(dado: bytes) -> list[int] | None:
    """Largura x altura de um PNG ou JPEG (só o cabeçalho)."""
    if dado[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", dado[16:24])
        return [w, h]
    i = 2
    while i < len(dado) - 9:
        if dado[i] != 0xFF:
            i += 1
            continue
        marca = dado[i + 1]
        if marca in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", dado[i + 5 : i + 9])
            return [w, h]
        i += 2 + struct.unpack(">H", dado[i + 2 : i + 4])[0]
    return None


if __name__ == "__main__":
    main()
