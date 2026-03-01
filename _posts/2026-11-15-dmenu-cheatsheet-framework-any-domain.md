---
title: "A dmenu Cheatsheet Framework for Arbitrary Domain Knowledge"
date: 2026-11-15 10:00:00 -0700
categories: [Linux, Workflow]
tags: [dmenu, bash, yocto, bitbake, embedded-linux, productivity, shell-scripting]
---

The heredoc-based dmenu cheatsheet pattern introduced for keybinding references extends naturally to any domain requiring categorized quick-reference access. This post generalizes the framework and demonstrates its application to Yocto/BitBake embedded Linux development.

## Prior Work

A [previous post on dmenu keybinding cheatsheets](/linux/workflow/2026/11/01/dmenu-searchable-keybinding-cheatsheets.html) established the core architecture: heredoc-embedded data, category extraction via grep/sed, and two-level dmenu navigation. That implementation focused exclusively on keyboard shortcuts for tools like Neovim, tmux, and i3.

However, the underlying pattern contains no keybinding-specific assumptions. The same architecture supports any domain knowledge expressible as categorized key-value pairs.

## Problem Statement

### Domain Knowledge Sprawl

Technical practitioners accumulate reference material across diverse domains:

- **Build System Commands**: Yocto/BitBake, CMake, Bazel, Gradle task invocations
- **CLI Tool Syntax**: ffmpeg encoding options, ImageMagick transformations, git porcelain commands
- **Configuration Formats**: systemd unit files, Nginx directives, Docker Compose schemas
- **API References**: REST endpoints, GraphQL queries, SDK method signatures
- **Protocol Specifications**: HTTP headers, MQTT topics, CAN bus message formats

This knowledge exhibits a consistent pattern: categorized entries where each entry maps a **key** (command, directive, endpoint) to a **value** (description, syntax, behavior).

### Reference Friction

Existing documentation access patterns introduce friction:

**Man pages** provide comprehensive coverage but require context switches and navigation through verbose prose. Finding a specific bitbake task option requires scanning thousands of lines.

**Browser-based wikis** break keyboard-centric workflows. Yocto Project documentation spans multiple subsites with inconsistent search behavior.

**Personal notes** accumulate in scattered files without standardized access patterns. Markdown cheatsheets require opening editors and manual searching.

**IDE integrations** bind documentation to specific environments. Knowledge remains inaccessible from terminal sessions, window manager contexts, or other tools.

The dmenu cheatsheet framework provides instant, searchable access from any context while maintaining a single-file, version-controllable knowledge base.

## Framework Generalization

### Core Pattern

The heredoc-based cheatsheet architecture reduces to three components:

```text
┌─────────────────────────────────────────────────────────────────┐
│  1. HEREDOC DATABASE                                            │
│     # Category Name                                             │
│     key/command/item     → description/syntax/behavior          │
│     ...                                                         │
│                                                                 │
│  2. CATEGORY EXTRACTION                                         │
│     grep '^# ' | sed 's/# //'                                   │
│                                                                 │
│  3. TWO-LEVEL NAVIGATION                                        │
│     Category selection → Entry display within category          │
└─────────────────────────────────────────────────────────────────┘
```

The pattern imposes minimal constraints on content:

- Categories begin with `# ` followed by a category name
- Entries use a consistent separator (typically `→`) between key and value
- Whitespace alignment improves visual scanning but is not required

### Applicable Domains

Any knowledge domain fitting the categorized key-value model benefits from this framework:

| Domain | Key | Value | Example Categories |
|--------|-----|-------|-------------------|
| Build systems | Command/variable | Behavior/syntax | Setup, Tasks, Debugging |
| CLI tools | Flag/subcommand | Effect/usage | Input, Output, Filters |
| Configuration | Directive/option | Meaning/default | Server, Security, Logging |
| APIs | Endpoint/method | Parameters/response | Auth, CRUD, Webhooks |
| Protocols | Message/field | Format/constraints | Handshake, Data, Control |

The framework excels for reference material that is:
- Accessed frequently during active work
- Organized into logical categories
- Composed of discrete, self-contained entries
- Stable enough to warrant maintenance overhead

## Case Study: Yocto/BitBake Cheatsheet

### Embedded Linux Complexity

The Yocto Project presents a particularly compelling use case. Yocto provides a build system and toolchain for creating custom Linux distributions targeting embedded hardware. Its complexity stems from several factors:

**Layered Architecture**: Build configurations span multiple layers (meta-poky, meta-openembedded, BSP layers, custom layers), each contributing recipes, classes, and configuration fragments.

**Task System**: BitBake executes recipes through a task graph (do_fetch, do_unpack, do_patch, do_configure, do_compile, do_install, do_package). Understanding task dependencies requires mental model maintenance.

**Variable System**: Hundreds of variables control build behavior (SRC_URI, DEPENDS, RDEPENDS, IMAGE_INSTALL, MACHINE, DISTRO). Variable override syntax adds conditional complexity.

**Devtool Workflow**: The devtool utility provides source modification workflows separate from direct recipe editing, introducing additional command sets.

Documentation exists across the Yocto Project Manual, BitBake User Manual, BSP guides, and layer-specific READMEs. A consolidated quick-reference accelerates development cycles.

### Cheatsheet Structure

The Yocto cheatsheet organizes knowledge into eleven categories:

```bash
choices=$(cat <<'EOF'
# Yocto Setup
source oe-init-build-env     → Set up build environment
MACHINE=<name>               → Target machine override
DISTRO=<name>                → Set distro (e.g. poky)
bitbake <recipe>             → Build specified recipe
bitbake -c <task> <recipe>   → Run specific task for recipe
bitbake-layers show-layers   → Show active layers
bitbake-layers show-recipes  → List available recipes
bitbake-layers add-layer ... → Add new layer to conf/bblayers.conf

# Configuration Files
conf/local.conf              → Machine, distro, parallelism settings
conf/bblayers.conf           → Declares layer paths
conf/*.conf                  → Global/custom configuration

# Layer Creation
yocto-layer create <name>    → Create new custom layer
meta-<name>                  → Naming convention for layers
recipes-<type>/<name>        → Directory convention inside layer

# Recipe Basics
SRC_URI                      → Source location (git, http, file://)
S                            → Working directory
do_compile, do_install       → Core tasks
FILES_${PN}                  → Installed files
inherit autotools / cmake    → Common build systems
DEPENDS                      → Build-time deps
RDEPENDS_${PN}               → Runtime deps

# Common BitBake Commands
bitbake -s                   → Show available recipes
bitbake -e <recipe>          → Show environment for recipe
bitbake -g <recipe>          → Generate dependency graphs
bitbake -c clean <recipe>    → Clean workdir
bitbake -c cleansstate <rec> → Full clean (removes sstate)
bitbake -c listtasks <rec>   → List recipe tasks
bitbake -c devshell <rec>    → Drop into build shell

# Image Creation
bitbake core-image-minimal   → Build base image
IMAGE_INSTALL_append         → Add packages to image
ROOTFS_POSTPROCESS_COMMAND   → Custom post-processing
WKS_FILE                     → Wic partition layout definition
wic create <wks> --image     → Manual image creation

# Debugging & Logs
tmp/work/.../log.*           → Task logs per recipe
tmp/deploy/images/           → Output directory
bitbake -c log <task> <rec>  → View task log
oe-pkgdata-util list-pkgs    → Installed packages
oe-run-native <tool>         → Use native-built tools

# Devtool (Layer Dev)
devtool modify <recipe>      → Extract and patch
devtool build <recipe>       → Build modified recipe
devtool finish <recipe> ...  → Finalize into layer
devtool status               → Show active workspace mods
devtool reset <recipe>       → Undo changes

# Package Feeds
bitbake package-index        → Generate package index
rpm/opkg/ipk support         → Controlled by PACKAGE_CLASSES
deploy/rpm|opkg|ipk/         → Location of built packages

# Licensing & Compliance
LICENSE                      → SPDX license ID
LIC_FILES_CHKSUM             → Required license file hash
INCOMPATIBLE_LICENSE         → Exclude licenses

# Tips
touch conf/local.conf        → Force reparse config
oe-selftest                  → Run sanity checks
buildhistory                 → Enable and track changes
EOF
)
```

Categories reflect natural workflow groupings:
- **Setup** covers environment initialization
- **Configuration Files** documents the conf/ directory structure
- **Recipe Basics** explains recipe variable semantics
- **Common BitBake Commands** provides the most-used invocations
- **Debugging & Logs** aids troubleshooting

### Category Navigation Logic

Category extraction and selection follows the established pattern:

