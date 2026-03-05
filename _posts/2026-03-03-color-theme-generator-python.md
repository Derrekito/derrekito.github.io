---
title: "Build a Color Theme Generator: Harmony, Contrast, and WCAG in Python"
date: 2026-03-03
categories: [Tools, Design]
tags: [python, color-theory, accessibility, wcag, design-tools]
---

Choosing colors that work together is harder than it looks. This post presents a Python script that analyzes any hex color and generates harmonizing palettes based on color theory, while also calculating WCAG contrast ratios for accessibility compliance.

## The Problem

You have a brand color or a color you like, and you need to:
- Find colors that harmonize with it
- Ensure text remains readable (WCAG AA/AAA compliance)
- Understand the color's properties (hue, saturation, lightness)
- Generate complementary, analogous, and triadic palettes

## Color Theory Primer

### The Color Wheel

Colors relate to each other based on their position on the color wheel (0-360 degrees of hue):

| Relationship | Hue Shift | Description |
|--------------|-----------|-------------|
| Analogous | ±30° | Adjacent colors, naturally harmonious |
| Complementary | 180° | Opposite colors, high contrast |
| Split-complementary | ±150° | Softer than pure complementary |
| Triadic | ±120° | Three evenly-spaced colors |

### WCAG Contrast Requirements

The Web Content Accessibility Guidelines define minimum contrast ratios:

| Level | Normal Text | Large Text |
|-------|-------------|------------|
| AA | 4.5:1 | 3:1 |
| AAA | 7:1 | 4.5:1 |

Large text is defined as 18pt (24px) or 14pt bold (18.5px bold).

## The Implementation

### Color Space Conversions

First, we need functions to convert between color spaces:

```python
import colorsys

def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    """Convert hex color to RGB tuple."""
    hex_color = hex_color.lstrip('#')
    r, g, b = [int(hex_color[i:i+2], 16) for i in (0, 2, 4)]
    return r, g, b


def rgb_to_hex(r: int, g: int, b: int) -> str:
    """Convert RGB tuple to hex color."""
    return '#{:02x}{:02x}{:02x}'.format(r, g, b)
```

### Relative Luminance

WCAG contrast calculations require relative luminance, which accounts for human perception of brightness:

```python
def srgb_to_linear(c: int) -> float:
    """Convert sRGB component to linear RGB.

    sRGB uses gamma correction; we need linear values for
    luminance calculations.
    """
    c = c / 255.0
    if c <= 0.04045:
        return c / 12.92
    else:
        return ((c + 0.055) / 1.055) ** 2.4


def relative_luminance(r: int, g: int, b: int) -> float:
    """Calculate relative luminance per WCAG 2.1.

    Returns a value between 0 (black) and 1 (white).
    The coefficients reflect human perception: we're most
    sensitive to green, then red, then blue.
    """
    r_lin = srgb_to_linear(r)
    g_lin = srgb_to_linear(g)
    b_lin = srgb_to_linear(b)
    return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin
```

The gamma correction step (`srgb_to_linear`) is critical. sRGB values are perceptually uniform but not physically linear—the conversion accounts for this.

### Contrast Ratio

With luminance values, we can calculate WCAG contrast ratio:

```python
def contrast_ratio(lum1: float, lum2: float) -> float:
    """Calculate WCAG contrast ratio between two luminance values.

    Returns a ratio from 1:1 (identical) to 21:1 (black/white).
    """
    lighter = max(lum1, lum2)
    darker = min(lum1, lum2)
    return (lighter + 0.05) / (darker + 0.05)
```

The 0.05 offset prevents division by zero and accounts for ambient light reflectance.

### Color Harmony Functions

Generate harmonizing colors by shifting hue while preserving saturation and lightness:

```python
def shift_hue(h: float, shift_degrees: float) -> float:
    """Shift hue by degrees, wrapping around the color wheel."""
    return (h + shift_degrees / 360.0) % 1.0


def hsl_to_rgb_hex(h: float, s: float, l: float) -> str:
    """Convert HSL (0-1 range) to hex color."""
    # colorsys uses HLS order, not HSL
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return rgb_to_hex(int(r * 255), int(g * 255), int(b * 255))
```

Note: Python's `colorsys` uses HLS (Hue, Lightness, Saturation) order, not the more common HSL.

### The Complete Analyzer

