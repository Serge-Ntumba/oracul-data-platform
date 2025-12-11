FROM python:3.11-slim

# Metadata
LABEL maintainer="Oracul Platform Team"
LABEL description="FastAPI service for Oracul blockchain analytics platform"

# Set working directory
WORKDIR /app

# Install system dependencies
# - gcc: Required for compiling ClickHouse driver
# - curl: Required for health checks
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (layer caching optimization)
COPY api/requirements.txt /app/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY api/app /app/app

# Set Python path
ENV PYTHONPATH=/app

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Run with uvicorn
# In development, --reload is enabled via docker-compose environment variable
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
