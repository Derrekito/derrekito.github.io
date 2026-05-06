# Blog Quality Improvement System

Complete toolkit for analyzing and improving blog post quality.

---

## What's Here

### 📊 Analysis Tools
- **`rewrite-introduction.sh`** - Analyzes post introductions, scores 0-100, suggests improvements

### 📚 Comprehensive Guides
- **`blog-quality-improvements.md`** - Complete list of quality issues and how to fix them
- **`introduction-rewrite-plan.md`** - Detailed plan for improving introductions
- **`introduction-rewrites-examples.md`** - 6 before/after examples with patterns
- **`INTRODUCTION-IMPROVEMENT-SUMMARY.md`** - Summary of introduction improvements made

### 📝 Templates & Checklists
- **`post-quality-checklist.md`** - Pre-publish checklist and section templates
- **`new-post-template.md`** - Template for writing new posts with built-in quality checks

---

## Quick Start

### For New Posts

1. **Start with template**:
   ```bash
   cp tools/new-post-template.md _posts/YYYY-MM-DD-title.md
   ```

2. **Write following the template** (has built-in checklist)

3. **Before publishing, run analysis**:
   ```bash
   ./tools/rewrite-introduction.sh _posts/YYYY-MM-DD-title.md
   ```
   Target score: 80+

4. **Check against quality checklist**:
   - See `tools/post-quality-checklist.md`

### For Existing Posts

1. **Identify issues**:
   ```bash
   ./tools/rewrite-introduction.sh _posts/existing-post.md
   ```

2. **Review priority improvements**:
   - See `tools/blog-quality-improvements.md` for full list
   - Focus on: introduction, code context, examples, conclusion

3. **Use templates** from `post-quality-checklist.md`

4. **Re-check after improvements**

---

## The Quality Framework

### 1. Introduction Quality (COMPLETED ✅)

**Status**: 6 posts improved, tools created

**Formula**: 3 paragraphs, 80-110 words
- P1 (30-40w): Concrete scenario + why existing solutions fail
- P2 (35-45w): What this approach does + key differentiator  
- P3 (25-35w): Specific topics covered + capability gained

**Tool**: `./tools/rewrite-introduction.sh`

**Examples**: See `introduction-rewrites-examples.md`

### 2. Code Context (HIGH PRIORITY 🔴)

**Problem**: Many posts have consecutive code blocks without explanation

**Fix**: Add 2-3 sentences between each code block explaining:
- WHAT this block does
- WHY it's needed
- WHAT to expect/watch for

**Impact**: Prevents "code dump" feeling even when posts are well-written

### 3. Examples Sections (HIGH PRIORITY 🔴)

**Problem**: 60+ posts have code but no dedicated examples section

**Fix**: Add "## Examples" section with 3-5 real-world use cases

**Template**: See `post-quality-checklist.md` → Examples Template

### 4. Conclusions (MEDIUM PRIORITY 🟡)

**Problem**: 40+ posts >800 words have no conclusion

**Fix**: Add "## Conclusion" section (100-150 words) with:
- Summary of approach
- 3-4 key insights (bullets)
- Concrete capability statement

**Template**: See `post-quality-checklist.md` → Conclusion Template

### 5. Next Steps (MEDIUM PRIORITY 🟡)

**Problem**: Posts don't link to related content

**Fix**: Add "## Next Steps" or "## See Also" section

**Template**: See `post-quality-checklist.md` → Next Steps Template

### 6. Long Code Blocks (MEDIUM PRIORITY 🟡)

**Problem**: 20+ posts have code blocks >100 lines

**Fix Options**:
- Break into sections with prose between
- Add inline section comments
- Link to full source, show simplified version

### 7. Troubleshooting (LOW-MEDIUM PRIORITY 🟢)

**Problem**: Setup posts lack common issues section

**Fix**: Add "## Troubleshooting" with 3-5 common issues

**Template**: See `post-quality-checklist.md` → Troubleshooting Template

---

