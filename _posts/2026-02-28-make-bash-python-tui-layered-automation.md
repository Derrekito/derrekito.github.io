---
title: "Layered Automation: Make for Dependencies, Wrappers for UX"
date: 2026-02-28 12:00:00 -0700
categories: [DevOps, Automation]
tags: [make, bash, python, tui, automation, devops]
---

Make is a 48-year-old build tool that refuses to become obsolete—because dependency graphs are genuinely difficult to replace. However, Make's user experience remains rooted in 1976. This post argues for a layered approach: let Make handle what it does best (dependency resolution and incremental builds), while wrapping it with modern tooling for human interaction.

## Rationale for Make

Make solves a fundamental problem: given a set of tasks with dependencies, execute only what is necessary in the correct order.

```makefile
deploy: build test
	./scripts/deploy.sh

build: src/*.go
	go build -o bin/app ./cmd/app

test: build
	go test ./...
```

Running `make deploy` causes Make to:
1. Check if `src/*.go` files are newer than `bin/app`
2. Rebuild only if necessary
3. Run tests only if build succeeded
4. Deploy only if tests passed

This dependency tree is **declarative**. Relationships are described, not procedures. Make determines the execution order and skips unnecessary work.

### Features Provided Automatically

**Incremental builds**: Make compares timestamps. If nothing changed, nothing runs.

```makefile
output/report.pdf: data/results.csv scripts/generate.py
	python scripts/generate.py data/results.csv -o $@
```

Running this twice results in an instant second execution because `results.csv` has not changed.

**Parallel execution**: `make -j4` runs independent targets concurrently.

```makefile
all: service-a service-b service-c

service-a:
	docker build -t service-a ./a

service-b:
	docker build -t service-b ./b

service-c:
	docker build -t service-c ./c
```

With `-j3`, all three images build simultaneously.

**Dry runs**: `make -n deploy` shows what would execute without running anything.

**Failure handling**: If a step fails, Make stops. Dependent targets do not run.

## Limitations of Raw Make

Make's strengths come with real usability costs.

### Cryptic Syntax

```makefile
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@
```

The meaning of `$<` and `$@` (the first prerequisite and the target, respectively) is not immediately apparent. This syntax is concise but hostile to newcomers.

### No Native Help System

Listing available targets requires workarounds:

```makefile
.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

deploy: ## Deploy to production
build: ## Build the application
test: ## Run test suite
```

This works, but it is a pattern that must be known and implemented.

### No Argument Handling

```bash
# This does not work
make deploy --environment=staging --dry-run
```

Make targets do not take arguments. Environment variables must be used:

```bash
ENV=staging DRY_RUN=1 make deploy
```

Functional, but cumbersome.

### Verbose Output

Make echoes every command by default. For complex builds, the output is overwhelming. Suppression requires `@` prefixes:

```makefile
deploy:
	@echo "Deploying..."
	@./scripts/deploy.sh
```

This requires manual management of what users see.

## The Wrapper Solution

Wrappers provide the UX layer that Make lacks while preserving Make's core value.

### Bash Wrapper

A simple shell script adds argument parsing, colors, and help:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << EOF
Usage: ./manage.sh <command> [options]

Commands:
    deploy      Deploy application to target environment
    build       Build all services
    test        Run test suite
    clean       Remove build artifacts
    logs        Tail service logs

Options:
    -e, --env       Target environment (dev|staging|prod)
    -v, --verbose   Show detailed output
    -n, --dry-run   Show what would run without executing
    -h, --help      Show this help message

Examples:
    ./manage.sh deploy --env staging
    ./manage.sh build --verbose
    ./manage.sh test --dry-run
EOF
}

# Defaults
ENV="dev"
VERBOSE=0
DRY_RUN=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENV="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        deploy|build|test|clean|logs)
            COMMAND="$1"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate
if [[ -z "${COMMAND:-}" ]]; then
    echo -e "${RED}Error: No command specified${NC}"
    show_help
    exit 1
fi

# Build make arguments
MAKE_ARGS=""
[[ $VERBOSE -eq 1 ]] && MAKE_ARGS="$MAKE_ARGS VERBOSE=1"
[[ $DRY_RUN -eq 1 ]] && MAKE_ARGS="$MAKE_ARGS -n"

