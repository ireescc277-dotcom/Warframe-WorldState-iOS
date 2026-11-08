"""Generate the 1024pt app icon.

iOS masks icons with a superellipse, so the artwork is full-bleed with no
transparency and no rounded corners of its own. Everything that must survive
at 60pt is one thick stroke plus one solid shape.

Run: python scripts/make_icon.py
"""

import os

from PIL import Image, ImageDraw

SIZE = 1024
OUT = os.path.join(
    "WarframeWatch", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png"
)

BG_TOP = (18, 27, 38)
BG_BOTTOM = (4, 7, 12)
GOLD = (234, 183, 96)
GOLD_DIM = (92, 71, 38)

RING_RADIUS = 300
RING_WIDTH = 56
# The ring is 300° of gold plus a 60° depleted tail, so it reads as a
# countdown rather than a broken circle.
GOLD_FROM, GOLD_TO = 60, 360
# One degree of overlap at each join, otherwise the two arc calls leave a
# hairline of background showing through.
DIM_FROM, DIM_TO = 0, 61


def gradient() -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), BG_TOP)
    px = img.load()
    for y in range(SIZE):
        t = (y / (SIZE - 1)) ** 0.8
        c = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        for x in range(SIZE):
            px[x, y] = c
    return img


def main() -> None:
    img = gradient()
    d = ImageDraw.Draw(img)
    cx = cy = SIZE / 2
    box = [cx - RING_RADIUS, cy - RING_RADIUS, cx + RING_RADIUS, cy + RING_RADIUS]

    d.arc(box, DIM_FROM, DIM_TO, fill=GOLD_DIM, width=RING_WIDTH)
    d.arc(box, GOLD_FROM, GOLD_TO, fill=GOLD, width=RING_WIDTH)

    # Void relic at the centre: a tall diamond, the same gold as the ring.
    half_h, half_w = 104, 74
    d.polygon(
        [(cx, cy - half_h), (cx + half_w, cy), (cx, cy + half_h), (cx - half_w, cy)],
        fill=GOLD,
    )

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG", optimize=True)
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
