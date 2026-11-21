"""Testes de tools/decimate_glb.py: leitura/escrita de GLB e redução com UV preservada."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import decimate_glb as dg  # noqa: E402

IMG = b"\x89PNG-falso" * 7


def uv_sphere(n: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Esfera com costura de UV (coluna duplicada em u=0/u=1), como as malhas do ForgeGUI."""
    th = np.linspace(0, np.pi, n + 1)
    ph = np.linspace(0, 2 * np.pi, 2 * n + 1)
    t, p = np.meshgrid(th, ph, indexing="ij")
    pos = np.stack([np.sin(t) * np.cos(p), np.cos(t), np.sin(t) * np.sin(p)], -1).reshape(-1, 3)
    uv = np.stack([p / (2 * np.pi), t / np.pi], -1).reshape(-1, 2)
    w = 2 * n + 1
    f = []
    for i in range(n):
        for j in range(2 * n):
            a, b, c, d = i * w + j, i * w + j + 1, (i + 1) * w + j, (i + 1) * w + j + 1
            if i > 0:
                f.append((a, b, c))
            if i < n - 1:
                f.append((b, d, c))
    nrm = pos / np.linalg.norm(pos, axis=1, keepdims=True)
    return pos.astype(np.float32), nrm.astype(np.float32), uv.astype(np.float32), np.array(f)


def make_glb(path: Path, pos, nrm, uv, faces, scale: float = 3.5) -> None:
    js = {
        "asset": {"version": "2.0"},
        "nodes": [
            {"mesh": 0},
            {
                "matrix": [scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, scale, 0, 0, 1, 0, 1],
                "children": [0],
            },
        ],
        "meshes": [
            {
                "primitives": [
                    {"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3}
                ]
            }
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3"},
            {"bufferView": 1, "componentType": 5126, "count": len(pos), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(pos), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5125, "count": faces.size, "type": "SCALAR"},
        ],
        "images": [{"mimeType": "image/png", "bufferView": 4}],
        "textures": [{"source": 0}],
        "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
        "bufferViews": [],
        "buffers": [],
    }
    parts = [pos.tobytes(), nrm.tobytes(), uv.tobytes(), faces.astype(np.uint32).tobytes(), IMG]
    off = 0
    blob = b""
    for p in parts:
        pad = (-off) % 4
        blob += b"\x00" * pad
        off += pad
        js["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(p)})
        blob += p
        off += len(p)
    blob += b"\x00" * ((-len(blob)) % 4)
    js["buffers"] = [{"byteLength": len(blob)}]
    jb = json.dumps(js).encode()
    jb += b" " * ((-len(jb)) % 4)
    total = 28 + len(jb) + len(blob)
    path.write_bytes(
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(jb), b"JSON")
        + jb
        + struct.pack("<I4s", len(blob), b"BIN\x00")
        + blob
    )


def image_bytes(js: dict, blob: bytes) -> bytes:
    bv = js["bufferViews"][js["images"][0]["bufferView"]]
    return blob[bv["byteOffset"] : bv["byteOffset"] + bv["byteLength"]]


def test_escrita_preserva_geometria_imagem_e_no(tmp_path: Path) -> None:
    pos, nrm, uv, f = uv_sphere(8)
    src, dst = tmp_path / "a.glb", tmp_path / "b.glb"
    make_glb(src, pos, nrm, uv, f)
    js, blob = dg.read_glb(src)
    dg.write_glb(js, blob, dst, pos, nrm, uv, f.reshape(-1).astype(np.uint32))
    js2, blob2 = dg.read_glb(dst)
    p2, uv2, f2 = dg.load_mesh(js2, blob2)
    assert np.allclose(p2, pos) and np.allclose(uv2, uv) and (f2 == f).all()
    assert image_bytes(js2, blob2) == IMG
    assert dg.node_scale(js2) == 3.5
    a = js2["accessors"][js2["meshes"][0]["primitives"][0]["indices"]]
    assert a["componentType"] == 5123  # menos de 65.536 vértices: índices de 16 bits


def test_reducao_atinge_alvo_e_preserva_forma_e_uv(tmp_path: Path) -> None:
    pymeshlab = pytest.importorskip("pymeshlab")
    if not hasattr(pymeshlab.MeshSet(), "meshing_decimation_quadric_edge_collapse_with_texture"):
        pytest.skip("filtro de redução indisponível (plugin de malha sem libopengl0)")
    pos, nrm, uv, f = uv_sphere(40)
    src, dst = tmp_path / "a.glb", tmp_path / "b.glb"
    make_glb(src, pos, nrm, uv, f)
    r = dg.run(src, dst, 600)
    assert r["tris_antes"] == len(f) and 560 <= r["tris"] <= 600
    # a posição ótima dos vértices pode passar um pouco da borda original
    assert np.allclose(r["dim_studs_xyz"], r["dim_antes"], rtol=0.01)
    # raio 1 × escala 3,5 × 0,28 m = 0,98 m: desvio máximo abaixo de 2% do raio
    assert r["desvio_max_m"] < 0.02
    js, blob = dg.read_glb(dst)
    p, uv2, _ = dg.load_mesh(js, blob)
    # UV ainda segue a posição (u = longitude, v = colatitude) fora dos polos e da costura
    lon = np.mod(np.arctan2(p[:, 2], p[:, 0]), 2 * np.pi) / (2 * np.pi)
    col = np.arccos(np.clip(p[:, 1] / np.linalg.norm(p, axis=1), -1, 1)) / np.pi
    ok = (col > 0.1) & (col < 0.9) & (lon > 0.05) & (lon < 0.95)
    assert np.abs(uv2[ok, 1] - col[ok]).max() < 0.02
    assert np.abs(uv2[ok, 0] - lon[ok]).max() < 0.02
    assert image_bytes(js, blob) == IMG
