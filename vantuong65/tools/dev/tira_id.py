"""Tira chaves do roblox_ids.json sem reformatar o resto, para o upload-assets subir o modelo novo.

uv run python tools/dev/tira_id.py Models.ret_x Models.ret_y
"""

import json
import re
import sys
from pathlib import Path

p = Path(__file__).resolve().parents[2] / "assets" / "roblox_ids.json"
b = p.read_bytes().decode("utf-8")
for chave in sys.argv[1:]:
    novo, n = re.subn(r'[ \t]*"' + re.escape(chave) + r'"\s*:\s*"?\d+"?,?\r?\n', "", b)
    if n != 1:
        raise SystemExit(f"{chave}: {n} linhas")
    b = novo
b = re.sub(r",(\r?\n\s*\})", r"\1", b)
json.loads(b)
p.write_bytes(b.encode("utf-8"))
print("ok")