```bash
categories=$(echo "$choices" | grep '^# ' | sed 's/# //')

selected_category=$(echo "$categories" | $DMENU -i -l 25 -p "Yocto Cheatsheet")

if [ -n "$selected_category" ]; then
    echo "$choices" | sed -n "/# $selected_category/,/^# /p" | \
        grep -v '^#' | $DMENU -i -l 30 -p "$selected_category"
fi
```

The sed range address `/# $selected_category/,/^# /p` extracts lines from the selected category header to the next category header. The subsequent `grep -v '^#'` removes the header lines, leaving only entry content for the second dmenu invocation.

## Font Detection Fallback

### The Font Availability Problem

Cheatsheet scripts may execute on systems with varying font configurations. Specifying a non-existent font causes dmenu to fall back to a default, but the `-fn` argument with an invalid font name can produce warnings or unexpected behavior on some systems.

### Runtime Font Detection

A font detection pattern ensures graceful degradation:

```bash
if fc-list | grep -qi "Hack"; then
    DMENU="dmenu -fn 'Hack-12' \
                 -nb #232136 -nf #e0def4 \
                 -sb #9ccfd8 -sf #232136"
else
    DMENU="dmenu \
                 -nb #232136 -nf #e0def4 \
                 -sb #9ccfd8 -sf #232136"
fi
```

The `fc-list` command queries the fontconfig database for available fonts. Piping through `grep -qi "Hack"` performs a case-insensitive search for the Hack font family. If found, the DMENU variable includes the font specification; otherwise, dmenu uses its compiled default.

This pattern extends to multiple font preferences:

```bash
if fc-list | grep -qi "Hack Nerd Font"; then
    FONT="'Hack Nerd Font-12'"
elif fc-list | grep -qi "Hack"; then
    FONT="'Hack-12'"
elif fc-list | grep -qi "JetBrains Mono"; then
    FONT="'JetBrains Mono-12'"
else
    FONT=""
fi

if [ -n "$FONT" ]; then
    DMENU="dmenu -fn $FONT -nb #232136 -nf #e0def4 -sb #9ccfd8 -sf #232136"
else
    DMENU="dmenu -nb #232136 -nf #e0def4 -sb #9ccfd8 -sf #232136"
fi
```

## Template for New Domains

### Starter Template

The following template provides a starting point for new domain cheatsheets:

```bash
#!/bin/bash

# Font detection with fallback
if fc-list | grep -qi "Hack"; then
    DMENU="dmenu -fn 'Hack-12' \
                 -nb #232136 -nf #e0def4 \
                 -sb #9ccfd8 -sf #232136"
else
    DMENU="dmenu \
                 -nb #232136 -nf #e0def4 \
                 -sb #9ccfd8 -sf #232136"
fi

# Domain knowledge database
choices=$(cat <<'EOF'
# Category One
item-one        → Description of item one
item-two        → Description of item two
item-three      → Description of item three

# Category Two
another-item    → What this item does
yet-another     → Explanation of behavior

# Category Three
final-item      → Last entry description
EOF
)

# Category extraction
categories=$(echo "$choices" | grep '^# ' | sed 's/# //')

# First-level menu: category selection
selected_category=$(echo "$categories" | $DMENU -i -l 20 -p "Domain Cheatsheet")

# Second-level menu: entry display within selected category
if [ -n "$selected_category" ]; then
    echo "$choices" | sed -n "/# $selected_category/,/^# /p" | \
        grep -v '^#' | $DMENU -i -l 25 -p "$selected_category"
fi
```

### Customization Points

| Element | Modification |
|---------|--------------|
| Color scheme | Adjust `-nb`, `-nf`, `-sb`, `-sf` hex values |
| Font | Change `'Hack-12'` to preferred font and size |
| List height | Modify `-l 20` and `-l 25` for display density |
| Prompt text | Replace `"Domain Cheatsheet"` with domain name |
| Separator | Change `→` to `|`, `:`, or other delimiter |

### Category Design Guidelines

Effective category organization follows these principles:

1. **Task-oriented grouping**: Categories should match mental models of the domain (e.g., "Setup", "Building", "Debugging" rather than alphabetical)

2. **Consistent granularity**: Avoid mixing high-level concepts with low-level details in the same category

3. **7±2 entries per category**: Cognitive load research suggests this range for scannable lists

4. **Predictable naming**: Use noun phrases for categories ("Configuration Files") rather than verbs ("Configure") for consistency with the entry format

## Integration Patterns

### Window Manager Bindings

Cheatsheet scripts integrate with window manager hotkey configurations:

```text
# i3/Sway configuration
bindsym $mod+F4 exec ~/.scripts/cheatsheet-yocto.sh
bindsym $mod+F5 exec ~/.scripts/cheatsheet-ffmpeg.sh
bindsym $mod+F6 exec ~/.scripts/cheatsheet-docker.sh
```

Function keys beyond F1-F3 (reserved for keybinding cheatsheets in the prior implementation) provide domain-specific access.

### Shell Aliases

For terminal-centric access without window manager involvement:

```bash
# .bashrc or .zshrc
alias yocto-help='~/.scripts/cheatsheet-yocto.sh'
alias ffmpeg-help='~/.scripts/cheatsheet-ffmpeg.sh'
```

```fish
# config.fish
alias yocto-help '~/.scripts/cheatsheet-yocto.sh'
alias ffmpeg-help '~/.scripts/cheatsheet-ffmpeg.sh'
```

### Meta-Launcher Integration

A unified launcher can present all cheatsheets (both keybinding and domain):

```bash
#!/bin/bash

DMENU="dmenu -fn 'Hack-12' -nb #232136 -nf #e0def4 -sb #9ccfd8 -sf #232136"

cheatsheets="Neovim Keybindings
tmux Keybindings
i3 Keybindings
Yocto/BitBake
ffmpeg
Docker Compose"

selected=$(echo "$cheatsheets" | $DMENU -i -l 15 -p "Cheatsheets")

case "$selected" in
    "Neovim Keybindings")  exec ~/.scripts/cheatsheet-nvim.sh ;;
    "tmux Keybindings")    exec ~/.scripts/cheatsheet-tmux.sh ;;
    "i3 Keybindings")      exec ~/.scripts/cheatsheet-i3.sh ;;
    "Yocto/BitBake")       exec ~/.scripts/cheatsheet-yocto.sh ;;
    "ffmpeg")              exec ~/.scripts/cheatsheet-ffmpeg.sh ;;
    "Docker Compose")      exec ~/.scripts/cheatsheet-docker.sh ;;
esac
```

Binding this meta-launcher to a memorable hotkey (e.g., `$mod+/` or `$mod+?`) provides universal access to all reference material.

## Additional Domain Examples

### ffmpeg Encoding Reference

```bash
choices=$(cat <<'EOF'
# Input Options
-i <file>              → Input file
-f <fmt>               → Force format
-ss <time>             → Seek to position
-t <duration>          → Limit duration

# Video Encoding
-c:v libx264           → H.264 codec
-crf 23                → Quality (0-51, lower=better)
-preset slow           → Encoding speed/quality tradeoff
-vf scale=1920:1080    → Resize video

# Audio Encoding
-c:a aac               → AAC codec
-b:a 192k              → Audio bitrate
-ar 48000              → Sample rate
-ac 2                  → Channel count

# Output Options
-y                     → Overwrite output
-n                     → Never overwrite
-map 0                 → Include all streams
EOF
)
```

### Git Subcommand Reference

```bash
choices=$(cat <<'EOF'
# Working Tree
git status             → Show working tree status
git diff               → Show unstaged changes
git diff --staged      → Show staged changes
git stash              → Stash working changes
git stash pop          → Apply and drop stash

# Branching
git branch -a          → List all branches
git checkout -b <name> → Create and switch branch
git merge <branch>     → Merge branch into current
git rebase <branch>    → Rebase onto branch

# History
git log --oneline      → Compact commit history
git log --graph        → Visualize branch history
git show <commit>      → Show commit details
git blame <file>       → Line-by-line authorship

# Remote Operations
git fetch              → Download remote refs
git pull               → Fetch and merge
git push               → Upload local commits
git remote -v          → List remotes with URLs
EOF
)
```

## Summary

The dmenu cheatsheet framework generalizes beyond keybinding references to arbitrary domain knowledge. Key characteristics of the approach:

- **Heredoc embedding** maintains single-file deployment and version control simplicity
- **Category-based navigation** scales to hundreds of entries while preserving scannability
- **Font detection fallback** ensures portability across systems with varying configurations
- **Minimal dependencies** require only bash and dmenu, tools present in most Linux environments

The Yocto/BitBake case study demonstrates applicability to complex technical domains where documentation sprawl impedes workflow efficiency. The template structure enables rapid creation of new domain cheatsheets following established patterns.

This pattern complements rather than replaces comprehensive documentation. Quick-reference cheatsheets accelerate recall of known-but-forgotten information, while detailed documentation remains essential for learning and edge cases.
