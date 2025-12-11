#!/bin/bash
# =============================================================================
# Oracul Platform - Test Runner
# =============================================================================
# Unified test runner for both local development and CI/CD environments.
# Supports multiple test types and generates coverage reports.
#
# Usage:
#   ./scripts/run_tests.sh [TEST_TYPE]
#
# Test Types:
#   all          - Run all tests (linters + unit + api + integration)
#   lint         - Run linters only (black, isort, flake8)
#   unit         - Run unit tests only
#   api          - Run API tests only
#   integration  - Run integration tests only (requires services running)
#   pipeline     - Run pipeline tests only (Phase 3+)
#
# Examples:
#   ./scripts/run_tests.sh             # Run all tests
#   ./scripts/run_tests.sh unit        # Run only unit tests
#   ./scripts/run_tests.sh lint        # Run only linters
# =============================================================================

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default test type
TEST_TYPE="${1:-all}"

# Track failures
FAILED=0

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}>>> $1${NC}"
    echo ""
}

print_status() {
    echo -e "${GREEN}[]${NC} $1"
}

print_error() {
    echo -e "${RED}[]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    # Check if we're in the project root
    if [ ! -f "$PROJECT_ROOT/pyproject.toml" ] && [ ! -f "$PROJECT_ROOT/setup.py" ]; then
        print_warning "Not in project root or project not set up"
    fi

    # Check if pytest is installed
    if ! command -v pytest &> /dev/null; then
        print_warning "pytest not found, attempting to install..."
        pip install pytest pytest-cov pytest-asyncio
    fi
}

# =============================================================================
# Linting
# =============================================================================

run_linters() {
    print_section "Running Linters"

    local lint_failed=0

    # Black check
    print_info "Running black..."
    if black --check --line-length 100 "$PROJECT_ROOT" 2>&1 | grep -v "^All done"; then
        print_status "Black: PASSED"
    else
        print_error "Black: FAILED - code needs formatting"
        print_info "Run 'black .' to fix formatting issues"
        lint_failed=1
    fi
    echo ""

    # isort check
    print_info "Running isort..."
    if isort --check-only --profile black "$PROJECT_ROOT" 2>&1; then
        print_status "isort: PASSED"
    else
        print_error "isort: FAILED - imports need sorting"
        print_info "Run 'isort .' to fix import order"
        lint_failed=1
    fi
    echo ""

    # flake8
    print_info "Running flake8..."
    if flake8 "$PROJECT_ROOT" --max-line-length=100 --extend-ignore=E203,W503 2>&1; then
        print_status "flake8: PASSED"
    else
        print_error "flake8: FAILED - linting issues found"
        lint_failed=1
    fi
    echo ""

    if [ $lint_failed -eq 0 ]; then
        print_status "All linters passed"
    else
        print_error "Some linters failed"
        FAILED=1
    fi

    return $lint_failed
}

# =============================================================================
# Unit Tests
# =============================================================================

run_unit_tests() {
    print_section "Running Unit Tests"

    cd "$PROJECT_ROOT"

    if [ -d "tests/unit" ]; then
        pytest tests/unit/ \
            -v \
            --tb=short \
            --cov=api \
            --cov=ingestion \
            --cov=pipelines \
            --cov-report=term-missing \
            --cov-report=html:htmlcov/unit \
            -m unit

        if [ $? -eq 0 ]; then
            print_status "Unit tests passed"
            return 0
        else
            print_error "Unit tests failed"
            FAILED=1
            return 1
        fi
    else
        print_warning "No unit tests found (tests/unit/ directory missing)"
        return 0
    fi
}

# =============================================================================
# API Tests
# =============================================================================

run_api_tests() {
    print_section "Running API Tests"

    cd "$PROJECT_ROOT/api"

    if [ -d "tests" ]; then
        pytest tests/ \
            -v \
            --tb=short \
            --cov=app \
            --cov-report=term-missing \
            --cov-report=html:htmlcov/api

        if [ $? -eq 0 ]; then
            print_status "API tests passed"
            cd "$PROJECT_ROOT"
            return 0
        else
            print_error "API tests failed"
            FAILED=1
            cd "$PROJECT_ROOT"
            return 1
        fi
    else
        print_warning "No API tests found (api/tests/ directory missing)"
        cd "$PROJECT_ROOT"
        return 0
    fi
}

# =============================================================================
# Integration Tests
# =============================================================================

check_services_running() {
    # Check if docker-compose services are running
    if ! docker ps | grep -q "oracul_clickhouse"; then
        return 1
    fi

    if ! docker ps | grep -q "oracul_kafka"; then
        return 1
    fi

    return 0
}

run_integration_tests() {
    print_section "Running Integration Tests"

    # Check if services are running
    if ! check_services_running; then
        print_error "Required services are not running"
        print_info "Start services with: ./scripts/bootstrap_dev.sh"
        print_warning "Skipping integration tests"
        return 0
    fi

    print_status "Services are running"

    cd "$PROJECT_ROOT"

    if [ -d "tests/integration" ]; then
        pytest tests/integration/ \
            -v \
            --tb=short \
            -m integration

        if [ $? -eq 0 ]; then
            print_status "Integration tests passed"
            return 0
        else
            print_error "Integration tests failed"
            FAILED=1
            return 1
        fi
    else
        print_warning "No integration tests found (tests/integration/ directory missing)"
        return 0
    fi
}

# =============================================================================
# Pipeline Tests
# =============================================================================

run_pipeline_tests() {
    print_section "Running Pipeline Tests"

    cd "$PROJECT_ROOT"

    if [ -d "tests/pipelines" ]; then
        pytest tests/pipelines/ \
            -v \
            --tb=short \
            -m pipeline

        if [ $? -eq 0 ]; then
            print_status "Pipeline tests passed"
            return 0
        else
            print_error "Pipeline tests failed"
            FAILED=1
            return 1
        fi
    else
        print_warning "No pipeline tests found (expected in Phase 3+)"
        return 0
    fi
}

# =============================================================================
# Coverage Report
# =============================================================================

generate_coverage_report() {
    print_section "Coverage Summary"

    if [ -d "$PROJECT_ROOT/htmlcov" ]; then
        print_info "HTML coverage reports generated:"
        find "$PROJECT_ROOT/htmlcov" -name "index.html" -exec echo "  - file://{}" \;
    fi

    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

print_header "Oracul Platform - Test Runner"

# Show test type
print_info "Test type: $TEST_TYPE"
echo ""

# Run prerequisite checks
check_prerequisites

# Execute tests based on type
case "$TEST_TYPE" in
    "lint")
        run_linters
        ;;

    "unit")
        run_unit_tests
        ;;

    "api")
        run_api_tests
        ;;

    "integration")
        run_integration_tests
        ;;

    "pipeline")
        run_pipeline_tests
        ;;

    "all")
        run_linters
        run_unit_tests
        run_api_tests
        run_integration_tests
        run_pipeline_tests
        generate_coverage_report
        ;;

    *)
        print_error "Unknown test type: $TEST_TYPE"
        echo ""
        echo "Usage: $0 [all|lint|unit|api|integration|pipeline]"
        echo ""
        exit 1
        ;;
esac

# Summary
print_header "Test Summary"

if [ $FAILED -eq 0 ]; then
    print_status "All tests passed!"
    echo ""
    exit 0
else
    print_error "Some tests failed"
    echo ""
    exit 1
fi
