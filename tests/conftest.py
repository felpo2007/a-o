import os

import pytest

from quantbr.config import load_config


def pytest_collection_modifyitems(config, items):
    if os.environ.get("RUN_NETWORK_TESTS") == "1":
        return
    skip = pytest.mark.skip(reason="teste de rede: rode com RUN_NETWORK_TESTS=1")
    for item in items:
        if "network" in item.keywords:
            item.add_marker(skip)


@pytest.fixture(scope="session")
def cfg():
    return load_config()
