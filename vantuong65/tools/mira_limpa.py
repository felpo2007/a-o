"""Limpa a mira da M16 e da SKS direto no GLB (D-236).

Pedido do dono: "melhore a mira da m16 deixe ela mais limpa" e "melhore a mira da sks deixe mais
limpa". Refazer a arma no Blender trocaria o UV e invalidaria os acabamentos (uma textura por arma).
Aqui só as peças da linha de visada mudam de lugar, vértice a vértice, com o mesmo UV, as mesmas
normais e as mesmas texturas. Os valores novos também estão em tools/blender/m16.py e sks.py, para
um build futuro sair igual.

M16 (olho a 9 cm do anel):
- o anel da alça abre de 5 para 8,4 mm de furo e fica fino;
- os trilhos da alça de transporte, que entravam no furo pelos dois lados, abrem para fora dele e
  descem para baixo da linha de visada;
- as orelhas da massa abrem e o poste engrossa um pouco: o poste fica sozinho no meio do anel.

SKS: o entalhe abre de 4,4 para 7,6 mm e fica 3 mm mais fundo. O fundo dele estava na altura da
ponta do poste e escondia o poste inteiro; agora o poste aparece no meio, com a ponta no nível das
orelhas.

Lê o GLB guardado em <arma>.antes_d236.glb (criado na 1ª vez), então pode rodar de novo.

Uso (a partir de vantuong65): uv run --group arte python tools/mira_limpa.py
"""

from __future__ import annotations

import json
import shutil
import struct
from collections.abc import Callable
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
M = 0.28  # o GLB está em studs: (x, altura, distância da soleira)
Regra = tuple[str, tuple[float, float], tuple[float, float], tuple[float, float], Callable]

ZS_M16 = 0.066
D_ALCA_M16 = 0.2775
D_MASSA_M16 = D_ALCA_M16 + 0.502
ZS_SKS = 0.034


def _trilho(x, z, d):
    s = np.sign(x)
    return s * (0.0125 + (np.abs(x) - 0.0045) / 0.006 * 0.003), z - 0.010, d


def _anel(x, z, d):
    dz = z - ZS_M16
    r = np.hypot(x, dz)
    novo = np.where(r < 0.0040, 0.0042, 0.0062)
    k = novo / np.maximum(r, 1e-9)
    return x * k, ZS_M16 + dz * k, d


def _orelha_massa(x, z, d):
    # mais abertas e abaixo da linha de visada: acima dela fica só o poste
    s = np.sign(x)
    return s * (0.0078 + (np.abs(x) - 0.0058) / 0.0026 * 0.0022), np.minimum(z, 0.061), d


def _orelha_alca(x, z, d):
    # as orelhas de trás ficam mais finas, mais abertas e mais baixas
    s = np.sign(x)
    return s * (0.0100 + (np.abs(x) - 0.0080) / 0.0030 * 0.0015), np.where(z > 0.07, 0.075, z), d


def _poste(x, z, d):
    return x * (0.0011 / 0.0009), z, d


def _orelha_entalhe(x, z, d):
    # o topo das orelhas fica na linha de visada: a ponta do poste alinha com ele, como na mira real
    s = np.sign(x)
    return (
        np.where(np.abs(x) < 0.005, s * 0.0038, x),
        np.where(z > ZS_SKS + 0.002, ZS_SKS + 0.0002, z),
        d,
    )


def _fundo_entalhe(x, z, d):
    # o fundo do entalhe estava na altura da ponta do poste e escondia o poste inteiro
    # 3 mm abaixo da linha: mostra o poste e ainda tapa a madeira do guarda-mão lá atrás
    return x * (0.0038 / 0.0022), np.where(z > ZS_SKS - 0.001, ZS_SKS - 0.0030, z), d