# Execute
echo -e "${BLUE}Running: make $COMMAND ENV=$ENV $MAKE_ARGS${NC}"
make "$COMMAND" ENV="$ENV" $MAKE_ARGS
```

Users now receive:
- Tab completion for commands
- `--help` that provides useful information
- Colored output
- Familiar `--flag` syntax

Make still handles the dependency graph.

### Python TUI Wrapper

For interactive workflows, Python TUI libraries provide rich interfaces:

```python
#!/usr/bin/env python3
"""
Interactive project management TUI.
"""
import subprocess
import sys
from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt, Confirm
from rich.progress import Progress, SpinnerColumn, TextColumn

console = Console()


def get_available_targets() -> list[dict]:
    """Parse Makefile for documented targets."""
    targets = []
    try:
        with open("Makefile") as f:
            for line in f:
                if "##" in line and ":" in line:
                    parts = line.split(":")
                    name = parts[0].strip()
                    desc = parts[1].split("##")[1].strip() if "##" in parts[1] else ""
                    targets.append({"name": name, "description": desc})
    except FileNotFoundError:
        console.print("[red]No Makefile found[/red]")
        sys.exit(1)
    return targets


def show_menu(targets: list[dict]) -> str:
    """Display interactive menu."""
    console.print("\n[bold blue]Available Commands[/bold blue]\n")

    table = Table(show_header=True, header_style="bold magenta")
    table.add_column("#", style="dim", width=4)
    table.add_column("Command", style="cyan")
    table.add_column("Description")

    for i, target in enumerate(targets, 1):
        table.add_row(str(i), target["name"], target["description"])

    console.print(table)
    console.print()

    choice = Prompt.ask(
        "Select command",
        choices=[str(i) for i in range(1, len(targets) + 1)] + ["q"],
        default="q"
    )

    if choice == "q":
        return None
    return targets[int(choice) - 1]["name"]


def get_options(target: str) -> dict:
    """Gather options for the selected target."""
    options = {}

    if target in ["deploy", "build"]:
        options["env"] = Prompt.ask(
            "Environment",
            choices=["dev", "staging", "prod"],
            default="dev"
        )

    options["verbose"] = Confirm.ask("Verbose output?", default=False)
    options["dry_run"] = Confirm.ask("Dry run (show commands only)?", default=False)

    return options


def run_make(target: str, options: dict):
    """Execute make target with options."""
    cmd = ["make", target]

    if options.get("env"):
        cmd.append(f"ENV={options['env']}")
    if options.get("verbose"):
        cmd.append("VERBOSE=1")
    if options.get("dry_run"):
        cmd.insert(1, "-n")

    console.print(f"\n[dim]Running: {' '.join(cmd)}[/dim]\n")

    if options.get("dry_run"):
        subprocess.run(cmd)
        return

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        task = progress.add_task(f"Running {target}...", total=None)
        result = subprocess.run(cmd, capture_output=not options.get("verbose"))
        progress.remove_task(task)

    if result.returncode == 0:
        console.print(f"\n[green]✓ {target} completed successfully[/green]")
    else:
        console.print(f"\n[red]✗ {target} failed[/red]")
        if result.stderr:
            console.print(f"[red]{result.stderr.decode()}[/red]")
        sys.exit(1)


def main():
    console.print("[bold]Project Manager[/bold]", style="blue")

    targets = get_available_targets()
    if not targets:
        console.print("[yellow]No documented targets found[/yellow]")
        console.print("Add ## comments to Makefile targets for documentation")
        sys.exit(1)

    while True:
        target = show_menu(targets)
        if target is None:
            console.print("[dim]Goodbye![/dim]")
            break

        options = get_options(target)

        if Confirm.ask(f"\nRun '{target}'?", default=True):
            run_make(target, options)

        if not Confirm.ask("\nRun another command?", default=True):
            break


if __name__ == "__main__":
    main()
