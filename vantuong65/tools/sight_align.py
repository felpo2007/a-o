"""Linha de mira de verdade de cada arma: centro da alça (anel ou entalhe) e topo da massa (D-67).

Pedido do usuário (2026-11-11): "concerte as miras coloque o anel e os risco da mira centralizados".
Até a D-66 o ponto Sight era um ponto de conta (9 cm à frente da mão direita, na altura da massa):
a linha ia dele ao topo da massa, e a alça de verdade (o anel da M14, o entalhe da Type 56) ficava
onde caísse, fora do centro da tela.

Aqui, no referencial alinhado do tools/weapon_landmarks.py (Roblox, centro da caixa, eixo longo
exato), para cada arma:
1. alça: fatia da malha numa janela ao longo do cano, vista de frente (lateral × altura) em
   0,2 mm por pixel. "anel" = furo fechado perto do plano do cano → centro do furo. "entalhe" =
   vale no topo do perfil perto do plano do cano → meio do vale, na altura dos ombros (a massa
   aparece rente aos ombros, como na visada certa);
2. massa: fatia da massa; o ponto mais alto a até POST_HALF_M do plano do cano (as orelhas e o
   túnel ficam de fora).
3. olho (no tools/weapon_landmarks.py): na reta alça → massa, atrás da alça: anel a 4,5 cm;
   entalhe sobre o punho.
"conta" (espingarda do Blender, 2026-11-13): sem alça; a "alça" é o topo da caixa da culatra perto
do plano do cano e a massa é o topo da conta de latão (também mede o diâmetro da conta). O GLB é o
do Blender (`glb`), só o nó da arma (`no`); o olho fica no eyeM do pontos.json.

Uso:
  uv run python tools/sight_align.py --side          (vistas de lado com grade, para achar janelas)
  uv run python tools/sight_align.py                 (mede, grava assets/miras/*.png e imprime)
O tools/weapon_landmarks.py lê REAR/FRONT medidos daqui (função medir).
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from weapon_landmarks import FORWARD, MODELS, M, ry, yaw_fix  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "miras"

# kind: "anel" (orifício) ou "entalhe"; rear/front: janelas em u (0 na boca, 1 na coronha).
# Preenchido olhando as vistas de lado (--side) de cada malha.
CFG: dict[str, dict] = {
    "m14": {"kind": "anel", "rear": (0.665, 0.70), "front": (0.07, 0.095)},
    "type56": {
        "kind": "entalhe",
        "rear": (0.435, 0.47),
        "front": (0.02, 0.055),
        "capuz": True,
        "half_m": 0.006,
    },
    "sks": {"kind": "entalhe", "rear": (0.415, 0.44), "front": (0.03, 0.055), "capuz": True},
    # Lote 7 (2026-11-13, dono: "a RPD não atira onde a mira aponta"): a massa da RPD fica ~5 cm
    # acima do cano a 12–15% da boca e a alça a 65–68%; a linha da D-60 usava a ponta do cano
    "rpd": {
        "kind": "entalhe",
        "rear": (0.655, 0.68),
        "front": (0.115, 0.15),
        "janela_m": (-0.04, 0.04, -0.01, 0.08),
        "capuz": True,  # massa num capuz de anel aberto em cima: a ponta é o poste dentro dele
    },
    # M60: massa com capuz a 8–12% da boca (~11 cm acima do cano). A alça da malha não tem entalhe
    # limpo (três dentes, o do meio fora da linha da massa): "topo" = o olho passa rente ao dente
    # que fica na linha da massa (2 mm à esquerda do cano)
    "m60": {
        "kind": "topo",
        "rear": (0.70, 0.73),
        "front": (0.08, 0.12),
        "janela_m": (-0.05, 0.05, 0.0, 0.14),
        "center_m": -0.002,
        "half_m": 0.004,
        "capuz": True,
    },
    # Armas do Blender com GLB próprio (tools/blender/espingarda.py): só o nó "Arma" (a MeshPart
    # que recebe os pontos), boca em -Z. "conta": espingarda sem alça; a massa é a conta de latão
    # na boca e a "alça" é o topo de trás da caixa da culatra (o olho alinha a conta com ele).
    "win12": {
        "kind": "conta",
        "glb": ROOT / "assets/blender/arma_win12/arma_win12.glb",
        "no": "Arma",
        "forward": "-Z",
        "rear": (0.646, 0.666),  # d 0,335–0,355 m da soleira: o topo plano da caixa da culatra
        "front": (0.012, 0.028),  # a conta (d 0,983 m) sobre o anel do adaptador de baioneta
        "half_m": 0.004,
    },
}
# M60, RPD, M79, pistolas e RPG-2 seguem com a linha de visada da D-60 (tools/weapon_landmarks.py):
# na M60 a fatia da alça (u 0,705–0,73, até 11 cm acima do cano) não mostrou furo fechado.

PX_M = 0.0002  # 0,2 mm por pixel na fatia
POST_HALF_M = 0.003  # meia largura da faixa da massa


def load_tris(path: Path, so_no: str | None = None) -> tuple[np.ndarray, np.ndarray]:
    """Triângulos do GLB no espaço da MeshPart (giro de 180° em Y, centro da caixa). Com `so_no`,
    só a malha desse nó (o modelo do Blender tem as peças móveis em nós à parte)."""
    data = path.read_bytes()
    off = 12
    js: dict | None = None
    binb = b""
    while off < len(data):
        ln, typ = struct.unpack_from("<II", data, off)
        chunk = data[off + 8 : off + 8 + ln]
        if typ == 0x4E4F534A:
            js = json.loads(chunk)
        else:
            binb = chunk
        off += 8 + ln
    assert js is not None
    pts: list[np.ndarray] = []
    tris: list[np.ndarray] = []
    base = 0
    ct = {5123: np.uint16, 5125: np.uint32, 5121: np.uint8}

    def acc(i: int) -> np.ndarray:
        a = js["accessors"][i]
        bv = js["bufferViews"][a["bufferView"]]
        start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        if a["type"] == "VEC3":
            return np.frombuffer(binb, np.float32, a["count"] * 3, start).reshape(-1, 3)
        return np.frombuffer(binb, ct[a["componentType"]], a["count"], start)

    def walk(idx: int, parent: np.ndarray) -> None:
        nonlocal base
        n = js["nodes"][idx]
        m = np.eye(4)
        if "matrix" in n:
            m = np.array(n["matrix"]).reshape(4, 4).T
        else:
            x, y, z, w = n.get("rotation", [0, 0, 0, 1])
            r = np.array(
                [
                    [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                    [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                    [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
                ]
            )
            m[:3, :3] = r * np.array(n.get("scale", [1, 1, 1]))
            m[:3, 3] = n.get("translation", [0, 0, 0])
        world = parent @ m
        if "mesh" in n and (so_no is None or n.get("name") == so_no):
            for prim in js["meshes"][n["mesh"]]["primitives"]:
                p = acc(prim["attributes"]["POSITION"]).astype(np.float64)
                pts.append((np.c_[p, np.ones(len(p))] @ world.T)[:, :3])
                tris.append(acc(prim["indices"]).astype(np.int64).reshape(-1, 3) + base)
                base += len(p)
        for c in n.get("children", []):
            walk(c, world)

    for r in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))
    p = np.vstack(pts)
    p[:, 0] *= -1  # importador do Roblox: 180° em Y (igual ao weapon_landmarks)
    p[:, 2] *= -1
    return p - (p.min(0) + p.max(0)) / 2, np.vstack(tris)


class Arma:
    """Malha no referencial alinhado: u (0 boca, 1 coronha), lateral e altura."""

    def __init__(self, key: str):
        self.key = key
        cfg = CFG.get(key, {})
        fwd = cfg.get("forward") or FORWARD[key]
        if "glb" in cfg:  # arma do Blender: GLB próprio, só o nó da arma
            mesh, self.tri = load_tris(cfg["glb"], cfg.get("no"))
        else:
            mesh, self.tri = load_tris(MODELS / f"{key}_studs.glb")
        self.rot = ry(yaw_fix(mesh, fwd))
        self.p = mesh @ self.rot.T
        self.ax = 0 if fwd[1] == "X" else 2
        self.lat = 2 - self.ax
        lo, hi = self.p[:, self.ax].min(), self.p[:, self.ax].max()
        self.length = hi - lo
        self.sign = 1 if fwd[0] == "+" else -1
        self.muzzle_end = hi if self.sign > 0 else lo
        self.u = (self.muzzle_end - self.p[:, self.ax]) * self.sign / self.length
        q = self.p[self.u < 0.015]
        self.bore_y = float(np.median(q[:, 1]))
        self.bore_lat = float(np.median(q[:, self.lat]))

    def along(self, uu: float) -> float:
        return float(self.muzzle_end - self.sign * uu * self.length)

    def ponto(self, uu: float, y: float, lateral: float) -> np.ndarray:
        v = np.zeros(3)
        v[1] = y
        v[self.ax] = self.along(uu)
        v[self.lat] = lateral
        return v

    def malha(self, v: np.ndarray) -> list[float]:
        """Alinhado → espaço da MeshPart (o que o WeaponArt guarda)."""
        return [round(float(c), 4) for c in self.rot.T @ v]

    def fatia(self, u0: float, u1: float) -> np.ndarray:
        """Triângulos com vértice dentro da janela (lateral e altura em m, relativos ao cano)."""
        tu = self.u[self.tri]
        sel = (tu.max(axis=1) >= u0) & (tu.min(axis=1) <= u1)
        t = self.p[self.tri[sel]]
        return np.stack([(t[..., self.lat] - self.bore_lat) * M, (t[..., 1] - self.bore_y) * M], -1)


def raster(tris2d: np.ndarray, lo: np.ndarray, hi: np.ndarray, px: float) -> np.ndarray:
    w = int(np.ceil((hi[0] - lo[0]) / px))
    h = int(np.ceil((hi[1] - lo[1]) / px))
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for t in tris2d:
        pts = [((x - lo[0]) / px, (hi[1] - y) / px) for x, y in t]
        d.polygon(pts, fill=255)
    return np.asarray(img) > 0


def medir(key: str, cfg: dict) -> dict:
    a = Arma(key)
    out: dict = {"key": key, "kind": cfg["kind"]}
    # ---- alça ----
    t = a.fatia(*cfg["rear"])
    jx0, jx1, jy0, jy1 = cfg.get("janela_m", (-0.03, 0.03, -0.01, 0.06))
    lo = np.array([jx0, jy0])
    hi = np.array([jx1, jy1])
    sol = raster(t, lo, hi, PX_M)
    h, w = sol.shape
    xs = lo[0] + (np.arange(w) + 0.5) * PX_M
    ys = hi[1] - (np.arange(h) + 0.5) * PX_M
    if cfg["kind"] == "anel":
        fundo, n = ndimage.label(~sol)
        borda = set(np.unique(np.concatenate([fundo[0], fundo[-1], fundo[:, 0], fundo[:, -1]])))
        melhor = None
        for k in range(1, n + 1):
            if k in borda:
                continue
            yy, xx = np.nonzero(fundo == k)
            if len(yy) < 20:
                continue
            cx, cy = xs[xx].mean(), ys[yy].mean()
            dist = abs(cx)
            if melhor is None or dist < melhor[0]:
                melhor = (dist, cx, cy, len(yy))
        if melhor is None:
            OUT_DIR.mkdir(parents=True, exist_ok=True)
            Image.fromarray((sol * 255).astype(np.uint8)).save(OUT_DIR / f"{key}_alca.png")
            raise SystemExit(f"{key}: nenhum furo fechado na janela da alça {cfg['rear']}")
        rear = (melhor[1], melhor[2])
        out["furo_mm"] = round(2 * np.sqrt(melhor[3] / np.pi) * PX_M * 1000, 2)
    elif cfg["kind"] in ("conta", "topo"):
        # sem alça: o ponto mais alto perto do plano do cano (topo da caixa da culatra)
        topo = np.full(w, np.nan)
        for j in range(w):
            col = np.nonzero(sol[:, j])[0]
            if len(col):
                topo[j] = ys[col.min()]
        meio = np.abs(xs - cfg.get("center_m", 0.0)) < cfg.get("half_m", 0.004)
        perfil = np.where(meio, topo, np.nan)
        if np.isnan(perfil).all():
            OUT_DIR.mkdir(parents=True, exist_ok=True)
            Image.fromarray((sol * 255).astype(np.uint8)).save(OUT_DIR / f"{key}_alca.png")
            raise SystemExit(f"{key}: nada perto do plano do cano na janela {cfg['rear']}")
        y_top = float(np.nanmax(perfil))
        cols = np.nonzero(meio & (topo >= y_top - 0.0002))[0]
        rear = (float(xs[cols].mean()), y_top)
    else:
        topo = np.full(w, np.nan)
        for j in range(w):
            col = np.nonzero(sol[:, j])[0]
            if len(col):
                topo[j] = ys[col.min()]
        meio = np.abs(xs - cfg.get("center_m", 0.0)) < cfg.get("half_m", 0.012)
        perfil = np.where(meio, topo, np.nan)
        if np.isnan(perfil).all():
            OUT_DIR.mkdir(parents=True, exist_ok=True)
            Image.fromarray((sol * 255).astype(np.uint8)).save(OUT_DIR / f"{key}_alca.png")
            raise SystemExit(f"{key}: nada perto do plano do cano na janela da alça {cfg['rear']}")
        j_vale = int(np.nanargmin(perfil))
        y_vale = perfil[j_vale]
        esq = np.nanmax(np.where(xs < xs[j_vale], perfil, np.nan))
        dir_ = np.nanmax(np.where(xs > xs[j_vale], perfil, np.nan))
        ombro = min(esq, dir_)
        # meio do vale: colunas abaixo da metade da profundidade, perto do fundo
        corte = y_vale + 0.5 * (ombro - y_vale)
        dentro = np.nonzero(meio & (topo < corte))[0]
        cx = float(xs[dentro].mean()) if len(dentro) else float(xs[j_vale])
        rear = (cx, float(ombro))
        out["entalhe_mm"] = round((ombro - y_vale) * 1000, 2)
    # ---- massa ----
    tf = a.fatia(*cfg["front"])
    solf = raster(tf, lo, hi, PX_M)
    colf = np.abs(xs - rear[0]) < cfg.get("post_half_m", POST_HALF_M)
    linhas = np.nonzero(solf[:, colf].any(axis=1))[0]
    topo_f = int(linhas.min())
    # massa com capuz (Type 56, SKS): de cima para baixo vem o arco do capuz, um vão e a ponta da
    # massa; a ponta é o primeiro sólido depois do primeiro vão (até 25 mm abaixo do topo)
    if cfg.get("capuz"):
        cheio = solf[:, colf].any(axis=1)
        k = topo_f
        while k < h and cheio[k]:
            k += 1
        vao = k
        while k < h and not cheio[k]:
            k += 1
        if k < h and vao < k and (k - topo_f) * PX_M < 0.025:
            topo_f = k
    front_y = float(ys[topo_f])
    jcols = np.nonzero(colf & solf[topo_f])[0]
    front_x = float(xs[jcols].mean())
    if cfg["kind"] == "conta":
        # diâmetro da conta: a largura sólida contínua em volta do centro, no meio da conta
        # (a até 3,5 mm abaixo do topo, a maior largura achada antes de chegar ao anel)
        larg = 0.0
        jc = int(np.argmin(np.abs(xs - front_x)))
        for dk in range(1, int(0.0035 / PX_M)):
            linha = solf[min(topo_f + dk, h - 1)]
            if not linha[jc]:
                break
            j0 = jc
            while j0 > 0 and linha[j0 - 1]:
                j0 -= 1
            j1 = jc
            while j1 < w - 1 and linha[j1 + 1]:
                j1 += 1
            larg = max(larg, (j1 - j0 + 1) * PX_M)
            if larg > 0.008:  # já é o anel do adaptador
                break
        out["conta_mm"] = round(larg * 1000, 2)
    # posição ao longo do cano: média dos u dos vértices da massa perto do topo
    tu = a.u
    near = (
        (tu >= cfg["front"][0])
        & (tu <= cfg["front"][1])
        & (np.abs((a.p[:, 1] - a.bore_y) * M - front_y) < 0.003)
    )
    fu = float(tu[near].mean()) if near.any() else float(np.mean(cfg["front"]))
    ru = float(np.mean(cfg["rear"]))
    rear_v = a.ponto(ru, a.bore_y + rear[1] / M, a.bore_lat + rear[0] / M)
    front_v = a.ponto(fu, a.bore_y + front_y / M, a.bore_lat + front_x / M)
    out.update(
        rear_u=round(ru, 4),
        front_u=round(fu, 4),
        rear_mm=[round(rear[0] * 1000, 2), round(rear[1] * 1000, 2)],
        front_mm=[round(front_x * 1000, 2), round(front_y * 1000, 2)],
        sight=a.malha(rear_v),
        front=a.malha(front_v),
        base_m=round(float(np.linalg.norm(front_v - rear_v)) * M, 3),
    )
    # ---- imagem de conferência ----
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    vis = np.zeros((h, w, 3), np.uint8)
    vis[solf] = (90, 110, 140)
    vis[sol] = (200, 200, 200)
    im = Image.fromarray(vis)
    d = ImageDraw.Draw(im)

    def pix(x: float, y: float) -> tuple[float, float]:
        return ((x - lo[0]) / PX_M, (hi[1] - y) / PX_M)

    for (x, y), c in (((rear[0], rear[1]), (255, 60, 60)), ((front_x, front_y), (60, 255, 60))):
        px_, py_ = pix(x, y)
        d.line([(px_ - 12, py_), (px_ + 12, py_)], fill=c, width=2)
        d.line([(px_, py_ - 12), (px_, py_ + 12)], fill=c, width=2)
    im.save(OUT_DIR / f"{key}_frente.png")
    return out


def lado(key: str) -> None:
    """Vista de lado (u × altura) com grade a cada 5% e régua do cano: para escolher as janelas."""
    a = Arma(key)
    t = a.p[a.tri]
    uu = (a.muzzle_end - t[..., a.ax]) * a.sign / a.length
    yy = (t[..., 1] - a.bore_y) * M
    w, h = 2400, 520
    y0, y1 = -0.25, 0.12
    img = Image.new("RGB", (w, h), (250, 250, 245))
    d = ImageDraw.Draw(img)
    for k in range(0, 21):
        x = k / 20 * (w - 1)
        d.line([(x, 0), (x, h)], fill=(220, 120, 120) if k % 2 == 0 else (240, 200, 200))
        d.text((x + 2, 2), f"{k * 5}", fill=(160, 0, 0))
    zb = (yy - y0) / (y1 - y0)
    for i in np.argsort(t[..., a.lat].mean(axis=1)):
        pts = [(uu[i, k] * (w - 1), (1 - zb[i, k]) * (h - 1)) for k in range(3)]
        d.polygon(pts, fill=(70, 70, 80), outline=(40, 40, 40))
    yb = (1 - (0 - y0) / (y1 - y0)) * (h - 1)
    d.line([(0, yb), (w, yb)], fill=(0, 140, 0))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img.save(OUT_DIR / f"{key}_lado.png")


def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--side":
        for k in args[1:] or list(FORWARD):
            lado(k)
            print("lado", k)
        return
    for k in args or list(CFG):
        print(json.dumps(medir(k, CFG[k]), ensure_ascii=False))


if __name__ == "__main__":
    main()
