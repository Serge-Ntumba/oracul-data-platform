# Oracul Blockchain Data Platform – Roadmap & Execution Plan (v1)

Owner: Principal Data Platform Architect  
Status: Draft – to be agreed by Data Platform / DevOps / DS/DA leads

This roadmap is based on the PRD for **Oracul Blockchain Data Platform v1**.  
Target outcome: a production-ready MVP that ingests Ethereum on-chain + spot price data, builds ERC-20 level metrics, runs anomaly detection, and exposes data via BI + internal API + alerts.

---

## 0. Principles & Expectations

- **Single source of truth**: This document + PRD define *what* we build.  
- **Thin orchestration, thick components**: Airflow DAGs should just orchestrate; business logic lives in libs/jobs.
- **Everything as code**: Infra, schemas, migrations, configs, DAGs – all in Git.
- **Minimal surprises**: If something is unclear, first check PRD + roadmap; then propose a concrete solution in a PR, not a vague question.

---

## 1. High-Level Phases

1. **Phase 0 – Repo & Foundations (Week 1)**
2. **Phase 1 – Core Infra & Local Dev Environment (Weeks 1–2)**
3. **Phase 2 – Ingestion: On-chain + Prices (Weeks 3–4)**
4. **Phase 3 – DWH Modeling & ETL (Weeks 5–6)**
5. **Phase 4 – Anomaly Detection & Serving (Weeks 7–8)**
6. **Phase 5 – Backfill, Hardening & Performance (Weeks 9–10)**

Weeks are indicative; we optimize once we know actual capacity.

---

## 2. Phase 0 – Repo & Foundations (Week 1)

**Goal:** Create the mono-repo and basic scaffolding so every team works in a consistent structure.

### 2.1. Tasks

1. **Create repo and top-level structure**
   - Location: `oracul-platform/`
   - Structure: as defined in architecture docs:
     - `infra/`, `config/`, `dwh/`, `ingestion/`, `pipelines/`, `api/`, `analytics/`, `docs/`, `scripts/`, `tests/`.
   - Include initial `.gitignore`, `README.md`.

2. **Add docs**
   - `docs/product/PRD_oracul_platform_v1.md` – copy our PRD.
   - `docs/product/roadmap.md` – this file.
   - `docs/architecture/high_level_overview.md` – short 1–2 page summary of the pipeline.
   - `docs/adr/0001_use_clickhouse.md` and `0002_use_kafka.md` and `0003_use_airflow.md`.

3. **Basic tooling**
   - Python `pyproject.toml` or `requirements.txt` for:
     - ingestion
     - pipelines
     - api
   - Pre-commit hooks:
     - `black`, `isort`, `flake8` (or `ruff`), and `mypy` if we use typing.

4. **CI skeleton**
   - Github Actions / GitLab CI:
     - 1 workflow: `ci.yml` that:
       - installs deps
       - runs linters
       - runs unit tests (even if empty at start)

### 2.2. Roles

- **Lead:** Principal Data Platform Architect  
- **Support:** 1 Senior Data Engineer, 1 DevOps engineer

### 2.3. Definition of Done (DoD)

- Repo exists with agreed folder structure.
- PRD + Roadmap checked into `docs/`.
- Basic CI pipeline runs on every PR (lint + basic tests).
- No infra or data logic yet, just skeleton.

---

## 3. Phase 1 – Core Infra & Local Dev Environment (Weeks 1–2)

**Goal:** Any engineer can run the full stack locally with `docker-compose` and connect to ClickHouse & Airflow.

### 3.1. Tasks

1. **Docker Compose for local**
   - Under `infra/docker-compose/`:
     - `docker-compose.dev.yml` with services:
       - `clickhouse-server`
       - `zookeeper`
       - `kafka`
       - `airflow` (webserver, scheduler, worker, flower, postgres)
       - `fastapi-api` (will be stub at this phase)
       - `metabase` or `superset` (choose one)
     - Provide `.env.example` for local env variables.

2. **ClickHouse base setup**
   - Add base config in `config/base/clickhouse.yml`.
   - Confirm:
     - CLI / HTTP endpoint is reachable from host.
   - (Schema creation will come in Phase 3.)

