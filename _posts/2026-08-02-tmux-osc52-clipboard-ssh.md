---
title: OSC 52 Clipboard Integration in tmux for SSH Sessions
date: 2026-08-02 10:00:00 -0700
categories: [Linux, Terminal]
tags: [tmux, clipboard, ssh, osc52, terminal]
---

A technical guide to implementing OSC 52 escape sequences in tmux for seamless clipboard synchronization across SSH sessions, nested terminals, and mosh connections.

## Abstract

Clipboard access from terminal applications presents significant challenges when operating over SSH connections or within multiplexed terminal environments. OSC 52 provides a standardized mechanism for terminals to access the system clipboard through escape sequences, bypassing traditional limitations. This document details the implementation of OSC 52 clipboard integration within tmux configurations.

## Problem Statement

Standard clipboard operations fail in several common scenarios:

- **SSH Sessions**: The X11 clipboard (`xclip`, `xsel`) is unavailable without X11 forwarding, and Wayland tools (`wl-copy`) are entirely inaccessible
- **Nested tmux Sessions**: Clipboard data becomes trapped within inner tmux instances
- **Mosh Connections**: The mosh protocol does not forward clipboard state
- **Headless Servers**: No display server exists to provide clipboard functionality

Traditional solutions require either X11 forwarding (introducing latency and security considerations) or manual transfer of data through other channels. OSC 52 eliminates these requirements by communicating directly with the terminal emulator.

## Technical Background

### OSC 52 Escape Sequence

OSC (Operating System Command) 52 is a terminal escape sequence defined for clipboard manipulation. The sequence structure follows this format:

```
ESC ] 52 ; <selection> ; <base64-data> BEL
```