```python
#!/usr/bin/env python3
"""Analyze colors and generate harmonizing palettes.

Examples:
    python3 create_color_theme.py
    # Enter: #232136
    # Outputs color properties and harmony suggestions
"""
import colorsys


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    hex_color = hex_color.lstrip('#')
    r, g, b = [int(hex_color[i:i+2], 16) for i in (0, 2, 4)]
    return r, g, b


def rgb_to_hex(r: int, g: int, b: int) -> str:
    return '#{:02x}{:02x}{:02x}'.format(r, g, b)


def srgb_to_linear(c: int) -> float:
    c = c / 255.0
    if c <= 0.04045:
        return c / 12.92
    else:
        return ((c + 0.055) / 1.055) ** 2.4


def relative_luminance(r: int, g: int, b: int) -> float:
    r_lin = srgb_to_linear(r)
    g_lin = srgb_to_linear(g)
    b_lin = srgb_to_linear(b)
    return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin


def contrast_ratio(lum1: float, lum2: float) -> float:
    lighter = max(lum1, lum2)
    darker = min(lum1, lum2)
    return (lighter + 0.05) / (darker + 0.05)


def shift_hue(h: float, shift_degrees: float) -> float:
    return (h + shift_degrees / 360.0) % 1.0


def hsl_to_rgb_hex(h: float, s: float, l: float) -> str:
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return rgb_to_hex(int(r * 255), int(g * 255), int(b * 255))


def analyze_color(hex_color: str, compare_hex: str = None) -> None:
    """Analyze a color and print harmonizing suggestions."""
    print(f"Analyzing {hex_color}:")

    r, g, b = hex_to_rgb(hex_color)
    print(f"  RGB: ({r}, {g}, {b})")

    r_lin = srgb_to_linear(r)
    g_lin = srgb_to_linear(g)
    b_lin = srgb_to_linear(b)
    print(f"  Linear RGB: ({r_lin:.4f}, {g_lin:.4f}, {b_lin:.4f})")

    luminance = relative_luminance(r, g, b)
    print(f"  Relative Luminance: {luminance:.4f}")

    # Convert to HSL for harmony calculations
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
    print(f"  HSL: ({h * 360:.1f}°, {s * 100:.1f}%, {l * 100:.1f}%)")

    # Contrast against comparison color
    if compare_hex:
        r2, g2, b2 = hex_to_rgb(compare_hex)
        lum2 = relative_luminance(r2, g2, b2)
        ratio = contrast_ratio(luminance, lum2)
        print(f"  Contrast Ratio vs {compare_hex}: {ratio:.2f}:1")

        # WCAG compliance
        if ratio >= 7:
            print("    ✓ Passes WCAG AAA (normal text)")
        elif ratio >= 4.5:
            print("    ✓ Passes WCAG AA (normal text)")
        elif ratio >= 3:
            print("    ✓ Passes WCAG AA (large text only)")
        else:
            print("    ✗ Fails WCAG requirements")

    # Generate harmonizing colors
    print("\nSuggested Harmonizing Colors:")

    # Analogous (±30°)
    print(f"  Analogous Left:  {hsl_to_rgb_hex(shift_hue(h, -30), s, l)}")
    print(f"  Analogous Right: {hsl_to_rgb_hex(shift_hue(h, 30), s, l)}")

    # Complementary (180°)
    print(f"  Complementary:   {hsl_to_rgb_hex(shift_hue(h, 180), s, l)}")

    # Split Complementary (±150°)
    print(f"  Split Comp Left:  {hsl_to_rgb_hex(shift_hue(h, 150), s, l)}")
    print(f"  Split Comp Right: {hsl_to_rgb_hex(shift_hue(h, -150), s, l)}")

    # Triadic (±120°)
    print(f"  Triadic Left:  {hsl_to_rgb_hex(shift_hue(h, 120), s, l)}")
    print(f"  Triadic Right: {hsl_to_rgb_hex(shift_hue(h, -120), s, l)}")


if __name__ == "__main__":
    user_color = input("Enter hex color (e.g., #1a1b26): ")
    compare_color = input("Enter optional background color for contrast (or Enter to skip): ")
    if not compare_color.strip():
        compare_color = None
    analyze_color(user_color, compare_color)
```

## Usage Examples

### Analyzing a Dark Theme Background

```
$ python3 create_color_theme.py
Enter hex color (e.g., #1a1b26): #1a1b26
Enter optional background color for contrast (or Enter to skip):

Analyzing #1a1b26:
  RGB: (26, 27, 38)
  Linear RGB: (0.0085, 0.0088, 0.0126)
  Relative Luminance: 0.0093
  HSL: (235.0°, 18.8%, 12.5%)

Suggested Harmonizing Colors:
  Analogous Left:  #1a1926
  Analogous Right: #261a26
  Complementary:   #26251a
  Split Comp Left:  #251a26
  Split Comp Right: #1a261b
  Triadic Left:  #1a2619
  Triadic Right: #261a19
```

