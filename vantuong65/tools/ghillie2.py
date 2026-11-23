"""Camuflagem de mato v2 (ghillie): o soldado coberto da cabeça aos pés por tiras de juta e folhas
soltas, em camadas, com volume que quebra a silhueta (pedido do dono, 2026-11-11, com foto).

Roda FORA do Blender (`uv run python tools/ghillie2.py`):
1. desenha as 3 texturas (1024 x 1024, RGBA com recorte): `assets/ghillie/ghillie2_arroz.png`,
   `ghillie2_selva.png` e `ghillie2_bambu.png`, com a MESMA disposição (as três usam a mesma malha):
   - metade de cima: 8 feixes de tiras de juta desfiadas + capim/folha, pendurados (raiz em cima);
   - faixa do meio: 8 tufos de folha em pé (raiz embaixo; as folhas do `tools/ghillie.py`);
   - faixa de baixo: 4 mantas (tiras curtas e folhas emboladas) para a camada rente ao corpo;
   - canto de cima à esquerda transparente (onde ficam as âncoras);
2. monta os cartões de cada parte do corpo R15 em 3 camadas: manta rente ao corpo (escamas),
   tiras penduradas (soltas e em X) e tufos em pé nos ombros, costas, capuz e coxas;
3. MESMO ENCAIXE da v1 (só trocar o ID): cada peça "Ghillie_<parte>" cabe na caixa da v1
   (`assets/ghillie/ghillie_fit.json` = bloco GHILLIE do `Shared/Skins.luau`) e ganha 2
   triângulos minúsculos nos cantos da caixa, mapeados num texel transparente, para a caixa da
   malha ficar IGUAL à da v1 (o Characters põe Size = caixa da v1 e solda pelo centro dela);
4. nada na frente do rosto: na cabeça só capuz para cima e para trás (z >= -0,25 abaixo do topo
   da cabeça); no tronco, o que fica na frente não passa da altura do queixo;
5. escreve `assets/blender/ghillie/ghillie.glb` e o `metricas.json` (triângulos total e por
   peça, caixas, conferência da 1ª pessoa) e chama o Blender (`tools/blender/ghillie2.py`, pelo
   `lote.py`, que espera a GPU e respeita VT65_CPU) para a `comparacao.png` (v1 x v2).

Uso: uv run python tools/ghillie2.py [--sem-render]
"""

from __future__ import annotations

import io
import json
import math
import sys
from pathlib import Path

import numpy as np

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(AQUI / "blender"))
import ghillie as G1  # noqa: E402  (v1: paletas, desenho de folha, partes R15)
import glb  # noqa: E402

SAIDA_TEX = RAIZ / "assets" / "ghillie"
SAIDA = RAIZ / "assets" / "blender" / "ghillie"
FIT_V1 = SAIDA_TEX / "ghillie_fit.json"
SEMENTE = 1965_0818 + 2
TEX = 1024
SS = 3  # superamostragem do desenho

# ---------------------------------------------------------------- disposição da textura (px)
# (x0, y0, w, h) com y de cima para baixo
CEL_TIRA = [(k * 128, 0, 128, 512) for k in range(8)]
CEL_TUFO = [(k * 128, 512, 128, 256) for k in range(8)]
CEL_MANTA = [(k * 256, 768, 256, 256) for k in range(4)]
TEXEL_VAZIO = (3.5, 3.5)  # px: canto transparente (âncoras)

# juta tingida por variante (cor de fibra: escura, média, clara)
JUTA = {
    "arroz": ((112, 96, 62), (150, 130, 88), (190, 172, 124)),
    "selva": ((52, 52, 32), (74, 70, 44), (98, 92, 58)),
    "bambu": ((92, 88, 50), (122, 116, 70), (152, 146, 94)),
}
FOLHAS = {
    "arroz": (G1.ARROZ_VERDE, G1.ARROZ_PALHA),
    "selva": (G1.SELVA, G1.SELVA_SECA),
    "bambu": (G1.BAMBU, G1.BAMBU_VELHA),
}


