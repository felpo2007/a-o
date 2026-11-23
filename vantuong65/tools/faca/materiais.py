"""Materiais procedurais das facas (Cycles) para o bake: cor, rugosidade, metal e relevo.

Roda no Python do Blender. Cada material expõe quatro saídas que o `produzir.py` liga na saída
do material, uma por passe de bake:
- "cor": cor base (linear);
- "rm": (rugosidade, metal, 0) numa cor só (um passe EMIT para os dois);
- "bsdf": Principled com a normal do relevo (passe NORMAL);
- e a própria Principled serve para a prévia procedural.

Unidades: as coordenadas do objeto vêm em metros e viram mm (`P`); escalas de ruído são "por mm"
e alturas do relevo em mm (o Bump usa Distance = 0,001). Atributos da malha: `d_fio`, `bisel`,
`afiado`, `xadrez` (por vértice) e as UVs "local" (mm desenrolados) e "costura" (ao longo,
através da linha de costura, em mm).

Cores e acabamento seguem as armas do jogo (tools/armas_parker.py): aço fosfatizado cinza-
esverdeado sRGB (64, 66, 60), rugosidade >= 0,62 e pouco metal; oxidado azulado (52, 54, 60) nas
peças chinesas; o aço gasto e o fio afiado ficam claros, com metal 1.
"""

from __future__ import annotations

import math

import bpy


def _lin(c):
    """sRGB 0-255 -> linear."""
    out = []
    for v in c:
        v = v / 255
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return tuple(out)


FOSFATO = _lin((56, 58, 53))  # um pouco mais escuro que as armas: faca nova de 1965
OXIDADO = _lin((46, 49, 58))


