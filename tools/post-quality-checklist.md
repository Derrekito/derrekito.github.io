# Blog Post Quality Checklist

Use this checklist before publishing any new post or when improving existing posts.

---

## Pre-Publish Checklist

### ✅ Introduction (80-110 words, 3 paragraphs)
- [ ] Paragraph 1: Concrete scenario + why existing solutions fail
- [ ] Paragraph 2: What this approach does + key differentiator  
- [ ] Paragraph 3: Specific topics covered + capability gained
- [ ] NO generic phrases ("this post", "guide to", "learn how")
- [ ] NO title restatement
- [ ] Run: `./tools/rewrite-introduction.sh _posts/my-post.md` (score 80+)

### ✅ Code Quality
- [ ] Every code block has language tag (```bash, ```python, etc.)
- [ ] No more than 2 consecutive code blocks without prose between
- [ ] Every code block has 1-2 sentences explaining what it does
- [ ] Code blocks >20 lines have explanatory prose after OR inline comments
- [ ] Code blocks >50 lines are split into sections OR link to full source
- [ ] Code examples are complete and runnable (not fragments)

### ✅ Structure & Sections

**Required for all posts**:
- [ ] Introduction (80-110 words)
- [ ] Clear section headings (specific, not generic)
- [ ] Code with context (prose between blocks)

**Required for posts >800 words**:
- [ ] Conclusion or Summary section (100-150 words)
- [ ] Next Steps, See Also, or References section
- [ ] Examples section (if post has 5+ code blocks)

**Required for setup/installation posts**:
- [ ] Troubleshooting section with 3-5 common issues
- [ ] Each issue has: symptom, cause, solution

**Recommended**:
- [ ] Comparison table (if discussing alternatives)
- [ ] Visual diagrams (mermaid, architecture diagrams)
- [ ] Command output examples (what to expect)

### ✅ Content Quality
- [ ] First sentence hooks the reader (concrete scenario, not abstract)
- [ ] Explains WHY before HOW (motivation before implementation)
- [ ] Includes specific technical terms, tools, versions
- [ ] Mentions alternatives and when to use each
- [ ] Links to related internal posts (if they exist)
- [ ] Links to official docs/source repos
- [ ] Avoids unexplained jargon (or defines it on first use)