```

This provides:
- Interactive menus with arrow key navigation
- Rich formatted tables
- Spinners during execution
- Confirmation prompts
- Colored status output

### The Layered Architecture

```text
┌─────────────────────────────────────────────────┐
│              User Entry Points                   │
│  ┌──────────────┐  ┌──────────────────────────┐ │
│  │ ./manage.sh  │  │ ./manage.py (TUI)        │ │
│  │ CLI flags    │  │ Interactive menus        │ │
│  └──────┬───────┘  └────────────┬─────────────┘ │
│         │                       │               │
│         └───────────┬───────────┘               │
│                     ▼                           │
├─────────────────────────────────────────────────┤
│                  Makefile                        │
│  • Dependency graph                             │
│  • Incremental builds                           │
│  • Parallel execution                           │
│  • Target orchestration                         │
├─────────────────────────────────────────────────┤
│              Implementation Layer                │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │ scripts/ │ │ docker-  │ │ language-native  │ │
│  │ *.sh     │ │ compose  │ │ tooling          │ │
│  └──────────┘ └──────────┘ └──────────────────┘ │
└─────────────────────────────────────────────────┘
```

Each layer has a single responsibility:
- **Entry points**: UX, argument parsing, human interaction
- **Makefile**: Orchestration, dependencies, build logic
- **Scripts/tools**: Actual implementation of tasks

## Modular Makefiles with mk/

As projects grow, a single Makefile becomes unwieldy. The `mk/` directory pattern splits concerns into focused modules that the main Makefile includes.

### The mk/ Directory Schema

```text
project/
├── Makefile              # Entry point, includes mk/*.mk
├── manage.sh             # Bash wrapper
├── manage.py             # Python TUI
├── mk/
│   ├── config.mk         # Variables, environment detection
│   ├── help.mk           # Help system
│   ├── docker.mk         # Container targets
│   ├── build.mk          # Build targets
│   ├── test.mk           # Test targets
│   ├── deploy.mk         # Deployment targets
│   ├── dev.mk            # Development environment
│   └── utils.mk          # Shared functions/macros
├── scripts/
│   ├── build.sh
│   ├── deploy.sh
│   └── test.sh
└── docker-compose.yml
```

### The Main Makefile

The root Makefile becomes a thin orchestrator:

```makefile
# =============================================================================
# Makefile - Project entry point
# =============================================================================
# This file includes modular makefiles from mk/ directory.
# Each module handles a specific concern.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Include modules in dependency order
include mk/config.mk
include mk/utils.mk
include mk/help.mk
include mk/docker.mk
include mk/build.mk
include mk/test.mk
include mk/deploy.mk
include mk/dev.mk

# =============================================================================
# Composite targets
# =============================================================================

.PHONY: all
all: build test ## Build and test everything

.PHONY: ci
ci: lint test build ## Full CI pipeline
```

### mk/config.mk - Configuration

```makefile
# =============================================================================
# mk/config.mk - Project configuration and environment detection
# =============================================================================

# Project metadata
PROJECT_NAME := myapp
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Environment (override with ENV=staging make deploy)
ENV ?= dev
VALID_ENVS := dev staging prod

# Validate environment
ifeq ($(filter $(ENV),$(VALID_ENVS)),)
    $(error Invalid ENV '$(ENV)'. Must be one of: $(VALID_ENVS))
endif

# Verbosity control
VERBOSE ?= 0
ifeq ($(VERBOSE),1)
    Q :=
    REDIRECT :=
else
    Q := @
    REDIRECT := > /dev/null 2>&1
endif

# Detect OS
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    OS := macos
    SED := gsed
else
    OS := linux
    SED := sed
endif

# Docker configuration
DOCKER_REGISTRY ?= ghcr.io/myorg
DOCKER_TAG ?= $(VERSION)

# Paths
ROOT_DIR := $(shell pwd)
BUILD_DIR := $(ROOT_DIR)/build
DIST_DIR := $(ROOT_DIR)/dist
```

### mk/help.mk - Self-Documenting Help

```makefile
# =============================================================================
# mk/help.mk - Help system
# =============================================================================

