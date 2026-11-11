"""Textos da interface para traduzir (D-84).

Varre os .luau de src/ e junta os textos em português que podem ir para a tela. Não precisa ser
exato: um texto a mais no dicionário não muda nada (a tradução só mexe no que aparece na tela);
um a menos fica em português.

Dois grupos:
- texto de tela: o que o jogador lê. Tem de estar nos três dicionários (en, es, vi), nem que
  seja igual ao português (siglas e termos iguais entram como tradução idêntica).
- identificador de código: chave interna, nome de peça, modelo de arma, sigla. Fica em
  `tools/i18n/ignorar.json` ("exato" = textos; "regex" = padrões) e não conta como falta.

Saídas: `tools/i18n/fontes.json` (texto -> onde aparece) e `tools/i18n/telas.json` (só os textos de
tela; o teste `tests/luau/idiomas.luau` confere a cobertura por ele).

Uso (de vantuong65/):
    uv run python tools/i18n/extrai.py             # escreve fontes.json e telas.json e o relatório
    uv run python tools/i18n/extrai.py --faltam en # texto de tela que falta no dicionário en
    uv run python tools/i18n/extrai.py --novos     # lista o que nem é tela marcada nem ignorado
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
DATA = SRC / "ReplicatedStorage" / "Shared" / "LangData"
HERE = Path(__file__).resolve().parent
OUT = HERE / "fontes.json"
TELAS = HERE / "telas.json"
IGNORAR = HERE / "ignorar.json"
LANGS = ("en", "es", "vi")

# texto entre aspas duplas ou simples (com escapes)
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"|\'((?:[^\'\\\n]|\\.)*)\'')
# chamadas cujo argumento nunca é texto de tela
API = re.compile(
    r"(GetAttribute|SetAttribute|GetAttributeChangedSignal|FindFirstChild\w*|WaitForChild|"
    r"FindFirstAncestor\w*|Instance\.new|IsA|GetService|GetPropertyChangedSignal|require|"
    r"Net\.\w+|event|func|unreliable|BindAction\w*|UnbindAction|BindToRenderStep|"
    r"UnbindFromRenderStep|HasTag|AddTag|RemoveTag|GetTagged|Connect|fire|on)\s*\(\s*$"
)
SKIP_LINE = re.compile(r"\b(print|warn|error|assert)\s*\(")
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# módulos fora da interface cujas palavras soltas em minúsculas SÃO texto de tela (rumos, armas...)
LOWER_OK = ("Casualty.luau",)


def unescape(s: str) -> str:
    return (
        s.replace(r"\n", "\n")
        .replace(r"\"", '"')
        .replace(r"\'", "'")
        .replace(r"\t", "\t")
        .replace("\\\\", "\\")
    )


VIET = re.compile(r"[Ā-῿]")
UI_DIRS = ("src/StarterPlayer/", "src/ReplicatedFirst/")


def is_display(s: str, before: str, rel: str) -> bool:
    if len(re.findall(r"[A-Za-zÀ-ỹ]", s)) < 2:
        return False
    if "://" in s or s.startswith("rbxasset") or s.startswith("["):
        return False
    if re.match(r"^(wiki|pass|product|dev|key):", s) or s.startswith("./") or s.startswith("../"):
        return False
    words = s.split()
    # palavra solta em minúsculas sem acento: só nas telas (opção "alto"); nos módulos é chave
    # interna ("supply", "leader", "hold")
    if (
        len(words) == 1
        and re.fullmatch(r"[a-z]+", s)
        and not rel.startswith(UI_DIRS)
        and not rel.endswith(LOWER_OK)
    ):
        return False
    # nome vietnamita (Vạn Tường, TRUNG ĐOÀN 1): fica como está, a não ser que haja frase em volta
    if VIET.search(s):
        rest = [w for w in words if not VIET.search(w)]
        if len([w for w in rest if re.fullmatch(r"[A-Za-zÀ-ÿ]{3,}", w)]) < 2:
            return False
    if API.search(before):
        return False
    if re.search(r"\.Name\s*=\s*$|\bName\s*=\s*$", before):
        return False
    if IDENT.match(s):
        # identificador de código: CamelCase interno, com _ ou dígito, ou em inglês técnico
        if "_" in s or re.search(r"\d", s) or re.search(r"[a-z][A-Z]", s):
            return False
        if s[0].isupper() and len(s) > 1 and s[1:].islower() is False and not s.isupper():
            return False
    if re.fullmatch(r"[%.\w]+\.(png|jpg|ogg|mp3|glb|fbx|dds)", s):
        return False
    return True


def strip_comment(line: str) -> str:
    # tira o comentário fora de string (aproximado: '--' antes da primeira aspa ou depois da última)
    out, quote = [], None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < len(line):
                out.append(line[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
        else:
            if c in "\"'":
                quote = c
            elif line.startswith("--", i):
                break
            out.append(c)
        i += 1
    return "".join(out)


def extract() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in sorted(SRC.rglob("*.luau")):
        rel = path.relative_to(ROOT).as_posix()
        if "/VT65Build/" in rel or rel.endswith(("SelfTest.luau", "Profiler.luau", "/Lang.luau")):
            continue  # construção do mapa, autoteste (servidor, sem tela) e padrões do próprio Lang
        for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = strip_comment(raw)
            if not line.strip() or SKIP_LINE.search(line):
                continue
            for m in STRING.finditer(line):
                s = unescape(m.group(1) if m.group(1) is not None else m.group(2))
                if not is_display(s, line[: m.start()], rel):
                    continue
                keys = {s}
                core = s.strip().rstrip(":").strip()
                if core and core != s:
                    keys.add(core)  # "Conflito: " .. x -> "Conflito" (regra "Rótulo: valor")
                for k in keys:
                    if len(re.findall(r"[A-Za-zÀ-ỹ]", k)) >= 2:
                        found.setdefault(k, []).append(f"{rel}:{n}")
    return found


def load(lang: str) -> dict[str, str]:
    p = DATA / f"{lang}.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


class Ignorar:
    """Identificadores, siglas, modelos e nomes próprios que não são traduzidos."""

    def __init__(self) -> None:
        raw = json.loads(IGNORAR.read_text(encoding="utf-8")) if IGNORAR.exists() else {}
        self.exato = set(raw.get("exato", []))
        self.regex = [re.compile(r) for r in raw.get("regex", [])]

    def __call__(self, key: str) -> bool:
        return key in self.exato or any(r.search(key) for r in self.regex)


def telas(found: dict[str, list[str]]) -> list[str]:
    """Textos de tela: o que foi achado menos os identificadores marcados em ignorar.json."""
    skip = Ignorar()
    return sorted(k for k in found if not skip(k))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--faltam", help="idioma: lista o texto de tela que falta traduzir (JSON em stdout)"
    )
    ap.add_argument(
        "--novos", action="store_true", help="lista o que falta em algum idioma (sem filtro)"
    )
    args = ap.parse_args()
    found = extract()
    screen = telas(found)
    OUT.write_text(
        json.dumps(dict(sorted(found.items())), ensure_ascii=False, indent=1), encoding="utf-8"
    )
    TELAS.write_text(json.dumps(screen, ensure_ascii=False, indent=1), encoding="utf-8")
    if args.faltam:
        have = load(args.faltam)
        missing = [k for k in screen if k not in have]
        sys.stdout.reconfigure(encoding="utf-8")
        print(json.dumps(missing, ensure_ascii=False, indent=1))
        return 0
    if args.novos:
        sys.stdout.reconfigure(encoding="utf-8")
        dicts = {lang: load(lang) for lang in LANGS}
        skip = Ignorar()
        out = [k for k in sorted(found) if not skip(k) and any(k not in d for d in dicts.values())]
        print(json.dumps(out, ensure_ascii=False, indent=1))
        return 0
    print(f"{len(found)} textos achados em {OUT.relative_to(ROOT).as_posix()}")
    print(
        f"{len(screen)} textos de tela em {TELAS.relative_to(ROOT).as_posix()} "
        f"({len(found) - len(screen)} identificadores em ignorar.json)"
    )
    for lang in LANGS:
        have = load(lang)
        done = sum(1 for k in screen if k in have)
        print(
            f"  {lang}: {done}/{len(screen)} traduzidos ({100 * done / max(1, len(screen)):.1f}%)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