3. **Kafka base setup**
   - Define topics (at least):
     - `eth.blocks.raw`
     - `eth.transactions.raw`
     - `eth.logs.raw`
     - `market.prices.raw`
   - For now, simple 1 partition, 1 replication in local.

4. **Airflow base setup**
   - Place DAGs folder to mount from `pipelines/dags/`.
   - Add `airflow_config/` with:
     - `airflow.cfg`
     - `requirements.txt`
   - Create a `dummy_dag.py` in `pipelines/dags/` to confirm scheduling.

5. **BI Tool base setup**
   - Choose **Metabase** or **Superset** (decision in ADR).
   - Connect it to ClickHouse; verify simple query works (e.g., `SELECT 1`).

6. **Dev convenience scripts**
   - `scripts/bootstrap_dev.sh`:
     - Bring up docker-compose
     - Run necessary init commands (e.g. create topics, simple tables)
   - `scripts/run_tests.sh`:
     - Run all tests for CI & dev.

### 3.2. Roles

- **Lead:** DevOps Engineer  
- **Support:** 1–2 Data Engineers

### 3.3. DoD

- Single command (`bootstrap_dev.sh` or `docker-compose up`) starts:
  - ClickHouse
  - Kafka
  - Airflow
  - BI tool
- Airflow web UI accessible.
- BI tool can query ClickHouse.
- Kafka topics exist and can be listed.

---

## 4. Phase 2 – Ingestion: On-chain + Prices (Weeks 3–4)

**Goal:** Collect raw Ethereum blocks, transactions, logs, and spot prices into ClickHouse raw tables via Kafka.

### 4.1. Preparation

- Confirm RPC provider and credentials (Alchemy/Infura/etc).
- Fill `config/chains.yml` with `eth_mainnet` parameters.
- Fill `config/base/kafka.yml` and `config/base/tokens.yml` (for tracked tokens).

### 4.2. Tasks

#### 4.2.1. ClickHouse raw schemas

In `dwh/schemas/raw/`:

- `raw_blocks.sql`
- `raw_transactions.sql`
- `raw_logs.sql`
- `prices_spot.sql`

Add corresponding migration files under `dwh/migrations/0001_*.sql`.

#### 4.2.2. Ingestion common library

Under `ingestion/common/`:

- `config.py` – read from `config/base/*.yml` + env variables.
- `kafka_client.py` – wrapper around Kafka producer (sync or async).
- `logging.py` – standard structured logs.
- `state_store.py` – store/read last processed block height:
  - Implementation v1: ClickHouse meta table or local file.

#### 4.2.3. Ethereum collectors

Under `ingestion/chains/eth_mainnet/`:

- `block_scanner.py`:
  - Uses `web3.py` and RPC provider.
  - Loops from `last_processed_block + 1` to `current_head - N_confirmations`.
  - For each block:
    - Fetch via `eth_getBlockByNumber`.
    - Publish to `eth.blocks.raw`.

- `tx_receipt_scanner.py` (option A – direct from blocks) or `tx_scanner.py + log_scanner.py`:
  - For each block:
    - For each transaction hash:
      - Get full tx and receipt.
      - Send tx to `eth.transactions.raw`.
      - For each log, send to `eth.logs.raw`.

Design decision: keep v1 simple (one service that does both tx + logs).

**Important behavior:**

- Retry with exponential backoff on RPC errors.
- Stop gracefully and persist last processed block height frequently.
- Expose metrics (e.g., to logs) showing progress: `blocks/sec`, `current_block`, etc.

#### 4.2.4. Price collector

Under `ingestion/market_data/price_collector.py`:

- Query price API (e.g. CoinGecko) every minute.
- For each symbol (ETH + few stablecoins + top N tokens):
  - Write message to `market.prices.raw`.

#### 4.2.5. Kafka → ClickHouse loader(s)

We have two options; for MVP, we go with **Python consumers**.

Under `pipelines/jobs/ingestion/` (create folder if missing):

- `kafka_to_clickhouse_blocks.py`
- `kafka_to_clickhouse_txs.py`
- `kafka_to_clickhouse_logs.py`
- `kafka_to_clickhouse_prices.py`

These scripts:

- Read from corresponding topics.
- Buffer messages in batches (e.g. 1k / 10k).
- Insert into raw ClickHouse tables via HTTP/driver.
- Commit offsets only after successful insert.

We can wrap them in long-running processes (deployed alongside Kafka).

