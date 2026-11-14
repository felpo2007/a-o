"""Escritor de GLB mínimo (numpy puro, sem bpy) para a linha de produção do Blender.

Segue a convenção do `tools/prep_trees.py` (classe `Glb`) e do `tools/rig_animals.py`:
- 1 unidade = 1 stud (1 stud = 0,28 m), Y para cima, base no chão (Y mínimo = 0) e pivô na origem;
- uma malha por nó, sem transformação no nó (o importador do Roblox cria uma MeshPart por nó);
- material PBR com metallicFactor 0 quando o objeto não é de metal. A textura de
  metal/rugosidade, quando existe, leva a rugosidade no canal G e o metal no B (0 = não metal).
  Sem TANGENT: o importador calcula as tangentes (MikkTSpace), como no prep_trees.

As posições chegam do Blender em metros, Z para cima; `de_blender` converte para studs, Y para
cima: (x, y, z) -> (x, z, -y) / 0,28. A coordenada V do glTF é 1 - V do Blender.

Roda dentro do Python do Blender (que traz numpy) e fora dele (uv run python).
"""

from __future__ import annotations

import json
import struct

import numpy as np

M_POR_STUD = 0.28


def de_blender(pos_m: np.ndarray, nrm: np.ndarray, uv: np.ndarray):
    """Metros, Z para cima (Blender) -> studs, Y para cima (glTF); UV com V invertido."""
    p = np.column_stack([pos_m[:, 0], pos_m[:, 2], -pos_m[:, 1]]) / M_POR_STUD
    n = np.column_stack([nrm[:, 0], nrm[:, 2], -nrm[:, 1]])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    t = np.column_stack([uv[:, 0], 1.0 - uv[:, 1]])
    return p.astype(np.float32), n.astype(np.float32), t.astype(np.float32)


class Glb:
    def __init__(self, gerador: str = "VT65 tools/blender"):
        self.js: dict = {
            "asset": {"version": "2.0", "generator": gerador},
            "scene": 0,
            "scenes": [{"nodes": []}],
            "nodes": [],
            "meshes": [],
            "materials": [],
            "textures": [],
            "images": [],
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
            "accessors": [],
            "bufferViews": [],
            "buffers": [],
        }
        self.chunks: list[bytes] = []
        self.size = 0

    def view(self, data: bytes, target: int | None = None) -> int:
        pad = (-self.size) % 4
        if pad:
            self.chunks.append(b"\x00" * pad)
            self.size += pad
        v = {"buffer": 0, "byteOffset": self.size, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.chunks.append(data)
        self.size += len(data)
        self.js["bufferViews"].append(v)
        return len(self.js["bufferViews"]) - 1

    def accessor(self, arr: np.ndarray, ctype: int, typ: str, target: int, minmax=False) -> int:
        a = {
            "bufferView": self.view(arr.tobytes(), target),
            "componentType": ctype,
            "count": int(arr.shape[0]),
            "type": typ,
        }
        if minmax:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        self.js["accessors"].append(a)
        return len(self.js["accessors"]) - 1

    def texture(self, data: bytes, mime: str) -> int:
        self.js["images"].append({"bufferView": self.view(data), "mimeType": mime})
        self.js["textures"].append({"sampler": 0, "source": len(self.js["images"]) - 1})
        return len(self.js["textures"]) - 1

    def material(
        self,
        nome: str,
        cor: int | None,
        normal: int | None = None,
        metal_rug: int | None = None,
        metal: bool = False,
        rugosidade: float = 0.9,
        cor_fator: tuple[float, float, float, float] | None = None,
    ) -> int:
        """Material PBR. Sem textura de metal/rugosidade, a rugosidade é o fator fixo."""
        pbr: dict = {
            "metallicFactor": 1.0 if (metal and metal_rug is not None) else 0.0,
            "roughnessFactor": 1.0 if metal_rug is not None else float(rugosidade),
        }
        if cor is not None:
            pbr["baseColorTexture"] = {"index": cor}
        if cor_fator is not None:
            pbr["baseColorFactor"] = [float(c) for c in cor_fator]
        if metal_rug is not None:
            pbr["metallicRoughnessTexture"] = {"index": metal_rug}
        m: dict = {"name": nome, "pbrMetallicRoughness": pbr, "doubleSided": False}
        if normal is not None:
            m["normalTexture"] = {"index": normal}
        self.js["materials"].append(m)
        return len(self.js["materials"]) - 1

    def mesh(self, nome: str, pos, nrm, uv, idx, mat: int) -> None:
        idx = np.asarray(idx).reshape(-1)
        use16 = len(pos) < 65536
        attrs = {
            "POSITION": self.accessor(np.asarray(pos, np.float32), 5126, "VEC3", 34962, True),
            "NORMAL": self.accessor(np.asarray(nrm, np.float32), 5126, "VEC3", 34962),
        }
        if uv is not None:
            attrs["TEXCOORD_0"] = self.accessor(np.asarray(uv, np.float32), 5126, "VEC2", 34962)
        prim = {
            "attributes": attrs,
            "indices": self.accessor(
                idx.astype(np.uint16 if use16 else np.uint32),
                5123 if use16 else 5125,
                "SCALAR",
                34963,
            ),
            "material": mat,
        }
        self.js["meshes"].append({"name": nome, "primitives": [prim]})
        self.js["nodes"].append({"name": nome, "mesh": len(self.js["meshes"]) - 1})
        self.js["scenes"][0]["nodes"].append(len(self.js["nodes"]) - 1)

    def bytes(self) -> bytes:
        body = b"".join(self.chunks)
        body += b"\x00" * ((-len(body)) % 4)
        self.js["buffers"] = [{"byteLength": len(body)}]
        if not self.js["images"]:
            for k in ("images", "textures", "samplers"):
                self.js.pop(k)
        jb = json.dumps(self.js, separators=(",", ":")).encode()
        jb += b" " * ((-len(jb)) % 4)
        total = 12 + 8 + len(jb) + 8 + len(body)
        return (
            struct.pack("<4sII", b"glTF", 2, total)
            + struct.pack("<I4s", len(jb), b"JSON")
            + jb
            + struct.pack("<I4s", len(body), b"BIN\x00")
            + body
        )


def ler_json(caminho) -> dict:
    """Só o JSON de um GLB (para conferir materiais e contar triângulos sem bpy)."""
    data = open(caminho, "rb").read()
    n, tipo = struct.unpack_from("<I4s", data, 12)
    if tipo != b"JSON":
        raise ValueError(f"{caminho}: primeiro chunk não é JSON")
    return json.loads(data[20 : 20 + n])


def triangulos(caminho) -> int:
    js = ler_json(caminho)
    total = 0
    for m in js["meshes"]:
        for p in m["primitives"]:
            total += js["accessors"][p["indices"]]["count"] // 3
    return total
