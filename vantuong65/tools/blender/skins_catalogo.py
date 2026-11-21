"""Imagens dos acabamentos de arma (D-229; dono: "melhore as imagens da skin").

Antes, cada cartão mostrava a arma num ViewportFrame com a luz chapada do Roblox. Aqui cada
acabamento sai no mesmo estúdio das imagens de `armas_catalogo.py`, sem renderizar 347 vezes:

1. por arma, o Cycles faz só as passadas de luz, com a arma do jogo (o relevo dela fica): difusa,
   brilho agudo e brilho fosco, mais uma de coordenadas UV em dobro da resolução;
2. por acabamento, a cor, o metal e a aspereza dele (`assets/acabamentos`, as texturas do jogo)
   são lidos pela UV e combinados com essa luz;
3. a revelação é a mesma AgX das outras imagens.

Saída: `assets/ui/skins/<id>.png` (o `@` do universal vira `__`), 640 x 320, RGBA.

Uso (sempre na CPU: a GPU de 2 GB é do Studio):
    $env:VT65_CPU = "1"; $env:VT65_THREADS = "4"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/skins_catalogo.py -- [armas...] [--so id1,id2] [--amostras N] `
        [--saida PASTA]

As passadas ficam em `assets/blender/_trabalho/skins/<arma>_*.exr`; com `--reusar`, não renderiza de
novo e só refaz a combinação.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import armas_catalogo as A  # noqa: E402
import comum as C  # noqa: E402
import loja as L  # noqa: E402

RAIZ = C.RAIZ
ACAB = RAIZ / "assets" / "acabamentos"
META = RAIZ / "assets" / "acabamentos_meta.json"
SAIDA = RAIZ / "assets" / "ui" / "skins"
TRABALHO = C.TRABALHO / "skins"
LARG, ALT = 640, 320
UV_ESCALA = 2  # a textura é lida em dobro e reduzida: a borda e o padrão fino saem sem serrilhado
BASE_DIFUSA = 0.8
RUG_AGUDA, RUG_FOSCA = 0.22, 0.62


def log(*a):
    print("[VT65]", *a, flush=True)


# ------------------------------------------------------------------ passadas de luz
def materiais_de_luz(obj) -> list:
    """Cópias dos materiais da arma com a cor, o metal e a aspereza soltos (a normal continua)."""
    copias = []
    for slot in obj.material_slots:
        if slot.material is None or not slot.material.use_nodes:
            continue
        m = slot.material.copy()
        nt = m.node_tree
        b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if b is None:
            continue
        for nome in ("Base Color", "Metallic", "Roughness"):
            for li in list(b.inputs[nome].links):
                nt.links.remove(li)
        slot.material = m
        copias.append(b)
    return copias


def ajusta(bsdfs, base: float, metal: float, rug: float, espec: float):
    for b in bsdfs:
        b.inputs["Base Color"].default_value = (base, base, base, 1.0)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rug
        b.inputs["Specular IOR Level"].default_value = espec


def material_uv(obj) -> bpy.types.Material:
    m = bpy.data.materials.new("PassadaUV")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = obj.data.uv_layers.active.name
    em = nt.nodes.new("ShaderNodeEmission")
    saida = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(uv.outputs["UV"], em.inputs["Color"])
    nt.links.new(em.outputs[0], saida.inputs["Surface"])
    return m


def grava_exr(cena, caminho: Path):
    s = cena.render.image_settings
    s.file_format = "OPEN_EXR"
    s.color_mode = "RGBA"
    s.color_depth = "32"
    s.exr_codec = "ZIP"
    cena.render.filepath = str(caminho)
    bpy.ops.render.render(write_still=True)


def passadas(chave: str, amostras: int):
    C.cena_vazia()
    cena = bpy.context.scene
    L.configurar(cena, LARG, ALT, amostras)
    A.acabar(cena)
    A.mundo_estudio(cena)
    obj = A.arma_canonica(chave)
    lo, hi = C.caixa(obj)
    tam = hi - lo
    centro = Vector(((lo + hi) / 2).tolist())
    r = float(max(tam[0], tam[2] * 2)) / 2
    A.camera_orto(centro, float(tam[0]), float(tam[2]), LARG, ALT)
    A.luzes_catalogo(centro, r)
    sombra = A.apanha_sombra((centro.x, float(hi[1]) + 0.15 * r, centro.z), (0, -1, 0), 40 * r)
    TRABALHO.mkdir(parents=True, exist_ok=True)
    bsdfs = materiais_de_luz(obj)
    for nome, base, metal, rug, espec in (
        ("dif", BASE_DIFUSA, 0.0, 0.6, 0.0),
        ("agu", 1.0, 1.0, RUG_AGUDA, 0.5),
        ("fos", 1.0, 1.0, RUG_FOSCA, 0.5),
    ):
        ajusta(bsdfs, base, metal, rug, espec)
        t = time.time()
        grava_exr(cena, TRABALHO / f"{chave}_{nome}.exr")
        log("passada", chave, nome, round(time.time() - t, 1), "s")
    # coordenadas: uma amostra por pixel, sem filtro e sem denoise (média de UV não existe)
    sombra.hide_render = True
    for slot in obj.material_slots:
        slot.material = material_uv(obj)
    cena.render.resolution_x = LARG * UV_ESCALA
    cena.render.resolution_y = ALT * UV_ESCALA
    cena.cycles.samples = 1
    cena.cycles.use_adaptive_sampling = False
    cena.cycles.use_denoising = False
    cena.cycles.pixel_filter_type = "BOX"
    cena.cycles.filter_width = 0.01
    grava_exr(cena, TRABALHO / f"{chave}_uv.exr")


# ------------------------------------------------------------------ leitura
def ler(caminho: Path) -> np.ndarray:
    """RGBA em float, na ordem do Blender (linha 0 embaixo, como a coordenada V)."""
    img = bpy.data.images.load(str(caminho), check_existing=False)
    img.colorspace_settings.name = "Non-Color"
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)


def lin(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def amostra(t: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Bilinear, com a textura repetindo."""
    h, w = t.shape[:2]
    x = (u % 1.0) * w - 0.5
    y = (v % 1.0) * h - 0.5
    x0, y0 = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    x0, y0 = x0 % w, y0 % h
    x1, y1 = (x0 + 1) % w, (y0 + 1) % h
    return (t[y0, x0] * (1 - fx) + t[y0, x1] * fx) * (1 - fy) + (
        t[y1, x0] * (1 - fx) + t[y1, x1] * fx
    ) * fy


