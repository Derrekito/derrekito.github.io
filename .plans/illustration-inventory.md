# Blog Post Illustration Inventory

## Summary

| Priority | Post Count | Illustration Count |
|----------|------------|-------------------|
| HIGH     | 26         | ~95               |
| MEDIUM   | 32         | ~85               |
| LOW      | 16         | ~30               |
| **Total**| **74**     | **~210**          |

### By Illustration Type

| Type | Count | Notes |
|------|-------|-------|
| Mermaid Diagrams | ~70 | Flowcharts, architecture, state diagrams |
| Mathematical Plots | ~35 | Weibull curves, distributions, time series |
| Screenshots/Images | ~40 | UI mockups, terminal output, rendered examples |
| Terminal Output (ASCII) | ~35 | Colored output examples, command results |
| Architecture Diagrams | ~30 | System diagrams, data flow |

---

## HIGH Priority Posts

### 2025-11-16-dotfiles-worktree-workflow.md
**Priority**: HIGH
- [ ] Mermaid: Architecture overview (bare repo, worktrees, $HOME relationship)
- [ ] Mermaid: Deployment flow (commit -> hook -> rsync -> $HOME)
- [ ] Mermaid: Multi-machine sync workflow

### 2026-02-28-local-pdf-to-knowledge-graph-series.md
**Priority**: HIGH
- [ ] Mermaid: Complete pipeline architecture (convert existing ASCII)
- [ ] Image: Component icons (MinerU, Ollama, Kuzu, vis.js)

### 2026-02-28-knowledge-graph-visualization-visjs.md
**Priority**: HIGH
- [ ] Screenshot: Example vis.js visualization output
- [ ] Screenshot: Filtered subgraph example
- [ ] Image: Color/size encoding legend

### 2026-02-28-make-bash-python-tui-layered-automation.md
**Priority**: HIGH
- [ ] Mermaid: Layered architecture (convert existing ASCII)
- [ ] Mermaid: mk/ directory structure tree
- [ ] Screenshot: Python TUI example output

### 2026-03-15-executable-notebooks-series.md
**Priority**: HIGH
- [ ] Mermaid: Pipeline architecture (convert existing ASCII)
- [ ] Image: Comparison table with Jupyter

### 2026-03-22-executable-markdown-notebooks.md
**Priority**: HIGH
- [ ] Mermaid: Processing stages (Markdown -> Python -> Pandoc -> LaTeX -> PDF)
- [ ] Mermaid: Code block modifier decision tree
- [ ] Screenshot: Example PDF output with tcolorbox styling
- [ ] Mermaid: Dynamic includes flow

### 2026-03-29-custom-pandoc-filters.md
**Priority**: HIGH
- [ ] Mermaid: Filter chain architecture showing AST transformation sequence
- [ ] Mermaid: Pandoc pipeline (input.md -> filters -> output.pdf)
- [ ] Screenshot: Mermaid diagram rendered in PDF vs raw code block

### 2026-04-12-latex-tcolorbox-environments.md
**Priority**: HIGH
- [ ] Screenshot: Each box type rendered (resultbox, passbox, warningbox, failbox, infobox)
- [ ] Image: Color swatch showing all 7 box color schemes
- [ ] Screenshot: Before/after - hardcoded LaTeX vs Python helper

### 2026-05-03-discord-bot-ml-training-monitor.md
**Priority**: HIGH
- [ ] Mermaid: Architecture (Mobile -> VPS -> SSH -> Training machines)
- [ ] Screenshot: Discord embed showing machine status
- [ ] Screenshot: /status command output with GPU metrics

### 2026-05-10-rathole-secure-tunnels-mcp.md
**Priority**: HIGH
- [ ] Mermaid: Client-Server-VPS data flow with ports labeled
- [ ] Mermaid: nginx WebSocket proxy path vs decoy response
- [ ] Mermaid: Connection establishment through NAT

### 2026-05-24-vps-security-hardening-monitoring.md
**Priority**: HIGH
- [ ] Mermaid: Security stack layers (Prevent/Detect/Respond)
- [ ] Terminal: security-report output with colored sections
- [ ] Image: sysctl settings with attack mitigation mapping

### 2026-07-12-local-dev-dashboard-python.md
**Priority**: HIGH
- [ ] Screenshot: Dashboard web UI with dark theme
- [ ] Screenshot: Service cards showing running/stopped status
- [ ] Mermaid: Dashboard polling architecture

