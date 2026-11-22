"""Desgaste de campanha nas armas e nos veículos (D-249), direto nas texturas do GLB.

Pedido do dono: o estilo das imagens, com a arma suja, gasta e enferrujada. A malha e o UV não
mudam, então os acabamentos e os pontos da arma continuam valendo. Na cor e no mapa ORM entram:
- quinas gastas: a borda de cada ilha de UV (as arestas do modelo) mostra aço ou madeira batida;
- ferrugem só no metal, graxa escura nos cantos e poeira;
- barro: respingos na arma e, nos veículos, da parte de baixo para cima.

Saída: assets/desgaste/<chave>.glb. O GLB original não é tocado.

Uso (a partir de vantuong65):
    uv run --group arte python tools/desgaste.py --armas
    uv run --group arte python tools/desgaste.py --veiculos
    uv run --group arte python tools/desgaste.py --so m16 [--previa]
"""

from __future__ import annotations

import argparse
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SAIDA = ROOT / "assets" / "desgaste"
ARMAS = [
    "m14",
    "m16",
    "m60",
    "m1911",
    "m79",
    "type56",
    "sks",
    "rpd",
    "type54",
    "rpg2",
    "m70",
    "mosin",
    "win12",
]
VEICULOS = ["m48a3_v2", "lvtp5_v2", "ontos_v2", "uh34d_v3", "m151", "m35", "peugeot403"]
PESOS = np.array([0.299, 0.587, 0.114])
FERRUGEM_A = np.array([58.0, 37.0, 25.0])
FERRUGEM_B = np.array([118.0, 74.0, 44.0])
BARRO_A = np.array([48.0, 34.0, 22.0])
BARRO_B = np.array([112.0, 84.0, 54.0])
ACO = np.array([168.0, 162.0, 150.0])


def suave(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def fractal(n: int, rng: np.random.Generator, escala: float, oitavas: int = 5) -> np.ndarray:
    total = np.zeros((n, n), dtype=np.float32)
    amp, soma = 1.0, 0.0
    for i in range(oitavas):
        c = rng.normal(0, 1, (n, n)).astype(np.float32)
        c = ndimage.gaussian_filter(c, max(escala / 2**i, 0.6), mode="wrap")
        c /= max(float(c.std()), 1e-5)
        total += amp * c
        soma += amp
        amp *= 0.55
    return total / soma


def ler(p: Path) -> tuple[dict, bytes]:
    b = p.read_bytes()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20 : 20 + n])
    t = struct.unpack("<I", b[20 + n : 24 + n])[0]
    return j, b[28 + n : 28 + n + t]


