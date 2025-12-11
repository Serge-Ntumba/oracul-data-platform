"""
Integration tests for Kafka topics and connectivity.

These tests verify that:
1. Kafka broker is accessible
2. All required topics exist
3. Topics have correct configuration
4. Producer and consumer work correctly

Requirements:
- Kafka must be running (via docker-compose)
- Topics must be created (via kafka-init service)
"""

import json
import os
import time
from uuid import uuid4

import pytest
from kafka import KafkaAdminClient, KafkaConsumer, KafkaProducer
from kafka.admin import ConfigResource, ConfigResourceType


@pytest.fixture
def kafka_bootstrap_servers():
    """Get Kafka bootstrap servers from environment."""
    return os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")


@pytest.fixture
def kafka_admin_client(kafka_bootstrap_servers):
    """Create Kafka admin client for testing."""
    client = KafkaAdminClient(
        bootstrap_servers=kafka_bootstrap_servers, client_id="test-admin-client"
    )

    yield client

    client.close()


@pytest.fixture
def kafka_producer(kafka_bootstrap_servers):
    """Create Kafka producer for testing."""
    producer = KafkaProducer(
        bootstrap_servers=kafka_bootstrap_servers,
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),
        key_serializer=lambda k: k.encode("utf-8") if k else None,
    )

    yield producer

    producer.close()


@pytest.mark.integration
def test_kafka_broker_available(kafka_admin_client):
    """Test that Kafka broker is reachable."""
    # This will raise an exception if broker is not available
    topics = kafka_admin_client.list_topics()
    assert isinstance(topics, list), "Should return a list of topics"


@pytest.mark.integration
def test_required_topics_exist(kafka_admin_client):
    """Test that all required Oracul topics exist."""
    topics = kafka_admin_client.list_topics()

    required_topics = [
        "eth.blocks.raw",
        "eth.transactions.raw",
        "eth.logs.raw",
        "market.prices.raw",
    ]

    for topic in required_topics:
        assert topic in topics, (
            f"Topic '{topic}' should exist. " "Make sure kafka-init service ran successfully."
        )


@pytest.mark.integration
def test_topic_configuration(kafka_admin_client):
    """Test that topics have correct configuration."""
    # Check partition count for one of our topics
    metadata = kafka_admin_client.describe_topics(["eth.blocks.raw"])

    assert len(metadata) > 0, "Should have metadata for eth.blocks.raw"
    topic_metadata = metadata[0]

    # In dev environment, we expect 1 partition
    assert len(topic_metadata["partitions"]) == 1, "Should have 1 partition in dev"


@pytest.mark.integration
def test_topic_retention_config(kafka_admin_client):
    """Test that topics have retention configured."""
    # Get topic configs
    config_resource = ConfigResource(ConfigResourceType.TOPIC, "eth.blocks.raw")

    configs = kafka_admin_client.describe_configs([config_resource])

    # Check retention.ms is set (should be 604800000ms = 7 days)
    retention_config = None
    for config_response in configs:
        for config_name, config_entry in config_response.resources[0][4].items():
            if config_name == "retention.ms":
                retention_config = config_entry.value

    assert retention_config is not None, "retention.ms should be configured"
    # Should be 7 days (604800000ms)
    assert int(retention_config) == 604800000, "Should have 7-day retention"


@pytest.mark.integration
def test_kafka_produce_consume(kafka_bootstrap_servers, kafka_producer):
    """Test producing and consuming messages from Kafka."""
    test_topic = "eth.blocks.raw"

    # Create test data with unique ID
    test_id = str(uuid4())
    test_data = {
        "test_id": test_id,
        "block_number": 12345,
        "timestamp": int(time.time()),
        "message": "integration test message",
    }

    # Produce message
    future = kafka_producer.send(test_topic, value=test_data, key=test_id)
    kafka_producer.flush()

    # Wait for message to be sent
    record_metadata = future.get(timeout=10)
    assert record_metadata.topic == test_topic, "Message should be sent to correct topic"

    # Consume message
    consumer = KafkaConsumer(
        test_topic,
        bootstrap_servers=kafka_bootstrap_servers,
        auto_offset_reset="earliest",
        value_deserializer=lambda m: json.loads(m.decode("utf-8")),
        consumer_timeout_ms=5000,  # 5 second timeout
        group_id=f"test-group-{uuid4()}",  # Unique group ID
    )

    # Find our test message
    found = False
    for message in consumer:
        if message.value.get("test_id") == test_id:
            assert message.value == test_data, "Message content should match"
            found = True
            break

    consumer.close()

    assert found, "Should be able to consume the produced message"


@pytest.mark.integration
def test_kafka_topic_compaction(kafka_admin_client):
    """Test that topics use delete (not compact) cleanup policy."""
    config_resource = ConfigResource(ConfigResourceType.TOPIC, "eth.blocks.raw")

    configs = kafka_admin_client.describe_configs([config_resource])

    cleanup_policy = None
    for config_response in configs:
        for config_name, config_entry in config_response.resources[0][4].items():
            if config_name == "cleanup.policy":
                cleanup_policy = config_entry.value

    assert cleanup_policy == "delete", "Topics should use 'delete' cleanup policy, not 'compact'"


@pytest.mark.integration
def test_kafka_compression(kafka_admin_client):
    """Test that topics have compression enabled."""
    config_resource = ConfigResource(ConfigResourceType.TOPIC, "eth.blocks.raw")

    configs = kafka_admin_client.describe_configs([config_resource])

    compression_type = None
    for config_response in configs:
        for config_name, config_entry in config_response.resources[0][4].items():
            if config_name == "compression.type":
                compression_type = config_entry.value

    # Should be snappy compression
    assert compression_type == "snappy", "Topics should use snappy compression"


@pytest.mark.integration
def test_all_topics_accessible(kafka_bootstrap_servers):
    """Test that we can create consumers for all required topics."""
    required_topics = [
        "eth.blocks.raw",
        "eth.transactions.raw",
        "eth.logs.raw",
        "market.prices.raw",
    ]

    for topic in required_topics:
        # This will raise an exception if topic is not accessible
        consumer = KafkaConsumer(
            topic,
            bootstrap_servers=kafka_bootstrap_servers,
            auto_offset_reset="latest",
            consumer_timeout_ms=1000,
            group_id=f"test-accessibility-{uuid4()}",
        )

        # Just verify we can subscribe, no need to consume
        assert (
            consumer.subscription() or topic in consumer.topics()
        ), f"Should be able to access topic {topic}"

        consumer.close()