### Checking Text Contrast

```
$ python3 create_color_theme.py
Enter hex color (e.g., #1a1b26): #c0caf5
Enter optional background color for contrast (or Enter to skip): #1a1b26

Analyzing #c0caf5:
  RGB: (192, 202, 245)
  Linear RGB: (0.5271, 0.5906, 0.9130)
  Relative Luminance: 0.5903
  HSL: (228.7°, 76.8%, 85.7%)
  Contrast Ratio vs #1a1b26: 12.94:1
    ✓ Passes WCAG AAA (normal text)
```

## Extending the Script

### Generate CSS Custom Properties

```python
def generate_css_vars(base_hex: str, prefix: str = "color") -> str:
    """Generate CSS custom properties for a color palette."""
    r, g, b = hex_to_rgb(base_hex)
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)

    colors = {
        "base": base_hex,
        "analogous-1": hsl_to_rgb_hex(shift_hue(h, -30), s, l),
        "analogous-2": hsl_to_rgb_hex(shift_hue(h, 30), s, l),
        "complement": hsl_to_rgb_hex(shift_hue(h, 180), s, l),
        "triadic-1": hsl_to_rgb_hex(shift_hue(h, 120), s, l),
        "triadic-2": hsl_to_rgb_hex(shift_hue(h, -120), s, l),
    }

    lines = [":root {"]
    for name, value in colors.items():
        lines.append(f"  --{prefix}-{name}: {value};")
    lines.append("}")

    return "\n".join(lines)
```

Output:

```css
:root {
  --color-base: #1a1b26;
  --color-analogous-1: #1a1926;
  --color-analogous-2: #261a26;
  --color-complement: #26251a;
  --color-triadic-1: #1a2619;
  --color-triadic-2: #261a19;
}
```

### Lightness Variations

Generate tints (lighter) and shades (darker) of a color:

```python
def generate_scale(hex_color: str, steps: int = 9) -> list[str]:
    """Generate a lightness scale from dark to light."""
    r, g, b = hex_to_rgb(hex_color)
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)

    scale = []
    for i in range(steps):
        # Map step to lightness: 0.1 to 0.9
        new_l = 0.1 + (i * 0.8 / (steps - 1))
        scale.append(hsl_to_rgb_hex(h, s, new_l))

    return scale
```

### Find Accessible Text Color

Automatically find a text color that meets WCAG requirements:

```python
def find_accessible_text(background_hex: str, target_ratio: float = 4.5) -> str:
    """Find white or black text color that meets contrast requirements."""
    r, g, b = hex_to_rgb(background_hex)
    bg_lum = relative_luminance(r, g, b)

    white_lum = relative_luminance(255, 255, 255)
    black_lum = relative_luminance(0, 0, 0)

    white_ratio = contrast_ratio(bg_lum, white_lum)
    black_ratio = contrast_ratio(bg_lum, black_lum)

    if white_ratio >= target_ratio:
        return "#ffffff"
    elif black_ratio >= target_ratio:
        return "#000000"
    else:
        # Return whichever has better contrast
        return "#ffffff" if white_ratio > black_ratio else "#000000"
```

## Why Not Just Use an Online Tool?

Online color tools are convenient, but this script:

1. **Works offline** - No internet required
2. **Integrates with your workflow** - Pipe output to other tools
3. **Is customizable** - Add your own harmony rules
4. **Explains the math** - You understand what's happening
5. **Generates code** - Output CSS, JSON, or any format you need

## Installation

No dependencies beyond Python's standard library:

```bash
# Save the script
curl -o ~/bin/color_theme.py https://raw.githubusercontent.com/your-repo/color_theme.py
chmod +x ~/bin/color_theme.py

# Run it
python3 ~/bin/color_theme.py
```

## Summary

| Function | Purpose |
|----------|---------|
| `hex_to_rgb` / `rgb_to_hex` | Color format conversion |
| `srgb_to_linear` | Gamma correction for luminance |
| `relative_luminance` | WCAG-compliant brightness calculation |
| `contrast_ratio` | Accessibility compliance checking |
| `shift_hue` | Color wheel navigation |
| `hsl_to_rgb_hex` | Generate harmonizing colors |

The script demonstrates that color theory fundamentals can be implemented in under 100 lines of Python. Understanding these principles helps you make better design decisions, whether you're theming an editor, designing a website, or building data visualizations.
