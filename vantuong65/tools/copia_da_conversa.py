"""Grava um texto que o Studio devolveu pelo MCP sem transcrever à mão (D-169).

O texto grande (a cópia do `tools/estatico_copiar.luau`) volta do `execute_luau` em pedaços que
começam com a linha "VT65COPIA <nome> <i>/<n>". O Claude Code guarda cada resultado de ferramenta
no registro da conversa (um .jsonl em ~/.claude/projects/<projeto>/). Este script acha os pedaços
nesse registro, junta na ordem e grava em <saida>, com LF e sem a quebra final. Confira depois com
a soma FNV-1a que o Studio calculou (CLAUDE.md, arte fixa).

Uso: uv run python tools/copia_da_conversa.py <registro.jsonl> <nome> <saida>
"""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Iterator
from pathlib import Path


def textos(o: object) -> Iterator[str]:
    if isinstance(o, str):
        yield o
    elif isinstance(o, dict):
        for v in o.values():
            yield from textos(v)
    elif isinstance(o, list):
        for v in o:
            yield from textos(v)


def pedacos(registro: Path, nome: str) -> str:
    padrao = re.compile(r"VT65COPIA " + re.escape(nome) + r" (\d+)/(\d+)\n")
    pecas: dict[int, str] = {}
    total = None
    for linha in registro.read_text("utf-8").splitlines():
        if "VT65COPIA " + nome not in linha:
            continue
        try:
            j = json.loads(linha)
        except json.JSONDecodeError:
            continue
        if j.get("type") != "user":  # o resultado da ferramenta, não o código que o pediu
            continue
        for t in textos(j):
            m = padrao.match(t)
            if m:
                i, n = int(m.group(1)), int(m.group(2))
                if total is not None and n != total:
                    pecas.clear()  # uma cópia nova com outro número de pedaços
                total = n
                pecas[i] = t[m.end() :]
    if total is None or sorted(pecas) != list(range(1, total + 1)):
        raise SystemExit(f"faltam pedaços de {nome}: tenho {sorted(pecas)} de {total}")
    return "\n".join(pecas[i] for i in range(1, total + 1))


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    registro, nome, saida = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    texto = pedacos(registro, nome)
    saida.write_bytes(texto.encode("utf-8"))
    print(f"{saida.name}: {len(texto.encode('utf-8'))} bytes, {texto.count(chr(10)) + 1} linhas")


if __name__ == "__main__":
    main()
