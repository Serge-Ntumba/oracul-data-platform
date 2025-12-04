# Component Responsibilities

This document defines the responsibilities, interfaces, and ownership for each component in the Oracul platform.

---

## Table of Contents

1. [Data Source Integrations](#1-data-source-integrations)
2. [Collector Services](#2-collector-services)
3. [Streaming Layer (Kafka)](#3-streaming-layer-kafka)
4. [Storage Layer (ClickHouse)](#4-storage-layer-clickhouse)
5. [Orchestration Layer (Airflow)](#5-orchestration-layer-airflow)
6. [Serving Layer](#6-serving-layer)
7. [Alerting System](#7-alerting-system)
8. [Infrastructure & Monitoring](#8-infrastructure--monitoring)

---

## 1. Data Source Integrations

### 1.1 Ethereum RPC Integration

| Attribute | Details |
|-----------|---------|
| **Purpose** | Provide access to Ethereum blockchain data |
| **Provider** | Alchemy / Infura (TBD) |
| **Data Provided** | Blocks, transactions, transaction receipts, logs |
| **Protocol** | JSON-RPC over HTTPS |
| **Owner** | Data Engineering |

**Responsibilities:**
- Maintain API credentials and access configuration
- Monitor rate limit usage and costs
- Handle provider failover (if secondary configured)
- Document RPC methods used and their parameters

**Interfaces:**
- Input: None (external source)
- Output: JSON-RPC responses consumed by collectors

---

### 1.2 Price API Integration

| Attribute | Details |
|-----------|---------|
| **Purpose** | Provide spot price data for tokens |
| **Provider** | CoinGecko / CEX APIs (TBD) |
| **Data Provided** | Token prices in USD |
| **Protocol** | REST API |
| **Owner** | Data Engineering |

**Responsibilities:**
- Maintain API keys and rate limit compliance
- Define and maintain token list for price tracking
- Handle API response normalization across sources
- Monitor for API deprecations or changes

**Interfaces:**
- Input: None (external source)
- Output: JSON responses consumed by `price_collector`

---

## 2. Collector Services

### 2.1 block_scanner

| Attribute | Details |
|-----------|---------|
| **Purpose** | Ingest Ethereum block headers and metadata |
| **Language** | Python |
| **Deployment** | Containerized service |
| **Owner** | Data Engineering |

**Responsibilities:**
- Poll RPC for new blocks at configured interval
- Extract block-level fields (number, hash, timestamp, miner, tx count)
- Maintain cursor state for resumable ingestion
- Emit block records to `eth.blocks.raw` Kafka topic
- Implement retry logic with exponential backoff
- Expose health metrics (blocks processed, errors, lag)

**Interfaces:**
- Input: Ethereum RPC (JSON-RPC)
- Output: `eth.blocks.raw` Kafka topic
- State: Cursor position in Redis/DB/file

**Configuration:**
```yaml
rpc_url: ${ETH_RPC_URL}
poll_interval_ms: 1000
batch_size: 10
kafka_topic: eth.blocks.raw
state_backend: redis
```

---

### 2.2 tx_and_logs_scanner

| Attribute | Details |
|-----------|---------|
| **Purpose** | Ingest transactions and event logs for each block |
| **Language** | Python |
| **Deployment** | Containerized service |
| **Owner** | Data Engineering |

**Responsibilities:**
- Fetch full transaction data for processed blocks
- Retrieve transaction receipts to extract logs
- Parse and structure transaction fields
- Parse and structure log fields (address, topics, data)
- Emit to `eth.transactions.raw` and `eth.logs.raw` topics
- Handle large blocks with batched requests
- Deduplicate on `(chain, tx_hash)` and `(chain, tx_hash, log_index)`

**Interfaces:**
- Input: Ethereum RPC (JSON-RPC), block numbers from `block_scanner` or independent cursor
- Output: `eth.transactions.raw`, `eth.logs.raw` Kafka topics
- State: Cursor position synchronized with block processing

**Configuration:**
```yaml
rpc_url: ${ETH_RPC_URL}
receipt_batch_size: 100
kafka_topics:
  transactions: eth.transactions.raw
  logs: eth.logs.raw
```

---

### 2.3 price_collector

| Attribute | Details |
|-----------|---------|
| **Purpose** | Collect spot prices for configured tokens |
| **Language** | Python |
| **Deployment** | Containerized service |
| **Owner** | Data Engineering |

**Responsibilities:**
- Poll price APIs at configured frequency (default: 1 minute)
- Normalize responses from different sources
- Emit price records to `market.prices.raw` topic
- Handle API rate limits gracefully
- Support multiple price sources for redundancy

**Interfaces:**
- Input: Price APIs (REST)
- Output: `market.prices.raw` Kafka topic

**Configuration:**
```yaml
sources:
  - name: coingecko
    url: https://api.coingecko.com/api/v3
    api_key: ${COINGECKO_API_KEY}
poll_interval_seconds: 60
tokens:
  - ETH
  - USDC
  - USDT
  # ... configurable list
kafka_topic: market.prices.raw
```

---

## 3. Streaming Layer (Kafka)

### 3.1 Kafka Cluster

| Attribute | Details |
|-----------|---------|
| **Purpose** | Decouple ingestion from storage, enable replay |
| **Deployment** | Managed service or self-hosted cluster |
| **Owner** | Platform/Infrastructure |

**Responsibilities:**
- Provide reliable message delivery between collectors and loaders
- Retain messages for configurable period (replay capability)
- Support consumer group management for parallel loading
- Monitor partition lag and throughput

**Topics Managed:**

| Topic | Partitions | Retention | Key |
|-------|------------|-----------|-----|
| `eth.blocks.raw` | 4 | 7 days | `chain:block_number` |
| `eth.transactions.raw` | 8 | 7 days | `chain:tx_hash` |
| `eth.logs.raw` | 8 | 7 days | `chain:tx_hash:log_index` |
| `market.prices.raw` | 2 | 7 days | `symbol:source` |

---

### 3.2 Kafka Loaders (ClickHouse)

| Attribute | Details |
|-----------|---------|
| **Purpose** | Consume Kafka topics and load into ClickHouse raw tables |
| **Implementation** | ClickHouse Kafka engine or custom consumer |
| **Owner** | Data Engineering |

**Responsibilities:**
- Consume messages from Kafka topics
- Transform to ClickHouse row format
- Insert into corresponding raw tables
- Handle batching for insert efficiency
- Manage consumer offsets for exactly-once semantics
- Monitor consumer lag

**Interfaces:**
- Input: Kafka topics
- Output: ClickHouse raw tables

---

## 4. Storage Layer (ClickHouse)

### 4.1 Raw Tables

| Attribute | Details |
|-----------|---------|
| **Purpose** | Store unprocessed source data |
| **Owner** | Data Engineering |

**Tables & Responsibilities:**

| Table | Source | Key Fields | Partitioning |
|-------|--------|------------|--------------|
| `raw_blocks` | `eth.blocks.raw` | chain, block_number, block_hash, timestamp | `toDate(timestamp)` |
| `raw_transactions` | `eth.transactions.raw` | chain, tx_hash, from_address, to_address, value_wei | `toDate(timestamp)` |
| `raw_logs` | `eth.logs.raw` | chain, tx_hash, log_index, address, topic0-3, data | `toDate(timestamp)` |
| `prices_spot` | `market.prices.raw` | symbol, source, ts, price_usd | `toDate(ts)` |

**Schema Management:**
- Version-controlled DDL scripts
- Migration tooling for schema changes
- Backward-compatible changes preferred

---

### 4.2 Curated Tables

| Attribute | Details |
|-----------|---------|
| **Purpose** | Store normalized, business-ready data |
| **Owner** | Data Engineering |

**Tables & Responsibilities:**

| Table | Purpose | Populated By |
|-------|---------|--------------|
| `erc20_transfers` | Decoded ERC-20 transfer events | `normalize_erc20_dag` |

**`erc20_transfers` Fields:**
- chain, block_number, tx_hash, log_index
- token_address, from_address, to_address
- amount_raw (uint256), amount_decimal (float)
- symbol (optional enrichment)
- timestamp

---

### 4.3 Aggregated Tables

| Attribute | Details |
|-----------|---------|
| **Purpose** | Pre-computed metrics for efficient querying |
| **Owner** | Data Engineering / Analytics Engineering |

**Tables & Responsibilities:**

| Table | Grain | Populated By |
|-------|-------|--------------|
| `token_metrics_daily` | (chain, token_address, date) | `token_metrics_daily_dag` |
| `address_flows_daily` | (chain, address, date) | `address_flows_daily_dag` |

---

### 4.4 Derived Tables

| Attribute | Details |
|-----------|---------|
| **Purpose** | Store analysis outputs (anomalies, quality checks) |
| **Owner** | Data Engineering / Data Science |

**Tables & Responsibilities:**

| Table | Purpose | Populated By |
|-------|---------|--------------|
| `anomalies` | Detected anomalous events | `anomaly_detection_dag` |
| `data_quality_checks` | DQ validation results | `data_quality_dag` |

---

## 5. Orchestration Layer (Airflow)

### 5.1 normalize_erc20_dag

| Attribute | Details |
|-----------|---------|
| **Purpose** | Transform raw logs into ERC-20 transfer records |
| **Schedule** | Every 15 minutes |
| **Owner** | Data Engineering |

**Responsibilities:**
- Identify new records in `raw_logs` since last run
- Filter for ERC-20 Transfer event signature
- Decode from/to addresses and value from topics/data
- Enrich with token symbol (optional mapping table)
- Insert into `erc20_transfers` idempotently
- Update watermark for next run

**Dependencies:** `raw_logs` table populated

---

### 5.2 token_metrics_daily_dag

| Attribute | Details |
|-----------|---------|
| **Purpose** | Compute daily token-level aggregations |
| **Schedule** | Daily at 01:00 UTC |
| **Owner** | Analytics Engineering |

**Responsibilities:**
- Aggregate previous day's `erc20_transfers` by token
- Calculate: volume (raw + USD), tx count, unique addresses
- Join with `prices_spot` for USD conversion
- Upsert into `token_metrics_daily`

**Dependencies:** `erc20_transfers`, `prices_spot`

---

### 5.3 address_flows_daily_dag

| Attribute | Details |
|-----------|---------|
| **Purpose** | Compute daily address-level flow metrics |
| **Schedule** | Daily at 01:30 UTC |
| **Owner** | Analytics Engineering |

**Responsibilities:**
- Aggregate previous day's `erc20_transfers` by address
- Calculate: inflow/outflow, net flow, counterparties
- Join with `prices_spot` for USD conversion
- Upsert into `address_flows_daily`

**Dependencies:** `erc20_transfers`, `prices_spot`

---

### 5.4 anomaly_detection_dag

| Attribute | Details |
|-----------|---------|
| **Purpose** | Identify anomalous token and address behaviors |
| **Schedule** | Daily at 02:00 UTC |
| **Owner** | Data Science / Analytics Engineering |

**Responsibilities:**
- Load rolling window of metrics (e.g., 60 days)
- Apply detection methods:
  - Z-score against rolling baseline
  - IQR outlier detection
  - Isolation Forest multi-feature scoring
- Classify severity (low/medium/high)
- Insert anomaly records into `anomalies` table
- Trigger alerts for high-severity anomalies

**Dependencies:** `token_metrics_daily`, `address_flows_daily`

**Configuration:**
```yaml
lookback_days: 60
zscore_threshold: 3.0
iqr_multiplier: 1.5
isolation_forest:
  contamination: 0.01
  n_estimators: 100
severity_thresholds:
  high: 4.0
  medium: 3.0
  low: 2.0
```

---

### 5.5 data_quality_dag

| Attribute | Details |
|-----------|---------|
| **Purpose** | Validate data freshness, completeness, integrity |
| **Schedule** | Hourly |
| **Owner** | Data Engineering |

**Responsibilities:**
- Check block freshness vs chain tip (max lag threshold)
- Detect gaps in block number sequence
- Identify duplicate transaction hashes
- Validate row count ratios between layers
- Log results to `data_quality_checks`
- Trigger alerts on failures

**Checks Implemented:**

| Check | Threshold | Severity |
|-------|-----------|----------|
| Block freshness | > 10 min lag | FAIL |
| Block gaps | Any gap in last 1000 blocks | FAIL |
| Duplicate tx_hash | Any duplicates | FAIL |
| Raw:Curated ratio | Outside [0.95, 1.05] | WARN |

---

### 5.6 ingestion_monitoring_dag

| Attribute | Details |
|-----------|---------|
| **Purpose** | Monitor health of collector services |
| **Schedule** | Every 5 minutes |
| **Owner** | Data Engineering / Platform |

**Responsibilities:**
- Check collector service health endpoints
- Monitor Kafka consumer lag
- Verify recent records in raw tables
- Alert on collector failures or excessive lag

---

## 6. Serving Layer

### 6.1 BI Dashboards (Superset/Metabase)

| Attribute | Details |
|-----------|---------|
| **Purpose** | Interactive visualization for analysts and stakeholders |
| **Tool** | Superset or Metabase (TBD) |
| **Owner** | Analytics / Data Engineering |

**Responsibilities:**
- Connect to ClickHouse as data source
- Build and maintain dashboards:
  - Overview (volume, anomalies, top movers)
  - Token drilldown (time series, anomaly overlay)
  - Address drilldown (flows, counterparties)
- Manage user access and permissions
- Optimize queries with caching/materialized views

**Dashboards:**

| Dashboard | Primary Users | Refresh |
|-----------|---------------|---------|
| Overview | Business, Ops | Real-time |
| Token Drilldown | Analysts, Quants | Real-time |
| Address Drilldown | Analysts, Risk | Real-time |
| Engineering Health | Data Eng | Real-time |

---

### 6.2 REST API (FastAPI)

| Attribute | Details |
|-----------|---------|
| **Purpose** | Programmatic access to metrics and anomalies |
| **Framework** | FastAPI |
| **Owner** | Data Engineering / Backend |

**Responsibilities:**
- Expose endpoints for key data access patterns
- Query ClickHouse and return JSON responses
- Implement request validation and error handling
- Apply rate limiting for internal fairness
- Provide health/status endpoint

**Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/tokens/{token_address}/metrics/daily` | GET | Daily metrics for a token |
| `/anomalies` | GET | Query anomalies with filters |
| `/health` | GET | System health and status |

**Query Parameters (anomalies):**
- `entity_type`: token / address
- `token_address` / `address`: Filter by entity
- `from`, `to`: Date range
- `min_severity`: low / medium / high

---

## 7. Alerting System

### 7.1 Alert Service

| Attribute | Details |
|-----------|---------|
| **Purpose** | Deliver notifications for anomalies and failures |
| **Channels** | Slack / Telegram (MVP: pick one) |
| **Owner** | Data Engineering / Platform |

**Responsibilities:**
- Receive alert triggers from Airflow tasks
- Format messages appropriately per channel
- Implement rate limiting to prevent spam
- Support different alert streams (pipeline vs anomaly)
- Provide abstraction layer for adding channels

**Alert Types:**

| Type | Source | Recipients | Rate Limit |
|------|--------|------------|------------|
| Pipeline failure | Any DAG failure | #data-alerts | None |
| Data quality failure | `data_quality_dag` | #data-alerts | None |
| Ingestion lag | `ingestion_monitoring_dag` | #data-alerts | 1/hour |
| High-severity anomaly | `anomaly_detection_dag` | #anomaly-alerts | Max N/day |

---

## 8. Infrastructure & Monitoring

### 8.1 Deployment Platform

| Attribute | Details |
|-----------|---------|
| **Purpose** | Host and orchestrate all platform components |
| **Technology** | Docker Compose (dev) / Kubernetes (prod) |
| **Owner** | Platform / DevOps |

**Responsibilities:**
- Containerize all services
- Manage deployment configurations
- Handle scaling and resource allocation
- Implement secrets management
- Configure networking and security groups

---

### 8.2 Monitoring Stack

| Attribute | Details |
|-----------|---------|
| **Purpose** | Observe system health and performance |
| **Technology** | Prometheus + Grafana (preferred) |
| **Owner** | Platform / Data Engineering |

**Responsibilities:**
- Collect metrics from all components
- Build dashboards for key metrics
- Configure alerting rules
- Maintain log aggregation

**Key Metrics:**

| Component | Metrics |
|-----------|---------|
| Collectors | blocks_processed, errors, lag_seconds |
| Kafka | consumer_lag, messages_per_second |
| ClickHouse | query_latency, rows_inserted, storage_used |
| Airflow | dag_success_rate, task_duration |
| API | request_latency, error_rate |

---

## Ownership Summary

| Component | Primary Owner | Secondary |
|-----------|---------------|-----------|
| RPC Integration | Data Engineering | Platform |
| Price Integration | Data Engineering | — |
| Collectors | Data Engineering | — |
| Kafka | Platform | Data Engineering |
| ClickHouse Schema | Data Engineering | Analytics Eng |
| Airflow DAGs | Data Engineering | Analytics Eng |
| Anomaly Logic | Data Science | Analytics Eng |
| BI Dashboards | Analytics | Data Engineering |
| REST API | Data Engineering | Backend |
| Alerting | Data Engineering | Platform |
| Infrastructure | Platform | Data Engineering |
| Monitoring | Platform | Data Engineering |

---

*Document Version: 1.0*  
*Last Updated: MVP Planning Phase*
