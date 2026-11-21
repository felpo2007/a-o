"""Expansão da Vila e do Arrozal (D-232): construções novas pelo mesmo caminho das casas da vila.

As receitas ficam em `exp_vila.py` e `exp_arrozal.py` (cada uma com `CASAS` e `receita_<chave>`).
Este arquivo as registra no catálogo de `vila_casas` e chama `vila.py` e `vila_trim.py`, sem mudar
nada das 10 casas que já existem.

Uso (sempre com VT65_CPU=1):
    blender -b --factory-startup -P tools/blender/exp.py -- <chave> --so-montar
    blender -b --factory-startup -P tools/blender/exp.py -- <chave> --previa-alta [azimute]
    blender -b --factory-startup -P tools/blender/exp.py -- <chave>
    blender -b --factory-startup -P tools/blender/exp.py -- <chave> --trim [--sem-previa]

Sem bandeira: assa os atlas e grava `assets/blender/<chave>/<chave>.glb`. `--trim` passa o grupo
Casa para as folhas comuns (`<chave>_trim.glb`, o que sobe) e faz a prévia em
`assets/blender/trim_vila/previa_<chave>.png`. No máximo 2 bakes ao mesmo tempo no PC (`VAGAS`).
"""

from __future__ import annotations

import importlib
import sys
import time
from pathlib import Path

PASTA = Path(__file__).resolve().parent
sys.path.insert(0, str(PASTA))
import comum as C  # noqa: E402
import vila  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_trim as VT  # noqa: E402

MODULOS = ("exp_vila", "exp_arrozal", "exp_sobrado")
VAGAS = 2


def registrar() -> list[str]:
    chaves: list[str] = []
    for nome in MODULOS:
        if not (PASTA / f"{nome}.py").is_file():
            continue
        mod = importlib.import_module(nome)
        for chave, cfg in mod.CASAS.items():
            VC.CASAS[chave] = cfg
            setattr(VC, f"receita_{chave}", getattr(mod, f"receita_{chave}"))
            chaves.append(chave)
    VT.CASAS = (*VT.CASAS, *chaves)
    VT.TESTES = C.TRABALHO / "exp_previas"
    return chaves


def pegar_vaga():
    """Trava de arquivo: o Windows solta sozinha se o processo morrer."""
    import msvcrt

    C.TRABALHO.mkdir(parents=True, exist_ok=True)
    while True:
        for i in range(VAGAS):
            f = open(C.TRABALHO / f"exp_vaga_{i}.lock", "a+b")  # noqa: SIM115
            try:
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
                return f
            except OSError:
                f.close()
        time.sleep(5)


def main() -> None:
    a = C.argumentos()
    chaves = registrar()
    if not a or a[0] not in chaves:
        raise SystemExit(f"chave desconhecida: {a[:1]}; há {chaves}")
    leve = "--so-montar" in a or "--previa-alta" in a
    _vaga = None if leve else pegar_vaga()
    if "--trim" in a:
        VT.cmd_casa(a[0], "--sem-previa" not in a)
    else:
        vila.main()


if __name__ == "__main__":
    main()