### 4.3. Monitoring / logging basics

- Each collector logs:
  - `chain`, `from_block`, `to_block`, `blocks_processed`, `errors`.
- Each loader logs:
  - `topic`, `batch_size`, `insert_duration`.

(Full Prometheus integration can come in Phase 5.)

### 4.4. DoD

- In local/dev environment:
  - `raw_blocks`, `raw_transactions`, `raw_logs`, `prices_spot` populated with live data for ETH mainnet and prices.
- Lag vs latest block:
  - In steady state: <= **5 minutes** in dev (depends on RPC limits).
- No unbounded growth of collector errors (they recover on transient issues).

---

## 5. Phase 3 – DWH Modeling & ETL (Weeks 5–6)

**Goal:** Transform raw data into curated ERC-20 transfers and daily metrics for tokens and addresses.

### 5.1. ERC-20 normalization

#### 5.1.1. Schema

In `dwh/schemas/curated/erc20_transfers.sql`:

- As per PRD (fields: chain, block_number, tx_hash, log_index, token_address, from_address, to_address, amount_raw, amount_decimal, symbol, timestamp).

Add migration `0002_add_erc20_transfers.sql`.

#### 5.1.2. Normalization job

Under `pipelines/jobs/normalization/normalize_erc20.py`:

- Query `raw_logs` for:
  - `topic0 = ERC20_TRANSFER_SIGNATURE`.
- Decode:
  - `from_address`, `to_address`, `value` from topics/data.
- Join with `tokens` metadata for decimals and symbol:
  - from `dwh/seeds/erc20_token_metadata.csv` or the `tokens` table if we materialize it.
- Insert into `erc20_transfers`.

**Important:** Support range-based processing:
- Input: `from_block`, `to_block` or `from_ts`, `to_ts`.
- Use ClickHouse queries with filters on block_number / timestamp.

#### 5.1.3. Airflow DAG

`pipelines/dags/normalize_erc20_dag.py`:

- Schedule: every 15 minutes.
- Logic:
  - Determine last normalized block or timestamp.
  - Call `normalize_erc20.run(from_block, to_block)`.
- Idempotency:
  - Either:
    - Delete & reinsert range, or
    - Use `INSERT ... ON CONFLICT` style semantics (ClickHouse may need workaround using ReplacingMergeTree).

### 5.2. Daily metrics – tokens

#### 5.2.1. Schema

`dwh/schemas/marts/token_metrics_daily.sql`:

- As per PRD (date, chain, token_address, symbol, volume_in/out_raw/usd, tx_count, unique addresses, price OHLC).

Add migration `0003_add_token_metrics_daily.sql`.

#### 5.2.2. Aggregation job

Under `pipelines/jobs/aggregates/compute_token_metrics_daily.py`:

- Input: date `D` (previous day for production).
- Steps:
  1. Filter `erc20_transfers` where `timestamp` in `[D, D+1)`.
  2. Group by `token_address` (and chain).
  3. Compute:
     - sum of amounts in/out (raw and converted to USD via `prices_spot`).
     - count transactions.
     - count unique addresses (senders + receivers).
  4. Compute daily price OHLC from `prices_spot`.

#### 5.2.3. Airflow DAG

`pipelines/dags/token_metrics_daily_dag.py`:

- Schedule: daily 01:00 UTC.
- Steps:
  - For yesterday’s date:
    - Run `compute_token_metrics_daily(date=D)`.
- Insert or upsert into `token_metrics_daily`.

### 5.3. Daily metrics – addresses

#### 5.3.1. Schema

`dwh/schemas/marts/address_flows_daily.sql`:

- As per PRD (date, chain, address, inflow/outflow/net_flow, tx_count, counterparties_count, optionally per token).

Add migration `0004_add_address_flows_daily.sql`.

#### 5.3.2. Aggregation job

`pipelines/jobs/aggregates/compute_address_flows_daily.py`:

- Input: date `D`.
- For each address:
  - Sum incoming/outgoing amounts.
  - Compute net_flow.
  - Count txs and distinct counterparties.

#### 5.3.3. DAG

`pipelines/dags/address_flows_daily_dag.py`:

- Schedule: daily 01:30 UTC.
- Steps:
  - Run address aggregation for date D (yesterday).

### 5.4. Data quality DAG

