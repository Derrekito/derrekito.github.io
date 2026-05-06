# Blog Improvement Action Plan

Prioritized list of posts needing improvements, sorted by impact.

---

## Status Summary

### Introductions ✅ MOSTLY DONE
- **Improved**: 7 posts (dotfiles, virtualbox, nohup, rathole, game-server, tmux-ssh, executable-notebooks)
- **Remaining**: 3-4 posts with weak intros (all others are 60+ words)
- **Tools created**: Analysis script, templates, examples

### Other Issues 🔄 IN PROGRESS
- **Code context needed**: 80+ posts
- **Examples missing**: 60+ posts
- **Conclusions missing**: 40+ posts

---

## Phase 2: High-Impact Improvements (NEXT)

### Priority 1: Posts Needing Introduction + Multiple Fixes

These posts have weak intros AND other quality issues. Fix them comprehensively:

| Post | Intro Score | Issues | Effort |
|------|-------------|--------|--------|
| 2026-04-22-local-dev-dashboard-python.md | Low | intro, no examples, no conclusion | 45min |
| 2026-04-10-modular-docker-compose-makefile.md | 21w | intro, no examples | 30min |
| 2026-04-25-caddy-local-dns-dev-environment.md | 20w | intro, no examples | 30min |
| 2026-05-04-tmux-osc52-clipboard-ssh.md | 23w | intro, no examples | 30min |
| 2026-03-04-custom-pandoc-filters.md | 20w | intro, long code blocks | 40min |
| 2026-03-05-precommit-validation-technical-docs.md | 23w | intro, no examples | 30min |

**Total**: 6 posts, ~4 hours

### Priority 2: High-Traffic Posts Needing Code Context

These have OK intros but lots of consecutive code blocks:

| Post | Code Blocks | Consecutive Blocks | Effort |
|------|-------------|--------------------| -------|
| 2026-02-22-pdf-extraction-mineru.md | 30 | Many | 30min |
| 2026-02-23-structured-llm-extraction-instructor.md | 48 | Many | 45min |
| 2026-02-24-knowledge-graph-kuzu.md | 36 | Many | 35min |
| 2026-03-26-rathole-secure-tunnels-mcp.md | 52 | Many | 40min |
| 2026-08-03-rest-api-caching-market-data.md | 34 | Many | 35min |

**Total**: 5 posts, ~3 hours

### Priority 3: Series Posts Needing Examples Sections

Series posts should be comprehensive:

| Post | Series | Missing | Effort |
|------|--------|---------|--------|
| 2026-02-22-pdf-extraction-mineru.md | PDF→KG Part 1 | Examples | 20min |
| 2026-02-23-structured-llm-extraction-instructor.md | PDF→KG Part 2 | Examples | 25min |
| 2026-02-24-knowledge-graph-kuzu.md | PDF→KG Part 3 | Examples | 20min |
| 2026-02-25-automated-pdf-pipeline-watchdog.md | PDF→KG Part 4 | Examples | 20min |
| 2026-02-26-knowledge-graph-visualization-visjs.md | PDF→KG Part 5 | Examples | 20min |
| 2026-02-27-rag-knowledge-graphs.md | PDF→KG Part 6 | Examples, conclusion | 25min |

**Total**: 6 posts, ~2.5 hours

---

## Recommended Week 1 Plan (10 hours)

### Day 1-2: Fix Priority 1 Posts (4 hours)
Comprehensive improvements to 6 posts with multiple issues.

**Template to follow**:
1. Rewrite introduction (3 paragraphs, 80-110 words)
2. Add context between code blocks (2-3 sentences each)
3. Add Examples section (3-5 use cases)
4. Add Conclusion (if >800 words)

**Start with**: `2026-04-22-local-dev-dashboard-python.md` (demonstrate full process)

### Day 3-4: Add Code Context to Priority 2 (3 hours)
Focus on adding 2-3 sentences between consecutive code blocks.

**Template**:
- Before block: "The next function handles X by Y"
- After block: "This returns Z, which will be used for W"

### Day 5: Add Examples to Series Posts (3 hours)
PDF→KG series should be comprehensive with examples.

**Template**:
```markdown
## Examples

### Example 1: Processing a Research Paper

Given a PDF with tables and equations:

```bash
python extract.py paper.pdf
```

Output shows extracted text with preserved structure...

### Example 2: [Another use case]
...
```

---

## Week 2+ (Lower Priority)

### Add Conclusions to Long Posts
40+ posts >800 words missing conclusions.

**Effort**: 10-15 min each = ~10 hours total

**Template**:
```markdown
## Conclusion

[Summary of approach in 1-2 sentences]

Key insights:
- [Technical insight with specific detail]
- [When to use this vs alternatives]
- [Main tradeoff to be aware of]

[Capability statement: what readers can now do]
```

### Add Next Steps Sections
50+ posts missing related content links.

**Effort**: 10 min each = ~8 hours total

