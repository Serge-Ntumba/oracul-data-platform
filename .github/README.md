# Oracul Platform

A blockchain analytics platform for detecting anomalies and tracking token metrics across multiple chains.

## Overview

Oracul Platform ingests blockchain data in real-time, computes daily metrics for tokens and addresses, and detects anomalies using statistical methods. It provides a REST API for querying metrics and anomalies.

## Architecture

```
Blockchain → Ingestion (Python) → Kafka → ClickHouse → Airflow → FastAPI
```

**Core Components:**
- **Ingestion Layer**: Python collectors that extract blockchain data and emit to Kafka
- **Streaming Layer**: Kafka topics for decoupled data ingestion
- **Storage Layer**: ClickHouse warehouse with layered table architecture
- **Orchestration Layer**: Airflow DAGs for transformation and analysis
- **Serving Layer**: FastAPI application exposing metrics and anomalies

## Project Structure

```
oracul-platform/
├── infra/              # Docker Compose, initialization scripts
├── config/             # Environment configs and chain definitions
├── dwh/                # ClickHouse schemas and migrations
├── ingestion/          # Python collectors + Kafka producers
├── pipelines/          # Airflow DAGs + shared pipeline code
├── api/                # FastAPI service to serve metrics & anomalies
├── analytics/          # Notebooks, experiments, DS models
├── scripts/            # Helper scripts (bootstrap, testing, utilities)
└── tests/              # Integration and end-to-end tests
```

## Quick Start

### Prerequisites

- **Docker & Docker Compose** 4.20+
- **Python** 3.11+
- **16GB RAM** (recommended, 8GB minimum)
- **20GB free disk space**

### One-Command Setup

```bash
./scripts/bootstrap_dev.sh
```

This script will:
- ✅ Check prerequisites (Docker, Python, disk space)
- ✅ Generate secrets (Fernet key, passwords)
- ✅ Start all services (ClickHouse, Kafka, Airflow, API, Metabase)
- ✅ Initialize databases and topics
- ✅ Verify service health

### Access Services

Once the bootstrap completes, access:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Airflow UI** | http://localhost:8080 | admin / admin |
| **API Docs** | http://localhost:8000/docs | - |
| **Metabase** | http://localhost:3000 | Setup on first visit |
| **ClickHouse HTTP** | http://localhost:8123 | - |
| **ClickHouse Native** | localhost:9000 | default / (from .env) |
| **Kafka** | localhost:9092 | - |

### Manual Setup (Alternative)

<details>
<summary>Click to expand manual setup steps</summary>

1. **Start services:**
```bash
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml up -d
```

2. **Check service health:**
```bash
docker-compose -f docker-compose.dev.yml ps
```

3. **View logs:**
```bash
docker-compose -f docker-compose.dev.yml logs -f [service-name]
```

4. **Stop services:**
```bash
docker-compose -f docker-compose.dev.yml down
```

</details>

## Development

### Environment Setup

1. **Create virtual environment:**
```bash
python3 -m venv venv
source venv/bin/activate  # macOS/Linux
```

2. **Install dependencies:**
```bash
pip install -r ingestion/requirements.txt
pip install -r api/requirements.txt
pip install -r pipelines/airflow_config/requirements.txt
pip install -r tests/requirements.txt

export PYTHONPATH=$PWD
```

3. **Configure environment:**
```bash
# Copy example and edit with your values
cp config/env/dev/.env.example infra/docker-compose/.env
# Add your RPC URL: ALCHEMY_ETH_MAINNET_URL=your_url_here
```

### Running Services Locally

**Start block scanner:**
```bash
export ALCHEMY_ETH_MAINNET_URL="your_rpc_url"
python -m ingestion.chains.eth_mainnet.block_scanner
```

**Start API server:**
```bash
cd api && uvicorn app.main:app --reload
```

### Testing

**Run all tests:**
```bash
./scripts/run_tests.sh
```

