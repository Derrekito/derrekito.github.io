---
title: "Building Searchable Keybinding Cheatsheets with dmenu"
date: 2026-11-01 10:00:00 -0700
categories: [Linux, Workflow]
tags: [dmenu, bash, keybindings, neovim, tmux, i3, productivity]
---

Terminal-centric workflows rely heavily on keyboard shortcuts. As configurations grow across editors, multiplexers, and window managers, the cognitive load of memorizing hundreds of keybindings becomes a significant obstacle. This post presents a shell-based cheatsheet system using dmenu that provides instant, searchable access to keybindings organized by category.

## Problem Statement

### The Keybinding Proliferation Challenge

Power users accumulate keybindings across multiple tools:

- **Text Editors**: Neovim alone can have 200+ bindings across modes, plugins, and LSP features
- **Terminal Multiplexers**: tmux session, window, and pane management shortcuts
- **Window Managers**: i3/Sway workspace switching, container manipulation, launcher bindings
- **Additional Tools**: Git clients, debuggers, file managers, each with their own shortcuts

Several factors compound this challenge:

1. **Context Switching**: Moving between tools requires mental context switches for different binding conventions
2. **Infrequent Bindings**: Rarely-used but powerful commands are forgotten between uses
3. **Configuration Drift**: New bindings are added but memory of existing ones fades
4. **Documentation Scatter**: Binding references exist in config files, man pages, and external documentation

### Existing Solutions and Limitations

**Man pages and help commands** provide comprehensive references but require leaving the current context and navigating verbose documentation.

**Printed cheatsheets** become outdated as configurations evolve and offer no search capability.

**which-key style popup hints** show continuations after pressing a leader key but cannot display all bindings for a concept (e.g., "all git-related bindings") across different prefixes.

**Browser-based references** break keyboard-centric workflows and require window switching.

The desired solution provides instant access from any context, supports fuzzy search, integrates with the existing visual theme, and requires minimal maintenance overhead.

## Technical Background

### dmenu as a Fuzzy Selection Interface

dmenu (dynamic menu) is a minimalist X11 application that reads lines from standard input and presents them as a selectable menu. The selected line is written to standard output.

Core characteristics:

- **Stdin/stdout interface**: Composable with standard Unix pipelines
- **Fuzzy matching**: Built-in incremental search narrows options
- **Keyboard-driven**: Navigation via arrow keys or Ctrl-n/Ctrl-p
- **Themeable**: Colors, fonts, and dimensions configurable via command-line arguments

Basic usage pattern:

```bash
echo -e "option1\noption2\noption3" | dmenu -p "Select:"
```

The `-p` flag sets the prompt text. dmenu blocks until the user makes a selection or dismisses the menu, then outputs the selected line.

### Hierarchical vs. Flat Navigation

Two navigation patterns apply to keybinding lookups:

**Flat Navigation**: All bindings appear in a single searchable list. This approach works well for small binding sets (under 50 entries) where the full list remains scannable.

```text
┌─────────────────────────────────────┐
│ i3 Shortcuts                        │
├─────────────────────────────────────┤
│ $mod+Return      → Open terminal    │
│ $mod+d           → Launch dmenu     │
│ $mod+Shift+q     → Kill focused     │
│ $mod+1..0        → Switch workspace │
│ ...                                 │
└─────────────────────────────────────┘
```

**Hierarchical Navigation**: Categories are presented first; selecting a category reveals its bindings. This pattern scales to hundreds of bindings while maintaining clarity.

```text
┌─────────────────────────┐      ┌─────────────────────────────────┐
│ Neovim Shortcuts        │      │ LSP (Normal Mode)               │
├─────────────────────────┤      ├─────────────────────────────────┤
│ Leader Key              │      │ n: gr     → Telescope refs      │
│ Standard Vim Bindings   │ ──►  │ n: gd     → Go to definition    │
│ Core Neovim (Normal)    │      │ n: K      → Hover               │
│ LSP (Normal Mode)       │      │ n: <leader>vca → Code action    │
│ Harpoon (Normal Mode)   │      │ n: <leader>vrn → Rename         │
│ ...                     │      │                                 │
└─────────────────────────┘      └─────────────────────────────────┘
     Category Selection                 Binding List
```

## Architecture

### Heredoc-Based Binding Database

Each cheatsheet script embeds its bindings in a heredoc structure. This approach offers several advantages:

- **Single-file deployment**: No external data files to manage
- **Version control friendly**: Changes appear as simple diffs
- **Shell-native**: No parsing libraries or external dependencies
- **Human-readable**: The heredoc serves as documentation itself

The binding format uses a consistent structure:

```text
# Category Name
keybinding          → description
keybinding          → description

# Another Category
keybinding          → description
```

Category headers begin with `#` followed by a space and the category name. Binding entries use an arrow separator (`→`) between the key sequence and its description. Whitespace alignment improves readability in both the source file and the dmenu display.

### Script Structure

A two-level cheatsheet script contains four logical sections:

```bash
#!/bin/bash

# 1. Theme configuration
DMENU="dmenu -fn 'Hack-12' -nb #232136 -nf #e0def4 -sb #9ccfd8 -sf #232136"

# 2. Binding database (heredoc)
choices=$(cat <<'EOF'
# Category One
binding → description
...
EOF
)

# 3. Category extraction
categories=$(echo "$choices" | grep '^# [A-Z]' | sed 's/# //')

# 4. Two-level menu logic
selected_category=$(echo "$categories" | $DMENU -i -l 32 -p "Tool Shortcuts")

if [ -n "$selected_category" ]; then
    # Extract and display bindings for selected category
fi
```

### Data Flow Diagram

The two-level navigation follows this data flow:

```text
┌─────────────────────────────────────────────────────────────────┐
│                         HEREDOC                                 │
│  # Leader Key                                                   │
│  <Space>  → Leader key                                          │
│  # Standard Vim Bindings                                        │
│  h/j/k/l  → Move cursor                                         │
│  ...                                                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  grep '^# [A-Z]' | sed 's/# //' │
              │  Category Extraction           │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │        First dmenu            │
              │   (Category Selection)        │
              └───────────────────────────────┘
                              │
                    User selects category
                              │
                              ▼
              ┌───────────────────────────────┐
              │  sed -n '/pattern1/,/pattern2/p' │
              │  OR awk section extraction     │
              │  Section Filtering             │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │        Second dmenu           │
              │   (Binding Display)           │
              └───────────────────────────────┘
```

## Implementation Details

### Category Extraction with grep and sed

Categories are extracted from the heredoc using pattern matching:

```bash
categories=$(echo "$choices" | grep '^# [A-Z]' | sed 's/# //')
```

This pipeline:

1. **grep '^# [A-Z]'**: Matches lines starting with `#`, a space, and an uppercase letter. This pattern captures top-level category headers while excluding subcategory markers (e.g., `## Normal Mode`).

2. **sed 's/# //'**: Removes the `# ` prefix, leaving only the category name for display in dmenu.

Example transformation:

```text
Input:                          Output:
# Leader Key                    Leader Key
<Space> → Leader key
# Standard Vim Bindings    →    Standard Vim Bindings
## Normal Mode
h/j/k/l → Move cursor
# Core Neovim (Normal)          Core Neovim (Normal)
```

### Section Extraction with sed Range Addresses

The sed approach uses range addresses to extract lines between two patterns:

```bash
echo "$choices" | sed -n "/# $selected_category/,/^# [^$selected_category]/p" | grep -v '^#'
```

Breaking down this pattern:

- **`-n`**: Suppresses automatic printing; only explicit `p` commands produce output
- **`/# $selected_category/`**: Start address matches the selected category header
- **`,`**: Range operator
- **`/^# [^...]/`**: End address matches the next top-level category header
- **`p`**: Print lines in range
- **`grep -v '^#'`**: Remove category headers from output, showing only bindings

This approach works for most categories but requires special handling for category names that share prefixes (e.g., "Standard Vim Bindings" would match before "Standard" alone).

### Section Extraction with awk

The awk approach provides more precise control over section boundaries:

```bash
section=$(echo "$choices" | awk -v section="$selected_category" '
    BEGIN { print_section=0 }
    $0 ~ "^# "section"$" { print_section=1; next }
    /^# / && print_section { exit }
    print_section && !/^#/ { print }
')
```

Line-by-line analysis:

| Line | Function |
|------|----------|
| `BEGIN { print_section=0 }` | Initialize state variable to "not printing" |
| `$0 ~ "^# "section"$"` | Match exact category header; require end-of-line anchor |
| `{ print_section=1; next }` | Enable printing, skip to next line (exclude header) |
| `/^# / && print_section` | If another category header is found while printing |
| `{ exit }` | Stop processing; section is complete |
| `print_section && !/^#/` | If printing is enabled and line is not a header |
| `{ print }` | Output the binding line |

