"""Tira as grades das janelas direto no GLB (D-249), sem refazer as casas no Blender.

Pedido do dono: "faça as janelas das casas varaveis". O soldado já passa pela janela
(Movement.janelaPlan), mas atravessava as barras. Cada barra é uma ilha de malha que cabe inteira
dentro da caixa Colisao_*jan*: só essas ilhas saem. Moldura, peitoril, verga e a aba de bambu ficam,
e o UV e as texturas não mudam.

Saída: assets/janelas/<chave>.glb.

Uso (a partir de vantuong65):
    uv run --group arte python tools/janelas_abertas.py          # lista o que sairia
    uv run --group arte python tools/janelas_abertas.py --gravar
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SAIDA = ROOT / "assets" / "janelas"
FOLGA = 0.03  # studs além da caixa


def ler(p: Path) -> tuple[dict, bytearray]:
    b = p.read_bytes()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20 : 20 + n])
    t = struct.unpack("<I", b[20 + n : 24 + n])[0]
    return j, bytearray(b[28 + n : 28 + n + t])


def gravar(p: Path, j: dict, binario: bytes) -> None:
    t = json.dumps(j, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    t += b" " * ((4 - len(t) % 4) % 4)
    d = bytes(binario) + b"\0" * ((4 - len(binario) % 4) % 4)
    p.write_bytes(
        struct.pack("<III", 0x46546C67, 2, 28 + len(t) + len(d))
        + struct.pack("<I", len(t))
        + b"JSON"
        + t
        + struct.pack("<I", len(d))
        + b"BIN\0"
        + d
    )


def matriz(no: dict) -> np.ndarray:
    if "matrix" in no:
        return np.array(no["matrix"], dtype=np.float64).reshape(4, 4).T
    x, y, z, w = no.get("rotation", [0, 0, 0, 1])
    r = np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )
    m = np.eye(4)
    m[:3, :3] = r * np.array(no.get("scale", [1, 1, 1]))
    m[:3, 3] = no.get("translation", [0, 0, 0])
    return m


def mundo(j: dict) -> dict[int, np.ndarray]:
    out: dict[int, np.ndarray] = {}

    def desce(i: int, pai: np.ndarray) -> None:
        m = pai @ matriz(j["nodes"][i])
        out[i] = m
        for f in j["nodes"][i].get("children", []):
            desce(f, m)

    for r in j["scenes"][j.get("scene", 0)]["nodes"]:
        desce(r, np.eye(4))
    return out


def acessor(j: dict, d: bytearray, ac: int) -> tuple[np.ndarray, int]:
    a = j["accessors"][ac]
    bv = j["bufferViews"][a["bufferView"]]
    tipo = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[a["componentType"]]
    comp = {"SCALAR": 1, "VEC3": 3}[a["type"]]
    ini = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = np.frombuffer(bytes(d[ini : ini + a["count"] * comp * np.dtype(tipo).itemsize]), tipo)
    return (arr.reshape(-1, comp) if comp > 1 else arr), ini


def ilhas(idx: np.ndarray, n: int) -> np.ndarray:
    pai = np.arange(n)

    def acha(a: int) -> int:
        while pai[a] != a:
            pai[a] = pai[pai[a]]
            a = int(pai[a])
        return a

    for i in range(0, len(idx), 3):
        a, b, c = acha(int(idx[i])), acha(int(idx[i + 1])), acha(int(idx[i + 2]))
        pai[b] = a
        pai[acha(c)] = a
    return np.array([acha(i) for i in range(n)])


def caixas(j: dict, d: bytearray, mw: dict[int, np.ndarray]) -> list[tuple[np.ndarray, np.ndarray]]:
    """Cada caixa de janela: a matriz inversa e a meia medida, no espaço da própria caixa."""
    out = []
    for i, no in enumerate(j["nodes"]):
        nome = no.get("name", "")
        if not (nome.startswith("Colisao_") and "jan" in nome[8:]) or "mesh" not in no:
            continue
        pts = []
        for pr in j["meshes"][no["mesh"]]["primitives"]:
            pts.append(acessor(j, d, pr["attributes"]["POSITION"])[0])
        q = np.concatenate(pts).astype(np.float64)
        c, meia = (q.max(0) + q.min(0)) / 2, (q.max(0) - q.min(0)) / 2
        m = mw[i].copy()
        m[:3, 3] = (mw[i] @ np.array([*c, 1.0]))[:3]
        escala = np.linalg.norm(m[:3, :3], axis=0)
        m[:3, :3] = m[:3, :3] / np.maximum(escala, 1e-9)
        out.append((np.linalg.inv(m), meia * escala))
    return out


def tratar(chave: str, origem: Path, grava: bool) -> tuple[int, int, int] | None:
    j, d = ler(origem)
    if not any(
        n.get("name", "").startswith("Colisao_") and "jan" in n.get("name", "")[8:]
        for n in j["nodes"]
    ):
        return None
    mw = mundo(j)
    cx = caixas(j, d, mw)
    tiradas, tri = 0, 0
    for i, no in enumerate(j["nodes"]):
        if "mesh" not in no or no.get("name", "").startswith(("Colisao_", "Zona_")) or i not in mw:
            continue
        for pr in j["meshes"][no["mesh"]]["primitives"]:
            pos = acessor(j, d, pr["attributes"]["POSITION"])[0].astype(np.float64)
            idx, ini = acessor(j, d, pr["indices"])
            rot = ilhas(idx, len(pos))
            h = np.c_[pos, np.ones(len(pos))]
            w = (mw[i] @ h.T).T
            fora = np.zeros(len(pos), dtype=bool)
            for inv, meia in cx:
                loc = (inv @ w.T).T[:, :3]
                dentro = (np.abs(loc) <= meia + FOLGA).all(axis=1)
                ids, cont = np.unique(rot[dentro], return_counts=True)
                total = dict(zip(*np.unique(rot, return_counts=True), strict=True))
                for r, c in zip(ids, cont, strict=True):
                    # só ilha inteira na caixa, fina: a barra (nunca a parede)
                    if c == total[int(r)]:
                        sel = rot == r
                        tam = np.ptp(loc[sel], axis=0)
                        if np.sort(tam)[1] <= 0.34:
                            fora |= sel
                            tiradas += 1
            if not fora.any():
                continue
            tris = idx.reshape(-1, 3)
            fica = ~fora[tris].any(axis=1)
            tri += int((~fica).sum())
            novo = tris[fica].ravel()
            a = j["accessors"][pr["indices"]]
            a["count"] = int(novo.size)
            bytes_novos = novo.astype(idx.dtype).tobytes()
            d[ini : ini + len(bytes_novos)] = bytes_novos
    if grava and tri:
        SAIDA.mkdir(parents=True, exist_ok=True)
        gravar(SAIDA / f"{chave}.glb", j, d)
    return len(cx), tiradas, tri


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gravar", action="store_true")
    a = ap.parse_args()
    plano = json.loads((ROOT / "assets/upload_plan.json").read_text("utf-8"))
    soma = 0
    for e in plano:
        k, f = e["key"], e["file"]
        if not k.startswith("Models.") or not f.endswith(".glb") or not (ROOT / f).exists():
            continue
        r = tratar(k.split(".", 1)[1], ROOT / e.get("file_limpo", f), a.gravar)
        if r:
            print(f"{k}: {r[0]} janelas, {r[1]} barras, {r[2]} triângulos  ({f})")
            soma += r[2]
    print("triângulos a menos:", soma)


if __name__ == "__main__":
    main()
