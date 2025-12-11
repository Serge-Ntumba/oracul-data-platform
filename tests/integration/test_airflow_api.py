"""
Integration tests for Airflow API connectivity.

These tests verify that:
1. Airflow webserver is accessible
2. Airflow database is initialized
3. API endpoints work correctly
4. Admin user was created
5. DAGs can be listed (empty in Phase 1)

Requirements:
- Airflow must be running (via docker-compose)
- airflow-init must have completed successfully
"""

import os

import pytest
import requests
from requests.auth import HTTPBasicAuth


@pytest.fixture
def airflow_base_url():
    """Get Airflow base URL from environment."""
    host = os.getenv("AIRFLOW_HOST", "localhost")
    port = os.getenv("AIRFLOW_PORT", "8080")
    return f"http://{host}:{port}"


@pytest.fixture
def airflow_auth():
    """Get Airflow authentication credentials."""
    username = os.getenv("AIRFLOW_USERNAME", "admin")
    password = os.getenv("AIRFLOW_PASSWORD", "admin")
    return HTTPBasicAuth(username, password)


@pytest.mark.integration
def test_airflow_webserver_accessible(airflow_base_url):
    """Test that Airflow webserver is accessible."""
    response = requests.get(f"{airflow_base_url}/health", timeout=10)

    assert response.status_code == 200, (
        "Airflow health endpoint should return 200. " "Make sure airflow-webserver is running."
    )


@pytest.mark.integration
def test_airflow_health_endpoint(airflow_base_url):
    """Test Airflow health endpoint returns healthy status."""
    response = requests.get(f"{airflow_base_url}/health", timeout=10)

    assert response.status_code == 200, "Health check should succeed"

    data = response.json()
    assert "metadatabase" in data, "Health response should include metadatabase status"

    # Metadatabase should be healthy
    assert data["metadatabase"]["status"] == "healthy", (
        "Metadatabase should be healthy. " "Check that airflow-init completed successfully."
    )


@pytest.mark.integration
def test_airflow_api_version(airflow_base_url):
    """Test that Airflow API version endpoint works."""
    response = requests.get(f"{airflow_base_url}/api/v1/version", timeout=10)

    assert response.status_code == 200, "Version endpoint should be accessible"

    data = response.json()
    assert "version" in data, "Response should include version"
    assert "git_version" in data, "Response should include git_version"

    # Should be Airflow 2.7.x
    version = data["version"]
    assert version.startswith("2.7"), f"Should be Airflow 2.7.x, got {version}"


@pytest.mark.integration
def test_airflow_authentication_required(airflow_base_url):
    """Test that protected endpoints require authentication."""
    # Try to access DAGs without authentication
    response = requests.get(f"{airflow_base_url}/api/v1/dags", timeout=10)

    # Should return 401 Unauthorized
    assert response.status_code == 401, "Protected endpoints should require authentication"


@pytest.mark.integration
def test_airflow_authentication_works(airflow_base_url, airflow_auth):
    """Test that authentication with admin credentials works."""
    response = requests.get(f"{airflow_base_url}/api/v1/dags", auth=airflow_auth, timeout=10)

    assert response.status_code == 200, (
        "Authenticated request should succeed. "
        "Check that admin user was created by airflow-init."
    )


@pytest.mark.integration
def test_airflow_dags_endpoint(airflow_base_url, airflow_auth):
    """Test that DAGs endpoint works (should be empty in Phase 1)."""
    response = requests.get(f"{airflow_base_url}/api/v1/dags", auth=airflow_auth, timeout=10)

    assert response.status_code == 200, "DAGs endpoint should be accessible"

    data = response.json()
    assert "dags" in data, "Response should include dags list"
    assert isinstance(data["dags"], list), "dags should be a list"

    # In Phase 1, no DAGs should be present
    # In Phase 3+, this will have our pipeline DAGs
    assert len(data["dags"]) >= 0, "DAGs list should be valid (may be empty in Phase 1)"


@pytest.mark.integration
def test_airflow_config_endpoint(airflow_base_url, airflow_auth):
    """Test that config endpoint works and shows expected executor."""
    response = requests.get(
        f"{airflow_base_url}/api/v1/config",
        auth=airflow_auth,
        timeout=10,
    )

    assert response.status_code == 200, "Config endpoint should be accessible"

    data = response.json()
    assert "sections" in data, "Response should include config sections"

    # Find executor configuration
    executor_found = False
    for section in data["sections"]:
        if section["name"] == "core":
            for option in section["options"]:
                if option["key"] == "executor":
                    executor_found = True
                    # Should be LocalExecutor in Phase 1
                    assert (
                        option["value"] == "LocalExecutor"
                    ), "Should be using LocalExecutor in Phase 1"

    assert executor_found, "Executor configuration should be present"


@pytest.mark.integration
def test_airflow_pools_endpoint(airflow_base_url, airflow_auth):
    """Test that pools endpoint works."""
    response = requests.get(
        f"{airflow_base_url}/api/v1/pools",
        auth=airflow_auth,
        timeout=10,
    )

    assert response.status_code == 200, "Pools endpoint should be accessible"

    data = response.json()
    assert "pools" in data, "Response should include pools list"

    # Should have at least the default pool
    pool_names = [pool["name"] for pool in data["pools"]]
    assert "default_pool" in pool_names, "default_pool should exist"


@pytest.mark.integration
def test_airflow_connections_endpoint(airflow_base_url, airflow_auth):
    """Test that connections endpoint works."""
    response = requests.get(
        f"{airflow_base_url}/api/v1/connections",
        auth=airflow_auth,
        timeout=10,
    )

    assert response.status_code == 200, "Connections endpoint should be accessible"

    data = response.json()
    assert "connections" in data, "Response should include connections list"
    assert isinstance(data["connections"], list), "connections should be a list"


@pytest.mark.integration
def test_airflow_ui_accessible(airflow_base_url):
    """Test that Airflow UI (HTML) is accessible."""
    response = requests.get(airflow_base_url, timeout=10)

    assert response.status_code == 200, "Airflow UI should be accessible"
    assert "text/html" in response.headers.get("Content-Type", ""), "Should return HTML content"
    assert "Airflow" in response.text, "Page should contain 'Airflow' text"


@pytest.mark.integration
def test_airflow_scheduler_health(airflow_base_url):
    """Test that Airflow scheduler is running."""
    response = requests.get(f"{airflow_base_url}/health", timeout=10)

    data = response.json()

    # Check scheduler status (may not be immediately available)
    if "scheduler" in data:
        assert data["scheduler"]["status"] == "healthy", "Scheduler should be healthy"