The awk approach handles edge cases more robustly:

- Exact category name matching prevents prefix collisions
- Explicit state machine logic makes behavior predictable
- The `exit` command terminates early, improving performance for large files

### Flat Navigation Implementation

For smaller binding sets, flat navigation suffices:

```bash
#!/bin/bash

choices=$(cat <<'EOF'
$mod+Return      → Open terminal
$mod+d           → Launch dmenu
$mod+Shift+q     → Kill focused window
...
EOF
)

echo "$choices" | dmenu -i -l 20 -p "i3 Shortcuts"
```

This implementation:

- Omits category headers entirely
- Pipes the complete binding list directly to dmenu
- Uses `-i` for case-insensitive matching
- Uses `-l 20` to display 20 lines in vertical list mode

## Theming Integration

### dmenu Color Arguments

dmenu accepts color configuration via command-line arguments:

| Argument | Purpose | Format |
|----------|---------|--------|
| `-nb` | Normal background | Hex color |
| `-nf` | Normal foreground | Hex color |
| `-sb` | Selected background | Hex color |
| `-sf` | Selected foreground | Hex color |
| `-fn` | Font specification | Xft font string |

### Rose Pine Moon Theme Application

The Rose Pine Moon color palette provides a cohesive visual theme:

```bash
DMENU="dmenu -fn 'Hack-12' \
             -nb #232136 \
             -nf #e0def4 \
             -sb #9ccfd8 \
             -sf #232136"
```

Color mapping:

| Element | Color | Rose Pine Token |
|---------|-------|-----------------|
| Normal background | `#232136` | Base |
| Normal foreground | `#e0def4` | Text |
| Selected background | `#9ccfd8` | Foam (cyan accent) |
| Selected foreground | `#232136` | Base (inverted) |

The selected item uses an inverted color scheme (light background with dark text) for clear visual distinction.

### Font Configuration

The font specification follows Xft naming conventions:

```text
'Hack-12'
```

This specifies:
- **Font family**: Hack (a monospace programming font)
- **Size**: 12 points

More complex specifications support additional properties:

```text
'Hack Nerd Font:size=12:style=Regular'
```

Monospace fonts ensure consistent column alignment for the arrow separators in binding entries.

## Extension Patterns

### Adding a New Application Cheatsheet

To create a cheatsheet for a new application:

**Step 1**: Determine navigation complexity

- Fewer than 50 bindings: Use flat navigation
- 50+ bindings: Use hierarchical navigation with categories

**Step 2**: Create the script structure

For hierarchical navigation:

```bash
#!/bin/bash

DMENU="dmenu -fn 'Hack-12' -nb #232136 -nf #e0def4 -sb #9ccfd8 -sf #232136"

choices=$(cat <<'EOF'
# Category One
binding1 → description
binding2 → description

# Category Two
binding3 → description
binding4 → description
EOF
)

categories=$(echo "$choices" | grep '^# [A-Z]' | sed 's/# //')

selected_category=$(echo "$categories" | $DMENU -i -l 20 -p "AppName Shortcuts")

if [ -n "$selected_category" ]; then
    section=$(echo "$choices" | awk -v section="$selected_category" '
        BEGIN { print_section=0 }
        $0 ~ "^# "section"$" { print_section=1; next }
        /^# / && print_section { exit }
        print_section && !/^#/ { print }
    ')
    echo "$section" | $DMENU -i -l 20 -p "$selected_category"
fi
```

**Step 3**: Populate the heredoc with bindings organized by logical category

**Step 4**: Bind to a global hotkey via the window manager

```text
# i3 config
bindsym $mod+F1 exec ~/.scripts/cheatsheet-appname.sh
```

### Centralizing Theme Configuration

For multiple cheatsheet scripts, theme duplication can be eliminated by sourcing a common configuration:

```bash
# ~/.scripts/dmenu-theme.sh
export DMENU_THEME="-fn 'Hack-12' -nb #232136 -nf #e0def4 -sb #9ccfd8 -sf #232136"
```

```bash
# Individual cheatsheet scripts
source ~/.scripts/dmenu-theme.sh
DMENU="dmenu $DMENU_THEME"
```

### Adding Search-and-Execute Capability

The basic implementation displays bindings for reference. An enhanced version could execute actions:

```bash
# After second dmenu selection
selected_binding=$(echo "$section" | $DMENU -i -l 20 -p "$selected_category")

if [ -n "$selected_binding" ]; then
    # Extract key sequence before arrow
    key=$(echo "$selected_binding" | sed 's/ *→.*//')
    # Send to active window via xdotool (for demonstration)
    notify-send "Selected binding" "$key"
fi
```

This pattern enables building launcher-style interfaces where selecting an action executes it rather than simply displaying it.

## ASCII Mockup: Two-Level Navigation Flow

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│   User presses hotkey (e.g., Mod+F1)                                     │
│                                                                          │
│                              │                                           │
│                              ▼                                           │
│   ┌──────────────────────────────────────────────┐                       │
│   │ Neovim Shortcuts                             │                       │
│   ├──────────────────────────────────────────────┤                       │
│   │ > Leader Key                                 │  ◄── First dmenu     │
│   │   Standard Vim Bindings                      │      shows categories │
│   │   Core Neovim (Normal Mode)                  │                       │
│   │   Core Neovim (Visual Mode)                  │                       │
│   │   Terminal Integration (Normal Mode)         │                       │
│   │   Buffer Management (Normal Mode)            │                       │
│   │   Window Management (Normal Mode)            │                       │
│   │   LSP (Normal Mode)                          │                       │
│   │   Telescope (Normal Mode)                    │                       │
│   │   Harpoon (Normal Mode)                      │                       │
│   │   Fugitive (Git, Normal Mode)                │                       │
│   │   Gitsigns (Git, Normal Mode)                │                       │
│   │   DAP (Debugging, Normal Mode)               │                       │
│   └──────────────────────────────────────────────┘                       │
│                              │                                           │
│                   User types "lsp" and presses Enter                     │
│                              │                                           │
│                              ▼                                           │
│   ┌──────────────────────────────────────────────┐                       │
│   │ LSP (Normal Mode)                            │                       │
│   ├──────────────────────────────────────────────┤                       │
│   │ > n: gr                 → Telescope refs     │  ◄── Second dmenu    │
│   │   n: gd                 → Go to definition   │      shows bindings   │
│   │   n: K                  → Hover              │      in category      │
│   │   n: <leader>vws        → Workspace symbol   │                       │
│   │   n: <leader>vca        → Code action        │                       │
│   │   n: <leader>vrr        → References         │                       │
│   │   n: <leader>vrn        → Rename             │                       │
│   └──────────────────────────────────────────────┘                       │
│                              │                                           │
│                   User views binding or presses Escape                   │
│                              │                                           │
│                              ▼                                           │
│                                                                          │
│   dmenu closes, user returns to previous context                         │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Integration with Window Manager

### i3/Sway Keybinding Example

```text
# ~/.config/i3/config

# Cheatsheet bindings
bindsym $mod+F1 exec ~/.scripts/cheatsheet-nvim.sh
bindsym $mod+F2 exec ~/.scripts/cheatsheet-tmux.sh
bindsym $mod+F3 exec ~/.scripts/cheatsheet-i3.sh
```

The function keys provide consistent access regardless of the currently focused application.

### Alternative: Unified Launcher

A meta-script can present all cheatsheets in a single interface:

```bash
#!/bin/bash

DMENU="dmenu -fn 'Hack-12' -nb #232136 -nf #e0def4 -sb #9ccfd8 -sf #232136"

apps="Neovim
tmux
i3"

selected=$(echo "$apps" | $DMENU -i -l 10 -p "Cheatsheets")

case "$selected" in
    "Neovim") exec ~/.scripts/cheatsheet-nvim.sh ;;
    "tmux")   exec ~/.scripts/cheatsheet-tmux.sh ;;
    "i3")     exec ~/.scripts/cheatsheet-i3.sh ;;
esac
```

## Summary

The dmenu-based cheatsheet system provides a lightweight, keyboard-driven solution for keybinding reference. Key architectural decisions include:

- **Heredoc embedding**: Self-contained scripts with no external dependencies
- **Hierarchical navigation**: Two-level dmenu interaction scales to hundreds of bindings
- **Pattern-based extraction**: grep, sed, and awk provide robust text processing
- **Theme consistency**: Centralized color configuration maintains visual coherence

The implementation requires only bash and dmenu, tools already present in most Linux desktop environments. Scripts remain human-readable and version-control friendly, evolving alongside the configurations they document.

This approach complements rather than replaces in-editor solutions like which-key or Telescope-based pickers. dmenu cheatsheets provide cross-application access from any context, while editor-native solutions offer deeper integration within their respective tools.
