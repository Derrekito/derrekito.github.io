---
title: "Part 3: Docker Compose Patterns for Multi-Service Trading Infrastructure"
date: 2027-02-28 10:00:00 -0700
categories: [Trading Systems, DevOps]
tags: [docker, docker-compose, containers, microservices, infrastructure, devops]
series: real-time-trading-infrastructure
series_order: 3
---

*Part 3 of the [Real-Time Trading Infrastructure series](/posts/real-time-trading-infrastructure-series/). Previous: [Part 2: Message Queue Architecture](/posts/message-queue-trading-architecture/). Next: [Part 4: Time-Series Database Integration](/posts/timeseries-database-trading/).*

Trading systems comprise multiple interdependent services: market data ingestion, order management, risk calculation, position tracking, and database persistence. Managing these services individually—starting them in the correct order, ensuring network connectivity, handling restarts—quickly becomes untenable. Docker Compose provides declarative infrastructure definition, transforming complex multi-service deployments into reproducible, version-controlled configurations.

This post presents practical Docker Compose patterns for trading infrastructure, covering service dependencies, network isolation, volume strategies, and environment management. The patterns apply equally to development environments and production deployments, with specific considerations for each context.

## Service Dependency Management

Trading services exhibit strict startup ordering requirements. The database must accept connections before the order management service attempts schema migrations. The message broker must be ready before producers and consumers connect. Health checks transform implicit timing assumptions into explicit readiness guarantees.

### Health Check Patterns

A service declaring `depends_on` without health checks only waits for container startup, not application readiness. The database container starts in milliseconds; the database engine accepting connections takes seconds. Health checks bridge this gap:

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: trading
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
      POSTGRES_DB: trading_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U trading -d trading_db"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - backend

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass "${REDIS_PASSWORD}"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - backend

  rabbitmq:
    image: rabbitmq:3-management-alpine
    environment:
      RABBITMQ_DEFAULT_USER: trading
      RABBITMQ_DEFAULT_PASS_FILE: /run/secrets/rabbitmq_password
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      timeout: 10s
      retries: 5
      start_period: 30s
    networks:
      - backend
```

The `start_period` parameter proves critical for services with lengthy initialization. RabbitMQ performs cluster formation and plugin loading before accepting connections; a 30-second start period prevents premature health check failures during normal startup.

### Dependency Conditions

Compose version 3.9+ supports health-based dependency conditions:

```yaml
services:
  order-service:
    build:
      context: ./services/order-service
      dockerfile: Dockerfile
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://trading:${DB_PASSWORD}@postgres:5432/trading_db
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      RABBITMQ_URL: amqp://trading:${RABBITMQ_PASSWORD}@rabbitmq:5672
    networks:
      - backend
      - frontend
```

The `condition: service_healthy` directive ensures the order service starts only after all infrastructure services report healthy status. Without this condition, connection retry logic must handle infrastructure unavailability—logic that belongs in infrastructure orchestration, not application code.

### Health Check Timing Considerations

The `start_period` parameter deserves particular attention for services with lengthy initialization sequences. During this period, health check failures do not count toward the retry limit. RabbitMQ exemplifies this requirement: cluster formation, plugin loading, and queue recovery may require 30-60 seconds on large installations. Setting an appropriate start period prevents premature container restarts during normal initialization.

Timeout values should account for worst-case response times under load. A database health check that succeeds in 10ms during idle periods may require 3-5 seconds when the system processes bulk inserts. Conservative timeout settings prevent false-positive health failures during legitimate high-load scenarios.

| Parameter | Database | Cache | Message Queue | Application |
|-----------|----------|-------|---------------|-------------|
| `interval` | 5-10s | 3-5s | 10-15s | 10-30s |
| `timeout` | 5s | 3s | 10s | 10s |
| `retries` | 5 | 5 | 5 | 3 |
| `start_period` | 10-30s | 5s | 30-60s | 15-60s |

These values represent starting points; production systems should tune parameters based on observed behavior under load.

## Network Isolation Between Service Layers

Trading infrastructure benefits from network segmentation. Market data ingestion services require external connectivity; internal calculation engines should not. Database services need connectivity from application services but not from the public internet. Docker networks enforce these boundaries at the container runtime level.

### Multi-Network Architecture

```yaml
networks:
  frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/24
  backend:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.29.0.0/24
  market-data:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24