### 2026-07-19-caddy-local-dns-dev-environment.md
**Priority**: HIGH
- [ ] Mermaid: Request flow (device -> DNS -> Caddy -> service)
- [ ] Mermaid: Domain resolution process (.localhost vs .lan paths)
- [ ] Terminal: dig output example
- [ ] Terminal: caddy validate output

### 2026-07-26-unified-local-dev-environment.md
**Priority**: HIGH
- [ ] Mermaid: Network topology (convert existing ASCII)
- [ ] Mermaid: "Adding a New Project" workflow
- [ ] Screenshot: Services dashboard mockup
- [ ] Terminal: dig verification output

### 2026-09-27-curses-tui-gpu-seu-monitoring.md
**Priority**: HIGH
- [ ] Screenshot: Enhanced TUI interface mockup
- [ ] Mermaid: Data flow (nvidia-smi -> parser -> queue -> renderer)
- [ ] Terminal: nvidia-smi -q output
- [ ] Terminal: ECC error detection example

### 2026-10-11-stochastic-simulation-python-labs-series.md
**Priority**: HIGH
- [ ] Mermaid: Course structure diagram
- [ ] Plot: Monte Carlo integration visualization
- [ ] Plot: Markov chain state transition
- [ ] Plot: Brownian motion paths
- [ ] Mermaid: Lab dependency graph

### 2026-10-25-docker-latex-reproducible-builds.md
**Priority**: HIGH
- [ ] Mermaid: Docker layer diagram (build cache)
- [ ] Mermaid: Complete toolchain architecture
- [ ] Terminal: docker run latexmk output
- [ ] Mermaid: CI/CD pipeline (GitHub Actions)

### 2026-12-13-ichimoku-cloud-trading-bot-coinbase.md
**Priority**: HIGH
- [ ] Mermaid: System architecture (convert existing ASCII)
- [ ] Plot: Ichimoku Cloud with all 5 components
- [ ] Plot: Price chart with cloud, bullish/bearish signals
- [ ] Mermaid: Order execution sequence

### 2026-12-27-electron-remote-command-gui.md
**Priority**: HIGH
- [ ] Screenshot: Application UI mockup
- [ ] Mermaid: Electron process architecture (convert ASCII)
- [ ] Mermaid: Command execution sequence
- [ ] Terminal: ANSI-colored log output

### 2027-01-10-naive-weibull-curve-fit-seu-cross-section.md
**Priority**: HIGH
- [ ] Plot: Weibull function with parameter annotations
- [ ] Plot: Cross-section vs LET with confidence bands
- [ ] Plot: Bootstrap parameter distributions (4-panel)
- [ ] Plot: Poisson vs Gaussian CI comparison
- [ ] Mermaid: Fitting workflow

### 2027-01-17-c-singly-linked-list-implementation.md
**Priority**: HIGH
- [ ] Mermaid: Node structure memory layout
- [ ] Mermaid: Linked list operations (prepend, append)
- [ ] Mermaid: Pointer-to-pointer indirection
- [ ] Mermaid: Memory leak vs proper cleanup

### 2027-02-14-event-driven-trading-nats-jetstream.md
**Priority**: HIGH
- [ ] Mermaid: NATS JetStream cluster architecture (convert ASCII)
- [ ] Mermaid: Subject hierarchy tree
- [ ] Mermaid: Publish -> Consumer -> Ack sequence
- [ ] Mermaid: Stream separation strategy

### 2027-02-21-polyglot-persistence-trading-systems.md
**Priority**: HIGH
- [ ] Mermaid: Data flow architecture (convert ASCII)
- [ ] Mermaid: Query pattern decision tree (convert ASCII)
- [ ] Mermaid: Eventual consistency write order
- [ ] Mermaid: Redis order book structure

### 2027-03-14-websocket-market-data-pipeline.md
**Priority**: HIGH
- [ ] Mermaid: WebSocket connection state machine
- [ ] Mermaid: Message processing pipeline
- [ ] Mermaid: Exponential backoff with jitter
- [ ] Mermaid: Circuit breaker states
- [ ] Mermaid: Gap detection/recovery sequence

