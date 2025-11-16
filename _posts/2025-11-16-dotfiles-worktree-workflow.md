---
title: Multi-Machine Dotfiles Management with Git Worktrees
date: 2025-11-16 10:00:00 -0700
categories: [Linux, Configuration Management]
tags: [dotfiles, git, worktrees, automation, linux]
---

A comprehensive guide to managing dotfiles across multiple machines using git worktrees and automatic deployment hooks.

## Overview

This workflow allows you to:
- Maintain separate configurations for different machines (darknova, darkstar, darkspacer, etc.)
- Work directly on your system in `$HOME` and commit changes
- Automatically deploy changes when committing from worktrees
- Keep everything synced via git
- Have a clean worktree copy for each machine

## Architecture

### Components

1. **Bare Repository**: `~/.dotfiles` (the central git repository)
2. **Worktrees**: `~/dotfiles-{hostname}` (one per machine)
3. **Working Directory**: `$HOME` (where you actually use your dotfiles)
4. **Deploy Script**: `.deploy.sh` (syncs worktree → $HOME)
5. **Git Hooks**: `.githooks/` (triggers deployment automatically)

### Directory Structure

```
~/.dotfiles/              # Bare repository
~/dotfiles-darknova/      # Worktree for darknova machine
~/dotfiles-darkstar/      # Worktree for darkstar machine
~/dotfiles-darkspacer/    # Worktree for darkspacer machine
~/dotfiles-darkspacer2/   # Worktree for darkspacer2 machine
~/                        # Your actual working files
```

## Initial Setup

### On a New Machine

1. **Clone the bare repository**:
   ```bash
   git clone --bare git@github.com:YOUR-USERNAME/dotfiles.git ~/.dotfiles
   ```

2. **Configure fetch to get all branches**:
   ```bash
   cd ~/.dotfiles
   git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
   git fetch origin
   ```

3. **Set up git hooks path**:
   ```bash
   git config core.hooksPath .githooks
   ```

4. **Create worktree for your machine** (example for darknova):
   ```bash
   git worktree add ~/dotfiles-darknova darknova
   ```

5. **Set branch to track remote**:
   ```bash
   git branch --set-upstream-to=origin/darknova darknova
   ```

6. **Pull to trigger initial deployment**:
   ```bash
   cd ~/dotfiles-darknova
   git pull
   ```

   This will deploy all your dotfiles to `$HOME`, including the deploy script and hooks.

7. **Set up the dotfiles command** (add to `~/.config/fish/config.fish` or `~/.bashrc`):
   ```fish
   # Fish shell
   function dotfiles
       /usr/bin/git --git-dir=$HOME/.dotfiles --work-tree=$HOME $argv
   end
   ```

   ```bash
   # Bash
   alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
   ```

## How It Works

### The Deploy Script

