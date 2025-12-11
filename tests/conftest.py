"""Shared test fixtures for pytest.

This module provides common fixtures used across all test suites in the Oracul platform.
"""

import os
from pathlib import Path
from typing import Dict

import pytest


@pytest.fixture(scope="session")
def project_root() -> Path:
    """Return the project root directory."""
    return Path(__file__).parent.parent


@pytest.fixture(scope="session")
def test_config() -> Dict[str, str]:
    """Provide test configuration.

    Returns:
        Dictionary containing test environment configuration.
    """
    return {
        "environment": "test",
        "phase": "0",
        "project_name": "oracul-platform",
    }


@pytest.fixture(scope="session")
def test_data_dir(project_root: Path) -> Path:
    """Return the test data directory.

    Args:
        project_root: The project root directory fixture.

    Returns:
        Path to the test data directory.
    """
    test_data = project_root / "tests" / "data"
    test_data.mkdir(parents=True, exist_ok=True)
    return test_data


@pytest.fixture
def mock_env_vars(monkeypatch) -> None:
    """Set up mock environment variables for testing.

    Args:
        monkeypatch: pytest monkeypatch fixture for modifying environment.
    """
    test_env = {
        "CLICKHOUSE_HOST": "localhost",
        "CLICKHOUSE_PORT": "9000",
        "CLICKHOUSE_DATABASE": "oracul_test",
        "CLICKHOUSE_USER": "test_user",
        "CLICKHOUSE_PASSWORD": "test_password",
        "KAFKA_BOOTSTRAP_SERVERS": "localhost:9092",
        "ALCHEMY_ETH_MAINNET_URL": "https://eth-mainnet.test.com/v2/test_key",
        "LOG_LEVEL": "DEBUG",
    }
    for key, value in test_env.items():
        monkeypatch.setenv(key, value)


@pytest.fixture(autouse=True)
def reset_environment():
    """Reset environment variables after each test to avoid cross-test contamination."""
    original_env = os.environ.copy()
    yield
    os.environ.clear()
    os.environ.update(original_env)