### 2027-04-04-ohlcv-aggregation-etl-pipelines.md
**Priority**: HIGH
- [ ] Mermaid: Tick-to-bar aggregation pipeline
- [ ] Mermaid: Timeframe hierarchy tree
- [ ] Mermaid: Hierarchical bar builder cascade
- [ ] Mermaid: MongoDB to DuckDB ETL
- [ ] Terminal: DuckDB query output
- [ ] Plot: OHLCV bar construction with tick overlay

### 2027-04-25-bayesian-market-regime-detection.md
**Priority**: HIGH
- [ ] Mermaid: Regime state transitions with probabilities
- [ ] Plot: Fuzzy membership functions
- [ ] Plot: Transition probability heatmap
- [ ] Plot: Regime probability evolution (stacked area)
- [ ] Plot: Model agreement gauge
- [ ] Plot: Confidence history
- [ ] Mermaid: Ensemble detection pipeline

### 2027-05-02-monte-carlo-risk-analysis-trading.md
**Priority**: HIGH
- [ ] Plot: Loss distribution with VaR/CVaR markers
- [ ] Plot: Price path fan chart
- [ ] Plot: Heston stochastic volatility paths
- [ ] Plot: Bootstrap Sharpe ratio distribution
- [ ] Mermaid: Monte Carlo methodology
- [ ] Table: Risk metric interpretation guide

### 2027-05-16-seu-cross-section-manifesto-vibe-fitting.md
**Priority**: HIGH
- [ ] Mermaid: Method selection decision tree (5 decisions)
- [ ] Mermaid: Complete validation pipeline
- [ ] Plot: 4-parameter Weibull curve example
- [ ] Table: Overdispersion interpretation
- [ ] Table: Sample size adequacy

### 2027-06-13-seu-cross-section-zero-events.md
**Priority**: HIGH
- [ ] Plot: Weibull fit with upper limit arrows
- [ ] Plot: Poisson upper limit derivation
- [ ] Mermaid: Zero-event handling workflow
- [ ] Table: Confidence level upper limit factors

### 2027-07-04-seu-cross-section-validation-pipeline.md
**Priority**: HIGH
- [ ] Mermaid: 9-check validation pipeline
- [ ] Screenshot: Validation report template
- [ ] Mermaid: Status indicator system
- [ ] Terminal: Complete validation report example

---

## MEDIUM Priority Posts

### 2025-06-22-ArchInstallEncrypt.md
**Priority**: MEDIUM
- [ ] Mermaid: Partition layout visual
- [ ] Mermaid: Boot process flow
- [ ] Mermaid: Encryption layer (LUKS structure)

### 2026-02-28-pdf-extraction-mineru.md
**Priority**: MEDIUM
- [ ] Screenshot: Before/after (PDF vs markdown output)
- [ ] Mermaid: Layout detection regions

### 2026-02-28-structured-llm-extraction-instructor.md
**Priority**: MEDIUM
- [ ] Mermaid: Schema enforcement flow (LLM -> Instructor -> validation)
- [ ] Mermaid: Chunking strategies comparison

### 2026-02-28-knowledge-graph-kuzu.md
**Priority**: MEDIUM
- [ ] Mermaid: Entity resolution flow
- [ ] Mermaid: Graph schema

### 2026-02-28-rag-knowledge-graphs.md
**Priority**: MEDIUM
- [ ] Mermaid: Vector RAG vs Graph RAG
- [ ] Mermaid: Query expansion flow

### 2026-02-28-neovim-cheatsheet-telescope.md
**Priority**: MEDIUM
- [ ] Screenshot: Telescope picker with categories
- [ ] Screenshot: Drill-down view
- [ ] Mermaid: Plugin file structure

### 2026-04-05-precommit-validation-technical-docs.md
**Priority**: MEDIUM
- [ ] Mermaid: Validation pipeline
- [ ] Terminal: PASS/FAIL colored output
- [ ] Mermaid: Git hook integration

### 2026-04-19-docker-compose-makefile-management.md
**Priority**: MEDIUM
- [ ] Terminal: Colored help menu
- [ ] Mermaid: Directory structure
- [ ] Mermaid: Environment switching

### 2026-05-17-automated-token-rotation-rathole.md
**Priority**: MEDIUM
- [ ] Mermaid: Rotation timeline
- [ ] Mermaid: Pull-based rotation loop
- [ ] Mermaid: Sync sequence

