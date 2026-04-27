#!/bin/bash
# Tool to analyze and suggest improvements for blog post introductions

set -euo pipefail

YELLOW='\033[1;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

analyze_intro() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: $file${NC}"
        return 1
    fi

    # Extract all content between YAML frontmatter and first ## heading
    intro=$(awk '
        BEGIN { in_yaml=0; past_yaml=0; collecting=0 }

        /^---$/ {
            if (in_yaml) { past_yaml=1; in_yaml=0 }
            else { in_yaml=1 }
            next
        }

        in_yaml { next }

        # Stop at first ## heading
        past_yaml && /^##/ { exit }

        # Skip blank lines before content starts
        past_yaml && !collecting && /^$/ { next }

        # Skip series markers (italic lines like *Part 1 of...*)
        past_yaml && /^\*.*\*$/ { next }

        # Start collecting
        past_yaml && !collecting && NF > 0 { collecting=1 }

        # Print everything until we hit ##
        collecting { print }
    ' "$file" | sed '/^$/N;/^\n$/D')

    if [[ -z "$intro" ]]; then
        echo -e "${RED}No introduction found${NC}"
        return 1
    fi

    # Count sentences (rough heuristic)
    sentences=$(echo "$intro" | grep -o '\. ' | wc -l)
    sentences=$((sentences + 1))

    # Count words
    words=$(echo "$intro" | wc -w)

    # Check for title restatement
    title=$(grep '^title:' "$file" | sed 's/^title: *"*//;s/"*$//' | tr '[:upper:]' '[:lower:]')
    intro_lower=$(echo "$intro" | tr '[:upper:]' '[:lower:]')

    # Extract key phrases from title
    has_restatement=0
    for phrase in $(echo "$title" | sed 's/[^a-z ]//g' | tr ' ' '\n' | grep -v '^.$' | grep -v '^..$'); do
        if echo "$intro_lower" | grep -q "$phrase"; then
            has_restatement=$((has_restatement + 1))
        fi
    done

    # Check for generic phrases
    generic_phrases=(
        "this post"
        "this tutorial"
        "this guide"
        "we'll explore"
        "in this article"
        "we will discuss"
    )

    has_generic=0
    for phrase in "${generic_phrases[@]}"; do
        if echo "$intro_lower" | grep -qi "$phrase"; then
            has_generic=$((has_generic + 1))
        fi
    done

    # Analysis output
    echo -e "${BLUE}=== Introduction Analysis ===${NC}"
    echo -e "${BLUE}File:${NC} $(basename "$file")"
    echo ""
    echo -e "${BLUE}Current Introduction:${NC}"
    echo "$intro" | fold -s -w 80
    echo ""
    echo -e "${BLUE}Metrics:${NC}"
    echo "  Sentences: $sentences"
    echo "  Words: $words"
    echo "  Title overlap phrases: $has_restatement"
    echo "  Generic phrases: $has_generic"
    echo ""

    # Scoring
    score=100
    issues=()

    if [[ $sentences -le 1 ]]; then
        score=$((score - 40))
        issues+=("${RED}✗ Only 1 sentence (need 3-6)${NC}")
    elif [[ $sentences -le 2 ]]; then
        score=$((score - 20))
        issues+=("${YELLOW}⚠ Only $sentences sentences (recommend 3-6)${NC}")
    else
        issues+=("${GREEN}✓ Good sentence count${NC}")
    fi

    if [[ $words -lt 30 ]]; then
        score=$((score - 30))
        issues+=("${RED}✗ Too short: $words words (need 50+)${NC}")
    elif [[ $words -lt 50 ]]; then
        score=$((score - 15))
        issues+=("${YELLOW}⚠ Short: $words words (recommend 50-100)${NC}")
    else
        issues+=("${GREEN}✓ Good length${NC}")
    fi

    if [[ $has_restatement -ge 3 ]]; then
        score=$((score - 20))
        issues+=("${RED}✗ High title overlap (likely restatement)${NC}")
    fi

    if [[ $has_generic -ge 2 ]]; then
        score=$((score - 10))
        issues+=("${YELLOW}⚠ Generic phrasing detected${NC}")
    fi

    echo -e "${BLUE}Issues:${NC}"
    for issue in "${issues[@]}"; do
        echo -e "  $issue"
    done
    echo ""

    # Overall score
    if [[ $score -ge 80 ]]; then
        echo -e "${GREEN}Score: $score/100 - Good introduction${NC}"
    elif [[ $score -ge 60 ]]; then
        echo -e "${YELLOW}Score: $score/100 - Needs improvement${NC}"
    else
        echo -e "${RED}Score: $score/100 - Rewrite recommended${NC}"
    fi
    echo ""

    # Suggestions
    echo -e "${BLUE}Improvement Suggestions:${NC}"

    if [[ $sentences -le 2 ]]; then
        cat <<EOF
  1. Expand to 2-3 paragraphs:
     - Para 1: What problem does this solve? Who has this problem?
     - Para 2: What approach/tool/technique does this cover?
     - Para 3: What will readers learn/build?
EOF
    fi

    if [[ $has_restatement -ge 3 ]]; then
        cat <<EOF
  2. Avoid restating the title. Instead:
     - Start with the underlying problem
     - Explain why existing solutions fall short
     - Preview what makes your approach different
EOF
    fi

    if [[ $has_generic -ge 1 ]]; then
        cat <<EOF
  3. Remove generic phrases like "this post", "we'll explore":
     - Start directly with the problem/context
     - Be specific about what readers will learn
     - Use concrete examples and technical terms
EOF
    fi

    cat <<EOF
  4. Add specificity:
     - Name specific tools, libraries, versions
     - Include metrics (X% faster, N fewer lines)
     - Reference concrete use cases
EOF
}

# Main
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <post-file.md>"
    echo ""
    echo "Analyzes blog post introduction and suggests improvements"
    exit 1
fi

analyze_intro "$1"
