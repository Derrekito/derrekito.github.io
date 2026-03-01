---
title: "Building a Context-Aware Help System in tmux"
date: 2026-08-16 10:00:00 -0700
categories: [Linux, Terminal]
tags: [tmux, help, keybindings, productivity]
---

A modal help system for tmux that displays mode-specific keybinding references. Rather than presenting an overwhelming list of all commands, the system shows only the bindings relevant to the current context: pane management in root mode, text operations in copy mode, and tree navigation in choose-tree mode.

## Problem Statement

The tmux terminal multiplexer provides extensive functionality through keyboard shortcuts. A typical configuration includes bindings for pane management, window operations, session control, copy mode, and plugin-specific commands. The built-in help system (accessed via `prefix ?`) displays a raw list of all bindings across all modes—a wall of text that proves difficult to parse during active workflow.

Several factors compound this usability challenge:

- **Mode-specific bindings**: Different keybindings apply in root mode, copy mode, and choose-tree mode. The built-in help conflates all of these.
- **Plugin additions**: Plugins like tmux-pain-control, vim-tmux-navigator, and tmux-yank add their own bindings that do not appear in the default help.
- **Custom overrides**: Personal configurations override defaults and add new bindings. These customizations exist only in configuration files.
- **Cognitive load**: Remembering 50+ bindings across multiple modes exceeds typical working memory capacity.

External cheatsheets (printed references, markdown files, browser tabs) require context-switching away from the terminal. The ideal solution surfaces help within tmux itself, scoped to the current operational mode.

## Solution Architecture

The implementation leverages tmux's `display-popup` command to render help text in a floating overlay. Each mode receives its own dedicated help popup, bound to a consistent key (`?` in root mode, `H` in copy-mode-vi and choose-tree modes).

The architecture consists of three components:

1. **Root mode help**: Pane management, navigation, sessions, windows
2. **Copy mode help**: Movement, selection, search, yanking
3. **Choose-tree mode help**: Session/window tree navigation

Each help popup executes a shell command that echoes formatted text, then waits for a keypress before dismissing.

