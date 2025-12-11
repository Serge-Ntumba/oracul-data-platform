# **1\. Document Info**

* **Product name:** Oracul Blockchain Data Platform (Internal)

* **Owner:** Principal Data Platform Architect

* **Version:** v1.0 (MVP)

* **Status:** Draft → for review

---

# **2\. TL;DR**

Build a **multi-source blockchain analytics and anomaly detection platform** that:

* Ingests **on-chain (EVM)** \+ **market data** in near real-time.

* Stores it in a scalable warehouse (**ClickHouse**).

* Runs scheduled transformations and **anomaly detection** (z-score, IQR, IsolationForest, etc.) using **Airflow \+ Python**.

* Exposes results to:

  * internal users (BI dashboards, SQL),

  * quants/DS (feature tables, anomalies),

  * services (simple API),

  * alerts (Slack/Telegram).

Phase 1 focuses on: **1–2 EVM chains \+ spot price data \+ ERC-20 flows \+ per-token/per-address daily metrics \+ anomaly detection for token volumes and address flows**.

---

# **3\. Background & Problem**

We want to make money and build products on top of **blockchain behavior**:

* Detect suspicious or opportunity-rich patterns (whale moves, hacks, unusual liquidity flows, protocol stress).

* Provide reliable data for:

  * internal trading / risk models,

  * future B2B/B2C products (dashboards, APIs).

Current gap (assumed):

* No single place where **clean, historical, and fresh** on-chain \+ market data lives.

* No robust system for **detecting anomalies** in blockchain metrics.

* Manual or ad-hoc scripts, with poor reproducibility and monitoring.

We need a **proper data platform**.

---

# **4\. Goals & Non-Goals**

### **4.1. Goals (for this MVP)**

1. **Ingest & store**

   * Ingest selected EVM chain blocks/transactions/logs and spot prices in near real-time.

   * Persist raw and curated data in ClickHouse with partitioning & basic retention.

2. **Model & transform**

   * Build **curated tables** for ERC-20 transfers and basic address & token activity.

   * Create **daily aggregated metrics**:

     * per token (volume, tx count, unique addresses),

     * per address (inflow/outflow, balance change, activity).

3. **Detect anomalies**

   * Implement anomaly detection for:

     * token daily volume,

     * token daily active addresses,

     * large abnormal address flows.

   * Use at least:

     * simple statistical methods (z-score, IQR),

     * one ML-ish method (IsolationForest or DBSCAN).

4. **Serve & visualize**

   * Provide:

     * internal BI dashboards,

     * SQL access for DE/DA/DS,

     * simple internal REST API endpoints for key metrics and anomalies,

     * alert notifications for high-severity anomalies.

5. **Reliability & observability**

   * Airflow DAGs with retries & failure alerts.

   * Data quality checks for gaps and duplicates.

   * Basic infrastructure monitoring.

### **4.2. Non-Goals (for v1)**

* Full **multi-chain** coverage (we start with 1–2 chains; multi-chain is v2+).

* Full protocol-level semantics (deep integration per DeFi protocol).

* Complex trading strategy backtesting engine.

* External customer-facing SLA’d API (v1 is internal / alpha).

* Complex role-based access or full governance (basic access control is enough).

---

# **5\. Target Users & Use Cases**

### **5.1. Personas**

1. **Quant / Data Scientist**

   * Needs feature tables and anomaly data to build trading/risk models.

2. **Data Engineer**

   * Builds and maintains ingestion, ETL, and infrastructure.

3. **Data Analyst / Product Analyst**

   * Explores blockchain behavior using SQL/BI tools; prepares reports.

4. **Business / Product Stakeholders**

   * Want dashboards and simple narratives: which tokens/protocols/addresses are “interesting” today?

5. **Operations / Risk**

   * Receive alerts when anomalies indicate hacks, unusual flows, etc.

### **5.2. Key Use Cases (MVP)**

1. **UC1: Token anomaly detection**

   * Question: “Which tokens had abnormal volume or active addresses yesterday?”

   * Flow: pull from `anomalies` table / API or view in dashboard.

