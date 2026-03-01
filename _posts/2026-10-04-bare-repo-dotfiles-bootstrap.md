---
title: "Dotfiles Management with Bare Git Repository Bootstrap"
date: 2026-10-04 10:00:00 -0700
categories: [Linux, Configuration Management]
tags: [dotfiles, git, bootstrap, fish-shell, neovim, automation]
---

Configuration files scattered across a home directory present a significant challenge for system administrators and developers. Tracking changes to shell configurations, editor settings, and application preferences requires a systematic approach. This post presents a bootstrap script that establishes a bare git repository workflow for managing dotfiles, including integration with Fish shell and Neovim.

## Problem Statement

### The Dotfiles Challenge

Unix-like systems store user configuration in hidden files (dotfiles) throughout the home directory. These files accumulate over years of customization:

- Shell configurations (`.bashrc`, `.zshrc`, `.config/fish/`)
- Editor settings (`.vimrc`, `.config/nvim/`)
- Tool configurations (`.gitconfig`, `.tmux.conf`)
- Application preferences (`.config/` subdirectories)

Manual backup of these files leads to several problems:

1. **Version History Loss**: Manual copying provides no change history
2. **Synchronization Difficulty**: Keeping multiple machines consistent requires manual effort
3. **Restoration Complexity**: Setting up a new system involves remembering which files to copy
4. **Conflict Resolution**: Changes made on different machines may conflict without visibility

### The Git Problem

Standard git repositories store their `.git` directory alongside tracked files. For dotfiles, this creates a conflict: the home directory cannot become a standard git repository without interfering with other projects and cluttering git status output.

## Technical Background

### Bare Repository Architecture

A bare git repository contains only the git database (`objects/`, `refs/`, `HEAD`, etc.) without a working tree. This architecture enables separation of the repository location from the working directory.

Standard repository structure:
```text
~/project/
├── .git/           # Repository data
├── src/            # Working tree
└── README.md       # Working tree
```

Bare repository structure for dotfiles:
```text
~/.dotfiles/        # Repository data (bare)
~/                  # Working tree (separate)
├── .bashrc
├── .config/
└── .gitconfig
```

### Advantages of Bare Repository Approach

1. **No Repository Conflicts**: The `.git` directory does not exist in `$HOME`
2. **Native Git Operations**: Standard git commands work with a wrapper alias
3. **Selective Tracking**: Only explicitly added files are tracked
4. **Clean Status Output**: Untracked files can be hidden from status

## Bootstrap Implementation

### Script Architecture

The bootstrap script follows a modular design with separate functions for each operation:

```sh
#!/bin/sh

REPO_URL="git@github.com:username/dotfiles.git"
GIT_DIR="$HOME/.dotfiles"
WORK_TREE="$HOME"
BACKUP_DIR="$HOME/.dotfiles-backup"

dotfiles() {
  git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" "$@"
}
```

The `dotfiles` function wraps git commands, specifying:
- `--git-dir`: Location of the bare repository
- `--work-tree`: Location of the working tree (home directory)

### Clone Operation

```sh
clone_repo() {
  echo ">> Cloning bare repo into $GIT_DIR"
  git clone --bare "$REPO_URL" "$GIT_DIR"
}
```

The `--bare` flag instructs git to clone only the repository data, without checking out a working tree. The repository resides entirely within `~/.dotfiles/`.

### Checkout with Conflict Resolution

Checkout attempts may fail when existing files conflict with repository contents. The script handles this automatically:

```sh
checkout_dotfiles() {
  echo ">> Checking out dotfiles into $WORK_TREE"
  if ! dotfiles checkout; then
    echo "!! Conflicts found. Moving existing files to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    dotfiles checkout 2>&1 | grep -E "^\s+\." | awk '{print $1}' | while read -r file; do
      mkdir -p "$(dirname "$BACKUP_DIR/$file")"
      mv "$WORK_TREE/$file" "$BACKUP_DIR/$file"
    done
    echo ">> Retrying checkout"
    dotfiles checkout
  fi
  echo ">> Dotfiles successfully checked out."
}
```

The conflict resolution process:

1. **Initial Checkout Attempt**: Try checking out repository contents
2. **Conflict Detection**: Parse error output for conflicting file paths
3. **Backup Creation**: Move conflicting files to `~/.dotfiles-backup/` preserving directory structure
4. **Retry Checkout**: Second checkout succeeds with conflicts removed

This approach preserves existing configurations rather than overwriting them, enabling manual review and selective restoration.

### Untracked File Configuration

After initial setup, the bare repository configuration should hide untracked files:

```sh
dotfiles config --local status.showUntrackedFiles no
```

This setting prevents `dotfiles status` from listing every file in the home directory. Only tracked files and their modifications appear in status output.

## Fish Shell Integration

### The Alias Function Pattern

Fish shell uses functions rather than aliases. The dotfiles command requires a Fish function:

```fish
function dotfiles
    /usr/bin/git --git-dir=$HOME/.dotfiles --work-tree=$HOME $argv
end
```