`pipelines/dags/data_quality_dag.py` and `jobs/dq/` helpers:

- Checks (minimal for v1):
  - Latest block in `raw_blocks` not older than X minutes from chain tip.
  - No gaps in `block_number` in the last N blocks.
  - No duplicate `tx_hash` in `raw_transactions`.
  - Optional: ratio checks between raw and curated (e.g. number of ERC-20 logs vs tx count).

- Writes results to `data_quality_checks` table.

### 5.5. DoD

- `erc20_transfers` populated with data and consistent with random on-chain spot checks.
- `token_metrics_daily` and `address_flows_daily` have correct numbers for selected tokens/addresses (verify manually for some cases).
- Data quality DAG runs hourly and produces passes/fails in `data_quality_checks`.

---

## 6. Phase 4 – Anomaly Detection & Serving (Weeks 7–8)

**Goal:** Implement anomaly detection over daily metrics, and expose results to BI, API, and alerts.

### 6.1. Anomaly Detection

#### 6.1.1. Schema (already defined)

- `anomalies` table exists from `dwh/schemas/meta/anomalies.sql`.

#### 6.1.2. Detection logic

Under `pipelines/libs/anomaly_utils.py`:

- Implement:
  - `compute_zscore(values)`
  - `compute_iqr_bounds(values, k)`
  - helpers for severity scoring.

Under `pipelines/jobs/anomalies/`:

- `detect_token_volume_anomalies.py`
- `detect_address_flow_anomalies.py`

Token anomalies:

- For each token:
  - Take last N days (e.g. 60) of `daily_volume_usd`, `unique_addresses`.
  - Compute baseline mean/median + std + IQR.
  - If yesterday’s value > threshold:
    - Save anomaly row.

Address anomalies:

- For top-N addresses (by volume or net_flow):
  - Similar z-score / IQR logic on `net_flow_usd`.

Optional: a simple **IsolationForest** model for tokens (if DS capacity is available).

#### 6.1.3. DAG

`pipelines/dags/anomaly_detection_dag.py`:

- Schedule: daily 02:00 UTC (after daily metrics).
- Steps:
  1. Run token anomalies detection.
  2. Run address anomalies detection.
  3. Write results into `anomalies`.

### 6.2. API (FastAPI)

#### 6.2.1. Endpoints

Under `api/app/routes/`:

1. `health.py`:
   - `GET /health`
   - Returns:
     - `latest_block_number`
     - `latest_block_timestamp`
     - status of last DAG runs (read from Airflow meta or log table).

2. `tokens.py`:
   - `GET /tokens/{token_address}/metrics/daily?from=&to=`
   - Reads from `token_metrics_daily`.

3. `anomalies.py`:
   - `GET /anomalies`
   - Query params:
     - `entity_type` (`token` / `address`, optional)
     - `entity_id` (address or token, optional)
     - `from`, `to`
     - `min_severity`
   - Reads from `anomalies`.

Implement `services/clickhouse_service.py` for DB interaction.

#### 6.2.2. Tests

Under `api/tests/`:

- Test each endpoint:
  - Schema validation of responses.
  - At least 1 test hitting real ClickHouse in dev with sample data (or use fixtures).

### 6.3. BI Dashboards

In chosen BI tool (Metabase/Superset):

1. **Overview Dashboard**
   - Cards:
     - `# anomalies last 7 days (by severity)`.
     - `# tokens with anomalies yesterday`.
     - `# addresses with anomalies yesterday`.
   - Charts:
     - Daily token volume (top N tokens).
     - Bar chart of anomalies per day.

2. **Token Detail Dashboard**
   - Filter by token.
   - Time-series of `daily_volume_usd` with anomaly markers.
   - Table of recent anomalies for the token.

3. **Address Detail Dashboard**
   - Filter by address.
   - Time-series of net_flow.
   - Table of anomalies.

### 6.4. Alerts

Add a minimal alert module:

- `pipelines/libs/alerting.py`:
  - `send_slack_message(channel, text)` or `send_telegram_message(chat_id, text)`.

Wire into:

- `anomaly_detection_dag`:
  - After writing anomalies:
    - Query `anomalies` with `severity = 'high'` for yesterday.
    - If > 0:
      - Send a nicely formatted summary.

- `data_quality_dag`:
  - Any `status = 'fail'` triggers a separate alert.

