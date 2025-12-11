#!/bin/bash
# =============================================================================
# Kafka Topic Initialization Script
# =============================================================================
# This script creates the required Kafka topics for the Oracul platform.
# It runs once during the first docker-compose startup via the kafka-init
# service.
#
# Topics created:
#   - eth.blocks.raw: Block headers and metadata
#   - eth.transactions.raw: Transaction data
#   - eth.logs.raw: Event logs from smart contracts
#   - market.prices.raw: Spot price data for tokens
#
# Configuration:
#   - 1 partition (dev environment, scale to 3+ in production)
#   - 1 replication factor (single broker)
#   - 7 day retention (604800000ms)
#   - Snappy compression
# =============================================================================

set -e

echo "========================================"
echo "Kafka Topic Initialization"
echo "========================================"
echo ""

# Wait for Kafka to be fully ready
echo "Waiting for Kafka broker to be ready..."

MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if kafka-topics --bootstrap-server kafka:9092 --list &>/dev/null; then
        echo "✓ Kafka broker is ready"
        echo ""
        break
    fi

    ATTEMPT=$((ATTEMPT + 1))
    echo "  Attempt $ATTEMPT/$MAX_ATTEMPTS - waiting..."
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "ERROR: Kafka broker did not become ready in time"
    exit 1
fi

# Topic configuration
PARTITIONS=1
REPLICATION_FACTOR=1
RETENTION_MS=604800000  # 7 days
COMPRESSION_TYPE=snappy

# Function to create topic
create_topic() {
    local topic_name=$1
    local description=$2

    echo "Creating topic: $topic_name"
    echo "  Description: $description"

    kafka-topics --bootstrap-server kafka:9092 \
        --create \
        --if-not-exists \
        --topic "$topic_name" \
        --partitions $PARTITIONS \
        --replication-factor $REPLICATION_FACTOR \
        --config retention.ms=$RETENTION_MS \
        --config compression.type=$COMPRESSION_TYPE \
        --config cleanup.policy=delete

    if [ $? -eq 0 ]; then
        echo "  ✓ Topic created successfully"
    else
        echo "  ✗ Failed to create topic"
        return 1
    fi
    echo ""
}

# Create all required topics
echo "Creating Kafka topics..."
echo ""

create_topic "eth.blocks.raw" "Ethereum block headers and metadata"
create_topic "eth.transactions.raw" "Ethereum transaction data"
create_topic "eth.logs.raw" "Ethereum event logs from smart contracts"
create_topic "market.prices.raw" "Spot price data for tracked tokens"

# Verify topics were created
echo "Verifying topic creation..."
echo ""

TOPICS=$(kafka-topics --bootstrap-server kafka:9092 --list)

echo "Available topics:"
echo "$TOPICS"
echo ""

# Check that all expected topics exist
EXPECTED_TOPICS=("eth.blocks.raw" "eth.transactions.raw" "eth.logs.raw" "market.prices.raw")
MISSING_TOPICS=()

for topic in "${EXPECTED_TOPICS[@]}"; do
    if echo "$TOPICS" | grep -q "^${topic}$"; then
        echo "✓ $topic exists"
    else
        echo "✗ $topic is missing"
        MISSING_TOPICS+=("$topic")
    fi
done

echo ""

if [ ${#MISSING_TOPICS[@]} -eq 0 ]; then
    echo "========================================"
    echo "✓ All Kafka topics initialized successfully!"
    echo "========================================"
    exit 0
else
    echo "========================================"
    echo "✗ Some topics are missing:"
    for topic in "${MISSING_TOPICS[@]}"; do
        echo "  - $topic"
    done
    echo "========================================"
    exit 1
fi