services:
  # External-facing API gateway
  api-gateway:
    build: ./services/api-gateway
    ports:
      - "8080:8080"
    networks:
      - frontend
      - backend

  # Market data ingestion (requires external connectivity)
  market-data-ingester:
    build: ./services/market-data-ingester
    networks:
      - market-data
      - backend
    dns:
      - 8.8.8.8
      - 8.8.4.4

  # Internal calculation service (no external access needed)
  risk-engine:
    build: ./services/risk-engine
    networks:
      - backend

  # Database (backend only)
  postgres:
    image: postgres:16-alpine
    networks:
      - backend
```

The `internal: true` flag on the backend network prevents outbound internet connectivity. Services on this network communicate with each other but cannot initiate external connections—a defense-in-depth measure limiting blast radius if a service is compromised.

### Service Discovery

Docker Compose provides automatic DNS resolution using service names. The order service connects to `postgres:5432` rather than hardcoded IP addresses. This abstraction enables service replacement without configuration changes—swapping PostgreSQL for a compatible database requires only changing the service definition, not application configuration.

For services with multiple replicas, Docker's embedded DNS returns all container IP addresses. Round-robin resolution distributes requests across instances. More sophisticated load balancing requires explicit configuration through reverse proxies or service meshes.

### Network Aliases

Services occasionally require multiple names for backward compatibility or environment parity:

```yaml
services:
  postgres:
    image: postgres:16-alpine
    networks:
      backend:
        aliases:
          - database
          - db
          - trading-db
```

All aliases resolve to the same container, enabling gradual configuration migration without coordinated changes across dependent services.

## Volume Strategies for Database Persistence

Trading data is irreplaceable. Position records, order history, and audit logs require persistence guarantees beyond container lifecycle. Volume configuration determines whether a `docker compose down` results in data loss or data preservation.

### Named Volumes for Production Data

```yaml
volumes:
  postgres_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /opt/trading/data/postgres

  redis_data:
    driver: local

  rabbitmq_data:
    driver: local

  timescale_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /opt/trading/data/timescale
```

Bind-mounting to specific host directories enables backup integration with existing infrastructure. The `/opt/trading/data` hierarchy can be backed up by traditional tools without Docker-specific considerations.

### Initialization Scripts

Database schemas require initialization on first startup. Docker entry points execute scripts in `/docker-entrypoint-initdb.d/` during initial database creation:

```yaml
services:
  postgres:
    image: postgres:16-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/init:/docker-entrypoint-initdb.d:ro
      - ./database/migrations:/migrations:ro
```

The `:ro` suffix mounts directories read-only, preventing container processes from modifying initialization scripts. This immutability guarantee supports reproducible deployments.

### Backup Considerations

Volume backup strategies differ between development and production:

```yaml
services:
  postgres-backup:
    image: postgres:16-alpine
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./backups:/backups
    environment:
      PGPASSWORD_FILE: /run/secrets/db_password
    entrypoint: >
      /bin/sh -c "
        while true; do
          pg_dump -h postgres -U trading trading_db | gzip > /backups/trading_$$(date +%Y%m%d_%H%M%S).sql.gz
          sleep 3600
        done
      "
    networks:
      - backend
    profiles:
      - backup
```

The `profiles` feature enables optional services. Running `docker compose --profile backup up` starts the backup service; standard `docker compose up` excludes it. Development environments skip backup overhead while production deployments include it.

## Environment-Based Configuration Management

Trading applications require different configurations across environments: database credentials, API endpoints, feature flags, and logging levels. Environment variable injection separates configuration from container images.

### Environment File Structure

```
.
├── docker-compose.yml
├── docker-compose.override.yml      # Development overrides (auto-loaded)
├── docker-compose.prod.yml          # Production overrides
├── .env                             # Default environment (development)
├── .env.production                  # Production environment
└── .env.example                     # Template (committed to version control)
```

The base `docker-compose.yml` defines service structure. Override files modify behavior for specific environments:

```yaml
# docker-compose.yml (base)
services:
  order-service:
    build:
      context: ./services/order-service
    env_file:
      - .env
    networks:
      - backend

# docker-compose.override.yml (development, auto-loaded)
services:
  order-service:
    build:
      context: ./services/order-service
      target: development
    volumes:
      - ./services/order-service/src:/app/src:ro
    environment:
      LOG_LEVEL: debug
      RELOAD: "true"
    ports:
      - "8001:8000"

# docker-compose.prod.yml (production)
services:
  order-service:
    build:
      context: ./services/order-service
      target: production
    environment:
      LOG_LEVEL: warning
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '2'
          memory: 4G