2. **UC2: Address anomaly detection**

   * Question: “Which addresses had abnormal inflow/outflow vs their history?”

   * Flow: same.

3. **UC3: Ad-hoc analysis**

   * Analyst/DS queries ClickHouse: “Show last 30 days of ERC-20 transfers for token X across all addresses; group by address to see whales.”

4. **UC4: Daily monitoring**

   * Dashboard summarizes:

     * total volume per token,

     * number of anomalies,

     * top anomalous tokens/addresses.

5. **UC5: Engineering robustness**

   * Engineer wants to see status of:

     * latest ingested block,

     * ingestion lag vs chain tip,

     * data quality metrics.

---

# **6\. Scope & Phasing**

### **6.1. MVP Scope (v1 – 8–12 weeks)**

* Chains: **Ethereum mainnet** (optionally extend to 1 more EVM chain if capacity).

* Tokens: Start with **all ERC-20 transfers**, but optimization can prioritize top N by volume.

* Data sources:

  * On-chain via single RPC provider (Alchemy/Infura/etc.).

  * Market data via 1–2 sources (e.g. CoinGecko / CEX spot).

Core components:

1. Ingestion collectors (Python) → Kafka.

2. Kafka → ClickHouse loaders.

3. ClickHouse schemas (raw → curated → aggregate → anomalies).

4. Airflow DAGs for:

   * normalization,

   * aggregates,

   * anomaly detection,

   * data quality.

5. Simple BI dashboard (Superset/Metabase).

6. Minimal REST API (FastAPI) for 2–3 endpoints.

7. Alerting: Slack/Telegram integration for anomalies & pipeline failures.

### **6.2. Future Scope (not in this PRD)**

* Multi-chain support (Polygon, BSC, L2s).

* Per-protocol metrics (DEX, lending, etc.).

* Real-time streaming features & online inference.

* External API with authentication and quotas.

---

# **7\. High-Level Architecture (Logical)**

1. **Sources**

   * `Ethereum RPC`

   * `Spot price API`

2. **Ingestion**

   * Python collector services:

     * `block_scanner`

     * `tx_and_logs_scanner`

     * `price_collector`

   * Messages → Kafka topics:

     * `eth.blocks.raw`

     * `eth.transactions.raw`

     * `eth.logs.raw`

     * `market.prices.raw`

3. **Storage (ClickHouse)**

   * Raw tables:

     * `raw_blocks`

     * `raw_transactions`

     * `raw_logs`

     * `prices_spot`

   * Curated tables:

     * `erc20_transfers`

   * Aggregated / feature tables:

     * `token_metrics_daily`

     * `address_flows_daily`

   * Derived tables:

     * `anomalies`

     * `data_quality_checks`

4. **Orchestration (Airflow)**

   * DAGs:

     * `ingestion_monitoring_dag`

     * `normalize_erc20_dag`

     * `token_metrics_daily_dag`

     * `address_flows_daily_dag`

     * `anomaly_detection_dag`

     * `data_quality_dag`

5. **Serving**

   * BI (Superset/Metabase) → ClickHouse.

   * REST API (FastAPI) → ClickHouse.

   * Alerts (Slack/Telegram) → from Airflow tasks or separate alert service.

6. **Platform**

   * Deployment via Docker Compose / Kubernetes (depending on env).

   * Monitoring & logging (choice left to platform team, but needed).

---

# **8\. Functional Requirements (Detailed)**

## **8.1. Data Sources & Ingestion**

### **FR-1: Block ingestion**

* The system **must** ingest Ethereum blocks from RPC:

  * Fields: block number, hash, parent hash, timestamp, miner, tx count, etc.

* Max acceptable lag vs latest chain tip (MVP): **≤ 5 minutes** under normal conditions.

* Store raw responses in Kafka and then in ClickHouse `raw_blocks`.

### **FR-2: Transaction & logs ingestion**

* For each block, ingest:

  * All transactions (hash, from, to, value, gas, status, input…).

  * All logs from transaction receipts (log index, address, topics, data).

