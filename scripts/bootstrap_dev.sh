#!/bin/bash
# =============================================================================
# Oracul Platform - Development Environment Bootstrap Script
# =============================================================================
# This script sets up the complete local development environment with a single
# command. It handles:
#   - Prerequisite checks (Docker, Docker Compose)
#   - Environment configuration (.env setup)
#   - Secret generation (Fernet key, JWT secret)
#   - Docker Compose startup
#   - Service health checks
#   - Database initialization
#   - Verification and status display
#
# Usage:
#   ./scripts/bootstrap_dev.sh
#
# Requirements:
#   - Docker Desktop 4.20+
#   - Python 3.9+ (for secret generation)
#   - 16GB RAM recommended (8GB minimum)
#   - 20GB free disk space
# =============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_DIR="$PROJECT_ROOT/infra/docker-compose"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}>>> $1${NC}"
}

print_status() {
    echo -e "${GREEN}[]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    print_section "Checking prerequisites"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        print_info "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
    print_status "Docker found: $(docker --version)"

    # Check Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running"
        print_info "Please start Docker Desktop and try again"
        exit 1
    fi
    print_status "Docker daemon is running"

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed"
        print_info "Please install Docker Compose or use Docker Desktop which includes it"
        exit 1
    fi
    print_status "Docker Compose found: $(docker-compose --version)"

    # Check Python (for secret generation)
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        print_info "Please install Python 3.9 or higher"
        exit 1
    fi
    print_status "Python found: $(python3 --version)"

    # Check available disk space (need at least 20GB)
    if command -v df &> /dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS: df output is in 512-byte blocks by default
            AVAILABLE_KB=$(df -k "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
            AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))
        else
            # Linux: use -BG flag
            AVAILABLE_GB=$(df -BG "$PROJECT_ROOT" | tail -1 | awk '{print $4}' | sed 's/G//')
        fi

        if [ "$AVAILABLE_GB" -lt 20 ] 2>/dev/null; then
            print_warning "Low disk space: ${AVAILABLE_GB}GB available (20GB+ recommended)"
        else
            print_status "Sufficient disk space: ${AVAILABLE_GB}GB available"
        fi
    fi

    echo ""
}

# =============================================================================
# Environment Configuration
# =============================================================================

setup_environment() {
    print_section "Setting up environment configuration"

    # Check if .env exists
    if [ -f "$COMPOSE_DIR/.env" ]; then
        print_status ".env file already exists"

        # Ask if user wants to recreate it
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Using existing .env file"
            return 0
        fi
    fi

    # Check if .env.example exists
    if [ ! -f "$PROJECT_ROOT/config/env/dev/.env.example" ]; then
        print_error "Template file not found: config/env/dev/.env.example"
        exit 1
    fi

    # Copy .env.example to .env
    print_info "Creating .env from template..."
    cp "$PROJECT_ROOT/config/env/dev/.env.example" "$COMPOSE_DIR/.env"
    print_status ".env file created"

    # Generate secrets
    print_info "Generating secrets..."

    # Generate Fernet key for Airflow
    FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

    # Generate secret key for Airflow webserver
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

    # Generate ClickHouse password
    CH_PASSWORD="oracul_dev_$(python3 -c "import secrets; print(secrets.token_hex(8))")"

    # Update .env file with generated secrets
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|your_fernet_key_here|$FERNET_KEY|" "$COMPOSE_DIR/.env"
        sed -i '' "s|your_secret_key_here|$SECRET_KEY|" "$COMPOSE_DIR/.env"
        sed -i '' "s|oracul_dev_2024|$CH_PASSWORD|" "$COMPOSE_DIR/.env"
    else
        # Linux
        sed -i "s|your_fernet_key_here|$FERNET_KEY|" "$COMPOSE_DIR/.env"
        sed -i "s|your_secret_key_here|$SECRET_KEY|" "$COMPOSE_DIR/.env"
        sed -i "s|oracul_dev_2024|$CH_PASSWORD|" "$COMPOSE_DIR/.env"
    fi

    print_status "Secrets generated and configured"

    # Check for required environment variables
    if grep -q "your_rpc_url_here" "$COMPOSE_DIR/.env"; then
        print_warning "RPC URL not configured"
        print_info "You need to add your Alchemy/Infura RPC URL to: $COMPOSE_DIR/.env"
        print_info "Look for ALCHEMY_ETH_MAINNET_URL and replace 'your_rpc_url_here'"
        echo ""
        read -p "Press Enter after you've updated the RPC URL (or skip for now)..."
    fi

    echo ""
}

