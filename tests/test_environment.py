import sys

import pytest

from quantbr import envcheck


def test_python_version():
    assert sys.version_info >= (3, 11)


@pytest.mark.parametrize("module", sorted(envcheck.REQUIRED_MODULES))
def test_required_module_imports(module):
    __import__(module)


def test_run_checks_offline_all_required_ok():
    checks = envcheck.run_checks(network=False)
    failures = [c for c in checks if c.required and not c.ok]
    assert not failures, envcheck.format_checks(failures)


@pytest.mark.network
def test_network_sources_reachable():
    checks = envcheck.check_network()
    failures = [c for c in checks if not c.ok]
    assert not failures, envcheck.format_checks(failures)