* Store in Kafka → ClickHouse `raw_transactions` and `raw_logs`.

* Deduplicate based on `(chain, tx_hash)` and `(chain, tx_hash, log_index)`.

### **FR-3: Price ingestion**

* Collect **spot price** data for:

  * ETH and the top N tokens by volume (list configurable).

* Minimum frequency: every **1 minute** (configurable).

* Store in Kafka → ClickHouse `prices_spot`.

### **FR-4: Ingestion robustness**

* Collectors should:

  * Resume from last processed block (state stored in DB/Redis/file).

  * Handle RPC retries and backoff.

  * Emit metrics (processed blocks, errors) to monitoring.

---

## **8.2. Storage & Data Modeling (ClickHouse)**

Note: This PRD defines **logical fields**. Exact types/DDL decided by DEs, but must support scale to billions of rows.

### **FR-5: Raw tables**

1. `raw_blocks`

   * Required fields:

     * chain (e.g. `eth_mainnet`)

     * block\_number

     * block\_hash

     * parent\_hash

     * timestamp

     * miner

     * tx\_count

     * raw\_json (optional)

   * Partitioning: by `toDate(timestamp)`.

2. `raw_transactions`

   * Fields:

     * chain

     * block\_number

     * tx\_index

     * tx\_hash

     * from\_address

     * to\_address

     * value\_wei

     * gas\_price\_wei

     * gas\_used (if available)

     * nonce

     * status (success/fail)

     * input (hex)

     * timestamp

   * Partition: by `toDate(timestamp)`.

3. `raw_logs`

   * Fields:

     * chain

     * block\_number

     * tx\_index

     * log\_index

     * tx\_hash

     * address (contract)

     * topic0..topic3

     * data (hex)

     * timestamp

4. `prices_spot`

   * Fields:

     * symbol (e.g. `ETH`, `USDC`)

     * source (e.g. `coingecko`)

     * ts (timestamp)

     * price\_usd (float)

### **FR-6: ERC-20 transfers table**

`erc20_transfers` (normalized events from raw\_logs):

* Fields:

  * chain

  * block\_number

  * tx\_hash

  * log\_index

  * token\_address

  * from\_address

  * to\_address

  * amount\_raw (integer)

  * amount\_decimal (float)

  * symbol (optional, from mapping)

  * timestamp

* Transfer detection:

  * Topic0 \== standard ERC-20 Transfer signature.

  * Decode `from_address`, `to_address`, `value` from topics/data.

### **FR-7: Daily token metrics**

`token_metrics_daily`:

* Grain: `(chain, token_address, date)`

* Fields:

  * date

  * chain

  * token\_address

  * symbol

  * volume\_in\_raw / volume\_out\_raw (per day)

  * volume\_in\_usd / volume\_out\_usd (using daily avg or close price)

  * tx\_count

  * unique\_senders

  * unique\_receivers

  * unique\_addresses\_total

  * price\_open / price\_close / price\_high / price\_low (optional)

### **FR-8: Daily address flows**

`address_flows_daily`:

* Grain: `(chain, address, date)`

* Fields:

  * date

  * chain

  * address

  * token\_address (or aggregated for all tokens; v1 can start with ETH \+ top N tokens)

  * inflow\_raw / outflow\_raw

  * inflow\_usd / outflow\_usd

  * net\_flow\_raw / net\_flow\_usd

  * tx\_count

  * counterparties\_count

### **FR-9: Anomalies table**

`anomalies`:

* Fields:

  * anomaly\_id (UUID)

  * entity\_type (`token` / `address`)

  * entity\_id (token\_address or address)

  * metric (e.g. `daily_volume_usd`, `daily_net_flow_usd`)

  * ts (the date/time the metric refers to)

  * value (actual metric value)

  * baseline\_mean (or median)

  * baseline\_std (if applicable)

  * score (e.g. z-score, anomaly score)

  * method (`zscore`, `iqr`, `isolation_forest`, etc.)

  * severity (`low` / `medium` / `high`)

  * meta (JSON: additional context, e.g. quantiles, neighbor densities)