def amplia(t: np.ndarray, k: int) -> np.ndarray:
    """Luz na resolução da UV. Sem premultiplicar: a borda da arma não puxa o preto do fundo."""
    h, w = t.shape[:2]
    a = np.clip(t[..., 3:4], 1e-4, 1.0)
    rgb = t[..., :3] / a
    ys = (np.arange(h * k) + 0.5) / k - 0.5
    xs = (np.arange(w * k) + 0.5) / k - 0.5
    y0, x0 = (
        np.clip(np.floor(ys).astype(np.int32), 0, h - 2),
        np.clip(np.floor(xs).astype(np.int32), 0, w - 2),
    )
    fy, fx = np.clip(ys - y0, 0, 1)[:, None, None], np.clip(xs - x0, 0, 1)[None, :, None]
    return (
        rgb[y0][:, x0] * (1 - fx) * (1 - fy)
        + rgb[y0][:, x0 + 1] * fx * (1 - fy)
        + rgb[y0 + 1][:, x0] * (1 - fx) * fy
        + rgb[y0 + 1][:, x0 + 1] * fx * fy
    )


def rampa(n: int, m: int) -> np.ndarray:
    a = np.clip(np.minimum(np.arange(n), np.arange(n)[::-1]) / m, 0.0, 1.0)
    return a * a * (3 - 2 * a)


# ------------------------------------------------------------------ combinação
def revela(cena, rgb: np.ndarray, alfa: np.ndarray, destino: Path):
    """Revelação AgX da cena sobre a cor (opaca), com o alfa posto depois (como `apagar_bordas`)."""
    h, w = rgb.shape[:2]
    img = bpy.data.images.new("Revela", w, h, alpha=True, float_buffer=True)
    px = np.ones((h, w, 4), np.float32)
    px[..., :3] = rgb
    img.pixels.foreach_set(px.reshape(-1))
    tmp = TRABALHO / "_revela.png"
    s = cena.render.image_settings
    s.file_format = "PNG"
    s.color_mode = "RGBA"
    s.color_depth = "8"
    img.save_render(str(tmp), scene=cena)
    bpy.data.images.remove(img)
    sai = bpy.data.images.load(str(tmp), check_existing=False)
    p2 = np.empty(w * h * 4, np.float32)
    sai.pixels.foreach_get(p2)
    p2 = p2.reshape(h, w, 4)
    p2[..., 3] = alfa
    sai.pixels.foreach_set(p2.reshape(-1))
    sai.filepath_raw = str(destino)
    sai.file_format = "PNG"
    sai.save()
    bpy.data.images.remove(sai)


