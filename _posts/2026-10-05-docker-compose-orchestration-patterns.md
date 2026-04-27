---
title: "Real-Time Telemetry (Part 4): Docker Compose Orchestration for Multi-Service Systems"
date: 2026-10-05
categories: [DevOps, Docker]
tags: [docker, docker-compose, makefile, orchestration, devops, containers]
series: real-time-telemetry
series_order: 4
---

A telemetry pipeline involves multiple services: message broker, database, ingestion workers, dashboard, and simulators. Managing these manually—starting in order, passing configuration, checking health—doesn't scale. Docker Compose orchestrates the entire stack. A Makefile provides the human interface. This post covers patterns for multi-service orchestration: profiles for different environments, health checks for startup ordering, environment management, and Makefile automation.

## The Stack

Our telemetry system comprises:

| Service | Role | Dependencies |
|---------|------|--------------|
| `mqtt` | Message broker (Mosquitto) | None |
| `mongodb` | Persistent storage | None |
| `mqtt_ingest` | MQTT → MongoDB bridge | mqtt, mongodb |
| `dut_ingest` | Device data processor | mqtt, mongodb, mqtt_ingest |
| `dash` | Web dashboard | mqtt, mongodb |
| `dut_sim` | Device simulator | dut_ingest |
| `pacs_sim` | Sensor simulator | mqtt |

Some services are always needed (core infrastructure). Others are optional (simulators for development, dashboard for monitoring).

## Profiles: Grouping Services

Docker Compose profiles group services by purpose. Services only start when their profile is activated.

```yaml
services:
  mqtt:
    profiles: [core, prod]
    build: ./mqtt
    # ...

  mongodb:
    profiles: [core, prod]
    build: ./mongodb
    # ...

  mqtt_ingest:
    profiles: [core, prod]
    build: ./mqtt_ingest
    # ...

  dash:
    profiles: [ui, prod]
    build: ./dash
    # ...

  dut_sim:
    profiles: [sim]
    build: ./dut_sim
    # ...

  pacs_sim:
    profiles: [sim]
    build: ./pacs_sim
    # ...
```

Start different configurations:

```bash
# Core infrastructure only
docker compose --profile core up -d

# Core + simulators (development)
docker compose --profile core --profile sim up -d

# Production (core + UI, no simulators)
docker compose --profile prod up -d

# Everything
docker compose --profile core --profile sim --profile ui up -d
```

Profiles prevent accidentally running simulators in production or forgetting to start the database.

## Health Checks

Services must wait for dependencies to be *ready*, not just *started*. A container starting doesn't mean the application inside is accepting connections.

### MQTT Broker Health Check

Test by publishing a message:

```yaml
mqtt:
  build: ./mqtt
  healthcheck:
    test: ["CMD-SHELL", "mosquitto_pub -h localhost -t healthcheck -m test -q 1 || exit 1"]
    interval: 5s
    timeout: 3s
    retries: 5
    start_period: 10s
```

If `mosquitto_pub` succeeds, the broker is accepting connections. The `start_period` gives the broker time to initialize before health checks begin.

### MongoDB Health Check

Test TCP connectivity:

```yaml
mongodb:
  build: ./mongodb
  healthcheck:
    test: ["CMD", "nc", "-z", "localhost", "27017"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 20s
```

Alternatively, use `mongosh` for a deeper check:

```yaml
healthcheck:
  test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### Custom Application Health Check

For custom services, implement a health endpoint or use a ping mechanism:

```yaml
dut_ingest:
  build: ./dut_ingest
  healthcheck:
    test: ["CMD-SHELL", "python -c \"import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(1); s.sendto(b'ping', ('127.0.0.1', 5000)); data=s.recv(1024); exit(0 if data==b'pong' else 1)\""]
    interval: 30s
    timeout: 10s
    start_period: 5s
    retries: 3
```

The application responds to UDP pings with pongs. The health check verifies this works.

## Dependency Ordering

Use `depends_on` with `condition: service_healthy` to enforce startup order:

```yaml
services:
  mqtt_ingest:
    depends_on:
      mqtt:
        condition: service_healthy
      mongodb:
        condition: service_healthy

  dash:
    depends_on:
      mqtt:
        condition: service_healthy
      mongodb:
        condition: service_healthy

  dut_sim:
    depends_on:
      dut_ingest:
        condition: service_started
      mqtt:
        condition: service_healthy