### 2026-05-31-vps-self-pentest-script.md
**Priority**: MEDIUM
- [ ] Terminal: Pentest output with colors
- [ ] Image: Test coverage matrix
- [ ] Mermaid: CI/CD integration

### 2026-06-07-reproducible-vps-deployment-bash.md
**Priority**: MEDIUM
- [ ] Mermaid: Bundle directory structure
- [ ] Mermaid: deploy.sh sequence
- [ ] Mermaid: Age encryption flow

### 2026-06-28-game-server-backup-update-rollback.md
**Priority**: MEDIUM
- [ ] Mermaid: Update process with rollback
- [ ] Mermaid: Backup retention rotation
- [ ] Terminal: Update script output

### 2026-07-26-non-blocking-bash-tui-ddc-monitor.md
**Priority**: MEDIUM
- [ ] Screenshot: TUI interface mockup
- [ ] Mermaid: Background worker flow
- [ ] Terminal: ddcutil detect output
- [ ] Terminal: ddcutil getvcp output

### 2026-08-02-tmux-osc52-clipboard-ssh.md
**Priority**: MEDIUM
- [ ] Mermaid: OSC 52 flow (tmux -> SSH -> terminal -> clipboard)
- [ ] Terminal: OSC 52 test verification
- [ ] Mermaid: Copy operation pipeline

### 2026-08-30-story-arc-templates-technical-presentations.md
**Priority**: MEDIUM
- [ ] Plot: Hero's Journey arc (fortune vs time)
- [ ] Plot: Man in a Hole arc
- [ ] Mermaid: Story beats to slide types timeline

### 2026-09-06-conditional-tikz-decorations-content-height.md
**Priority**: MEDIUM
- [ ] Image: Short vs tall code blocks comparison
- [ ] Mermaid: Conditional decoration logic
- [ ] Image: Blob decorations on code blocks

### 2026-09-13-monogatari-scene-slides-beamer.md
**Priority**: MEDIUM
- [ ] Image: Primary palette swatches
- [ ] Image: Melancholy palette swatches
- [ ] Screenshot: Rendered scene slides

### 2026-09-20-gogyo-five-elements-palette-generator.md
**Priority**: MEDIUM
- [ ] Mermaid: Five Elements cycle (circular)
- [ ] Image: Element color swatches
- [ ] Terminal: Palette generation output
- [ ] Plot: Hue wheel with element assignments

### 2026-10-04-bare-repo-dotfiles-bootstrap.md
**Priority**: MEDIUM
- [ ] Mermaid: Bootstrap process flowchart
- [ ] Mermaid: Bare repository architecture
- [ ] Terminal: dotfiles status output
- [ ] Mermaid: Branch-per-machine strategy

### 2026-10-18-cac-piv-smartcard-arch-linux.md
**Priority**: MEDIUM
- [ ] Mermaid: PKCS#11 architecture stack
- [ ] Terminal: pcsc_scan output
- [ ] Terminal: pkcs11-tool output
- [ ] Mermaid: Certificate trust chain

### 2026-11-22-pandoc-filter-minted-syntax-highlighting.md
**Priority**: MEDIUM
- [ ] Mermaid: Pandoc filter pipeline
- [ ] Image: Highlighting quality comparison
- [ ] Terminal: JSON AST structure
- [ ] Mermaid: Filter function logic

### 2026-11-29-svg-to-tikz-batch-conversion.md
**Priority**: MEDIUM
- [ ] Image: SVG vs TikZ rendering comparison
- [ ] Mermaid: Conversion workflow
- [ ] Terminal: Batch conversion output
- [ ] Image: Before/after diagram

### 2026-12-20-docker-yocto-poky-build-environment.md
**Priority**: MEDIUM
- [ ] Mermaid: Docker layer architecture
- [ ] Mermaid: Volume mounting structure
- [ ] Terminal: Build output with timing
- [ ] Terminal: docker run command

### 2027-01-03-latex-printable-test-data-booklets.md
**Priority**: MEDIUM
- [ ] Image: Sample booklet page layout
- [ ] Mermaid: Imposition mathematics
- [ ] Image: Folding/assembly diagram
- [ ] Image: Cover page example

### 2027-01-31-yoctoforge-declarative-embedded-linux-builds.md
**Priority**: MEDIUM
- [ ] Mermaid: Bootstrap workflow
- [ ] Mermaid: Workspace directory structure
- [ ] Mermaid: Branch-per-project strategy
- [ ] Terminal: make build output