Key implementation details:

- **Absolute Path**: `/usr/bin/git` ensures the system git binary is used, avoiding conflicts with git wrapper scripts
- **Variable Expansion**: `$HOME` resolves to the user's home directory
- **Argument Passing**: `$argv` passes all function arguments to git

This function should reside in `~/.config/fish/config.fish` or as a separate file in `~/.config/fish/functions/dotfiles.fish`.

### Fish Bootstrap Integration

The bootstrap script includes Fish plugin and completion setup:

```sh
run_fish_bootstrap() {
  if command -v fish >/dev/null 2>&1; then
    if [ -f "$FISH_BOOTSTRAP" ]; then
      echo ">> Running Fish bootstrap: $FISH_BOOTSTRAP"
      fish "$FISH_BOOTSTRAP"
      fish_update_completions
    else
      echo "!! Fish bootstrap file not found: $FISH_BOOTSTRAP"
    fi
  else
    echo "!! Fish is not installed. Skipping Fish bootstrap."
  fi
}
```

The Fish bootstrap file (`~/.config/fish/bootstrap.fish`) typically:
- Installs plugin managers (Fisher, Oh My Fish)
- Installs plugins for enhanced functionality
- Configures shell completions

## Neovim Bootstrap Integration

### Headless Plugin Installation

Neovim requires plugin installation after configuration files are in place. The bootstrap script runs Neovim in headless mode:

```sh
run_nvim_setup() {
  if command -v nvim >/dev/null 2>&1; then
    echo ">> Running Neovim Mason, Treesitter, and Lazy setup..."
    nvim --headless "+MasonInstallAll" +qall 2>/dev/null
    nvim --headless "+TSUpdate" +qall 2>/dev/null
    nvim --headless "+Lazy! sync" +qall 2>/dev/null
    echo ">> Neovim bootstrapping complete."
  else
    echo "!! Neovim is not installed. Skipping Neovim setup."
  fi
}
```

The sequence installs:
1. **Mason**: LSP servers, linters, and formatters
2. **Treesitter**: Language parsers for syntax highlighting
3. **Lazy.nvim**: Plugin manager synchronization

Headless mode (`--headless`) enables automated execution without a terminal interface.

## Per-Machine Branching Strategy

### Branch-Per-Machine Architecture

Different machines require different configurations. A branching strategy addresses this:

```text
main (or common)
├── machine-a
├── machine-b
├── machine-c
└── machine-d
```

Each branch contains machine-specific configurations:
- Different shell aliases for different roles
- Machine-specific paths and environment variables
- Hardware-specific settings (display scaling, power management)
- Tool availability differences (work vs. personal machines)

### Branch Management

On initial setup, checkout the appropriate branch:

```sh
dotfiles checkout machine-name
```

For new machines, create a branch from an existing configuration:

```sh
dotfiles checkout -b new-machine
dotfiles push -u origin new-machine
```

### Sharing Common Configuration

Common configurations can be maintained in a shared branch and merged into machine branches:

```sh
dotfiles checkout machine-a
dotfiles merge common
dotfiles push
```

This approach enables both shared defaults and machine-specific customization.

## Complete Bootstrap Sequence

### Full Installation Process

The script supports a full installation mode:

```sh
run_full_install() {
  clone_repo
  checkout_dotfiles
  run_fish_bootstrap
  run_nvim_setup
}
```

Execution:

```sh
./bootstrap.sh install
```

### Modular Operations

Individual components can be executed separately for partial setup or reinstallation:

```sh
./bootstrap.sh --run-fish-bootstrap   # Fish plugins only
./bootstrap.sh --run-nvim-setup       # Neovim plugins only
```

This modularity supports scenarios where only specific components require re-initialization.

## Usage After Bootstrap

### Daily Operations

Common dotfiles operations after initial setup:

```sh
# Check status
dotfiles status

# View changes
dotfiles diff

# Stage and commit
dotfiles add .config/fish/config.fish
dotfiles commit -m "add fish configuration"

# Push to remote
dotfiles push

# Pull changes from another machine
dotfiles pull
```

### Adding New Files

To track a new configuration file:

```sh
dotfiles add ~/.config/newapp/config.yaml
dotfiles commit -m "track newapp configuration"
dotfiles push
```

### Restoration on New System

On a fresh system installation:

1. Install git
2. Run the bootstrap script
3. Install Fish shell and Neovim (if not present)
4. Re-run component bootstraps if needed

## Summary

The bare git repository approach provides a robust solution for dotfiles management:

- **Clean Separation**: Repository data stored separately from working files
- **Standard Git Workflow**: Familiar commands with a simple wrapper
- **Conflict Handling**: Automatic backup of existing files during initial setup
- **Multi-Machine Support**: Branch-per-machine strategy enables customization
- **Integrated Tooling**: Fish shell and Neovim bootstrap in a single script

The bootstrap script transforms system configuration from manual file copying to a reproducible, version-controlled workflow. New machine setup reduces from hours of manual configuration to a single script execution.