# =============================================================================
# Docker Operations
# =============================================================================

stop_existing_containers() {
    print_section "Stopping any existing containers"

    cd "$COMPOSE_DIR"

    if docker-compose -f docker-compose.dev.yml ps -q 2>/dev/null | grep -q .; then
        print_info "Stopping and removing existing containers..."
        docker-compose -f docker-compose.dev.yml down
        print_status "Existing containers stopped"
    else
        print_info "No existing containers found"
    fi

    cd "$PROJECT_ROOT"
    echo ""
}

pull_docker_images() {
    print_section "Pulling Docker images"

    cd "$COMPOSE_DIR"

    print_info "This may take several minutes on first run..."
    docker-compose -f docker-compose.dev.yml pull

    print_status "Docker images pulled successfully"
    cd "$PROJECT_ROOT"
    echo ""
}

start_services() {
    print_section "Starting services"

    cd "$COMPOSE_DIR"

    print_info "Starting all services in background..."
    docker-compose -f docker-compose.dev.yml up -d

    print_status "Services started"
    cd "$PROJECT_ROOT"
    echo ""
}

# =============================================================================
# Health Checks
# =============================================================================

wait_for_service() {
    local service=$1
    local max_attempts=${2:-60}  # Default 60 attempts (2 minutes)
    local attempt=0

    echo -n "Waiting for $service to be healthy..."

    cd "$COMPOSE_DIR"

    while [ $attempt -lt $max_attempts ]; do
        # Check if service is healthy
        HEALTH=$(docker-compose -f docker-compose.dev.yml ps --filter "health=healthy" --format json 2>/dev/null | jq -r 'select(.Name | contains("'$service'")) | .Health' 2>/dev/null || echo "")

        if [ "$HEALTH" = "healthy" ] || docker-compose -f docker-compose.dev.yml ps | grep -q "$service.*healthy"; then
            echo -e " ${GREEN}${NC}"
            cd "$PROJECT_ROOT"
            return 0
        fi

        # Check if service exited with error
        if docker-compose -f docker-compose.dev.yml ps --filter "status=exited" | grep -q "$service"; then
            echo -e " ${RED}${NC}"
            print_error "$service exited with error"
            docker-compose -f docker-compose.dev.yml logs --tail=20 "$service"
            cd "$PROJECT_ROOT"
            return 1
        fi

        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done

    echo -e " ${RED}${NC}"
    print_error "$service failed to become healthy after $max_attempts attempts"
    print_info "Showing recent logs:"
    docker-compose -f docker-compose.dev.yml logs --tail=20 "$service"
    cd "$PROJECT_ROOT"
    return 1
}

wait_for_all_services() {
    print_section "Waiting for services to be healthy"

    # Wait for foundation services (Level 0)
    wait_for_service "clickhouse" 60
    wait_for_service "postgres" 30
    wait_for_service "zookeeper" 30

    # Wait for Kafka (Level 1)
    wait_for_service "kafka" 60

    # Wait for Airflow and API (Level 3)
    wait_for_service "airflow-webserver" 90
    wait_for_service "fastapi" 60 || print_warning "API may not be fully ready (expected if /health endpoint not implemented)"

    # Wait for Metabase (Level 3, longer timeout)
    wait_for_service "metabase" 120

    print_status "All critical services are healthy"
    echo ""
}

# =============================================================================
# Verification
# =============================================================================