# Colors
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RESET := \033[0m
BOLD := \033[1m

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "$(BOLD)$(PROJECT_NAME) v$(VERSION)$(RESET)"
	@echo ""
	@echo "$(BOLD)Usage:$(RESET)"
	@echo "  make $(CYAN)<target>$(RESET) [$(YELLOW)VAR=value$(RESET)]"
	@echo ""
	@echo "$(BOLD)Variables:$(RESET)"
	@echo "  $(YELLOW)ENV$(RESET)       Target environment ($(VALID_ENVS)) [current: $(ENV)]"
	@echo "  $(YELLOW)VERBOSE$(RESET)   Show detailed output (0|1) [current: $(VERBOSE)]"
	@echo ""
	@echo "$(BOLD)Targets:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		sort | \
		awk 'BEGIN {FS = ":.*?## "}; \
			/^#/ {next} \
			{printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""

.PHONY: help-all
help-all: ## Show all targets including internal ones
	@echo "All targets:"
	@grep -E '^[a-zA-Z_-]+:' $(MAKEFILE_LIST) | \
		cut -d: -f1 | \
		sort -u | \
		xargs -I{} echo "  {}"
```

### mk/docker.mk - Container Management

```makefile
# =============================================================================
# mk/docker.mk - Docker and container management
# =============================================================================

DOCKER_COMPOSE := docker-compose
DOCKER_BUILD_ARGS := --build-arg VERSION=$(VERSION) --build-arg BUILD_DATE=$(BUILD_DATE)

.PHONY: docker-build
docker-build: ## Build Docker images
	$(Q)echo "Building Docker images..."
	$(Q)$(DOCKER_COMPOSE) build $(DOCKER_BUILD_ARGS)

.PHONY: docker-push
docker-push: docker-build ## Push images to registry
	$(Q)echo "Pushing to $(DOCKER_REGISTRY)..."
	$(Q)docker push $(DOCKER_REGISTRY)/$(PROJECT_NAME)-api:$(DOCKER_TAG)
	$(Q)docker push $(DOCKER_REGISTRY)/$(PROJECT_NAME)-web:$(DOCKER_TAG)

.PHONY: docker-pull
docker-pull: ## Pull images from registry
	$(Q)docker pull $(DOCKER_REGISTRY)/$(PROJECT_NAME)-api:$(DOCKER_TAG)
	$(Q)docker pull $(DOCKER_REGISTRY)/$(PROJECT_NAME)-web:$(DOCKER_TAG)

.PHONY: docker-clean
docker-clean: ## Remove project images and volumes
	$(Q)$(DOCKER_COMPOSE) down -v --rmi local
	$(Q)docker image prune -f --filter "label=project=$(PROJECT_NAME)"

.PHONY: docker-shell
docker-shell: ## Open shell in API container
	$(Q)$(DOCKER_COMPOSE) exec api /bin/sh
```

### mk/build.mk - Build Targets

```makefile
# =============================================================================
# mk/build.mk - Build targets
# =============================================================================

.PHONY: build
build: build-api build-web ## Build all services

.PHONY: build-api
build-api: $(BUILD_DIR)/api ## Build API service

$(BUILD_DIR)/api: $(shell find api -name '*.go' 2>/dev/null)
	$(Q)echo "Building API..."
	$(Q)mkdir -p $(BUILD_DIR)
	$(Q)cd api && go build -ldflags "-X main.Version=$(VERSION)" -o ../$(BUILD_DIR)/api ./cmd/server
	@echo "✓ API built: $(BUILD_DIR)/api"

.PHONY: build-web
build-web: $(DIST_DIR)/web ## Build web frontend

$(DIST_DIR)/web: $(shell find web/src -name '*.ts' -o -name '*.tsx' 2>/dev/null)
	$(Q)echo "Building web..."
	$(Q)mkdir -p $(DIST_DIR)
	$(Q)cd web && npm run build
	$(Q)cp -r web/dist $(DIST_DIR)/web
	@echo "✓ Web built: $(DIST_DIR)/web"

.PHONY: build-clean
build-clean: ## Clean build artifacts
	$(Q)rm -rf $(BUILD_DIR) $(DIST_DIR)
	@echo "✓ Build artifacts cleaned"
```

### mk/test.mk - Testing

```makefile
# =============================================================================
# mk/test.mk - Test targets
# =============================================================================

.PHONY: test
test: test-unit test-integration ## Run all tests

.PHONY: test-unit
test-unit: ## Run unit tests
	$(Q)echo "Running unit tests..."
	$(Q)cd api && go test -v -short ./...
	$(Q)cd web && npm test

.PHONY: test-integration
test-integration: ## Run integration tests
	$(Q)echo "Running integration tests..."
	$(Q)cd api && go test -v -run Integration ./...

.PHONY: test-coverage
test-coverage: ## Run tests with coverage report
	$(Q)mkdir -p $(BUILD_DIR)/coverage
	$(Q)cd api && go test -coverprofile=$(BUILD_DIR)/coverage/api.out ./...
	$(Q)go tool cover -html=$(BUILD_DIR)/coverage/api.out -o $(BUILD_DIR)/coverage/api.html
	@echo "Coverage report: $(BUILD_DIR)/coverage/api.html"

.PHONY: lint
lint: ## Run linters
	$(Q)echo "Linting..."
	$(Q)cd api && golangci-lint run
	$(Q)cd web && npm run lint
```

### mk/deploy.mk - Deployment

```makefile
# =============================================================================
# mk/deploy.mk - Deployment targets
# =============================================================================

# Deployment requires tests to pass
deploy: test ## Deploy to target environment
	$(Q)echo "Deploying to $(ENV)..."
ifeq ($(ENV),prod)
	@echo "$(YELLOW)WARNING: Deploying to PRODUCTION$(RESET)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
endif
	$(Q)./scripts/deploy.sh $(ENV)
	@echo "$(GREEN)✓ Deployed to $(ENV)$(RESET)"

.PHONY: deploy-dry-run
deploy-dry-run: ## Show what deploy would do
	$(Q)echo "Dry run for $(ENV):"
	$(Q)./scripts/deploy.sh $(ENV) --dry-run

.PHONY: rollback
rollback: ## Rollback to previous deployment
	$(Q)echo "Rolling back $(ENV)..."
	$(Q)./scripts/rollback.sh $(ENV)
```

### mk/dev.mk - Development Environment

```makefile
# =============================================================================
# mk/dev.mk - Development environment
# =============================================================================

.PHONY: dev
dev: ## Start development environment
	$(Q)$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Development environment running$(RESET)"
	@echo "  API: http://localhost:8080"
	@echo "  Web: http://localhost:3000"

.PHONY: dev-down
dev-down: ## Stop development environment
	$(Q)$(DOCKER_COMPOSE) down
	@echo "✓ Development environment stopped"

.PHONY: dev-logs
dev-logs: ## Tail development logs
	$(Q)$(DOCKER_COMPOSE) logs -f

.PHONY: dev-reset
dev-reset: dev-down docker-clean dev ## Reset development environment

.PHONY: dev-db-reset
dev-db-reset: ## Reset development database
	$(Q)$(DOCKER_COMPOSE) exec db psql -U postgres -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	$(Q)$(DOCKER_COMPOSE) exec api ./migrate up
	@echo "✓ Database reset"
```

### mk/utils.mk - Shared Utilities

```makefile
# =============================================================================
# mk/utils.mk - Shared functions and macros
# =============================================================================

# Print a section header
define print_header
	@echo ""
	@echo "$(BOLD)━━━ $(1) ━━━$(RESET)"
	@echo ""
endef

# Check if a command exists
define require_command
	@command -v $(1) >/dev/null 2>&1 || { echo "$(RED)Error: $(1) is required but not installed$(RESET)"; exit 1; }
endef

# Check required tools
.PHONY: check-deps
check-deps: ## Verify required tools are installed
	$(call require_command,docker)
	$(call require_command,docker-compose)
	$(call require_command,go)
	$(call require_command,node)
	@echo "$(GREEN)✓ All dependencies available$(RESET)"

# Print current configuration
.PHONY: show-config
show-config: ## Show current configuration
	$(call print_header,Configuration)
	@echo "PROJECT_NAME: $(PROJECT_NAME)"
	@echo "VERSION:      $(VERSION)"
	@echo "ENV:          $(ENV)"
	@echo "OS:           $(OS)"
	@echo "DOCKER_TAG:   $(DOCKER_TAG)"
```

### Benefits of the mk/ Pattern

| Benefit | Explanation |
|---------|-------------|
| **Separation of concerns** | Each file has one responsibility |
| **Easier navigation** | Docker targets reside in `mk/docker.mk`, not line 847 |
| **Team scaling** | Different people own different modules |
| **Conditional loading** | `include mk/optional.mk` with `-include` |
| **Testing** | Test modules in isolation |
| **Reusability** | Copy `mk/docker.mk` to other projects |

### Pattern Variations

**Conditional includes** for optional features:

```makefile
# Include Kubernetes targets only if kubectl exists
ifneq ($(shell command -v kubectl 2>/dev/null),)
    include mk/kubernetes.mk
endif
```

**Environment-specific overrides**:

```makefile
# Include environment-specific config
-include mk/config.$(ENV).mk
```

**Plugin architecture**:

```makefile
# Include all mk files automatically
include $(wildcard mk/*.mk)
```

## Complete Example

### Project Structure

```text
project/
├── Makefile
├── manage.sh
├── manage.py
├── mk/
│   ├── config.mk
│   ├── help.mk
│   ├── docker.mk
│   ├── build.mk
│   ├── test.mk
│   ├── deploy.mk
│   ├── dev.mk
│   └── utils.mk
├── scripts/
│   ├── build.sh
│   ├── deploy.sh
│   └── test.sh
└── docker-compose.yml
```

### The Makefile

```makefile
# Project configuration
PROJECT := myapp
ENV ?= dev
VERBOSE ?= 0

# Conditional verbosity
ifeq ($(VERBOSE),1)
    Q :=
else
    Q := @
endif

# ============================================================================
# Main targets
# ============================================================================

.PHONY: all
all: build test ## Build and test everything

.PHONY: build
build: build-api build-web ## Build all services

.PHONY: build-api
build-api: ## Build API service
	$(Q)echo "Building API..."
	$(Q)docker build -t $(PROJECT)-api:$(ENV) ./api

.PHONY: build-web
build-web: ## Build web frontend
	$(Q)echo "Building web..."
	$(Q)docker build -t $(PROJECT)-web:$(ENV) ./web

.PHONY: test
test: build ## Run all tests
	$(Q)echo "Running tests..."
	$(Q)./scripts/test.sh

.PHONY: deploy
deploy: build test ## Deploy to target environment
	$(Q)echo "Deploying to $(ENV)..."
	$(Q)ENV=$(ENV) ./scripts/deploy.sh

.PHONY: clean
clean: ## Remove build artifacts
	$(Q)echo "Cleaning..."
	$(Q)docker image prune -f
	$(Q)rm -rf ./build ./dist

.PHONY: logs
logs: ## Tail service logs
	$(Q)docker-compose logs -f

.PHONY: shell
shell: ## Open shell in API container
	$(Q)docker-compose exec api /bin/sh

# ============================================================================
# Development targets
# ============================================================================

.PHONY: dev
dev: ## Start development environment
	$(Q)docker-compose up -d
	$(Q)echo "Development environment running"

.PHONY: dev-down
dev-down: ## Stop development environment
	$(Q)docker-compose down

.PHONY: dev-reset
dev-reset: dev-down clean dev ## Reset development environment

# ============================================================================
# Help
# ============================================================================

.PHONY: help
help: ## Show this help
	@echo "Usage: make <target> [ENV=dev|staging|prod] [VERBOSE=1]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
```

### Usage Patterns

**Power users** invoke Make directly:
```bash
make deploy ENV=staging VERBOSE=1
make build -j4
make -n deploy  # dry run
```

**Regular users** use the bash wrapper:
```bash
./manage.sh deploy --env staging --verbose
./manage.sh build
./manage.sh --help
```

**Interactive sessions** use the TUI:
```bash
./manage.py
# Arrow keys to select, Enter to confirm
# Prompted for options
```

All three invoke the same underlying Makefile targets.

## Layer Selection Guidelines

### Use Make Directly When:
- Running in CI/CD (scripts, not humans)
- Parallel builds are needed (`-j`)
- Dry runs are needed (`-n`)
- The user is a Make power user

### Use Bash Wrapper When:
- Familiar `--flag` syntax is desired
- Basic argument validation is needed
- Colored output is desired
- Scripting but readability matters

### Use Python TUI When:
- Users are not comfortable with CLI
- Tasks have many options to configure
- Guided workflows are desired
- Interactive confirmation matters (destructive operations)

## Trade-offs

| Approach | Pros | Cons |
|----------|------|------|
| **Raw Make** | No dependencies, universal, powerful | Cryptic UX, no help, verbose |
| **Bash wrapper** | Portable, familiar flags, simple | Another file to maintain |
| **Python TUI** | Polished UX, validation, guidance | Requires Python + libraries |
| **All three** | Best of all worlds | More complexity |

For solo projects, raw Make is adequate. For teams with mixed experience levels, the layered approach pays dividends in reduced friction and fewer mistakes.

## Summary

Make's dependency graph is genuinely valuable—it is why the tool persists after nearly five decades. However, Make's UX reflects its age. Rather than abandoning Make for trendier alternatives (Task, Just, Mage), consider wrapping it.

The wrapper handles human interaction. Make handles orchestration. Scripts handle implementation. Each layer does one thing well.

Key points:
- **Make's dependency resolution is difficult to replace**—do not discard it
- **Wrappers are inexpensive**—a 50-line bash script transforms UX
- **Python TUIs are polished**—textual, rich, and questionary make it straightforward
- **Layers separate concerns**—UX, orchestration, and implementation evolve independently
- **Power users bypass wrappers**—`make deploy` always works

The best automation is invisible. Users should not need to understand Make's syntax to deploy safely. They should type `./manage.sh deploy --env staging`, see a confirmation prompt, and trust the system to do the right thing.

---

*Related: [Docker Compose Management with Modular Makefiles](/posts/docker-compose-makefile-management/)*