def gravar(p: Path, j: dict, binario: bytes) -> None:
    t = json.dumps(j, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    t += b" " * ((4 - len(t) % 4) % 4)
    d = binario + b"\0" * ((4 - len(binario) % 4) % 4)
    p.write_bytes(
        struct.pack("<III", 0x46546C67, 2, 28 + len(t) + len(d))
        + struct.pack("<I", len(t))
        + b"JSON"
        + t
        + struct.pack("<I", len(d))
        + b"BIN\0"
        + d
    )


def vista(j: dict, d: bytes, ac: int) -> np.ndarray:
    a = j["accessors"][ac]
    bv = j["bufferViews"][a["bufferView"]]
    tipo = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[a["componentType"]]
    comp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    ini = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    passo = bv.get("byteStride")
    tam = np.dtype(tipo).itemsize * comp
    if passo and passo != tam:
        bruto = np.frombuffer(d, np.uint8, a["count"] * passo, ini).reshape(-1, passo)[:, :tam]
        arr = np.frombuffer(bruto.tobytes(), tipo)
    else:
        arr = np.frombuffer(d, tipo, a["count"] * comp, ini)
    return arr.reshape(-1, comp) if comp > 1 else arr


def mapas_uv(j: dict, d: bytes, n: int) -> tuple[np.ndarray, np.ndarray]:
    """Máscara das ilhas de UV e a altura (0 embaixo, 1 em cima) de cada pixel."""
    pos = []
    for me in j["meshes"]:
        for pr in me["primitives"]:
            pos.append(vista(j, d, pr["attributes"]["POSITION"]))
    # eixo vertical: GLB usa Y para cima
    tudo = np.concatenate(pos)
    y0, y1 = float(tudo[:, 1].min()), float(tudo[:, 1].max())
    m = Image.new("L", (n, n), 0)
    alt = Image.new("F", (n, n), 0.5)
    dm, da = ImageDraw.Draw(m), ImageDraw.Draw(alt)
    for me in j["meshes"]:
        for pr in me["primitives"]:
            if "TEXCOORD_0" not in pr["attributes"]:
                continue
            uv = vista(j, d, pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
            py = vista(j, d, pr["attributes"]["POSITION"])[:, 1]
            idx = vista(j, d, pr["indices"]).astype(np.int64).reshape(-1, 3)
            px = np.mod(uv, 1.0) * n
            for a, b, c in idx:
                q = [tuple(px[a]), tuple(px[b]), tuple(px[c])]
                dm.polygon(q, fill=255)
                da.polygon(q, fill=float((py[a] + py[b] + py[c]) / 3 - y0) / max(y1 - y0, 1e-5))
    return np.asarray(m, dtype=np.float32) / 255, np.asarray(alt, dtype=np.float32)


def imagem(j: dict, d: bytes, i: int) -> Image.Image:
    bv = j["bufferViews"][j["images"][i]["bufferView"]]
    ini = bv.get("byteOffset", 0)
    return Image.open(io.BytesIO(d[ini : ini + bv["byteLength"]]))


def reconstruir(j: dict, d: bytes, novas: dict[int, tuple[bytes, str]]) -> bytes:
    troca = {j["images"][i]["bufferView"]: v for i, v in novas.items()}
    for i, (_, mime) in novas.items():
        j["images"][i]["mimeType"] = mime
    saida = bytearray()
    for k, bv in enumerate(j["bufferViews"]):
        ini = bv.get("byteOffset", 0)
        dado = troca[k][0] if k in troca else d[ini : ini + bv["byteLength"]]
        saida += b"\0" * ((4 - len(saida) % 4) % 4)
        bv["byteOffset"] = len(saida)
        bv["byteLength"] = len(dado)
        saida += dado
    j["buffers"][0]["byteLength"] = len(saida)
    return bytes(saida)


def gastar(chave: str, veiculo: bool, previa: bool) -> None:
    texto = (ROOT / "assets/upload_plan.json").read_text("utf-8")
    plano = {e["key"]: e for e in json.loads(texto)}
    item = plano[f"Models.{chave}"]
    origem = ROOT / item.get("file_limpo", item["file"])  # nunca gasta o que já foi gasto
    j, d = ler(origem)
    mat = j["materials"][0]["pbrMetallicRoughness"]
    ic = j["textures"][mat["baseColorTexture"]["index"]]["source"]
    im = j["textures"][mat["metallicRoughnessTexture"]["index"]]["source"]
    cor0 = imagem(j, d, ic).convert("RGB")
    orm0 = imagem(j, d, im).convert("RGB")
    lado = cor0.width
    n = min(lado, 2048)
    cor = np.asarray(cor0.resize((n, n), Image.LANCZOS), dtype=np.float32)
    orm = np.asarray(orm0.resize((n, n), Image.BILINEAR), dtype=np.float32)
    rng = np.random.default_rng(sum(ord(c) * (i + 3) for i, c in enumerate(chave)))
    k = n / 1024

    ilha, alt = mapas_uv(j, d, n)
    dentro = ilha > 0.5
    dist = ndimage.distance_transform_edt(dentro)
    lum = cor @ PESOS
    sat = (cor.max(axis=2) - cor.min(axis=2)) / np.maximum(cor.max(axis=2), 1)
    metal = suave(90, 180, orm[..., 2])
    if not veiculo:  # nas armas do gerador o aço escuro nem sempre vem marcado como metal
        metal = np.maximum(metal, suave(0.34, 0.14, sat) * suave(140, 80, lum))
    madeira = (1 - metal) * suave(0.28, 0.5, sat) * suave(40, 80, lum)

    # graxa nas partes escuras do relevo largo
    g = fractal(n, rng, 46 * k)
    cor *= (0.80 + 0.16 * suave(-1.3, 1.1, g))[..., None]

    # quinas gastas
    ruido = fractal(n, rng, 5 * k, 4)
    borda = np.exp(-dist / (2.4 * k)) * suave(-0.5, 0.9, ruido) * dentro
    borda = np.clip(borda * 1.25, 0, 1)
    cor_quina = cor * (1 - metal[..., None]) * 1.55 + ACO * metal[..., None]
    kq = (borda * (0.62 * metal + 0.42 * madeira + 0.14 * (1 - metal) * (1 - madeira)))[..., None]
    cor = cor * (1 - kq) + np.clip(cor_quina, 0, 255) * kq
    orm[..., 1] = orm[..., 1] * (1 - borda * metal * 0.45)

    # ferrugem no metal
    f = fractal(n, rng, 20 * k)
    fino = fractal(n, rng, 3 * k, 3)
    limiar = 0.85 if veiculo else 0.68
    ferr = suave(limiar, limiar + 0.75, f + 0.32 * fino + 0.55 * borda) * metal
    tom = suave(-1.0, 1.0, fractal(n, rng, 6 * k, 3))[..., None]
    corf = FERRUGEM_A * (1 - tom) + FERRUGEM_B * tom
    kf = (ferr * 0.74)[..., None]
    cor = cor * (1 - kf) + corf * kf
    orm[..., 1] = orm[..., 1] * (1 - ferr) + 225 * ferr
    orm[..., 2] = orm[..., 2] * (1 - ferr * 0.92)

    # barro
    b = fractal(n, rng, 12 * k)
    if veiculo:
        chance = 2.5 * suave(0.62, 0.05, alt) - 1.5
    else:
        chance = np.full((n, n), -1.02, dtype=np.float32)
    barro = suave(0.0, 0.42, b + chance)
    pingos = Image.new("L", (n, n), 0)
    dp = ImageDraw.Draw(pingos)
    qtd = int((2600 if veiculo else 520) * k * k)
    for _ in range(qtd):
        x, y = rng.uniform(0, n), rng.uniform(0, n)
        if veiculo and float(alt[int(y) % n, int(x) % n]) > float(rng.uniform(0.25, 0.9)):
            continue
        r = float(rng.uniform(0.5, 2.8)) ** 1.5 * k
        dp.ellipse(
            (x - r, y - r, x + r, y + r * float(rng.uniform(1, 1.8))),
            fill=int(rng.integers(120, 255)),
        )
    barro = np.clip(barro + np.asarray(pingos, dtype=np.float32) / 255, 0, 1)
    tom = suave(-1.1, 1.2, fractal(n, rng, 4 * k, 3))[..., None]
    corb = BARRO_A * (1 - tom) + BARRO_B * tom
    kb = (barro * 0.9)[..., None]
    cor = cor * (1 - kb) + corb * kb
    orm[..., 1] = orm[..., 1] * (1 - barro) + 235 * barro
    orm[..., 2] = orm[..., 2] * (1 - barro)

    # fora das ilhas fica como estava (a borda do filtro de textura não pega cor nova errada)
    fora = (~ndimage.binary_dilation(dentro, iterations=int(3 * k)))[..., None]
    base = np.asarray(cor0.resize((n, n), Image.LANCZOS), dtype=np.float32)
    cor = np.where(fora, base, cor)

    saida_c = Image.fromarray(cor.clip(0, 255).round().astype(np.uint8), "RGB")
    saida_o = Image.fromarray(orm.clip(0, 255).round().astype(np.uint8), "RGB")
    bc, bo = io.BytesIO(), io.BytesIO()
    saida_c.save(bc, "JPEG", quality=90, subsampling=0)
    saida_o.save(bo, "JPEG", quality=90)
    novo = reconstruir(j, d, {ic: (bc.getvalue(), "image/jpeg"), im: (bo.getvalue(), "image/jpeg")})
    SAIDA.mkdir(parents=True, exist_ok=True)
    gravar(SAIDA / f"{chave}.glb", j, novo)
    if previa:
        tela = Image.new("RGB", (1000, 500))
        tela.paste(cor0.resize((500, 500)), (0, 0))
        tela.paste(saida_c.resize((500, 500)), (500, 0))
        tela.save(SAIDA / f"previa_{chave}.jpg", quality=88)
    tamanho = (SAIDA / f"{chave}.glb").stat().st_size // 1024
    print(f"ok {chave}: {tamanho} KB, ferrugem {float((ferr > 0.5).mean()) * 100:.1f}%", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--armas", action="store_true")
    ap.add_argument("--veiculos", action="store_true")
    ap.add_argument("--so")
    ap.add_argument("--previa", action="store_true")
    a = ap.parse_args()
    alvos = [(c, False) for c in ARMAS] if a.armas else []
    if a.veiculos:
        alvos += [(c, True) for c in VEICULOS]
    if a.so:
        alvos = [(c, c in VEICULOS) for c in a.so.split(",")]
    for chave, veiculo in alvos:
        gastar(chave, veiculo, a.previa)


if __name__ == "__main__":
    main()