### Break Up Long Code Blocks
20+ posts with 100+ line code blocks.

**Effort**: 20-30 min each = ~10 hours total

---

## Quick Wins (Do Anytime)

### 5-Minute Fixes
- Add language tags to code blocks: `for f in _posts/*.md; do sed -i 's/^```$/```bash/g' "$f"; done`
- Fix generic headings: "## Setup" → "## Server Setup: nginx Configuration"

### 15-Minute Fixes
- Add troubleshooting section to setup posts
- Add comparison table to posts discussing alternatives

---

## Tracking Progress

Create a simple tracking file:

```bash
# tools/improvement-progress.md

## Week 1 Progress

### Day 1
- [x] 2026-04-22-local-dev-dashboard-python.md (intro, examples, conclusion, code context)
- [x] 2026-04-10-modular-docker-compose-makefile.md (intro, examples)

### Day 2
- [ ] 2026-04-25-caddy-local-dns-dev-environment.md
- [ ] 2026-05-04-tmux-osc52-clipboard-ssh.md
...
```

---

## Measurement

### Before (Baseline - Current State)
- Posts with strong intros (80+ score): ~80/120 (67%)
- Posts with code context: ~40/120 (33%)
- Posts with examples sections: ~40/120 (33%)
- Posts with conclusions: ~60/120 (50%)

### After Week 1 (Target)
- Posts with strong intros: ~95/120 (79%) [+15 posts]
- Posts with code context: ~50/120 (42%) [+10 posts]
- Posts with examples sections: ~56/120 (47%) [+16 posts]
- Posts with conclusions: ~65/120 (54%) [+5 posts]

### After Phase 2 Complete (Target)
- Posts with strong intros: 115/120 (96%)
- Posts with code context: 100/120 (83%)
- Posts with examples sections: 90/120 (75%)
- Posts with conclusions: 110/120 (92%)

---

## Commands for Batch Analysis

### Find all posts missing specific improvements

```bash
# Posts missing conclusions (>800 words)
for f in _posts/*.md; do
    words=$(awk '/^---$/,/^---$/{next} {print}' "$f" | wc -w)
    has_conclusion=$(grep -qi "^## \(conclusion\|summary\)" "$f" && echo 1 || echo 0)
    [ $words -gt 800 ] && [ $has_conclusion -eq 0 ] && \
        echo "$(basename $f): $words words, no conclusion"
done

# Posts with many code blocks but no examples
for f in _posts/*.md; do
    blocks=$(grep -c '^```' "$f")
    has_examples=$(grep -qi "^## \(example\|usage\)" "$f" && echo 1 || echo 0)
    [ $blocks -gt 8 ] && [ $has_examples -eq 0 ] && \
        echo "$(basename $f): $blocks blocks, no examples"
done

# Posts with weak introductions
for f in _posts/*.md; do
    score=$(./tools/rewrite-introduction.sh "$f" 2>/dev/null | \
        grep "Score:" | grep -oP '\d+' | head -1)
    [ "${score:-0}" -lt 70 ] 2>/dev/null && \
        echo "$(basename $f): score $score"
done | sort -t':' -k2 -n

# Posts with very long code blocks
for f in _posts/*.md; do
    longest=$(awk '/^```/{flag=!flag; if(!flag && count>100) print count; count=0; next} \
        flag{count++}' "$f" | sort -rn | head -1)
    [ -n "$longest" ] && \
        echo "$(basename $f): $longest lines"
done | sort -t':' -k2 -rn
```

---

## Template Workflow for Comprehensive Post Improvement

Use this workflow for each post:

### 1. Analyze Current State
```bash
# Run analysis
./tools/rewrite-introduction.sh _posts/file.md

# Check sections
grep "^##" _posts/file.md

# Count code blocks
grep -c '^```' _posts/file.md
```

### 2. Plan Improvements
Based on analysis, determine what's needed:
- [ ] Introduction (if score <80)
- [ ] Code context (if many consecutive blocks)
- [ ] Examples (if 8+ code blocks and no examples section)
- [ ] Conclusion (if >800 words and missing)
- [ ] Next steps (if no related links)

### 3. Execute Improvements
Use templates from `tools/post-quality-checklist.md`

### 4. Verify
```bash
# Re-run intro analysis
./tools/rewrite-introduction.sh _posts/file.md

# Should score 80+
```

### 5. Commit
```bash
git add _posts/file.md
git commit -m "Improve [post-title]

- Rewrote introduction (X → Y words)
- Added code context between blocks
- Added Examples section (N use cases)
- Added Conclusion with key insights"
```

---

## Questions?

- **Which posts should I improve first?** Start with Priority 1 list above
- **How long will each post take?** 15-45 min depending on issues
- **What's the biggest impact?** Introduction + code context + examples
- **Do I need to fix everything?** No - focus on high-traffic or newest posts first

See `tools/README-BLOG-IMPROVEMENTS.md` for comprehensive documentation.
