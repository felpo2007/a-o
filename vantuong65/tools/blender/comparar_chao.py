"""`comparar.py` com chão de terra com textura no lugar do chão liso marrom.

Para a touceira sem o disco marrom (`bambu_sem_disco.py`): no chão liso marrom do `comparar.py` o
disco que saiu e o chão se confundem. Mesma luz, câmera, ângulos e silhuetas do `comparar.py`.

Uso:
    blender -b --factory-startup -P tools/blender/comparar_chao.py -- <chave> [--amostras N]
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apresentar  # noqa: E402
import comparar  # noqa: E402

comparar.material_chao = apresentar.chao_leve

if __name__ == "__main__":
    comparar.main()
