"""Mapas retangulares (D-243): biblioteca de construções pelo mesmo caminho das casas da vila.

As receitas ficam nos módulos de `MODULOS` (cada um com `CASAS` e `receita_<chave>`).
Unidades: 1 unidade do Blender = 1 metro, Z para cima. As portas seguem o prompt: vão
livre de 1,40 x 2,50 m.

Uso (sempre com VT65_CPU=1):
    blender -b --factory-startup -P tools/blender/ret.py -- <chave> --so-montar
    blender -b --factory-startup -P tools/blender/ret.py -- <chave> --previa-alta [azimute]
    blender -b --factory-startup -P tools/blender/ret.py -- <chave>
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

PASTA = Path(__file__).resolve().parent
sys.path.insert(0, str(PASTA))
import comum as C  # noqa: E402
import exp  # noqa: E402
import vila  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
import vila_trim as VT  # noqa: E402

MODULOS = ("ret_piloto",)
PORTA_LARG = 1.40
PORTA_ALT = 2.50


def registrar() -> list[str]:
    # os módulos da expansão entram também: as receitas novas usam as peças deles
    exp.registrar()
    V.PORTA_LARG = PORTA_LARG
    V.PORTA_ALT = PORTA_ALT
    chaves: list[str] = []
    for nome in MODULOS:
        mod = importlib.import_module(nome)
        for chave, cfg in mod.CASAS.items():
            VC.CASAS[chave] = cfg
            setattr(VC, f"receita_{chave}", getattr(mod, f"receita_{chave}"))
            chaves.append(chave)
    VT.CASAS = (*VT.CASAS, *chaves)
    VC.LIMITE_PEGADA = 60.0  # os marcos são maiores que as casas da vila
    return chaves


def main() -> None:
    a = C.argumentos()
    chaves = registrar()
    if not a or a[0] not in chaves:
        raise SystemExit(f"chave desconhecida: {a[:1]}; há {chaves}")
    leve = "--so-montar" in a or "--previa-alta" in a
    _vaga = None if leve else exp.pegar_vaga()
    if "--trim" in a:
        VT.cmd_casa(a[0], "--sem-previa" not in a)
    else:
        vila.main()


if __name__ == "__main__":
    main()