**Run specific test types:**
```bash
# Integration tests only
./scripts/run_tests.sh integration

# API tests only
./scripts/run_tests.sh api

# Unit tests only
./scripts/run_tests.sh unit
```

**Manual pytest:**
```bash
# All tests
pytest tests/

# Specific test file
pytest tests/integration/test_clickhouse_connection.py -v

# With coverage
pytest tests/ --cov=. --cov-report=html
```

### Code Quality

**Pre-commit hooks** (automatically runs on commit):
```bash
pre-commit install
pre-commit run --all-files
```

**Manual formatting and linting:**
```bash
# Format code
black .
isort .

# Lint
flake8 .
```

## Common Tasks

### Query ClickHouse

**Via CLI:**
```bash
clickhouse-client --host localhost --port 9000
```

**Common queries:**
```sql
SELECT count() FROM raw_blocks;
SELECT * FROM erc20_transfers LIMIT 10;
SELECT * FROM anomalies WHERE severity = 'high';
```

**Via HTTP:**
```bash
curl http://localhost:8123/ping
curl -X POST 'http://localhost:8123/' --data 'SELECT version()'
```

### Manage Kafka Topics

**List topics:**
```bash
docker-compose -f docker-compose.dev.yml exec kafka \
  kafka-topics --bootstrap-server kafka:9093 --list
```

**Describe topic:**
```bash
docker-compose -f docker-compose.dev.yml exec kafka \
  kafka-topics --bootstrap-server kafka:9093 --describe --topic eth.blocks.raw
```

### View Service Logs

```bash
cd infra/docker-compose

# All services
docker-compose -f docker-compose.dev.yml logs -f

# Specific service
docker-compose -f docker-compose.dev.yml logs -f kafka
docker-compose -f docker-compose.dev.yml logs -f airflow-scheduler
```

## Troubleshooting

### Services won't start

1. Check Docker is running: `docker info`
2. Check available disk space: `df -h`
3. View service logs: `docker-compose logs [service]`
4. Restart services: `docker-compose down && docker-compose up -d`

### ClickHouse connection errors

- Verify service is healthy: `docker-compose ps clickhouse-server`
- Test connection: `clickhouse-client --host localhost --port 9000`
- Check credentials in `.env` file

### Kafka topics not created

- Check kafka-init logs: `docker-compose logs kafka-init`
- Manually create topics (see "Manage Kafka Topics" section)

### Airflow DAGs not appearing

- Check Airflow logs: `docker-compose logs airflow-scheduler`
- Verify `pipelines/dags/` directory is mounted correctly
- Refresh Airflow UI (may take 30-60 seconds to detect new DAGs)

See [GETTING_STARTED.md](GETTING_STARTED.md) for detailed setup instructions and troubleshooting.

## Key Technologies

- **ClickHouse** 23.8 - OLAP database for analytics
- **Kafka** 7.5 - Message streaming platform
- **Airflow** 2.7 - Workflow orchestration
- **FastAPI** - High-performance REST API framework
- **Python** 3.11 - Data processing & ingestion
- **Docker Compose** - Local development orchestration
- **Metabase** - Business intelligence and visualization

## Current Status

**Phase 1: Core Infrastructure ✅ COMPLETE**
- Docker Compose orchestration with 8 services
- ClickHouse warehouse initialized
- Kafka topics created (eth.blocks.raw, eth.transactions.raw, eth.logs.raw, market.prices.raw)
- Airflow LocalExecutor configured
- FastAPI health endpoints working
- Integration tests passing

**Next Steps (Phase 2):**
- Implement ClickHouse table schemas
- Build Airflow ETL pipelines
- Develop data quality checks

## Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Add/update tests
4. Run code quality checks (`pre-commit run --all-files`)
5. Submit a pull request

## License

MIT

## Support

For issues and questions, please open a GitHub issue or refer to [GETTING_STARTED.md](GETTING_STARTED.md) for detailed documentation.