### 2027-02-07-cac-smartcard-multi-distro-linux.md
**Priority**: MEDIUM
- [ ] Mermaid: CAC setup workflow (convert ASCII)
- [ ] Mermaid: Distribution detection pattern
- [ ] Terminal: pcsc_scan with card
- [ ] Terminal: certutil -L output

### 2027-02-28-docker-compose-trading-infrastructure.md
**Priority**: MEDIUM
- [ ] Mermaid: Multi-network architecture
- [ ] Mermaid: Service dependency graph
- [ ] Mermaid: Secrets management flow
- [ ] Mermaid: Dev vs Prod profiles

### 2027-02-28-pandoc-latex-manual-pipeline.md
**Priority**: MEDIUM
- [ ] Mermaid: Pipeline architecture
- [ ] Mermaid: Filter chain execution
- [ ] Mermaid: Makefile.include integration
- [ ] Image: Mermaid diagram in PDF

### 2027-03-07-linux-standard-streams-redirection.md
**Priority**: MEDIUM
- [ ] Mermaid: File descriptor relationships
- [ ] Mermaid: Redirection operator effects
- [ ] Mermaid: tee splitting flow
- [ ] Terminal: Correct vs incorrect redirection

### 2027-03-14-git-perfect-commit-workflow.md
**Priority**: MEDIUM
- [ ] Mermaid: Pre-commit verification checklist
- [ ] Mermaid: Branch lifecycle
- [ ] Terminal: git add -p example
- [ ] Mermaid: Rebase vs Merge comparison

### 2027-03-21-rest-api-caching-market-data.md
**Priority**: MEDIUM
- [ ] Mermaid: API endpoint hierarchy
- [ ] Mermaid: Cache key/TTL decision flow
- [ ] Mermaid: Request flow (hit vs miss)
- [ ] Terminal: Redis cache stats
- [ ] ASCII: Token bucket visualization

### 2027-04-11-technical-indicator-framework-design.md
**Priority**: MEDIUM
- [ ] Mermaid: Indicator class hierarchy
- [ ] Mermaid: Warmup period cascade (MACD)
- [ ] Plot: SMA vs EMA response
- [ ] Plot: RSI with zones
- [ ] Terminal: Benchmark results
- [ ] Table: Indicator category overview

### 2027-05-09-production-trading-system-lessons.md
**Priority**: MEDIUM
- [ ] Mermaid: Alert severity triage
- [ ] Mermaid: WebSocket reconnection sequence
- [ ] Terminal: Structured logging (JSON)
- [ ] Terminal: py-spy profiling
- [ ] Mermaid: Blue-green deployment
- [ ] ASCII: Incident retrospective timeline

### 2027-05-23-seu-cross-section-mle-weibull.md
**Priority**: MEDIUM
- [ ] Plot: Poisson vs Gaussian CI comparison
- [ ] Plot: Weibull curve with parameter labels
- [ ] Mermaid: MLE variant selection
- [ ] Plot: Log-likelihood surface
- [ ] Table: Physical parameter bounds

### 2027-05-30-seu-cross-section-bootstrap-uncertainty.md
**Priority**: MEDIUM
- [ ] Mermaid: Bootstrap algorithm steps
- [ ] Plot: Bootstrap distributions (4 panels)
- [ ] Plot: Correlation matrix heatmap
- [ ] Plot: Hessian vs Bootstrap SE comparison
- [ ] Table: Bootstrap success rate interpretation

### 2027-06-06-seu-cross-section-confidence-intervals.md
**Priority**: MEDIUM
- [ ] Plot: Bootstrap distribution with percentile vs BCA
- [ ] Mermaid: CI method selection
- [ ] Plot: Coverage probability comparison
- [ ] Plot: Asymmetric CI visualization
- [ ] Table: First vs second-order accuracy

### 2027-06-20-seu-cross-section-deviance-test.md
**Priority**: MEDIUM
- [ ] Plot: Pearson residuals vs LET
- [ ] Plot: Observed vs predicted counts
- [ ] Mermaid: Model failure investigation
- [ ] Table: Residual pattern interpretation
- [ ] Table: DoF requirements