```

Development deployments mount source code for hot-reloading; production deployments specify resource limits and replicas.

### Environment Variable Precedence

Compose resolves environment variables in order:

1. Shell environment variables
2. Variables in `.env` file
3. Variables in `env_file` directive
4. Default values in compose file (`${VAR:-default}`)

This precedence enables CI/CD pipelines to override defaults without modifying files:

```bash
# CI/CD deployment
export DATABASE_URL="postgresql://prod-user:${DB_SECRET}@prod-db:5432/trading"
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

## Local Development vs Production Parity

Development environments prioritize iteration speed; production environments prioritize reliability and performance. Docker Compose profiles and multi-stage builds balance these requirements.

### Multi-Stage Dockerfile Pattern

```dockerfile
# Base stage with shared dependencies
FROM python:3.12-slim AS base
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Development stage with hot-reload support
FROM base AS development
RUN pip install watchdog debugpy
COPY . .
CMD ["python", "-m", "debugpy", "--listen", "0.0.0.0:5678", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--reload"]

# Production stage with optimized image
FROM base AS production
COPY --from=base /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY . .
RUN python -m compileall .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--workers", "4"]
```

The `target` build argument selects stages:

```yaml
services:
  order-service:
    build:
      context: ./services/order-service
      target: ${BUILD_TARGET:-development}
```

### Development Tooling Services

Development environments benefit from additional tooling not present in production:

```yaml
services:
  # Database admin interface (development only)
  pgadmin:
    image: dpage/pgadmin4:latest
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@localhost
      PGADMIN_DEFAULT_PASSWORD: admin
      PGADMIN_CONFIG_SERVER_MODE: "False"
    ports:
      - "5050:80"
    networks:
      - backend
    profiles:
      - tools

  # Message queue management (development only)
  rabbitmq:
    ports:
      - "15672:15672"  # Management UI
    profiles:
      - tools
```

Running `docker compose --profile tools up` includes administrative interfaces; production deployments exclude them.

## Resource Constraints and Scaling

Trading workloads exhibit predictable resource patterns: market data ingestion peaks at market open, risk calculations spike during high volatility, and database operations concentrate around settlement times. Resource constraints prevent runaway services from affecting neighbors.

### Memory and CPU Limits

```yaml
services:
  market-data-ingester:
    build: ./services/market-data-ingester
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '1'
          memory: 2G

  risk-engine:
    build: ./services/risk-engine
    deploy:
      resources:
        limits:
          cpus: '8'
          memory: 16G
        reservations:
          cpus: '2'
          memory: 4G
      replicas: 2
```

Reservations guarantee minimum resources; limits prevent overconsumption. The risk engine reserves 2 CPUs and 4GB RAM but can burst to 8 CPUs and 16GB when available.

Memory limits prove particularly critical for trading systems. A memory leak in a market data processor can consume all available memory, triggering OOM kills across unrelated services. Container memory limits isolate failures: the leaking service terminates while others continue operation.

CPU constraints operate differently. Docker throttles CPU access rather than terminating containers. A compute-intensive calculation may take longer with CPU limits but completes without disruption. This behavior makes CPU limits safer for latency-tolerant batch processing while requiring careful tuning for latency-sensitive order execution paths.

### Horizontal Scaling Patterns

```yaml
services:
  order-service:
    build: ./services/order-service
    deploy:
      replicas: 3
      endpoint_mode: dnsrr
    networks:
      - backend

  nginx:
    image: nginx:alpine
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - order-service
    ports:
      - "80:80"
    networks:
      - frontend
      - backend
```

The `endpoint_mode: dnsrr` returns multiple IP addresses for the service name, enabling client-side load balancing or upstream load balancer configuration.

## Secrets Management Approaches

Credentials, API keys, and certificates require protection beyond environment variables. Docker secrets provide file-based secret injection without environment variable exposure (which appears in process listings and logs).

### Docker Secrets Pattern

```yaml
secrets:
  db_password:
    file: ./secrets/db_password.txt
  rabbitmq_password:
    file: ./secrets/rabbitmq_password.txt
  api_key:
    file: ./secrets/api_key.txt

services:
  postgres:
    image: postgres:16-alpine
    secrets:
      - db_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password

  order-service:
    build: ./services/order-service
    secrets:
      - db_password
      - api_key
    environment:
      DATABASE_PASSWORD_FILE: /run/secrets/db_password
      API_KEY_FILE: /run/secrets/api_key
```

Secrets mount as files in `/run/secrets/`. Applications read credentials from files rather than environment variables, preventing accidental exposure in logs or process tables.

### External Secrets Integration

Production environments often require external secret managers:

```yaml
secrets:
  db_password:
    external: true
    name: trading_db_password_v2
```

External secrets integrate with Docker Swarm secret management or third-party solutions. The compose file references secret names without containing actual values.

