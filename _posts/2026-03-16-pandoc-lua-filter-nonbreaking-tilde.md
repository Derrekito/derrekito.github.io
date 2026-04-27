---
title: "Restoring Non-Breaking Spaces in Pandoc 3.x with a Lua Filter"
date: 2026-03-16
categories: [Lua, Documentation]
tags: [pandoc, lua, latex, filters, typography]
---

Pandoc 3.x changed how it handles the tilde character (`~`) in Markdown-to-LaTeX conversion. Where earlier versions treated `~` as a LaTeX non-breaking space, Pandoc 3.x now emits `\textasciitilde` — a literal tilde glyph. This breaks documents that rely on `~` for non-breaking spaces in names, units, and references. A small Lua filter restores the expected behavior.

## The Problem

In LaTeX, `~` is a tie — a non-breaking space that prevents line breaks between adjacent words. Technical documents use it constantly:

```latex
Figure~1        % keeps "Figure" and "1" on the same line
Dr.~Smith       % prevents break between title and name
100~MHz         % keeps value and unit together
Section~3.2     % anchors label to number
```

Prior to version 3.x, Pandoc passed `~` through to LaTeX unchanged, preserving this behavior. Starting with Pandoc 3.x, the Markdown reader interprets `~` as a literal tilde and the LaTeX writer emits `\textasciitilde`, which renders as a raised tilde glyph (~) instead of a space.

A document with `Figure~1` now produces `Figure\textasciitilde 1` in the LaTeX output — visually wrong and typographically broken.

## The Filter

The fix is a Lua filter that intercepts `Str` elements in the AST, finds tildes, and replaces them with raw LaTeX `~` characters:

```lua
--- Convert literal ~ in text to LaTeX non-breaking space (~).
--- Pandoc 3.x treats ~ as \textasciitilde in markdown→LaTeX;
--- this filter restores the expected non-breaking space behavior.
function Str(el)
  if el.text:find("~") then
    local parts = {}
    for part in el.text:gmatch("[^~]+") do
      table.insert(parts, part)
    end
    local result = {}
    for i, part in ipairs(parts) do
      if part ~= "" then
        table.insert(result, pandoc.Str(part))
      end
      if i < #parts then
        table.insert(result, pandoc.RawInline('latex', '~'))
      end
    end
    return result
  end
end
```

## Walkthrough

The filter operates on `Str` elements — the AST nodes that contain literal text strings. Pandoc splits inline content into typed elements: `Str` for text, `Space` for whitespace, `Code` for inline code, and so on. A tilde embedded in text lands inside a `Str` node.

### Early Exit

```lua
if el.text:find("~") then
```

The guard clause uses Lua's `string.find` to check whether the text contains a tilde at all. Most `Str` elements don't, so this skips them without allocating any tables.

### Splitting on Tildes

```lua
local parts = {}
for part in el.text:gmatch("[^~]+") do
  table.insert(parts, part)
end
```

`gmatch("[^~]+")` extracts every run of non-tilde characters. For the input `Figure~1`, this produces `{"Figure", "1"}`. For `A~B~C`, it produces `{"A", "B", "C"}`.

### Reassembling with Raw LaTeX

```lua
local result = {}
for i, part in ipairs(parts) do
  if part ~= "" then
    table.insert(result, pandoc.Str(part))
  end
  if i < #parts then
    table.insert(result, pandoc.RawInline('latex', '~'))
  end
end
return result
```

Each text fragment becomes a `pandoc.Str` element, and each tilde position becomes a `pandoc.RawInline('latex', '~')` — a raw LaTeX non-breaking space that Pandoc passes through verbatim to the writer.

The `if i < #parts` condition places a tilde between every pair of fragments but not after the last one. For `Figure~1`, the result is:

```
[Str "Figure", RawInline "~", Str "1"]
```

Returning a list from a filter function tells Pandoc to replace the original element with the list contents spliced into the document.

## Usage

Save the filter as `nonbreaking-tilde.lua` and pass it to Pandoc:

```bash
pandoc input.md \
  --lua-filter=nonbreaking-tilde.lua \
  -o output.pdf
```

In a multi-filter pipeline, this filter should run early — before filters that modify or consume inline elements:

```bash
pandoc input.md \
  --lua-filter=nonbreaking-tilde.lua \
  --lua-filter=other-filters.lua \
  --filter=pandoc-minted.py \
  -o output.pdf
```

### Verifying the Fix

Check the intermediate LaTeX to confirm the filter is working:

```bash
pandoc input.md --lua-filter=nonbreaking-tilde.lua -o output.tex
grep '~' output.tex
```

You should see bare `~` characters in the output rather than `\textasciitilde`.

## Why Lua Over Python

This filter is a good example of when to use a Lua filter instead of a Python JSON filter. Lua filters run inside Pandoc's process with no serialization overhead. A Python filter would need to parse the full JSON AST, walk every element, and serialize it back — adding hundreds of milliseconds for what amounts to a string replacement. The Lua version adds negligible overhead since it skips elements that don't contain tildes.

## References

- [Pandoc Lua Filters Manual](https://pandoc.org/lua-filters.html)
- [Pandoc 3.0 Release Notes](https://pandoc.org/releases.html#pandoc-3.0-2023-01-18)
- [LaTeX Non-Breaking Spaces](https://www.overleaf.com/learn/latex/Line_breaks_and_blank_spaces#Non-breaking_spaces)
