"""Garante que o repositório segue a estrutura e as regras de segurança da SPEC."""

import re
import subprocess

import pytest

from quantbr.paths import ROOT

REQUIRED_FILES = ["README.md", "CLAUDE.md", "SPEC.md", "PROGRESS.md", "ASSUMPTIONS.md", "pyproject.toml",
                  "uv.lock", ".python-version", ".gitignore", ".env.example", "run.py",
                  "config/default.toml"]

# Mapeamento SPEC -> código (ver ASSUMPTIONS.md, decisão D1)
CODE_PACKAGES = ["data", "strategies", "backtest", "validation", "models/googl", "site", "live"]
TOP_LEVEL_DIRS = ["data", "models/googl", "site", "live", "tests", "config"]


@pytest.mark.parametrize("name", REQUIRED_FILES)
def test_required_file_exists(name):
    assert (ROOT / name).is_file(), name


@pytest.mark.parametrize("pkg", CODE_PACKAGES)
def test_code_package_exists(pkg):
    assert (ROOT / "src" / "quantbr" / pkg / "__init__.py").is_file()


@pytest.mark.parametrize("d", TOP_LEVEL_DIRS)
def test_top_level_dir_exists(d):
    assert (ROOT / d).is_dir()


def test_env_is_gitignored():
    lines = (ROOT / ".gitignore").read_text().splitlines()
    assert ".env" in lines


def test_env_ignored_by_git():
    r = subprocess.run(["git", "check-ignore", "-q", ".env"], cwd=ROOT)
    assert r.returncode == 0, ".env não está sendo ignorado pelo git"


def test_env_example_has_no_values_for_secrets():
    secret_keys = ("TOKEN", "SECRET", "PASSWORD", "API_KEY")
    for line in (ROOT / ".env.example").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            if any(s in key for s in secret_keys):
                assert value.strip() == "", f"{key} não pode ter valor no .env.example"


SECRET_PATTERNS = [
    re.compile(r"(?i)(api[_-]?key|secret|token|password)\s*=\s*['\"][A-Za-z0-9_\-]{12,}['\"]"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
]


def test_no_hardcoded_secrets_in_code():
    files = list((ROOT / "src").rglob("*.py")) + [ROOT / "run.py"]
    for f in files:
        text = f.read_text()
        for pat in SECRET_PATTERNS:
            assert not pat.search(text), f"possível segredo em {f.relative_to(ROOT)}"


def test_readme_explains_install():
    readme = (ROOT / "README.md").read_text().lower()
    for must in ("instala", "uv sync", "pytest", ".env"):
        assert must in readme, f"README deve mencionar '{must}'"
