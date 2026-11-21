"""Redução local de malha de um GLB do ForgeGUI (F5, D-45), sem gastar crédito.

Usada quando o remesh do ForgeGUI termina em `outcome_unknown` (a regra é não regenerar).
Colapso de arestas por quádricas preservando as costuras de UV (pymeshlab). As texturas
embutidas (cor, ORM, normal) e o nó de escala/pivô do GLB preparado são mantidos. Mede o desvio
geométrico (Hausdorff) entre o original e o reduzido, em metros, já com a escala do nó.

Uso (precisa do grupo "arte" e de libopengl0 no sistema):
    uv run --group arte python tools/decimate_glb.py entrada.glb saida.glb --faces 4000
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

import numpy as np

M_POR_STUD = 0.28
COMP = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, _ver, _total = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF", "não é GLB"
    clen, ctype = struct.unpack_from("<I4s", data, 12)
    assert ctype == b"JSON"
    js = json.loads(data[20 : 20 + clen])
    off = 20 + clen
    blen, btype = struct.unpack_from("<I4s", data, off)
    assert btype == b"BIN\x00"
    return js, data[off + 8 : off + 8 + blen]


def accessor(js: dict, blob: bytes, i: int) -> np.ndarray:
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    n = NCOMP[a["type"]]
    dt = np.dtype(COMP[a["componentType"]])
    stride = bv.get("byteStride")
    assert stride in (None, n * dt.itemsize), "bufferView intercalado não suportado"
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = np.frombuffer(blob, dtype=dt, count=a["count"] * n, offset=start)
    return arr.reshape(a["count"], n) if n > 1 else arr


def node_scale(js: dict) -> float:
    for n in js["nodes"]:
        if "matrix" in n:
            return float(n["matrix"][0])
    return 1.0


def load_mesh(js: dict, blob: bytes) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    assert len(js["meshes"]) == 1 and len(js["meshes"][0]["primitives"]) == 1, "1 primitiva"
    pr = js["meshes"][0]["primitives"][0]
    assert pr.get("mode", 4) == 4, "só triângulos"
    pos = accessor(js, blob, pr["attributes"]["POSITION"]).astype(np.float64)
    uv = accessor(js, blob, pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
    faces = accessor(js, blob, pr["indices"]).astype(np.int64).reshape(-1, 3)
    return pos, uv, faces


def decimate(pos, uv, faces, target: int, free_borders: bool = False):
    import pymeshlab

    ms = pymeshlab.MeshSet()
    ms.add_mesh(
        pymeshlab.Mesh(
            vertex_matrix=pos, face_matrix=faces.astype(np.int32), v_tex_coords_matrix=uv
        )
    )
    # UV por canto de face: as costuras viram atributo do canto e os vértices duplicados na
    # costura podem ser soldados, senão a borda da costura trava a redução
    ms.compute_texcoord_transfer_vertex_to_wedge()
    ms.meshing_merge_close_vertices(threshold=pymeshlab.PercentageValue(0.001))
    # Folhagem (D-65) é feita de lâminas abertas: com a borda presa, a redução parava em ~6,5 mil
    # triângulos (tràm, taioba). free_borders solta a borda; a folha encolhe um pouco na ponta.
    ms.meshing_decimation_quadric_edge_collapse_with_texture(
        targetfacenum=target,
        qualitythr=0.5,
        extratcoordw=1.0,
        preserveboundary=not free_borders,
        boundaryweight=1.0 if free_borders else 2.0,
        optimalplacement=True,
        preservenormal=True,
        planarquadric=True,
    )
    ms.meshing_remove_unreferenced_vertices()
    ms.compute_normal_per_vertex(weightmode="By Angle")
    m = ms.current_mesh()
    v = m.vertex_matrix()
    f = m.face_matrix()
    n = m.vertex_normal_matrix()
    w = m.wedge_tex_coord_matrix().reshape(-1, 2)
    # volta a UV por vértice: um vértice por par (vértice, UV) distinto
    corners = f.reshape(-1)
    key = np.column_stack([corners.astype(np.float64), np.round(w, 7)])
    uniq, inv = np.unique(key, axis=0, return_inverse=True)
    vi = uniq[:, 0].astype(np.int64)
    out_pos = v[vi].astype(np.float32)
    nrm = n[vi]
    nrm = nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
    out_uv = uniq[:, 1:].astype(np.float32)
    out_idx = inv.reshape(-1).astype(np.uint32)
    return out_pos, nrm.astype(np.float32), out_uv, out_idx


def hausdorff_m(pos, faces, out_pos, out_idx, scale: float) -> tuple[float, float]:
    """Desvio do reduzido para o original, nos dois sentidos (máximo e média), em metros."""
    import pymeshlab

    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix=pos, face_matrix=faces.astype(np.int32)))
    ms.add_mesh(
        pymeshlab.Mesh(
            vertex_matrix=out_pos.astype(np.float64),
            face_matrix=out_idx.reshape(-1, 3).astype(np.int32),
        )
    )
    k = scale * M_POR_STUD
    a = ms.get_hausdorff_distance(sampledmesh=0, targetmesh=1, samplevert=True, samplenum=20000)
    b = ms.get_hausdorff_distance(sampledmesh=1, targetmesh=0, samplevert=True, samplenum=20000)
    return max(a["max"], b["max"]) * k, max(a["mean"], b["mean"]) * k


def write_glb(js: dict, blob: bytes, out: Path, pos, nrm, uv, idx) -> bytes:
    js = json.loads(json.dumps(js))
    pr = js["meshes"][0]["primitives"][0]
    attrs = pr["attributes"]
    geo_acc = {attrs["POSITION"], attrs["NORMAL"], attrs["TEXCOORD_0"], pr["indices"]}
    geo_bv = {js["accessors"][i]["bufferView"] for i in geo_acc}
    use16 = len(pos) < 65536
    chunks: list[bytes] = []
    views: list[dict] = []
    remap: dict[int, int] = {}

    def push(data: bytes, target: int | None) -> int:
        off = sum(len(c) for c in chunks)
        pad = (-off) % 4
        if pad:
            chunks.append(b"\x00" * pad)
            off += pad
        chunks.append(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def set_acc(i: int, arr: np.ndarray, ctype: int, typ: str, target: int) -> None:
        a = js["accessors"][i]
        a.update(
            bufferView=push(arr.tobytes(), target),
            byteOffset=0,
            componentType=ctype,
            count=int(arr.shape[0]),
            type=typ,
        )
        if typ == "VEC3" and i == attrs["POSITION"]:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        else:
            a.pop("min", None)
            a.pop("max", None)

    set_acc(attrs["POSITION"], pos, 5126, "VEC3", 34962)
    set_acc(attrs["NORMAL"], nrm, 5126, "VEC3", 34962)
    set_acc(attrs["TEXCOORD_0"], uv, 5126, "VEC2", 34962)
    ind = idx.astype(np.uint16 if use16 else np.uint32)
    set_acc(pr["indices"], ind, 5123 if use16 else 5125, "SCALAR", 34963)
    # demais bufferViews (imagens): copiados como estão
    for i, bv in enumerate(js["bufferViews"]):
        if i in geo_bv:
            continue
        s = bv.get("byteOffset", 0)
        remap[i] = push(blob[s : s + bv["byteLength"]], bv.get("target"))
    for img in js.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = remap[img["bufferView"]]
    js["bufferViews"] = views
    body = b"".join(chunks)
    body += b"\x00" * ((-len(body)) % 4)
    js["buffers"] = [{"byteLength": len(body)}]
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((-len(jb)) % 4)
    total = 12 + 8 + len(jb) + 8 + len(body)
    data = (
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(jb), b"JSON")
        + jb
        + struct.pack("<I4s", len(body), b"BIN\x00")
        + body
    )
    out.write_bytes(data)
    return data


def bounds_studs(js: dict, blob: bytes) -> list[float]:
    pos = accessor(js, blob, js["meshes"][0]["primitives"][0]["attributes"]["POSITION"])
    s = node_scale(js)
    return [round(float(x) * s, 2) for x in (pos.max(axis=0) - pos.min(axis=0))]


def run(src: Path, dst: Path, faces: int, free_borders: bool = False) -> dict:
    js, blob = read_glb(src)
    pos, uv, f = load_mesh(js, blob)
    out_pos, out_nrm, out_uv, out_idx = decimate(pos, uv, f, faces, free_borders)
    hmax, hmean = hausdorff_m(pos, f, out_pos, out_idx, node_scale(js))
    data = write_glb(js, blob, dst, out_pos, out_nrm, out_uv, out_idx)
    js2, blob2 = read_glb(dst)
    return {
        "tris_antes": int(len(f)),
        "tris": int(len(out_idx) // 3),
        "vertices": int(len(out_pos)),
        "desvio_max_m": round(hmax, 4),
        "desvio_medio_m": round(hmean, 5),
        "dim_antes": bounds_studs(js, blob),
        "dim_studs_xyz": bounds_studs(js2, blob2),
        "bytes": len(data),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("entrada", type=Path)
    ap.add_argument("saida", type=Path)
    ap.add_argument("--faces", type=int, required=True)
    ap.add_argument("--soltar-bordas", action="store_true", help="folhagem: solta a borda (D-65)")
    a = ap.parse_args()
    print(json.dumps(run(a.entrada, a.saida, a.faces, a.soltar_bordas), ensure_ascii=False))


if __name__ == "__main__":
    main()
