# ADR-0003: Use Apache Airflow for Batch ETL Orchestration

**Status:** Accepted
**Date:** 2025-12-04
**Authors:** Principal Data Platform Architect
**Deciders:** Data Platform Team, DevOps Team, Data Science Team

## Context

The Oracul platform needs to orchestrate complex data transformation pipelines that:

1. **Transform raw data:** Normalize `raw_logs` into `erc20_transfers` every 15 minutes
2. **Compute daily aggregates:** Generate `token_metrics_daily` and `address_flows_daily` tables
3. **Run anomaly detection:** Execute statistical and ML-based algorithms on daily metrics
4. **Validate data quality:** Check for freshness, gaps, and inconsistencies hourly
5. **Handle dependencies:** Ensure daily metrics complete before anomaly detection runs
6. **Support retries:** Automatically retry failed tasks with backoff
7. **Provide observability:** Track pipeline status, failures, and execution times
8. **Enable backfills:** Reprocess historical data when logic changes or data is missing

Our pipeline requirements:
- **Languages:** Primarily Python (for sharing code with ingestion layer and leveraging ML libraries)
- **Schedule types:** Cron-based (hourly, daily) and interval-based (every 15 minutes)
- **Dependencies:** Complex DAG structures (e.g., normalization → aggregation → anomaly detection)
- **Idempotency:** Tasks must safely re-run without duplicating data
- **SLAs:** Monitor and alert when pipelines miss deadlines
- **Scale:** Dozens of DAGs initially, growing to hundreds as we add chains and metrics

Without orchestration:
- Engineers would manually cron individual scripts (fragile, no dependency management)
- No central monitoring of pipeline health
- Difficult to debug failures and understand lineage
- Manual retries and recovery

## Decision

We will use **Apache Airflow** for batch ETL orchestration in the Oracul platform.

**Implementation details:**
- Deploy Airflow with **LocalExecutor** for MVP (single-node)
- Use **PostgreSQL** as the metadata database (stores DAG state, task history, connections)
- Store DAGs in `pipelines/dags/` directory
- Implement shared utilities in `pipelines/libs/` (ClickHouse clients, anomaly algorithms)
- Configure **retries = 2** with **5-minute retry delay** by default
- Enable **email alerts** on task failures (Slack integration optional)
- Use **Airflow Variables** for configuration (thresholds, window sizes)
- Schedule key DAGs:
  - `normalize_erc20_dag` - Every 15 minutes
  - `token_metrics_daily_dag` - Daily at 01:00 UTC
  - `address_flows_daily_dag` - Daily at 01:30 UTC
  - `anomaly_detection_dag` - Daily at 02:00 UTC
  - `data_quality_dag` - Hourly
  - `ingestion_monitoring_dag` - Every 5 minutes

## Consequences

### Positive Consequences

1. **Powerful DAG abstraction:** Clearly express complex task dependencies and execution order
2. **Python-native:** Share code with ingestion layer, leverage rich Python ecosystem (pandas, scikit-learn, etc.)
3. **Rich UI:** Web interface for monitoring, triggering, and debugging pipelines
4. **Built-in retry logic:** Automatic retries with backoff reduce manual intervention
5. **SLA monitoring:** Track and alert on pipeline completion times
6. **Backfill support:** Easily reprocess historical data with parameterized date ranges
7. **Large ecosystem:** Extensive library of operators, sensors, and integrations (ClickHouse, Kafka, APIs)
8. **Active community:** Large user base, frequent releases, abundant resources and tutorials
9. **Observability:** Detailed logs, task duration tracking, and failure analytics
10. **Dynamic DAG generation:** Programmatically create DAGs based on configuration (e.g., per-chain pipelines)
11. **Testing support:** DAGs can be unit-tested before deployment

### Negative Consequences