# nome, faixa de |x|, faixa de altura, faixa de d (m): a peça inteira tem de caber na faixa
REGRAS: dict[str, list[Regra]] = {
    "m16": [
        ("trilhos", (0.0044, 0.0106), (0.0515, 0.0705), (0.2975, 0.4375), _trilho),
        ("orelhas da alça", (0.0079, 0.0111), (0.0555, 0.0805), (0.2675, 0.2905), _orelha_alca),
        (
            "anel",
            (0.0, 0.0057),
            (ZS_M16 - 0.0057, ZS_M16 + 0.0057),
            (D_ALCA_M16 - 0.0017, D_ALCA_M16 + 0.0017),
            _anel,
        ),
        (
            "orelhas da massa",
            (0.0057, 0.0085),
            (0.0395, 0.0745),
            (D_MASSA_M16 - 0.0067, D_MASSA_M16 + 0.0067),
            _orelha_massa,
        ),
        (
            "poste",
            (0.0, 0.00095),
            (0.0435, ZS_M16 + 0.0005),
            (D_MASSA_M16 - 0.0022, D_MASSA_M16 + 0.0022),
            _poste,
        ),
    ],
    "sks": [
        (
            "orelhas do entalhe",
            (0.0021, 0.0091),
            (0.0205, ZS_SKS + 0.005),
            (0.5255, 0.5305),
            _orelha_entalhe,
        ),
        (
            "fundo do entalhe",
            (0.0, 0.0023),
            (0.0205, ZS_SKS + 0.0005),
            (0.5255, 0.5305),
            _fundo_entalhe,
        ),
    ],
}


def ler(p: Path) -> tuple[dict, bytearray]:
    b = p.read_bytes()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20 : 20 + n])
    inicio = 20 + n + 8
    tam = struct.unpack("<I", b[20 + n : 24 + n])[0]
    return j, bytearray(b[inicio : inicio + tam])


def gravar(p: Path, j: dict, binario: bytearray) -> None:
    t = json.dumps(j, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    t += b" " * ((4 - len(t) % 4) % 4)
    d = bytes(binario) + b"\0" * ((4 - len(binario) % 4) % 4)
    total = 12 + 8 + len(t) + 8 + len(d)
    p.write_bytes(
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<I", len(t))
        + b"JSON"
        + t
        + struct.pack("<I", len(d))
        + b"BIN\0"
        + d
    )


def vista(j: dict, binario: bytearray, ac: int, comps: int, tipo) -> tuple[np.ndarray, int]:
    a = j["accessors"][ac]
    bv = j["bufferViews"][a["bufferView"]]
    ini = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = np.frombuffer(binario, dtype=tipo, count=a["count"] * comps, offset=ini).copy()
    return arr.reshape(-1, comps) if comps > 1 else arr, ini


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


def limpar(chave: str) -> None:
    pasta = ROOT / "assets" / "blender" / f"arma_{chave}"
    glb = pasta / f"arma_{chave}.glb"
    antes = pasta / f"arma_{chave}.antes_d236.glb"
    if not antes.exists():
        shutil.copy2(glb, antes)
    j, binario = ler(antes)
    pr = j["meshes"][0]["primitives"][0]
    ac = pr["attributes"]["POSITION"]
    pos, ini = vista(j, binario, ac, 3, np.float32)
    idx, _ = vista(j, binario, pr["indices"], 1, np.uint16)
    rot = ilhas(idx, len(pos))
    m = pos.astype(np.float64) * M
    novo = m.copy()
    for nome, fx, fz, fd, f in REGRAS[chave]:
        n_ilhas = n_v = 0
        for r in np.unique(rot):
            sel = rot == r
            q = m[sel]
            ax = np.abs(q[:, 0])
            if (
                ax.min() >= fx[0]
                and ax.max() <= fx[1]
                and q[:, 1].min() >= fz[0]
                and q[:, 1].max() <= fz[1]
                and q[:, 2].min() >= fd[0]
                and q[:, 2].max() <= fd[1]
            ):
                x, z, d = f(q[:, 0], q[:, 1], q[:, 2])
                novo[sel, 0], novo[sel, 1], novo[sel, 2] = x, z, d
                n_ilhas += 1
                n_v += int(sel.sum())
        print(f"{chave}: {nome}: {n_ilhas} ilhas, {n_v} vértices")
        if n_ilhas == 0:
            raise SystemExit(f"{chave}: nada casou com a regra '{nome}'")
    saida = (novo / M).astype(np.float32)
    binario[ini : ini + saida.size * 4] = saida.tobytes()
    j["accessors"][ac]["min"] = [float(v) for v in saida.min(axis=0)]
    j["accessors"][ac]["max"] = [float(v) for v in saida.max(axis=0)]
    gravar(glb, j, binario)
    print(f"{chave}: {glb.name} gravado")


if __name__ == "__main__":
    for k in REGRAS:
        limpar(k)
