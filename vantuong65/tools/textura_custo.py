"""Custo teórico de textura dos modelos do jogo (D-168), para escolher o alvo da trim sheet.

Lê os GLBs que sobem (`assets/upload_plan.json`, só os que têm ID em `assets/roblox_ids.json` e
estão no `ArtBudget`) e soma, por modelo e por grupo, o tamanho das imagens: o Roblox reduz toda
imagem a no máximo 1024, e a conta usa 4 bytes por pixel mais 1/3 dos mipmaps, sem a compressão do
Roblox.
É um número para comparar modelos entre si; o custo de verdade só se mede no Studio (D-165: o
Roblox carrega de longe em resolução baixa).

Uso: uv run python tools/textura_custo.py [--top N]
"""

from __future__ import annotations

import argparse
import json
import re
import struct
from collections import defaultdict
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
TETO = 1024  # o Roblox reduz a imagem enviada a no máximo 1024 x 1024
VEICULOS = ("lvtp5", "m151", "m35", "m48a3", "ontos", "peugeot403", "uh34d")


def tamanho_png(d: bytes) -> tuple[int, int]:
    w, h = struct.unpack(">II", d[16:24])
    return w, h


def tamanho_jpg(d: bytes) -> tuple[int, int]:
    i = 2
    while i + 9 <= len(d):
        if d[i] != 0xFF:
            i += 1
            continue
        if d[i + 1] in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", d[i + 5 : i + 9])
            return w, h
        i += 2 + struct.unpack(">H", d[i + 2 : i + 4])[0]
    return 0, 0


def imagens(glb: Path) -> list[tuple[int, int]]:
    b = glb.read_bytes()
    n = struct.unpack_from("<I", b, 12)[0]
    js = json.loads(b[20 : 20 + n])
    base = 20 + n + 8
    out = []
    for im in js.get("images", []):
        bv = js["bufferViews"][im["bufferView"]]
        ini = base + bv.get("byteOffset", 0)
        d = b[ini : ini + bv["byteLength"]]
        out.append(tamanho_png(d) if d[:8] == b"\x89PNG\r\n\x1a\n" else tamanho_jpg(d))
    return out


def mb(ims: list[tuple[int, int]]) -> float:
    return sum(min(w, TETO) * min(h, TETO) * 4 * 4 / 3 for w, h in ims) / 2**20


def grupo(nome: str) -> str:
    if nome.startswith("us_"):
        return "base dos EUA"
    if nome.startswith("vc_"):
        return "base do VC"
    if nome.startswith("vila_"):
        return "casas da vila"
    if nome.split("_")[0] in VEICULOS:
        return "veículos"
    if nome.startswith("ph_"):
        return "árvores da mata (Poly Haven)"
    return "outros"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=25)
    a = ap.parse_args()
    plano = json.loads((RAIZ / "assets" / "upload_plan.json").read_text("utf-8"))
    ids = json.loads((RAIZ / "assets" / "roblox_ids.json").read_text("utf-8"))
    ab = (RAIZ / "src" / "ServerScriptService" / "Modules" / "ArtBudget.luau").read_text("utf-8")
    usados = set(re.findall(r"^\t([a-z0-9_]+) = \"", ab, re.M))
    linhas = []
    grupos: dict[str, list[float]] = defaultdict(lambda: [0, 0, 0.0])
    for it in plano:
        chave, arq = it["key"], it.get("file", "")
        nome = chave.removeprefix("Models.")
        if chave == nome or not arq.endswith(".glb") or chave not in ids or nome not in usados:
            continue
        glb = RAIZ / arq
        if not glb.exists():
            continue
        ims = imagens(glb)
        g = grupo(nome)
        grupos[g][0] += 1
        grupos[g][1] += len(ims)
        grupos[g][2] += mb(ims)
        linhas.append((mb(ims), nome, len(ims), g))
    print(f"{len(usados)} modelos no ArtBudget; {len(linhas)} GLBs achados")
    print("Grupo: modelos, texturas, MB teóricos (RGBA + mips, teto 1024, sem compressão)")
    for g, (n, ni, total) in sorted(grupos.items(), key=lambda x: -x[1][2]):
        print(f"  {g}: {n:.0f} modelos, {ni:.0f} texturas, {total:.0f} MB")
    print(f"Os {a.top} maiores:")
    for custo, nome, ni, g in sorted(linhas, reverse=True)[: a.top]:
        print(f"  {custo:5.1f} MB  {nome} ({ni} texturas) [{g}]")


if __name__ == "__main__":
    main()
