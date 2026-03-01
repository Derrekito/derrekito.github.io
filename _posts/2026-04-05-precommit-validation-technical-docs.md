---
title: "Part 3: Pre-commit Validation for Technical Documents"
date: 2026-04-05 10:00:00 -0700
categories: [Automation, Documentation]
tags: [git, bash, validation, pre-commit, latex, markdown]
series: "Executable Notebooks"
series_order: 3
---

Building a pre-commit validation pipeline that catches formatting errors, broken includes, missing citations, and accidentally staged build artifacts before they pollute the repository.

> **Note:** Code examples in this post are simplified for illustration. The actual validators include additional patterns and edge cases. A complete starter template is [available on Gumroad](https://derrekito.gumroad.com/).

## Problem Statement

Technical documentation projects accumulate subtle errors:
- LaTeX math syntax mixed with Unicode where it should not be
- `!include` directives pointing to renamed or deleted files
- Citations referencing keys that do not exist in the bibliography
- Executed notebooks and build artifacts accidentally committed

These errors slip through because they do not break anything immediately. The document still compiles. The PDF still generates. But reproducibility suffers, collaborators become confused, and the repository fills with extraneous files.

## Solution: Validation Pipeline

A set of bash scripts run as a pre-commit hook:

```text
.validation/
├── scripts/
│   ├── run-all-validators.sh      # Orchestrator
│   ├── formatting-validator.sh    # LaTeX/Unicode rules
│   ├── structural-validator.sh    # Include file checks
│   ├── citation-validator.sh      # Bibliography verification
│   └── clean-check.sh             # No generated files
```

Each validator:
- Exits 0 on pass, 1 on failure
- Generates a detailed report in `build/`
- Only checks staged files (fast)
- Provides actionable error messages

## Orchestrator Implementation

`run-all-validators.sh` coordinates all validators:

```bash
#!/bin/bash
set -e

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VALIDATION_DIR="${PROJECT_ROOT}/.validation/scripts"

# Track overall status
OVERALL_STATUS=0

# Define validators
declare -A VALIDATORS=(
    ["Formatting"]="$VALIDATION_DIR/formatting-validator.sh"
    ["Structure"]="$VALIDATION_DIR/structural-validator.sh"
    ["Citations"]="$VALIDATION_DIR/citation-validator.sh"
    ["Clean check"]="$VALIDATION_DIR/clean-check.sh"
)

# Run each validator
for name in "Formatting" "Structure" "Citations" "Clean check"; do
    script="${VALIDATORS[$name]}"

    echo -n "Running $name validation... "

    if bash "$script" 2>&1; then
        echo "[PASS]"
    else
        echo "[FAIL]"
        OVERALL_STATUS=1
    fi
done

exit $OVERALL_STATUS
```

Output example:

```text
Running pre-commit validation pipeline...

Running Formatting validation... [PASS]
Running Structure validation... [PASS]
Running Citations validation... [FAIL]
Running Clean check... [PASS]

Validation failed!
Review report: build/validation-summary.txt
```

## Validator 1: Formatting

Enforces consistent math notation:

| Context | Use | Example |
|---------|-----|---------|
| Python code | Unicode | `σ_sat`, `→`, `·` |
| Plot labels | LaTeX | `$\sigma_{sat}$` |
| Markdown text | LaTeX | `$\alpha$`, `$$...$$` |
| `.latex` blocks | LaTeX | Raw LaTeX output |

### Implementation

```bash
#!/bin/bash
# formatting-validator.sh

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' || true)

for file in $STAGED_FILES; do
    in_python_block=false
    has_latex_attribute=false
    line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Track code block state
        if [[ "$line" =~ ^\`\`\`python ]]; then
            in_python_block=true
            # Check for .latex attribute
            [[ "$line" =~ \{.*\.latex.*\} ]] && has_latex_attribute=true
            continue
        fi

        if [[ "$line" =~ ^\`\`\` ]] && [ "$in_python_block" = true ]; then
            in_python_block=false
            has_latex_attribute=false
            continue
        fi

        # Check for violations in Python blocks
        if [ "$in_python_block" = true ] && [ "$has_latex_attribute" = false ]; then
            # Skip plot labels (allowed to have LaTeX)
            if [[ "$line" =~ (xlabel|ylabel|title)\s*= ]]; then
                continue
            fi

            # Flag LaTeX $ in Python code
            if [[ "$line" =~ [^#]*\$[^f\"] ]] && [[ ! "$line" =~ ^\s*# ]]; then
                echo "VIOLATION: LaTeX in Python code at $file:$line_num"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        fi
    done < "$file"
done
```

### Detection Examples

```python
# VIOLATION - LaTeX in Python code
coefficient = $\alpha_{max}$  # Line flagged

# OK - Unicode in Python
coefficient = α_max

# OK - LaTeX in plot labels (whitelisted)
plt.ylabel(r'$\alpha_{max}$ (units)')

# OK - .latex block (whitelisted)
```python {.latex}
print(r"\alpha_{max}")
```

## Validator 2: Structure

Verifies `!include` directives resolve to existing files:

```bash
#!/bin/bash
# structural-validator.sh

for file in $STAGED_FILES; do
    line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Match !include directives
        if [[ "$line" =~ ^!include[[:space:]]+(.+)$ ]]; then
            include_path="${BASH_REMATCH[1]}"

            # Resolve relative to file's directory
            file_dir=$(dirname "$file")
            full_path="$file_dir/$include_path"

            if [ ! -f "$full_path" ]; then
                echo "VIOLATION: Include not found"
                echo "  File: $file:$line_num"
                echo "  Include: $include_path"
                echo "  Expected: $full_path"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        fi
    done < "$file"
done
```

### Detection Examples

```markdown
!include sections/introduction.md      # OK if file exists
!include sections/introdcution.md      # FAIL - typo
!include deleted_section.md            # FAIL - file removed
!include ../common/theory.md           # OK - relative path resolved
```

## Validator 3: Citations

Cross-references `\cite{key}` patterns against `bibliography.bib`:

```bash
#!/bin/bash
# citation-validator.sh

BIB_FILE="${PROJECT_ROOT}/references/bibliography.bib"

# Extract citation keys from bibliography
BIB_KEYS=$(grep -E '^@[a-zA-Z]+\{' "$BIB_FILE" | \
           sed -E 's/@[a-zA-Z]+\{([^,]+),.*/\1/' | sort -u)

for file in $STAGED_FILES; do
    line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Find \cite{key} patterns
        while [[ "$line" =~ \\cite\{([a-zA-Z0-9_:-]+)\} ]]; do
            cite_key="${BASH_REMATCH[1]}"

            # Check if key exists
            if ! echo "$BIB_KEYS" | grep -q "^${cite_key}$"; then
                echo "VIOLATION: Citation key not found: $cite_key"
                echo "  File: $file:$line_num"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi

            # Remove matched pattern, find next
            line="${line#*\\cite\{${cite_key}\}}"
        done
    done < "$file"
done
```

### Detection Examples

```latex
According to \cite{smith2023}...    # FAIL if not in bibliography.bib
See \cite{vaswani2017} for...       # OK if key exists in bibliography.bib
Multiple \cite{foo,bar}...          # Checks both keys
```

## Validator 4: Clean Check

Prevents generated files from being committed:

```bash
#!/bin/bash
# clean-check.sh

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM || true)