```

The ingestion service waits for both MQTT and MongoDB to be healthy. The simulator waits for the ingestion service to start (it doesn't need to be healthy, just running).

## Environment Configuration

### Environment Files

Store configuration in `.env` files:

```bash
# .env.local - Development configuration
MQTT_HOST=mqtt
MQTT_PORT=1883
MONGO_HOST=mongodb
MONGODB_PORT=27017
MONGO_DB=telemetry
DASH_PORT=8050

# MQTT Topics
MQTT_SENSOR_TOPIC=telemetry/sensors
MQTT_EVENT_TOPIC=telemetry/events
MQTT_RUN_TOPIC=telemetry/run

# Test configuration
TEST_FACILITY=Lab-A
TEST_NAME=integration_test
```

```bash
# .env.prod - Production configuration
MQTT_HOST=mqtt.prod.internal
MQTT_PORT=1883
MONGO_HOST=mongodb.prod.internal
MONGODB_PORT=27017
MONGO_DB=telemetry_prod
DASH_PORT=80
```

Symlink the active configuration:

```bash
ln -sf .env.local .env   # Development
ln -sf .env.prod .env    # Production
```

### Injecting Environment Variables

Reference environment variables in `docker-compose.yml`:

```yaml
services:
  mqtt:
    ports:
      - "${MQTT_PORT}:1883"

  mongodb:
    ports:
      - "${MONGODB_PORT}:27017"

  dash:
    ports:
      - "${DASH_PORT}:8050"
    environment:
      - DASH_PORT=${DASH_PORT}
      - MONGO_HOST=${MONGO_HOST}
      - MONGO_PORT=${MONGODB_PORT}
      - MONGO_DB=${MONGO_DB}
      - MQTT_SENSOR_TOPIC=${MQTT_SENSOR_TOPIC}
      - MQTT_EVENT_TOPIC=${MQTT_EVENT_TOPIC}
```

Services receive their configuration through environment variables. Change the `.env` file to reconfigure without modifying `docker-compose.yml`.

## Network Configuration

Create an isolated network for inter-service communication:

```yaml
networks:
  backend:
    driver: bridge
    enable_ipv6: false
    ipam:
      config:
        - subnet: 172.30.1.0/24

services:
  mqtt:
    networks:
      - backend

  mongodb:
    networks:
      - backend

  mqtt_ingest:
    networks:
      - backend
```

Services communicate via container names (`mqtt`, `mongodb`) within the network. External access goes through published ports.

## Volume Management

### Persistent Data

Mount volumes for data that must survive container restarts:

```yaml
services:
  mongodb:
    volumes:
      - ./mongodb/data:/data/db           # Persistent database
      - ./mongodb/init:/docker-entrypoint-initdb.d  # Init scripts
      - /etc/localtime:/etc/localtime:ro  # Sync timezone
```

### Development Mounts

Mount source code for live reloading during development:

```yaml
services:
  dash:
    volumes:
      - ./dash/src:/src  # Live reload on code changes
```

### Shared State

Use named volumes for shared state between containers:

```yaml
volumes:
  dut-pty:  # Shared virtual serial port

services:
  dut_sim:
    volumes:
      - dut-pty:/shared-pty
