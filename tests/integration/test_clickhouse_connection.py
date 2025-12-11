"""
Integration tests for ClickHouse connectivity.

These tests verify that:
1. ClickHouse is accessible from the host
2. The oracul database exists
3. Basic queries work
4. Authentication is properly configured

Requirements:
- ClickHouse must be running (via docker-compose)
- Connection details in environment or use defaults
"""

import os

import pytest
from clickhouse_driver import Client


@pytest.fixture
def clickhouse_client():
    """Create a ClickHouse client for testing."""
    host = os.getenv("CLICKHOUSE_HOST", "localhost")
    port = int(os.getenv("CLICKHOUSE_PORT", "9000"))
    user = os.getenv("CLICKHOUSE_USER", "default")
    password = os.getenv("CLICKHOUSE_PASSWORD", "oracul_dev_2024")

    client = Client(host=host, port=port, user=user, password=password, connect_timeout=10)

    yield client

    # Cleanup
    client.disconnect()


@pytest.mark.integration
def test_clickhouse_connection(clickhouse_client):
    """Test basic ClickHouse connectivity."""
    result = clickhouse_client.execute("SELECT 1")
    assert result == [(1,)], "Basic SELECT query should return 1"


@pytest.mark.integration
def test_clickhouse_version(clickhouse_client):
    """Test ClickHouse version query."""
    result = clickhouse_client.execute("SELECT version()")
    assert len(result) == 1, "Version query should return one row"
    assert len(result[0]) == 1, "Version should be a single value"
    version = result[0][0]
    assert isinstance(version, str), "Version should be a string"
    assert "." in version, "Version should contain dots (e.g., 23.8.2.7)"


@pytest.mark.integration
def test_oracul_database_exists(clickhouse_client):
    """Test that the oracul database exists."""
    result = clickhouse_client.execute("SHOW DATABASES")
    databases = [row[0] for row in result]

    assert "oracul" in databases, (
        "Database 'oracul' should exist. " "Make sure init-db.sql ran during container startup."
    )


@pytest.mark.integration
def test_use_oracul_database(clickhouse_client):
    """Test switching to the oracul database."""
    # This should not raise an exception
    clickhouse_client.execute("USE oracul")

    # Verify we're in the right database
    result = clickhouse_client.execute("SELECT currentDatabase()")
    assert result == [("oracul",)], "Should be using the oracul database"


@pytest.mark.integration
def test_clickhouse_http_interface():
    """Test ClickHouse HTTP interface (port 8123)."""
    import requests

    http_port = int(os.getenv("CLICKHOUSE_HTTP_PORT", "8123"))
    url = f"http://localhost:{http_port}/"

    # Simple ping
    response = requests.get(f"{url}ping")
    assert response.status_code == 200, "HTTP ping should succeed"
    assert response.text.strip() == "Ok.", "Ping should return 'Ok.'"

    # Simple query
    response = requests.post(url, data="SELECT 1")
    assert response.status_code == 200, "HTTP query should succeed"
    assert response.text.strip() == "1", "Query should return 1"


@pytest.mark.integration
def test_clickhouse_settings(clickhouse_client):
    """Test that ClickHouse has reasonable settings."""
    # Check max memory usage setting
    result = clickhouse_client.execute(
        "SELECT name, value FROM system.settings WHERE name = 'max_memory_usage'"
    )

    assert len(result) > 0, "Should have max_memory_usage setting"

    # The value should be reasonable (at least 1GB)
    setting_value = int(result[0][1])
    assert setting_value >= 1_000_000_000, "max_memory_usage should be at least 1GB"


@pytest.mark.integration
def test_clickhouse_create_drop_table(clickhouse_client):
    """Test creating and dropping a temporary table in the oracul database."""
    # Create a test table
    clickhouse_client.execute("USE oracul")
    clickhouse_client.execute(
        """
        CREATE TABLE IF NOT EXISTS test_integration_table (
            id UInt32,
            message String,
            created_at DateTime DEFAULT now()
        ) ENGINE = MergeTree()
        ORDER BY id
    """
    )

    # Insert test data
    clickhouse_client.execute("INSERT INTO test_integration_table (id, message) VALUES (1, 'test')")

    # Query it back
    result = clickhouse_client.execute(
        "SELECT id, message FROM test_integration_table WHERE id = 1"
    )
    assert result == [(1, "test")], "Should be able to insert and query data"

    # Drop the table
    clickhouse_client.execute("DROP TABLE IF EXISTS test_integration_table")

    # Verify it's gone
    tables = clickhouse_client.execute("SHOW TABLES FROM oracul")
    table_names = [row[0] for row in tables]
    assert "test_integration_table" not in table_names, "Table should be dropped"