### **FR-10: Data quality checks table**

`data_quality_checks`:

* Fields:

  * check\_id

  * check\_name

  * ts

  * status (`pass` / `warn` / `fail`)

  * details (JSON: e.g. expected vs actual block height)

  * affected\_component (e.g. `raw_blocks`, `erc20_transfers`)

---

## **8.3. Orchestration (Airflow DAGs)**

### **FR-11: Normalize ERC-20 DAG**

* Name: `normalize_erc20_dag`

* Schedule: every **15 minutes**.

* Steps:

  1. Identify new `raw_logs` since last run.

  2. Filter ERC-20 Transfer events.

  3. Decode and insert into `erc20_transfers`.

* Idempotency: must safely handle reruns without duplicating transfers.

### **FR-12: Daily token metrics DAG**

* Name: `token_metrics_daily_dag`

* Schedule: daily at **UTC 01:00** (time configurable).

* Steps:

  1. For each token:

     * Aggregate previous day’s transfers to compute required metrics.

  2. Join with `prices_spot` to convert to USD.

  3. Insert/Upsert into `token_metrics_daily`.

### **FR-13: Daily address flows DAG**

* Name: `address_flows_daily_dag`

* Schedule: daily at **UTC 01:30**.

* Steps similar: aggregate `erc20_transfers` by `(address, date)`.

### **FR-14: Anomaly detection DAG**

* Name: `anomaly_detection_dag`

* Schedule: daily at **UTC 02:00** (after aggregates).

* Logic (MVP):

  * For each entity type:

     **Tokens**

    * Take rolling window (e.g. last 60 days) of `daily_volume_usd`, `unique_addresses_total`.

    * Compute z-score for yesterday’s value vs baseline.

    * Mark as anomaly if |z| \>= configured threshold (e.g. 3).

    * Additional IQR-based rule (value outside \[Q1 − k*IQR, Q3 \+ k*IQR\]).

  * **Addresses**

    * For selected addresses (e.g. top N by volume or net\_flow), compute z-score for `daily_net_flow_usd`.

  * Optionally run IsolationForest across features for tokens:

    * features: `[daily_volume_usd, tx_count, unique_addresses, net_flow, etc.]`.

  * Write rows to `anomalies`.

### **FR-15: Data quality DAG**

* Name: `data_quality_dag`

* Schedule: hourly.

* Checks:

  * Latest block in `raw_blocks` is not older than X minutes vs chain tip.

  * No gaps in `block_number` range for last N blocks.

  * No duplicate `tx_hash`.

  * Row counts between raw and curated within expected ratio.

* Results logged to `data_quality_checks`.

* On failure: send alert to Slack/Telegram.

### **FR-16: Ingestion monitoring DAG**

* Name: `ingestion_monitoring_dag`

* Schedule: every 5 minutes.

* Checks:

  * Alive metrics for collector services.

  * Kafka lag (if available).

* On failure: alert.

---

## **8.4. Serving & Interfaces**

### **FR-17: BI Dashboards**

Using Superset / Metabase (choice to DE/DA, but one must be chosen), build at least:

1. **Overview dashboard**

   * Total daily volume per token (top N).

   * Number of anomalies per day by severity.

   * Latest anomalies list (tokens \+ addresses).

2. **Token drilldown**

   * Time series of:

     * volume\_usd,

     * tx\_count,

     * unique addresses.

   * Overlays anomalies points.

   * Table of last N anomalies for that token.

3. **Address drilldown**

   * Time series of address net\_flow\_usd.

   * List of counterparties and flows for anomalous days.

### **FR-18: REST API (FastAPI)**

Minimal endpoints for internal use:

1. `GET /tokens/{token_address}/metrics/daily?from=&to=`

   * Returns daily metrics from `token_metrics_daily`.

2. `GET /anomalies`

   * Query params:

     * entity\_type

     * token\_address / address

     * from, to

     * min\_severity

   * Returns records from `anomalies`.

