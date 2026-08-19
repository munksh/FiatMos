#!/usr/bin/env python3
"""Generate the Fiat Mos launcher icon.

The mark: a tally cut into a dressed stone. Four strokes and the fifth struck
across them -- the oldest counting instrument there is, and the plainest way
to say "I have done this repeatedly" without needing any explanation. The
stone is what the repetitions are making.

Earlier attempts, kept as a warning: a worn stone step read as a bowl, a
falling drop read as a flame point-up and a map pin point-down, an oval read
as an olive, and an oval with a motion trail read as a spermatozoon. The
silhouette space is crowded. Four bars and a diagonal is one of the few marks
nothing else has claimed.


THE SHAPE
---------
The silhouette is Fiat Lux's, character for character -- see SHAPE below. It
is not a rounded square. A rounded square is the Android convention, and an
earlier version of this file drew one (rx=18, opaque corners), which is
exactly why the icon looked foreign on a Sailfish launcher.

The Sailfish shape is ASYMMETRIC: top-left and bottom-right are rounded at
full radius (42.7 on an 86 canvas, half the width), while top-right and
bottom-left are square but for a 1.423 hairline. That asymmetry is the whole
character of the shape, and it is why no symmetric approximation -- rounded
square, superellipse -- can be made right by tuning a radius. Everything
outside the path is transparent.


THE STONE IS THE SAME SHAPE, INSET
----------------------------------
Not a rounded rectangle sitting inside a silhouette -- that reads as a label
stuck on a badge, because its corners disagree with the corners around them.
The stone is the silhouette itself, scaled down about the centre, so every
corner of the cream follows the corner of the dark outside it. One shape
twice, and the icon reads as one object.

MARGIN is the only number worth touching. It sets how much dark ground is
left around the stone, and everything else -- bar width, bar spacing, the
length and weight of the diagonal -- is a fraction of the remaining box, so
the mark rescales with it instead of having to be re-measured.

The tally stays INSIDE the stone: the strokes are clipped to it, and the
diagonal has round caps and stops short of the edge. An earlier version ran
the diagonal out past the silhouette and let the clip cut it square. It was a
nice idea and it looked like a mistake.

Run:   python3 tools/make_icon.py
Needs: pip install cairosvg
"""
import os

import cairosvg

BG    = "#1E1A12"   # house ground, shared with Fiat Lux and Fiat Vox
STONE = "#F4EED8"   # house cream
GREEN = "#4E6B3A"   # Fiat Mos accent, same value as FiatMosTheme

SIZES = (86, 108, 128, 172)

# Dark ground left around the stone, on the 86 canvas. The one dial.
MARGIN = 17

# The family silhouette. Copied verbatim from Fiat Lux so the two cannot
# drift apart -- if this ever changes, it changes in both.
SHAPE = ("M84.277,0.3H43C19.417,0.3,0.3,19.418,0.3,43v41.277c0,0.786,0.637,1.423,1.423,1.423H43"
         "c23.583,0,42.7-19.118,42.7-42.7V1.723C85.7,0.937,85.063,0.3,84.277,0.3z")

# The path's own box is 0.3 .. 85.7, not 0 .. 86, so the inset has to be
# worked out from 85.4 rather than from the canvas.
scale = (86.0 - 2 * MARGIN) / 85.4
offset = MARGIN - 0.3 * scale
inner = 86.0 - 2 * MARGIN


def at(f):
    """A fraction of the stone's box, in canvas coordinates."""
    return MARGIN + inner * f


bar_w = inner * 0.105
bar_top, bar_bottom = at(0.24), at(0.76)
BARS = "".join(
    '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="%s"/>'
    % (at(0.16) + i * inner * 0.20, bar_top, bar_w, bar_bottom - bar_top, bar_w / 2, BG)
    for i in range(4)
)

SVG = f'''<?xml version="1.0" encoding="utf-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" x="0px" y="0px"
     width="86px" height="86px" viewBox="0 0 86 86" xml:space="preserve">
  <defs>
    <clipPath id="outer">
      <path d="{SHAPE}"/>
    </clipPath>
    <!-- The same path, inset. Used both to fill the stone and to clip the
         tally to it, so a stroke can never cross the cream edge. -->
    <clipPath id="stone">
      <g transform="translate({offset:.4f},{offset:.4f}) scale({scale:.5f})">
        <path d="{SHAPE}"/>
      </g>
    </clipPath>
  </defs>

  <g clip-path="url(#outer)">
    <path d="{SHAPE}" fill="{BG}"/>

    <g transform="translate({offset:.4f},{offset:.4f}) scale({scale:.5f})">
      <path d="{SHAPE}" fill="{STONE}"/>
    </g>

    <g clip-path="url(#stone)">
      {BARS}
      <line x1="{at(0.15):.2f}" y1="{at(0.79):.2f}"
            x2="{at(0.85):.2f}" y2="{at(0.23):.2f}"
            stroke="{GREEN}" stroke-width="{inner * 0.105:.2f}" stroke-linecap="round"/>
    </g>
  </g>
</svg>
'''

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
svg_path = os.path.join(here, "fiatmos-icon.svg")

with open(svg_path, "w") as f:
    f.write(SVG)

for size in SIZES:
    out_dir = os.path.join(root, "icons", "%dx%d" % (size, size))
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "harbour-fiatmos.png")
    cairosvg.svg2png(url=svg_path, write_to=out,
                     output_width=size, output_height=size)
    print("wrote", out)