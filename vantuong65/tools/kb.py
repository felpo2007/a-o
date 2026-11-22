"""Base de conhecimento do jogo (D-244): acha o que importa sem ler o projeto inteiro.

    uv run python tools/kb.py onde <termos>        notas, módulos, decisões e ativos
    uv run python tools/kb.py modulo <Nome>        resumo, API, de quem depende e quem usa
    uv run python tools/kb.py remote <Nome>        direção, quem dispara e quem escuta
    uv run python tools/kb.py decisao D-243 [--texto]
    uv run python tools/kb.py ativo <termo>        ID, triângulos e medidas
    uv run python tools/kb.py mapa <id> [setor]    dados espaciais do Layout gerado
    uv run python tools/kb.py check                integridade da base
    uv run python tools/kb.py velhas               notas cujo código mudou desde a verificação
    uv run python tools/kb.py confere <nota>       marca a nota como verificada no commit atual

Módulos, remotes, ativos e mapas são lidos do código na hora, então não ficam desatualizados.
A saída é curta de propósito: serve para decidir o que abrir, não para substituir o código.
"""

from __future__ import annotations

import datetime as dt
import json
import math
import re
import subprocess
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
KB = RAIZ / "knowledge"
SRC = RAIZ / "src"
DESIGN = RAIZ / "DESIGN.md"
CLAUDE = RAIZ / "CLAUDE.md"
ORCA = SRC / "ServerScriptService" / "Modules" / "ArtBudget.luau"
NET = SRC / "ReplicatedStorage" / "Shared" / "Net.luau"
MAPAS = SRC / "ReplicatedStorage" / "Shared" / "MapasRet.luau"
IDS = RAIZ / "assets" / "roblox_ids.json"
M = 0.28
ESTADOS = {"verified", "planned", "stale", "deprecated"}
LIMITE_CLAUDE = 150
LIMITE_NOTA = 260
PERMITIDO = {"noreply@anthropic.com"}
SEGREDOS = (
    re.compile(r"ROBLOX_API_KEY\s*=\s*\S"),
    re.compile(r"(?<![\w/.-])[A-Za-z0-9_-]{48,}(?![\w/.-])"),
    re.compile(r"[\w.+-]+@[\w-]+\.[a-z]{2,}"),
)
CAMINHO = re.compile(
    r"`((?:src|tools|tests|testes|knowledge)/[^`\s<>*]+?\.(?:luau|py|md|json|ps1))`"
)


def normaliza(s: str) -> str:
    d = unicodedata.normalize("NFKD", s)
    return "".join(c for c in d if not unicodedata.combining(c)).lower()


def ler(p: Path) -> str:
    return p.read_text("utf-8", "replace").replace("\r\n", "\n")


def rel(p: Path) -> str:
    return p.relative_to(RAIZ).as_posix()


