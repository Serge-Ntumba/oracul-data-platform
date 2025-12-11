# ADR-0002: Use Apache Kafka for Streaming Data Layer

**Status:** Accepted
**Date:** 2025-12-04
**Authors:** Principal Data Platform Architect
**Deciders:** Data Platform Team, DevOps Team

## Context

The Oracul platform needs to ingest blockchain data continuously from RPC endpoints and market data APIs, then load it into ClickHouse for analysis. This ingestion pipeline requires:

1. **Decoupling:** Separate the ingestion rate (variable, depends on RPC limits) from the storage rate (depends on ClickHouse capacity)
2. **Buffering:** Handle backpressure when ClickHouse is temporarily unavailable or slow
3. **Replay capability:** Re-process data for backfills or error recovery without re-fetching from expensive RPC endpoints
4. **Durability:** Ensure no data loss if consumer processes crash
5. **Scalability:** Support high throughput (thousands of events per second) as we add more chains
6. **Multiple consumers:** Enable future use cases like real-time alerting or streaming analytics without duplicating ingestion logic
7. **Exactly-once semantics:** Avoid duplicate data in ClickHouse from retries

Our data flow:
```
Collectors (Python) → [Buffer Layer] → ClickHouse Loaders (Python) → ClickHouse
```

Without a proper buffer layer:
- Collectors must block if ClickHouse is slow/unavailable
- No replay capability (must re-fetch from RPC, incurring costs and rate limits)
- Direct writes to ClickHouse couple ingestion and storage tightly

## Decision

We will use **Apache Kafka** as the streaming data layer between collectors and ClickHouse.

**Implementation details:**
- Deploy Kafka with **ZooKeeper** for MVP (migrate to KRaft mode in production)
- Create dedicated topics for each data type:
  - `eth.blocks.raw` - Block headers and metadata
  - `eth.transactions.raw` - Transaction data
  - `eth.logs.raw` - Event logs
  - `market.prices.raw` - Price ticks
- Configure **replication factor = 1** for local dev, **= 3** for production
- Set **retention policy = 7 days** (configurable based on storage and replay needs)
- Use **Kafka producer** in collectors (Python `kafka-python` library)
- Use **Kafka consumer groups** in loaders with manual offset commit for exactly-once processing
- Configure **compression = snappy** for efficient storage and network transfer
- Use **message keys** based on logical partitioning (e.g., block_number, token_address)

## Consequences

### Positive Consequences

1. **Decoupling:** Collectors and loaders run independently; failures in one don't block the other
2. **Backpressure handling:** Kafka buffers messages when ClickHouse is slow, preventing data loss
3. **Replay capability:** Can reprocess historical data from Kafka without hitting RPC endpoints again (useful for debugging and backfills)
4. **Durability:** Kafka's durable log ensures no data loss even if consumer crashes mid-processing
5. **Scalability:** Easily scale consumers horizontally by adding more consumer instances to the group
6. **Multiple consumers:** Future use cases (e.g., real-time anomaly detection, alerting) can consume the same topics without impacting main loaders
7. **Exactly-once semantics:** With manual offset commit, we ensure each message is processed exactly once (no duplicates in ClickHouse)
8. **Battle-tested:** Kafka powers critical data pipelines at LinkedIn, Uber, Netflix, and thousands of other companies
9. **Observability:** Built-in metrics for lag monitoring, throughput tracking, and error detection

### Negative Consequences

1. **Operational complexity:** Requires managing Kafka brokers, ZooKeeper (or KRaft), and monitoring
2. **Infrastructure overhead:** Additional service to deploy, maintain, and scale
3. **Resource requirements:** Kafka requires dedicated RAM and disk (typically 4GB+ RAM, 50GB+ disk for MVP)
4. **Learning curve:** Team needs to understand Kafka concepts (topics, partitions, offsets, consumer groups)
5. **Network hops:** Adds one extra hop between collectors and ClickHouse (minimal latency impact)
6. **Storage costs:** Must provision disk for message retention (mitigated by compression and short retention)

### Neutral Consequences

1. **Message ordering:** Kafka guarantees order within a partition (sufficient for our block-based ingestion)
2. **Schema evolution:** Need to manage message format changes (can use Avro or JSON with versioning)
3. **Monitoring required:** Must monitor consumer lag to detect slow/stuck loaders
4. **Retention tuning:** Must balance retention period vs disk costs

## Alternatives Considered

### Alternative 1: RabbitMQ

**Description:** Advanced message queue with complex routing capabilities

**Pros:**
- Mature and widely adopted
- Rich routing features (exchanges, queues, bindings)
- Easier to set up than Kafka (fewer moving parts)
- Better for traditional request/response patterns
- Strong delivery guarantees with acknowledgments

**Cons:**
- **Lower throughput:** ~10-50K messages/sec vs Kafka's 100K-1M+ messages/sec
- **Not designed for replay:** Messages deleted after consumption; no log-based replay
- **Limited scalability:** Harder to scale horizontally compared to Kafka
- **Less suitable for streaming:** Optimized for queuing, not continuous stream processing
- **Message replay difficult:** Would need to persist messages separately for replay scenarios

**Why not chosen:** RabbitMQ's queuing model doesn't fit our log-based streaming requirements. We need to replay messages for backfills and multi-consumer scenarios, which Kafka handles natively but RabbitMQ does not.

### Alternative 2: AWS Kinesis

**Description:** Fully-managed streaming data service from AWS

**Pros:**
- Fully managed (no infrastructure to maintain)
- Auto-scaling of shards
- Integrates natively with AWS services
- Built-in monitoring via CloudWatch
- High availability and durability

