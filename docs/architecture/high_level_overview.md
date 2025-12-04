# Oracul Platform: High-Level Overview

## What is Oracul?

Oracul is an internal **multi-source blockchain analytics and anomaly detection platform** designed to ingest, process, and analyze on-chain and market data in near real-time. It provides the foundation for detecting suspicious patterns, identifying trading opportunities, and powering data-driven products.

---

## Problem Statement

The organization lacks a centralized, reliable data infrastructure for blockchain analytics:

- **No single source of truth** for clean, historical, and fresh on-chain + market data
- **No systematic anomaly detection** for blockchain metrics
- **Manual, ad-hoc scripts** with poor reproducibility and no monitoring
- **Fragmented access** making it difficult for quants, analysts, and product teams to work efficiently

Oracul solves this by providing a **proper data platform**.

---

## Core Capabilities

### 1. Data Ingestion
- Near real-time ingestion of Ethereum blocks, transactions, and event logs
- Market price feeds for ETH and top tokens
- Maximum 5-minute lag from chain tip under normal conditions

### 2. Data Storage & Modeling
- Scalable ClickHouse warehouse designed for billions of rows
- Layered table architecture: Raw → Curated → Aggregated → Derived
- Time-based partitioning with configurable retention policies

### 3. Transformation & Analytics
- Automated ERC-20 transfer normalization
- Daily aggregated metrics for tokens and addresses
- Multi-method anomaly detection (statistical + ML)

### 4. Serving & Alerting
- BI dashboards for interactive exploration
- REST API for programmatic access
- Real-time alerts for high-severity anomalies and pipeline failures

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              ORACUL PLATFORM                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   SOURCES              STREAMING          STORAGE          SERVING      │
│   ───────              ─────────          ───────          ───────      │
│                                                                         │
│   ┌──────────┐        ┌─────────┐       ┌──────────┐     ┌──────────┐  │
│   │ Ethereum │───────►│  Kafka  │──────►│ClickHouse│────►│ BI Tools │  │
│   │   RPC    │        │ Topics  │       │ Warehouse│     └──────────┘  │
│   └──────────┘        └─────────┘       │          │     ┌──────────┐  │
│                                         │  Raw     │────►│ REST API │  │
│   ┌──────────┐                          │  Curated │     └──────────┘  │
│   │  Price   │────────────────────────►│  Agg     │     ┌──────────┐  │
│   │  APIs    │                          │  Derived │────►│  Alerts  │  │
│   └──────────┘                          └──────────┘     └──────────┘  │
│                                               ▲                        │
│                                               │                        │
│                                         ┌──────────┐                   │
│                                         │ Airflow  │                   │
│                                         │  DAGs    │                   │
│                                         └──────────┘                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| Data Sources | Ethereum RPC, CoinGecko/CEX APIs | Raw blockchain and market data |
| Ingestion | Python collector services | Extract and emit data to Kafka |
| Streaming | Apache Kafka | Decouple ingestion from storage, enable replay |
| Storage | ClickHouse | High-performance analytics warehouse |
| Orchestration | Apache Airflow | Schedule and monitor data pipelines |
| Serving | Superset/Metabase, FastAPI | Dashboards and API access |
| Alerting | Slack/Telegram | Notifications for anomalies and failures |
| Infrastructure | Docker Compose / Kubernetes | Deployment and scaling |

---

## Target Users

| Persona | Primary Use Case |
|---------|------------------|
| **Quant / Data Scientist** | Feature tables and anomaly data for trading/risk models |
| **Data Engineer** | Build and maintain ingestion, ETL, and infrastructure |
| **Data Analyst** | Explore blockchain behavior via SQL/BI tools |
| **Business Stakeholders** | Dashboards showing "interesting" tokens/addresses |
| **Operations / Risk** | Receive alerts on hacks, unusual flows, protocol stress |

---

## Key Use Cases (MVP)

1. **Token Anomaly Detection**  
   Identify tokens with abnormal volume or active addresses

2. **Address Anomaly Detection**  
   Flag addresses with unusual inflow/outflow patterns

3. **Ad-Hoc Analysis**  
   Query historical ERC-20 transfers, identify whale addresses

4. **Daily Monitoring**  
   Dashboard summary of volumes, anomaly counts, top movers

5. **Engineering Health**  
   Monitor ingestion lag, data quality, pipeline status

---

## Anomaly Detection Methods

Oracul employs multiple detection techniques to balance precision and recall:

| Method | Description | Use Case |
|--------|-------------|----------|
| **Z-Score** | Deviation from rolling mean in standard deviations | General outlier detection |
| **IQR** | Values outside interquartile range bounds | Robust to non-normal distributions |
| **Isolation Forest** | ML-based multi-feature anomaly scoring | Complex pattern detection |

Anomalies are classified by severity (`low`, `medium`, `high`) to prioritize attention and limit alert noise.

---

## MVP Scope

### In Scope (v1.0)
- Ethereum mainnet (optionally +1 EVM chain)
- All ERC-20 transfers (optimizable to top N tokens)
- Single RPC provider
- 1-2 price data sources
- Internal-only access (no external SLA)

### Out of Scope (Future Versions)
- Full multi-chain coverage (Polygon, BSC, L2s)
- Per-protocol metrics (DEX, lending specifics)
- Real-time streaming inference
- External customer-facing API
- Complex RBAC and governance

---

## Timeline Overview

| Phase | Duration | Focus |
|-------|----------|-------|
| **Foundations** | Weeks 1-2 | Infrastructure setup (ClickHouse, Kafka, Airflow) |
| **Ingestion** | Weeks 3-4 | Collectors, Kafka topics, raw table loading |
| **Transformation** | Weeks 5-6 | ERC-20 normalization, daily aggregates, DQ checks |
| **Anomalies & Serving** | Weeks 7-8 | Detection algorithms, dashboards, API, alerts |
| **Stabilization** | Weeks 9-10 | Load testing, performance tuning, threshold refinement |

**Total MVP timeline: 8-12 weeks**

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Ingestion lag | ≤ 5 minutes from chain tip |
| Query performance | < 5 seconds for 30-day analytics |
| Pipeline completion | Daily DAGs done by 03:00 UTC |
| System uptime | 99%+ availability |
| Data scale | Support 500M+ transfer rows |

---

## Key Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| RPC rate limits/costs | Ingestion delays | High-tier plan, batching, caching |
| Data volume explosion | Storage/query costs | Filter to ERC-20, prioritize top tokens |
| Anomaly false positives | Alert fatigue | Iterative threshold tuning with DS |
| Infrastructure complexity | Delayed delivery | DevOps buy-in, phased rollout |

---

## Open Decisions

The following require stakeholder input before finalizing:

1. Which RPC provider(s) and what SLA tier?
2. All ERC-20 transfers vs. curated token whitelist?
3. Ethereum-only or include one L2 in MVP?
4. BI tool selection: Superset vs. Metabase?
5. Deployment environment: Cloud provider/region or on-prem?

---

## Next Steps

1. Review and approve this PRD with stakeholders
2. Finalize open decisions
3. Kick off Week 1 infrastructure setup
4. Establish regular sync cadence for progress tracking

---

*Document Version: 1.0 (MVP Draft)*  
*Owner: Principal Data Platform Architect*
