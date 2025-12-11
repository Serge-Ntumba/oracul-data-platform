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

### Setting Up Your Development Environment

1. **Create and activate a virtual environment:**

```bash
python3 -m venv venv
source venv/bin/activate  # On macOS/Linux
# or
venv\Scripts\activate  # On Windows
```

2. **Install development dependencies:**

```bash
# Install dev tools (linting, formatting, testing)
pip install -r requirements-dev.txt

# Install project-specific dependencies
pip install -r ingestion/requirements.txt
pip install -r api/requirements.txt
pip install -r pipelines/airflow_config/requirements.txt
pip install -r tests/requirements.txt

# Set PYTHONPATH
export PYTHONPATH=$PWD
```

3. **Install pre-commit hooks:**

```bash
pre-commit install
```

This will automatically run code formatters and linters before each commit.

### Running Pre-commit Hooks Manually

```bash
# Run on all files
pre-commit run --all-files

# Run on staged files only
pre-commit run
```

### Running Tests

```bash
# All tests
pytest tests/

# Unit tests only
pytest tests/unit/

# API tests only
cd api && pytest tests/

# Integration tests
pytest tests/integration/ -m integration
```

### Code Quality

The project uses pre-commit hooks to automatically enforce code quality. You can also run these tools manually:

```bash
# Format code
black --line-length=100 .
isort --profile=black --line-length=100 .

# Lint
flake8 . --max-line-length=100 --extend-ignore=E203,W503,E501

# Type checking (optional)
mypy ingestion/common/ api/app/ pipelines/libs/
```

### Adding a New Chain

See [docs/runbooks/how_to_add_new_chain.md](docs/runbooks/how_to_add_new_chain.md)

### Backfilling Data

See [docs/runbooks/how_to_backfill_data.md](docs/runbooks/how_to_backfill_data.md)

## CI/CD

The project uses GitHub Actions for continuous integration. On every pull request and push to `main`/`develop`, the following checks run:

- **Linting**: Code formatting (black, isort) and style checking (flake8)
- **Unit Tests**: Fast, isolated tests (`tests/unit/`)
- **API Tests**: API endpoint tests with ClickHouse service (`api/tests/`)
- **Integration Tests**: Integration tests with external services (`tests/integration/`)

Workflows are defined in [`.github/workflows/`](.github/workflows/):
- [`ci.yml`](.github/workflows/ci.yml) - Main CI pipeline (lint + all tests)
- [`api_tests.yml`](.github/workflows/api_tests.yml) - API-specific tests (triggered on `api/` changes)
- [`pipelines_tests.yml`](.github/workflows/pipelines_tests.yml) - Pipeline tests (triggered on `pipelines/` changes)

All workflows use pip caching for faster execution.

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
