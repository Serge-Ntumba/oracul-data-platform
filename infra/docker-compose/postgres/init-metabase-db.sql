-- =============================================================================
-- PostgreSQL Initialization - Metabase Database
-- =============================================================================
-- This script creates an additional database for Metabase to store its
-- configuration, users, and dashboards.
--
-- The main 'airflow' database is already created by the POSTGRES_DB env var.
-- This script runs automatically during first container startup.
-- =============================================================================

-- Create Metabase database (only if it doesn't exist)
SELECT 'CREATE DATABASE metabase'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'metabase')\gexec

-- Grant privileges to airflow user (who will own this database too)
GRANT ALL PRIVILEGES ON DATABASE metabase TO airflow;

-- Display confirmation
\echo 'PostgreSQL initialization complete:'
\echo '  - airflow database: ready (for Airflow metadata)'
\echo '  - metabase database: ready (for Metabase configuration)'