Each branch has a `.deploy.sh` script that:
- Checks if the current hostname matches the branch name
- If match: uses `rsync` to copy files from worktree to `$HOME`
- Excludes `.git/` and the worktree directory itself
- Includes `.deploy.sh` and `.githooks/` (so they're also in `$HOME`)

Example for darknova:
```bash
#!/bin/bash
INTENDED_HOSTNAME="darknova"
CURRENT_HOSTNAME=$(hostname)
WORKTREE_DIR="$HOME/dotfiles-darknova"
TARGET_DIR="$HOME"

# Only deploy if we're on the correct machine
if [[ "$CURRENT_HOSTNAME" != "$INTENDED_HOSTNAME" ]]; then
  echo "Skipping deployment: This is $CURRENT_HOSTNAME, not $INTENDED_HOSTNAME"
  exit 0
fi

rsync -av \
  --exclude='.git' \
  --exclude='dotfiles-darknova' \
  "$WORKTREE_DIR/" \
  "$TARGET_DIR/"
```

### The Git Hooks

Three hooks automatically trigger the deploy script:
- **post-commit**: After every commit in the worktree
- **post-checkout**: When switching branches in the worktree
- **post-merge**: After pulling/merging in the worktree

Example `post-commit`:
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/.deploy.sh" ]; then
    echo "Deploying dotfiles..."
    "$SCRIPT_DIR/.deploy.sh"
fi
```

## Daily Workflow

### Making Changes on Your Machine

You have two equivalent workflows:

#### Workflow A: Work in $HOME (Recommended)

1. **Edit files directly in $HOME**:
   ```bash
   nvim ~/.config/nvim/init.lua
   nvim ~/.bashrc
   ```

2. **Check what changed**:
   ```bash
   dotfiles status
   ```

3. **Commit changes**:
   ```bash
   dotfiles add .config/nvim/init.lua
   dotfiles commit -m "update nvim config"
   ```

4. **Push to origin**:
   ```bash
   dotfiles push
   ```

5. **Sync the worktree** (optional, for clean copy):
   ```bash
   cd ~/dotfiles-darknova
   git pull
   ```

#### Workflow B: Work in Worktree

1. **Edit files in the worktree**:
   ```bash
   cd ~/dotfiles-darknova
   nvim .config/nvim/init.lua
   ```

2. **Commit changes**:
   ```bash
   git add .config/nvim/init.lua
   git commit -m "update nvim config"
   ```

   The `post-commit` hook automatically deploys to `$HOME`!

3. **Push to origin**:
   ```bash
   git push
   ```

### Syncing Changes from Other Machines

When you push changes from another machine:

1. **Pull in the worktree**:
   ```bash
   cd ~/dotfiles-darknova
   git pull
   ```

   The `post-merge` hook automatically deploys to `$HOME`!

2. **Verify with dotfiles command**:
   ```bash
   dotfiles status
   ```

   Should show: "nothing to commit"

## Common Operations

### Check Status

```bash
# Check what's different in $HOME
dotfiles status

# Check worktree status
cd ~/dotfiles-darknova
git status
```

### View Changes

```bash
# See what changed in $HOME
dotfiles diff

# See changes in worktree
cd ~/dotfiles-darknova
git diff
```

### List Worktrees

```bash
cd ~/.dotfiles
git worktree list
```

Output:
```
/home/user/.dotfiles           (bare)
/home/user/dotfiles-darknova   abc1234 [darknova]
/home/user/dotfiles-darkstar   def5678 [darkstar]
```

### Create a New Machine Branch

On your main machine:

1. **Create new branch from existing**:
   ```bash
   cd ~/dotfiles-darknova
   git checkout -b newmachine
   ```

2. **Customize for the new machine**:
   ```bash
   # Update hostname in .deploy.sh
   sed -i 's/INTENDED_HOSTNAME="darknova"/INTENDED_HOSTNAME="newmachine"/' .deploy.sh
   sed -i 's/dotfiles-darknova/dotfiles-newmachine/' .deploy.sh

   git add .deploy.sh
   git commit -m "configure deploy for newmachine"
   ```

3. **Push the new branch**:
   ```bash
   git push -u origin newmachine
   ```

4. **On the new machine**: Follow the "Initial Setup" steps using the new branch name.

### Manually Deploy

If you need to manually trigger deployment:

```bash
cd ~/dotfiles-darknova
./.deploy.sh
```

### Remove a Worktree

```bash
git worktree remove dotfiles-oldmachine
git branch -d oldmachine  # Delete local branch
git push origin --delete oldmachine  # Delete remote branch
```

## Troubleshooting

### Hooks Not Triggering

Check if hooks path is configured:
```bash
cd ~/.dotfiles
git config --get core.hooksPath
```

Should output: `.githooks`

If not set:
```bash
git config core.hooksPath .githooks
```

### Deployment Skipped (Wrong Hostname)

The deploy script checks `hostname` vs `INTENDED_HOSTNAME`. Verify:
```bash
hostname
# Should match your branch name (e.g., "darknova")
```

If hostname doesn't match, either:
- Change your system hostname
- Update `INTENDED_HOSTNAME` in `.deploy.sh`

### dotfiles status Shows Deletions

This happens if files exist in the branch but not in `$HOME`. Usually means deployment didn't run. Fix:
```bash
cd ~/dotfiles-darknova
./.deploy.sh  # Manually deploy
dotfiles status  # Should be clean now
```

### Merge Conflicts Between Machines

If you edit the same file on two machines:

1. **Pull changes in worktree**:
   ```bash
   cd ~/dotfiles-darknova
   git pull
   ```

2. **If conflicts occur**, resolve them:
   ```bash
   # Edit conflicted files
   nvim .config/nvim/init.lua

   # Mark as resolved
   git add .config/nvim/init.lua
   git commit
   ```

3. **Deploy the resolved version**:
   ```bash
   ./.deploy.sh
   ```

## Advanced Tips

### Ignore Machine-Specific Files

Add to `.gitignore` in each branch:
```
.venv/
.cache/
*.local
```

### Backup Before Deployment

Modify `.deploy.sh` to create backups:
```bash
# Add before rsync
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r "$TARGET_DIR/.config" "$BACKUP_DIR/" 2>/dev/null || true
```

### Dry-Run Deployment

Test what would be deployed:
```bash
rsync -avn \
  --exclude='.git' \
  --exclude='dotfiles-darknova' \
  ~/dotfiles-darknova/ \
  ~/
```

### Share Common Config Between Machines

Create a "common" branch with shared configs, then merge it into machine branches:
```bash
cd ~/dotfiles-darknova
git merge common
git push
```

## Summary

This workflow gives you:
- **Per-machine customization**: Each machine has its own branch
- **Automatic deployment**: Hooks deploy changes automatically
- **Flexible editing**: Work in `$HOME` or worktrees
- **Version control**: Full git history for all configs
- **Sync across machines**: Push/pull to share changes

The key insight: The worktree holds the "source of truth" for each machine, and the deploy script keeps `$HOME` in sync. The `dotfiles` command lets you work directly in `$HOME` for convenience.
