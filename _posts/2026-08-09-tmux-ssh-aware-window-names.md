---
title: SSH-Aware Window Names in tmux with Automatic Title Detection
date: 2026-08-09 10:00:00 -0700
categories: [Linux, Terminal]
tags: [tmux, ssh, status-bar, automation]
---

A technical guide to configuring tmux for automatic SSH hostname detection in window names and status bar indicators.

## Problem Statement

The default tmux configuration displays the current command name in window titles. When connected to remote hosts via SSH, this results in all windows showing "ssh" as the window name, regardless of the destination host. This behavior creates navigation difficulties when managing multiple simultaneous SSH sessions, as each window appears identical in the status bar.

Consider a typical workflow involving connections to three different servers: production, staging, and development. Without SSH-aware window naming, the tmux status bar displays:

```
[0] ssh  [1] ssh  [2] ssh
```

The desired behavior displays the actual remote hostname:

```
[0] prod-server  [1] staging-server  [2] dev-server
```

## Solution Architecture

The solution leverages two tmux features working in coordination:

1. **Conditional automatic-rename-format**: Detects when SSH is running and switches the display source
2. **Terminal title escape sequences**: Allows remote shells to set the pane title

When SSH is the active command, tmux displays the `pane_title` (set by the remote shell) instead of `pane_current_command`. This mechanism provides accurate hostname display without manual intervention.

## tmux Configuration

### Automatic Window Renaming

The following configuration enables SSH-aware automatic renaming:

```
set-option -g automatic-rename on
set-option -g allow-rename on
# When SSH is running, show pane_title (set by remote host), otherwise show command
set-option -g automatic-rename-format '#{?#{==:#{pane_current_command},ssh},#{pane_title},#{pane_current_command}}'
```

#### Configuration Breakdown

| Option | Purpose |
|--------|---------|
| `automatic-rename on` | Enables automatic window name updates based on the running command |
| `allow-rename on` | Permits escape sequences to modify the pane title |
| `automatic-rename-format` | Defines the format string for automatic naming |

The format string uses tmux's conditional syntax:

```
#{?CONDITION,TRUE_VALUE,FALSE_VALUE}
```

The condition `#{==:#{pane_current_command},ssh}` evaluates to true when the current pane command equals "ssh". When true, the window displays `#{pane_title}` (the terminal title set by the remote host). When false, it displays `#{pane_current_command}` (the local command name).

## Remote Shell Configuration

For the `pane_title` to contain useful information, the remote host must set the terminal title. This requires configuring the shell to emit escape sequences that update the terminal title.

### Terminal Title Escape Sequence

The standard escape sequence for setting the terminal title:

```
\033]0;TITLE\007
```

Or using the alternative terminator:

```
\033]0;TITLE\033\\
```

Where `TITLE` is the desired window/pane title string.

### Bash Configuration

Add the following to `~/.bashrc` on each remote host:

```bash
# Set terminal title to user@hostname
case "$TERM" in
    xterm*|rxvt*|screen*|tmux*)
        PROMPT_COMMAND='printf "\033]0;%s@%s\007" "${USER}" "${HOSTNAME%%.*}"'
        ;;
esac
```

For a more detailed title including the current directory:

```bash
PROMPT_COMMAND='printf "\033]0;%s@%s:%s\007" "${USER}" "${HOSTNAME%%.*}" "${PWD/#$HOME/~}"'
```

### Zsh Configuration

Add the following to `~/.zshrc` on each remote host:

```zsh
# Set terminal title before each prompt
precmd() {
    print -Pn "\033]0;%n@%m\007"
}
```

For directory inclusion:

```zsh
precmd() {
    print -Pn "\033]0;%n@%m:%~\007"
}
```

### Fish Configuration

Add the following to `~/.config/fish/config.fish` on each remote host:

```fish
function fish_title
    printf "%s@%s" $USER (hostname -s)
end
```

## Status Bar SSH Indicator

Beyond window naming, a visual SSH indicator in the status bar provides immediate awareness of remote connections. The following configuration displays "SSH" in a highlighted color when the active pane runs an SSH session:

```
#{?#{==:#{pane_current_command},ssh},#[fg=#f6c177 bold]SSH #[default],}
```

### Integration with Status-Right

A complete status-right configuration incorporating the SSH indicator:

```
set-option -g status-right '#{?#{==:#{pane_current_command},ssh},#[fg=#f6c177 bold]SSH #[default],}#[fg=#9ccfd8]%H:%M#[default]'
```

