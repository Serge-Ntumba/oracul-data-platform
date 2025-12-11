# ADR-0001: Use ClickHouse as Primary Data Warehouse

**Status:** Accepted
**Date:** 2025-12-04
**Authors:** Principal Data Platform Architect
**Deciders:** Data Platform Team, DevOps Team

## Context

The Oracul blockchain data platform needs a database system capable of:

1. **Scale:** Handling 500M+ rows initially, growing to billions of rows as we ingest historical and real-time blockchain data
2. **Query Performance:** Sub-5-second query response times for analytical queries over 30-day windows
3. **Time-series optimization:** Efficient storage and querying of time-stamped blockchain events (blocks, transactions, logs, prices)
4. **Aggregation performance:** Fast computation of daily metrics across millions of records
5. **Cost efficiency:** Reasonable infrastructure costs for storing and querying massive datasets
6. **Analytical workload:** OLAP-style queries with complex aggregations, joins, and filters

Our data model consists of:
- Raw tables: `raw_blocks`, `raw_transactions`, `raw_logs`, `prices_spot`
- Curated tables: `erc20_transfers`
- Aggregated tables: `token_metrics_daily`, `address_flows_daily`
- Derived tables: `anomalies`, `data_quality_checks`

Typical query patterns include:
- Time-range scans (e.g., "all transactions in the last 7 days")
- Aggregations by token, address, or date
- Multi-table joins for enrichment
- Ad-hoc exploratory queries by data scientists

## Decision

We will use **ClickHouse** as the primary data warehouse for the Oracul platform.

**Implementation details:**
- Deploy ClickHouse as a single-node instance for MVP (Phase 0-1)
- Scale to multi-node cluster in production phases
- Use **partitioning by date** (`PARTITION BY toDate(timestamp)`) for all time-series tables
- Implement **MergeTree** engine family for all analytical tables
- Use **ReplacingMergeTree** for tables requiring deduplication
- Configure retention policies using TTL expressions
- Expose both native protocol (port 9000) and HTTP endpoint (port 8123) for different use cases

## Consequences

### Positive Consequences

1. **Exceptional query performance:** ClickHouse's columnar storage and vectorized query execution deliver sub-second queries on billions of rows
2. **Excellent compression:** 10-40x compression ratios reduce storage costs significantly (typical blockchain data compresses from TB to tens of GB)
3. **Native time-series support:** Built-in functions for time windowing, moving averages, and time-based aggregations
4. **Efficient partitioning:** Date-based partitioning enables fast pruning of irrelevant data during queries
5. **Scalability:** Proven to handle petabyte-scale deployments at companies like Uber, Cloudflare, and Bloomberg
6. **SQL interface:** Familiar SQL dialect with analytical extensions makes it accessible to data analysts and scientists
7. **Low latency inserts:** High-throughput batch inserts from Kafka consumers
8. **Cost effective:** Open-source with no licensing costs; runs efficiently on commodity hardware

### Negative Consequences

1. **Less mature ecosystem:** Fewer ORMs, tools, and community resources compared to PostgreSQL
2. **Limited transaction support:** No full ACID transactions across multiple statements (not critical for our append-only analytical workload)
3. **Eventual consistency:** In distributed mode, data may not be immediately consistent across replicas (acceptable for near-real-time analytics)
4. **Learning curve:** Team needs to learn ClickHouse-specific SQL dialect and optimization patterns
5. **Operational complexity:** Running and tuning ClickHouse clusters requires specialized knowledge
6. **No in-place updates:** Mutation queries (UPDATE/DELETE) are slow; requires designing around immutability

### Neutral Consequences

1. **ClickHouse-specific SQL dialect:** Some standard SQL features missing, but analytical extensions compensate
2. **Infrastructure requirements:** Requires dedicated resources; can't easily share with transactional databases
3. **Batch-oriented writes:** Optimized for batch inserts rather than single-row inserts (aligns with our Kafka → ClickHouse architecture)

## Alternatives Considered

### Alternative 1: PostgreSQL with TimescaleDB

**Description:** PostgreSQL extended with TimescaleDB for time-series workloads

**Pros:**
- Mature ecosystem with extensive tooling, ORMs, and community support
- Full ACID transactions and strong consistency guarantees
- Familiar to most engineers
- TimescaleDB provides time-series optimizations via hypertables and continuous aggregates

**Cons:**
- Query performance degrades significantly at 100M+ row scale
- Compression ratios inferior to ClickHouse (2-5x vs 10-40x)
- Higher infrastructure costs for equivalent performance
- Less optimized for pure analytical workloads
- Limited native parallel query execution