### 6.5. DoD

- `anomalies` table populated daily.
- `/anomalies` endpoint returns correct data.
- Overview dashboard shows anomalies matching `anomalies` table.
- Alerts appear in Slack/Telegram when:
  - Pipeline fails,
  - New high severity anomalies appear.

---

## 7. Phase 5 – Backfill, Hardening & Performance (Weeks 9–10)

**Goal:** Backfill past data, improve performance & robustness, and prepare for production usage.

### 7.1. Backfill

Tasks:

1. Decide **backfill window** (e.g. last 90 days, 180 days).
2. Implement backfill scripts under `scripts/`:
   - `backfill_erc20.py`:
     - Runs normalization for historical ranges in batches of block_number or date.
   - `backfill_daily_metrics.py`:
     - Re-runs daily jobs for historical dates.

3. Run backfill in dev/staging:
   - Monitor ClickHouse disk usage and performance.

### 7.2. Performance tuning

Tasks:

- ClickHouse:
  - Add appropriate `ORDER BY` (primary keys) and `PARTITION BY` for each table.
  - Add sampling indexes if needed.
  - Tune `max_threads`, `max_memory_usage`, etc. (with tests).

- Kafka & ingestion:
  - Adjust batch sizes and flush intervals to balance ingestion speed vs ClickHouse load.

- Anomaly jobs:
  - Ensure they run within target window (e.g. < 10 minutes).

### 7.3. Reliability & Observability

Tasks:

- Add proper monitoring:
  - Prometheus exporters for:
    - ingestion services,
    - Airflow,
    - ClickHouse.
  - Grafana dashboards for:
    - ingestion lag,
    - DAG failures,
    - ClickHouse query latencies.

- Write runbooks in `docs/runbooks/`:
  - `oncall_playbook.md` – what to do when ingestion stops, when anomaly DAG fails, etc.
  - `how_to_backfill_data.md`
  - `how_to_add_new_chain.md` (template workflow).

### 7.4. Hardening

Tasks:

- Security checks:
  - Restrict ClickHouse and Kafka to internal network.
  - Ensure API is not exposed publicly for MVP.
- Access control:
  - Create read-only users for BI / analysts.
  - Enforce environment separation (dev/stage/prod).

### 7.5. DoD

- Historical data loaded for agreed range.
- Main dashboards show coherent historical trends (no monstrous gaps).
- All DAGs complete within expected time.
- Monitoring dashboards exist and are useful.
- Runbooks describe concrete procedures for common issues.

---

## 8. Execution & Collaboration Rules

To avoid ambiguity & noise:

1. **Branching model**
   - `main` – stable code, always deployable.
   - `develop` – integration branch (optional).
   - Feature branches: `feature/<area>/<short-name>`, e.g. `feature/ingestion/eth-block-scanner`.

2. **PR rules**
   - Every non-trivial change:
     - Has a PR.
     - Includes basic tests.
     - Updates docs where needed.

3. **Coding rules**
   - Follow folder structure exactly; do not invent random new top-level dirs.
   - Do not put heavy logic directly in DAG files; use `jobs/` and `libs/`.
   - Table names and topic names follow naming patterns defined in PRD & DWH schema folder.

4. **Design changes**
   - Any non-trivial design change:
     - Needs an ADR (`docs/adr/XXXX_*.md`).
     - Needs sign-off from Principal Data Platform Architect or a delegated lead.

5. **Ceremonies**
   - Weekly short sync (max 30 min):
     - Each area lead (Infra, Ingestion, DWH, Anomalies, API/BI) states:
       - what was delivered last week,
       - what’s next week’s scope,
       - blockers.

---

## 9. RACI – Who Owns What (for v1)

- **Infra / DevOps**
  - Own `infra/`, pipeline deployment, monitoring stack.
- **Data Engineers**
  - Own `ingestion/`, `pipelines/`, `dwh/` schemas, ClickHouse tuning.
- **Data Scientists / Quants**
  - Own anomaly detection methods (`pipelines/jobs/anomalies/`, `analytics/` experiments).
- **Data Analysts**
  - Own BI dashboards, metric definitions, business validation.
- **Principal Data Platform Architect**
  - Owns architecture, PRD, roadmap, ADRs, final sign-off on structural changes.

---

End of roadmap.
