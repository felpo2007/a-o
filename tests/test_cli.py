import subprocess
import sys

from quantbr.paths import ROOT


def _run(*args):
    return subprocess.run([sys.executable, str(ROOT / "run.py"), *args],
                          capture_output=True, text=True, cwd=ROOT, timeout=300)


def test_help():
    r = _run("--help")
    assert r.returncode == 0
    assert "--universe" in r.stdout


def test_check_env_offline():
    r = _run("--check-env")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Ambiente OK." in r.stdout


def test_universe_not_yet_implemented_exits_cleanly():
    # Até a Etapa 1, o pipeline deve falhar de forma explícita, sem gerar nada.
    r = _run("--universe", "mvp")
    assert r.returncode == 2
    assert "Etapa 1" in r.stdout
