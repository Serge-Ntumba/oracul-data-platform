# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Oracul is a blockchain analytics platform for detecting anomalies and tracking token metrics. It ingests blockchain data in real-time, processes it through Kafka and ClickHouse, computes daily metrics via Airflow, and exposes results through a FastAPI REST API.

**Core data flow:** Blockchain → Ingestion (Python) → Kafka → ClickHouse → Airflow → FastAPI

## Architecture Layers

### 1. Ingestion Layer (`ingestion/`)
Python collector services that extract blockchain data and emit to Kafka topics:
- `block_scanner` - Polls RPC for new blocks
- `tx_and_logs_scanner` - Fetches transactions and event logs
- `price_collector` - Collects market price data

All collectors maintain cursor state for resumable ingestion and implement retry logic with exponential backoff.

### 2. Streaming Layer (Kafka)
Decouples ingestion from storage with dedicated topics:
- `eth.blocks.raw` - Block headers
- `eth.transactions.raw` - Transaction data
- `eth.logs.raw` - Event logs
- `market.prices.raw` - Price ticks

### 3. Storage Layer (`dwh/`)
ClickHouse warehouse with layered table architecture:
- **Raw tables**: Minimal transformation from Kafka (`raw_blocks`, `raw_transactions`, `raw_logs`, `prices_spot`)
- **Curated tables**: Normalized business data (`erc20_transfers`)
- **Aggregated tables**: Pre-computed metrics (`token_metrics_daily`, `address_flows_daily`)
- **Derived tables**: Analysis outputs (`anomalies`, `data_quality_checks`)

All tables partitioned by `toDate(timestamp)` for efficient time-range queries and retention management.

### 4. Orchestration Layer (`pipelines/`)
Airflow DAGs handle transformation and analysis:
- `normalize_erc20_dag` (every 15 min) - Decode ERC-20 Transfer events from raw logs
- `token_metrics_daily_dag` (01:00 UTC) - Compute daily token aggregations
- `address_flows_daily_dag` (01:30 UTC) - Compute daily address flow metrics
- `anomaly_detection_dag` (02:00 UTC) - Detect anomalies using Z-score, IQR, and Isolation Forest
- `data_quality_dag` (hourly) - Validate freshness, completeness, and integrity

All DAGs are idempotent and support reruns.

### 5. Serving Layer (`api/`)
FastAPI application exposing metrics and anomalies. Key endpoints:
- `/tokens/{token_address}/metrics/daily` - Token metrics
- `/anomalies` - Query anomalies with filters
- `/health` - System health status

## Common Development Commands

### Environment Setup
```bash
# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate  # macOS/Linux

# Install dependencies
pip install -r ingestion/requirements.txt
pip install -r api/requirements.txt
pip install -r pipelines/airflow_config/requirements.txt

# Set PYTHONPATH for imports
export PYTHONPATH=$PWD
```

### Starting Infrastructure
```bash
# Bootstrap development environment (starts all services)
./scripts/bootstrap_dev.sh

# Start specific environment
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml up -d

# View logs
docker-compose -f docker-compose.dev.yml logs -f [service]

# Stop services
docker-compose -f docker-compose.dev.yml down
```

### Running Tests
```bash
# All tests
pytest tests/

# API tests only
cd api && pytest tests/

# Specific test file
pytest tests/integration/test_foo.py

# With verbose output
pytest -v tests/

# Run test script
./scripts/run_tests.sh
```

### Running Services Locally
```bash
# Set environment variables
export ALCHEMY_ETH_MAINNET_URL="your_rpc_url"

# Run block scanner
python -m ingestion.chains.eth_mainnet.block_scanner

# Run API server
cd api && uvicorn app.main:app --reload

# Load sample data
python scripts/load_sample_data.py

# Backfill historical data
python scripts/backfill_erc20.py --start 18000000 --end 18001000 --chain 1
```

