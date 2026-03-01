---
title: "A Modular, Self-Documenting Makefile for Docker Compose"
date: 2026-06-14 10:00:00 -0700
categories: [DevOps, Docker]
tags: [docker, makefile, docker-compose, automation, devops]
---

A reusable Makefile template for managing Docker Compose projects, featuring colored output, self-documenting help, environment management, database operations, and modular organization.

## Problem Statement

Docker Compose commands are verbose:

```bash
docker compose -f docker-compose.yml up -d
docker compose -f docker-compose.yml logs -f api
docker compose -f docker-compose.yml exec postgres psql -U postgres
docker compose -f docker-compose.yml down --remove-orphans
```

This verbosity leads to scattered shell aliases, disorganized scripts, or repetitive typing of lengthy commands.

## Proposed Solution

A Makefile wraps common operations into concise, memorable commands:

```bash
make up              # Start services
make logs            # Follow all logs
make shell SERVICE=api   # Shell into container
make db-backup       # Backup database
make help            # See all commands
```

## Project Structure

```text
project/
├── Makefile              # Main file, includes modules
├── docker-compose.yml
├── .env.example
├── mk/
│   ├── colors.mk         # Terminal colors with NO_COLOR support
│   ├── helper.mk         # Reusable functions
│   └── help_menu.mk      # Self-documenting help system
├── backups/
├── logs/
└── data/
```

## Main Makefile Implementation

{% raw %}
```makefile
# Docker Compose Management Makefile
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Configuration
DOCKER_COMPOSE_CMD := docker compose --progress=plain
COMPOSE_FILE := docker-compose.yml
COMPOSE := $(DOCKER_COMPOSE_CMD) -f $(COMPOSE_FILE)
PROFILE ?= dev
ECHO := /bin/echo -e

# Include modular components
include mk/colors.mk
include mk/helper.mk
include mk/help_menu.mk

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

##@ Environment Setup

validate: ## Validate Docker and compose file
	@$(call check_docker)
	@$(call check_compose_file)
	@$(ECHO) "$(GREEN)All prerequisites validated$(RESET)"

prepare: ## Create directories and check .env
	@mkdir -p backups logs data
	@if [ ! -f .env ]; then \
		if [ -f .env.example ]; then \
			cp .env.example .env; \
		else \
			$(ECHO) "$(RED)ERROR: .env not found$(RESET)"; \
			exit 1; \
		fi; \
	fi

env-print: ## Show environment variables
	@$(ECHO) "$(BLUE)Environment Variables:$(RESET)"
	@grep -v '^\s*#' .env 2>/dev/null | grep '=' | sed 's/^/  /'

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

##@ Service Management

up: validate ## Start services
	@$(ECHO) "$(BLUE)Starting services...$(RESET)"
	@$(COMPOSE) up -d
	@$(ECHO) "$(GREEN)Services started$(RESET)"

up-dev: validate ## Start with dev profile
	@$(call setup_env_file,.env.dev)
	@$(COMPOSE) --profile dev up -d

up-prod: validate ## Start with prod profile
	@$(call setup_env_file,.env.prod)
	@$(COMPOSE) --profile prod up -d

down: ## Stop and remove services
	@$(COMPOSE) down --remove-orphans

stop: ## Stop without removing
	@$(COMPOSE) stop

start: ## Start stopped services
	@$(COMPOSE) start

restart: ## Restart all or SERVICE=name
	@if [ -n "$(SERVICE)" ]; then \
		$(COMPOSE) restart $(SERVICE); \
	else \
		$(COMPOSE) restart; \
	fi

# =============================================================================
# BUILD OPERATIONS
# =============================================================================

##@ Build

build: validate ## Build all services
	@$(COMPOSE) build

build-no-cache: ## Rebuild without cache
	@$(COMPOSE) build --no-cache --pull

pull: ## Pull latest images
	@$(COMPOSE) pull

# =============================================================================
# LOGS AND MONITORING
# =============================================================================

##@ Monitoring

logs: ## View logs (follow mode)
	@$(COMPOSE) logs -f

logs-service: ## Logs for SERVICE=name
	@$(call check_service,logs-service)
	@$(COMPOSE) logs -f $(SERVICE)

logs-tail: ## Last N lines (LINES=100)
	@$(COMPOSE) logs --tail=$${LINES:-100}

status: ## Show service status
	@$(COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

stats: ## Live resource usage
	@docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

health: ## Check service health
	@$(COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"

top: ## Show processes in containers
	@$(COMPOSE) top

# =============================================================================
# DATABASE OPERATIONS
# =============================================================================

##@ Database

db-shell: ## Open psql shell
	@$(COMPOSE) exec postgres psql -U postgres

db-backup: ## Backup database (DB=name)
	@DB=$${DB:-postgres}; \
	TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	mkdir -p backups; \
	BACKUP="backups/db_$${DB}_$${TIMESTAMP}.sql.gz"; \
	$(COMPOSE) exec -T postgres pg_dump -U postgres $$DB | gzip > "$$BACKUP"; \
	$(ECHO) "$(GREEN)Backup: $$BACKUP ($(shell du -h "$$BACKUP" | cut -f1))$(RESET)"

db-restore: ## Restore from BACKUP=path DB=name
	@if [ -z "$(BACKUP)" ]; then \
		$(ECHO) "$(RED)Usage: make db-restore BACKUP=path/to/backup.sql.gz$(RESET)"; \
		exit 1; \
	fi; \
	DB=$${DB:-postgres}; \
	gunzip -c "$(BACKUP)" | $(COMPOSE) exec -T postgres psql -U postgres $$DB; \
	$(ECHO) "$(GREEN)Restored $$DB from $(BACKUP)$(RESET)"

db-list-backups: ## List available backups
	@ls -lh backups/db_*.sql.gz 2>/dev/null || $(ECHO) "No backups found"

# =============================================================================
# DEVELOPMENT
# =============================================================================

##@ Development

shell: ## Open shell in SERVICE=name
	@$(call check_service,shell)
	@$(COMPOSE) exec $(SERVICE) /bin/bash 2>/dev/null || \
		$(COMPOSE) exec $(SERVICE) /bin/sh

exec: ## Run CMD in SERVICE
	@$(call check_service,exec)
	@if [ -z "$(CMD)" ]; then \
		$(ECHO) "$(RED)Usage: make exec SERVICE=api CMD=\"ls -la\"$(RESET)"; \
		exit 1; \
	fi
	@$(COMPOSE) exec $(SERVICE) $(CMD)

config: ## Validate and show resolved config
	@$(COMPOSE) config

# =============================================================================
# CLEANUP
# =============================================================================

##@ Cleanup

clean: ## Remove containers, networks, volumes
	@$(COMPOSE) down -v --remove-orphans

clean-all: clean ## Also remove images
	@$(COMPOSE) down -v --remove-orphans --rmi all

prune: ## Remove unused Docker resources
	@docker system prune -f

prune-all: ## Remove all unused resources including volumes
	@docker system prune -af --volumes

# =============================================================================
# HELP
# =============================================================================

##@ Help

help: ## Quick reference
	@$(ECHO) "$(CYAN)Docker Compose Management$(RESET)"
	@$(ECHO) ""
	@$(ECHO) "  $(GREEN)make up$(RESET)        Start services"
	@$(ECHO) "  $(GREEN)make down$(RESET)      Stop services"
	@$(ECHO) "  $(GREEN)make logs$(RESET)      View logs"
	@$(ECHO) "  $(GREEN)make status$(RESET)    Show status"
	@$(ECHO) "  $(GREEN)make shell SERVICE=api$(RESET)  Shell into container"
	@$(ECHO) ""
	@$(ECHO) "  $(YELLOW)make help-full$(RESET) Show all commands"

help-full: ## All commands grouped by category
	@$(call render_help_table)
```
{% endraw %}

