#!/usr/bin/env python3
"""Generates Fadeo's app icon as SVG, using a real superellipse (not a CSS-style
rounded-rect) for the squircle, matching macOS icon proportions: the shape spans nearly
the full 1024 canvas, since macOS does not auto-mask app icons (unlike iOS), so the
squircle has to be baked into the artwork itself.

Regenerate: python3 scripts/gen-icon.py && rsvg-convert -w 1024 -h 1024 \
  assets/redesign/fadeo-icon.svg -o assets/redesign/fadeo-icon-1024.png
Then copy the PNG into assets/appicon/ and assets/logo/, and run scripts/make-assets.sh.

Requires librsvg for rasterizing (`brew install librsvg`).
"""
import math

CANVAS = 1024
N = 5.0  # Apple-style superellipse exponent

def squircle_points(cx, cy, half_w, half_h, n, steps=240):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = cx + (abs(ct) ** (2.0 / n)) * half_w * (1 if ct >= 0 else -1)
        y = cy + (abs(st) ** (2.0 / n)) * half_h * (1 if st >= 0 else -1)
        pts.append((x, y))
    return pts

def path_from_points(pts):
    d = f"M {pts[0][0]:.2f},{pts[0][1]:.2f} "
    d += " ".join(f"L {x:.2f},{y:.2f}" for x, y in pts[1:])
    d += " Z"
    return d

# Squircle: near edge-to-edge, matching real macOS icon proportion (~1000/1024)
margin = 14
half = (CANVAS - 2 * margin) / 2
cx = cy = CANVAS / 2
squircle_path = path_from_points(squircle_points(cx, cy, half, half, N))

# Waveform bars: tapering from tall (left-center) down to dots (right), like the original
# mark, redrawn with clean proportions and rounded caps.
bar_heights = [70, 150, 210, 260, 130, 100, 140, 180, 120, 80, 55, 34, 20, 12]
bar_width = 34
gap = 20
total_w = len(bar_heights) * bar_width + (len(bar_heights) - 1) * gap
start_x = cx - total_w / 2 + bar_width / 2
bars_svg = []
for i, h in enumerate(bar_heights):
    x = start_x + i * (bar_width + gap)
    y1 = cy - h / 2
    y2 = cy + h / 2
    r = bar_width / 2
    if h <= bar_width:
        # small dot
        bars_svg.append(f'<circle cx="{x:.2f}" cy="{cy:.2f}" r="{h/2:.2f}" fill="url(#barGrad)"/>')
    else:
        bars_svg.append(
            f'<rect x="{x - bar_width/2:.2f}" y="{y1:.2f}" width="{bar_width:.2f}" height="{h:.2f}" '
            f'rx="{r:.2f}" ry="{r:.2f}" fill="url(#barGrad)"/>'
        )

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <defs>
    <linearGradient id="bgGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#6B7C8E"/>
      <stop offset="55%" stop-color="#57697B"/>
      <stop offset="100%" stop-color="#485867"/>
    </linearGradient>
    <radialGradient id="sheen" cx="30%" cy="18%" r="75%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.16"/>
      <stop offset="45%" stop-color="#FFFFFF" stop-opacity="0.04"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="barGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#8BF0DF"/>
      <stop offset="100%" stop-color="#52D9C4"/>
    </linearGradient>
    <linearGradient id="innerShadow" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#000000" stop-opacity="0"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.10"/>
    </linearGradient>
  </defs>

  <path d="{squircle_path}" fill="url(#bgGrad)"/>
  <path d="{squircle_path}" fill="url(#sheen)"/>
  <path d="{squircle_path}" fill="url(#innerShadow)"/>

  <g>
    {''.join(bars_svg)}
  </g>
</svg>'''

with open("/Users/yashashwisinghania/Fadeo/assets/redesign/fadeo-icon.svg", "w") as f:
    f.write(svg)
print("SVG written")
