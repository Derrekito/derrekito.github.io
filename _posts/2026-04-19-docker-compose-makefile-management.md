---
layout: post
title: "Docker Compose Management with Modular Makefiles"
date: 2026-04-19
categories: [docker, devops, automation]
tags: [docker-compose, makefile, cli, development-workflow]
---

Managing Docker Compose environments across development, testing, and production can become unwieldy as projects scale. Simple `docker compose up` commands evolve into sprawling collections of scripts, profiles, and environment configurations with poor discoverability.

This post presents a modular Makefile system that transforms Docker Compose management into an intuitive command-line interface with colored help menus, automatic validation, and organized command categories.

## Problem Statement

A typical Docker Compose project accumulates complexity:

- Multiple profiles (prod, sim, debug, test)
- Environment file switching (.env.local, .env.prod)
- Service-specific operations (start/stop/restart individual containers)
- Database backup and restore operations
- Log management across services
- Health checks and monitoring

Most teams accumulate shell scripts, documentation that becomes stale, and implicit knowledge about command sequences and dependencies.

## Proposed Solution: Modular Makefiles

The system organizes commands into logical modules:

```text
project/
├── Makefile              # Main entry point
├── docker-compose.yml
├── mk/
│   ├── colors.mk         # ANSI color definitions
│   ├── helper.mk         # Reusable functions
│   └── help_menu.mk      # Help rendering logic
└── .env files
```

### Core Architecture

The main Makefile includes modular components:

```makefile
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Use Docker Compose plugin syntax
DOCKER_COMPOSE_CMD := docker compose --progress=plain
COMPOSE_FILE := docker-compose.yml
COMPOSE := $(DOCKER_COMPOSE_CMD) -f $(COMPOSE_FILE)

# Use /bin/echo for consistent escape sequence handling
ECHO := /bin/echo -e

include mk/colors.mk
include mk/helper.mk
include mk/help_menu.mk
```

### Color Support with Fallbacks

The `colors.mk` module handles terminal color support gracefully:

```makefile
# Color codes (only used if COLOR is enabled)
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
BLUE := \033[34m
RESET := \033[0m

# Check for color support: disable if NO_COLOR is set or TERM is dumb
ifeq ($(NO_COLOR),1)
    COLOR := 0
    CYAN :=
    GREEN :=
    YELLOW :=
    RED :=
    BLUE :=
    RESET :=
else ifeq ($(TERM),dumb)
    COLOR := 0
    CYAN :=
    GREEN :=
    YELLOW :=
    RED :=
    BLUE :=
    RESET :=
else
    COLOR := 1
endif
```

