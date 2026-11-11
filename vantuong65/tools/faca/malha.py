"""Malha procedural das facas (VẠN TƯỜNG '65): lofts de anéis, tornos e tubos.

Numpy puro (sem bpy): o `produzir.py` passa a malha para o Blender.

Convenções:
- tudo em MILÍMETROS no referencial do Blender (Z para cima): a lâmina corre ao longo de -Y
  (ponta para -Y), o fio aponta para -Z e as faces planas para ±X;
- cada `loft` fecha um sólido (anel fechado + tampas, pontas em leque ou caminho em ciclo) e a
  orientação das faces é acertada para fora pelo volume com sinal;
- a UV "local" é em mm: desenrolada ao longo do anel (modo "rolo": u = comprimento de arco a
  partir do meio da ilha, v = caminho percorrido pelo ponto do meio) ou plana (modo "plano"). Cada
  ilha tem um peso de densidade de texels; o atlas sai do empacotamento no Blender. Ilha espelhada
  é desvirada (u -> -u) para o espaço tangente não inverter;
- atributos por vértice (`d_fio`, `bisel`, `afiado`, `xadrez`) e a UV "costura" (ao longo,
  através da linha de costura, em mm) alimentam os materiais procedurais;
- arestas "vivas" viram arestas duras (normais divididas); o resto é suave.
"""

from __future__ import annotations

import math

import numpy as np

LONGE = 1000.0  # valor de atributo "longe de tudo" (sem efeito no material)
ATRIBUTOS = ("d_fio", "bisel", "afiado", "xadrez")


