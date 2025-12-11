-- =============================================================================
-- ClickHouse Database Initialization
-- =============================================================================
-- This script creates the main Oracul database and basic metadata tables.
-- It runs automatically when the ClickHouse container first starts.
--
-- Tables will be created in subsequent phases via migration scripts.
-- For Phase 1, we only need the database to exist.
-- =============================================================================

-- Create main database
CREATE DATABASE IF NOT EXISTS oracul
COMMENT 'Oracul Blockchain Data Platform - Main analytical database';

-- Switch to oracul database for subsequent operations
-- Note: Actual table creation will happen in Phase 2-3 via migration scripts

-- Verify database was created
SELECT 'ClickHouse database "oracul" initialized successfully' AS status;