PROHIBITED_PATTERNS=(
    "*_Master_executed.md"
    "build/*"
    "*.aux"
    "*.fdb_latexmk"
    "*.fls"
    "*.log"
    "*/__pycache__/*"
    "notebooks/*/output/*"
)

for file in $STAGED_FILES; do
    for pattern in "${PROHIBITED_PATTERNS[@]}"; do
        if [[ "$file" == $pattern ]]; then
            echo "VIOLATION: Generated file staged: $file"
            VIOLATIONS=$((VIOLATIONS + 1))
            break
        fi
    done

    # Specific checks
    if [[ "$file" =~ _Master_executed\.md$ ]]; then
        echo "VIOLATION: Executed notebook staged: $file"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done
```

### Detection Examples

```text
notebooks/BrainChip_Master_executed.md  # FAIL - should be gitignored
build/output.pdf                        # FAIL - build artifact
src/__pycache__/module.pyc              # FAIL - Python cache
notebooks/output/figure1.pdf            # WARNING - may be intentional
```

## Git Hook Integration

Install as pre-commit hook:

```bash
#!/bin/bash
# .git/hooks/pre-commit

exec ./.validation/scripts/run-all-validators.sh
```

Make executable:

```bash
chmod +x .git/hooks/pre-commit
```

Every `git commit` now runs validation:

```bash
$ git add notebooks/analysis.md
$ git commit -m "Update analysis"

Running pre-commit validation pipeline...

Running Formatting validation... [PASS]
Running Structural validation... [PASS]
Running Citation validation... [PASS]
Running Clean check... [PASS]

All validation checks passed!
[main abc1234] Update analysis
```

## Makefile Integration

Validators are exposed via Make targets:

```makefile
.PHONY: verify verify-formatting verify-structure verify-citations verify-clean

verify:
    @./.validation/scripts/run-all-validators.sh

verify-formatting:
    @./.validation/scripts/formatting-validator.sh

