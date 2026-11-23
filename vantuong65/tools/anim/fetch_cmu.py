"""Baixa só as capturas da CMU que o soldado usa (ASF/AMC originais, um arquivo por tomada).

Fonte: CMU Graphics Lab Motion Capture Database, http://mocap.cs.cmu.edu
Licença (página inicial, conferida em 2026-11-11): "This dataset of motions is free for all uses."
"You may include this data in commercially-sold products, but you may not resell this data
directly, even in converted form." Agradecimento pedido: "The data used in this project was
obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217."
O site pede para não varrer o banco: aqui vai só a lista abaixo.

Destino: assets/mocap/cmu/ (fora do Git). Cada download é conferido contra o sha256 gravado em
tools/anim/cmu_fontes.json; um arquivo novo (sem sha256) é registrado nele. A origem (URL, data,
tamanho, sha256 e licença) também vai em assets/mocap/cmu/ORIGEM.json.

Uso: uv run python tools/anim/fetch_cmu.py
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
DESTINO = RAIZ / "assets" / "mocap" / "cmu"
FONTES = Path(__file__).resolve().parent / "cmu_fontes.json"
BASE = "http://mocap.cs.cmu.edu/subjects/"
UA = {"User-Agent": "vt65-asset-fetch/1.0"}
LICENCA = (
    "CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu): 'This dataset of motions is "
    "free for all uses.' 'You may include this data in commercially-sold products, but you may "
    "not resell this data directly, even in converted form.' Agradecimento: 'The data used in "
    "this project was obtained from mocap.cs.cmu.edu. The database was created with funding "
    "from NSF EIA-0196217.'"
)

# caminho no site -> para que serve (descrição da CMU entre aspas)
ARQUIVOS: dict[str, str] = {
    "35/35.asf": "esqueleto do sujeito 35",
    "35/35_01.amc": "andar: 'walk'",
    "35/35_17.amc": "trote: 'run/jog'",
    "09/09.asf": "esqueleto do sujeito 9",
    "09/09_01.amc": "corrida: 'run'",
    "77/77.asf": "esqueleto do sujeito 77 ('careful actions')",
    "77/77_03.amc": "parado alerta: 'ready stance'",
    "77/77_10.amc": "corrida cautelosa: 'careful run'",
    "77/77_16.amc": "deitar e levantar: 'laying down, getting up, careful ready pose'",
    "77/77_28.amc": "andar cauteloso: 'careful walk'",
    "77/77_29.amc": "andar abaixado: 'creeping walk'",
    "136/136.asf": "esqueleto do sujeito 136",
    "136/136_09.amc": "andar agachado: 'Walk Crouched'",
    "139/139.asf": "esqueleto do sujeito 139",
    "139/139_29.amc": "andar furtivo: 'Sneaking'",
    "140/140.asf": "esqueleto do sujeito 140",
    "140/140_01.amc": "de bruços no chão: 'Get Up Face Down'",
    "111/111.asf": "esqueleto do sujeito 111",
    "111/111_03.amc": "engatinhar: 'Crawling'",
    "143/143.asf": "esqueleto do sujeito 143",
    "143/143_22.amc": "arremesso por cima: 'Catch And Throw Football'",
    "143/143_01.amc": "candidato: 'Run'",
    "07/07.asf": "esqueleto do sujeito 7",
    "07/07_12.amc": "candidato: 'brisk walk'",
    "132/132.asf": "esqueleto do sujeito 132",
    "132/132_17.amc": "candidato: 'Walk Fast'",
    "127/127.asf": "esqueleto do sujeito 127",
    "127/127_03.amc": "candidato: 'Run'",
    "127/127_06.amc": "candidato: 'Run'",
    "141/141.asf": "esqueleto do sujeito 141",
    "141/141_01.amc": "candidato: 'Run'",
    "16/16.asf": "esqueleto do sujeito 16",
    "16/16_35.amc": "candidato: 'run/jog'",
    "77/77_02.amc": "candidato: 'standing'",
    "77/77_08.amc": "candidato: 'investigating thing on ground with two hands'",
}


def _get(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def _sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> None:
    DESTINO.mkdir(parents=True, exist_ok=True)
    fontes: dict[str, dict] = json.loads(FONTES.read_text("utf-8")) if FONTES.exists() else {}
    origem = []
    hoje = dt.date.today().isoformat()
    for rel, uso in ARQUIVOS.items():
        alvo = DESTINO / Path(rel).name
        url = BASE + rel
        esperado = fontes.get(rel, {}).get("sha256")
        dados = alvo.read_bytes() if alvo.exists() else b""
        if not dados or (esperado and _sha(dados) != esperado):
            dados = _get(url)
            alvo.write_bytes(dados)
            print("baixado", rel, len(dados), "bytes")
        sha = _sha(dados)
        if esperado and sha != esperado:
            raise SystemExit(f"sha256 diferente em {rel}: {sha} (esperado {esperado})")
        fontes[rel] = {"sha256": sha, "bytes": len(dados), "uso": uso}
        origem.append(
            {
                "url": url,
                "arquivo": alvo.name,
                "bytes": len(dados),
                "sha256": sha,
                "uso": uso,
                "conferido": hoje,
            }
        )
    FONTES.write_text(json.dumps(fontes, indent=1, ensure_ascii=False) + "\n", "utf-8")
    (DESTINO / "ORIGEM.json").write_text(
        json.dumps({"licenca": LICENCA, "arquivos": origem}, indent=1, ensure_ascii=False) + "\n",
        "utf-8",
    )
    print(len(origem), "arquivos em", DESTINO)


if __name__ == "__main__":
    main()
