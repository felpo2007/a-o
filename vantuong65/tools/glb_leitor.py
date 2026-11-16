"""Leitor mínimo de GLB (glTF 2.0 binário), só com numpy e Pillow (D-178).

Lê o que os acabamentos de arma precisam: nós com malha, posições, UVs e índices de cada
primitiva (já no espaço do nó, com a matriz do nó aplicada), e a imagem de cor base do material.

Uso de conferência:
    uv run python tools/glb_leitor.py assets/blender/arma_m60/arma_m60.glb
"""

from __future__ import annotations

import io
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

COMP = {
    5120: np.int8,
    5121: np.uint8,
    5122: np.int16,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


@dataclass
class Primitiva:
    no: str  # nome do nó (vira o nome da MeshPart no Roblox)
    material: int
    pos: np.ndarray  # (n, 3) no espaço do modelo
    uv: np.ndarray  # (n, 2), origem no canto de cima (como o glTF)
    tri: np.ndarray  # (m, 3) índices
    imagem: int | None  # índice da imagem de cor base


class Glb:
    def __init__(self, caminho: Path):
        dados = caminho.read_bytes()
        magic, _versao, _total = struct.unpack_from("<III", dados, 0)
        assert magic == 0x46546C67, "não é GLB"
        off = 12
        self.json: dict = {}
        self.bin = b""
        while off < len(dados):
            tam, tipo = struct.unpack_from("<II", dados, off)
            off += 8
            pedaco = dados[off : off + tam]
            off += tam
            if tipo == 0x4E4F534A:
                self.json = json.loads(pedaco)
            elif tipo == 0x004E4942:
                self.bin = pedaco

    def acessor(self, i: int) -> np.ndarray:
        a = self.json["accessors"][i]
        bv = self.json["bufferViews"][a["bufferView"]]
        dt = np.dtype(COMP[a["componentType"]])
        n = NCOMP[a["type"]]
        ini = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        passo = bv.get("byteStride", 0)
        cont = a["count"]
        if passo and passo != dt.itemsize * n:
            linhas = np.frombuffer(
                self.bin, dtype=np.uint8, count=passo * cont, offset=ini
            ).reshape(cont, passo)
            arr = linhas[:, : dt.itemsize * n].copy().view(dt).reshape(cont, n)
        else:
            arr = np.frombuffer(self.bin, dtype=dt, count=cont * n, offset=ini).reshape(cont, n)
        if a.get("normalized") and dt.kind in "iu":
            arr = arr.astype(np.float32) / np.iinfo(dt).max
        return arr

    def imagem(self, i: int) -> Image.Image:
        im = self.json["images"][i]
        bv = self.json["bufferViews"][im["bufferView"]]
        ini = bv.get("byteOffset", 0)
        return Image.open(io.BytesIO(self.bin[ini : ini + bv["byteLength"]])).convert("RGBA")

    def imagem_cor(self, material: int) -> int | None:
        mat = self.json["materials"][material]
        t = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if t is None:
            return None
        return self.json["textures"][t["index"]]["source"]

    def primitivas(self) -> list[Primitiva]:
        out: list[Primitiva] = []
        nos = self.json.get("nodes", [])

        def matriz(no: dict) -> np.ndarray:
            if "matrix" in no:
                return np.array(no["matrix"], dtype=np.float64).reshape(4, 4).T
            m = np.eye(4)
            if "scale" in no:
                m = m @ np.diag([*no["scale"], 1.0])
            if "rotation" in no:
                x, y, z, w = no["rotation"]
                r = np.array(
                    [
                        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
                    ]
                )
                rr = np.eye(4)
                rr[:3, :3] = r
                m = rr @ m
            if "translation" in no:
                t = np.eye(4)
                t[:3, 3] = no["translation"]
                m = t @ m
            return m

        def visita(i: int, pai: np.ndarray) -> None:
            no = nos[i]
            m = pai @ matriz(no)
            if "mesh" in no:
                malha = self.json["meshes"][no["mesh"]]
                for p in malha["primitives"]:
                    at = p["attributes"]
                    if "TEXCOORD_0" not in at or "indices" not in p:
                        continue
                    pos = self.acessor(at["POSITION"]).astype(np.float64)
                    pos = (np.c_[pos, np.ones(len(pos))] @ m.T)[:, :3]
                    uv = self.acessor(at["TEXCOORD_0"]).astype(np.float64)
                    tri = self.acessor(p["indices"]).reshape(-1, 3).astype(np.int64)
                    mat = p.get("material", 0)
                    out.append(
                        Primitiva(no.get("name", f"no{i}"), mat, pos, uv, tri, self.imagem_cor(mat))
                    )
            for f in no.get("children", []):
                visita(f, m)

        cena = self.json["scenes"][self.json.get("scene", 0)]
        for r in cena["nodes"]:
            visita(r, np.eye(4))
        return out


if __name__ == "__main__":
    g = Glb(Path(sys.argv[1]))
    for p in g.primitivas():
        img = g.imagem(p.imagem).size if p.imagem is not None else None
        lo, hi = p.pos.min(axis=0), p.pos.max(axis=0)
        print(
            f"{p.no}: mat {p.material} img {p.imagem} {img} v {len(p.pos)} t {len(p.tri)} "
            f"caixa {np.round(hi - lo, 3)} "
            f"uv {np.round(p.uv.min(axis=0), 3)}..{np.round(p.uv.max(axis=0), 3)}"
        )