# =============================================================== textura
def _tira(dr, da, pts, larg, cores, tom, rng) -> None:
    """Tira de juta ao longo da curva (raiz no 1º ponto): faixa de largura quase constante,
    trama (riscos escuros atravessados), borda desfiada e a ponta abrindo em fios."""
    n = len(pts) - 1
    esq, dir_ = [], []
    for k, p in enumerate(pts):
        t = k / n
        w = larg * (1.0 - 0.25 * t) * (1 + 0.12 * math.sin(7 * t + rng.uniform(0, 6)))
        a, b = pts[max(k - 1, 0)], pts[min(k + 1, n)]
        dv = b - a
        nv = np.array([-dv[1], dv[0]]) / max(np.linalg.norm(dv), 1e-6)
        esq.append(tuple(p + nv * w / 2))
        dir_.append(tuple(p - nv * w / 2))
    corte = int(n * rng.uniform(0.78, 0.9))
    poly = esq[: corte + 1] + dir_[: corte + 1][::-1]
    dr.polygon(poly, fill=G1._grad(cores, 0.55, tom))
    da.polygon(poly, fill=255)
    # trama: riscos escuros e claros atravessados
    for k in range(1, corte, 2):
        c = G1._grad(cores, 0.15 if k % 4 == 1 else 0.85, tom)
        dr.line([esq[k], dir_[k]], fill=c, width=max(1, int(larg * 0.06)))
    # fios soltos na borda e na ponta
    for k in range(corte, n + 1):
        for lado in (esq, dir_):
            if rng.random() < 0.7:
                q0 = np.array(lado[min(k, n)])
                q1 = (
                    q0
                    + (pts[min(k + 1, n)] - pts[k]) * rng.uniform(0.6, 1.6)
                    + rng.normal(0, larg * 0.15, 2)
                )
                dr.line(
                    [tuple(q0), tuple(q1)],
                    fill=G1._grad(cores, rng.uniform(0.3, 0.9), tom),
                    width=max(2, int(larg * 0.08)),
                )
                da.line([tuple(q0), tuple(q1)], fill=255, width=max(2, int(larg * 0.08)))
    for _ in range(int(rng.integers(2, 5))):
        k = int(rng.integers(1, corte))
        lado = esq if rng.random() < 0.5 else dir_
        q0 = np.array(lado[k])
        q1 = q0 + rng.normal(0, larg * 0.5, 2)
        dr.line(
            [tuple(q0), tuple(q1)], fill=G1._grad(cores, 0.7, tom), width=max(2, int(larg * 0.07))
        )
        da.line([tuple(q0), tuple(q1)], fill=255, width=max(2, int(larg * 0.07)))


def _feixe(dr, da, cx, chao, ch, var, rng, curto=False) -> None:
    """Feixe pendurado desenhado de pé (raiz embaixo; depois a célula é virada): 4 a 8 tiras de juta
    e 2 a 6 folhas/capim do tipo."""
    verde, seca = FOLHAS[var]
    juta = JUTA[var]
    n_t = int(rng.integers(5, 9))
    for _ in range(n_t):
        ang = float(np.clip(rng.normal(0, 0.05), -0.1, 0.1))
        comp = ch * rng.uniform(0.6, 0.98) * (0.55 if curto else 1.0)
        curva = rng.uniform(-0.12, 0.12)
        pts = G1._curva(cx + rng.normal(0, 7 * SS), chao, ang, comp, curva, 16)
        _tira(dr, da, pts, rng.uniform(12, 20) * SS, juta, rng.uniform(0.85, 1.15), rng)
    n_f = int(rng.integers(3, 6))
    for _ in range(n_f):
        ang = float(np.clip(rng.normal(0, 0.08), -0.16, 0.16))
        comp = ch * rng.uniform(0.5, 0.92) * (0.6 if curto else 1.0)
        cores = seca if rng.random() < 0.3 else verde
        if var == "selva":
            # folha larga presa ao longo do feixe (menor, para caber na célula estreita)
            comp *= rng.uniform(0.45, 0.6)
            base = chao - rng.uniform(0.0, 0.45) * ch
            pts = G1._curva(cx + rng.normal(0, 6 * SS), base, ang, comp, rng.uniform(-0.2, 0.2), 14)
            G1._lamina(
                dr, da, pts, comp * rng.uniform(0.2, 0.28), cores, rng.uniform(0.85, 1.12), "larga"
            )
            continue
        pts = G1._curva(cx + rng.normal(0, 7 * SS), chao, ang, comp, rng.uniform(-0.2, 0.2), 14)
        if var == "selva":
            pass
        elif var == "bambu":
            G1._lamina(
                dr, da, pts, comp * rng.uniform(0.12, 0.17), cores, rng.uniform(0.85, 1.12), "lanca"
            )
        else:
            G1._lamina(
                dr, da, pts, rng.uniform(7, 11) * SS, cores, rng.uniform(0.85, 1.12), "capim"
            )


