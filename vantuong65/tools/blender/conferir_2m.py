"""Confere o soldado de 2,0 m nos veículos já exportados (sem render nem bake: só raios na malha).

Para cada olho do ART novo (`metricas.json`, `art_novo.eyes`): acha o teto acima do olho de hoje
(raio para cima) e compara com o topo da cabeça de um soldado de 2,0 m sentado no mesmo assento
(assento + 0,90 m de olho + 0,12 m de cabeça). Sem teto acima (cabeça fora da escotilha, carro
aberto) = céu aberto. Grava em `metricas.json` → `conferencia.soldado_2m.olhos`.

Uso: blender -b --factory-startup -P tools/blender/conferir_2m.py -- m48a3,ontos,...
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402

# altura do assento (m, do chão) onde o olho é de alguém sentado num banco do modelo
ASSENTOS_Z = {
    "uh34d": {"driver": 2.40, "copilot": 2.40},
    "m151": {"driver": 0.77, "passenger": 0.77},
    "m35": {"driver": 1.55, "passenger": 1.55},
    "peugeot403": {"driver": 0.54, "passenger": 0.54},
}


def main() -> None:
    chaves = C.argumentos()[0].split(",")
    for chave in chaves:
        pasta = C.SAIDA / chave
        met = json.loads((pasta / "metricas.json").read_text("utf-8"))
        C.cena_vazia()
        obj = C.importar_glb(pasta / f"{chave}.glb")
        lo, hi = C.caixa(obj)
        centro = (lo + hi) / 2
        bvh = C.bvh_de(obj)
        olhos = {}
        for s, r in met["art_novo"].get("eyes", {}).items():
            p = Vector(
                (
                    centro[0] - r[0] * C.M_POR_STUD,
                    centro[1] + r[2] * C.M_POR_STUD,
                    centro[2] + r[1] * C.M_POR_STUD,
                )
            )
            z_ass = ASSENTOS_Z.get(chave, {}).get(s)
            cabeca = (z_ass + 0.90 + 0.12) if z_ass is not None else p.z + 0.11 + 0.12
            hit = bvh.ray_cast(p + Vector((0, 0, 0.005)), Vector((0, 0, 1)), 3.0)
            teto = hit[0].z if hit[0] is not None else None
            olhos[s] = {
                "assento_z_m": z_ass,
                "olho_de_hoje_z_m": round(p.z, 3),
                "olho_2m_z_m": round(cabeca - 0.12, 3),
                "teto_acima_z_m": round(teto, 3) if teto is not None else None,
                "folga_cabeca_ao_teto_m": round(teto - cabeca, 3) if teto is not None else None,
            }
        met["conferencia"]["soldado_2m"]["olhos"] = olhos
        (pasta / "metricas.json").write_text(
            json.dumps(met, ensure_ascii=False, indent=1) + "\n", "utf-8"
        )
        C.log(chave, olhos)
    C.log("ok", "conferir_2m")


if __name__ == "__main__":
    main()
