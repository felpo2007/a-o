"""Junta traduções novas aos dicionários de idioma (D-84).

Uso (de vantuong65/):
    uv run python tools/i18n/mescla.py novas.json

`novas.json` = {"en": {"pt": "tradução"}, "es": {...}, "vi": {...}}. Chave nova vai para o fim
do dicionário, na ordem alfabética; chave que já existe com outra tradução é recusada (a menos
que `--troca`). Antes de gravar confere que os especificadores (%d, %s, %.1f, {a}) são os mesmos
do português.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[2] / "src" / "ReplicatedStorage" / "Shared" / "LangData"
SPEC = re.compile(r"%%|(%[-+#0]*\d*\.?\d*[dsfiqxg])|(\{[A-Za-z]+\})")


def specs(s: str) -> list[str]:
    return [m.group(0)[-1] if m.group(1) else "{}" for m in SPEC.finditer(s) if m.group(0) != "%%"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("arquivo")
    ap.add_argument(
        "--troca", action="store_true", help="troca a tradução de chaves que já existem"
    )
    args = ap.parse_args()
    novas = json.loads(Path(args.arquivo).read_text(encoding="utf-8"))
    bad = 0
    pronto: dict[Path, dict[str, str]] = {}
    for lang, add in novas.items():
        path = DATA / f"{lang}.json"
        cur: dict[str, str] = json.loads(path.read_text(encoding="utf-8"))
        fresh = {}
        for pt, tr in add.items():
            if specs(pt) != specs(tr):
                print(f"{lang}: especificadores diferentes: {pt!r} -> {tr!r}")
                bad += 1
            elif pt in cur and cur[pt] != tr and not args.troca:
                print(f"{lang}: já existe com outra tradução: {pt!r}: {cur[pt]!r} (novo {tr!r})")
                bad += 1
            elif pt not in cur:
                fresh[pt] = tr
            elif args.troca:
                cur[pt] = tr
        cur.update(dict(sorted(fresh.items())))
        pronto[path] = cur
        print(f"{lang}: {len(fresh)} novas")
    if bad:
        print("nada gravado")
        return 1
    for path, cur in pronto.items():
        path.write_text(json.dumps(cur, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