class Nos:
    """Montador compacto de árvore de nós de shader."""

    def __init__(self, mat: bpy.types.Material):
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self._p = None
        self._n = None

    # ------------------------------------------------ básicos
    def no(self, tipo: str, **props):
        n = self.nt.nodes.new(tipo)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def liga(self, saida, entrada) -> None:
        self.nt.links.new(saida, entrada)

    def _in(self, sock, v) -> None:
        if isinstance(v, bpy.types.NodeSocket):
            self.liga(v, sock)
            return
        if v is None:
            return
        dv = sock.default_value
        if isinstance(v, (int, float)):
            if hasattr(dv, "__len__"):
                n = len(dv)
                sock.default_value = (float(v),) * 3 + (1.0,) if n == 4 else (float(v),) * n
            else:
                sock.default_value = float(v)
            return
        v = tuple(float(x) for x in v)
        if hasattr(dv, "__len__") and len(dv) == 4 and len(v) == 3:
            v = v + (1.0,)
        sock.default_value = v

    def m(self, op: str, a=None, b=None, c=None, clamp: bool = False):
        n = self.no("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b, c)):
            self._in(n.inputs[i], v)
        return n.outputs[0]

    def v(self, op: str, a=None, b=None, escala=None):
        n = self.no("ShaderNodeVectorMath", operation=op)
        self._in(n.inputs[0], a)
        self._in(n.inputs[1], b)
        if escala is not None:
            self._in(n.inputs["Scale"], escala)
        return n.outputs["Value"] if op in ("LENGTH", "DOT_PRODUCT", "DISTANCE") else n.outputs[0]

    def add(self, *xs):
        out = xs[0]
        for x in xs[1:]:
            out = self.m("ADD", out, x)
        return out

    def mul(self, a, b, clamp=False):
        return self.m("MULTIPLY", a, b, clamp=clamp)

    def lerp(self, t, a, b):
        """a + (b - a) t (floats)."""
        return self.m("MULTIPLY_ADD", t, self.m("SUBTRACT", b, a), a)

    def mapa(self, x, a, b, c=0.0, d=1.0, suave=False, clamp=True):
        n = self.no("ShaderNodeMapRange", clamp=clamp)
        n.interpolation_type = "SMOOTHSTEP" if suave else "LINEAR"
        for k, val in (
            ("Value", x),
            ("From Min", a),
            ("From Max", b),
            ("To Min", c),
            ("To Max", d),
        ):
            self._in(n.inputs[k], val)
        return n.outputs[0]

    def mix(self, t, a, b, modo: str = "MIX"):
        n = self.no("ShaderNodeMixRGB", blend_type=modo)
        self._in(n.inputs["Fac"], t)
        self._in(n.inputs["Color1"], a)
        self._in(n.inputs["Color2"], b)
        return n.outputs["Color"]

    def rgb(self, r, g=None, b=None):
        n = self.no("ShaderNodeCombineColor")
        self._in(n.inputs[0], r)
        self._in(n.inputs[1], r if g is None else g)
        self._in(n.inputs[2], r if b is None else b)
        return n.outputs[0]

    def xyz(self, x, y, z):
        n = self.no("ShaderNodeCombineXYZ")
        for i, val in enumerate((x, y, z)):
            self._in(n.inputs[i], val)
        return n.outputs[0]

    def sep(self, vec):
        n = self.no("ShaderNodeSeparateXYZ")
        self._in(n.inputs[0], vec)
        return n.outputs[0], n.outputs[1], n.outputs[2]

    # ------------------------------------------------ entradas
    def P(self):
        """Coordenadas do objeto em mm."""
        if self._p is None:
            tc = self.no("ShaderNodeTexCoord")
            self._p = self.v("SCALE", tc.outputs["Object"], escala=1000.0)
        return self._p

    def N(self):
        if self._n is None:
            self._n = self.no("ShaderNodeNewGeometry").outputs["Normal"]
        return self._n

    def uv(self, nome: str):
        return self.no("ShaderNodeUVMap", uv_map=nome).outputs["UV"]

    def attr(self, nome: str):
        return self.no(
            "ShaderNodeAttribute", attribute_name=nome, attribute_type="GEOMETRY"
        ).outputs["Fac"]

    def esticar(self, vec, sx, sy, sz):
        return self.v("MULTIPLY", vec, (sx, sy, sz))

    def girar_x(self, vec, graus):
        """Gira o vetor em torno de X (no plano y-z)."""
        x, y, z = self.sep(vec)
        c, s = math.cos(math.radians(graus)), math.sin(math.radians(graus))
        return self.xyz(
            x, self.add(self.mul(y, c), self.mul(z, -s)), self.add(self.mul(y, s), self.mul(z, c))
        )

    # ------------------------------------------------ texturas
    def ruido(self, vec, escala, detalhe=2.0, rug=0.5, dist=0.0, cor=False):
        n = self.no("ShaderNodeTexNoise", noise_dimensions="3D")
        self._in(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = escala
        n.inputs["Detail"].default_value = detalhe
        n.inputs["Roughness"].default_value = rug
        n.inputs["Distortion"].default_value = dist
        return n.outputs["Color"] if cor else n.outputs["Fac"]

    def voronoi(self, vec, escala, feature="F1", rand=1.0, saida="Distance"):
        n = self.no("ShaderNodeTexVoronoi", feature=feature, voronoi_dimensions="3D")
        self._in(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = escala
        n.inputs["Randomness"].default_value = rand
        return n.outputs[saida]

    def branco(self, w=None, vec=None, cor=False):
        n = self.no("ShaderNodeTexWhiteNoise", noise_dimensions="1D" if vec is None else "3D")
        if vec is None:
            self._in(n.inputs["W"], w)
        else:
            self._in(n.inputs["Vector"], vec)
        return n.outputs["Color"] if cor else n.outputs["Value"]

    def borda(self, raio_mm: float = 0.8, a: float = 0.015, b: float = 0.12):
        """Máscara de quina (1 - N_bevel . N): 1 nas quinas vivas, 0 no plano."""
        bev = self.no("ShaderNodeBevel", samples=8)
        bev.inputs["Radius"].default_value = raio_mm / 1000
        d = self.v("DOT_PRODUCT", bev.outputs["Normal"], self.N())
        return self.mapa(self.m("SUBTRACT", 1.0, d), a, b)

    def oclusao(self, dist_mm: float, local: bool = True):
        ao = self.no("ShaderNodeAmbientOcclusion", samples=8, only_local=local, inside=False)
        ao.inputs["Distance"].default_value = dist_mm / 1000
        return ao.outputs["AO"]

    def arranhoes(self, p, escala, limiar, larg=0.03, esticar=(1.0, 0.012, 1.0), detalhe=1.0):
        """Riscos finos e compridos ao longo do eixo menos esticado (padrão: Y)."""
        q = self.esticar(p, *esticar)
        r = self.ruido(q, escala, detalhe, 0.5)
        return self.mapa(r, limiar, limiar + larg, suave=True)

    def finalizar(self, cor, rug, met, alt_mm=None, forca=1.0):
        """Principled + emissões; guarda as saídas para os passes do bake."""
        pr = self.no("ShaderNodeBsdfPrincipled")
        self._in(pr.inputs["Base Color"], cor)
        self._in(pr.inputs["Roughness"], rug)
        self._in(pr.inputs["Metallic"], met)
        if alt_mm is not None:
            bump = self.no("ShaderNodeBump")
            bump.inputs["Strength"].default_value = forca
            bump.inputs["Distance"].default_value = 0.001
            self._in(bump.inputs["Height"], alt_mm)
            self.liga(bump.outputs["Normal"], pr.inputs["Normal"])
        saida = self.no("ShaderNodeOutputMaterial")
        self.liga(pr.outputs[0], saida.inputs["Surface"])
        e_cor = self.no("ShaderNodeEmission")
        self._in(e_cor.inputs["Color"], cor)
        e_rm = self.no("ShaderNodeEmission")
        self._in(e_rm.inputs["Color"], self.rgb(rug, met, 0.0))
        liso = self.no("ShaderNodeBsdfDiffuse")  # passe de AO: só a geometria, sem o relevo
        return {
            "saida": saida,
            "bsdf": pr.outputs[0],
            "cor": e_cor.outputs[0],
            "rm": e_rm.outputs[0],
            "liso": liso.outputs[0],
        }


# ====================================================================== aços
def _aco(
    n: Nos,
    base,
    met0=0.32,
    rug0=0.66,
    eixo_riscos="y",
    fio_largura=2.2,
    gasto=1.0,
    ferrugem=0.5,
    cristal=1.0,
    cor_nu=(0.55, 0.55, 0.56),
):
    """Aço com acabamento (fosfato, oxidado): grão cristalino, manchas e lustro de manuseio,
    riscos (que mostram aço mais claro), quinas gastas até o aço, fio afiado claro com as
    marcas da pedra (atributos d_fio/afiado), sujeira nas reentrâncias e pontos de ferrugem."""
    p = n.P()
    fino = n.ruido(p, 5.5, 2.0, 0.7)  # grão cristalino do fosfato (~0,2 mm)
    grao = n.ruido(p, 1.6, 3.0, 0.6)
    med = n.mapa(n.ruido(p, 0.12, 4.0, 0.6), 0.3, 0.7)
    grande = n.mapa(n.ruido(p, 0.02, 2.0, 0.5), 0.3, 0.7)
    k = n.add(
        0.62, n.mul(fino, 0.22 * cristal), n.mul(grao, 0.18), n.mul(med, 0.28), n.mul(grande, 0.22)
    )
    cor = n.mix(1.0, n.rgb(*base), n.rgb(k), "MULTIPLY")
    rug = n.add(rug0 - 0.08, n.mul(fino, 0.1 * cristal), n.mul(med, 0.08))
    # lustro de manuseio (óleo e mão): manchas mais lisas e um pouco mais escuras
    lustro = n.mapa(n.ruido(p, 0.035, 3.0, 0.6), 0.48, 0.66)
    cor = n.mix(n.mul(lustro, 0.35), cor, n.rgb(base[0] * 0.6, base[1] * 0.6, base[2] * 0.6))
    rug = n.lerp(n.mul(lustro, 0.7), rug, 0.44)
    # riscos ao longo do eixo (lâmina) e alguns cruzados
    est = (1.0, 0.012, 1.0) if eixo_riscos == "y" else (0.05, 1.0, 1.0)
    r1 = n.arranhoes(p, 3.2, 0.70, 0.03, est)
    r2 = n.arranhoes(p, 7.0, 0.66, 0.035, est)
    r3 = n.arranhoes(n.girar_x(p, 28.0), 2.4, 0.72, 0.025, (1.0, 0.02, 1.0))
    r4 = n.arranhoes(n.girar_x(p, -61.0), 2.0, 0.73, 0.025, (0.02, 1.0, 1.0))
    r5 = n.arranhoes(n.girar_x(p, 8.0), 11.0, 0.62, 0.04, (1.0, 0.03, 1.0))  # micro
    quebra = n.mapa(n.ruido(p, 0.05, 2.0), 0.3, 0.6)
    riscos = n.mul(
        n.m("MAXIMUM", n.m("MAXIMUM", r1, n.mul(r2, 0.7)), n.m("MAXIMUM", r3, r4)), quebra
    )
    micro = n.mul(r5, n.mapa(n.ruido(p, 0.08, 2.0), 0.4, 0.6))
    # quinas gastas (convexas)
    quina = n.borda(0.7)
    convexo = n.mapa(n.oclusao(1.6), 0.82, 1.0)
    rasgo = n.ruido(p, 0.55, 5.0, 0.6)
    gasto_m = n.mapa(n.mul(n.mul(quina, convexo), n.add(rasgo, 0.25)), 0.2 / gasto, 0.55 / gasto)
    # fio afiado (faixa clara com marcas da pedra quase transversais)
    dfio = n.attr("d_fio")
    afi = n.attr("afiado")
    serr = n.ruido(n.esticar(p, 0.05, 1.0, 0.05), 0.35, 3.0)
    larg = n.add(fio_largura - 0.35, n.mul(serr, 0.7))
    fio = n.mul(afi, n.mapa(n.m("SUBTRACT", dfio, larg), 0.2, -0.2))
    marcas = n.ruido(
        n.add(n.esticar(p, 0.4, 1.0, 0.03), n.xyz(0.0, n.mul(n.sep(p)[2], 0.35), 0.0)), 4.5, 2.0
    )
    # composição
    nu = n.rgb(
        n.add(cor_nu[0] - 0.08, n.mul(marcas, 0.16)),
        n.add(cor_nu[1] - 0.08, n.mul(marcas, 0.16)),
        n.add(cor_nu[2] - 0.07, n.mul(marcas, 0.16)),
    )
    claro = n.rgb(cor_nu[0] * 0.3, cor_nu[1] * 0.3, cor_nu[2] * 0.3)
    cor = n.mix(n.mul(micro, 0.35), cor, claro)
    cor = n.mix(n.mul(riscos, 0.85), cor, claro)
    nu_m = n.m("MAXIMUM", gasto_m, fio)
    cor = n.mix(nu_m, cor, nu)
    rug = n.lerp(n.mul(micro, 0.4), rug, 0.45)
    rug = n.lerp(n.mul(riscos, 0.8), rug, 0.36)
    rug = n.lerp(gasto_m, rug, 0.3)
    rug = n.lerp(fio, rug, n.add(0.16, n.mul(marcas, 0.12)))
    met = n.lerp(n.m("MAXIMUM", nu_m, n.mul(riscos, 0.75)), met0, 1.0)
    # sujeira/óleo velho nas reentrâncias (sulco, junção com a guarda)
    sujo = n.mapa(n.oclusao(4.0), 0.95, 0.45)
    cor = n.mix(n.mul(sujo, 0.6), cor, n.rgb(0.010, 0.009, 0.007))
    rug = n.lerp(n.mul(sujo, 0.5), rug, 0.8)
    # pontinhos de ferrugem
    if ferrugem > 0:
        f1 = n.mapa(n.ruido(p, 0.9, 6.0, 0.65), 0.68, 0.77)
        f2 = n.mapa(n.ruido(p, 0.035, 2.0), 0.5, 0.64)
        ferr = n.mul(n.mul(f1, f2), ferrugem)
        ferr = n.mul(ferr, n.m("SUBTRACT", 1.0, fio))
        cor = n.mix(
            ferr,
            cor,
            n.mix(n.ruido(p, 3.0, 2.0), n.rgb(0.05, 0.02, 0.008), n.rgb(0.10, 0.04, 0.014)),
        )
        rug = n.lerp(ferr, rug, 0.88)
        met = n.lerp(ferr, met, 0.0)
    else:
        ferr = 0.0
    alt = n.add(
        n.mul(fino, 0.008 * cristal),
        n.mul(grao, 0.006 * cristal),
        n.mul(riscos, -0.018),
        n.mul(micro, -0.006),
        n.mul(gasto_m, -0.006),
        n.mul(n.mul(marcas, fio), 0.006),
    )
    if ferrugem > 0:
        alt = n.add(alt, n.mul(ferr, 0.03))
    return cor, rug, met, alt


def aco_lamina(n: Nos):
    return n.finalizar(*_aco(n, FOSFATO, eixo_riscos="y", fio_largura=2.2))


def aco(n: Nos):
    return n.finalizar(*_aco(n, FOSFATO, eixo_riscos="x", fio_largura=0.0, gasto=1.3))


def arame(n: Nos):
    return n.finalizar(*_aco(n, _lin((58, 60, 56)), eixo_riscos="x", gasto=1.6, ferrugem=0.8))


def aco_azul(n: Nos):
    cor, rug, met, alt = _aco(
        n,
        OXIDADO,
        met0=0.45,
        rug0=0.55,
        eixo_riscos="y",
        fio_largura=0.0,
        gasto=1.5,
        ferrugem=0.7,
        cristal=0.4,
        cor_nu=(0.46, 0.47, 0.49),
    )
    return n.finalizar(cor, rug, met, alt)


def ferro(n: Nos):
    """Virola de ferro escurecido e meio enferrujado."""
    p = n.P()
    cor, rug, met, alt = _aco(
        n,
        _lin((48, 44, 40)),
        met0=0.4,
        rug0=0.66,
        eixo_riscos="x",
        fio_largura=0.0,
        gasto=1.3,
        ferrugem=0.0,
        cristal=0.6,
        cor_nu=(0.40, 0.39, 0.38),
    )
    ferr = n.mapa(n.ruido(p, 0.12, 6.0, 0.62), 0.5, 0.68)
    cor = n.mix(
        n.mul(ferr, 0.85),
        cor,
        n.mix(n.ruido(p, 1.4, 3.0), n.rgb(0.06, 0.022, 0.008), n.rgb(0.11, 0.045, 0.016)),
    )
    rug = n.lerp(ferr, rug, 0.88)
    met = n.lerp(ferr, met, 0.05)
    alt = n.add(alt, n.mul(n.mul(ferr, n.ruido(p, 2.0, 4.0)), 0.04))
    return n.finalizar(cor, rug, met, alt)


def aco_forjado(n: Nos):
    """Lâmina do dao: aço-carbono forjado com pátina escura e manchada, marcas de martelo nas
    faces planas, chanfro limado mais claro e o fio afiado claro."""
    p = n.P()
    bis = n.attr("bisel")
    dfio = n.attr("d_fio")
    afi = n.attr("afiado")
    plano = n.mapa(bis, 0.97, 1.12)
    mancha = n.ruido(p, 0.07, 5.0, 0.6)
    mancha2 = n.ruido(p, 0.22, 3.0, 0.55)
    escuro = n.rgb(0.030, 0.027, 0.024)
    marrom = n.rgb(0.085, 0.060, 0.040)
    cinza = n.rgb(0.075, 0.072, 0.068)
    pat = n.mix(n.mapa(mancha, 0.38, 0.66), escuro, marrom)
    pat = n.mix(n.mul(n.mapa(mancha2, 0.45, 0.7), 0.6), pat, cinza)
    # marcas de martelo: covinhas rasas e irregulares (Voronoi suave em coordenadas torcidas),
    # mais fortes no plano; o alto entre as covinhas fica um pouco mais liso e claro
    pw = n.add(p, n.v("SCALE", n.ruido(p, 0.08, 2.0, 0.5, cor=True), escala=5.0))
    vd = n.voronoi(pw, 0.11, "SMOOTH_F1", 1.0)
    vc = n.voronoi(pw, 0.11, "F1", 1.0, saida="Color")
    prof = n.add(0.3, n.mul(n.sep(vc)[0], 0.9))
    covinha = n.mul(n.m("SUBTRACT", 1.0, n.m("MINIMUM", n.mul(n.mul(vd, vd), 2.2), 1.0)), prof)
    covinha = n.mul(covinha, n.mapa(n.ruido(p, 0.04, 2.0), 0.3, 0.6, 0.35, 1.0))
    pat = n.mix(
        n.mul(n.mul(n.m("SUBTRACT", 1.0, covinha), plano), 0.18), pat, n.rgb(0.10, 0.092, 0.082)
    )
    # chanfro limado/afiado à mão: cinza com riscos ao longo e oblíquos
    lima = n.arranhoes(p, 2.6, 0.55, 0.12, (1.0, 0.02, 1.0), 2.0)
    lima2 = n.arranhoes(n.girar_x(p, 12.0), 1.8, 0.6, 0.1, (1.0, 0.02, 1.0), 2.0)
    lima = n.m("MAXIMUM", lima, n.mul(lima2, 0.8))
    chanfro = n.rgb(
        n.add(0.085, n.mul(lima, 0.09)),
        n.add(0.082, n.mul(lima, 0.09)),
        n.add(0.078, n.mul(lima, 0.09)),
    )
    chanfro = n.mix(n.mul(n.mapa(mancha2, 0.5, 0.75), 0.6), chanfro, n.rgb(0.05, 0.042, 0.035))
    cor = n.mix(n.m("SUBTRACT", 1.0, plano), pat, chanfro)
    # fio afiado largo, com as marcas da pedra
    serr = n.ruido(n.esticar(p, 0.05, 1.0, 0.05), 0.25, 3.0)
    larg = n.add(3.0, n.mul(serr, 1.4))
    fio = n.mul(afi, n.mapa(n.m("SUBTRACT", dfio, larg), 0.35, -0.35))
    marcas = n.ruido(
        n.add(n.esticar(p, 0.4, 1.0, 0.03), n.xyz(0.0, n.mul(n.sep(p)[2], 0.5), 0.0)), 3.5, 2.0
    )
    nu = n.rgb(
        n.add(0.42, n.mul(marcas, 0.14)),
        n.add(0.42, n.mul(marcas, 0.14)),
        n.add(0.43, n.mul(marcas, 0.14)),
    )
    cor = n.mix(fio, cor, nu)
    rug = n.add(0.5, n.mul(mancha, 0.16), n.mul(covinha, 0.08))
    rug = n.lerp(n.m("SUBTRACT", 1.0, plano), rug, n.add(0.5, n.mul(lima, -0.12)))
    rug = n.lerp(fio, rug, n.add(0.2, n.mul(marcas, 0.1)))
    met = n.lerp(n.m("SUBTRACT", 1.0, plano), 0.62, 0.85)
    met = n.lerp(fio, met, 1.0)
    # ferrugem em pontos (mais perto do dorso) e sujeira
    f1 = n.mapa(n.ruido(p, 0.5, 6.0, 0.65), 0.64, 0.74)
    f2 = n.mapa(n.ruido(p, 0.03, 2.0), 0.45, 0.62)
    ferr = n.mul(n.mul(f1, f2), n.mul(plano, n.m("SUBTRACT", 1.0, fio)))
    cor = n.mix(
        ferr, cor, n.mix(n.ruido(p, 2.0, 3.0), n.rgb(0.07, 0.025, 0.009), n.rgb(0.13, 0.05, 0.016))
    )
    rug = n.lerp(ferr, rug, 0.88)
    met = n.lerp(ferr, met, 0.0)
    quina = n.mul(n.borda(0.8), n.mapa(n.oclusao(1.6), 0.82, 1.0))
    cor = n.mix(n.mul(quina, 0.6), cor, n.rgb(0.3, 0.3, 0.3))
    alt = n.add(
        n.mul(n.mul(covinha, plano), -0.06),
        n.mul(lima, -0.008),
        n.mul(n.mul(marcas, fio), 0.004),
        n.mul(ferr, 0.03),
        n.mul(n.ruido(p, 1.6, 4.0), 0.006),
    )
    return n.finalizar(cor, rug, met, alt)


# ====================================================================== couros
def couro_cabo(n: Nos):
    """Cabo de arruelas de couro empilhadas (Ka-Bar): tom por arruela, juntas escuras, fibras,
    poros, sujeira e brilho nos sulcos e onde a mão fecha."""
    p = n.P()
    x, y, z = n.sep(p)
    t_arr = 3.2  # espessura de uma arruela PLACEHOLDER
    u = n.m("DIVIDE", n.m("SUBTRACT", y, 4.8), t_arr)
    idx = n.m("FLOOR", u)
    fr = n.m("FRACT", u)
    rnd = n.branco(w=idx)
    rnd_c = n.sep(n.branco(w=n.add(idx, 17.3), cor=True))
    # tons de couro: cada arruela tem o seu (avermelhado, castanho, amarelado, escuro)
    tom = n.mix(n.mapa(rnd_c[0], 0.0, 0.5), n.rgb(0.135, 0.046, 0.014), n.rgb(0.105, 0.055, 0.022))
    tom = n.mix(n.mapa(rnd_c[1], 0.45, 1.0), tom, n.rgb(0.13, 0.075, 0.03))
    tom = n.mix(n.mul(n.mapa(rnd_c[2], 0.7, 1.0), 0.8), tom, n.rgb(0.05, 0.027, 0.013))
    cor = n.mix(1.0, tom, n.rgb(n.add(0.62, n.mul(rnd, 0.7))), "MULTIPLY")
    # camadas finas dentro da arruela, fibras que dão a volta no cabo, poros e trincas
    camada = n.ruido(n.esticar(p, 0.06, 1.0, 0.06), 1.3, 2.0, 0.5)
    fib = n.ruido(n.esticar(p, 0.25, 5.0, 0.25), 1.1, 5.0, 0.65)
    poro = n.mapa(n.voronoi(p, 1.4, "F1", 1.0), 0.0, 0.2, 1.0, 0.0)
    rach = n.mapa(
        n.voronoi(n.esticar(p, 1.0, 3.5, 1.0), 0.4, "DISTANCE_TO_EDGE"), 0.0, 0.04, 1.0, 0.0
    )
    rach = n.mul(rach, n.mapa(n.ruido(p, 0.15, 2.0), 0.45, 0.65))
    cor = n.mix(1.0, cor, n.rgb(n.add(0.74, n.mul(fib, 0.4), n.mul(camada, 0.12))), "MULTIPLY")
    cor = n.mix(n.mul(poro, 0.55), cor, n.rgb(0.025, 0.011, 0.005))
    cor = n.mix(n.mul(rach, 0.7), cor, n.rgb(0.02, 0.009, 0.004))
    # junta entre arruelas
    junta = n.mapa(n.m("MINIMUM", fr, n.m("SUBTRACT", 1.0, fr)), 0.0, 0.08, 1.0, 0.0)
    cor = n.mix(n.mul(junta, 0.85), cor, n.rgb(0.016, 0.008, 0.004))
    # sujeira e brilho nos sulcos (reentrâncias) e onde a mão fecha
    sulco = n.mapa(n.oclusao(3.0), 0.97, 0.6)
    pega = n.mul(n.mapa(y, 12.0, 30.0), n.mapa(y, 104.0, 84.0))
    pega = n.mul(pega, n.mapa(z, 8.0, -10.0, 0.45, 1.0))
    mao = n.mul(pega, n.mapa(n.ruido(p, 0.08, 2.0), 0.3, 0.7, 0.55, 1.0))
    cor = n.mix(n.mul(sulco, 0.8), cor, n.rgb(0.018, 0.009, 0.005))
    cor = n.mix(n.mul(mao, 0.5), cor, n.rgb(0.035, 0.018, 0.008))
    alto = n.m("SUBTRACT", 1.0, sulco)
    cor = n.mix(n.mul(alto, n.mul(mao, 0.3)), cor, n.rgb(0.15, 0.08, 0.038))
    # laca velha: acetinada, gasta (mais áspera) no alto dos gomos, oleosa nos sulcos
    laca = n.mapa(n.ruido(p, 0.06, 3.0), 0.3, 0.7)
    rug = n.add(0.44, n.mul(fib, 0.1), n.mul(laca, 0.14), n.mul(poro, 0.15))
    rug = n.lerp(n.mul(alto, 0.5), rug, 0.6)
    rug = n.lerp(n.mul(sulco, 0.8), rug, 0.38)
    rug = n.lerp(n.mul(mao, 0.6), rug, 0.4)
    rug = n.lerp(junta, rug, 0.78)
    alt = n.add(
        n.mul(junta, -0.1),
        n.mul(fib, 0.035),
        n.mul(camada, 0.01),
        n.mul(poro, -0.035),
        n.mul(rach, -0.05),
    )
    return n.finalizar(cor, rug, 0.0, alt)


def _costura(n: Nos, passo=4.0, comp=1.45, raio=0.42, ang=22.0):
    """Pontos de costura (linha encerada) a partir da UV 'costura' (ao longo, através, mm).
    Devolve (máscara da linha, altura da linha em mm, furo)."""
    a, c, _ = n.sep(n.uv("costura"))
    al = n.m("SUBTRACT", n.mul(n.m("FRACT", n.m("DIVIDE", a, passo)), passo), passo / 2)
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    u = n.add(n.mul(al, ca), n.mul(c, -sa))
    v = n.add(n.mul(al, sa), n.mul(c, ca))
    du = n.m("MAXIMUM", n.m("SUBTRACT", n.m("ABSOLUTE", u), comp), 0.0)
    d = n.v("LENGTH", n.xyz(du, v, 0.0))
    linha = n.mapa(d, raio, raio * 0.7)
    alt = n.mul(
        n.m(
            "SQRT",
            n.m(
                "MAXIMUM",
                n.m("SUBTRACT", 1.0, n.mul(n.m("DIVIDE", d, raio), n.m("DIVIDE", d, raio))),
                0.0,
            ),
        ),
        0.22,
    )
    furo_d = n.v("LENGTH", n.xyz(n.m("SUBTRACT", n.m("ABSOLUTE", al), passo / 2), c, 0.0))
    furo = n.mapa(furo_d, 0.42, 0.22)
    return linha, alt, furo


def couro_bainha(n: Nos):
    p = n.P()
    base = n.rgb(0.066, 0.027, 0.010)
    m1 = n.mapa(n.ruido(p, 0.018, 3.0, 0.55), 0.3, 0.7)
    m2 = n.mapa(n.ruido(p, 0.08, 4.0, 0.6), 0.3, 0.7)
    cor = n.mix(1.0, base, n.rgb(n.add(0.62, n.mul(m1, 0.5), n.mul(m2, 0.3))), "MULTIPLY")
    oleo = n.mapa(n.ruido(p, 0.03, 3.0), 0.48, 0.66)
    cor = n.mix(n.mul(oleo, 0.6), cor, n.rgb(0.028, 0.011, 0.004))
    # grão (pequenas dobras entre células), poros e vincos de dobra
    cel = n.voronoi(p, 0.9, "DISTANCE_TO_EDGE", 1.0)
    grao = n.mapa(cel, 0.0, 0.09, 1.0, 0.0)
    poro = n.mapa(n.voronoi(p, 2.6, "F1"), 0.0, 0.14, 1.0, 0.0)
    vinco = n.mapa(n.ruido(n.esticar(p, 0.25, 0.04, 1.0), 1.2, 3.0, 0.6), 0.6, 0.72)
    vinco = n.mul(vinco, n.mapa(n.ruido(p, 0.03), 0.4, 0.6))
    cor = n.mix(n.mul(grao, 0.35), cor, n.rgb(0.024, 0.01, 0.004))
    cor = n.mix(n.mul(vinco, 0.5), cor, n.rgb(0.02, 0.008, 0.003))
    # partes altas esfregadas (mais claras e opacas) e esfolados claros
    convexo = n.mul(n.mapa(n.oclusao(6.0), 0.85, 1.0), n.mapa(n.ruido(p, 0.05, 3.0), 0.45, 0.7))
    cor = n.mix(n.mul(convexo, 0.35), cor, n.rgb(0.12, 0.058, 0.026))
    esf1 = n.arranhoes(p, 1.4, 0.70, 0.04, (1.0, 0.05, 1.0), 2.0)
    esf2 = n.arranhoes(n.girar_x(p, 50.0), 1.1, 0.72, 0.04, (1.0, 0.05, 1.0), 2.0)
    esf3 = n.arranhoes(n.girar_x(p, -20.0), 3.0, 0.68, 0.05, (1.0, 0.03, 1.0), 1.0)
    esf = n.mul(
        n.m("MAXIMUM", n.m("MAXIMUM", esf1, esf2), n.mul(esf3, 0.6)),
        n.mapa(n.ruido(p, 0.06), 0.35, 0.6),
    )
    cor = n.mix(n.mul(esf, 0.7), cor, n.rgb(0.17, 0.09, 0.045))
    # quinas brunidas (mais escuras e lisas)
    quina = n.borda(1.0, 0.01, 0.09)
    cor = n.mix(n.mul(quina, 0.75), cor, n.rgb(0.022, 0.009, 0.003))
    sujo = n.mapa(n.oclusao(3.0), 0.95, 0.5)
    cor = n.mix(n.mul(sujo, 0.65), cor, n.rgb(0.016, 0.008, 0.004))
    # costura
    linha, alt_l, furo = _costura(n)
    fio_cor = n.mix(
        n.mapa(n.ruido(p, 0.5, 3.0), 0.3, 0.7), n.rgb(0.20, 0.16, 0.10), n.rgb(0.34, 0.28, 0.18)
    )
    fio_cor = n.mix(n.mul(sujo, 0.6), fio_cor, n.rgb(0.07, 0.05, 0.03))
    cor = n.mix(n.mul(furo, 0.8), cor, n.rgb(0.01, 0.005, 0.002))
    cor = n.mix(linha, cor, fio_cor)
    rug = n.add(0.52, n.mul(m2, 0.12), n.mul(grao, 0.08), n.mul(convexo, 0.12))
    rug = n.lerp(n.mul(oleo, 0.6), rug, 0.4)
    rug = n.lerp(esf, rug, 0.84)
    rug = n.lerp(n.mul(quina, 0.7), rug, 0.36)
    rug = n.lerp(linha, rug, 0.62)
    alt = n.add(
        n.mul(grao, -0.03),
        n.mul(poro, -0.018),
        n.mul(esf, -0.02),
        n.mul(vinco, -0.06),
        n.mul(n.ruido(p, 2.2, 3.0), 0.01),
        n.mul(furo, -0.15),
        n.mul(linha, 0.02),
        alt_l,
    )
    return n.finalizar(cor, rug, 0.0, alt)


def rebite(n: Nos):
    p = n.P()
    pat = n.mapa(n.ruido(p, 0.6, 4.0), 0.35, 0.7)
    cor = n.mix(pat, n.rgb(0.32, 0.21, 0.11), n.rgb(0.07, 0.055, 0.04))
    topo = n.mapa(n.oclusao(1.5), 0.9, 1.0)
    cor = n.mix(n.mul(topo, 0.4), cor, n.rgb(0.42, 0.29, 0.16))
    rug = n.lerp(pat, 0.32, 0.62)
    return n.finalizar(cor, rug, n.lerp(pat, 0.95, 0.6), n.mul(n.ruido(p, 3.0, 3.0), 0.006))


def botao(n: Nos):
    p = n.P()
    sujo = n.mapa(n.oclusao(2.0), 0.95, 0.6)
    pat = n.mapa(n.ruido(p, 0.5, 4.0), 0.4, 0.75)
    cor = n.mix(pat, n.rgb(0.40, 0.40, 0.39), n.rgb(0.22, 0.20, 0.17))
    cor = n.mix(n.mul(sujo, 0.7), cor, n.rgb(0.05, 0.045, 0.04))
    riscos = n.arranhoes(n.girar_x(p, 35.0), 4.0, 0.74, 0.03, (1.0, 0.05, 1.0))
    cor = n.mix(n.mul(riscos, 0.5), cor, n.rgb(0.6, 0.6, 0.6))
    rug = n.add(0.3, n.mul(pat, 0.2), n.mul(sujo, 0.25))
    return n.finalizar(cor, rug, n.lerp(sujo, 1.0, 0.6), n.mul(riscos, -0.004))


# ====================================================================== outros
def plastico(n: Nos):
    """Placas pretas quadriculadas da M6 (quadriculado de ~2 mm na UV local)."""
    a, b, _ = n.sep(n.uv("local"))
    passo = 2.0
    s1 = n.m("FRACT", n.m("DIVIDE", n.add(a, b), passo))
    s2 = n.m("FRACT", n.m("DIVIDE", n.m("SUBTRACT", a, b), passo))
    d1 = n.m("ABSOLUTE", n.m("SUBTRACT", s1, 0.5))
    d2 = n.m("ABSOLUTE", n.m("SUBTRACT", s2, 0.5))
    pir = n.m("SUBTRACT", 1.0, n.mul(n.m("MAXIMUM", d1, d2), 2.0))
    campo = n.mapa(n.attr("xadrez"), 0.45, 0.6)
    pir = n.mul(pir, campo)
    p = n.P()
    gasto = n.mul(n.mapa(pir, 0.75, 1.0), n.mapa(n.ruido(p, 0.08), 0.3, 0.7))
    po = n.mul(n.mapa(pir, 0.35, 0.0), campo)
    cor = n.rgb(0.014, 0.014, 0.015)
    cor = n.mix(n.mul(po, 0.7), cor, n.rgb(0.045, 0.042, 0.036))
    cor = n.mix(n.mul(gasto, 0.6), cor, n.rgb(0.03, 0.03, 0.031))
    riscos = n.arranhoes(n.girar_x(p, 20.0), 2.0, 0.76, 0.03, (1.0, 0.03, 1.0))
    cor = n.mix(n.mul(riscos, n.m("SUBTRACT", 1.0, campo)), cor, n.rgb(0.05, 0.05, 0.05))
    sujo = n.mapa(n.oclusao(2.5), 0.95, 0.55)
    cor = n.mix(n.mul(sujo, 0.5), cor, n.rgb(0.03, 0.026, 0.02))
    rug = n.add(0.44, n.mul(po, 0.3), n.mul(gasto, -0.16), n.mul(riscos, 0.15))
    alt = n.add(n.mul(pir, 0.32), n.mul(riscos, -0.01), n.mul(n.ruido(p, 2.0, 2.0), 0.004))
    return n.finalizar(cor, rug, 0.0, alt)


def fibra(n: Nos):
    """Corpo da bainha M8A1: fibra de vidro verde-oliva com fibras, arranhões e barro."""
    p = n.P()
    x, y, z = n.sep(p)
    base = n.rgb(0.046, 0.054, 0.024)
    fib = n.ruido(n.esticar(p, 1.0, 0.06, 1.0), 1.4, 3.0)
    trama = n.ruido(n.esticar(p, 0.5, 0.5, 2.0), 1.2, 2.0)  # esteira de fibra sob a resina
    salp = n.ruido(p, 1.8, 2.0)
    mancha = n.mapa(n.ruido(p, 0.03, 3.0), 0.3, 0.7)
    cor = n.mix(
        1.0,
        base,
        n.rgb(
            n.add(0.66, n.mul(fib, 0.3), n.mul(salp, 0.12), n.mul(trama, 0.12), n.mul(mancha, 0.25))
        ),
        "MULTIPLY",
    )
    esf = n.mul(
        n.m(
            "MAXIMUM",
            n.arranhoes(p, 1.6, 0.70, 0.04, (1.0, 0.06, 1.0), 2.0),
            n.arranhoes(n.girar_x(p, 40.0), 1.3, 0.72, 0.04, (1.0, 0.06, 1.0), 2.0),
        ),
        n.mapa(n.ruido(p, 0.05), 0.3, 0.6),
    )
    esf2 = n.mul(
        n.arranhoes(n.girar_x(p, -25.0), 4.0, 0.66, 0.05, (1.0, 0.03, 1.0), 1.0),
        n.mapa(n.ruido(p, 0.07), 0.4, 0.6),
    )
    cor = n.mix(n.mul(esf, 0.75), cor, n.rgb(0.12, 0.12, 0.085))
    cor = n.mix(n.mul(esf2, 0.4), cor, n.rgb(0.09, 0.095, 0.065))
    # quinas e lados gastos (a resina perde o verde e fica mais clara e áspera)
    quina = n.mul(n.borda(2.0, 0.005, 0.06), n.mapa(n.ruido(p, 0.2, 3.0), 0.35, 0.65))
    cor = n.mix(n.mul(quina, 0.5), cor, n.rgb(0.09, 0.092, 0.06))
    ponta = n.mapa(y, -120.0, -200.0)
    barro = n.mul(n.mapa(n.ruido(p, 0.06, 4.0, 0.6), 0.42, 0.62), n.add(0.3, ponta))
    poeira = n.mapa(n.ruido(p, 0.15, 5.0, 0.65), 0.55, 0.75)
    cor = n.mix(n.mul(barro, 0.8), cor, n.rgb(0.085, 0.066, 0.044))
    cor = n.mix(n.mul(poeira, 0.3), cor, n.rgb(0.11, 0.10, 0.08))
    sujo = n.mapa(n.oclusao(3.0), 0.95, 0.55)
    cor = n.mix(n.mul(sujo, 0.55), cor, n.rgb(0.018, 0.02, 0.01))
    rebarba = n.mapa(n.m("ABSOLUTE", x), 0.35, 0.12)
    rug = n.add(
        0.5,
        n.mul(fib, 0.08),
        n.mul(esf, 0.25),
        n.mul(barro, 0.3),
        n.mul(poeira, 0.2),
        n.mul(quina, 0.15),
    )
    alt = n.add(
        n.mul(fib, 0.01),
        n.mul(trama, 0.008),
        n.mul(esf, -0.02),
        n.mul(esf2, -0.01),
        n.mul(barro, 0.03),
        n.mul(rebarba, 0.05),
    )
    return n.finalizar(cor, rug, 0.0, alt)


def lona(n: Nos):
    """Fita de lona de algodão verde-oliva: trama na UV local (u através, v ao longo)."""
    a, b, _ = n.sep(n.uv("local"))
    p = n.P()
    urdume = n.add(0.5, n.mul(n.m("COSINE", n.mul(a, 2 * math.pi / 0.8)), 0.5))
    trama = n.add(0.5, n.mul(n.m("COSINE", n.mul(b, 2 * math.pi / 0.9)), 0.5))
    alterna = n.m("SIGN", n.m("SINE", n.add(n.mul(b, math.pi / 0.9), n.mul(a, math.pi / 0.8))))
    tec = n.add(n.mul(urdume, n.add(0.6, n.mul(alterna, 0.25))), n.mul(trama, 0.35))
    fio_var = n.branco(w=n.m("FLOOR", n.m("DIVIDE", a, 0.8)))
    base = n.rgb(0.066, 0.068, 0.040)
    cor = n.mix(1.0, base, n.rgb(n.add(0.8, n.mul(tec, 0.25), n.mul(fio_var, 0.15))), "MULTIPLY")
    desb = n.mapa(n.ruido(p, 0.05, 3.0), 0.4, 0.7)
    cor = n.mix(n.mul(desb, 0.35), cor, n.rgb(0.11, 0.105, 0.075))
    sujo = n.mapa(n.oclusao(3.0), 0.95, 0.55)
    barro = n.mapa(n.ruido(p, 0.08, 4.0), 0.55, 0.7)
    cor = n.mix(n.mul(n.m("MAXIMUM", sujo, barro), 0.55), cor, n.rgb(0.045, 0.038, 0.026))
    linha, alt_l, furo = _costura(n, passo=3.2, comp=1.1, raio=0.4, ang=0.0)
    cor = n.mix(linha, cor, n.rgb(0.05, 0.055, 0.03))
    rug = n.add(0.86, n.mul(tec, 0.08))
    alt = n.add(n.mul(tec, 0.07), n.mul(n.ruido(p, 3.0, 2.0), 0.01), alt_l, n.mul(furo, -0.05))
    return n.finalizar(cor, rug, 0.0, alt)


def _madeira(n: Nos, escuro, claro, cinza=None, polido=0.0):
    """Madeira com veio ao longo de Y: anéis de crescimento torcidos (linhas escuras finas e
    irregulares), manchas, poros alongados, esfolados e sujeira."""
    p = n.P()
    torto = n.v(
        "SCALE",
        n.v(
            "SUBTRACT",
            n.ruido(n.esticar(p, 1.0, 0.08, 1.0), 0.05, 3.0, 0.6, cor=True),
            (0.5, 0.5, 0.5),
        ),
        escala=14.0,
    )
    q = n.add(p, torto)
    anel = n.no("ShaderNodeTexWave", wave_type="RINGS", rings_direction="Y", wave_profile="SAW")
    n._in(anel.inputs["Vector"], n.esticar(q, 1.0, 0.02, 1.0))
    anel.inputs["Scale"].default_value = 0.09
    anel.inputs["Distortion"].default_value = 2.5
    anel.inputs["Detail"].default_value = 4.0
    anel.inputs["Detail Scale"].default_value = 1.5
    an = anel.outputs["Fac"]
    linha = n.mapa(an, 0.72, 0.97)
    veio = n.ruido(n.esticar(q, 1.0, 0.03, 1.0), 0.9, 6.0, 0.62)
    mancha = n.mapa(n.ruido(p, 0.025, 3.0), 0.3, 0.7)
    t = n.add(n.mul(veio, 0.45), n.mul(mancha, 0.45), n.mul(an, 0.25))
    cor = n.mix(n.mapa(t, 0.25, 0.95), n.rgb(*escuro), n.rgb(*claro))
    cor = n.mix(n.mul(linha, 0.55), cor, n.rgb(escuro[0] * 0.55, escuro[1] * 0.5, escuro[2] * 0.45))
    poro = n.mapa(n.ruido(n.esticar(p, 2.5, 0.25, 2.5), 2.2, 2.0), 0.68, 0.76)
    cor = n.mix(n.mul(poro, 0.6), cor, n.rgb(escuro[0] * 0.4, escuro[1] * 0.4, escuro[2] * 0.4))
    if cinza is not None:
        cz = n.mapa(n.ruido(p, 0.04, 3.0), 0.35, 0.7)
        cor = n.mix(n.mul(cz, 0.55), cor, n.rgb(*cinza))
    esf = n.mul(
        n.m(
            "MAXIMUM",
            n.arranhoes(n.girar_x(p, 70.0), 1.4, 0.75, 0.04, (1.0, 0.05, 1.0), 2.0),
            n.arranhoes(n.girar_x(p, -35.0), 1.0, 0.76, 0.04, (1.0, 0.05, 1.0), 2.0),
        ),
        n.mapa(n.ruido(p, 0.05), 0.4, 0.6),
    )
    cor = n.mix(n.mul(esf, 0.5), cor, n.rgb(claro[0] * 1.3, claro[1] * 1.3, claro[2] * 1.3))
    sujo = n.mapa(n.oclusao(4.0), 0.95, 0.5)
    cor = n.mix(n.mul(sujo, 0.65), cor, n.rgb(0.015, 0.009, 0.005))
    quina = n.borda(1.2, 0.01, 0.1)
    cor = n.mix(n.mul(quina, 0.4), cor, n.rgb(escuro[0] * 0.5, escuro[1] * 0.5, escuro[2] * 0.5))
    rug = n.add(0.68 - polido, n.mul(veio, 0.08), n.mul(poro, 0.1), n.mul(esf, 0.12))
    alt = n.add(n.mul(veio, 0.025), n.mul(linha, -0.03), n.mul(poro, -0.03), n.mul(esf, -0.02))
    return cor, rug, alt


def madeira_cabo(n: Nos):
    p = n.P()
    cor, rug, alt = _madeira(n, (0.055, 0.028, 0.013), (0.13, 0.072, 0.036), polido=0.18)
    y = n.sep(p)[1]
    mao = n.mul(n.mapa(y, 30.0, 60.0), n.mapa(y, 170.0, 140.0))
    cor = n.mix(n.mul(mao, 0.45), cor, n.rgb(0.03, 0.016, 0.008))
    rug = n.lerp(n.mul(mao, 0.6), rug, 0.4)
    return n.finalizar(cor, rug, 0.0, alt)


def madeira_bainha(n: Nos):
    cor, rug, alt = _madeira(
        n, (0.06, 0.038, 0.022), (0.15, 0.10, 0.058), cinza=(0.10, 0.092, 0.078)
    )
    p = n.P()
    x = n.sep(p)[0]
    junta = n.mapa(n.m("ABSOLUTE", x), 0.75, 0.25)
    cor = n.mix(n.mul(junta, 0.8), cor, n.rgb(0.02, 0.012, 0.007))
    return n.finalizar(cor, rug, 0.0, n.add(alt, n.mul(junta, -0.05)))


def rotim(n: Nos):
    """Voltas de rotim: tiras de ~2,2 mm dando a volta (ao longo de v na UV local)."""
    a, b, _ = n.sep(n.uv("local"))
    p = n.P()
    q = n.m("DIVIDE", n.add(a, n.mul(b, 0.07)), 3.0)
    fr = n.m("FRACT", q)
    idx = n.m("FLOOR", q)
    rnd = n.branco(w=idx)
    rnd2 = n.branco(w=n.add(idx, 31.7))
    perfil = n.m("POWER", n.m("SINE", n.mul(fr, 3.14159)), 0.35)
    beira = n.mapa(perfil, 0.0, 0.55, 1.0, 0.0)
    fibra_ = n.ruido(n.xyz(n.mul(a, 5.0), n.mul(b, 0.12), idx), 1.5, 3.0)
    nos_ = n.mapa(
        n.ruido(n.xyz(n.mul(a, 0.3), n.mul(b, 0.05), n.mul(idx, 3.0)), 3.0, 2.0), 0.66, 0.74
    )
    base = n.mix(n.mapa(rnd, 0.0, 1.0), n.rgb(0.13, 0.075, 0.025), n.rgb(0.27, 0.17, 0.065))
    base = n.mix(n.mul(n.mapa(rnd2, 0.75, 1.0), 0.7), base, n.rgb(0.07, 0.04, 0.015))
    cor = n.mix(1.0, base, n.rgb(n.add(0.72, n.mul(fibra_, 0.45))), "MULTIPLY")
    cor = n.mix(n.mul(nos_, 0.6), cor, n.rgb(0.05, 0.03, 0.012))
    cor = n.mix(n.mul(beira, 0.9), cor, n.rgb(0.02, 0.012, 0.005))
    sujo = n.mapa(n.oclusao(3.0), 0.95, 0.55)
    gasto = n.mapa(n.ruido(p, 0.08, 3.0), 0.35, 0.7)
    cor = n.mix(n.mul(n.add(sujo, n.mul(gasto, 0.5)), 0.6), cor, n.rgb(0.04, 0.025, 0.01))
    rug = n.add(0.3, n.mul(beira, 0.45), n.mul(fibra_, 0.1), n.mul(gasto, 0.18))
    alt = n.add(n.mul(perfil, 0.35), n.mul(fibra_, 0.02), n.mul(nos_, 0.03))
    return n.finalizar(cor, rug, 0.0, alt)


def cordao(n: Nos):
    """Cordão torcido de fibra natural (UV local: u em volta, v ao longo)."""
    a, b, _ = n.sep(n.uv("local"))
    p = n.P()
    q = n.m("DIVIDE", n.add(b, n.mul(a, 1.4)), 2.4)
    fr = n.m("FRACT", q)
    perfil = n.m("POWER", n.m("SINE", n.mul(fr, 3.14159)), 0.6)
    fibras = n.ruido(n.xyz(n.mul(a, 1.0), n.mul(b, 1.0), n.mul(a, 0.3)), 3.0, 4.0)
    cor = n.mix(
        n.mapa(n.ruido(p, 0.15, 3.0), 0.3, 0.7), n.rgb(0.14, 0.11, 0.07), n.rgb(0.23, 0.19, 0.13)
    )
    cor = n.mix(n.mapa(perfil, 0.3, 0.0), cor, n.rgb(0.035, 0.028, 0.018))
    cor = n.mix(1.0, cor, n.rgb(n.add(0.82, n.mul(fibras, 0.3))), "MULTIPLY")
    sujo = n.mapa(n.oclusao(3.0), 0.95, 0.55)
    cor = n.mix(n.mul(sujo, 0.6), cor, n.rgb(0.04, 0.03, 0.02))
    rug = n.add(0.82, n.mul(fibras, 0.1))
    alt = n.add(n.mul(perfil, 0.45), n.mul(fibras, 0.04))
    return n.finalizar(cor, rug, 0.0, alt)


MATERIAIS = {
    "aco_lamina": aco_lamina,
    "aco": aco,
    "arame": arame,
    "aco_azul": aco_azul,
    "ferro": ferro,
    "aco_forjado": aco_forjado,
    "couro_cabo": couro_cabo,
    "couro_bainha": couro_bainha,
    "rebite": rebite,
    "botao": botao,
    "plastico": plastico,
    "fibra": fibra,
    "lona": lona,
    "madeira_cabo": madeira_cabo,
    "madeira_bainha": madeira_bainha,
    "rotim": rotim,
    "cordao": cordao,
}


def criar(nome: str) -> tuple[bpy.types.Material, dict]:
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    n = Nos(mat)
    saidas = MATERIAIS[nome](n)
    return mat, saidas