1. **Heavy infrastructure:** Requires PostgreSQL, Redis (for Celery), and Airflow services (webserver, scheduler, workers)
2. **Learning curve:** DAG authoring, operators, sensors, XComs, and best practices require time to learn
3. **Performance limitations:** Scheduler can become bottleneck with thousands of concurrent tasks (less concern for our scale)
4. **Complexity:** More moving parts than simple cron jobs
5. **Deployment overhead:** Managing DAG deployments (code sync, versioning) requires discipline
6. **UI can be slow:** Web UI becomes sluggish with thousands of DAG runs (mitigated by purging old logs)
7. **Debugging challenges:** Distributed execution makes debugging harder than local scripts

### Neutral Consequences

1. **Python-first design:** Great for Python shops, but less ergonomic for SQL-heavy transformations (can use SQL operators)
2. **Not real-time:** Batch-oriented; not suitable for sub-second latency requirements (we handle real-time via Kafka)
3. **DAG design discipline:** Poorly designed DAGs can lead to cascading failures; requires careful design
4. **Metadata DB dependency:** PostgreSQL outage impacts all pipeline execution

## Alternatives Considered

### Alternative 1: Prefect

**Description:** Modern Python workflow orchestration engine with a focus on ease of use

**Pros:**
- Cleaner, more Pythonic API (no explicit operators, just decorators on Python functions)
- Better developer experience (less boilerplate than Airflow)
- Cloud-native design with hybrid execution (run anywhere)
- Improved observability UI
- Easier testing (functions are just Python functions)
- Incremental retries at task level

**Cons:**
- **Smaller ecosystem:** Fewer pre-built integrations than Airflow
- **Less production adoption:** Smaller community, fewer battle-tested deployments
- **Newer technology:** Less mature, faster-breaking changes
- **Limited plugins:** Many Airflow operators don't have Prefect equivalents
- **Commercial focus:** Open-source version has limited features; enterprise features in paid tier

**Why not chosen:** While Prefect offers a more modern API, Airflow's maturity, large ecosystem, and widespread adoption make it a safer choice. More engineers are familiar with Airflow, and the vast plugin library saves development time.

### Alternative 2: Dagster

**Description:** Asset-oriented orchestration framework for data pipelines

**Pros:**
- Asset-centric model (focuses on "what" you produce, not "how")
- Strong typing and testability
- Better for data quality and lineage tracking
- Modern UI with asset catalog
- Good for complex data engineering workflows
- Python-native with clean APIs

**Cons:**
- **Steeper learning curve:** Asset-based mental model is different from traditional task-based orchestration
- **Less mature:** Younger project with smaller community
- **Fewer integrations:** Limited library of pre-built connectors
- **More complex abstraction:** Requires rethinking pipeline design around assets vs tasks
- **Smaller ecosystem:** Fewer examples, tutorials, and community resources

**Why not chosen:** Dagster's asset-oriented approach is compelling for some use cases, but adds conceptual overhead. Airflow's task-based model is more intuitive and has proven effective for similar blockchain data pipelines at other companies.

### Alternative 3: dbt (Data Build Tool)

**Description:** SQL-first transformation framework for analytics engineering

**Pros:**
- **Excellent for SQL transformations:** Best-in-class for ELT patterns
- Simple YAML-based configuration
- Built-in testing and documentation
- Strong lineage tracking
- Incremental model builds
- Great for analytics engineering teams

**Cons:**
- **SQL-only:** Not suitable for Python-based ML pipelines (anomaly detection)
- **No general-purpose orchestration:** Limited to data transformations (no collectors, no alerting)
- **Requires separate orchestrator:** dbt doesn't schedule itself (often run inside Airflow)
- **Less flexible:** Harder to implement complex logic (e.g., API calls, file processing)

**Why not chosen:** dbt excels at SQL transformations but cannot handle our Python-based anomaly detection, data quality checks, and orchestration of non-SQL tasks. We could use dbt _within_ Airflow DAGs for SQL transformations, but it doesn't replace an orchestrator.

### Alternative 4: Cron + Bash Scripts

**Description:** Unix cron scheduler with custom bash/Python scripts

**Pros:**
- Simplest possible solution (no new infrastructure)
- Minimal resource overhead
- Familiar to all engineers
- No learning curve