Where:
- `ESC ]` (0x1B 0x5D) initiates the OSC sequence
- `52` specifies the clipboard operation
- `<selection>` indicates the clipboard buffer (`c` for clipboard, `p` for primary)
- `<base64-data>` contains the clipboard content encoded in base64
- `BEL` (0x07) or `ESC \` terminates the sequence

### Operational Flow

1. The terminal application (tmux) captures text for copying
2. The text is encoded using base64 to ensure safe transmission
3. The encoded data is wrapped in the OSC 52 escape sequence
4. The escape sequence is written to stdout
5. The terminal emulator intercepts the sequence
6. The terminal decodes the base64 data and places it on the system clipboard

This mechanism functions regardless of network topology because the escape sequence travels through the same channel as normal terminal output.

## Implementation

### tmux Configuration

The following configuration enables OSC 52 clipboard integration in tmux:

```
set -s set-clipboard on
set -g @copy_command "printf '\e]52;c;$(tmux save-buffer - | base64 -w0)\a'"
bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "#{@copy_command}"
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "#{@copy_command}"
```

### Configuration Analysis

**Line 1: `set -s set-clipboard on`**

This server option enables tmux's native clipboard handling. When set, tmux attempts to use OSC 52 for clipboard operations when it detects terminal support.

**Line 2: `set -g @copy_command "..."`**

This user-defined option stores the clipboard command as a variable. The command performs three operations:
1. `tmux save-buffer -` retrieves the current tmux buffer contents
2. `base64 -w0` encodes the data without line wrapping
3. `printf '\e]52;c;...\a'` constructs and emits the OSC 52 sequence

The `c` parameter targets the system clipboard (as opposed to `p` for X11 primary selection).

**Lines 3-4: Key Bindings**

These bindings attach the copy command to vi-mode copy operations:
- `y` in copy-mode-vi triggers the copy command
- Mouse selection completion triggers the copy command

The `copy-pipe-and-cancel` action simultaneously copies to the tmux buffer and pipes to the specified command, then exits copy mode.

### Alternative: Direct Command Binding

For configurations without user-defined variables, the commands can be inlined:

```
bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "printf '\e]52;c;'\$(tmux save-buffer - | base64 -w0)'\a'"
```

Note the escaped `$` to prevent premature expansion.

## Terminal Requirements

OSC 52 requires terminal emulator support. The following terminals implement OSC 52:

| Terminal | OSC 52 Support | Notes |
|----------|----------------|-------|
| Alacritty | Enabled by default | Full support |
| Kitty | Enabled by default | Full support |
| iTerm2 | Enabled by default | macOS |
| WezTerm | Enabled by default | Cross-platform |
| foot | Enabled by default | Wayland native |
| xterm | Requires configuration | Set `disallowedWindowOps` |
| GNOME Terminal | Limited | VTE-based, partial support |
| Windows Terminal | Supported | Recent versions |

### Verification of Terminal Support

Terminal support can be verified by executing the following test:

```bash
printf '\e]52;c;%s\a' "$(echo -n 'test clipboard' | base64)"
```

If the terminal supports OSC 52, the text "test clipboard" should appear when pasting from the system clipboard.

### Enabling in xterm

xterm requires explicit configuration. Add to `~/.Xresources`:

```
XTerm*disallowedWindowOps: 20,21,SetXprop
```

This removes clipboard operations from the disallowed list while maintaining other security restrictions.

## Testing and Verification

### Basic Functionality Test

1. Enter tmux
2. Execute: `echo "OSC 52 test" | tmux load-buffer -`
3. Enter copy mode: `<prefix> [`
4. Select text and press `y`
5. Paste in an external application

The copied text should appear in the external application clipboard.

### SSH Session Test

1. SSH into a remote host
2. Start or attach to a tmux session
3. Copy text using the configured bindings
4. Paste locally (outside the SSH session)

Success indicates OSC 52 traversal through the SSH connection.

### Nested tmux Test

1. Start tmux locally
2. SSH to a remote host within tmux
3. Start tmux on the remote host
4. Copy text in the inner tmux session
5. Paste locally

If the local clipboard receives the text, OSC 52 is propagating correctly through both tmux layers.

### Debug Mode

Enable tmux logging to diagnose issues:

```bash
tmux set -g @copy_command "printf '\e]52;c;%s\a' \"\$(tmux save-buffer - | tee /tmp/tmux-copy-debug | base64 -w0)\""
```

This logs copied content to `/tmp/tmux-copy-debug` for inspection.

## Limitations and Security Considerations

### Security Restrictions

Some terminal emulators disable or restrict OSC 52 for security reasons:

- **Read operations disabled**: Many terminals only allow write (copy) operations, preventing applications from reading clipboard contents
- **Size limits**: Some terminals impose maximum payload sizes (typically 74994 bytes base64-encoded)
- **User prompts**: Certain terminals prompt for confirmation before clipboard access

### Known Limitations

1. **Base64 overhead**: Encoded data is approximately 33% larger than raw data
2. **Binary data**: While base64 handles binary data, some terminals may have issues with certain content types
3. **Large selections**: Extremely large text selections may exceed terminal buffer limits
4. **Clipboard history managers**: Some clipboard managers may not recognize OSC 52 updates

### Multiplexer Interaction

When running tmux inside tmux or screen, the outer multiplexer may intercept OSC 52 sequences. The `set -s set-clipboard on` option in the outer tmux session allows passthrough of these sequences.

For screen, equivalent functionality requires version 4.6.0 or later with appropriate configuration.

## Troubleshooting

### Clipboard Not Updating

1. Verify terminal OSC 52 support using the test command
2. Check tmux option: `tmux show -s set-clipboard`
3. Verify the copy command: `tmux show -g @copy_command`
4. Test base64 encoding: `echo test | base64 -w0`

### SSH Session Issues

1. Confirm the local terminal (not the remote) supports OSC 52
2. Verify SSH is not filtering escape sequences
3. Test with a simple echo: `ssh host "printf '\e]52;c;dGVzdA==\a'"`

### Sequence Truncation

If large copies fail:

1. Check terminal documentation for size limits
2. Consider chunked copying for large data
3. Use alternative methods (scp, rsync) for large transfers

## Summary

OSC 52 provides a robust solution for clipboard synchronization in terminal environments where traditional methods fail. The implementation requires:

1. A terminal emulator with OSC 52 support
2. tmux configured with `set-clipboard on`
3. Copy bindings that emit the OSC 52 escape sequence

This configuration enables seamless clipboard operations across SSH sessions, nested multiplexers, and headless environments, eliminating the need for X11 forwarding or external clipboard synchronization tools.