### 2027-06-27-seu-cross-section-parameter-validation.md
**Priority**: MEDIUM
- [ ] Plot: Parameter validation ranges
- [ ] Plot: S-W correlation scatter
- [ ] Plot: Rate sensitivity to LET_th
- [ ] Table: Validation checklist
- [ ] Table: Technology node ranges

---

## LOW Priority Posts

### 2025-06-22-Nvidia.md
**Priority**: LOW
- [ ] Mermaid: Driver architecture

### 2025-06-22-realtek.md
**Priority**: LOW
- [ ] Mermaid: Driver loading sequence

### 2026-02-28-automated-pdf-pipeline-watchdog.md
**Priority**: LOW
- [ ] Mermaid: Watchdog event flow
- [ ] Mermaid: Batch processing state machine

### 2026-06-14-modular-docker-compose-makefile.md
**Priority**: LOW
- [ ] Terminal: make help-full output
- [ ] Mermaid: mk/ module structure
- [ ] Table: nohup vs systemd comparison

### 2026-06-21-virtualbox-vm-orchestration-script.md
**Priority**: LOW
- [ ] Terminal: vm_manage.sh status output
- [ ] Mermaid: systemd integration
- [ ] Mermaid: VM filter pattern matching

### 2026-07-05-nohup-background-processes-automation.md
**Priority**: LOW
- [ ] Mermaid: SIGHUP propagation
- [ ] Mermaid: nohup vs systemd decision tree
- [ ] Mermaid: Process detachment

### 2026-08-09-tmux-ssh-aware-window-names.md
**Priority**: LOW
- [ ] Screenshot: tmux status bar (before/after)
- [ ] Terminal: Escape sequence example
- [ ] Mermaid: automatic-rename-format logic

### 2026-08-16-tmux-modal-help-system.md
**Priority**: LOW
- [ ] Screenshot: Help popup overlay
- [ ] Mermaid: Mode detection routing

### 2026-08-23-tmux-vim-style-pane-window-management.md
**Priority**: LOW
- [ ] Mermaid: swap-pane sequence
- [ ] Terminal: display-message feedback

### 2026-11-01-dmenu-searchable-keybinding-cheatsheets.md
**Priority**: LOW
- [ ] Screenshot: dmenu category selection
- [ ] Mermaid: Data flow (heredoc -> dmenu)
- [ ] Terminal: Color-themed dmenu

### 2026-11-15-dmenu-cheatsheet-framework-any-domain.md
**Priority**: LOW
- [ ] Mermaid: Framework generalization
- [ ] Terminal: Yocto cheatsheet output
- [ ] Mermaid: Integration patterns

### 2026-12-06-ssh-hardening-drop-in-config.md
**Priority**: LOW
- [ ] Mermaid: Configuration precedence
- [ ] Terminal: sshd -T output
- [ ] Terminal: Auth failure logs

### 2027-01-24-ieee-latex-template-modern-tooling.md
**Priority**: LOW
- [ ] Mermaid: Build workflow
- [ ] Image: Microtype before/after
- [ ] Terminal: minted rendering

### 2027-02-14-nvidia-smi-mqtt-gpu-telemetry.md
**Priority**: LOW
- [ ] Mermaid: Data flow
- [ ] Terminal: nvidia-smi output
- [ ] Terminal: JSON payload

### 2027-02-21-liblog-lightweight-cpp-logging.md
**Priority**: LOW
- [ ] Terminal: Colored log output
- [ ] Mermaid: Compile-time filtering
- [ ] Mermaid: LogStatement RAII lifecycle

---

## Implementation Notes

### Mermaid Diagrams
- Can be embedded directly in markdown with ```mermaid blocks
- Jekyll/Chirpy theme may need mermaid.js enabled
- Convert existing ASCII diagrams to Mermaid

### Mathematical Plots
- Generate with Python (matplotlib/seaborn)
- Save as SVG or PNG to assets/img/posts/
- SEU and trading posts need the most plots

### Screenshots/Terminal Output
- Terminal: Consider using carbon.now.sh or similar
- TUI mockups: Can be ASCII art in code blocks
- Real screenshots for GUI applications

### Priority Order for Implementation
1. HIGH priority posts with existing ASCII diagrams (quick wins)
2. HIGH priority posts needing plots (SEU, trading)
3. MEDIUM priority posts
4. LOW priority as time permits