**Cons:**
- **No dependency management:** Can't express "run task B after task A completes"
- **No retries:** Must implement retry logic in every script
- **No central monitoring:** Must manually check logs on each server
- **No backfill support:** Must manually run scripts for date ranges
- **No SLA tracking:** No alerts when pipelines run late
- **Fragile:** Script failures go unnoticed until humans check
- **Scaling nightmare:** Managing hundreds of cron entries across multiple servers

**Why not chosen:** Cron is acceptable for 2-3 simple jobs, but quickly becomes unmanageable at scale. For a production data platform with complex dependencies, retries, and monitoring requirements, a proper orchestrator is essential.

### Alternative 5: Luigi

**Description:** Python workflow engine originally developed by Spotify

**Pros:**
- Python-native with explicit task dependencies
- Lightweight (simpler than Airflow)
- No external metadata database required (uses local state)
- Good for batch processing

**Cons:**
- **No scheduler:** Luigi doesn't schedule tasks; requires external cron or continuous run
- **No web UI:** Very basic UI compared to Airflow
- **Less active development:** Smaller community, slower release cycle
- **Limited operators:** Fewer pre-built integrations than Airflow
- **No backfill support:** Must manually run for historical dates

**Why not chosen:** Luigi is simpler than Airflow but lacks critical features like a built-in scheduler, rich UI, and backfill support. Airflow's ecosystem and features justify the additional complexity.

## Implementation Notes

### Phase 1: Local Development Setup
- Deploy Airflow via Docker Compose with LocalExecutor
- Use PostgreSQL for metadata database (included in docker-compose)
- Mount `pipelines/dags/` into Airflow container
- Configure Airflow with `config/base/airflow.yml`
- Enable webserver on port 8080

### Phase 2: DAG Development Patterns
- Store DAGs in `pipelines/dags/`
- Implement business logic in `pipelines/jobs/` (not in DAG files directly)
- Use utility functions from `pipelines/libs/`
- Follow naming convention: `{purpose}_{frequency}_dag.py` (e.g., `normalize_erc20_dag.py`)
- Set DAG-level default args:
  ```python
  default_args = {
      'owner': 'oracul-platform',
      'retries': 2,
      'retry_delay': timedelta(minutes=5),
      'email_on_failure': True,
      'email_on_retry': False,
  }
  ```

### Phase 3: Idempotency Patterns
- Use date-based processing windows (e.g., process yesterday's data)
- Implement "upsert" logic: delete existing data for date range before inserting
- Use watermark tables to track last processed timestamp
- For ClickHouse, use `ReplacingMergeTree` for natural deduplication

### Phase 4: Testing and Validation
- Write unit tests for job functions in `tests/`
- Test DAGs with `airflow dags test <dag_id> <execution_date>`
- Validate DAG syntax with `airflow dags list`
- Use Airflow's `pytest` plugin for integration tests

### Phase 5: Production Deployment
- Migrate to **CeleryExecutor** for horizontal scaling (add Redis)
- Deploy multiple worker nodes for parallel task execution
- Configure DAG-level SLAs and alerts
- Integrate with Prometheus for metrics export
- Set up centralized logging (e.g., ELK stack)
- Implement DAG versioning via Git tags

### Phase 6: Monitoring and Observability
- Monitor key metrics:
  - DAG success/failure rates
  - Task duration (detect performance regressions)
  - Scheduler lag (should be < 30 seconds)
  - Queue length (should be < 100 under normal operation)
- Alert on:
  - DAG failure
  - Task retry exhaustion
  - SLA misses
  - Scheduler downtime

## References

- [Apache Airflow Official Documentation](https://airflow.apache.org/docs/)
- [Airflow Best Practices](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html)
- [Airflow DAG Authoring Guide](https://airflow.apache.org/docs/apache-airflow/stable/concepts/dags.html)
- [Airflow Testing Guide](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html#testing)
- [Oracul PRD](../product/PRD_oracul_platform_v1.md)

---

## Status History

- **2025-12-04** - Accepted - Decision approved by Data Platform team for Phase 0 implementation
