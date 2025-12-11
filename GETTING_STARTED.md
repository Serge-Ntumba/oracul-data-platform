# Getting Started with Oracul Platform

Welcome to the Oracul Blockchain Data Platform! This guide will help you set up your local development environment and start building.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Verifying Your Installation](#verifying-your-installation)
- [Service Access](#service-access)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

## Prerequisites

Before you begin, ensure you have the following installed:

### Required Software

| Software | Minimum Version | Purpose | Installation Link |
|----------|----------------|---------|-------------------|
| **Docker Desktop** | 4.20+ | Container runtime | [docker.com](https://www.docker.com/products/docker-desktop) |
| **Python** | 3.9+ | Script execution & dev tools | [python.org](https://www.python.org/downloads/) |
| **Git** | 2.30+ | Version control | [git-scm.com](https://git-scm.com/downloads) |

### System Requirements

- **RAM:** 16GB recommended (8GB minimum)
- **Disk Space:** 20GB free for Docker images and data
- **OS:** macOS 11+, Ubuntu 22.04+, or Windows 10+ with WSL2

### Python Packages (for development)

```bash
pip install cryptography  # For secret generation in bootstrap script
```

## Quick Start

For experienced developers who want to get started immediately:

```bash
# 1. Clone the repository
git clone https://github.com/your-org/oracul-platform.git
cd oracul-platform

# 2. Run the bootstrap script
./scripts/bootstrap_dev.sh

# 3. Access services
# Airflow: http://localhost:8080 (admin/admin)
# API: http://localhost:8000/docs
# Metabase: http://localhost:3000
```

That's it! The bootstrap script handles everything automatically.

## Detailed Setup

### Step 1: Clone the Repository

```bash
git clone https://github.com/your-org/oracul-platform.git
cd oracul-platform
```

### Step 2: Install Pre-commit Hooks (Optional but Recommended)

```bash
# Install pre-commit
pip install pre-commit

# Install git hooks
pre-commit install

# Test the hooks
pre-commit run --all-files
```

This ensures code quality by running formatters and linters before each commit.

### Step 3: Configure Environment

The bootstrap script will guide you through this, but if you want to configure manually:

```bash
# Copy environment template
cp config/env/dev/.env.example infra/docker-compose/.env

# Edit the .env file
nano infra/docker-compose/.env

# IMPORTANT: Set your RPC URL
# Find ALCHEMY_ETH_MAINNET_URL and replace with your actual URL
```

### Step 4: Run Bootstrap Script

```bash
./scripts/bootstrap_dev.sh
```

This script will:
- ✅ Check prerequisites (Docker, Python, etc.)
- ✅ Create and configure `.env` file
- ✅ Generate secrets (Fernet key, JWT secret, passwords)
- ✅ Pull Docker images (~1.5GB download)
- ✅ Start all 9 services (ClickHouse, Kafka, Airflow, API, etc.)
- ✅ Wait for services to be healthy
- ✅ Initialize databases and topics
- ✅ Verify everything is working

**Expected time:** 3-5 minutes on first run, 1-2 minutes on subsequent runs.

### Step 5: Verify Installation

The bootstrap script shows service health, but you can manually verify:

```bash
# Run all verification tests
./scripts/run_tests.sh integration

# Or check individual services
curl http://localhost:8080/health  # Airflow
curl http://localhost:8000/docs    # API
curl http://localhost:3000/api/health  # Metabase

# ClickHouse CLI
clickhouse-client --host localhost --port 9000
> SHOW DATABASES;
> USE oracul;
> SHOW TABLES;  -- Should be empty in Phase 1
> exit
```

## Verifying Your Installation

### Service Health Check

View all running services:

```bash
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml ps
```

You should see 9+ services with "healthy" status:
- `oracul_clickhouse` - healthy
- `oracul_postgres` - healthy
- `oracul_zookeeper` - healthy
- `oracul_kafka` - healthy
- `oracul_airflow_webserver` - healthy
- `oracul_airflow_scheduler` - healthy
- `oracul_api` - healthy
- `oracul_metabase` - healthy

### Kafka Topics

```bash
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml exec kafka \
  kafka-topics --bootstrap-server localhost:9092 --list
```

Expected output:
```
eth.blocks.raw
eth.logs.raw
eth.transactions.raw
market.prices.raw
```

### ClickHouse Database

```bash
clickhouse-client --host localhost --port 9000 --query "SHOW DATABASES"
```

Expected output should include:
```
oracul
system
default
```

## Service Access

### Airflow

- **URL:** http://localhost:8080
- **Credentials:** `admin` / `admin`
- **Purpose:** DAG management and monitoring
- **What to check:**
  - Homepage loads successfully
  - No DAGs yet (expected in Phase 1)
  - Will have DAGs in Phase 3+

### API (FastAPI)

- **URL:** http://localhost:8000
- **API Docs:** http://localhost:8000/docs
- **Health:** http://localhost:8000/health
- **Purpose:** REST API for metrics and anomalies
- **Note:** Endpoints may return empty data in Phase 1

### Metabase

- **URL:** http://localhost:3000
- **First Visit:** Complete setup wizard
- **Purpose:** BI dashboards and visualizations

#### Metabase Setup Steps

1. **Open** http://localhost:3000
2. **Create account** (local only, not shared)
3. **Add ClickHouse database:**
   - Database type: **ClickHouse**
   - Host: `clickhouse-server` (container name)
   - Port: `8123` (HTTP port)
   - Database: `oracul`
   - Username: `default`
   - Password: (check `infra/docker-compose/.env` for `CLICKHOUSE_PASSWORD`)
4. **Test connection** and save

### ClickHouse

- **Native Protocol:** `localhost:9000`
- **HTTP Interface:** `localhost:8123`
- **CLI Access:**
  ```bash
  clickhouse-client --host localhost --port 9000
  ```
- **HTTP Query:**
  ```bash
  curl 'http://localhost:8123/?query=SELECT+1'
  ```

### Kafka

- **Bootstrap Server:** `localhost:9092`
- **Topics:** See "Kafka Topics" section above
- **Access:**
  ```bash
  cd infra/docker-compose
  docker-compose -f docker-compose.dev.yml exec kafka bash
  ```

## Common Tasks

### Starting Services

```bash
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml up -d
```

### Stopping Services

```bash
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml down
```

### Viewing Logs

```bash
# All services
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml logs -f

# Specific service
docker-compose -f docker-compose.dev.yml logs -f clickhouse-server
docker-compose -f docker-compose.dev.yml logs -f kafka
docker-compose -f docker-compose.dev.yml logs -f airflow-webserver
```

### Restarting a Service

```bash
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml restart clickhouse-server
```

### Running Tests

```bash
# All tests (linters + unit + integration)
./scripts/run_tests.sh

# Specific test types
./scripts/run_tests.sh lint         # Code quality only
./scripts/run_tests.sh unit         # Unit tests only
./scripts/run_tests.sh integration  # Integration tests only
```

### Resetting the Environment

If you need to start fresh:

```bash
cd infra/docker-compose

# Stop and remove containers + volumes (DELETES ALL DATA)
docker-compose -f docker-compose.dev.yml down -v

# Restart from scratch
cd ../..
./scripts/bootstrap_dev.sh
```

### Updating Dependencies

```bash
# Update Python dependencies
pip install -r requirements-dev.txt
pip install -r api/requirements.txt
pip install -r pipelines/airflow_config/requirements.txt

# Pull latest Docker images
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml pull
```

## Troubleshooting

### Port Conflicts

**Error:** `Bind for 0.0.0.0:9000 failed: port is already allocated`

**Solution:**
```bash
# Check what's using the port
lsof -i :9000

# Kill the process or change port in docker-compose.dev.yml
```

### Docker Not Running

**Error:** `Cannot connect to the Docker daemon`

**Solution:**
- Start Docker Desktop
- Wait for it to fully initialize (green icon)
- Try again

### Out of Memory

**Error:** Container exits with OOM error

**Solution:**
- Increase Docker Desktop memory to 12GB+
- Settings → Resources → Memory
- Apply & Restart

### Services Not Healthy

**Error:** Bootstrap script times out waiting for services

**Solution:**
```bash
# Check service logs
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml logs [service-name]

# Common issues:
# - ClickHouse: Need more memory
# - Kafka: Zookeeper not ready, wait longer
# - Airflow: Database init failed, check postgres logs
```

### ClickHouse Permission Denied

**Error:** `DB::Exception: Cannot open file, Permission denied`

**Solution:**
```bash
# Reset ClickHouse volume
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml down -v
docker volume rm oracul_clickhouse_data
docker-compose -f docker-compose.dev.yml up -d clickhouse-server
```

### Kafka Topics Not Created

**Error:** Topics don't exist when running tests

**Solution:**
```bash
# Check kafka-init logs
cd infra/docker-compose
docker-compose -f docker-compose.dev.yml logs kafka-init

# Manually re-run init
docker-compose -f docker-compose.dev.yml up kafka-init
```

### Airflow Webserver Won't Start

**Error:** Airflow webserver is unhealthy

**Solution:**
```bash
# Check if airflow-init completed
docker-compose -f docker-compose.dev.yml logs airflow-init

# Check webserver logs
docker-compose -f docker-compose.dev.yml logs airflow-webserver

# Restart airflow services
docker-compose -f docker-compose.dev.yml restart airflow-init airflow-webserver airflow-scheduler
```

### Pre-commit Hooks Failing

**Error:** `black`, `isort`, or `flake8` errors

**Solution:**
```bash
# Auto-fix formatting issues
black .
isort .

# Check what's wrong
flake8 .

# Skip hooks temporarily (not recommended)
git commit --no-verify -m "message"
```

## Next Steps

Now that your environment is set up, you can:

1. **Explore the codebase:**
   - Read [CLAUDE.md](CLAUDE.md) for project guidelines
   - Review [docs/architecture/](docs/architecture/) for system design
   - Check [docs/product/](docs/product/) for requirements

2. **Phase 1 is complete, but limited:**
   - No ingestion collectors yet (Phase 2)
   - No ClickHouse tables yet (Phase 2-3)
   - No DAGs yet (Phase 3)
   - No anomaly detection yet (Phase 4)

3. **What you CAN do in Phase 1:**
   - Explore Airflow UI
   - Query ClickHouse (database exists, no tables)
   - Test Kafka producers/consumers
   - Create test dashboards in Metabase
   - Write and run tests

4. **Contribute:**
   - Pick a task from Phase 2 roadmap
   - Create a feature branch
   - Write code with tests
   - Submit a pull request

## Getting Help

- **Documentation:** [docs/](docs/) directory
- **Runbooks:** [docs/runbooks/](docs/runbooks/)
- **Issues:** Create a GitHub issue
- **Team:** Ask in #oracul-dev Slack channel

---

**Ready to build?** Your development environment is now fully operational. Happy coding! 🚀
