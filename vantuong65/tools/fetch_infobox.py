"""Baixa os parâmetros da infobox de artigos da Wikipédia (wikitext bruto) para citar números.

Uso: uv run python tools/fetch_infobox.py <saida.json> "Título 1" "Título 2" ...
Cada entrada guarda o texto cru do parâmetro (com {{convert}}) e a URL de origem em `_fonte`:
o número usado no jogo é conferido à mão contra esse texto e citado em DESIGN.md.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://en.wikipedia.org/w/api.php"
UA = {"User-Agent": "vantuong65-research/1.0 (game research; contact via repository)"}


def wikitexts(titles: list[str]) -> dict[str, str]:
    """Uma única requisição para todos os títulos (a API limita a frequência)."""
    q = urllib.parse.urlencode(
        {
            "action": "query",
            "prop": "revisions",
            "rvprop": "content",
            "rvslots": "main",
            "redirects": 1,
            "format": "json",
            "formatversion": 2,
            "titles": "|".join(titles),
        }
    )
    with urllib.request.urlopen(urllib.request.Request(f"{API}?{q}", headers=UA), timeout=60) as r:
        data = json.load(r)
    alias = {n["to"]: n["from"] for n in data["query"].get("redirects", [])}
    alias.update({n["to"]: n["from"] for n in data["query"].get("normalized", [])})
    out = {}
    for page in data["query"]["pages"]:
        if "revisions" in page:
            out[alias.get(page["title"], page["title"])] = page["revisions"][0]["slots"]["main"][
                "content"
            ]
    return out


def _template(text: str, start: int) -> str:
    depth, j = 0, start
    while j < len(text):
        if text.startswith("{{", j):
            depth += 1
            j += 2
            continue
        if text.startswith("}}", j):
            depth -= 1
            j += 2
            if depth == 0:
                break
            continue
        j += 1
    return text[start:j]


def infobox(text: str) -> dict[str, str]:
    """Parâmetros da infobox e, em aeronaves, do bloco {{Aircraft specs}}."""
    out: dict[str, str] = {}
    low = text.lower()
    for marker in ("{{infobox", "{{aircraft specs"):
        i = low.find(marker)
        while i >= 0:
            body = _template(text, i)
            pat = r"\n\s*\|\s*([\w ]+?)[ \t]*=[ \t]*(.*?)(?=\n\s*\||\n\}\}|$)"
            for m in re.finditer(pat, body, re.S):
                v = re.sub(r"<ref[^>]*/>|<ref[^>]*>.*?</ref>", "", m.group(2), flags=re.S).strip()
                if v and m.group(1).strip() not in out:
                    out[m.group(1).strip()] = v[:600]
            i = low.find(marker, i + len(body))
    return out


def main() -> None:
    dest = Path(sys.argv[1])
    res = json.loads(dest.read_text("utf-8")) if dest.exists() else {}
    texts = wikitexts(sys.argv[2:])
    for title in sys.argv[2:]:
        if title not in texts:
            print(title, "NÃO ENCONTRADO")
            continue
        box = infobox(texts[title])
        box["_fonte"] = "https://en.wikipedia.org/wiki/" + title.replace(" ", "_")
        res[title] = box
        print(title, len(box), "campos")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(res, ensure_ascii=False, indent=1), "utf-8")


if __name__ == "__main__":
    main()
