# Oracul Platform

A blockchain analytics platform for detecting anomalies and tracking token metrics across multiple chains.

## Overview

Oracul Platform ingests blockchain data in real-time, computes daily metrics for tokens and addresses, and detects anomalies using statistical methods. It provides a REST API for querying metrics and anomalies.

## Architecture

```
Blockchain → Ingestion (Python) → Kafka → ClickHouse → Airflow → FastAPI
```

See [docs/architecture/high_level_overview.md](docs/architecture/high_level_overview.md) for details.

## Project Structure

```
oracul-platform/
├── infra/              # Infrastructure-as-code, docker-compose, k8s, terraform
├── config/             # Centralized configs: env vars, connection profiles
├── dwh/                # ClickHouse schemas, migrations, seed data
├── ingestion/          # Python collectors + Kafka producers
├── pipelines/          # Airflow DAGs + shared pipeline code
├── api/                # FastAPI service to serve metrics & anomalies
├── analytics/          # Notebooks, experiments, DS models
├── docs/               # Architecture docs, ADRs, diagrams, PRD
├── scripts/            # Helper scripts for dev, bootstrap, utilities
├── tests/              # Cross-project tests (integration, e2e, load)
└── .github/            # CI pipelines
```

Each directory contains its own README with detailed information.

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Python 3.11+
- ClickHouse client (optional)

### 1. Bootstrap Development Environment

```bash
./scripts/bootstrap_dev.sh
```

This will:
- Start ClickHouse, Kafka, Airflow, and API services
- Initialize database schemas
- Load seed data

### 2. Access Services

- **ClickHouse**: http://localhost:8123
- **Airflow**: http://localhost:8080 (admin/admin)
- **API**: http://localhost:8000/docs
- **Kafka**: localhost:9092

### 3. Load Sample Data

```bash
python scripts/load_sample_data.py
```

### 4. Run Ingestion

```bash
export ALCHEMY_ETH_MAINNET_URL="your_rpc_url"
python -m ingestion.chains.eth_mainnet.block_scanner
```

## Development

### Running Tests

```bash
# All tests
pytest tests/

# API tests only
cd api && pytest tests/

# Integration tests
pytest tests/integration/
```

### Code Quality

```bash
# Format code
black .
isort .

# Lint
flake8 .
```

### Adding a New Chain

See [docs/runbooks/how_to_add_new_chain.md](docs/runbooks/how_to_add_new_chain.md)

### Backfilling Data

See [docs/runbooks/how_to_backfill_data.md](docs/runbooks/how_to_backfill_data.md)

## Key Technologies

- **ClickHouse** - OLAP database for analytics
- **Kafka** - Message queue for data ingestion
- **Airflow** - Workflow orchestration
- **FastAPI** - REST API framework
- **Python** - Data processing & ingestion
- **Docker/Kubernetes** - Deployment

## Documentation

- [Product Requirements](docs/product/PRD_oracul_platform_v1.md)
- [Architecture Overview](docs/architecture/high_level_overview.md)
- [Architecture Decisions](docs/adr/)
- [Runbooks](docs/runbooks/)

## Contributing

1. Create a feature branch
2. Make changes
3. Add tests
4. Run linting and tests
5. Submit pull request

## License

MIT

## Support

For issues and questions, please open a GitHub issue.
