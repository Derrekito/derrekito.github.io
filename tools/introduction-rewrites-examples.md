# Introduction Rewrite Examples

This document shows before/after examples for weak introductions, demonstrating the pattern.

---

## Example 1: Dotfiles Management (Multi-Machine Dotfiles Management with Git Worktrees)

### ❌ BEFORE (16 words, generic)
```markdown
A comprehensive guide to managing dotfiles across multiple machines using git worktrees and automatic deployment hooks.
```

**Issues**:
- Generic phrase "comprehensive guide"
- Just lists what the post covers (title restatement)
- No hook, no problem statement
- Doesn't explain WHY you need this

### ✓ AFTER (3 paragraphs, ~85 words)
```markdown
Managing dotfiles across multiple machines becomes painful when configurations diverge. A laptop needs different monitor settings than a desktop. A work machine requires different SSH configs than a home server. Traditional dotfiles repos force you to either maintain separate branches (merge hell) or pollute configs with if-statements checking `$(hostname)`.

Git worktrees provide a cleaner solution: each machine gets its own branch, but you can edit any machine's config from anywhere without switching branches. A bare repo in `~/.dotfiles` tracks everything, while machine-specific worktrees in `~/dotfiles-hostname/` give you clean working copies.

This guide covers the complete setup: bare repo initialization, per-machine worktree creation, automatic deployment hooks that sync changes to your live `$HOME`, and systemd integration for seamless updates. You'll maintain separate configs without the branch-switching nightmare.
```

**Why it works**:
- P1: Establishes the pain (config drift, bad solutions)
- P2: Introduces the approach (worktrees) and why it's better
- P3: Previews what you'll learn (specific, actionable)

---

## Example 2: VirtualBox VM Management (VirtualBox VM Orchestration with a Simple Bash Script)

### ❌ BEFORE (24 words)
```markdown
A single script manages multiple VirtualBox VMs: batch start/stop operations, headless mode for servers, graceful shutdown, and systemd integration for automatic startup at boot.
```

**Issues**:
- Title restatement
- Lists features without context
- Doesn't explain the problem
- No hook for why you'd need this

### ✓ AFTER (3 paragraphs, ~95 words)
```markdown
Running a home lab with multiple VirtualBox VMs means clicking through the GUI to start five servers individually, hoping you remembered the correct boot order, and praying you didn't forget to shut them down before rebooting the host. VBoxManage exists but requires typing `VBoxManage startvm "LongVMName" --type headless` repeatedly—verbose, error-prone, and impossible to automate reliably.

A 200-line Bash script solves this: define your VMs in a simple list, run `vms start` to launch them all in parallel with progress indicators, and `vms stop` for graceful shutdowns. The script handles headless mode automatically, tracks VM states, and integrates with systemd for boot-time startup.

This post walks through the implementation: VM filtering and configuration, parallel operations with real-time progress, graceful ACPI shutdown with timeouts, and systemd service files for automatic lab startup. You'll go from GUI clicking to one-command infrastructure control.
```

**Why it works**:
- P1: Paints the pain vividly (clicking, forgetting, manual commands)
- P2: Solution is concrete (200 lines, specific commands, what it does)
- P3: Clear learning path (implementation details, end state)

---

## Example 3: nohup Usage (nohup for Background Processes: Use Cases, Tradeoffs, and Alternatives)

### ❌ BEFORE (21 words)
```markdown
Running long-lived processes that survive terminal disconnection: appropriate use cases for `nohup`, comparison with systemd, and implementation patterns for automated scripts.
```

**Issues**:
- Colon-separated list format (lazy structure)
- No context on when/why this matters
- Doesn't explain the actual problem
- Could apply to any terminal multiplexer post