3. `GET /health`

   * Returns status:

     * latest block\_number & timestamp ingested,

     * whether main DAGs succeeded in last run.

### **FR-19: Alerts**

* Slack or Telegram integration (pick one for MVP, but code should be abstractable).

* Two alert streams:

  * **Pipeline alerts:** DAG failures, dq failures, ingestion lag.

  * **Anomaly alerts:** only `severity = high` anomalies, limited to max N per day (avoid spam).

---

# **9\. Non-Functional Requirements**

### **NFR-1: Performance**

* ClickHouse queries for typical analytics (last 30 days of token metrics across all tokens) should complete in **\< 5 seconds** for interactive use.

* Airflow DAGs must finish within their windows:

  * Daily DAGs complete by **UTC 03:00**.

### **NFR-2: Reliability & Availability**

* MVP target: **99%+** uptime for ingestion and warehouse availability (internal).

* No data loss on single process failure; at most reprocess from Kafka.

### **NFR-3: Scalability**

* Architecture must handle:

  * At least **500M+** `erc20_transfers` rows and grow to multiple billions.

  * Adding new chains should not require major architectural changes (just new collectors \+ tables).

### **NFR-4: Security**

* Access to ClickHouse:

  * Separate roles:

    * `writer` (ETL),

    * `reader` (analytics).

  * Production access only via bastion / VPN.

* API:

  * Internal-only network (no public exposure for MVP).

### **NFR-5: Observability**

* Minimum:

  * Logs for collectors, loaders, and Airflow tasks.

  * Basic metrics:

    * ingestion lag,

    * processed blocks per minute,

    * DAG success/failure counts.

* Prefer integration with Prometheus \+ Grafana if infra supports.

---

# **10\. Rollout & Milestones (Rough)**

This is just a skeleton; PM/EM can refine.

1. **Week 1–2: Foundations**

   * Infra: ClickHouse, Kafka, Airflow, BI, API skeleton.

   * Basic ClickHouse instance with sample data.

2. **Week 3–4: Ingestion (On-chain \+ Prices)**

   * Implement `block_scanner`, `tx_and_logs_scanner`, `price_collector`.

   * Kafka topics & loader into raw tables.

   * Basic monitoring of ingestion.

3. **Week 5–6: Normalization & Aggregates**

   * Implement `normalize_erc20_dag`.

   * Implement `token_metrics_daily_dag` & `address_flows_daily_dag`.

   * Data quality DAG basics.

4. **Week 7–8: Anomalies & Serving**

   * Implement `anomaly_detection_dag` with z-score \+ IQR \+ one advanced method.

   * Build BI dashboards v1.

   * Implement REST API endpoints.

   * Alerts wired for pipeline failures and high-severity anomalies.

5. **Week 9–10: Stabilization**

   * Load test with historical backfill.

   * Fix performance bottlenecks.

   * Improve dashboards and anomaly thresholds with DS/quant feedback.

---

# **11\. Risks & Open Questions**

### **Risks**

* **RPC provider limits**:

  * Rate limits and costs could become constraints.

  * Mitigation: request high-tier plan / caching / batch requests.

* **Data volume explosion**:

  * Full Ethereum logs are huge; may need to filter or prioritize (e.g. ERC-20 only, selective contracts) for MVP.

* **Anomaly noise**

  * Simple methods may generate too many “false positives”.

  * Need iteration on scoring and severity thresholds with DS.

* **Infra complexity**

  * Running Kafka \+ ClickHouse \+ Airflow is non-trivial; need DevOps buy-in and time.

### **Open Questions (to be decided with stakeholders)**

1. Which RPC provider(s) do we use and what SLAs are required?

2. Do we start with **all ERC-20 transfers** or only a curated token list?

3. Exact chains included in MVP:

   * Ethereum only or Ethereum \+ one L2?

4. Preferred BI tool (Superset vs Metabase) and who owns dashboard maintenance?

5. Where do we run this stack (cloud provider / region / on-prem)?
