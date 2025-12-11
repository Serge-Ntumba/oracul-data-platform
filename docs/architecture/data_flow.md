# Oracul Data Flow Documentation

## Overview

This document describes how data flows through the Oracul Blockchain Data Platform, from external sources to end-user consumption. The platform follows a layered architecture with clear separation between ingestion, storage, transformation, and serving.

---

## 1. Data Sources

### 1.1 On-Chain Data (Ethereum RPC)

**Source:** Ethereum mainnet via RPC provider (Alchemy/Infura)

**Data extracted:**
- **Blocks:** block number, hash, parent hash, timestamp, miner, transaction count
- **Transactions:** hash, from/to addresses, value, gas price, gas used, nonce, status, input data
- **Logs:** contract address, topics (0-3), data payload, log index

**Characteristics:**
- Near real-time ingestion with ≤5 minute lag target
- Sequential block processing with resume capability
- Deduplication on `(chain, tx_hash)` and `(chain, tx_hash, log_index)`

### 1.2 Market Data (Price APIs)

**Source:** CoinGecko / CEX spot price APIs

**Data extracted:**
- Symbol (ETH, USDC, etc.)
- Price in USD
- Source identifier
- Timestamp

**Characteristics:**
- Polling frequency: every 1 minute
- Coverage: ETH + top N tokens by volume (configurable list)

---

## 2. Ingestion Layer

### 2.1 Collector Services

Three Python collector services handle data extraction:

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  block_scanner  │     │ tx_and_logs_scanner  │     │ price_collector │
└────────┬────────┘     └──────────┬───────────┘     └────────┬────────┘
         │                         │                          │
         ▼                         ▼                          ▼
   eth.blocks.raw          eth.transactions.raw         market.prices.raw
                           eth.logs.raw
```

**block_scanner:**
- Polls RPC for new blocks
- Extracts block headers and metadata
- Maintains cursor state for resumption
- Implements retry logic with exponential backoff

**tx_and_logs_scanner:**
- Fetches full transaction details per block
- Retrieves transaction receipts for logs
- Handles batch requests for efficiency

**price_collector:**
- Polls price APIs at configured intervals
- Normalizes responses across different sources
- Handles API rate limits and failures

### 2.2 Message Flow to Kafka

All collectors emit messages to dedicated Kafka topics:

| Topic | Content | Key |
|-------|---------|-----|
| `eth.blocks.raw` | Block headers | `chain:block_number` |
| `eth.transactions.raw` | Transaction data | `chain:tx_hash` |
| `eth.logs.raw` | Event logs | `chain:tx_hash:log_index` |
| `market.prices.raw` | Price ticks | `symbol:source` |

**Message format:** JSON with schema versioning for forward compatibility.

---

## 3. Storage Layer (ClickHouse)

### 3.1 Raw Tables

Kafka consumers load data into raw ClickHouse tables with minimal transformation:

```
Kafka Topics                    ClickHouse Raw Tables
─────────────                   ─────────────────────
eth.blocks.raw        ───►      raw_blocks
eth.transactions.raw  ───►      raw_transactions
eth.logs.raw          ───►      raw_logs
market.prices.raw     ───►      prices_spot
```

**Partitioning strategy:** All raw tables partitioned by `toDate(timestamp)` for efficient time-range queries and retention management.

**Key fields preserved:**
- Chain identifier for multi-chain readiness
- Original timestamps for audit trail
- Raw JSON payloads (optional) for reprocessing

### 3.2 Data Retention

Raw data retained based on configurable policies:
- Hot tier: 90 days (fast SSD storage)
- Warm tier: 1 year (standard storage)
- Archive: Beyond 1 year (compressed, slower access)

---

## 4. Transformation Layer (Airflow DAGs)

### 4.1 Normalization Flow

**DAG:** `normalize_erc20_dag`
**Schedule:** Every 15 minutes
**Purpose:** Transform raw logs into structured ERC-20 transfer records

```
raw_logs
    │
    ▼
┌───────────────────────────────────┐
│  Filter: topic0 == Transfer sig   │
│  Decode: from, to, value          │
│  Enrich: symbol lookup            │
└───────────────────────────────────┘
    │
    ▼
erc20_transfers
```

**Processing logic:**
1. Query `raw_logs` for unprocessed records (watermark-based)
2. Filter for ERC-20 Transfer event signature (`0xddf252ad...`)
3. Decode `from_address` and `to_address` from topics
4. Decode `value` from data field
5. Convert raw amount to decimal using token decimals
6. Insert into `erc20_transfers` with idempotency checks

### 4.2 Aggregation Flows

**DAG:** `token_metrics_daily_dag`
**Schedule:** Daily at 01:00 UTC
**Purpose:** Compute daily token-level metrics

```
erc20_transfers + prices_spot
    │
    ▼
┌─────────────────────────────────────┐
│  GROUP BY: chain, token, date       │
│  COMPUTE:                           │
│    - volume_in/out (raw + USD)      │
│    - tx_count                       │
│    - unique_senders/receivers       │
│    - price OHLC                     │
└─────────────────────────────────────┘
    │
    ▼
token_metrics_daily
```

---

**DAG:** `address_flows_daily_dag`
**Schedule:** Daily at 01:30 UTC
**Purpose:** Compute daily address-level flow metrics

```
erc20_transfers + prices_spot
    │
    ▼
┌─────────────────────────────────────┐
│  GROUP BY: chain, address, date     │
│  COMPUTE:                           │
│    - inflow/outflow (raw + USD)     │
│    - net_flow                       │
│    - tx_count                       │
│    - counterparties_count           │
└─────────────────────────────────────┘
    │
    ▼