verify-structure:
    @./.validation/scripts/structural-validator.sh

verify-citations:
    @./.validation/scripts/citation-validator.sh

verify-clean:
    @./.validation/scripts/clean-check.sh
```

Manual execution:

```bash
make verify              # All checks
make verify-formatting   # Just formatting
make verify-citations    # Just citations
```

## Detailed Reports

Each validator writes a report to `build/`:

```text
build/
├── formatting-validation.txt
├── structural-validation.txt
├── citation-validation.txt
├── clean-check.txt
└── validation-summary.txt
```

Example report:

```text
Formatting Validation Report
============================
Date: Sat Feb 22 16:00:00 MST 2026

Checking staged markdown files...

VIOLATION: LaTeX math in Python code (use Unicode)
  File: notebooks/analysis.md:42
  Line: sigma = $\sigma_{sat}$

============================
Total violations: 1
RESULT: FAIL

Fix violations according to guidelines:
  - Python code blocks: Use Unicode (σ_sat, ·, →)
  - Plot titles/labels: Use LaTeX ($\sigma_{sat}$)
  - Markdown text: Use LaTeX math mode
```

## Bypassing Validation

Commits can proceed despite failures when necessary:

```bash
git commit --no-verify -m "WIP: experimental changes"
```

The orchestrator reminds users of this escape hatch:

```text
Validation failed!
Review report: build/validation-summary.txt

To bypass (NOT recommended): git commit --no-verify
```

This option should be used sparingly. Violations should be fixed before merging to main.

## Performance

Validators are fast because they:

1. **Only check staged files**: Not the entire repository

```bash
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$')
```

2. **Exit early**: Skip checks when no relevant files exist

```bash
if [ -z "$STAGED_FILES" ]; then
    echo "No markdown files staged."
    exit 0
fi
```

3. **Run lightweight checks first**: Formatting before structure before citations

4. **Stream processing**: Line-by-line, without loading entire files

## Adding New Validators

Follow the established pattern:

```bash
#!/bin/bash
# my-validator.sh

set -e

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
REPORT_FILE="${PROJECT_ROOT}/build/my-validation.txt"

# Initialize report
mkdir -p "$(dirname "$REPORT_FILE")"
echo "My Validation Report" > "$REPORT_FILE"
echo "Date: $(date)" >> "$REPORT_FILE"

VIOLATIONS=0

# Get staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' || true)

if [ -z "$STAGED_FILES" ]; then
    echo "No files to check." >> "$REPORT_FILE"
    exit 0
fi

# Validation logic here
for file in $STAGED_FILES; do
    # Check something...
    if [[ condition ]]; then
        echo "VIOLATION: description" >> "$REPORT_FILE"
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done

# Summary
echo "Total violations: $VIOLATIONS" >> "$REPORT_FILE"

if [ $VIOLATIONS -eq 0 ]; then
    echo "RESULT: PASS" >> "$REPORT_FILE"
    exit 0
else
    echo "RESULT: FAIL" >> "$REPORT_FILE"
    exit 1
fi
```

Then add to `run-all-validators.sh`:

```bash
declare -A VALIDATORS=(
    ...
    ["My check"]="$VALIDATION_DIR/my-validator.sh"
)
```

## CI/CD Integration

Run in GitHub Actions:

```yaml
name: Validate

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run validation
        run: |
          # Stage all files for validation
          git add -A
          make verify
```

Note: CI requires files to be staged for validation. Use `git add -A` or modify validators to check all files in CI mode.

## Common Fixes

### Formatting Violations

```python
# Before (violation)
result = $\alpha$ * coefficient

# After (fixed)
result = α * coefficient
```

### Missing Includes

```bash
# Find the file
find notebooks -name "*introduction*"

# Fix the path
sed -i 's/!include intro.md/!include sections\/introduction.md/' file.md
```

### Missing Citations

```bash
# Add to bibliography.bib
cat >> references/bibliography.bib << 'EOF'
@article{smith2023,
  title = {The Title},
  author = {Smith, John},
  journal = {Journal Name},
  year = {2023}
}
EOF
```

### Staged Generated Files

```bash
# Unstage
git reset HEAD notebooks/*_executed.md

# Clean
make clean-notebooks

# Verify .gitignore
echo "*_executed.md" >> .gitignore
```

## Summary

Pre-commit validation catches errors at the cheapest possible moment: before they enter the repository. Key principles:

- **Fast**: Only check staged files
- **Specific**: Clear violation messages with file:line
- **Escapable**: `--no-verify` for emergencies
- **Extensible**: Simple pattern for new validators

The full implementation is included in the [starter template on Gumroad](https://derrekito.gumroad.com/).