## Color Module (mk/colors.mk)

```makefile
# Terminal colors with NO_COLOR support
# https://no-color.org/

CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
BLUE := \033[34m
MAGENTA := \033[35m
RESET := \033[0m

# Respect NO_COLOR environment variable
ifeq ($(NO_COLOR),1)
CYAN :=
GREEN :=
YELLOW :=
RED :=
BLUE :=
MAGENTA :=
RESET :=
else ifeq ($(TERM),dumb)
CYAN :=
GREEN :=
YELLOW :=
RED :=
BLUE :=
MAGENTA :=
RESET :=
endif
```

## Helper Module (mk/helper.mk)

```makefile
# Validation functions
define check_service
	@if [ -z "$(SERVICE)" ]; then \
		$(ECHO) "$(RED)ERROR: SERVICE required$(RESET)"; \
		$(ECHO) "$(YELLOW)Example: make $(1) SERVICE=api$(RESET)"; \
		exit 1; \
	fi
endef

define check_docker
	@command -v docker >/dev/null 2>&1 || { \
		$(ECHO) "$(RED)ERROR: Docker not installed$(RESET)"; \
		exit 1; \
	}
	@docker info >/dev/null 2>&1 || { \
		$(ECHO) "$(RED)ERROR: Docker daemon not running$(RESET)"; \
		exit 1; \
	}
endef

define check_compose_file
	@if [ ! -f "$(COMPOSE_FILE)" ]; then \
		$(ECHO) "$(RED)ERROR: $(COMPOSE_FILE) not found$(RESET)"; \
		exit 1; \
	fi
endef

# Environment file management (symlink switching)
define setup_env_file
	@if [ ! -f "$(1)" ]; then \
		$(ECHO) "$(RED)ERROR: $(1) not found$(RESET)"; \
		exit 1; \
	fi
	@if [ -f .env ] && [ ! -L .env ]; then \
		$(ECHO) "$(YELLOW)Backing up .env to .env.backup$(RESET)"; \
		mv .env .env.backup; \
	fi
	@ln -sf $(1) .env
	@$(ECHO) "$(GREEN)Environment: .env -> $(1)$(RESET)"
endef
```