verify_services() {
    print_section "Verifying services"

    cd "$COMPOSE_DIR"

    # ClickHouse
    print_info "Checking ClickHouse..."
    if docker-compose -f docker-compose.dev.yml exec -T clickhouse-server \
        clickhouse-client --query "SELECT version()" > /dev/null 2>&1; then
        CH_VERSION=$(docker-compose -f docker-compose.dev.yml exec -T clickhouse-server \
            clickhouse-client --query "SELECT version()" 2>/dev/null | tr -d '\r')
        print_status "ClickHouse: v$CH_VERSION"

        # Check database
        if docker-compose -f docker-compose.dev.yml exec -T clickhouse-server \
            clickhouse-client --query "SHOW DATABASES" 2>/dev/null | grep -q "oracul"; then
            print_status "Database 'oracul' exists"
        else
            print_warning "Database 'oracul' not found (will be created by init script)"
        fi
    else
        print_error "ClickHouse: FAILED"
    fi

    # Kafka
    print_info "Checking Kafka..."
    if docker-compose -f docker-compose.dev.yml exec -T kafka \
        kafka-topics --bootstrap-server localhost:9092 --list > /dev/null 2>&1; then
        print_status "Kafka: OK"

        # Check topics
        TOPICS=$(docker-compose -f docker-compose.dev.yml exec -T kafka \
            kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | tr -d '\r')

        if echo "$TOPICS" | grep -q "eth.blocks.raw"; then
            TOPIC_COUNT=$(echo "$TOPICS" | wc -l | tr -d ' ')
            print_status "Kafka topics created: $TOPIC_COUNT topics"
        else
            print_warning "Kafka topics not yet created (check kafka-init logs)"
        fi
    else
        print_error "Kafka: FAILED"
    fi

    # API
    print_info "Checking API..."
    if curl -f http://localhost:8000/health &> /dev/null; then
        print_status "API: OK (http://localhost:8000)"
    elif curl -f http://localhost:8000/docs &> /dev/null; then
        print_status "API: OK (docs available, /health not implemented)"
    else
        print_warning "API: Not responding (may need /health endpoint implementation)"
    fi

    cd "$PROJECT_ROOT"
    echo ""
}

# =============================================================================
# Display Final Status
# =============================================================================

display_service_urls() {
    print_header "Development Environment Ready!"

    echo "Service URLs:"
    echo ""
    echo -e "  ${GREEN}✓${NC} Airflow:     ${CYAN}http://localhost:8080${NC}  (admin / admin)"
    echo -e "  ${GREEN}✓${NC} API:         ${CYAN}http://localhost:8000${NC}  (docs at /docs)"
    echo -e "  ${GREEN}✓${NC} Metabase:    ${CYAN}http://localhost:3000${NC}  (setup on first visit)"
    echo -e "  ${GREEN}✓${NC} ClickHouse:  ${CYAN}http://localhost:8123${NC}  (HTTP) / ${CYAN}localhost:9000${NC} (native)"
    echo -e "  ${GREEN}✓${NC} Kafka:       ${CYAN}localhost:9092${NC}"
    echo ""

    echo "Useful Commands:"
    echo ""
    echo "  View logs:           cd $COMPOSE_DIR && docker-compose -f docker-compose.dev.yml logs -f [service]"
    echo "  Stop services:       cd $COMPOSE_DIR && docker-compose -f docker-compose.dev.yml down"
    echo "  Restart service:     cd $COMPOSE_DIR && docker-compose -f docker-compose.dev.yml restart [service]"
    echo "  Run tests:           $SCRIPT_DIR/run_tests.sh"
    echo "  ClickHouse CLI:      clickhouse-client --host localhost --port 9000"
    echo ""

    echo "Next Steps:"
    echo ""
    echo "  1. Open Airflow UI and verify it's accessible"
    echo "  2. Open Metabase and configure ClickHouse connection:"
    echo "     - Database Type: ClickHouse"
    echo "     - Host: clickhouse-server"
    echo "     - Port: 8123 (HTTP)"
    echo "     - Database: oracul"
    echo "     - Username: default"
    echo "     - Password: (check $COMPOSE_DIR/.env for CLICKHOUSE_PASSWORD)"
    echo "  3. Test ClickHouse connection:"
    echo "     clickhouse-client --host localhost --port 9000"
    echo ""

    print_info "For more information, see GETTING_STARTED.md"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    print_header "Oracul Platform - Development Environment Setup"

    # Run setup steps
    check_prerequisites
    setup_environment
    stop_existing_containers
    pull_docker_images
    start_services
    wait_for_all_services
    verify_services
    display_service_urls

    print_status "Bootstrap complete!"
}

# Run main function
main