def combina(cena, chave: str, itens: list, destino: Path):
    k = UV_ESCALA
    dif_b = ler(TRABALHO / f"{chave}_dif.exr")
    dif = amplia(dif_b, k)
    agu = amplia(ler(TRABALHO / f"{chave}_agu.exr"), k)
    fos = amplia(ler(TRABALHO / f"{chave}_fos.exr"), k)
    uv = ler(TRABALHO / f"{chave}_uv.exr")
    H, W = uv.shape[:2]
    masc = uv[..., 3] > 0.5
    iy, ix = np.nonzero(masc)
    u, v = uv[iy, ix, 0], uv[iy, ix, 1]
    d, a, f = dif[iy, ix], agu[iy, ix], fos[iy, ix]
    # alfa final: a arma (em dobro, reduzida) sobre a sombra da passada difusa
    cobre = masc.reshape(H // k, k, W // k, k).mean(axis=(1, 3)).astype(np.float32)
    h, w = H // k, W // k
    sombra = np.clip(dif_b[..., 3], 0, 1)
    alfa = np.maximum(cobre, sombra)
    alfa *= rampa(h, max(1, int(h * 0.09)))[:, None] * rampa(w, max(1, int(w * 0.045)))[None, :]
    destino.mkdir(parents=True, exist_ok=True)
    for sid, info in itens:
        cor = ler(ACAB / f"{sid}.png")
        alb = lin(amostra(cor[..., :3], u, v))
        cl = info.get("classe")
        if cl and (ACAB / "classes" / f"{cl}_m.png").exists():
            m = amostra(ler(ACAB / "classes" / f"{cl}_m.png")[..., :1], u, v)
            ru = amostra(ler(ACAB / "classes" / f"{cl}_r.png")[..., :1], u, v)
        else:
            m, ru = np.zeros((len(u), 1), np.float32), np.full((len(u), 1), 0.55, np.float32)
        q = np.clip((ru - RUG_AGUDA) / (RUG_FOSCA - RUG_AGUDA), 0, 1)
        q = q * q * (3 - 2 * q)
        brilho = a * (1 - q) + f * q
        f0 = 0.04 * (1 - m) + alb * m
        cor_final = alb * (1 - m) * d / BASE_DIFUSA + f0 * brilho
        tela = np.zeros((H, W, 3), np.float32)
        tela[iy, ix] = cor_final
        # média só do que é arma: a borda não escurece (o alfa é que recorta)
        soma = tela.reshape(h, k, w, k, 3).sum(axis=(1, 3))
        n = np.maximum(masc.reshape(h, k, w, k).sum(axis=(1, 3)), 1)[..., None]
        revela(cena, soma / n, alfa, destino / f"{sid.replace('@', '__')}.png")


def principal():
    args = C.argumentos()
    amostras = int(args[args.index("--amostras") + 1]) if "--amostras" in args else 32
    pasta = Path(args[args.index("--saida") + 1]) if "--saida" in args else SAIDA
    so = set(args[args.index("--so") + 1].split(",")) if "--so" in args else None
    reusar = "--reusar" in args
    pulos = {args.index(x) + 1 for x in ("--amostras", "--saida", "--so") if x in args}
    pedidas = [a for i, a in enumerate(args) if i not in pulos and not a.startswith("--")]
    meta = json.loads(META.read_text("utf-8"))
    por_arma: dict[str, list] = {}
    for sid, info in meta.items():
        if so is None or sid in so:
            por_arma.setdefault(info["arma"], []).append((sid, info))
    t0 = time.time()
    for chave in sorted(por_arma):
        if pedidas and chave not in pedidas:
            continue
        t = time.time()
        if not (reusar and (TRABALHO / f"{chave}_uv.exr").exists()):
            passadas(chave, amostras)
        t1 = time.time()
        combina(bpy.context.scene, chave, por_arma[chave], pasta)
        log(
            "ok",
            chave,
            len(por_arma[chave]),
            "imagens; luz",
            round(t1 - t, 1),
            "s; cor",
            round(time.time() - t1, 1),
            "s",
        )
    log("total", round(time.time() - t0, 1), "s")


if __name__ == "__main__":
    principal()