## Self-Documenting Help System (mk/help_menu.mk)

The help system parses Makefile comments: `##` comments become help text, and `##@` creates section headers.

```makefile
# Render help from Makefile comments
# - Lines with "##@" become section headers
# - Lines with "target: ## description" become entries

define render_help_table
	@awk ' \
	/^##@/ { \
		section = substr($$0, 5); \
		printf "\n$(YELLOW)%s$(RESET)\n", section; \
		next; \
	} \
	/^[a-zA-Z_-]+:.*##/ { \
		target = $$1; \
		gsub(/:.*/, "", target); \
		desc = $$0; \
		gsub(/^.*## /, "", desc); \
		printf "  $(GREEN)%-18s$(RESET) %s\n", target, desc; \
	}' $(MAKEFILE_LIST)
endef

# List services from compose file
define render_services
	@$(COMPOSE) config --services 2>/dev/null | sort | sed 's/^/  - /'
endef
```

## Usage Examples

### Basic Workflow

```bash
# First time setup
make prepare         # Create directories, copy .env.example

# Daily use
make up              # Start everything
make status          # Check what's running
make logs            # Follow logs
make down            # Stop everything
```

### Service-Specific Operations

```bash
# Target specific service
make restart SERVICE=api
make logs-service SERVICE=worker
make shell SERVICE=postgres

# Execute commands
make exec SERVICE=api CMD="python manage.py migrate"
make exec SERVICE=node CMD="npm test"
```

### Database Operations

```bash
# Backup
make db-backup                    # Backup 'postgres' database
make db-backup DB=myapp           # Backup specific database

# Restore
make db-restore BACKUP=backups/db_myapp_20260614.sql.gz

# List backups
make db-list-backups
```

### Environment Switching

```bash
# Development (uses .env.dev)
make up-dev

# Production (uses .env.prod)
make up-prod

# Check current environment
make env-print
```

### Help Commands

```bash
make help        # Quick reference
make help-full   # All commands with descriptions
```

Output of `make help-full`:

```text
Environment Setup
  validate           Validate Docker and compose file
  prepare            Create directories and check .env
  env-print          Show environment variables

Service Management
  up                 Start services
  up-dev             Start with dev profile
  up-prod            Start with prod profile
  down               Stop and remove services
  ...

Database
  db-shell           Open psql shell
  db-backup          Backup database (DB=name)
  db-restore         Restore from BACKUP=path DB=name
  ...
```

## Customization

### Adding New Targets

New targets follow this pattern:

```makefile
##@ My Category

my-target: validate ## Description of what it does
	@$(ECHO) "$(BLUE)Doing something...$(RESET)"
	@# actual commands here
	@$(ECHO) "$(GREEN)Done$(RESET)"
```

The `##` comment becomes the help text, and `##@` creates a section header.

### Alternative Database Configuration

For MySQL instead of PostgreSQL:

```makefile
db-shell:
	@$(COMPOSE) exec mysql mysql -u root -p

db-backup:
	@$(COMPOSE) exec mysql mysqldump -u root -p $$DB | gzip > backups/...
```

### Project-Specific Commands

Create `mk/project.mk`:

```makefile
##@ Project Commands

migrate: ## Run database migrations
	@$(COMPOSE) exec api python manage.py migrate

seed: ## Seed database with test data
	@$(COMPOSE) exec api python manage.py seed

test: ## Run test suite
	@$(COMPOSE) exec api pytest
```

Include in main Makefile:

```makefile
include mk/project.mk
```

## Makefile vs. Shell Scripts Comparison

| Feature | Makefile | Shell Scripts |
|---------|----------|---------------|
| Dependency tracking | Built-in | Manual |
| Tab completion | Works automatically | Requires setup |
| Self-documenting | `make help` pattern | Manual |
| Parallel execution | `make -j` | Manual |
| Dry run | `make -n` | Manual |
| Standard | Universal | Varies |

## Summary

This Makefile template provides:

- **Concise commands**: `make up` replaces `docker compose -f ...`
- **Self-documentation**: `make help` displays all available commands
- **Consistent output**: Colored feedback indicates success or failure
- **Validation**: Prerequisites are verified before execution
- **Modularity**: Reusable include files enable code organization
- **Environment handling**: Simplified switching between development and production configurations

The template can be cloned, customized, and applied to any Docker Compose project.