This implementation respects the [NO_COLOR](https://no-color.org/) standard and functions correctly in CI environments where `TERM=dumb`.

### Reusable Helper Functions

The `helper.mk` module defines composable functions:

```makefile
# Helper function for running docker compose
define run_compose
    $(DOCKER_COMPOSE_CMD) -f $(COMPOSE_FILE) $(1)
endef

# Run docker compose build with progress=plain
define run_build
    $(call run_compose,build --progress=plain $(1))
endef

# Validation functions
define check_service
    @if [ -z "$(SERVICE)" ]; then \
        $(ECHO) "$(RED)ERROR: SERVICE variable must be set$(RESET)"; \
        $(ECHO) "$(YELLOW)Example: make $(1) SERVICE=mqtt$(RESET)"; \
        exit 1; \
    fi
endef

define check_docker
    @if ! command -v docker >/dev/null 2>&1; then \
        $(ECHO) "$(RED)ERROR: Docker is not installed or not in PATH$(RESET)"; \
        exit 1; \
    fi
    @if ! docker info >/dev/null 2>&1; then \
        $(ECHO) "$(RED)ERROR: Docker daemon is not running$(RESET)"; \
        exit 1; \
    fi
endef

define check_compose_file
    @if [ ! -f "$(COMPOSE_FILE)" ]; then \
        $(ECHO) "$(RED)ERROR: $(COMPOSE_FILE) not found$(RESET)"; \
        exit 1; \
    fi
endef
```

### Environment File Management

Switching between environments is a common source of errors. The following function handles this operation:

```makefile
define setup_env_file
    @if [ ! -f "$(1)" ]; then \
        $(ECHO) "$(RED)ERROR: $(1) not found$(RESET)"; \
        $(ECHO) "$(YELLOW)TIP: Create $(1) with required environment variables$(RESET)"; \
        exit 1; \
    fi; \
    if [ -L .env ]; then \
        rm .env; \
    elif [ -f .env ] && [ ! -L .env ]; then \
        $(ECHO) "$(YELLOW)Backing up existing .env to .env.backup$(RESET)"; \
        mv .env .env.backup; \
    fi; \
    ln -sf $(1) .env; \
    $(ECHO) "$(GREEN)Environment linked: .env -> $(1)$(RESET)"
endef
```

Usage in targets:

```makefile
up-prod: validate
    @$(call setup_env_file,.env.prod)
    @$(ECHO) "$(BLUE)Starting production profile services...$(RESET)"
    @$(call run_compose,--profile prod up -d)

up-sim: validate
    @$(call setup_env_file,.env.local)
    @$(ECHO) "$(BLUE)Starting simulation profile services...$(RESET)"
    @$(call run_compose,--profile core --profile sim up -d)
```

## Self-Documenting Help System

The help rendering system parses specially formatted comments. Each target receives a `##` comment that becomes its documentation:

```makefile
##@ Build Operations
build-prod: ## Rebuild production (hardware) stack only
    @$(MAKE) build-profile BUILD_PROFILES="prod"

build-sim: ## Rebuild simulation stack only
    @$(MAKE) build-profile BUILD_PROFILES="core sim"

build-no-cache: validate prepare ## Force rebuild without cache
    @$(ECHO) "$(BLUE)Force rebuilding without cache...$(RESET)"
    @$(call run_compose,build --no-cache --pull)
```

The `##@` marker creates section headers. The `help_menu.mk` module parses these with AWK:

```makefile
define render_help_table
    @awk ' \
    BEGIN { width = 80; entry_count = 0; in_section = 0; } \
    /^##@/ { \
      if (in_section && entry_count > 0) { printf "$(CYAN)|%78s  |$(RESET)\n", ""; } \
      section = substr($$0, 5); \
      line = " -- " section " "; \
      while (length(line) < width - 1) line = line "-"; \
      printf "$(CYAN)|%s |$(RESET)\n", line; \
      printf "$(CYAN)|%78s  |$(RESET)\n", ""; \
      entry_count = 0; in_section = 1; next; \
    } \
    /^[a-zA-Z0-9_.-]+:.*##/ { \
      split($$0, parts, ":"); \
      target = parts[1]; \
      desc = gensub(/^.*## /, "", "g", $$0); \
      if (length(desc) > 53) desc = substr(desc, 1, 50) "..."; \
      printf "$(CYAN)|$(RESET)   $(YELLOW)%-22s$(RESET) %-53s $(CYAN)|$(RESET)\n", target, desc; \
      entry_count++; \
    } \
    END { if (in_section) printf "$(CYAN)|%78s  |$(RESET)\n", ""; }' $(firstword $(MAKEFILE_LIST))
endef
```

This produces styled help output:

```text
+------------------------------------------------------------------------------+
|                    Docker Compose Quick Reference                            |
+------------------------------------------------------------------------------+
| Essential Commands:                                                          |
|   make build-prod && make up-prod  Build & run production                    |
|   make build-sim && make up-sim    Build & run simulation                    |
|   make down                        Stop all services                         |
|   make logs                        View all logs                             |
|   make status                      Show service status                       |
|                                                                              |
| Get More Help:                                                               |
|   make help-build      Build operations                                      |
|   make help-container  Container management                                  |
|   make help-logs       Logging & monitoring                                  |
|   make help-dev        Development tools                                     |
+------------------------------------------------------------------------------+
```

## Command Categories

### Service Management

```makefile
##@ Service Management
up: validate ## Start test profile services
    @$(ECHO) "$(BLUE)Starting test profile services...$(RESET)"
    @$(call run_compose, up -d)

down: ## Stop and remove all services
    @$(ECHO) "$(BLUE)Stopping and removing all services...$(RESET)"
    @$(call run_compose,--profile core --profile prod --profile sim down --remove-orphans)

restart: validate ## Restart all or specific service(s) (SERVICE=name)
    @bash -c '\
        if [ -n "$(SERVICE)" ]; then \
            $(ECHO) "$(BLUE)Restarting service: $(SERVICE)...$(RESET)"; \
            $(call run_compose,restart $(SERVICE)); \
        else \
            $(ECHO) "$(BLUE)Restarting all services...$(RESET)"; \
            $(call run_compose,restart); \
        fi \
    '
```

### Individual Service Control

```makefile
##@ Individual Service Control
up-service: validate ## Start specific service (e.g., SERVICE=simulator)
    @$(call check_service,up-service)
    @$(ECHO) "$(BLUE)Starting service: $(SERVICE)...$(RESET)"
    @$(call run_compose,up -d $(SERVICE))

stop-service: validate ## Stop specific service (e.g., SERVICE=mqtt)
    @$(call check_service,stop-service)
    @$(ECHO) "$(BLUE)Stopping service: $(SERVICE)...$(RESET)"
    @$(call run_compose,stop $(SERVICE))
```

### Log Management

```makefile
##@ Log Management
logs: validate ## View logs for all services
    @$(call run_compose,logs -f)

logs-service: validate ## View logs for specific service
    @$(call check_service,logs-service)
    @$(call run_compose,logs -f $(SERVICE))

logs-tail: validate ## Show last N lines of logs (LINES=100)
    @bash -c '\
        LINES=$${LINES:-100}; \
        $(ECHO) "$(BLUE)Showing last $$LINES lines of logs...$(RESET)"; \
        $(call run_compose,logs --tail=$$LINES); \
    '

logs-since: validate ## Show logs since timestamp (SINCE="2024-01-01T00:00:00")
    @bash -c '\
        if [ -z "$(SINCE)" ]; then \
            $(ECHO) "$(RED)ERROR: SINCE variable required$(RESET)"; \
            exit 1; \
        fi; \
        $(call run_compose,logs --since="$(SINCE)"); \
    '
```

### Monitoring

{% raw %}
```makefile
##@ Monitoring
status: validate ## Show service status
    @$(call run_compose,ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}")

health: validate ## Check service health
    @$(call run_compose,ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}")

stats: validate ## Show live resource usage statistics
    @docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
```
{% endraw %}

### Database Operations

For projects with MongoDB:

```makefile
##@ Database Operations
mongo-shell: ## Open full mongosh in database
    @$(call run_compose,exec mongodb mongosh mydb)

mongo-backup: ## Backup MongoDB database to ./backups
    @bash -c 'set -e; \
        TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
        mkdir -p backups; \
        BACKUP_NAME="mongodb_$${TIMESTAMP}"; \
        $(call run_compose,exec mongodb mongodump --out=/tmp/backup); \
        CONTAINER_ID=$$($(call run_compose,ps -q mongodb)); \
        docker cp $$CONTAINER_ID:/tmp/backup "backups/$$BACKUP_NAME"; \
        $(call run_compose,exec mongodb rm -rf /tmp/backup); \
        tar -czf "backups/$$BACKUP_NAME.tar.gz" -C backups "$$BACKUP_NAME"; \
        rm -rf "backups/$$BACKUP_NAME"; \
        $(ECHO) "$(GREEN)Backup saved to: backups/$$BACKUP_NAME.tar.gz$(RESET)"; \
    '

mongo-restore: ## Restore MongoDB from backup (BACKUP=path/to/backup.tar.gz)
    @bash -c 'set -e; \
        if [ -z "$(BACKUP)" ]; then \
            $(ECHO) "$(RED)ERROR: BACKUP variable required$(RESET)"; \
            exit 1; \
        fi; \
        TEMP_DIR=$$(mktemp -d); \
        tar -xzf "$(BACKUP)" -C "$$TEMP_DIR"; \
        EXTRACTED_DIR=$$(find $$TEMP_DIR -type d -name "mongodb_*" | head -n1); \
        CONTAINER_ID=$$($(call run_compose,ps -q mongodb)); \
        docker cp "$$EXTRACTED_DIR" $$CONTAINER_ID:/tmp/restore; \
        $(call run_compose,exec mongodb mongorestore --drop /tmp/restore); \
        $(call run_compose,exec mongodb rm -rf /tmp/restore); \
        rm -rf "$$TEMP_DIR"; \
        $(ECHO) "$(GREEN)Database restored successfully$(RESET)"; \
    '
```

### Development Tools

```makefile
##@ Development Tools
shell: validate ## Open shell in container (SERVICE=name)
    @$(call check_service,shell)
    @bash -c '\
        if $(call run_compose,exec $(SERVICE) /bin/bash 2>/dev/null); then \
            true; \
        elif $(call run_compose,exec $(SERVICE) /bin/sh 2>/dev/null); then \
            true; \
        else \
            $(ECHO) "$(RED)Could not open shell in $(SERVICE)$(RESET)"; \
            exit 1; \
        fi \
    '

exec: validate ## Execute command in service (SERVICE=name CMD="command")
    @$(call check_service,exec)
    @bash -c '\
        if [ -z "$(CMD)" ]; then \
            $(ECHO) "$(RED)ERROR: CMD variable required$(RESET)"; \
            exit 1; \
        fi; \
        $(call run_compose,exec $(SERVICE) $(CMD)); \
    '
```

## Adding Custom Command Modules

The modular structure facilitates domain-specific command additions. A new `.mk` file can be created as follows:

```makefile
# mk/myapp.mk - Application-specific commands

include mk/colors.mk
include mk/helper.mk

##@ MyApp Operations
myapp-deploy: ## Deploy latest application version
    @$(ECHO) "$(BLUE)Deploying application...$(RESET)"
    @$(call run_compose,pull myapp)
    @$(call run_compose,up -d myapp)
    @$(ECHO) "$(GREEN)Deployment complete$(RESET)"

myapp-migrate: ## Run database migrations
    @$(ECHO) "$(BLUE)Running migrations...$(RESET)"
    @$(call run_compose,exec myapp python manage.py migrate)
```

Include it in the main Makefile:

```makefile
include mk/myapp.mk
```

The help system automatically incorporates new `##` comments and `##@` sections.

## Implementation Guidelines

1. **Validate prerequisites**: Use `check_docker` and `check_compose_file` before operations requiring these dependencies.

2. **Provide clear error messages**: When a required variable is missing, display both the error and an example of correct usage.

3. **Use colored output consistently**: Green indicates success, red indicates errors, yellow indicates warnings, and blue indicates informational messages.

4. **Make targets composable**: Use `$(MAKE)` to invoke other targets, enabling build pipelines such as `run: prepare build up`.

5. **Handle environment switching safely**: The `setup_env_file` function backs up existing `.env` files and uses symlinks for clarity.

6. **Support both interactive and CI usage**: Respect `NO_COLOR` and `TERM=dumb` for CI environments.

## Conclusion

A well-organized Makefile transforms Docker Compose management from implicit knowledge into a discoverable, self-documenting interface. The modular structure scales with project complexity, and the help system ensures new team members can locate commands without consulting external documentation.

Make already provides the foundation for command organization, dependency management, and parallel execution. Adding colored output, validation functions, and a structured help system creates an effective developer experience.

---

*A starter template implementing this pattern is available for purchase. It includes the complete modular structure, example services, database backup/restore, and all the patterns described in this post.*
