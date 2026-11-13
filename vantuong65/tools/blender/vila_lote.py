"""Lote das casas da vila: `vila.py <chave>` (modelagem, bake e GLB) e `vila.py <chave> --previa`,
uma casa por vez. Roda FORA do Blender (só a biblioteca padrão).

Com VT65_CPU=1 o Cycles fica na CPU (4 linhas, `comum.usar_gpu`) e o Blender roda em prioridade
ociosa (o dono jogando no mesmo PC). Sem ela, GPU e prioridade normal. Não espera os Blender de
outras tarefas (elas usam a mesma pasta, com chaves próprias). Log em
`assets/blender/_trabalho/<chave>/vila.log` e `previa.log`; estado em `_trabalho/vila_estado.json`.

Uso:
    uv run python tools/blender/vila_lote.py                 # as 10 casas
    uv run python tools/blender/vila_lote.py --chaves vila_casa_01,vila_casa_02
    uv run python tools/blender/vila_lote.py --so-previa
    uv run python tools/blender/vila_lote.py --pular-feitos
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
SAIDA = RAIZ / "assets" / "blender"
TRABALHO = SAIDA / "_trabalho"
BLENDER = os.environ.get(
    "VT65_BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe"
)
CASAS = [f"vila_casa_{i:02d}" for i in range(1, 11)]


def rodar(chave: str, extra: list[str], nome_log: str, limite: int) -> dict:
    log = TRABALHO / chave / nome_log
    log.parent.mkdir(parents=True, exist_ok=True)
    cmd = [BLENDER, "-b", "--factory-startup", "-P", str(AQUI / "vila.py"), "--", chave, *extra]
    cpu = os.environ.get("VT65_CPU", "") not in ("", "0")
    ocioso = os.environ.get("VT65_IDLE", "") not in ("", "0")  # dono jogando: prioridade ociosa
    flags = 0x00000040 if (ocioso and os.name == "nt") else 0  # IDLE_PRIORITY_CLASS
    t0 = time.time()
    with log.open("w", encoding="utf-8", errors="replace") as f:
        try:
            r = subprocess.run(
                cmd,
                stdout=f,
                stderr=subprocess.STDOUT,
                timeout=limite * (6 if cpu else 1),
                cwd=RAIZ,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                creationflags=flags,
            )
            estado = "ok" if r.returncode == 0 else f"erro {r.returncode}"
        except subprocess.TimeoutExpired:
            estado = "passou do tempo"
    texto = log.read_text("utf-8", errors="replace")
    if estado == "ok" and "[VT65] ok" not in texto:
        estado = "erro (sem linha [VT65] ok)"
    fim = [ln for ln in texto.splitlines() if ln.strip()][-6:]
    return {"estado": estado, "tempo_s": round(time.time() - t0, 1), "fim": fim}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--chaves", default="")
    ap.add_argument("--so-previa", action="store_true")
    ap.add_argument("--sem-previa", action="store_true")
    ap.add_argument("--pular-feitos", action="store_true")
    a = ap.parse_args()
    fila = a.chaves.split(",") if a.chaves else CASAS
    arq = TRABALHO / "vila_estado.json"
    estado = json.loads(arq.read_text("utf-8")) if arq.is_file() else {}
    for chave in fila:
        if a.pular_feitos and (SAIDA / chave / "previa.png").is_file():
            print(f"[vila] {chave}: já feito", flush=True)
            continue
        reg = {"inicio": time.strftime("%Y-%m-%d %H:%M:%S")}
        ok = True
        if not a.so_previa:
            r = rodar(chave, [], "vila.log", 3600)
            reg["vila"] = r
            ok = r["estado"] == "ok"
            print(f"[vila] {chave}: bake {r['estado']} em {r['tempo_s']} s", flush=True)
        if ok and not a.sem_previa:
            r = rodar(chave, ["--previa"], "previa.log", 1200)
            reg["previa"] = r
            ok = r["estado"] == "ok"
            print(f"[vila] {chave}: prévia {r['estado']} em {r['tempo_s']} s", flush=True)
        if not ok:
            for k in ("vila", "previa"):
                for ln in reg.get(k, {}).get("fim", []):
                    print(f"    {ln}", flush=True)
        reg["estado"] = "ok" if ok else "falhou"
        estado[chave] = reg
        arq.write_text(json.dumps(estado, ensure_ascii=False, indent=1) + "\n", "utf-8")
    falhas = [k for k in fila if estado.get(k, {}).get("estado") != "ok"]
    print(f"[vila] fim; com falha: {falhas or 'nenhuma'}", flush=True)
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