**Cons:**
- **Vendor lock-in:** Tightly coupled to AWS; difficult to migrate to other clouds or on-prem
- **Higher costs:** More expensive than self-hosted Kafka at high volumes
- **Less flexible:** Limited configurability compared to Kafka
- **API differences:** Kinesis API differs from Kafka, requiring specialized libraries
- **Shard management overhead:** Need to manage shard splits/merges as throughput changes

**Why not chosen:** We want to maintain infrastructure flexibility and avoid vendor lock-in. Self-hosted Kafka provides better cost efficiency and control while offering comparable or better features for our use case.

### Alternative 3: Direct Write to ClickHouse

**Description:** Collectors write directly to ClickHouse without an intermediate buffer

**Pros:**
- Simplest architecture (fewest components)
- No additional infrastructure to manage
- Lower operational complexity
- Minimal latency between ingestion and availability

**Cons:**
- **No backpressure handling:** Collectors must block or drop data if ClickHouse is slow
- **No replay capability:** Must re-fetch from RPC for backfills (expensive and slow)
- **Tight coupling:** Changes to ClickHouse schema require immediate changes to all collectors
- **No multi-consumer support:** Can't add new consumers without duplicating ingestion logic
- **Data loss risk:** If ClickHouse is unavailable and collectors crash, data is lost
- **Scalability bottleneck:** All ingestion limited by ClickHouse write capacity

**Why not chosen:** Direct writes create tight coupling, eliminate replay capability, and introduce data loss risks. For a production-grade data platform, the benefits of Kafka far outweigh its operational costs.

### Alternative 4: Redis Streams

**Description:** Redis data structure for append-only log streams

**Pros:**
- Very low latency (in-memory)
- Simpler to set up than Kafka
- Familiar Redis ecosystem
- Built-in consumer groups
- Good for small-to-medium scale

**Cons:**
- **Limited durability:** Primarily in-memory; disk persistence less robust than Kafka
- **Scalability limits:** Single-node Redis bottleneck; Redis Cluster adds complexity
- **Not designed for large streams:** Performance degrades with very large streams (billions of messages)
- **Weak replay semantics:** Limited ability to replay old messages compared to Kafka
- **Memory constraints:** Stream size limited by available RAM

**Why not chosen:** Redis Streams is great for small-scale, low-latency use cases, but Kafka is better suited for the scale and durability requirements of blockchain data ingestion (billions of events over time).

### Alternative 5: Apache Pulsar

**Description:** Next-generation distributed messaging and streaming platform

**Pros:**
- Unified messaging (queuing + streaming)
- Better multi-tenancy than Kafka
- Decoupled storage (BookKeeper) from compute
- Built-in geo-replication
- Better out-of-the-box observability

**Cons:**
- **Less mature ecosystem:** Smaller community and fewer integrations than Kafka
- **More complex architecture:** Requires BookKeeper, ZooKeeper, and brokers (more components)
- **Steeper learning curve:** More concepts to learn (tenants, namespaces, etc.)
- **Less production adoption:** Fewer proven large-scale deployments than Kafka
- **Operational expertise rare:** Harder to find engineers with Pulsar experience

**Why not chosen:** While Pulsar has compelling features, Kafka's maturity, ecosystem, and widespread adoption make it a safer choice for our platform. The team is more likely to find resources, libraries, and community support for Kafka.

## Implementation Notes

### Phase 1: Local Development Setup
- Deploy Kafka + ZooKeeper via Docker Compose
- Create 4 topics (`eth.blocks.raw`, `eth.transactions.raw`, `eth.logs.raw`, `market.prices.raw`)
- Configure single partition per topic (sufficient for single-chain MVP)
- Set retention policy = 7 days (168 hours)

### Phase 2: Producer Implementation (Collectors)
- Use `kafka-python` library in collector services
- Configure `acks='all'` for durability (wait for all replicas to acknowledge)
- Set `compression_type='snappy'` for network and disk efficiency
- Implement retry logic with exponential backoff
- Use block number as message key for partitioning (ensures ordered processing)

### Phase 3: Consumer Implementation (Loaders)
- Use Kafka consumer groups with `enable_auto_commit=False`
- Batch consume messages (e.g., 1000 messages per batch)
- Insert batches into ClickHouse
- Commit offsets only after successful ClickHouse insert (exactly-once semantics)
- Monitor consumer lag via Prometheus exporter

### Phase 4: Monitoring and Alerting
- Deploy Kafka Exporter for Prometheus metrics
- Monitor key metrics:
  - Consumer lag (should be < 1000 messages under normal operation)
  - Throughput (messages/sec)
  - Disk usage (should stay below 80%)
- Alert on:
  - Consumer lag > 10,000 messages
  - Kafka broker down
  - Disk usage > 90%

### Phase 5: Production Hardening
- Increase replication factor to 3
- Add multiple Kafka brokers for high availability
- Migrate from ZooKeeper to KRaft mode (Kafka Raft)
- Implement topic auto-creation policies
- Configure log compaction for certain topics if needed

## References

- [Apache Kafka Official Documentation](https://kafka.apache.org/documentation/)
- [Kafka Architecture and Design](https://kafka.apache.org/intro)
- [Exactly-Once Semantics in Kafka](https://www.confluent.io/blog/exactly-once-semantics-are-possible-heres-how-apache-kafka-does-it/)
- [Kafka Monitoring Best Practices](https://www.confluent.io/blog/kafka-monitoring-best-practices/)
- [Oracul PRD](../product/PRD_oracul_platform_v1.md)

---

## Status History

- **2025-12-04** - Accepted - Decision approved by Data Platform team for Phase 0 implementation
