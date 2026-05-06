---
title: "Your Post Title Here"
date: YYYY-MM-DD
categories: [Category1, Category2]
tags: [tag1, tag2, tag3, tag4]
---

[PARAGRAPH 1 - THE HOOK - 30-40 words]
[Concrete scenario that readers will relate to] + [Why existing solutions fail or are inadequate]. 
[The pain point must be specific and technical, not abstract.]

[Examples:
- "You SSH into five servers, run commands, forget which window is which."
- "Game server updates break worlds. Mod incompatibility corrupts player data."
- "Managing dotfiles across machines means either merge hell or hostname checks everywhere."
]

[PARAGRAPH 2 - THE SOLUTION - 35-45 words]
[Name the specific tool/approach you're covering]. [Explain what it does]. [Key differentiator: 
"Unlike X...", "Instead of Y...", "Compared to Z..."].

[Examples:
- "Rathole provides a self-hosted alternative: multiplexes services over one WebSocket, handles reconnection automatically."
- "Git worktrees provide a cleaner solution: each machine gets its own branch without switching."
- "nohup is the minimal solution: immunize a process, redirect output, no unit files needed."
]

[PARAGRAPH 3 - THE PREVIEW - 25-35 words]
This [post/guide] covers [specific topic 1], [specific topic 2], and [specific topic 3]. [Mention 
one key gotcha or edge case if relevant]. [End with concrete capability readers will gain].

[Examples:
- "This guide covers nginx TLS configuration, systemd integration, and token rotation. You'll expose SSH and Ollama without cloud dependency."
- "You'll learn when nohup is appropriate, when it's not, and critical mistakes that cause silent failures."
- "This post walks through VM filtering, parallel operations, ACPI shutdown with timeouts, and systemd integration. One-command infrastructure control."
]

## [First Major Section]

[Content starts here]

---

# INTRODUCTION CHECKLIST (DELETE THIS SECTION BEFORE PUBLISHING)

Before publishing, verify your introduction passes these checks:

## Structure
- [ ] Three distinct paragraphs (separated by blank lines)
- [ ] Paragraph 1 is 30-40 words
- [ ] Paragraph 2 is 35-45 words  
- [ ] Paragraph 3 is 25-35 words
- [ ] Total introduction: 80-110 words

## Content - Paragraph 1 (The Hook)
- [ ] Starts with concrete scenario, NOT abstract description
- [ ] Mentions a specific pain point readers will recognize
- [ ] Explains why existing solutions fail/are inadequate
- [ ] NO phrases like "this post", "in this article", "here's how to"
- [ ] NO title restatement

## Content - Paragraph 2 (The Solution)
- [ ] Names the specific tool/technology/approach
- [ ] Explains what it does (one technical detail)
- [ ] Compares to at least one alternative ("Unlike X", "Instead of Y")
- [ ] Makes clear why this approach is better/different

## Content - Paragraph 3 (The Preview)
- [ ] Lists 3+ specific technical topics covered
- [ ] NOT vague phrases like "installation and usage"
- [ ] YES specific like "nginx TLS config, systemd timers, token rotation"
- [ ] Mentions edge cases or gotchas if they exist
- [ ] Ends with concrete capability readers will gain

## Quality Checks
- [ ] Contains at least 3 concrete technical terms/tools/metrics
- [ ] NO generic phrases: "comprehensive guide", "in this tutorial", "learn how to"
- [ ] First sentence would hook a reader even without the title
- [ ] Introduction makes sense if you completely removed the title
- [ ] Includes at least one comparison to alternatives
- [ ] Includes at least one metric/number/specific detail

## Analysis Tool
Run before publishing:
```bash
./tools/rewrite-introduction.sh _posts/your-post.md
```

Target score: 80+

## Common Mistakes to Avoid

❌ "This post describes setting up X"
✓ Start with the problem: "Setting up X fails when Y..."

❌ "A comprehensive guide to managing dotfiles"
✓ Start with the pain: "Managing dotfiles across machines means..."

❌ "In this tutorial we'll explore nohup"
✓ Start with the scenario: "SSH into a server, start a job, close laptop—process dies"

❌ "Learn how to configure tmux"  
✓ Start with the frustration: "You SSH into five servers, forget which window is which"

❌ "Here's how to automate game server backups"
✓ Start with the disaster: "Game server updates break worlds. You need the backup you forgot to take"

## Red Flag Phrases (If These Appear, Rewrite)
- "This post describes"
- "A comprehensive guide"
- "In this tutorial"
- "Learn how to"
- "Here's how to"
- "An introduction to"
- "This article will show you"
- "We'll explore"

## Good Opening Patterns

**Pattern 1: Disaster Scenario**
"[Thing breaks]. [Consequence]. [What you need but don't have]."
Example: "Game updates break worlds. Players ask when it's back. You need the backup you forgot to take."

**Pattern 2: Repetitive Pain**
"[Action] means [tedious repetition], hoping [thing you forgot], and [frustrating consequence]."
Example: "Running a lab means clicking through GUI for five servers, hoping you remembered boot order, praying you didn't forget to shut down."

**Pattern 3: Terminal Disconnect**  
"[Action], [action], close/disconnect—and [what breaks]."
Example: "SSH in, start 12-hour job, close laptop—process dies."

**Pattern 4: Multi-Machine Drift**
"[Task] across machines means [specific config difference]. [Another difference]. [Third difference]. [How people cope badly]."
Example: "Dotfiles across machines means laptop needs different monitors. Work needs different SSH. Home needs different keys. People use hostname if-statements everywhere."

**Pattern 5: Navigation Confusion**
"[Do thing in multiple places], [try to find right one], [frustrated action], [useless info shown]."
Example: "SSH into five servers, forget which window is which, tab through all, status bar shows 'bash bash bash bash'."

---

# EXAMPLE POST (Following This Template)

Here's a complete example following the template:

---
title: "Automated Certificate Renewal with Let's Encrypt and Systemd Timers"
date: 2026-04-27
categories: [Security, Automation]
tags: [lets-encrypt, certbot, systemd, timers, automation, nginx]
---

Production TLS certificates expire. Midnight comes, certbot hasn't run, and your site serves warnings to every visitor until you wake up and fix it. Cron jobs work but fail silently, lack logging integration, and don't handle dependencies like "stop nginx before renewal, restart after." Manual renewal with calendar reminders scales to one server, maybe two.

Systemd timers provide declarative certificate management: certbot runs on a schedule with automatic retry on failure, journal logs every attempt, and pre/post renewal hooks ensure nginx reloads without dropping connections. Unlike cron, failed timers show up in `systemctl status`, and `OnCalendar` scheduling uses human-readable syntax instead of cron's arcane notation.

This guide covers certbot integration with systemd timers, pre/post renewal hooks for zero-downtime nginx reloads, certificate deployment to multiple vhosts, renewal verification testing with staging certs, and monitoring setup that alerts when renewal fails. You'll move from manual certificate babysitting to automated renewals with failure visibility.

## Certificate Lifecycle Management

[Rest of post content...]