```

## Makefile Automation

A Makefile provides a human-friendly interface to Docker Compose commands.

### Basic Structure

```make
SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE_FILE := docker-compose.yml
DOCKER_COMPOSE := docker compose --progress=plain -f $(COMPOSE_FILE)

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RED := \033[0;31m
RESET := \033[0m

##@ Environment Setup
.PHONY: validate
validate: ## Validate Docker and compose file
	@command -v docker >/dev/null || (echo "Docker not found" && exit 1)
	@docker info >/dev/null || (echo "Docker daemon not running" && exit 1)
	@test -f $(COMPOSE_FILE) || (echo "$(COMPOSE_FILE) not found" && exit 1)
	@echo -e "$(GREEN)✓ Validation passed$(RESET)"

.PHONY: prepare
prepare: ## Create directories and check .env
	@mkdir -p mongodb/data mongodb/init
	@test -f .env || (echo -e "$(RED)✗ .env not found$(RESET)" && exit 1)
	@echo -e "$(GREEN)✓ Preparation complete$(RESET)"
```

### Build Targets

```make
##@ Build Operations
.PHONY: build-prod
build-prod: validate prepare ## Build production stack
	@echo -e "$(BLUE)Building production containers...$(RESET)"
	$(DOCKER_COMPOSE) --profile prod build
	@echo -e "$(GREEN)✓ Build complete$(RESET)"

.PHONY: build-sim
build-sim: validate prepare ## Build simulation stack
	@echo -e "$(BLUE)Building simulation containers...$(RESET)"
	$(DOCKER_COMPOSE) --profile core --profile sim build
	@echo -e "$(GREEN)✓ Build complete$(RESET)"

.PHONY: build-all
build-all: ## Build all stacks
	@$(MAKE) build-prod
	@$(MAKE) build-sim

.PHONY: build-no-cache
build-no-cache: validate ## Force rebuild without cache
	$(DOCKER_COMPOSE) build --no-cache --pull
```

### Service Management

```make
##@ Service Management
.PHONY: up-prod
up-prod: validate ## Start production services
	@ln -sf .env.prod .env
	@echo -e "$(BLUE)Starting production services...$(RESET)"
	$(DOCKER_COMPOSE) --profile prod up -d
	@echo -e "$(GREEN)✓ Services started$(RESET)"

.PHONY: up-sim
up-sim: validate ## Start simulation services
	@ln -sf .env.local .env
	@echo -e "$(BLUE)Starting simulation services...$(RESET)"
	$(DOCKER_COMPOSE) --profile core --profile sim up -d
	@echo -e "$(GREEN)✓ Services started$(RESET)"

.PHONY: up-debug
up-debug: validate ## Start with DEBUG logging, stop on exit
	@ln -sf .env.local .env
	LOGLEVEL=DEBUG $(DOCKER_COMPOSE) --profile core --profile sim up --abort-on-container-exit

.PHONY: down
down: ## Stop all services
	@echo -e "$(BLUE)Stopping services...$(RESET)"
	$(DOCKER_COMPOSE) --profile core --profile prod --profile sim --profile ui down --remove-orphans
	@echo -e "$(GREEN)✓ Services stopped$(RESET)"

.PHONY: restart
restart: ## Restart all or specific service (SERVICE=name)
	@if [ -n "$(SERVICE)" ]; then \
		echo -e "$(BLUE)Restarting $(SERVICE)...$(RESET)"; \
		$(DOCKER_COMPOSE) restart $(SERVICE); \
	else \
		echo -e "$(BLUE)Restarting all services...$(RESET)"; \
		$(DOCKER_COMPOSE) restart; \
	fi
```

### Monitoring Targets

```make
##@ Monitoring
.PHONY: status
status: ## Show service status
	@echo -e "$(BLUE)Service Status:$(RESET)"
	@$(DOCKER_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

.PHONY: health
health: ## Check service health
	@$(DOCKER_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"

.PHONY: logs
logs: ## View all logs
	$(DOCKER_COMPOSE) logs -f

.PHONY: logs-service
logs-service: ## View specific service logs (SERVICE=name)
	@test -n "$(SERVICE)" || (echo "SERVICE required" && exit 1)
	$(DOCKER_COMPOSE) logs -f $(SERVICE)

.PHONY: stats
stats: ## Live resource usage
	docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
```

### Development Tools

```make
##@ Development
.PHONY: shell
shell: ## Open shell in container (SERVICE=name)
	@test -n "$(SERVICE)" || (echo "SERVICE required" && exit 1)
	@$(DOCKER_COMPOSE) exec $(SERVICE) /bin/bash 2>/dev/null || \
	 $(DOCKER_COMPOSE) exec $(SERVICE) /bin/sh

.PHONY: exec
exec: ## Execute command (SERVICE=name CMD="command")
	@test -n "$(SERVICE)" || (echo "SERVICE required" && exit 1)
	@test -n "$(CMD)" || (echo "CMD required" && exit 1)
	$(DOCKER_COMPOSE) exec $(SERVICE) $(CMD)
```

### Cleanup Targets

```make
##@ Cleanup
.PHONY: clean
clean: ## Remove containers and networks
	$(DOCKER_COMPOSE) down -v --remove-orphans

.PHONY: clean-all
clean-all: clean ## Remove everything including images
	$(DOCKER_COMPOSE) down -v --remove-orphans --rmi all

.PHONY: prune
prune: ## Remove unused Docker resources
	docker system prune -f

.PHONY: prune-all
prune-all: ## Remove ALL unused resources including volumes
	docker system prune -af --volumes
```

### Help System

```make
##@ Help
.PHONY: help
help: ## Show this help
	@echo -e "$(BLUE)Available targets:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} \
		/^##@/ { printf "\n$(YELLOW)%s$(RESET)\n", substr($$0, 5) } \
		/^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
```

Running `make help` produces:

```
Available targets:

Environment Setup
  validate             Validate Docker and compose file
  prepare              Create directories and check .env

Build Operations
  build-prod           Build production stack
  build-sim            Build simulation stack
  build-all            Build all stacks

Service Management
  up-prod              Start production services
  up-sim               Start simulation services
  down                 Stop all services
  ...
```

### Modular Makefiles

Split large Makefiles into modules:

```make
# Main Makefile
include mk/colors.mk
include mk/helper.mk
include mk/build.mk
include mk/services.mk
include mk/monitoring.mk
include mk/database.mk
```

```make
# mk/helper.mk
define check_service
	@test -n "$(SERVICE)" || (echo "SERVICE required" && exit 1)
endef

define setup_env_file
	@test -f "$(1)" || (echo "$(1) not found" && exit 1)
	@ln -sf $(1) .env
	@echo "Environment: .env -> $(1)"
endef
```

## Database Operations

Include database management in the Makefile:

```make
##@ Database
.PHONY: mongo-shell
mongo-shell: ## Open MongoDB shell
	$(DOCKER_COMPOSE) exec mongodb mongosh $(MONGO_DB)

.PHONY: mongo-backup
mongo-backup: ## Backup database (DB=name)
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	BACKUP_NAME="mongodb_$${DB:-all}_$$TIMESTAMP"; \
	mkdir -p backups; \
	$(DOCKER_COMPOSE) exec mongodb mongodump --db=$(DB) --out=/tmp/backup; \
	docker cp $$($(DOCKER_COMPOSE) ps -q mongodb):/tmp/backup backups/$$BACKUP_NAME; \
	tar -czf backups/$$BACKUP_NAME.tar.gz -C backups $$BACKUP_NAME; \
	rm -rf backups/$$BACKUP_NAME; \
	echo "Backup saved: backups/$$BACKUP_NAME.tar.gz"

.PHONY: mongo-restore
mongo-restore: ## Restore database (BACKUP=path)
	@test -n "$(BACKUP)" || (echo "BACKUP required" && exit 1)
	@TEMP_DIR=$$(mktemp -d); \
	tar -xzf $(BACKUP) -C $$TEMP_DIR; \
	docker cp $$TEMP_DIR/* $$($(DOCKER_COMPOSE) ps -q mongodb):/tmp/restore; \
	$(DOCKER_COMPOSE) exec mongodb mongorestore --drop /tmp/restore; \
	rm -rf $$TEMP_DIR
```

## Failure Testing

Simulate service failures for resilience testing:

```make
##@ Failure Testing
.PHONY: disable-service
disable-service: ## Disable service (SERVICE=name)
	@test -n "$(SERVICE)" || (echo "SERVICE required" && exit 1)
	$(DOCKER_COMPOSE) up -d --scale $(SERVICE)=0
	@echo "$(SERVICE) disabled for failure testing"

.PHONY: failure-report
failure-report: ## Check for errors after failure test
	@$(DOCKER_COMPOSE) logs 2>/dev/null | grep -i "error\|failed\|exception" | head -20 || \
	echo "No errors found"
```

## Complete Workflow

A typical development session:

```bash
# Initial setup
make validate          # Check prerequisites
make prepare           # Create directories

# Build and start
make build-sim         # Build simulation stack
make up-sim            # Start services

# Monitor
make status            # Check service status
make health            # Verify health checks
make logs              # Stream logs

# Development
make shell SERVICE=dash    # Debug in container
make restart SERVICE=dash  # Restart after changes

# Testing
make disable-service SERVICE=mongodb   # Simulate failure
make failure-report                     # Check error handling

# Cleanup
make down              # Stop services
make clean             # Remove containers and volumes
```

## Conclusion

Docker Compose profiles, health checks, and Makefile automation transform a complex multi-service system into something manageable. Profiles separate development from production. Health checks ensure proper startup ordering. Environment files externalize configuration. Makefiles provide discoverable commands.

The result: consistent deployments across machines, predictable startup behavior, and a development experience that doesn't require remembering dozens of Docker commands.

---

*This post is Part 4 of the Real-Time Telemetry series. Previous: [Hardware Test Simulators with Finite State Machines](/posts/hardware-test-simulators-fsm).*
