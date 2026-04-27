#!/bin/bash
#
# Deploy dev branch to main as a single squashed commit
#
# This script:
# 1. Verifies you're on the dev branch with no uncommitted changes
# 2. Backs up main to main-backup-<timestamp>
# 3. Resets main to a single squashed commit of dev
# 4. Pushes main to origin
#
# Usage: ./tools/deploy.sh [--dry-run] [--no-push]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DRY_RUN=false
NO_PUSH=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --no-push)
            NO_PUSH=true
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--no-push]"
            echo ""
            echo "Options:"
            echo "  --dry-run   Show what would be done without making changes"
            echo "  --no-push   Do everything except push to origin"
            exit 0
            ;;
    esac
done

log() {
    echo -e "${GREEN}[deploy]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[deploy]${NC} $1"
}

error() {
    echo -e "${RED}[deploy]${NC} $1" >&2
    exit 1
}

# Get repo root
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Check we're on dev
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "dev" ]]; then
    error "Must be on dev branch (currently on: $CURRENT_BRANCH)"
fi

# Check for uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    error "Uncommitted changes detected. Commit or stash them first."
fi

# Check for untracked files in _posts (common oversight)
UNTRACKED_POSTS=$(git ls-files --others --exclude-standard _posts/)
if [[ -n "$UNTRACKED_POSTS" ]]; then
    warn "Untracked files in _posts/:"
    echo "$UNTRACKED_POSTS"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get commit info
DEV_SHA=$(git rev-parse dev)
DEV_SHORT=$(git rev-parse --short dev)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
COMMIT_COUNT=$(git rev-list --count dev)

log "Preparing to deploy dev ($DEV_SHORT) to main"
log "  Commits on dev: $COMMIT_COUNT"

if $DRY_RUN; then
    warn "DRY RUN - no changes will be made"
    echo ""
    echo "Would execute:"
    echo "  1. git branch main-backup-$TIMESTAMP main"
    echo "  2. git checkout --orphan main-deploy"
    echo "  3. git commit -m '<squashed commit message>'"
    echo "  4. git branch -M main-deploy main"
    echo "  5. git checkout dev"
    echo "  6. git push origin main --force-with-lease"
    exit 0
fi

# Backup main
log "Backing up main to main-backup-$TIMESTAMP"
git branch "main-backup-$TIMESTAMP" main 2>/dev/null || true

# Create orphan branch with all dev content
log "Creating squashed commit..."
git checkout --orphan main-deploy

# Generate commit message from dev log
COMMIT_MSG=$(cat <<EOF
Deploy from dev ($DEV_SHORT)

Squashed $COMMIT_COUNT commits from dev branch.

Recent changes:
$(git log main-backup-$TIMESTAMP..dev --oneline 2>/dev/null | head -20 || git log dev --oneline | head -20)
EOF
)

git commit -m "$COMMIT_MSG"

# Replace main with our new branch
log "Replacing main branch..."
git branch -M main-deploy main

# Return to dev
git checkout dev

log "Local main updated successfully"

# Push
if $NO_PUSH; then
    warn "Skipping push (--no-push specified)"
    echo ""
    echo "To push manually:"
    echo "  git push origin main --force-with-lease"
else
    log "Pushing to origin..."
    git push origin main --force-with-lease
    log "Deployed successfully!"
fi

# Cleanup old backups (keep last 5)
BACKUP_COUNT=$(git branch --list 'main-backup-*' | wc -l)
if [[ $BACKUP_COUNT -gt 5 ]]; then
    log "Cleaning up old backups (keeping last 5)..."
    git branch --list 'main-backup-*' | sort | head -n -5 | xargs -r git branch -D
fi

echo ""
log "Done! main is now a single commit with all dev content."
