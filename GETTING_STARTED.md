# Getting Started with Oracul Platform

## Overview

This guide will help you get the Oracul Platform up and running on your local machine.

## Prerequisites

### Required
- Docker Desktop (or Docker + Docker Compose)
- Python 3.11 or higher
- Git

### Optional but Recommended
- ClickHouse CLI client
- Kafka CLI tools
- Make
- Act (for testing GitHub Actions locally)

## Step-by-Step Setup

### 1. Clone the Repository

```bash
cd /path/to/your/workspace
git clone <repository-url> oracul-platform
cd oracul-platform
```

### 2. Set Up Python Environment

```bash
# Create virtual environment
python3 -m venv venv

# Activate it
source venv/bin/activate  # On macOS/Linux
# or
venv\Scripts\activate  # On Windows

# Install dependencies for all components
pip install -r ingestion/requirements.txt
pip install -r api/requirements.txt
pip install -r pipelines/airflow_config/requirements.txt
```

### 3. Configure Environment Variables

```bash
# Copy example environment file
cp config/env/dev/.env.example config/env/dev/.env

# Edit with your values
nano config/env/dev/.env
```

Required variables:
- `ALCHEMY_ETH_MAINNET_URL` - Your Alchemy or Infura RPC URL
- `CLICKHOUSE_PASSWORD` - Choose a password for ClickHouse
- `API_SECRET_KEY` - Generate a secret key for the API

### 4. Start Infrastructure

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Bootstrap the development environment
./scripts/bootstrap_dev.sh
```

This will:
- Start ClickHouse, Kafka, Airflow, and the API
- Create database tables
- Load seed data (token metadata, chain info)

### 5. Verify Services

Check that all services are running:

```bash
# ClickHouse
curl http://localhost:8123/ping

# API
curl http://localhost:8000/health

# Airflow (open in browser)
open http://localhost:8080  # macOS
# Login: admin / admin
```

### 6. Load Sample Data

```bash
# Load sample blocks and transfers for testing
python scripts/load_sample_data.py
```

### 7. Start Data Ingestion (Optional)

```bash
# Set your RPC URL
export ALCHEMY_ETH_MAINNET_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"

# Run block scanner
python -m ingestion.chains.eth_mainnet.block_scanner
```

### 8. Explore the API

Open the interactive API documentation:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

Try some endpoints:
```bash
# Get health status
curl http://localhost:8000/health

# Get top tokens (requires sample data)
curl "http://localhost:8000/tokens/top?limit=10"
```

### 9. Run Airflow DAGs

1. Open Airflow UI: http://localhost:8080
2. Enable DAGs:
   - `token_metrics_daily`
   - `anomaly_detection`
3. Trigger manually or wait for scheduled runs

### 10. Explore Analytics

```bash
# Install Jupyter
pip install jupyter pandas numpy matplotlib

# Start Jupyter
cd analytics
jupyter notebook

# Open notebooks/01_explore_erc20_transfers.ipynb
```

## Common Tasks

### Stop Services

```bash
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml down
```

### View Logs

```bash
# All services
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml logs -f

# Specific service
docker-compose -f docker-compose.dev.yml logs -f clickhouse
```

### Query ClickHouse

```bash
# Using CLI
clickhouse-client --host localhost --port 9000

# Example query
SELECT count() FROM raw_blocks;
SELECT * FROM erc20_transfers LIMIT 10;
```

### Run Tests

```bash
# All tests
pytest tests/

# API tests only
cd api && pytest tests/

# Integration tests
pytest tests/integration/
```

### Backfill Historical Data

```bash
python scripts/backfill_erc20.py --start 18000000 --end 18001000 --chain 1
```

## Troubleshooting

### ClickHouse Connection Issues

```bash
# Check if ClickHouse is running
docker ps | grep clickhouse

# Restart ClickHouse
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml restart clickhouse
```

### Kafka Issues

```bash
# Check Kafka logs
docker-compose -f infra/docker-compose/docker-compose.dev.yml logs kafka

# List topics
docker exec -it <kafka-container> kafka-topics --list --bootstrap-server localhost:9092
```

### Port Already in Use

If ports are already in use, edit `infra/docker-compose/docker-compose.dev.yml` to change port mappings.

### Python Import Errors

Make sure you're in the project root and have activated your virtual environment:
```bash
cd /path/to/oracul-platform
source venv/bin/activate
export PYTHONPATH=$PWD
```

## Next Steps

- Read [Architecture Overview](docs/architecture/high_level_overview.md)
- Review [Architecture Decision Records](docs/adr/)
- Check out [Product Requirements](docs/product/PRD_oracul_platform_v1.md)
- Explore [Runbooks](docs/runbooks/) for operational guides

## Getting Help

- Check documentation in `docs/`
- Review code comments in each module
- Open an issue on GitHub
- Contact the team

## Quick Reference

| Service | URL | Credentials |
|---------|-----|-------------|
| ClickHouse HTTP | http://localhost:8123 | - |
| ClickHouse Native | localhost:9000 | oracul_user / (from .env) |
| Kafka | localhost:9092 | - |
| Airflow | http://localhost:8080 | admin / admin |
| API | http://localhost:8000 | - |
| API Docs | http://localhost:8000/docs | - |
