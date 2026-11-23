"""Base de conhecimento (tools/kb.py, D-244): leitura de notas, índice vivo e integridade."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("kb", ROOT / "tools" / "kb.py")
assert spec and spec.loader
kb = importlib.util.module_from_spec(spec)
sys.modules["kb"] = kb
spec.loader.exec_module(kb)


def test_frontmatter_le_campos_e_listas():
    t = "---\nstatus: verified\nsource_paths:\n  - src/a.luau\n  - tools/b.py\n---\n# X\n"
    fm = kb.frontmatter(t)
    assert fm["status"] == "verified"
    assert fm["source_paths"] == ["src/a.luau", "tools/b.py"]
    assert kb.frontmatter("# sem cabeçalho\n") == {}


def test_links_ignoram_ancora_e_rotulo():
    assert kb.links("[[Combate#Fluxo]] e [[Licoes|lições]]") == ["Combate", "Licoes"]


def test_segredo_e_detectado_e_caminho_nao():
    chave = "ROBLOX_API" + "_KEY=" + "x" * 12  # valor falso, montado por partes
    token = "A" * 56
    assert any(r.search(chave) for r in kb.SEGREDOS)
    assert any(r.search(f"valor {token} fim") for r in kb.SEGREDOS)
    limpo = "`src/ServerScriptService/Modules/CombatService.luau` na v146"
    assert not any(r.search(limpo) for r in kb.SEGREDOS)


def test_indice_vivo_acha_modulo_e_quem_usa():
    mods = {m.nome: m for m in kb.modulos()}
    combate = mods["CombatService"]
    assert "fire" in combate.api
    assert any(a.endswith("Weapons.luau") for a in combate.usa)
    assert any("BotService" in a for a in combate.usado)


def test_remote_mostra_os_dois_lados():
    assert kb.lista_remotes()["Combat_Fire"][0] == "Events"
    usos = kb.usos_remote("Combat_Fire", kb.modulos())
    assert any("CombatService" in a for a in usos["servidor escuta"])
    assert any("WeaponController" in a for a in usos["cliente envia"])


def test_mapa_le_o_projeto():
    p = kb.projeto_mapa("frente")
    assert (p["comp"], p["prof"]) == (700.0, 300.0)
    assert [s[0] for s in p["setores"]] == ["A", "B", "C", "D", "E"]


def test_base_sem_erros():
    erros, _avisos = kb.problemas()
    assert erros == []