address_flows_daily
```

### 4.3 Anomaly Detection Flow

**DAG:** `anomaly_detection_dag`
**Schedule:** Daily at 02:00 UTC
**Purpose:** Identify anomalous token and address behaviors

```
token_metrics_daily + address_flows_daily
    │
    ▼
┌─────────────────────────────────────────────┐
│  METHODS:                                   │
│    1. Z-score (rolling 60-day baseline)     │
│    2. IQR (outlier detection)               │
│    3. IsolationForest (multi-feature)       │
│                                             │
│  THRESHOLDS:                                │
│    - |z| >= 3 → anomaly                     │
│    - Outside [Q1-k*IQR, Q3+k*IQR] → anomaly │
│    - IF score > threshold → anomaly         │
└─────────────────────────────────────────────┘
    │
    ▼
anomalies
```

**Entity types processed:**
- **Tokens:** daily_volume_usd, unique_addresses_total
- **Addresses:** daily_net_flow_usd (for top N addresses)

**Severity classification:**
- `low`: Minor deviation, informational
- `medium`: Notable deviation, review recommended
- `high`: Significant deviation, triggers alert

### 4.4 Data Quality Flow

**DAG:** `data_quality_dag`
**Schedule:** Hourly
**Purpose:** Validate data freshness, completeness, and integrity

```
All tables
    │
    ▼
┌─────────────────────────────────────┐
│  CHECKS:                            │
│    - Block freshness vs chain tip   │
│    - Block number gaps              │
│    - Duplicate transaction hashes   │
│    - Row count ratios (raw:curated) │
└─────────────────────────────────────┘
    │
    ▼
data_quality_checks
    │
    ├──► Pass: Log result
    └──► Fail: Trigger alert
```

---

## 5. Serving Layer

### 5.1 BI Dashboards (Superset/Metabase)

**Data flow:** Direct SQL queries to ClickHouse

```
ClickHouse
    │
    ▼
┌─────────────────────────────┐
│  BI Tool Query Layer        │
│  - Cached aggregations      │
│  - Pre-built views          │
└─────────────────────────────┘
    │
    ▼
Dashboard Visualizations
```

**Available dashboards:**
- Overview: Total volume, anomaly counts, top movers
- Token Drilldown: Time series metrics, anomaly overlay
- Address Drilldown: Flow analysis, counterparty breakdown

### 5.2 REST API (FastAPI)

**Data flow:** API queries ClickHouse, returns JSON

```
Client Request
    │
    ▼
┌─────────────────────────────┐
│  FastAPI Endpoints          │
│  - /tokens/{addr}/metrics   │
│  - /anomalies               │
│  - /health                  │
└─────────────────────────────┘
    │
    ▼
ClickHouse Query
    │
    ▼
JSON Response
```

**Response caching:** Short TTL caching for frequently accessed endpoints.

### 5.3 Alerting

**Data flow:** Airflow tasks emit alerts on conditions

```
anomaly_detection_dag                    data_quality_dag
         │                                      │
         ▼                                      ▼
┌─────────────────┐                  ┌─────────────────┐
│ severity='high' │                  │ status='fail'   │
└────────┬────────┘                  └────────┬────────┘
         │                                    │
         └──────────────┬─────────────────────┘
                        ▼
              ┌─────────────────┐
              │  Alert Service  │
              │  (Slack/TG)     │
              └─────────────────┘
```

**Alert types:**
- **Pipeline alerts:** DAG failures, data quality failures, ingestion lag
- **Anomaly alerts:** High-severity anomalies (rate-limited to avoid spam)

---

## 6. Data Lineage Summary

```
                                    DATA LINEAGE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SOURCES              INGESTION           RAW              CURATED
───────              ─────────           ───              ───────
Ethereum RPC    ──►  block_scanner  ──►  raw_blocks
                ──►  tx_logs_scan   ──►  raw_transactions
                                    ──►  raw_logs      ──►  erc20_transfers
Price APIs      ──►  price_collect  ──►  prices_spot


CURATED              AGGREGATED                DERIVED
───────              ──────────                ───────
erc20_transfers ──►  token_metrics_daily  ──►  anomalies
                ──►  address_flows_daily  ──►  anomalies
prices_spot     ──►  (joins for USD conv)

All tables      ──►  data_quality_checks


DERIVED              SERVING
───────              ───────
anomalies       ──►  BI Dashboards
                ──►  REST API
                ──►  Alerts (high severity)

token_metrics   ──►  BI Dashboards
                ──►  REST API

address_flows   ──►  BI Dashboards
                ──►  REST API

data_quality    ──►  Engineering Dashboard
                ──►  Alerts (on failure)
```

---

## 7. Latency Expectations

| Stage | Target Latency |
|-------|----------------|
| Source → Kafka | ≤ 5 minutes |
| Kafka → Raw Tables | < 1 minute |
| Raw → Curated (ERC-20) | ≤ 15 minutes |
| Curated → Aggregates | Daily batch (by 01:30 UTC) |
| Aggregates → Anomalies | Daily batch (by 02:30 UTC) |
| Query response (BI/API) | < 5 seconds |

---

## 8. Failure Handling

### Ingestion Failures
- Collectors maintain cursor state in persistent storage
- On restart, resume from last successfully processed block
- Kafka provides replay capability for consumer failures

### Transformation Failures
- Airflow DAGs configured with retries (3 attempts, exponential backoff)
- Idempotent operations prevent duplicate data on reruns
- Failure alerts sent to Slack/Telegram

### Query Failures
- API implements circuit breaker pattern
- BI tools configured with query timeouts
- Graceful degradation with cached results where available