def _norm(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def _arco(pts: np.ndarray) -> np.ndarray:
    """Comprimento de arco acumulado ao longo de uma polilinha (P, 3)."""
    d = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    return np.concatenate([[0.0], np.cumsum(d)])


def _no_arco(pts: np.ndarray, c: np.ndarray, alvo: float) -> np.ndarray:
    i = int(np.clip(np.searchsorted(c, alvo) - 1, 0, len(pts) - 2))
    seg = c[i + 1] - c[i]
    t = 0.0 if seg < 1e-12 else (alvo - c[i]) / seg
    return pts[i] * (1 - t) + pts[i + 1] * t


def _area_uv(uv: list[tuple[float, float]]) -> float:
    a = 0.0
    for i in range(len(uv)):
        x0, y0 = uv[i]
        x1, y1 = uv[(i + 1) % len(uv)]
        a += x0 * y1 - x1 * y0
    return 0.5 * a


class Malha:
    """Acumula vértices, faces (com UV local, UV de costura, material e ilha) e arestas vivas."""

    def __init__(self) -> None:
        self.v: list[np.ndarray] = []
        self.f: list[list[int]] = []
        self.uv: list[list[tuple[float, float]]] = []
        self.cs: list[list[tuple[float, float]]] = []
        self.mat: list[int] = []
        self.ilha: list[int] = []
        self.no: list[int] = []  # 0 = nó Faca, 1 = nó Bainha
        self.dup: list[int] = []  # 1 = a face também vai na Bainha (cabo da faca embainhada)
        self.pesos: list[float] = []
        self.vivas: set[tuple[int, int]] = set()
        self.attr: dict[str, dict[int, float]] = {k: {} for k in ATRIBUTOS}
        self.materiais: list[str] = []
        self.no_atual = 0
        self.dup_atual = 0
        self._faces_ilha: dict[int, list[int]] = {}

    # ------------------------------------------------------------ básicos
    def m(self, nome: str) -> int:
        if nome not in self.materiais:
            self.materiais.append(nome)
        return self.materiais.index(nome)

    def nova_ilha(self, peso: float) -> int:
        self.pesos.append(float(peso))
        self._faces_ilha[len(self.pesos) - 1] = []
        return len(self.pesos) - 1

    def vert(self, p) -> int:
        self.v.append(np.asarray(p, dtype=float))
        return len(self.v) - 1

    def viva(self, a: int, b: int) -> None:
        self.vivas.add((min(a, b), max(a, b)))

    def _face(self, vs, uvs, mat, ilha, cs) -> int:
        self.f.append([int(x) for x in vs])
        self.uv.append([(float(a), float(b)) for a, b in uvs])
        self.cs.append([(float(a), float(b)) for a, b in cs])
        self.mat.append(mat)
        self.ilha.append(ilha)
        self.no.append(self.no_atual)
        self.dup.append(self.dup_atual)
        self._faces_ilha[ilha].append(len(self.f) - 1)
        return len(self.f) - 1

    def n_tris(self, no: int | None = None) -> int:
        return sum(
            len(f) - 2
            for f, n, d in zip(self.f, self.no, self.dup, strict=True)
            if no is None or n == no or (no == 1 and d == 1)
        )

    # ------------------------------------------------------------ UV de uma ilha
    def _uv_ilha(self, A, K, N, k0, k1, j0, j1, sp, p0, p1) -> dict:
        tab: dict = {}
        modo = sp.get("modo", "rolo")
        if modo == "plano":
            eu = np.asarray(sp["eu"], float)
            ev = np.asarray(sp["ev"], float)
            for k in range(k0, k1 + 1):
                for j in range(j0, j1 + 1):
                    p = A[k % K, j % N]
                    tab[(k, j)] = (float(p @ eu), float(p @ ev))
            for nome, p in (("p0", p0), ("p1", p1)):
                if p is not None:
                    tab[nome] = (float(p @ eu), float(p @ ev))
            return tab
        meios = []
        for k in range(k0, k1 + 1):
            pts = np.array([A[k % K, j % N] for j in range(j0, j1 + 1)])
            c = _arco(pts)
            meio = c[-1] / 2
            meios.append(_no_arco(pts, c, meio))
            for i, j in enumerate(range(j0, j1 + 1)):
                tab[(k, j)] = [float(c[i] - meio), 0.0]
        meios = np.array(meios)
        v = _arco(meios)
        for i, k in enumerate(range(k0, k1 + 1)):
            for j in range(j0, j1 + 1):
                tab[(k, j)][1] = float(v[i])
                tab[(k, j)] = tuple(tab[(k, j)])
        if p1 is not None:
            tab["p1"] = (0.0, float(v[-1] + np.linalg.norm(p1 - meios[-1])))
        if p0 is not None:
            tab["p0"] = (0.0, float(-np.linalg.norm(p0 - meios[0])))
        return tab

    def _ilha_tampa(self, pts: np.ndarray, peso: float) -> tuple[int, list]:
        c = pts.mean(axis=0)
        n = np.zeros(3)
        for i in range(len(pts)):
            a, b = pts[i] - c, pts[(i + 1) % len(pts)] - c
            n += np.cross(a, b)
        n = _norm(n) if np.linalg.norm(n) > 1e-12 else np.array([0.0, 0.0, 1.0])
        ref = np.array([0.0, 0.0, 1.0]) if abs(n[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        e1 = _norm(np.cross(ref, n))
        e2 = np.cross(n, e1)
        iid = self.nova_ilha(peso)
        return iid, [(float((p - c) @ e1), float((p - c) @ e2)) for p in pts]

    # ------------------------------------------------------------ loft
    def loft(
        self,
        aneis,
        mat: str,
        *,
        fechado: bool = True,
        ciclo: bool = False,
        ponta0=None,
        ponta1=None,
        tampa0: bool = False,
        tampa1: bool = False,
        ilhas: list[dict] | None = None,
        peso: float = 1.0,
        peso_tampa: float | None = None,
        vivas_j=(),
        vivas_k=(),
        tampa_viva: bool = False,
        costura=None,
        attrs: dict | None = None,
        attrs_ponta: dict | None = None,
    ) -> np.ndarray:
        """Superfície entre anéis consecutivos (K anéis de N pontos), fechada num sólido.

        `ilhas`: [{"k": (k0, k1), "j": (j0, j1), "modo": "rolo"|"plano", "peso": w, ...}] com
        índices estendidos (k até K com `ciclo`, j até N com anel `fechado`). Sem `ilhas`, uma ilha
        só (costura da UV no ponto j = 0)."""
        A = np.asarray(aneis, dtype=float)
        K, N = A.shape[0], A.shape[1]
        base = len(self.v)
        self.v.extend(list(A.reshape(-1, 3)))
        ids = base + np.arange(K * N).reshape(K, N)
        p0 = None if ponta0 is None else np.asarray(ponta0, float)
        p1 = None if ponta1 is None else np.asarray(ponta1, float)
        pid0 = None if p0 is None else self.vert(p0)
        pid1 = None if p1 is None else self.vert(p1)
        mi = self.m(mat)
        ke = K if ciclo else K - 1  # último anel estendido
        je = N if fechado else N - 1
        f_ini = len(self.f)
        tabelas = []
        for sp in ilhas or [{}]:
            k0, k1 = sp.get("k", (0, ke))
            j0, j1 = sp.get("j", (0, je))
            iid = self.nova_ilha(sp.get("peso", peso))
            q0 = p0 if k0 == 0 else None
            q1 = p1 if k1 == ke else None
            tab = self._uv_ilha(A, K, N, k0, k1, j0, j1, sp, q0, q1)
            tabelas.append((k0, k1, j0, j1, iid, tab))

        def acha(ka, kb, ja, jb):
            for t in tabelas:
                if t[0] <= ka and kb <= t[1] and t[2] <= ja and jb <= t[3]:
                    return t
            raise ValueError(f"face sem ilha: k {ka}-{kb} j {ja}-{jb}")

        cs = None if costura is None else np.asarray(costura, float)

        def c_de(k, j):
            return (0.0, 99.0) if cs is None else tuple(cs[k % K, j % N])

        for ka in range(ke):
            kb = ka + 1
            for j in range(je):
                t = acha(ka, kb, j, j + 1)
                cantos = [(ka, j), (ka, j + 1), (kb, j + 1), (kb, j)]
                vs = [ids[k % K, jj % N] for k, jj in cantos]
                self._face(vs, [t[5][c] for c in cantos], mi, t[4], [c_de(*c) for c in cantos])
        for j in range(je):
            if pid1 is not None:
                t = acha(ke, ke, j, j + 1)
                cantos = [(ke, j), (ke, j + 1)]
                vs = [ids[k % K, jj % N] for k, jj in cantos] + [pid1]
                uvs = [t[5][c] for c in cantos] + [t[5]["p1"]]
                self._face(vs, uvs, mi, t[4], [c_de(*c) for c in cantos] + [(0.0, 99.0)])
            if pid0 is not None:
                t = acha(0, 0, j, j + 1)
                cantos = [(0, j + 1), (0, j)]
                vs = [ids[k % K, jj % N] for k, jj in cantos] + [pid0]
                uvs = [t[5][c] for c in cantos] + [t[5]["p0"]]
                self._face(vs, uvs, mi, t[4], [c_de(*c) for c in cantos] + [(0.0, 99.0)])
        pt = peso if peso_tampa is None else peso_tampa
        for usar, k, inverte in ((tampa0, 0, True), (tampa1, K - 1, False)):
            if not usar:
                continue
            ordem = list(range(N))[::-1] if inverte else list(range(N))
            iid, uvs = self._ilha_tampa(A[k, ordem], pt)
            vs = [ids[k, j] for j in ordem]
            self._face(vs, uvs, mi, iid, [c_de(k, j) for j in ordem])
            if tampa_viva:
                for j in range(N):
                    self.viva(ids[k, j], ids[k, (j + 1) % N])
        for item in vivas_j:  # j (todo o comprimento) ou (j, k0, k1): só entre os anéis k0..k1
            j, kv0, kv1 = item if isinstance(item, tuple) else (item, 0, ke)
            for ka in range(max(0, kv0), min(ke, kv1)):
                self.viva(ids[ka % K, j % N], ids[(ka + 1) % K, j % N])
            if pid1 is not None and kv1 >= ke:
                self.viva(ids[K - 1, j % N], pid1)
            if pid0 is not None and kv0 <= 0:
                self.viva(ids[0, j % N], pid0)
        for k in vivas_k:
            for j in range(je):
                self.viva(ids[k % K, j % N], ids[k % K, (j + 1) % N])
        if attrs:
            for nome, arr in attrs.items():
                arr = np.asarray(arr, float)
                for k in range(K):
                    for j in range(N):
                        self.attr[nome][int(ids[k, j])] = float(arr[k, j])
        if attrs_ponta:
            for nome, val in attrs_ponta.items():
                for pid in (pid0, pid1):
                    if pid is not None:
                        self.attr[nome][pid] = float(val)
        self._orientar(f_ini)
        return ids

    def _orientar(self, f_ini: int) -> None:
        """Faces para fora (volume com sinal do sólido) e ilhas sem espelhamento."""
        vol = 0.0
        for f in self.f[f_ini:]:
            a = self.v[f[0]]
            for i in range(1, len(f) - 1):
                vol += a @ np.cross(self.v[f[i]], self.v[f[i + 1]])
        if vol < 0:
            for i in range(f_ini, len(self.f)):
                self.f[i] = self.f[i][::-1]
                self.uv[i] = self.uv[i][::-1]
                self.cs[i] = self.cs[i][::-1]
        ilhas = sorted({self.ilha[i] for i in range(f_ini, len(self.f))})
        for iid in ilhas:
            fs = self._faces_ilha[iid]
            if sum(_area_uv(self.uv[i]) for i in fs) < 0:
                for i in fs:
                    self.uv[i] = [(-u, v) for u, v in self.uv[i]]

    # ------------------------------------------------------------ formas prontas
    def torno(
        self,
        perfil,
        mat: str,
        *,
        centro=(0.0, 0.0, 0.0),
        eixo=(0.0, 1.0, 0.0),
        ref=(0.0, 0.0, 1.0),
        n: int = 16,
        fase: float = 0.0,
        ciclo: bool = False,
        escala_x: float = 1.0,
        **kw,
    ) -> np.ndarray:
        """Sólido de revolução: `perfil` = [(r, h)] ao longo do `eixo`. Raio 0 nas pontas vira
        polo (leque). Com `ciclo`, o perfil é fechado (anel, luva). `escala_x` achata o círculo
        na direção perpendicular a `ref` (oval)."""
        c = np.asarray(centro, float)
        a = _norm(np.asarray(eixo, float))
        e2 = _norm(np.asarray(ref, float) - (np.asarray(ref, float) @ a) * a)
        e1 = np.cross(e2, a)
        perfil = [tuple(p) for p in perfil]
        p0 = p1 = None
        if not ciclo and perfil[0][0] <= 1e-9:
            p0 = c + perfil[0][1] * a
            perfil = perfil[1:]
        if not ciclo and perfil[-1][0] <= 1e-9:
            p1 = c + perfil[-1][1] * a
            perfil = perfil[:-1]
        t = fase + 2 * math.pi * np.arange(n) / n
        circ = np.column_stack([np.cos(t) * escala_x, np.sin(t)])
        aneis = np.array([c + h * a + r * (circ[:, :1] * e1 + circ[:, 1:] * e2) for r, h in perfil])
        kw.setdefault("tampa0", p0 is None and not ciclo)
        kw.setdefault("tampa1", p1 is None and not ciclo)
        return self.loft(aneis, mat, ciclo=ciclo, ponta0=p0, ponta1=p1, **kw)

    def tubo(self, caminho, perfil, mat: str, *, normal0=None, ciclo: bool = False, **kw):
        """Varre o `perfil` 2D [(n, b)] ao longo do `caminho` (P, 3) com quadros de transporte
        paralelo: n na direção normal (começa em `normal0`), b na binormal."""
        C = np.asarray(caminho, float)
        Tg = quadro_tangentes(C, ciclo)
        Nn = np.zeros_like(C)
        n0 = np.asarray(normal0 if normal0 is not None else (0.0, 0.0, 1.0), float)
        n0 = _norm(n0 - (n0 @ Tg[0]) * Tg[0])
        Nn[0] = n0
        for k in range(1, len(C)):
            v = Nn[k - 1] - (Nn[k - 1] @ Tg[k]) * Tg[k]
            Nn[k] = _norm(v)
        B = np.cross(Tg, Nn)
        P = np.asarray(perfil, float)
        aneis = C[:, None, :] + P[None, :, :1] * Nn[:, None, :] + P[None, :, 1:] * B[:, None, :]
        if not ciclo:
            kw.setdefault("tampa0", True)
            kw.setdefault("tampa1", True)
        return self.loft(aneis, mat, ciclo=ciclo, **kw)

    def domo(
        self,
        centro,
        eixo,
        mat: str,
        raio: float,
        altura: float,
        *,
        n: int = 8,
        afundar: float = 0.25,
        perfil=None,
        **kw,
    ) -> np.ndarray:
        """Cabeça de rebite / botão: calota sobre `centro` (na superfície), virada para `eixo`."""
        a = _norm(np.asarray(eixo, float))
        ref = (0.0, 0.0, 1.0) if abs(a[2]) < 0.9 else (1.0, 0.0, 0.0)
        if perfil is None:
            perfil = [
                (raio, -afundar),
                (raio * 0.97, altura * 0.35),
                (raio * 0.66, altura * 0.85),
                (0.0, altura),
            ]
        return self.torno(perfil, mat, centro=centro, eixo=a, ref=ref, n=n, **kw)


def quadro_tangentes(C: np.ndarray, ciclo: bool) -> np.ndarray:
    if ciclo:
        T = np.roll(C, -1, axis=0) - np.roll(C, 1, axis=0)
    else:
        T = np.zeros_like(C)
        T[1:-1] = C[2:] - C[:-2]
        T[0] = C[1] - C[0]
        T[-1] = C[-1] - C[-2]
    return _norm(T)


def superelipse(a: float, b: float, n: int, expo: float = 2.0, fase: float = -math.pi / 2):
    """Pontos (x, z) de uma superelipse: meia-altura `a` (z), meia-largura `b` (x). Começa em
    `fase` (padrão: embaixo, -Z, onde fica a costura da UV) e gira no sentido anti-horário."""
    t = fase + 2 * math.pi * np.arange(n) / n
    c, s = np.cos(t), np.sin(t)
    x = b * np.sign(c) * np.abs(c) ** (2 / expo)
    z = a * np.sign(s) * np.abs(s) ** (2 / expo)
    return np.column_stack([x, z])


def anel_xz(y: float, xz, cz: float = 0.0, cx: float = 0.0) -> np.ndarray:
    xz = np.asarray(xz, float)
    return np.column_stack([xz[:, 0] + cx, np.full(len(xz), y), xz[:, 1] + cz])


def ret_arred(hx: float, hy: float, r: float, n_canto: int = 3) -> np.ndarray:
    """Retângulo de cantos arredondados (meias-medidas hx, hy, raio r), anti-horário, começando
    no canto (+, -). Devolve (4 n_canto, 2)."""
    r = min(r, hx * 0.999, hy * 0.999)
    out = []
    for cx, cy, a0 in (
        (hx - r, -hy + r, -90),
        (hx - r, hy - r, 0),
        (-hx + r, hy - r, 90),
        (-hx + r, -hy + r, 180),
    ):
        for i in range(n_canto):
            a = math.radians(a0 + 90 * i / (n_canto - 1))
            out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return np.array(out)


def estacoes(f_anel, s_fino, tol: float, fixas=()) -> np.ndarray:
    """Escolhe estações entre `s_fino` (ordenadas) para que a interpolação linear entre as
    escolhidas fique a menos de `tol` (mm) de todos os anéis do meio. `fixas` ficam sempre."""
    s_fino = np.unique(np.concatenate([np.asarray(s_fino, float), np.asarray(fixas, float)]))
    R = np.array([f_anel(s) for s in s_fino])
    fix = {int(np.argmin(np.abs(s_fino - f))) for f in fixas}
    M = len(s_fino)
    manter = [0]
    i = 0
    while i < M - 1:
        melhor = i + 1
        j = i + 2
        while j < M and melhor not in fix:
            t = (s_fino[i + 1 : j] - s_fino[i]) / (s_fino[j] - s_fino[i])
            interp = R[i][None] * (1 - t)[:, None, None] + R[j][None] * t[:, None, None]
            if np.abs(R[i + 1 : j] - interp).max() > tol:
                break
            melhor = j
            j += 1
        manter.append(melhor)
        i = melhor
    return s_fino[manter]


def simplificar(pts, tol: float, fechado: bool = False) -> np.ndarray:
    """Tira pontos de uma polilinha mantendo todos os originais a menos de `tol` (mm) dela."""
    P = np.asarray(pts, float)
    if fechado or len(P) < 3:
        return P
    manter = [0]
    i = 0
    while i < len(P) - 1:
        melhor = i + 1
        for j in range(i + 2, len(P)):
            a, b = P[i], P[j]
            ab = b - a
            t = np.clip(((P[i + 1 : j] - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
            d = np.linalg.norm(P[i + 1 : j] - (a + t[:, None] * ab), axis=1)
            if d.max() > tol:
                break
            melhor = j
        manter.append(melhor)
        i = melhor
    return P[manter]


def suave(x, a: float, b: float):
    """smoothstep de a a b (a > b inverte)."""
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)