This displays:
- "SSH" in amber/orange (`#f6c177`) when connected to a remote host
- Current time in cyan (`#9ccfd8`)

## Advanced Status Bar Integration

### Combining Multiple Status Elements

A comprehensive status bar configuration can incorporate SSH detection alongside other contextual information:

```
# Status bar with SSH indicator, git branch, and virtualenv
set-option -g status-right '\
#{?#{==:#{pane_current_command},ssh},#[fg=#f6c177 bold]SSH #[default],}\
#(cd #{pane_current_path} && git branch --show-current 2>/dev/null | sed "s/.*/[&] /")\
#{?VIRTUAL_ENV,#[fg=#c4a7e7](venv)#[default] ,}\
#[fg=#9ccfd8]%H:%M#[default]'
```

This configuration displays (when applicable):
- SSH indicator for remote connections
- Current git branch in brackets
- Virtual environment indicator
- Current time

### Status Element Order

The recommended element order from left to right:

1. SSH indicator (connection context)
2. Git branch (repository context)
3. Virtual environment (Python context)
4. Date/time (temporal context)

This ordering presents the most relevant contextual information first.

### Window Status Format

The window status format can also incorporate SSH awareness:

```
set-option -g window-status-format '#I:#W#{?#{==:#{pane_current_command},ssh},*,}'
set-option -g window-status-current-format '#[fg=#ebbcba,bold]#I:#W#{?#{==:#{pane_current_command},ssh},*,}#[default]'
```

This appends an asterisk to window names running SSH sessions, providing a quick visual scan capability.

## Troubleshooting

### Window Name Not Updating

Verify remote shell configuration by connecting and checking the terminal title:

```bash
ssh remote-host
# On the remote host:
printf "\033]0;TEST\007"
```

If the tmux window name does not change to "TEST", check:
- `allow-rename` is set to `on`
- The remote terminal type supports title setting
- No conflicting shell configuration overrides the title

### Pane Title Shows Incorrect Information

The `pane_title` retains its value from the last escape sequence received. If disconnecting from SSH leaves an old hostname:

```
# Force pane title update from local shell
printf "\033]0;%s\007" "$(hostname)"
```

Add this to the local shell configuration to reset the title when SSH sessions end.

### TERM Variable Considerations

Some remote servers may not set the terminal title based on the `$TERM` value. Ensure the terminal type is recognized:

```bash
# Check current TERM on remote host
echo $TERM

# Should be one of: xterm-256color, screen-256color, tmux-256color
```

If necessary, configure SSH to request a specific terminal type:

```
# ~/.ssh/config
Host *
    SetEnv TERM=xterm-256color
```

## Complete Configuration Reference

### tmux.conf

```
# Window naming
set-option -g automatic-rename on
set-option -g allow-rename on
set-option -g automatic-rename-format '#{?#{==:#{pane_current_command},ssh},#{pane_title},#{pane_current_command}}'

# Status bar
set-option -g status-right-length 100
set-option -g status-right '\
#{?#{==:#{pane_current_command},ssh},#[fg=#f6c177 bold]SSH #[default],}\
#(cd #{pane_current_path} && git branch --show-current 2>/dev/null | sed "s/.*/[&] /")\
#{?VIRTUAL_ENV,#[fg=#c4a7e7](venv)#[default] ,}\
#[fg=#9ccfd8]%H:%M#[default]'
```

### Remote Host Shell Configuration

#### Bash (~/.bashrc)

```bash
case "$TERM" in
    xterm*|rxvt*|screen*|tmux*)
        PROMPT_COMMAND='printf "\033]0;%s@%s\007" "${USER}" "${HOSTNAME%%.*}"'
        ;;
esac
```

#### Zsh (~/.zshrc)

```zsh
precmd() {
    print -Pn "\033]0;%n@%m\007"
}
```

#### Fish (~/.config/fish/config.fish)

```fish
function fish_title
    printf "%s@%s" $USER (hostname -s)
end
```

## Summary

SSH-aware window naming in tmux eliminates the ambiguity of multiple "ssh" windows by displaying remote hostnames. The solution requires:

1. Conditional `automatic-rename-format` in tmux configuration
2. Terminal title escape sequences from remote shell configurations
3. Optional status bar indicators for additional visual context

This configuration scales effectively across numerous simultaneous SSH sessions, providing clear identification without manual window renaming.