### Querying ClickHouse
```bash
# Connect via CLI
clickhouse-client --host localhost --port 9000

# Via HTTP
curl http://localhost:8123/ping
curl -X POST 'http://localhost:8123/' --data 'SELECT count() FROM raw_blocks'

# Common queries
SELECT count() FROM raw_blocks;
SELECT * FROM erc20_transfers LIMIT 10;
SELECT * FROM anomalies WHERE severity = 'high';
```

### Code Quality
```bash
# Format code
black .
isort .

# Lint
flake8 .
```

## Key Technical Patterns

### Ingestion Pattern
Collectors use a common pattern:
1. Maintain cursor state (last processed block/timestamp)
2. Poll external source with retry logic
3. Transform to standard format
4. Emit to Kafka topic with proper key
5. Update cursor on success

Shared utilities in `ingestion/common/`:
- `kafka_client.py` - Kafka producer wrapper
- `state_store.py` - Cursor persistence
- `config.py` - Configuration management
- `logging.py` - Structured logging
- `metrics.py` - Prometheus metrics

### Pipeline Pattern
Airflow DAGs follow these conventions:
- Use watermark-based processing to identify new records
- Implement idempotent inserts (handle duplicate runs)
- Include data quality checks within tasks
- Log metrics for monitoring
- Fail fast with clear error messages

Shared utilities in `pipelines/libs/`:
- `clickhouse_client.py` - ClickHouse connection wrapper
- `dq_utils.py` - Data quality check helpers
- `anomaly_utils.py` - Anomaly detection methods

### Configuration Management
Configuration is centralized in `config/`:
- `config/base/` - Shared YAML configs for all environments
- `config/env/{env}/.env` - Environment-specific variables
- Each service loads base config + env overrides

Chain configurations in `config/base/chains.yml` define RPC URLs, chain IDs, and block parameters.

## Important Considerations

### Multi-Chain Readiness
The codebase is designed for multi-chain support:
- All tables include `chain` field (1 = Ethereum mainnet)
- Kafka topic naming follows `{chain}.{entity}.{layer}` pattern
- When adding a new chain, update `config/base/chains.yml` and create chain-specific collectors

### Anomaly Detection Methods
Three methods with severity classification:
- **Z-score**: Deviation from rolling 60-day mean (|z| >= 3 triggers)
- **IQR**: Outlier detection robust to non-normal distributions
- **Isolation Forest**: ML-based multi-feature scoring

Thresholds configurable in anomaly detection DAG.

### Data Quality Checks
System validates:
- Block freshness vs chain tip (max 10 min lag)
- Block number gaps
- Duplicate transaction hashes
- Row count ratios between layers

### Reorg Handling
Block reorgs are not yet implemented. Future enhancement needed in block scanner to:
- Track block confirmations
- Detect and handle chain reorganizations
- Reprocess affected blocks

## Service URLs (Development)

| Service | URL | Credentials |
|---------|-----|-------------|
| ClickHouse HTTP | http://localhost:8123 | - |
| ClickHouse Native | localhost:9000 | oracul_user / (from .env) |
| Kafka | localhost:9092 | - |
| Airflow | http://localhost:8080 | admin / admin |
| API | http://localhost:8000 | - |
| API Docs | http://localhost:8000/docs | - |

## Performance Targets

| Metric | Target |
|--------|--------|
| Ingestion lag | ≤ 5 minutes from chain tip |
| Query performance | < 5 seconds for 30-day analytics |
| Pipeline completion | Daily DAGs done by 03:00 UTC |
| System uptime | 99%+ availability |

## Documentation References

- [Architecture Overview](docs/architecture/high_level_overview.md) - System design and capabilities
- [Data Flow](docs/architecture/data_flow.md) - Detailed data movement through layers
- [Component Responsibilities](docs/architecture/component_responsibilities.md) - Ownership and interfaces
- [Product Requirements](docs/product/PRD_oracul_platform_v1.md) - Business context and use cases
- [Getting Started](GETTING_STARTED.md) - Detailed setup instructions