def _celula(img_rgb, img_a, cel, desenhar, virar: bool, fundo) -> None:
    """Desenha numa célula (em superamostragem), cabendo inteira, e cola no atlas."""
    from PIL import Image, ImageDraw

    x0, y0, w, h = cel
    W, H = w * SS * 2, h * SS
    q_rgb = Image.new("RGB", (W, H), fundo)
    q_a = Image.new("L", (W, H), 0)
    dr, da = ImageDraw.Draw(q_rgb), ImageDraw.Draw(q_a)
    desenhar(dr, da, W / 2, H - 3 * SS, H - 10 * SS)
    caixa = q_a.getbbox() or (0, 0, W, H)
    meia = max(W / 2 - caixa[0], caixa[2] - W / 2, 1)
    k = min((w * SS / 2 - 3 * SS) / meia, (H - 4 * SS) / max(H - caixa[1], 1), 1.0)
    nw, nh = max(1, round(W * k)), max(1, round(H * k))
    q_rgb = q_rgb.resize((nw, nh), Image.Resampling.LANCZOS)
    q_a = q_a.resize((nw, nh), Image.Resampling.LANCZOS)
    corte = max(0, (nw - w * SS) // 2)
    jan = (corte, 0, corte + min(nw, w * SS), nh)
    q_rgb, q_a = q_rgb.crop(jan), q_a.crop(jan)
    if virar:
        q_rgb = q_rgb.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        q_a = q_a.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        py = y0 * SS
    else:
        py = y0 * SS + (h * SS - q_a.size[1])
    px = x0 * SS + (w * SS - q_a.size[0]) // 2
    img_rgb.paste(q_rgb, (px, py))
    img_a.paste(q_a, (px, py))


def _manta(dr, da, cx, chao, ch, var, rng) -> None:
    """Manta (camada rente ao corpo): muitas tiras curtas e folhas emboladas numa mancha oval,
    desenhadas de pé (depois a célula é virada: raiz em cima)."""
    for _ in range(int(rng.integers(30, 40))):
        x = cx + rng.uniform(-0.36, 0.36) * ch
        base = chao - rng.uniform(0, ch * 0.45)
        comp = ch * rng.uniform(0.3, 0.55)
        pts = G1._curva(x, base, float(rng.normal(0, 0.12)), comp, rng.uniform(-0.25, 0.25), 10)
        if rng.random() < 0.6:
            _tira(dr, da, pts, rng.uniform(10, 16) * SS, JUTA[var], rng.uniform(0.85, 1.15), rng)
        else:
            verde, seca = FOLHAS[var]
            cores = seca if rng.random() < 0.35 else verde
            forma = {"selva": "larga", "bambu": "lanca"}.get(var, "capim")
            larg = (
                comp * (0.38 if forma == "larga" else 0.16)
                if forma != "capim"
                else rng.uniform(8, 12) * SS
            )
            G1._lamina(dr, da, pts, larg, cores, rng.uniform(0.85, 1.12), forma)


def textura(var: str) -> bytes:
    from PIL import Image
    from scipy import ndimage

    rng = np.random.default_rng(SEMENTE + len(var) * 7)
    fundo = JUTA[var][1]
    rgb = Image.new("RGB", (TEX * SS, TEX * SS), fundo)
    alfa = Image.new("L", (TEX * SS, TEX * SS), 0)
    for cel in CEL_TIRA:
        _celula(
            rgb,
            alfa,
            cel,
            lambda dr, da, cx, chao, ch: _feixe(dr, da, cx, chao, ch, var, rng),
            True,
            fundo,
        )
    for cel in CEL_TUFO:
        _celula(
            rgb,
            alfa,
            cel,
            lambda dr, da, cx, chao, ch: G1._tufo(dr, da, cx, chao, ch, var, rng),
            False,
            fundo,
        )
    for cel in CEL_MANTA:
        _celula(
            rgb,
            alfa,
            cel,
            lambda dr, da, cx, chao, ch: _manta(dr, da, cx, chao, ch, var, rng),
            True,
            fundo,
        )
    rgb = rgb.resize((TEX, TEX), Image.Resampling.LANCZOS)
    alfa = alfa.resize((TEX, TEX), Image.Resampling.LANCZOS)
    a = np.asarray(alfa).astype(np.uint8).copy()
    a[:8, :8] = 0  # texel das âncoras
    cor = np.asarray(rgb).copy()
    _, (iy, ix) = ndimage.distance_transform_edt(a < 128, return_indices=True)
    cor = cor[iy, ix]
    from PIL import Image as I2

    out = I2.fromarray(np.dstack([cor, a]).astype(np.uint8), "RGBA")
    buf = io.BytesIO()
    out.save(buf, "PNG", optimize=True)
    return buf.getvalue()


# =============================================================== cartões
UP = np.array([0.0, 1.0, 0.0])


def unit(v):
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else np.array([1.0, 0.0, 0.0])


def uv_celula(cel, raiz_em_cima: bool, espelhar: bool):
    """UV (convenção glTF: v = 0 em cima) dos 4 cantos do cartão: raiz-esq, raiz-dir, ponta-dir,
    ponta-esq."""
    x0, y0, w, h = cel
    m = 1.5
    u0, u1 = (x0 + m) / TEX, (x0 + w - m) / TEX
    vt, vb = (y0 + m) / TEX, (y0 + h - m) / TEX
    if espelhar:
        u0, u1 = u1, u0
    if raiz_em_cima:
        return [(u0, vt), (u1, vt), (u1, vb), (u0, vb)]
    return [(u0, vb), (u1, vb), (u1, vt), (u0, vt)]


class Parte:
    def __init__(self, nome, ref, caixa_lo, caixa_hi, rng):
        self.nome = nome
        self.ref = np.array(ref)
        self.lo = np.array(caixa_lo)
        self.hi = np.array(caixa_hi)
        self.rng = rng
        self.pos, self.nrm, self.uv, self.tri = [], [], [], []
        self.n_cartoes = {"manta": 0, "tira": 0, "tufo": 0}
        self.recusados = 0
        self.permitido = lambda v: True

    def dentro(self, v) -> bool:
        return bool(
            np.all(v >= self.lo + 0.004) and np.all(v <= self.hi - 0.004) and self.permitido(v)
        )

    def cartao(self, raiz, d, f, larg, comp, cel, raiz_em_cima, tipo, n_luz) -> bool:
        """Quad da raiz até a ponta (direção d), largura larg, de frente para f. Encolhe em volta da
        raiz até caber na caixa (e na regra do rosto); se ficar curto demais, desiste."""
        lado = unit(np.cross(d, f))
        for t in (1.0, 0.85, 0.7, 0.55, 0.42):
            L, W = comp * t, larg * (0.5 + 0.5 * t)
            vs = [
                raiz - lado * W / 2,
                raiz + lado * W / 2,
                raiz + d * L + lado * W / 2,
                raiz + d * L - lado * W / 2,
            ]
            if all(self.dentro(v) for v in vs):
                break
        else:
            self.recusados += 1
            return False
        i = len(self.pos)
        esp = self.rng.random() < 0.5
        for v, uv in zip(vs, uv_celula(cel, raiz_em_cima, esp), strict=True):
            self.pos.append(v)
            self.uv.append(uv)
            self.nrm.append(n_luz)
        self.tri += [(i, i + 1, i + 2), (i, i + 2, i + 3)]
        self.n_cartoes[tipo] += 1
        return True

    def ancoras(self):
        """2 triângulos minúsculos nos cantos da caixa da v1 (texel transparente)."""
        u, v = TEXEL_VAZIO[0] / TEX, TEXEL_VAZIO[1] / TEX
        for c, s in ((self.lo, 1.0), (self.hi, -1.0)):
            i = len(self.pos)
            e = 0.003 * s
            for q in (c, c + [e, 0, 0], c + [0, e, 0]):
                self.pos.append(np.array(q, dtype=float))
                self.uv.append((u, v))
                self.nrm.append(UP)
            self.tri.append((i, i + 1, i + 2))


def pontos_superficie(ref, faces, n, rng, y_faixa=(-1.0, 1.0)):
    """n pontos na caixa do corpo (ref = largura, altura, profundidade), nas faces pedidas com pesos
    ({'+x': p, '-x': p, '+z': p (costas), '-z': p (frente), '+y': p (topo)}). Devolve (ponto,
    normal, face)."""
    w, h, d = ref
    area = {"+x": h * d, "-x": h * d, "+z": w * h, "-z": w * h, "+y": w * d}
    nomes = [k for k in faces if faces[k] > 0]
    p = np.array([area[k] * faces[k] for k in nomes])
    p /= p.sum()
    out = []
    for _ in range(n):
        f = nomes[int(rng.choice(len(nomes), p=p))]
        yy = rng.uniform(*y_faixa) * h / 2
        if f == "+y":
            q = np.array([rng.uniform(-0.48, 0.48) * w, h / 2, rng.uniform(-0.48, 0.48) * d])
            nn = UP.copy()
        elif f in ("+x", "-x"):
            s = 1 if f == "+x" else -1
            q = np.array([s * w / 2, yy, rng.uniform(-0.5, 0.5) * d])
            nn = np.array([s, 0.0, 0.0])
        else:
            s = 1 if f == "+z" else -1
            q = np.array([rng.uniform(-0.5, 0.5) * w, yy, s * d / 2])
            nn = np.array([0.0, 0.0, s])
        out.append((q, nn, f))
    return out


def radial(q, ref):
    """Direção para fora no plano horizontal (para cartões do topo caírem pela borda)."""
    w, _, d = ref
    v = np.array([q[0] / (w / 2), 0.0, q[2] / (d / 2)])
    return unit(v) if np.linalg.norm(v) > 0.2 else unit(np.array([0.0, 0.0, 1.0]))


# camadas por parte: (faces das mantas, faces das tiras, faces dos tufos, quantidades e tamanhos)
def faces_lado(nome):
    """Faces permitidas: braço e perna sem o lado de dentro (arma e entre as pernas)."""
    direita = nome.startswith("Right")
    dentro = "-x" if direita else "+x"
    fora = "+x" if direita else "-x"
    return dentro, fora


CONFIG = {
    "Head": dict(
        manta=26, tira=64, tufo=14, l_tira=(0.45, 0.85), l_tufo=(0.35, 0.6), l_manta=(0.42, 0.6)
    ),
    "UpperTorso": dict(
        manta=120, tira=300, tufo=56, l_tira=(0.7, 1.45), l_tufo=(0.45, 0.95), l_manta=(0.55, 0.85)
    ),
    "LowerTorso": dict(
        manta=34, tira=130, tufo=0, l_tira=(0.7, 1.3), l_tufo=(0.4, 0.6), l_manta=(0.5, 0.7)
    ),
    "UpperArm": dict(
        manta=28, tira=90, tufo=10, l_tira=(0.5, 1.0), l_tufo=(0.35, 0.6), l_manta=(0.42, 0.6)
    ),
    "LowerArm": dict(
        manta=16, tira=46, tufo=0, l_tira=(0.4, 0.75), l_tufo=(0.3, 0.5), l_manta=(0.38, 0.5)
    ),
    "UpperLeg": dict(
        manta=40, tira=135, tufo=12, l_tira=(0.6, 1.2), l_tufo=(0.4, 0.7), l_manta=(0.5, 0.7)
    ),
    "LowerLeg": dict(
        manta=30, tira=100, tufo=4, l_tira=(0.5, 1.0), l_tufo=(0.35, 0.55), l_manta=(0.45, 0.65)
    ),
}


FOV_V = math.radians(70 + 15)  # FOV vertical do jogo + folga
FOV_H = 2 * math.atan(math.tan(FOV_V / 2) * 16 / 9)


def no_campo(v_cabeca) -> bool:
    """Ponto (espaço da cabeça) no campo de visão de 1ª pessoa, câmera no centro da cabeça olhando
    para a frente (-z)."""
    z = -v_cabeca[2]
    return (
        z > 0.02
        and abs(v_cabeca[0]) < z * math.tan(FOV_H / 2)
        and abs(v_cabeca[1]) < z * math.tan(FOV_V / 2)
    )


def gerar_parte(p1: G1.Parte, caixa, rng) -> Parte:
    nome = p1.nome
    tipo = nome.replace("Right", "").replace("Left", "")
    cfg = CONFIG[tipo]
    w, h, d = p1.ref
    size, off = np.array(caixa["size"]), np.array(caixa["offset"])
    pt = Parte(nome, p1.ref, off - size / 2, off + size / 2, rng)
    dentro_lado, fora_lado = faces_lado(nome)
    if tipo == "Head":
        # capuz: só para cima e para trás; nada na frente do rosto
        def permitido(v):
            if v[2] < -0.25 and v[1] < 0.62:
                return False
            return v[2] >= -0.42 and not no_campo(v)

        pt.permitido = permitido
        f_manta = {"+y": 1.0, "+z": 1.2, "+x": 0.6, "-x": 0.6}
        f_tira = {"+y": 1.0, "+z": 1.4, "+x": 0.7, "-x": 0.7}
        f_tufo = {"+y": 1.0, "+z": 0.6}
        y_tira = (0.0, 1.0)
    elif tipo == "UpperTorso":
        # na frente (z < 0) nada sobe acima do queixo (y 1,0 do centro do tronco)
        pt.permitido = lambda v: (
            not (v[2] < -0.1 and v[1] > 1.0 and abs(v[0]) < 1.15)
            and not no_campo(v + np.array([0.0, -1.475, 0.0]))
        )
        f_manta = {"+y": 0.9, "+z": 1.4, "-z": 0.8, "+x": 1.0, "-x": 1.0}
        f_tira = {"+y": 1.3, "+z": 1.5, "-z": 0.55, "+x": 1.0, "-x": 1.0}
        f_tufo = {"+y": 1.2, "+z": 1.0, "+x": 0.4, "-x": 0.4}
        y_tira = (-0.6, 1.0)
    elif tipo == "LowerTorso":
        f_manta = {"+z": 1.2, "-z": 0.8, "+x": 1.0, "-x": 1.0}
        f_tira = {"+z": 1.3, "-z": 0.9, "+x": 1.1, "-x": 1.1}
        f_tufo = {}
        y_tira = (-0.2, 1.0)
    else:
        braco = "Arm" in tipo
        f_manta = {fora_lado: 1.2, "+z": 1.0, "-z": 0.3 if braco else 0.8, dentro_lado: 0.0}
        f_tira = {fora_lado: 1.3, "+z": 1.1, "-z": 0.25 if braco else 0.8, dentro_lado: 0.0}
        if "Upper" in tipo:
            f_manta["+y"] = 0.4
            f_tira["+y"] = 0.6
        f_tufo = {fora_lado: 1.0, "+z": 0.8}
        y_tira = (-0.4, 1.0)
        if "Lower" in tipo and braco:
            y_tira = (0.0, 1.0)
    # --------------------------------------------- 1) mantas rentes ao corpo (escamas)
    for q, nn, f in pontos_superficie(p1.ref, f_manta, cfg["manta"], rng, (-0.9, 1.0)):
        if f == "+y":
            dd = unit(radial(q, p1.ref) - UP * 0.5)
        else:
            dd = unit(-UP + nn * rng.uniform(0.12, 0.35) + np.cross(UP, nn) * rng.normal(0, 0.15))
        tam = rng.uniform(*cfg["l_manta"])
        cel = CEL_MANTA[int(rng.integers(0, len(CEL_MANTA)))]
        raiz = q + nn * rng.uniform(0.03, 0.08) - dd * 0.05
        luz = unit(nn * 0.7 + UP * 0.5)
        pt.cartao(raiz, dd, nn, tam, tam, cel, True, "manta", luz)
    # --------------------------------------------- 2) tiras penduradas (soltas e em X)
    for q, nn, f in pontos_superficie(p1.ref, f_tira, cfg["tira"], rng, y_tira):
        ang = math.radians(rng.uniform(8, 38))
        if f == "+y":
            dd = unit(radial(q, p1.ref) * 0.8 - UP * 0.6)
        else:
            dd = unit(-UP * math.cos(ang) + nn * math.sin(ang))
        dd = unit(dd + np.cross(UP, nn) * rng.normal(0, 0.18))
        comp = rng.uniform(*cfg["l_tira"])
        larg = comp * rng.uniform(0.3, 0.42)
        cel = CEL_TIRA[int(rng.integers(0, len(CEL_TIRA)))]
        raiz = q + nn * rng.uniform(0.02, 0.1) - dd * 0.06
        luz = unit(nn * 0.75 + UP * 0.45)
        frente = unit(nn - dd * float(np.dot(nn, dd)))
        giro = math.radians(rng.uniform(-25, 25))
        f0 = unit(frente * math.cos(giro) + np.cross(dd, frente) * math.sin(giro))
        pt.cartao(raiz, dd, f0, larg, comp, cel, True, "tira", luz)
        if rng.random() < 0.45:
            g2 = giro + math.radians(rng.uniform(65, 90))
            f1 = unit(frente * math.cos(g2) + np.cross(dd, frente) * math.sin(g2))
            pt.cartao(
                raiz,
                dd,
                f1,
                larg * 0.9,
                comp * 0.92,
                CEL_TIRA[int(rng.integers(0, 8))],
                True,
                "tira",
                luz,
            )
    # --------------------------------------------- 3) tufos em pé (quebram a silhueta)
    if f_tufo:
        for q, nn, f in pontos_superficie(p1.ref, f_tufo, cfg["tufo"], rng, (0.2, 1.0)):
            ang = math.radians(rng.uniform(15, 55))
            base = radial(q, p1.ref) if f == "+y" else nn
            if tipo == "Head":
                base = unit(base + np.array([0, 0, 0.8]))  # capuz: para trás
            dd = unit(UP * math.cos(ang) + base * math.sin(ang))
            comp = rng.uniform(*cfg["l_tufo"])
            larg = comp * rng.uniform(0.8, 1.0)
            luz = unit(base * 0.6 + UP * 0.6)
            frente = unit(base - dd * float(np.dot(base, dd)))
            phi = math.radians(rng.uniform(-20, 20))
            for k in range(2):
                a = phi + (0 if k == 0 else math.radians(rng.uniform(60, 85)))
                fk = unit(frente * math.cos(a) + np.cross(dd, frente) * math.sin(a))
                cel = CEL_TUFO[int(rng.integers(0, len(CEL_TUFO)))]
                pt.cartao(q - nn * 0.04, dd, fk, larg, comp, cel, False, "tufo", luz)
    pt.ancoras()
    return pt


def conferir_primeira_pessoa(pecas: dict) -> dict:
    """Vértices da cabeça e do tronco no campo de visão de 1ª pessoa: câmera no centro da cabeça
    e no olho (0, 0,1, -0,45), olhando para a frente (-z), FOV vertical 70° em 16:9 e com 15° a
    mais de folga. A malha está no espaço da parte; a cabeça fica 1,475 stud acima do centro do
    tronco (0,875 + 0,6)."""
    fov_v = math.radians(70 + 15)
    fov_h = 2 * math.atan(math.tan(fov_v / 2) * 16 / 9)
    out = {}
    for cam_nome, cam in (
        ("centro_da_cabeca", np.array([0.0, 0.0, 0.0])),
        ("olho", np.array([0.0, 0.1, -0.45])),
    ):
        visiveis = {}
        for nome, desl in (("Head", np.zeros(3)), ("UpperTorso", np.array([0.0, -1.475, 0.0]))):
            pt = pecas[nome]
            pos = np.array(pt.pos[:-6]) + desl - cam
            z = -pos[:, 2]
            ok = z > 0.02
            dentro_ = (
                ok
                & (np.abs(pos[:, 0]) < z * math.tan(fov_h / 2))
                & (np.abs(pos[:, 1]) < z * math.tan(fov_v / 2))
            )
            visiveis[nome] = int(dentro_.sum())
        out[cam_nome] = visiveis
    return out


def gerar() -> dict:
    fit = json.loads(FIT_V1.read_text("utf-8"))
    rng = np.random.default_rng(SEMENTE)
    return {p.nome: gerar_parte(p, fit["parts"][p.nome], rng) for p in G1.PARTES}, fit


def exportar(pecas: dict, png_arroz: bytes, caminho: Path) -> dict:
    g = glb.Glb("VT65 tools/ghillie2.py")
    ti = g.texture(png_arroz, "image/png")
    mi = g.material("Folhas", ti, rugosidade=0.85)
    g.js["materials"][mi]["alphaMode"] = "MASK"
    g.js["materials"][mi]["alphaCutoff"] = 0.5
    g.js["materials"][mi]["doubleSided"] = True
    g.js["samplers"][0]["wrapS"] = g.js["samplers"][0]["wrapT"] = 33071
    info = {}
    for nome in sorted(pecas):
        pt = pecas[nome]
        pos = np.array(pt.pos, np.float32)
        nrm = np.array(pt.nrm, np.float32)
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
        uv = np.array(pt.uv, np.float32)
        idx = np.array(pt.tri, np.uint32).reshape(-1)
        g.mesh(f"Ghillie_{nome}", pos, nrm, uv, idx, mi)
        lo, hi = pos.min(axis=0), pos.max(axis=0)
        info[nome] = {
            "triangulos": len(pt.tri),
            "cartoes": pt.n_cartoes,
            "recusados_pela_caixa_ou_rosto": pt.recusados,
            "caixa_size": [round(float(x), 3) for x in hi - lo],
            "caixa_offset": [round(float(x), 3) for x in (hi + lo) / 2],
        }
    data = g.bytes()
    caminho.parent.mkdir(parents=True, exist_ok=True)
    caminho.write_bytes(data)
    return {
        "partes": info,
        "mb": round(len(data) / 2**20, 3),
        "triangulos": sum(v["triangulos"] for v in info.values()),
    }


def main(argv) -> None:
    SAIDA_TEX.mkdir(parents=True, exist_ok=True)
    pngs = {}
    for var in ("arroz", "selva", "bambu"):
        pngs[var] = textura(var)
        (SAIDA_TEX / f"ghillie2_{var}.png").write_bytes(pngs[var])
        print("ok", f"assets/ghillie/ghillie2_{var}.png", len(pngs[var]) // 1024, "KB")
    pecas, fit = gerar()
    exp = exportar(pecas, pngs["arroz"], SAIDA / "ghillie.glb")
    # conferência do encaixe: a caixa de cada peça tem de ser a da v1
    encaixe = {}
    for nome, v in exp["partes"].items():
        a = fit["parts"][nome]
        ds = max(abs(x - y) for x, y in zip(v["caixa_size"], a["size"], strict=True))
        do = max(abs(x - y) for x, y in zip(v["caixa_offset"], a["offset"], strict=True))
        encaixe[nome] = {
            "desvio_size": round(ds, 4),
            "desvio_offset": round(do, 4),
            "ok": ds <= 0.002 and do <= 0.002,
        }
    fp = conferir_primeira_pessoa(pecas)
    v1 = glb.triangulos(SAIDA_TEX / "ghillie.glb")
    met = {
        "chave": "ghillie",
        "tipo": "refeito",
        "nome": "camuflagem de mato v2 (ghillie)",
        "classe": "prop (equipamento vestido)",
        "antigo": {
            "arquivo_jogo": "assets/ghillie/ghillie.glb",
            "triangulos": v1,
            "mb": round((SAIDA_TEX / "ghillie.glb").stat().st_size / 2**20, 3),
            "texturas_px": {"cor": [512, 512]},
            "por_peca": {k: v["tris"] for k, v in fit["parts"].items()},
        },
        "novo": {
            "arquivo": "assets/blender/ghillie/ghillie.glb",
            "triangulos": exp["triangulos"],
            "mb": exp["mb"],
            "texturas_px": {"cor": [TEX, TEX]},
            "texturas": [f"assets/ghillie/ghillie2_{v}.png" for v in ("arroz", "selva", "bambu")],
            "por_peca": exp["partes"],
        },
        "encaixe_v1": encaixe,
        "primeira_pessoa_vertices_no_campo": fp,
        "medidas_reais": {
            "estatura_ref": [
                1.75,
                "Characters/D-77: soldado de 6,25 studs; a peça escala pela parte do "
                "corpo (Size / ref), então serve no de 2,0 m sem mudar nada",
            ],
            "volume": [
                None,
                "PLACEHOLDER: a espessura (até ~0,3 m no tronco e nas pernas) é a caixa "
                "da v1 (para só trocar o ID); a foto do dono não tem medida",
            ],
        },
    }
    SAIDA.mkdir(parents=True, exist_ok=True)
    (SAIDA / "metricas.json").write_text(
        json.dumps(met, ensure_ascii=False, indent=1) + "\n", "utf-8"
    )
    print(
        "ok ghillie v2:",
        exp["triangulos"],
        "tri,",
        exp["mb"],
        "MB; encaixe:",
        all(e["ok"] for e in encaixe.values()),
        "; 1ª pessoa:",
        fp,
    )
    if "--sem-render" not in argv:
        import lote

        r = lote.rodar("ghillie2", "ghillie", [])
        print("render:", r["estado"], r["tempo_s"], "s")
        for ln in r["fim"]:
            print("   ", ln)


if __name__ == "__main__":
    main(sys.argv[1:])
