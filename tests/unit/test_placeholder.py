"""Placeholder unit test to ensure CI passes during Phase 0.

This test file serves as a basic validation that the test infrastructure
is properly configured and working. It will be replaced with actual unit
tests in subsequent phases of the project.
"""

import pytest


@pytest.mark.unit
def test_placeholder():
    """Basic placeholder test to validate test infrastructure."""
    assert True, "Phase 0 test infrastructure working"


@pytest.mark.unit
def test_environment_setup(test_config):
    """Verify that test configuration fixture is working.

    Args:
        test_config: Test configuration fixture from conftest.py
    """
    assert test_config is not None
    assert test_config["environment"] == "test"
    assert test_config["phase"] == "0"
    assert test_config["project_name"] == "oracul-platform"


@pytest.mark.unit
def test_mock_env_vars(mock_env_vars):
    """Verify that environment variable mocking works.

    Args:
        mock_env_vars: Environment variable mocking fixture from conftest.py
    """
    import os

    assert os.getenv("CLICKHOUSE_HOST") == "localhost"
    assert os.getenv("CLICKHOUSE_PORT") == "9000"
    assert os.getenv("KAFKA_BOOTSTRAP_SERVERS") == "localhost:9092"


@pytest.mark.unit
def test_project_structure(project_root):
    """Verify that key project directories exist.

    Args:
        project_root: Project root directory fixture from conftest.py
    """
    assert project_root.exists()
    assert (project_root / "api").exists()
    assert (project_root / "ingestion").exists()
    assert (project_root / "pipelines").exists()
    assert (project_root / "dwh").exists()
    assert (project_root / "config").exists()
    assert (project_root / "tests").exists()