### ✅ SEO & Metadata
- [ ] Title is <70 characters
- [ ] Title is specific and includes main keyword
- [ ] Tags include relevant technical terms
- [ ] First paragraph includes main keyword naturally
- [ ] Headings are semantic (## for sections, ### for subsections)
- [ ] Internal links use descriptive anchor text

---

## Quick Quality Checks

### Run These Commands:

```bash
# Check introduction quality
./tools/rewrite-introduction.sh _posts/my-post.md

# Count code blocks
grep -c '^```' _posts/my-post.md

# Find consecutive code blocks
awk '/^```/{flag=!flag; if(!flag && lines<2) print "Line " NR-1; lines=0; next} !flag && NF>0{lines++}' _posts/my-post.md

# Check for conclusion
grep -i "^## \(conclusion\|summary\)" _posts/my-post.md

# Check for examples
grep -i "^## \(example\|usage\)" _posts/my-post.md

# Word count
awk '/^---$/,/^---$/{next} {print}' _posts/my-post.md | wc -w
```

---

## Section Templates

### Introduction Template
```markdown
[Concrete scenario showing the problem]. [Why existing solutions fail]. 
[What makes this problem hard or frustrating].

[Name of tool/approach] provides [what it does]: [key technical detail]. 
Unlike [alternative], it [key differentiator]. Instead of [other approach], 
this [what makes it better].

This [post/guide] covers [specific topic 1], [specific topic 2], and 
[specific topic 3]. [Mention key gotcha if relevant]. [Concrete capability 
statement].
```

### Conclusion Template
```markdown
## Conclusion

[1-2 sentences summarizing what was covered and the main approach]

Key insights:
- [Technical insight #1 with specific detail]
- [Technical insight #2 with specific detail]
- [When to use this vs alternatives]
- [Main tradeoff or limitation to be aware of]

[Concrete capability statement: what readers can now do]
```

### Examples Template
```markdown
## Examples

### Example 1: [Most Common Use Case]

[1 sentence describing scenario]

```bash
# Complete, runnable code
```

[1-2 sentences explaining result or what this demonstrates]

### Example 2: [Second Common Use Case]

[Setup context if needed]

```bash
# Example code
```

[Explanation]

### Example 3: [Edge Case or Advanced Usage]

[When you'd need this]

```bash
# Advanced example
```

[Why this approach works]
```

### Troubleshooting Template
```markdown
## Troubleshooting

### Issue: [Specific error message or symptom]

**Symptom**: [What the user sees - be specific]

**Cause**: [Why this happens - technical explanation]

**Solution**:

```bash
# Commands to verify and fix
```

[What the fix does and how to verify it worked]

### Issue: [Another common problem]

**Symptom**: [Description]

**Cause**: [Explanation]

**Solution**:

```bash
# Fix commands
```
```

### Next Steps Template
```markdown
## Next Steps

[If part of series]
Continue to [Part X: Topic](/posts/slug/) for [specific learning objective].

[If standalone]
To extend this further:
- **[Capability/Topic]**: See [Related Post Title](/posts/slug/)
- **[Another capability]**: Check out [Tool/Resource](link)
- **[Advanced topic]**: Explore [Documentation](link)

## References

- [Official Documentation](url)
- [Source Repository](url)
- [Related Tool/Library](url)
- [Paper/Article Title](url) (if applicable)
```

---

## Common Mistakes to Avoid

### ❌ Don't Do This
1. **Code dumps** - Multiple code blocks in a row without explanation
2. **Fragment examples** - Code that can't run without context
3. **Generic headings** - "Setup", "Configuration", "Implementation"
4. **Missing language tags** - Plain ``` instead of ```bash
5. **Wall of text** - Long paragraphs without breaks or lists
6. **Ending abruptly** - No conclusion or next steps
7. **Unexplained output** - Show command output but don't explain what to look for
8. **Missing motivation** - Jump into "how" without explaining "why"

### ✅ Do This Instead
1. **Contextual code** - 2-3 sentences before each block
2. **Complete examples** - Runnable code with all necessary context
3. **Specific headings** - "Server Setup: nginx Configuration"
4. **Tagged blocks** - ```bash, ```python, ```json
5. **Scannable content** - Mix of prose, code, lists, tables
6. **Proper endings** - Summary + next steps + references
7. **Explained results** - "Look for 'Connected' in the output"
8. **Clear motivation** - Problem → failed alternatives → this solution

---

## Quality Scoring

Rate each post on these criteria (1-5 scale):

| Criterion | 1 (Poor) | 3 (Good) | 5 (Excellent) |
|-----------|----------|----------|---------------|
| **Introduction** | Generic, <30 words | Decent hook, ~50w | Compelling scenario, 80-110w |
| **Code Context** | Blocks with no explanation | Some explanation | Every block explained |
| **Structure** | Missing sections | Has main sections | Complete with examples/troubleshooting |
| **Conclusion** | No ending | Brief summary | Summary + insights + next steps |
| **Scannability** | Wall of text | Some breaks | Headers, lists, tables, emphasis |

**Target**: 4-5 on all criteria before publishing

---

## Post-Type Specific Checklists

### Tutorial Posts
- [ ] Step numbers or clear progression
- [ ] Each step has expected output or result
- [ ] Common failure points addressed
- [ ] "What you'll build" stated upfront
- [ ] Final result shown/demonstrated

### Reference Posts  
- [ ] Table of contents or section overview
- [ ] Consistent formatting across entries
- [ ] Quick lookup possible (not buried in prose)
- [ ] Examples for each entry
- [ ] Edge cases documented

### Deep-Dive Technical Posts
- [ ] Explains "why" it works this way
- [ ] Includes performance considerations
- [ ] Mentions tradeoffs
- [ ] Compares to alternatives
- [ ] Has diagrams or visual explanations

### Troubleshooting Guides
- [ ] Issues organized by symptom (what user sees)
- [ ] Each issue has cause + solution
- [ ] Includes verification steps
- [ ] Sorted by commonality (most common first)
- [ ] Has "Still not working?" section

---

## Pre-Commit Hook (Optional)

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Check quality of changed markdown files

for file in $(git diff --cached --name-only | grep '^_posts/.*\.md$'); do
    echo "Checking: $file"
    
    # Check intro length
    intro_words=$(awk '/^---$/,/^---$/{next} /^##/{exit} {print}' "$file" | wc -w)
    if [ $intro_words -lt 80 ]; then
        echo "  ⚠ Introduction too short: $intro_words words (need 80+)"
    fi
    
    # Check for conclusion
    if ! grep -qi "^## \(conclusion\|summary\)" "$file"; then
        words=$(awk '/^---$/,/^---$/{next} {print}' "$file" | wc -w)
        if [ $words -gt 800 ]; then
            echo "  ⚠ Long post ($words words) missing conclusion"
        fi
    fi
    
    # Check for code blocks without language
    plain_blocks=$(grep -c '^```$' "$file" || echo 0)
    if [ $plain_blocks -gt 0 ]; then
        echo "  ⚠ $plain_blocks code blocks missing language tags"
    fi
done
```

---

## Improvement Workflow

For existing posts needing improvement:

1. **Run analysis**: `./tools/rewrite-introduction.sh _posts/file.md`
2. **Identify issues**: Check against this checklist
3. **Prioritize fixes**:
   - Phase 1: Introduction, code context
   - Phase 2: Examples, conclusion
   - Phase 3: Troubleshooting, next steps
4. **Make changes**: Use templates above
5. **Re-check**: Run analysis again, verify score 80+
6. **Commit**: Good commit message describing improvements

---

## Quick Reference: Most Impactful Improvements

If you only have time for 3 things, do these:

1. **Strong introduction** (3 paragraphs, 80-110 words, concrete scenario)
2. **Context between code blocks** (2-3 sentences explaining each)
3. **Examples section** (3-5 complete, runnable use cases)

These three changes will dramatically improve post quality with minimal effort.