```text
┌─────────────────────────────────────────────────────────────┐
│                    Root Mode (prefix ?)                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Pane creation, navigation, resizing                │    │
│  │  Window management                                   │    │
│  │  Session operations                                  │    │
│  │  Mode entry points                                   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   Copy Mode (H)                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Vim-style movement                                  │    │
│  │  Selection (visual, line, rectangle)                │    │
│  │  Search (forward/backward, incremental)             │    │
│  │  Yank/copy operations                               │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  Choose-Tree Mode (h)                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Tree navigation (j/k, expand/collapse)             │    │
│  │  Session operations (kill, rename)                  │    │
│  │  Window operations (kill, rename)                   │    │
│  │  View options (preview, sort)                       │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Pattern

The `display-popup` command creates a floating terminal window that overlays the current tmux session. The `-E` flag closes the popup when the shell command exits. The `-h` and `-w` flags control popup dimensions as percentages of the terminal size.

```bash
bind-key '?' display-popup -E -h 80% -w 80% 'sh -c "
echo \"PANE MANAGEMENT HELP\"
echo \"\"
echo \"PANE CREATION:\"
echo \"  |          Split pane horizontally\"
echo \"  -          Split pane vertically\"
# ... additional bindings
read -n 1
"'
```

The `read -n 1` command at the end pauses the popup until any key is pressed, then exits and dismisses the popup automatically.

## Root Mode Help Implementation

The root mode help popup provides comprehensive reference for pane, window, and session operations. This binding replaces the default `?` behavior with a curated, categorized display.

```bash
# Pane Management help (main mode)
unbind-key '?'
bind-key '?' display-popup -E -h 80% -w 80% 'sh -c "
echo \"═══════════════════════════════════════════════════════════════════════════════\"
echo \"                            PANE MANAGEMENT HELP\"
echo \"═══════════════════════════════════════════════════════════════════════════════\"
echo \"\"
echo \"PANE CREATION:\"
echo \"  |          Split pane horizontally\"
echo \"  -          Split pane vertically\"
echo \"  c          Create new window\"
echo \"\"
echo \"PANE NAVIGATION:\"
echo \"  h/C-h      Move to left pane\"
echo \"  j/C-j      Move to pane below\"
echo \"  k/C-k      Move to pane above\"
echo \"  l/C-l      Move to right pane\"
echo \"  ;          Move to last active pane\"
echo \"  o          Move to next pane\"
echo \"\"
echo \"PANE RESIZING:\"
echo \"  M-h        Resize pane left\"
echo \"  M-j        Resize pane down\"
echo \"  M-k        Resize pane up\"
echo \"  M-l        Resize pane right\"
echo \"\"
echo \"PANE MANAGEMENT:\"
echo \"  x          Kill current pane\"
echo \"  z          Zoom/unzoom current pane\"
echo \"  !          Break pane into new window\"
echo \"  {          Swap with previous pane\"
echo \"  }          Swap with next pane\"
echo \"  H          Swap pane left\"
echo \"  J          Swap pane down\"
echo \"  K          Swap pane up\"
echo \"  L          Swap pane right\"
echo \"  S          Toggle pane synchronization (send input to all panes)\"
echo \"\"
echo \"SESSIONS & WINDOWS:\"
echo \"  w          Show session/window tree (press h for help there)\"
echo \"  s          Show session list\"
echo \"  Tab        Switch to last session\"
echo \"  d          Detach from session\"
echo \"  C-h        Move window left\"
echo \"  C-j        Move window down/left\"
echo \"  C-k        Move window up/right\"
echo \"  C-l        Move window right\"
echo \"  r          Reload tmux config\"
echo \"\"
echo \"COPY MODE:\"
echo \"  [          Enter copy mode (press H for help there)\"
echo \"\"
echo \"OTHER:\"
echo \"  ?          Show built-in tmux command list\"
echo \"  H          Show this help menu\"
echo \"\"
echo \"Press any key to continue...\"
read -n 1
"'
```

Notable design decisions in this implementation:

- **Logical grouping**: Bindings are organized by function (creation, navigation, resizing, management) rather than alphabetically
- **Cross-references**: The help text points to related modes ("press h for help there")
- **Modifier notation**: Meta/Alt is shown as `M-`, Control as `C-` following standard tmux conventions
- **Visual hierarchy**: Box-drawing characters and section headers create scannable structure

## Copy Mode Help Implementation

Copy mode in tmux (especially with vi bindings enabled) provides extensive text manipulation capabilities. The help popup documents movement, selection, and search operations.

```bash
# Copy Mode help
unbind-key -T copy-mode-vi H
bind-key -T copy-mode-vi H display-popup -E -h 80% -w 80% 'sh -c "
echo \"═══════════════════════════════════════════════════════════════════════════════\"
echo \"                              COPY MODE HELP\"
echo \"═══════════════════════════════════════════════════════════════════════════════\"
echo \"\"
echo \"MOVEMENT:\"
echo \"  h/Left     Move cursor left\"
echo \"  j/Down     Move cursor down\"
echo \"  k/Up       Move cursor up\"
echo \"  l/Right    Move cursor right\"
echo \"  w          Jump to next word\"
echo \"  b          Jump to previous word\"
echo \"  0/^        Jump to start of line\"
echo \"  \$          Jump to end of line\"
echo \"  g          Jump to top of buffer\"
echo \"  G          Jump to bottom of buffer\"
echo \"\"
echo \"SELECTION:\"
echo \"  v          Start selection\"
echo \"  V          Select whole line\"
echo \"  C-v        Rectangle selection\"
echo \"  y          Copy selection and exit\"
echo \"  Enter      Copy selection and exit\"
echo \"\"
echo \"SEARCH:\"
echo \"  /          Search forward (case-insensitive)\"
echo \"  ?          Search backward (case-insensitive)\"
echo \"  n          Next search result\"
echo \"  N          Previous search result\"
echo \"\"
echo \"OTHER:\"
echo \"  q/Escape   Exit copy mode\"
echo \"  H          Show this help menu\"
echo \"\"
echo \"Press any key to continue...\"
read -n 1
"'
```

The binding uses `-T copy-mode-vi` to target the vi-style copy mode key table. The `unbind-key` preceding the bind ensures no conflict with any existing `H` binding in that mode.

## Choose-Tree Mode Help Implementation

The choose-tree mode presents a navigable tree of sessions and windows. This mode has its own distinct set of bindings that differ from both root mode and copy mode.

```bash
# Session/Window chooser help
bind-key -T choose-tree h display-popup -E -h 80% -w 80% 'sh -c "
echo \"═══════════════════════════════════════════════════════════════════════════════\"
echo \"                      SESSION/WINDOW CHOOSER HELP\"
echo \"═══════════════════════════════════════════════════════════════════════════════\"
echo \"\"
echo \"NAVIGATION:\"
echo \"  j/Down     Move down one item\"
echo \"  k/Up       Move up one item\"
echo \"  Enter      Select/switch to highlighted session/window\"
echo \"  q/Escape   Exit chooser\"
echo \"\"
echo \"SESSION MANAGEMENT:\"
echo \"  d          Kill selected session\"
echo \"  x          Kill selected session\"
echo \"  D          Kill selected session (prompt)\"
echo \"\"
echo \"WINDOW MANAGEMENT:\"
echo \"  &          Kill selected window\"
echo \"  X          Kill selected window (prompt)\"
echo \"\"
echo \"FILTERING & SEARCH:\"
echo \"  s          Search/filter items\"
echo \"/          Search forward\"
echo \"  n          Next match\"
echo \"  N          Previous match\"
echo \"\"
echo \"VIEW OPTIONS:\"
echo \"  v          Toggle preview\"
echo \"  t          Toggle tree/flat view\"
echo \"  O          Change sort order\"
echo \"\"
echo \"OTHER:\"
echo \"  ?          Show built-in tmux help\"
echo \"  h/F1       Show this help menu\"
echo \"\"
echo \"Press any key to continue...\"
read -n 1
"'
```

The lowercase `h` serves as the help key in choose-tree mode, avoiding conflict with potential navigation bindings on `H`.

## Introductory Help Popup

An additional help popup can serve as an entry point for users unfamiliar with the help system itself. This popup explains how to access mode-specific help.

```bash
bind-key i display-popup -E -h 80% -w 80% 'bash -c "
clear
echo \"═══════════════════════════════════════════════════════════════════\"
echo \"              SESSION/WINDOW TREE HELP\"
echo \"═══════════════════════════════════════════════════════════════════\"
echo \"\"
echo \"First press <leader>+w to open tree, then use:\"
echo \"\"
echo \"NAVIGATION:\"
echo \"  j/k/↑/↓    Move up/down\"
echo \"  Enter      Switch to selection\"
echo \"  q/Escape   Exit tree\"
echo \"\"
echo \"SESSION OPERATIONS:\"
echo \"  d          Kill session\"
echo \"  \$          Rename session\"
echo \"\"
echo \"WINDOW OPERATIONS:\"
echo \"  &          Kill window\"
echo \"  ,          Rename window\"
echo \"\"
echo \"SEARCH:\"
echo \"  s          Search/filter\"
echo \"\"
echo \"Press any key to continue...\"
read -n 1
"'
```

## Design Considerations

### Content Selection

Determining which bindings to include requires balancing comprehensiveness against scannability. The following criteria guide inclusion:

- **Frequency of use**: Common operations receive prominent placement
- **Discoverability**: Non-obvious bindings (like `!` to break pane to window) warrant inclusion
- **Plugin bindings**: Custom and plugin-added bindings that do not appear in default help
- **Mode-specific scope**: Only bindings applicable to the current mode

Rarely-used bindings and those with obvious mnemonics may be omitted to reduce visual noise.

### Formatting Guidelines

Consistent formatting improves scannability:

- **Fixed-width alignment**: Key names align in a column, descriptions in another
- **Section headers**: ALL CAPS headers with blank lines for visual grouping
- **Box-drawing characters**: Unicode box characters (═, ║) create visual boundaries
- **Modifier notation**: Consistent use of `C-` for Control, `M-` for Meta/Alt

### Color Integration

The popup inherits terminal colors from the tmux session. For configurations using a theme (such as Rose Pine), the help text benefits from the established color palette. The Rose Pine Moon theme provides these accent colors:

```bash
# Rose Pine Moon palette reference
# Base: #232136 | Surface: #2a273f | Overlay: #393552
# Text: #e0def4 | Subtle: #908caa | Muted: #6e6a86
# Love: #eb6f92 | Gold: #f6c177 | Rose: #ea9a97
# Pine: #3e8fb0 | Foam: #9ccfd8 | Iris: #c4a7e7
```

For colored help text, ANSI escape sequences can be embedded in the echo statements:

```bash
echo -e "\e[38;2;246;193;119m═══════════════════════════════════════════════════════════════════\e[0m"
echo -e "\e[38;2;196;167;231m                            PANE MANAGEMENT HELP\e[0m"
```

However, plain text provides broader compatibility across terminal emulators and avoids escape sequence complexity.

## Integration with FZF Pickers

The help system complements FZF-based pickers for session and window management. While the pickers provide fuzzy search over live session data, the help popups document the available operations.

```bash
# FZF session switcher
bind-key s display-popup -E -w 50% -h 40% '\
    tmux list-sessions -F "#{session_name} │ #{session_windows} windows #{?session_attached,(attached),}" | \
    fzf --reverse --header="Switch to session" \
        --color="bg+:#3e8fb0,fg+:#e0def4,hl:#c4a7e7,hl+:#c4a7e7,header:#9ccfd8,pointer:#eb6f92" | \
    cut -d" " -f1 | \
    xargs -r tmux switch-client -t'