### ✓ AFTER (3 paragraphs, ~90 words)
```markdown
SSH into a server, start a 12-hour training job, close your laptop—and the process dies. This happens because the shell forwards SIGHUP to child processes when the terminal disconnects. Screen and tmux solve this by maintaining persistent sessions, but they're overkill for fire-and-forget scripts that you'll never interact with again.

`nohup` is the minimal solution: immunize a process against SIGHUP, redirect output to a file, and background it with `&`. Unlike systemd services, it requires no unit files or root privileges. Unlike tmux, it doesn't maintain a session you'll never reattach to.

This post covers when nohup is appropriate (one-off automation, deployment scripts), when it's not (anything needing restart policies, monitoring, or resource limits), and how to use it correctly: output redirection, background job control, PID management, and the critical mistakes that cause silent failures.
```

**Why it works**:
- P1: Concrete scenario everyone has experienced
- P2: Positions nohup relative to alternatives (not just "what" but "why not X")
- P3: Sets clear expectations (when to use, when not to, how to avoid failures)

---

## Example 4: Rathole Tunnels (Exposing Local Services Securely with Rathole)

### ❌ BEFORE (26 words)
```markdown
This post describes a method to securely expose local services (SSH, Ollama, MCP servers) through NAT using rathole reverse tunnels, nginx WebSocket proxying, and token-based authentication.
```

**Issues**:
- "This post describes" - classic weak opening
- Technical feature list without context
- No explanation of WHY you need this
- Could be shortened to title

### ✓ AFTER (3 paragraphs, ~100 words)
```markdown
Your home server runs Ollama with a 4090, but you're on a laptop at a coffee shop. Your lab SSH server sits behind NAT with no public IP. You want remote access, but port forwarding exposes services to the internet, ngrok routes traffic through third parties who can inspect it, and WireGuard requires client-side configuration everywhere you want access.

Rathole provides a self-hosted alternative: a Rust-based reverse tunnel that multiplexes multiple services over a single WebSocket connection to your VPS. Unlike SSH's `-R` tunnels, it handles reconnection automatically, supports per-service token authentication, and hides behind nginx's TLS termination—scanners see a JSON API, legitimate clients get a tunnel.

This guide walks through the complete setup: nginx configuration for TLS and WebSocket proxying, rathole server and client configuration, systemd integration for automatic reconnection, and security hardening including token rotation, fail2ban for SSH protection, and GeoIP blocking. You'll expose SSH, Ollama, and MCP servers securely without cloud dependency.
```

**Why it works**:
- P1: Relatable scenario + failures of existing solutions
- P2: Clear positioning (what rathole does differently/better)
- P3: Comprehensive preview (not just "setup" but specific security concerns)

---

## Example 5: Tmux SSH-Aware Names (SSH Hostname Detection in Tmux Window Names)

### ❌ BEFORE (18 words)
```markdown
A technical guide to configuring tmux for automatic SSH hostname detection in window names and status bar indicators.
```

**Issues**:
- "A technical guide" - filler phrase
- Feature description, not a problem
- Doesn't explain impact/benefit
- Very generic

### ✓ AFTER (3 paragraphs, ~85 words)
```markdown
You SSH into five servers in different tmux windows, run commands, switch between them, and completely forget which window contains which host. Tab through them all, check prompts, curse quietly. Meanwhile, the tmux status bar helpfully displays "0:bash 1:bash 2:bash 3:bash"—technically accurate, completely useless.

Tmux can detect SSH connections and update window names automatically by monitoring the `SSH_CLIENT` environment variable and extracting hostnames from your shell prompt. Instead of "bash", your windows display "prod-db-01", "staging-web-02", "dev-ansible" without any manual renaming.

This post covers the implementation: escape sequence handling for window title updates, shell integration for bash/zsh/fish, tmux configuration for status bar formatting, and the critical timing issues that cause race conditions where windows briefly show "ssh" before resolving to the hostname.
```