### Development vs Production Secrets

```yaml
# docker-compose.override.yml (development)
secrets:
  db_password:
    file: ./secrets/dev/db_password.txt

# docker-compose.prod.yml (production)
secrets:
  db_password:
    external: true
    name: prod_trading_db_password
```

Development uses local files (excluded from version control via `.gitignore`); production references externally managed secrets.

### Secret Rotation Strategy

Trading systems require periodic credential rotation without service disruption. Versioned secret names facilitate gradual migration:

```yaml
secrets:
  db_password_v1:
    external: true
  db_password_v2:
    external: true

services:
  order-service:
    secrets:
      - db_password_v2  # New version
  legacy-service:
    secrets:
      - db_password_v1  # Pending migration
```

This pattern enables rolling credential updates: deploy services with new credentials, verify operation, then deprecate old secrets. Attempting atomic rotation across all services introduces coordination risk; versioned secrets eliminate this dependency.

## Complete Infrastructure Example

The following compose file integrates patterns presented throughout this post:

```yaml
version: "3.9"

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true
  market-data:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  rabbitmq_data:
  timescale_data:

secrets:
  db_password:
    file: ./secrets/db_password.txt
  redis_password:
    file: ./secrets/redis_password.txt
  rabbitmq_password:
    file: ./secrets/rabbitmq_password.txt

services:
  postgres:
    image: postgres:16-alpine
    secrets:
      - db_password
    environment:
      POSTGRES_USER: trading
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
      POSTGRES_DB: trading_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U trading -d trading_db"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - backend
    deploy:
      resources:
        limits:
          memory: 4G

  redis:
    image: redis:7-alpine
    secrets:
      - redis_password
    command: >
      sh -c "redis-server
      --appendonly yes
      --requirepass $$(cat /run/secrets/redis_password)"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - backend

  rabbitmq:
    image: rabbitmq:3-management-alpine
    secrets:
      - rabbitmq_password
    environment:
      RABBITMQ_DEFAULT_USER: trading
      RABBITMQ_DEFAULT_PASS_FILE: /run/secrets/rabbitmq_password
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      timeout: 10s
      retries: 5
      start_period: 30s
    networks:
      - backend

  market-data-ingester:
    build:
      context: ./services/market-data-ingester
      target: ${BUILD_TARGET:-development}
    depends_on:
      rabbitmq:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - market-data
      - backend
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G

  order-service:
    build:
      context: ./services/order-service
      target: ${BUILD_TARGET:-development}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    secrets:
      - db_password
    networks:
      - frontend
      - backend
    deploy:
      replicas: ${ORDER_SERVICE_REPLICAS:-1}
      resources:
        limits:
          cpus: '2'
          memory: 4G

  risk-engine:
    build:
      context: ./services/risk-engine
      target: ${BUILD_TARGET:-development}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    secrets:
      - db_password
    networks:
      - backend
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G

  api-gateway:
    build:
      context: ./services/api-gateway
      target: ${BUILD_TARGET:-development}
    depends_on:
      - order-service
    ports:
      - "${API_PORT:-8080}:8080"
    networks:
      - frontend
      - backend
```

## Summary

Docker Compose transforms multi-service trading infrastructure from ad-hoc scripts into declarative, version-controlled definitions. Health checks ensure services start only when dependencies are ready. Network isolation enforces security boundaries between service tiers. Volume strategies protect critical data. Environment management separates configuration from code. Resource constraints prevent runaway services.

The patterns presented here scale from single-developer workstations to multi-node production deployments. The same compose files that run `docker compose up` locally deploy via CI/CD pipelines with environment-specific overrides.

## Next Steps

[Part 4: Time-Series Database Integration](/posts/timeseries-database-trading/) covers TimescaleDB integration for market data storage, addressing time-series specific considerations including hypertable configuration, continuous aggregates, and retention policies.

---

## Series Navigation

| Part | Topic | Status |
|------|-------|--------|
| 1 | [System Architecture Overview](/posts/trading-infrastructure-architecture/) | Published |
| 2 | [Message Queue Architecture](/posts/message-queue-trading-architecture/) | Published |
| **3** | **Docker Compose Patterns** | **Current** |
| 4 | [Time-Series Database Integration](/posts/timeseries-database-trading/) | Next |
| 5 | Market Data Ingestion Pipeline | Upcoming |
| 6 | Order Management Service | Upcoming |
| 7 | Risk Calculation Engine | Upcoming |
| 8 | Position Tracking System | Upcoming |
| 9 | Monitoring and Alerting | Upcoming |
| 10 | Production Deployment Strategies | Upcoming |
