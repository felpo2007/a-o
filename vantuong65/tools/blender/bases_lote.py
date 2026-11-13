"""Lote da Tarefa C (bases iniciais): `bases.py <chave>` e depois `apresentar.py <chave>`.

Usa o `lote.py` (mesmos caminhos e logs em `_trabalho/<chave>/<etapa>.log`, mesma contagem de
Blenders abertos). Padrão: CPU (`--cpu`: Cycles com 4 threads), Blender em prioridade Idle, no
máximo 2 Blenders ao mesmo tempo; com `--gpu`, um Blender por vez (GPU livre). Estado em
`_trabalho/bases_estado.json`.

Uso:
    uv run python tools/blender/bases_lote.py                  # todas (EUA e VC)
    uv run python tools/blender/bases_lote.py --base US
    uv run python tools/blender/bases_lote.py --chaves us_bunker,vc_punji
    uv run python tools/blender/bases_lote.py --pular-feitos
    uv run python tools/blender/bases_lote.py --so-apresentar
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
sys.path.insert(0, str(AQUI))
import lote  # noqa: E402

TAREFA_C = [
    "us_range_target",
    "us_range_sign",
    "us_range_bench",
    "us_jerrycans",
    "us_generator",
    "us_conex",
    "us_fuel_drums",
    "us_water_trailer",
    "us_concertina",
    "us_helipad",
    "us_range_berm",
    "us_armor_revetment",
    "us_flagpole",
    "us_gate",
    "us_watchtower",
    "us_bunker",
    "us_tent_gp_medium",
    "us_command_tent",
    "us_tent_gp_large",
    "us_mess_tent",
    "us_motor_pool",
    "vc_punji",
    "vc_weapon_rack",
    "vc_range_target",
    "vc_range_rest",
    "vc_hammock",
    "vc_lean_to",
    "vc_hoang_cam_kitchen",
    "vc_car_shelter",
]
TEMPO_MAX_S = {"bases": 5400, "apresentar": 3600}
# prioridade Idle no Windows (o dono pode estar jogando no mesmo PC)
IDLE = getattr(subprocess, "IDLE_PRIORITY_CLASS", 0)


def gpu_livre(cpu: bool) -> float:
    """Na GPU: espera qualquer outro Blender acabar (um render por vez na placa de 6 GB).
    Na CPU (sem GPU, pedido do coordenador): no máximo 2 Blenders ao mesmo tempo, cada um com 4
    threads e prioridade Idle. Com a espera de um por vez, o lote do outro agente emendava uma
    etapa na outra e este nunca pegava a vez."""
    t0 = time.time()
    if cpu:
        while lote.outros_blender() >= 2:
            time.sleep(0.25)
    else:
        # GPU livre = nenhum Blender com contexto na placa (nvidia-smi); Blender de outro agente
        # rodando só na CPU não ocupa a GPU. No máximo 3 Blenders abertos ao mesmo tempo.
        while blender_na_gpu() or lote.outros_blender() >= 3:
            time.sleep(0.5)
    return round(time.time() - t0, 1)


def blender_na_gpu() -> int:
    """Quantos blender.exe têm contexto na GPU (nvidia-smi); sem nvidia-smi, conta todos."""
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-compute-apps=pid,process_name", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return lote.outros_blender()
    return sum(1 for ln in r.stdout.splitlines() if "blender" in ln.lower())


def rodar(etapa: str, chave: str, extra: list[str], idle: bool = True) -> dict:
    """Como `lote.rodar`; com `idle`, o Blender nasce em prioridade Idle (modo CPU)."""
    log = lote.TRABALHO / chave / f"{etapa}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    cmd = [lote.BLENDER, "-b", "--factory-startup", "-P", str(AQUI / f"{etapa}.py"), "--", chave]
    cmd += extra
    t0 = time.time()
    with log.open("w", encoding="utf-8", errors="replace") as f:
        p = subprocess.Popen(
            cmd,
            stdout=f,
            stderr=subprocess.STDOUT,
            cwd=lote.RAIZ,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            creationflags=IDLE if idle else 0,
        )
        try:
            rc = p.wait(timeout=TEMPO_MAX_S[etapa])
            estado = "ok" if rc == 0 else f"erro {rc}"
        except subprocess.TimeoutExpired:
            p.kill()
            estado = f"passou de {TEMPO_MAX_S[etapa]} s"
    texto = log.read_text("utf-8", errors="replace")
    if estado == "ok" and "[VT65] ok" not in texto:
        estado = "erro (sem linha [VT65] ok)"
    fim = [ln for ln in texto.splitlines() if ln.strip()][-6:]
    return {"etapa": etapa, "estado": estado, "tempo_s": round(time.time() - t0, 1), "fim": fim}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", choices=["US", "VC"], default=None)
    ap.add_argument("--chaves", default="")
    ap.add_argument("--pular-feitos", action="store_true")
    ap.add_argument("--so-apresentar", action="store_true")
    ap.add_argument("--amostras", default="")
    ap.add_argument(
        "--sufixo", default="", help="estado em bases_estado<sufixo>.json (filas paralelas)"
    )
    ap.add_argument("--gpu", action="store_true", help="usar a GPU (padrão: CPU, 4 threads)")
    ap.add_argument(
        "--cpu-livre",
        action="store_true",
        help="CPU com todas as threads, prioridade normal (a GPU não roda com o driver atual)",
    )
    a = ap.parse_args()
    dispositivo = [] if a.gpu else (["--cpu-todos"] if a.cpu_livre else ["--cpu"])
    fila = list(TAREFA_C)
    if a.base:
        fila = [k for k in fila if k.startswith(a.base.lower() + "_")]
    if a.chaves:
        quero = a.chaves.split(",")
        fila = [k for k in quero if k in TAREFA_C]
    estado_arq = lote.TRABALHO / f"bases_estado{a.sufixo}.json"
    lote.TRABALHO.mkdir(parents=True, exist_ok=True)
    estado = json.loads(estado_arq.read_text("utf-8")) if estado_arq.is_file() else {}
    for chave in fila:
        if a.pular_feitos and (lote.SAIDA / chave / "comparacao.png").is_file():
            print(f"[bases] {chave}: já feito, pulando", flush=True)
            continue
        reg = {"inicio": time.strftime("%Y-%m-%d %H:%M:%S"), "etapas": []}
        ok = True
        etapas = [] if a.so_apresentar else [("bases", dispositivo)]
        amostras = a.amostras or ("64" if a.gpu else "24")
        etapas.append(("apresentar", ["--amostras", amostras, *dispositivo]))
        for etapa, extra in etapas:
            espera = 0.0 if a.cpu_livre else gpu_livre(not a.gpu)
            if espera > 1:
                print(f"[bases] {chave}: esperou {espera} s outro Blender acabar", flush=True)
            r = rodar(etapa, chave, extra, idle=not (a.gpu or a.cpu_livre))
            reg["etapas"].append(r)
            ok = r["estado"] == "ok"
            print(f"[bases] {chave}: {etapa} {r['estado']} em {r['tempo_s']} s", flush=True)
            if not ok:
                for ln in r["fim"]:
                    print(f"    {ln}", flush=True)
                break
        reg["estado"] = "ok" if ok else "pulado"
        estado[chave] = reg
        estado_arq.write_text(json.dumps(estado, ensure_ascii=False, indent=1) + "\n", "utf-8")
    falhas = [k for k in fila if estado.get(k, {}).get("estado") != "ok"]
    print(f"[bases] fim; com falha: {falhas or 'nenhuma'}", flush=True)
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