## Priority Roadmap

### Phase 1: Foundation (DONE ✅)
- [x] Create analysis tools
- [x] Improve 6 sample introductions
- [x] Create templates and guides
- [x] Document improvement methodology

### Phase 2: High-Impact Improvements (NEXT)
**Target**: 20-30 posts

Focus on posts with most traffic or highest code-to-prose ratio:

1. **Add code context** - 2-3 sentences between consecutive blocks
2. **Add Examples sections** - 3-5 real-world use cases  
3. **Improve remaining introductions** - ~35 more posts need work

**Estimated effort**: 15-30 min per post

### Phase 3: Polish (FUTURE)
**Target**: All posts >800 words

1. Add conclusions to longer posts
2. Add Next Steps sections
3. Break up very long code blocks
4. Add troubleshooting to setup posts

**Estimated effort**: 10-20 min per post

### Phase 4: Nice-to-Have (ONGOING)
1. Add language tags to all code blocks
2. Improve heading specificity
3. Add comparison tables where relevant

---

## Metrics & Tracking

### Before (Baseline)
- **Weak introductions**: 40+ posts (1-2 sentences, <30 words)
- **Missing conclusions**: 40+ posts >800 words
- **Missing examples**: 60+ posts with many code blocks
- **Consecutive code blocks**: ~80+ posts

### After Phase 1
- **Improved introductions**: 6 posts (16-27w → 85-100w)
- **Tools created**: 6 comprehensive guides + 1 analysis script
- **Templates available**: 4 section templates + 1 full post template

### Target (After All Phases)
- **Introduction quality**: 100% of posts score 80+ on analysis
- **Code context**: <5% of posts have consecutive blocks without prose
- **Conclusions**: 100% of posts >800 words have proper endings
- **Examples**: 80% of code-heavy posts have examples section

---

## Tools Reference

### Analysis Commands

```bash
# Analyze single post introduction
./tools/rewrite-introduction.sh _posts/file.md

# Find posts with weak introductions
for f in _posts/*.md; do
    score=$(./tools/rewrite-introduction.sh "$f" 2>/dev/null | grep "Score:" | grep -oP '\d+' | head -1)
    [ "$score" -lt 70 ] 2>/dev/null && echo "$f: $score"
done

# Count code blocks in a post
grep -c '^```' _posts/file.md

# Find consecutive code blocks
awk '/^```/{flag=!flag; if(!flag && lines<2) print NR; lines=0; next} !flag && NF>0{lines++}' _posts/file.md

# Check for conclusion
grep -i "^## \(conclusion\|summary\)" _posts/file.md

# Check for examples
grep -i "^## \(example\|usage\)" _posts/file.md