def git(*args: str) -> str:
    r = subprocess.run(
        ["git", *args], cwd=RAIZ, capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    return r.stdout.strip() if r.returncode == 0 else ""


# ===================================================================== notas
def frontmatter(texto: str) -> dict:
    texto = texto.replace("\r\n", "\n")
    if not texto.startswith("---\n"):
        return {}
    fim = texto.find("\n---", 4)
    if fim < 0:
        return {}
    dados: dict = {}
    chave = None
    for linha in texto[4:fim].split("\n"):
        m = re.match(r"([\w-]+):\s*(.*)$", linha)
        if m:
            chave = m[1]
            dados[chave] = m[2].strip() if m[2].strip() else []
        elif chave and linha.strip().startswith("- ") and isinstance(dados[chave], list):
            dados[chave].append(linha.strip()[2:].strip())
    return dados


def notas() -> list[Path]:
    if not KB.is_dir():
        return []
    return sorted(p for p in KB.rglob("*.md") if ".obsidian" not in p.parts)


def links(texto: str) -> list[str]:
    return [a.strip() for a in re.findall(r"\[\[([^\]|#]+)", texto)]


def achar_nota(nome: str) -> Path | None:
    alvo = normaliza(nome.removesuffix(".md"))
    for p in notas():
        if normaliza(p.stem) == alvo or normaliza(rel(p).removesuffix(".md")) == alvo:
            return p
        if normaliza(p.relative_to(KB).as_posix().removesuffix(".md")) == alvo:
            return p
    return None


# ===================================================================== módulos
@dataclass
class Modulo:
    nome: str
    caminho: Path
    texto: str
    resumo: str
    api: list[str] = field(default_factory=list)
    usa: set[str] = field(default_factory=set)
    usado: set[str] = field(default_factory=set)

    @property
    def id(self) -> str:
        return rel(self.caminho)


def resumo(texto: str) -> str:
    partes: list[str] = []
    for linha in texto.split("\n")[:12]:
        s = linha.strip()
        if s.startswith("--!") or not s:
            continue
        if not s.startswith("--"):
            break
        partes.append(s.lstrip("- ").strip())
        if len(" ".join(partes)) > 90:
            break
    return " ".join(partes)[:120]


def alvo_require(expr: str, origem: Path, por_nome: dict[str, list[Modulo]]) -> Modulo | None:
    achados = re.findall(r'WaitForChild\("(\w+)"', expr) or re.findall(r"\.(\w+)", expr)
    if not achados:
        return None
    lista = por_nome.get(achados[-1])
    if not lista:
        return None
    if len(lista) == 1:
        return lista[0]
    if "script" in expr:
        for m in lista:
            if m.caminho.parent == origem.parent:
                return m
    for pasta in ("Shared", "Modules", "Controllers"):
        if pasta in expr:
            for m in lista:
                if pasta in m.caminho.parts:
                    return m
    return lista[0]


def modulos() -> list[Modulo]:
    saida: list[Modulo] = []
    for p in SRC.rglob("*.luau"):
        if any(re.fullmatch(r"Data(_\w+)?", a) for a in p.parts):
            continue
        nome = p.name.split(".")[0]
        if nome == "init":
            nome = p.parent.name
        t = ler(p)
        api = [m[1] for m in re.finditer(r"^function \w+[.:](\w+)\(", t, re.M)]
        saida.append(Modulo(nome, p, t, resumo(t), api))
    por_nome: dict[str, list[Modulo]] = {}
    for m in saida:
        por_nome.setdefault(m.nome, []).append(m)
    por_id = {m.id: m for m in saida}
    for m in saida:
        for ex in re.findall(r"require\(\s*([^()\n]*(?:\([^()\n]*\)[^()\n]*)*)\)", m.texto):
            a = alvo_require(ex, m.caminho, por_nome)
            if a and a is not m:
                m.usa.add(a.id)
                por_id[a.id].usado.add(m.id)
    return sorted(saida, key=lambda m: m.id)


def curto(ids: set[str], lim: int = 18) -> str:
    nomes = sorted({Path(i).name.split(".")[0] for i in ids})
    extra = f" (+{len(nomes) - lim})" if len(nomes) > lim else ""
    return ", ".join(nomes[:lim]) + extra if nomes else "nenhum"


# ===================================================================== decisões
@dataclass
class Decisao:
    linha: int
    fim: int
    nivel: int
    titulo: str
    ids: list[int]


def decisoes() -> list[Decisao]:
    linhas = ler(DESIGN).split("\n")
    cab = []
    for i, s in enumerate(linhas, 1):
        m = re.match(r"(#+)\s+(.*)$", s)
        if m:
            cab.append((i, len(m[1]), m[2]))
    saida = []
    for k, (i, nivel, titulo) in enumerate(cab):
        ids = [int(a) for a in re.findall(r"\bD-(\d+)", titulo)]
        if not ids:
            continue
        fim = len(linhas)
        for j, n2, _ in cab[k + 1 :]:
            if n2 <= nivel:
                fim = j - 1
                break
        saida.append(Decisao(i, fim, nivel, titulo, ids))
    return saida


# ===================================================================== comandos
def cmd_onde(args: list[str]) -> int:
    termos = [normaliza(a) for a in args]
    if not termos:
        raise SystemExit("uso: kb.py onde <termos>")

    def conta(s: str) -> int:
        return sum(1 for a in termos if a in s)

    achadas = []
    for p in notas():
        t = normaliza(ler(p))
        nome = normaliza(rel(p))
        tem = conta(t) + conta(nome)
        if not tem:
            continue
        nota = 8 * conta(nome) + 3 * conta(t) + sum(min(t.count(a), 6) for a in termos)
        linhas = [i for i, s in enumerate(t.split("\n"), 1) if any(a in s for a in termos)]
        achadas.append((nota, p, linhas[0] if linhas else 1, len(linhas)))
    print("NOTAS")
    for _, p, li, n in sorted(achadas, key=lambda x: -x[0])[:4]:
        estado = frontmatter(ler(p)).get("status", "-")
        print(f"  {rel(p)}:{li} [{estado}] {n} linhas com o termo")
    if not achadas:
        print("  nenhuma")
    mods = []
    for m in modulos():
        nome = normaliza(m.nome)
        fn = normaliza(" ".join(m.api))
        nota = 8 * conta(nome) + 3 * conta(normaliza(m.resumo)) + conta(fn)
        if nota:
            mods.append((nota, m))
    print("MÓDULOS")
    for _, m in sorted(mods, key=lambda x: (-x[0], x[1].id))[:8]:
        print(f"  {m.id} ({len(m.texto) // 1024} KB): {m.resumo[:78]}")
    if not mods:
        print("  nenhum")
    ds = [(conta(normaliza(d.titulo)), d) for d in decisoes()]
    print("DECISÕES (DESIGN.md)")
    boas = sorted((x for x in ds if x[0]), key=lambda x: (-x[0], -x[1].linha))[:4]
    for _, d in boas:
        print(f"  DESIGN.md:{d.linha} {d.titulo[:84]}")
    if not boas:
        print("  nenhuma")
    return 0


def cmd_modulo(args: list[str]) -> int:
    if not args:
        raise SystemExit("uso: kb.py modulo <Nome>")
    alvo = normaliza(args[0])
    todos = modulos()
    lista = [m for m in todos if normaliza(m.nome) == alvo] or [
        m for m in todos if alvo in normaliza(m.nome)
    ]
    if not lista:
        print("nenhum módulo com esse nome")
        return 1
    if len(lista) > 6:
        print("vários: " + ", ".join(sorted(m.nome for m in lista)[:24]))
        return 0
    for m in lista:
        print(f"{m.id} ({len(m.texto) // 1024} KB, {m.texto.count(chr(10))} linhas)")
        print(f"  resumo: {m.resumo}")
        print(f"  API: {', '.join(m.api[:22]) or 'nenhuma'}{' ...' if len(m.api) > 22 else ''}")
        print(f"  usa: {curto(m.usa)}")
        print(f"  usado por: {curto(m.usado)}")
    return 0


def lista_remotes() -> dict[str, tuple[str, str]]:
    t = ler(NET)
    t = t[: t.index("function Net.server")]
    saida: dict[str, tuple[str, str]] = {}
    for bloco in re.finditer(r"Net\.(\w+)\s*=\s*\{(.*?)\n\}", t, re.S):
        for m in re.finditer(r'"(\w+)",?[ \t]*(?:--[ \t]*([^\n]*))?', bloco[2]):
            saida[m[1]] = (bloco[1], (m[2] or "").strip())
    return saida


USOS = (
    ("servidor escuta", r"OnServerEvent|OnServerInvoke"),
    ("cliente envia", r"FireServer|InvokeServer"),
    ("servidor envia", r"FireClient|FireAllClients"),
    ("cliente escuta", r"OnClientEvent"),
)


def usos_remote(nome: str, mods: list[Modulo]) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {r: set() for r, _ in USOS}
    pad = re.compile(r'["\.]' + re.escape(nome) + r'\b"?')
    for m in mods:
        if m.caminho == NET or nome not in m.texto:
            continue
        linhas = [s for s in m.texto.split("\n") if pad.search(s)]
        trechos = list(linhas)
        for s in linhas:
            v = re.match(r"\s*local (\w+)\s*(?::[^=]+)?=", s)
            if v:
                trechos += [q for q in m.texto.split("\n") if re.search(rf"\b{v[1]}[.:]", q)]
        for rotulo, rx in USOS:
            if any(re.search(rx, s) for s in trechos):
                out[rotulo].add(m.id)
    return out


def cmd_remote(args: list[str]) -> int:
    todos = lista_remotes()
    if not args:
        grupos: dict[str, int] = {}
        for tipo, _ in todos.values():
            grupos[tipo] = grupos.get(tipo, 0) + 1
        print(f"{len(todos)} remotes em {rel(NET)}: {grupos}")
        return 0
    alvo = normaliza(args[0])
    achados = [n for n in todos if alvo in normaliza(n)]
    if not achados:
        print("nenhum remote com esse nome")
        return 1
    if len(achados) > 5:
        print("vários: " + ", ".join(sorted(achados)[:30]))
        return 0
    mods = modulos()
    for n in achados:
        print(f"{n} [{todos[n][0]}] {todos[n][1]}")
        for rotulo, ids in usos_remote(n, mods).items():
            if ids:
                print(f"  {rotulo}: {curto(ids, 8)}")
    return 0


def cmd_decisao(args: list[str]) -> int:
    ids = [int(a) for x in args for a in re.findall(r"\d+", x)]
    if not ids:
        raise SystemExit("uso: kb.py decisao D-243 [--texto]")
    lista = [d for d in decisoes() if ids[0] in d.ids]
    if not lista:
        print("nenhuma decisão com esse número")
        return 1
    linhas = ler(DESIGN).split("\n")
    for d in lista:
        print(f"DESIGN.md:{d.linha}-{d.fim} {d.titulo[:90]}")
        if "--texto" in args:
            corpo = linhas[d.linha : min(d.fim, d.linha + 45)]
            print("\n".join(s[:160] for s in corpo))
            if d.fim > d.linha + 45:
                print(f"... mais {d.fim - d.linha - 45} linhas")
    return 0


def tabela_orca(nome: str) -> str:
    t = ler(ORCA)
    i = t.find(f"ArtBudget.{nome} = {{")
    return t[i : t.index("\n}", i)] if i >= 0 else ""


def cmd_ativo(args: list[str]) -> int:
    if not args:
        raise SystemExit("uso: kb.py ativo <termo>")
    alvo = normaliza(args[0])
    ids = json.loads(ler(IDS))
    tris = {m[1]: int(m[2]) for m in re.finditer(r"(\w+) = (\d+),", tabela_orca("TRIS"))}
    dims = {
        m[1]: (float(m[2]) * M, float(m[3]) * M, float(m[4]) * M)
        for m in re.finditer(r"(\w+) = \{ ([\d.]+), ([\d.]+), ([\d.]+) \}", tabela_orca("DIMS"))
    }
    achados = sorted(k for k in ids if alvo in normaliza(k))
    print(f"{len(achados)} de {len(ids)} ativos")
    for k in achados[:16]:
        c = k.split(".", 1)[-1]
        extra = f" {tris[c]} tri" if c in tris else ""
        if c in dims:
            a, h, b = dims[c]
            extra += f" {a:.1f} x {b:.1f} x {h:.1f} m"
        print(f"  {k} = {ids[k]}{extra}")
    if len(achados) > 16:
        print(f"  ... mais {len(achados) - 16}")
    return 0


def projeto_mapa(id_: str) -> dict:
    t = ler(MAPAS)
    i = t.index(f'id = "{id_}"')
    j = t.find('id = "comboio"', i + 5)
    b = t[i : j if j > 0 else len(t)]
    return {
        "nome": re.search(r'nome = "([^"]+)"', b)[1],
        "modo": re.search(r'modo = "([^"]+)"', b)[1],
        "comp": float(re.search(r"compM = ([\d.]+)", b)[1]),
        "prof": float(re.search(r"profM = ([\d.]+)", b)[1]),
        "bases": re.findall(r"base(Oeste|Leste) = \{ x = ([\d.]+), y = ([\d.]+)", b),
        "setores": [
            (m[1], m[2], float(m[3]), float(m[4]))
            for m in re.finditer(r'id = "(\w)", nome = "([^"]+)", x = ([\d.]+), y = ([\d.]+)', b)
        ],
    }


def cmd_mapa(args: list[str]) -> int:
    if not args or args[0] not in ("frente", "comboio"):
        print("mapas com dados gerados: frente, comboio. O principal: World/Mapa-Principal.md")
        return 1
    p = projeto_mapa(args[0])
    layout = ler(SRC / "ServerStorage" / "VT65Build" / f"Data_{args[0]}" / "Layout.luau")
    pad = re.compile(
        r'key = "(\w+)", x = ([-\d.]+), z = ([-\d.]+), yaw = ([-\d.]+), scale = [\d.]+, '
        r'tipo = "(\w+)"'
    )
    itens = [
        (
            m[1],
            float(m[2]) * M + p["comp"] / 2,
            p["prof"] / 2 - float(m[3]) * M,
            (-math.degrees(float(m[4])) + 180) % 360 - 180,
            m[5],
        )
        for m in pad.finditer(layout)
    ]
    if len(args) == 1:
        print(f"{p['nome']} ({args[0]}), {p['modo']}, {p['comp']:.0f} x {p['prof']:.0f} m")
        print("  planta: X leste, Y norte. Mundo: X = (x-comp/2)/0.28, Z = -(y-prof/2)/0.28")
        print("  bases: " + ", ".join(f"{a} ({x}, {y})" for a, x, y in p["bases"]))
        for s in p["setores"]:
            print(f"  {s[0]} {s[1]} ({s[2]:.0f}, {s[3]:.0f})")
        casas = sum(1 for i in itens if i[4] == "casa")
        pontes = len(re.findall(r'tipo = "(?:rodoviaria|passarela)"', layout))
        conj = len(re.findall(r'id = "c\d+"', layout))
        print(f"  {len(itens)} construções ({casas} casas), {pontes} pontes, {conj} conjuntos")
        return 0
    s = next((a for a in p["setores"] if a[0] == args[1].upper()), None)
    if not s:
        print("setor inexistente")
        return 1
    perto = sorted(((math.hypot(i[1] - s[2], i[2] - s[3]), i) for i in itens), key=lambda a: a[0])
    perto = [a for a in perto if a[0] <= 48]
    print(f"{s[0]} {s[1]} ({s[2]:.0f}, {s[3]:.0f}): {len(perto)} peças a até 48 m")
    grupos: dict[str, list[str]] = {}
    for d, i in perto:
        if i[4] == "casa":
            grupos.setdefault("casas", []).append(i[0])
            continue
        grupos.setdefault(i[0], []).append(
            f"({i[1] - s[2]:+.0f},{i[2] - s[3]:+.0f}) r{i[3]:.0f} d{d:.0f}"
        )
    for k, v in grupos.items():
        print(f"  {k}: {len(v)} casas" if k == "casas" else f"  {k}: {' '.join(v[:5])}")
    return 0


def problemas() -> tuple[list[str], list[str]]:
    erros: list[str] = []
    avisos: list[str] = []
    lista = notas()
    if not lista:
        return ["knowledge/ sem notas"], []
    if CLAUDE.is_file():
        n = ler(CLAUDE).count("\n") + 1
        if n > LIMITE_CLAUDE:
            erros.append(f"CLAUDE.md com {n} linhas (limite {LIMITE_CLAUDE})")
    for p in lista:
        t = ler(p)
        nome = rel(p)
        fm = frontmatter(t)
        if not fm:
            erros.append(f"{nome}: sem frontmatter")
        elif fm.get("status") not in ESTADOS:
            erros.append(f"{nome}: status inválido ({fm.get('status')})")
        fontes = fm.get("source_paths", [])
        for f in fontes if isinstance(fontes, list) else []:
            if not (RAIZ / f).exists():
                erros.append(f"{nome}: source_path inexistente: {f}")
        if fm.get("status") == "verified" and not fm.get("verified_commit"):
            erros.append(f"{nome}: verified sem verified_commit")
        for a in links(t):
            if achar_nota(a) is None:
                erros.append(f"{nome}: link quebrado [[{a}]]")
        for a in CAMINHO.findall(t):
            if not (RAIZ / a).exists():
                avisos.append(f"{nome}: caminho citado não existe: {a}")
        for rx in SEGREDOS:
            for m in rx.finditer(t):
                if m[0] not in PERMITIDO:
                    erros.append(f"{nome}: possível segredo ({m[0][:12]}...)")
        if t.count("\n") > LIMITE_NOTA:
            avisos.append(f"{nome}: {t.count(chr(10))} linhas (acima de {LIMITE_NOTA})")
    return erros, avisos


def cmd_check(_args: list[str]) -> int:
    erros, avisos = problemas()
    print(f"{len(notas())} notas, {len(erros)} erros, {len(avisos)} avisos")
    for e in erros[:20]:
        print("  ERRO " + e)
    for a in avisos[:12]:
        print("  aviso " + a)
    if len(avisos) > 12:
        print(f"  ... mais {len(avisos) - 12} avisos")
    return 1 if erros else 0


def cmd_velhas(_args: list[str]) -> int:
    n = 0
    for p in notas():
        fm = frontmatter(ler(p))
        c, fontes = fm.get("verified_commit"), fm.get("source_paths")
        if fm.get("status") != "verified" or not c or not isinstance(fontes, list) or not fontes:
            continue
        mudou = git("rev-list", "--count", f"{c}..HEAD", "--", *fontes)
        if mudou and mudou != "0":
            n += 1
            print(f"  {rel(p)}: {mudou} commits nas fontes desde {c}")
    print(f"{n} notas para reverificar")
    return 0


def cmd_confere(args: list[str]) -> int:
    p = achar_nota(args[0]) if args else None
    if p is None:
        raise SystemExit("uso: kb.py confere <nota>")
    b = p.read_bytes().decode("utf-8")
    eol = "\r\n" if "\r\n" in b else "\n"
    t = b.replace("\r\n", "\n")
    cab = t[: t.find("\n---", 4)]
    novo = re.sub(r"^status: .*$", "status: verified", cab, flags=re.M)
    for k, v in (
        ("last_verified", dt.date.today().isoformat()),
        ("verified_commit", git("rev-parse", "--short=7", "HEAD")),
    ):
        if re.search(rf"^{k}:", novo, re.M):
            novo = re.sub(rf"^{k}: .*$", f"{k}: {v}", novo, flags=re.M)
        else:
            novo += f"\n{k}: {v}"
    p.write_bytes((novo + t[len(cab) :]).replace("\n", eol).encode("utf-8"))
    print(f"{rel(p)}: verificada no commit {git('rev-parse', '--short=7', 'HEAD')}")
    return 0


COMANDOS = {
    "onde": cmd_onde,
    "modulo": cmd_modulo,
    "remote": cmd_remote,
    "decisao": cmd_decisao,
    "ativo": cmd_ativo,
    "mapa": cmd_mapa,
    "check": cmd_check,
    "velhas": cmd_velhas,
    "confere": cmd_confere,
}


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    if len(sys.argv) < 2 or sys.argv[1] not in COMANDOS:
        print(__doc__)
        return 1
    return COMANDOS[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    raise SystemExit(main())
