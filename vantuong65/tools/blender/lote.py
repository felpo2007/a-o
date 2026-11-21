"""Lote da linha de produção do Blender: refaz/cria cada asset e faz a comparação, um por vez.

Roda FORA do Blender (só a biblioteca padrão) e chama o Blender sem janela para cada etapa:
- Tarefa A (assets antigos do ForgeGUI): `refazer.py <chave>` e depois `comparar.py <chave>`;
- Tarefa B (assets novos do zero): `novos.py <chave>` e depois `comparar.py <chave>`.
Uma etapa por vez (a GPU do notebook é de 6 GB). Se uma etapa passar do tempo ou falhar, o lote
registra, pula a chave e segue. Estado em `assets/blender/_trabalho/lote_estado.json` e saída do
Blender em `assets/blender/_trabalho/<chave>/<etapa>.log`.

Uso:
    uv run python tools/blender/lote.py                # tudo (A e B)
    uv run python tools/blender/lote.py --tarefa A     # só os refeitos
    uv run python tools/blender/lote.py --chaves well,shrine
    uv run python tools/blender/lote.py --pular-feitos # pula o que já tem comparacao.png
    uv run python tools/blender/lote.py --so-comparar  # refaz só as imagens de comparação
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

# mesma ordem e chaves de refazer.ANTIGOS e novos.NOVOS (aqui sem bpy)
TAREFA_A = [
    "hut_thatch",
    "hut_veranda",
    "hut_kitchen",
    "house_tile",
    "granary",
    "well",
    "shrine",
    "grave_mound",
    "vc_bunker",
    "sandbags",
    "bamboo_fence",
    "trench_section",
    "tunnel_entrance",
    "spider_hole",
    "log_bridge",
    "rice_patch",
]
TAREFA_B = [
    "water_jar",
    "straw_stack",
    "grenade_m26",
    "grenade_stick",
    "smoke_m18",
    "ammo_crate",
    "rice_sack",
    "clay_lamp",
    "sandbag_wall",
    "conical_hat",
    "bamboo_clothesline",
]
# Tarefa V (veículos em partes, veiculos.py + veic_<chave>.py) e G (ghillie v2, ghillie2.py)
TAREFA_V = ["m48a3", "ontos", "lvtp5", "uh34d", "m151", "m35", "peugeot403"]
TAREFA_G = ["ghillie"]
TEMPO_MAX_S = {"refazer": 1500, "novos": 1800, "comparar": 900, "veiculos": 7200, "ghillie2": 3600}


def outros_blender() -> int:
    """Quantos blender.exe estão rodando agora (Windows: tasklist; fora dele, 0)."""
    if os.name != "nt":
        return 0
    r = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq blender.exe", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
    )
    return sum(1 for ln in r.stdout.splitlines() if ln.lower().startswith('"blender.exe"'))


def esperar_gpu(max_s: int | None = None) -> float:
    """Espera outro Blender (de outra tarefa) acabar: a GPU do notebook faz um render por vez.
    VT65_ESPERA_S muda o limite (padrão 1200 s): com vários agentes renderizando sem parar, a GPU
    nunca fica livre e o lote esperaria o limite inteiro antes de cada etapa."""
    if max_s is None:
        max_s = int(os.environ.get("VT65_ESPERA_S", "1200"))
    t0 = time.time()
    while outros_blender() and time.time() - t0 < max_s:
        time.sleep(5)
    return round(time.time() - t0, 1)


def rodar(etapa: str, chave: str, extra: list[str]) -> dict:
    """Uma etapa no Blender sem janela; devolve estado, tempo e as últimas linhas do log."""
    espera = esperar_gpu()
    if espera > 1:
        print(f"[lote] {chave}: esperou {espera} s outro Blender liberar a GPU", flush=True)
    log = TRABALHO / chave / f"{etapa}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        BLENDER,
        "-b",
        "--factory-startup",
        "-P",
        str(AQUI / f"{etapa}.py"),
        "--",
        chave,
        *extra,
    ]
    t0 = time.time()
    # VT65_CPU=1: o dono está usando a GPU (jogo aberto). Cycles só na CPU (comum.usar_gpu, 4
    # linhas) e o Blender em prioridade ociosa, para não pesar no jogo.
    cpu = os.environ.get("VT65_CPU", "") not in ("", "0")
    flags = 0x00000040 if (cpu and os.name == "nt") else 0  # IDLE_PRIORITY_CLASS
    limite = TEMPO_MAX_S[etapa] * (6 if cpu else 1)
    with log.open("w", encoding="utf-8", errors="replace") as f:
        try:
            r = subprocess.run(
                cmd,
                stdout=f,
                stderr=subprocess.STDOUT,
                timeout=limite,
                cwd=RAIZ,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                creationflags=flags,
            )
            estado = "ok" if r.returncode == 0 else f"erro {r.returncode}"
        except subprocess.TimeoutExpired:
            estado = f"passou de {limite} s"
    texto = log.read_text("utf-8", errors="replace")
    if estado == "ok" and "[VT65] ok" not in texto:
        estado = "erro (sem linha [VT65] ok)"
    fim = [ln for ln in texto.splitlines() if ln.strip()][-6:]
    return {"etapa": etapa, "estado": estado, "tempo_s": round(time.time() - t0, 1), "fim": fim}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tarefa", choices=["A", "B", "V", "G"], default=None)
    ap.add_argument("--chaves", default="")
    ap.add_argument("--pular-feitos", action="store_true")
    ap.add_argument("--so-comparar", action="store_true")
    ap.add_argument("--sem-comparar", action="store_true")
    ap.add_argument("--extra", default="", help="argumentos a mais para a etapa (com espaço)")
    ap.add_argument("--amostras", default="64")
    a = ap.parse_args()
    fila = []
    if a.tarefa in (None, "A"):
        fila += [("refazer", k) for k in TAREFA_A]
    if a.tarefa in (None, "B"):
        fila += [("novos", k) for k in TAREFA_B]
    if a.tarefa in (None, "V"):
        fila += [("veiculos", k) for k in TAREFA_V]
    if a.tarefa in (None, "G"):
        fila += [("ghillie2", k) for k in TAREFA_G]
    if a.chaves:
        quero = set(a.chaves.split(","))
        fila = [(e, k) for e, k in fila if k in quero]
    estado_arq = TRABALHO / "lote_estado.json"
    TRABALHO.mkdir(parents=True, exist_ok=True)
    estado = json.loads(estado_arq.read_text("utf-8")) if estado_arq.is_file() else {}
    for etapa, chave in fila:
        if a.pular_feitos and (SAIDA / chave / "comparacao.png").is_file():
            print(f"[lote] {chave}: já feito, pulando", flush=True)
            continue
        print(f"[lote] {chave}: {etapa}...", flush=True)
        reg = {"inicio": time.strftime("%Y-%m-%d %H:%M:%S"), "etapas": []}
        ok = True
        if not a.so_comparar:
            r = rodar(etapa, chave, a.extra.split())
            reg["etapas"].append(r)
            ok = r["estado"] == "ok"
            print(f"[lote] {chave}: {etapa} {r['estado']} em {r['tempo_s']} s", flush=True)
        if ok and not a.sem_comparar:
            amostras = a.amostras
            if os.environ.get("VT65_CPU", "") not in ("", "0") and a.amostras == "64":
                amostras = "24"  # na CPU: menos amostras, o OIDN limpa o ruído
            r = rodar("comparar", chave, ["--amostras", amostras])
            reg["etapas"].append(r)
            ok = r["estado"] == "ok"
            print(f"[lote] {chave}: comparar {r['estado']} em {r['tempo_s']} s", flush=True)
        if not ok:
            for ln in reg["etapas"][-1]["fim"]:
                print(f"    {ln}", flush=True)
        reg["estado"] = "ok" if ok else "pulado"
        estado[chave] = reg
        estado_arq.write_text(json.dumps(estado, ensure_ascii=False, indent=1) + "\n", "utf-8")
    falhas = [k for k, v in estado.items() if v.get("estado") != "ok"]
    print(f"[lote] fim; com falha: {falhas or 'nenhuma'}", flush=True)
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