# Check word count
awk '/^---$/,/^---$/{next} {print}' _posts/file.md | wc -w
```

### Batch Operations

```bash
# List all posts missing conclusions (>800 words)
for f in _posts/*.md; do
    words=$(awk '/^---$/,/^---$/{next} {print}' "$f" | wc -w)
    has_conclusion=$(grep -qi "^## \(conclusion\|summary\)" "$f" && echo 1 || echo 0)
    [ $words -gt 800 ] && [ $has_conclusion -eq 0 ] && echo "$(basename $f): $words words, no conclusion"
done

# List all posts with many code blocks but no examples
for f in _posts/*.md; do
    blocks=$(grep -c '^```' "$f")
    has_examples=$(grep -qi "^## \(example\|usage\)" "$f" && echo 1 || echo 0)
    [ $blocks -gt 5 ] && [ $has_examples -eq 0 ] && echo "$(basename $f): $blocks blocks, no examples"
done

# Find longest code blocks
for f in _posts/*.md; do
    longest=$(awk '/^```/{flag=!flag; if(!flag && count>50) print count; count=0; next} flag{count++}' "$f" | sort -rn | head -1)
    [ -n "$longest" ] && echo "$(basename $f): $longest lines"
done | sort -t':' -k2 -rn | head -20
```

---

## File Descriptions

### Analysis Tool
- **`rewrite-introduction.sh`** (executable)
  - Analyzes introduction quality
  - Scores 0-100 based on multiple factors
  - Provides specific improvement suggestions
  - Detects generic phrases and title restatements

### Planning Documents
- **`introduction-rewrite-plan.md`**
  - Methodology for improving introductions
  - Quality checklist
  - Red flags to avoid
  - Priority queue for rewrites

- **`blog-quality-improvements.md`**
  - Comprehensive list of 9 quality issues
  - Examples of good vs bad for each
  - Templates and fix patterns
  - Priority order for improvements
  - Estimated effort per fix

### Examples & Patterns
- **`introduction-rewrites-examples.md`**
  - 6 detailed before/after examples
  - Analysis of what makes each better
  - Pattern summary for different post types
  - Quick reference guide

- **`INTRODUCTION-IMPROVEMENT-SUMMARY.md`**
  - Summary of work completed
  - Metrics (before/after)
  - Files created
  - Next steps

### Templates
- **`new-post-template.md`**
  - Full post template with built-in checklist
  - Introduction template with examples
  - Common opening patterns
  - Example post following template

- **`post-quality-checklist.md`**
  - Pre-publish checklist
  - Section templates (conclusion, examples, troubleshooting, next steps)
  - Common mistakes to avoid
  - Quality scoring rubric
  - Post-type specific checklists

---

## Writing Workflow

### Creating New Posts

1. Copy template: `cp tools/new-post-template.md _posts/YYYY-MM-DD-title.md`
2. Fill in frontmatter (title, date, categories, tags)
3. Write introduction following 3-paragraph template
4. Write body content
5. Add Examples section (3-5 use cases)
6. Add Conclusion (summary + key insights)
7. Add Next Steps (related posts, references)
8. Run quality check: `./tools/rewrite-introduction.sh _posts/file.md`
9. Review against checklist: `tools/post-quality-checklist.md`
10. Commit when score 80+

### Improving Existing Posts

1. Identify issues: `./tools/rewrite-introduction.sh _posts/file.md`
2. Consult improvement guide: `tools/blog-quality-improvements.md`
3. Focus on highest-impact fixes:
   - Introduction (if score <80)
   - Code context (add prose between blocks)
   - Examples section (if many code blocks)
   - Conclusion (if >800 words)
4. Use templates from `post-quality-checklist.md`
5. Re-run analysis to verify improvements
6. Commit with clear description of changes

---

## Success Criteria

A high-quality post has:

✅ **Introduction** scoring 80+ on analysis tool  
✅ **Code context** - prose before/after every code block  
✅ **Examples** - 3-5 complete, runnable use cases  
✅ **Conclusion** - summary + insights + capability statement (if >800w)  
✅ **Next steps** - links to related content + references (if >800w)  
✅ **Clear structure** - specific headings, scannable content  
✅ **Technical depth** - specific tools, versions, metrics  
✅ **Troubleshooting** - common issues covered (if setup/install post)

---

## Contributing Improvements

When you identify new quality patterns or create new templates:

1. Add pattern to `blog-quality-improvements.md`
2. Add template to `post-quality-checklist.md`  
3. Update this README with new tool/template
4. Consider adding analysis to `rewrite-introduction.sh` if automatable

---

## Questions?

See the individual guides for detailed information:

- **How do I write a strong introduction?** → `introduction-rewrites-examples.md`
- **What sections should my post have?** → `post-quality-checklist.md`
- **What are all the quality issues?** → `blog-quality-improvements.md`
- **What was already done?** → `INTRODUCTION-IMPROVEMENT-SUMMARY.md`

---

## Summary

**Current Status**: Phase 1 complete (foundation + tools)  
**Next Steps**: Phase 2 (high-impact improvements to 20-30 posts)  
**Key Tools**: `rewrite-introduction.sh`, quality checklist, templates  
**Main Improvements Needed**: Code context, examples sections, conclusions