**Why it works**:
- P1: Relatable frustration (we've all been there)
- P2: Solution is specific (how it works, what changes)
- P3: Technical depth preview (not just config, but edge cases)

---

## Example 6: Game Server Backups (Automated Backup and Update Scripts for Game Servers)

### ❌ BEFORE (27 words)
```markdown
Automated backup and update scripts for self-hosted game servers: Vintage Story and Minecraft implementations featuring retention policies, integrity checks, systemd integration, and automatic rollback on failed updates.
```

**Issues**:
- Feature list without motivation
- Doesn't explain the problem
- "Automated...scripts" is redundant
- No hook

### ✓ AFTER (3 paragraphs, ~95 words)
```markdown
Game server updates break worlds. A mod incompatibility corrupts player data. A config change causes crashes. You need to restore the backup—which you forgot to take, or took three days ago, or can't verify isn't also corrupted. Meanwhile, players are messaging you asking when the server will be back up.

Self-hosted game servers need automated backups before every update, retention policies to manage disk space, integrity verification to catch corruption, and automatic rollback when updates fail. For Minecraft and Vintage Story specifically, this means handling their world formats, respecting server-side vs. client-side mods, and avoiding backups during chunk generation.

This guide provides production-ready scripts for both servers: backup creation with compression and verification, retention policies that keep daily/weekly/monthly snapshots, systemd timers for scheduled updates, and rollback automation that detects crashes and restores the last known-good state within minutes.
```

**Why it works**:
- P1: Disaster scenario everyone fears
- P2: Lists requirements in problem context (not just features)
- P3: Concrete deliverables (scripts, policies, recovery time)

---

## Pattern Summary

### Paragraph 1 (The Hook) - 30-40 words
**Format**: `[Concrete scenario] + [Why existing solutions fail/are inadequate]`

**Examples**:
- "SSH into a server, start a job, close laptop—process dies."
- "Running a home lab with multiple VMs means clicking through the GUI..."
- "Game server updates break worlds. A mod incompatibility corrupts player data."

**Avoid**:
- "This post describes..."
- "A comprehensive guide to..."
- "In modern development..."

### Paragraph 2 (The Solution) - 35-45 words
**Format**: `[What this approach/tool does] + [Key differentiator from alternatives]`

**Examples**:
- "Rathole provides a self-hosted alternative: a Rust-based tunnel that..."
- "Git worktrees provide a cleaner solution: each machine gets its own branch..."
- "`nohup` is the minimal solution: immunize a process, redirect output, background it."

**Key elements**:
- Name the technology/approach
- One concrete technical detail
- Comparison to alternatives (unlike X, instead of Y)

### Paragraph 3 (The Preview) - 25-35 words
**Format**: `[What this post covers] + [Specific technical depth areas] + [End state/capability]`

**Examples**:
- "This guide walks through the complete setup: nginx configuration for TLS..."
- "This post covers when nohup is appropriate..., when it's not..., and how to use it correctly..."
- "You'll go from GUI clicking to one-command infrastructure control."

**Must include**:
- Specific technical topics (not "installation and usage")
- Mention of edge cases/gotchas if they exist
- Concrete capability readers gain

---

## Red Flag Phrases to Delete

| ❌ Delete | ✓ Replace with |
|-----------|-----------------|
| "This post describes" | Start with the problem directly |
| "A comprehensive guide to" | Specific technical detail |
| "In this tutorial we'll explore" | Jump straight to scenario |
| "This article will show you" | State what readers will build |
| "Here's how to..." | Explain why existing methods fail first |
| "An introduction to..." | Assume readers know basics, go deeper |
| "Learn how to..." | Describe the specific problem solved |

---

## Quick Checklist

Before publishing, verify your introduction:

- [ ] First sentence is a concrete scenario or technical problem
- [ ] No phrases containing "this post/article/guide/tutorial"
- [ ] Explains WHY existing solutions are inadequate
- [ ] Names the specific tool/technique (not generic categories)
- [ ] Compares to at least one alternative
- [ ] Lists 3+ specific technical topics covered
- [ ] Total word count: 80-110 words
- [ ] Sentence count: 5-8 sentences across 3 paragraphs
- [ ] Contains at least 3 concrete technical terms/tools/metrics
- [ ] Would make sense if you removed the title entirely