```

The help popup and FZF picker serve different purposes: the help documents operations, while the picker executes them. Both use the `display-popup` mechanism for consistent visual presentation.

## Preserving Built-in Help Access

The original `?` binding shows tmux's internal command list, which remains useful for debugging and discovering unmapped commands. This functionality can be preserved by rebinding it to choose-tree mode:

```bash
unbind-key -T choose-tree ?
bind-key -T choose-tree ? send -X help
```

Alternatively, the root mode help popup can document how to access the built-in help through the command prompt (`:list-keys`).

## Extension Possibilities

Several enhancements can extend the help system:

- **Dynamic generation**: Parse `tmux list-keys` output to auto-generate help content, ensuring synchronization with actual bindings
- **Searchable help**: Pipe help content through FZF for fuzzy search within the help text
- **Multi-page help**: Implement paging for extensive help content using `less` or a pager
- **Context detection**: Automatically display relevant help based on detected mode

## Configuration Requirements

The help system requires tmux 3.2 or later for `display-popup` support. Earlier versions lack the popup functionality.

Verify popup support:

```bash
tmux display-popup -E 'echo "Popup works"; read -n 1'
```

If the command fails, upgrade tmux or fall back to `display-message` for simpler notifications.

## Conclusion

Context-aware help popups address the discoverability challenge in complex tmux configurations. By scoping help content to the current operational mode, the system reduces cognitive load and surfaces relevant bindings at the moment of need.

The implementation pattern—`display-popup` with shell commands and a blocking `read`—generalizes to any interactive help scenario in tmux. The same mechanism can present plugin documentation, quick reference cards, or workflow guides.

The modal approach mirrors how modern applications provide context-sensitive help: different help for different states. Applied to tmux, this pattern transforms an overwhelming list of bindings into navigable, mode-specific reference material accessible without leaving the terminal.