**Why not chosen:** While PostgreSQL + TimescaleDB is excellent for smaller-scale time-series data with transactional requirements, it cannot match ClickHouse's performance and cost efficiency at the scale required for blockchain data (billions of rows).

### Alternative 2: Cloud Data Warehouses (BigQuery, Snowflake, Redshift)

**Description:** Fully-managed cloud data warehouse services

**Pros:**
- Fully managed (no infrastructure to maintain)
- Auto-scaling and separation of compute/storage
- Strong SQL compatibility and ecosystem
- Excellent performance for ad-hoc queries

**Cons:**
- **Vendor lock-in:** Difficult to migrate once committed
- **Costs:** Expensive at high query and storage volumes (estimated 5-10x more expensive than self-hosted ClickHouse)
- **Less control:** Limited ability to tune and optimize infrastructure
- **Egress costs:** Expensive to move data out for other use cases
- **Privacy concerns:** Sensitive blockchain insights stored in third-party cloud

**Why not chosen:** High recurring costs and vendor lock-in make this unsuitable for an early-stage platform. Self-hosted ClickHouse provides better cost efficiency and control while maintaining comparable performance.

### Alternative 3: Apache Cassandra

**Description:** Distributed NoSQL database optimized for write-heavy workloads

**Pros:**
- Exceptional write throughput and horizontal scalability
- High availability and fault tolerance
- Proven at massive scale (Netflix, Apple)
- Strong support for time-series data via wide rows

**Cons:**
- **Poor analytical performance:** Not optimized for complex aggregations and joins
- **Limited query flexibility:** Requires careful data modeling around access patterns
- **No SQL interface:** CQL is more limited than SQL for analytics
- **Higher operational complexity:** More complex to manage than ClickHouse
- **Inefficient for aggregations:** Would require maintaining pre-aggregated tables for every query pattern

**Why not chosen:** Cassandra excels at write-heavy operational workloads but is ill-suited for the complex analytical queries required by data scientists and analysts exploring blockchain data.

### Alternative 4: Apache Druid

**Description:** Real-time OLAP database designed for streaming analytics

**Pros:**
- Optimized for real-time ingestion and sub-second query latency
- Excellent for time-series aggregations
- Built-in rollup and sketches for approximate queries
- Strong community in observability/analytics space

**Cons:**
- More complex architecture (multiple node types: historical, broker, coordinator, etc.)
- Steeper learning curve than ClickHouse
- Smaller ecosystem and community
- More operationally intensive to run and maintain
- Less flexible schema evolution

**Why not chosen:** While Druid is powerful for real-time dashboards, ClickHouse provides comparable or better performance for our use cases with a simpler architecture and broader SQL support. Druid's added complexity is not justified for our requirements.

## Implementation Notes

### Phase 1: Single-Node Setup
- Deploy ClickHouse via Docker Compose for local development
- Use `docker-compose.dev.yml` to spin up ClickHouse alongside Kafka and Airflow
- Configure single-node with 16GB RAM, 4 CPUs for development

### Phase 2: Schema Design
- Implement partitioning by `toDate(timestamp)` for all time-series tables
- Use `ORDER BY` to optimize for common query patterns (e.g., `(chain, token_address, timestamp)` for ERC-20 transfers)
- Set TTL policies for raw tables (retain 90 days, archive to S3 if needed)
- Use `ReplacingMergeTree` for tables requiring deduplication (e.g., `erc20_transfers`)

### Phase 3: Query Optimization
- Add secondary indexes (skipping indexes) for frequently filtered fields (e.g., `token_address`, `from_address`)
- Configure `max_threads` and `max_memory_usage` based on workload
- Use materialized views for pre-aggregated metrics (if needed for performance)

### Phase 4: Production Scaling
- Deploy multi-node cluster with replication for high availability
- Configure ZooKeeper/ClickHouse Keeper for distributed coordination
- Implement distributed tables (`Distributed` engine) over sharded tables
- Monitor with Prometheus + Grafana for query performance and resource usage

## References

- [ClickHouse Official Documentation](https://clickhouse.com/docs)
- [ClickHouse Performance Comparison](https://benchmark.clickhouse.com/)
- [Time-Series Data in ClickHouse](https://clickhouse.com/docs/en/guides/best-practices/#time-series)
- [Partitioning and TTL Guide](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree/#table_engine-mergetree-ttl)
- [Oracul PRD](../product/PRD_oracul_platform_v1.md)

---

## Status History

- **2025-12-04** - Accepted - Decision approved by Data Platform team for Phase 0 implementation
