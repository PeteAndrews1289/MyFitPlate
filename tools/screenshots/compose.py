#!/usr/bin/env python3
"""App Store screenshot compositor for MyFitPlate.

Reads raw device captures from raw/ and the captions from shots.json, renders each onto
a brand-green canvas (the Weekly Recap share-card green, so the listing and the in-app
share assets match) with an SF Rounded headline, and writes App Store-sized PNGs to
output/.

Usage:
    python3 compose.py                 # 6.9-inch set (1320x2868)
    python3 compose.py --size 1284x2778  # 6.5-inch set
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BRAND_BG = (23, 56, 41)          # the recap share-card deep green
HEADLINE_COLOR = (255, 255, 255)
SUBLINE_COLOR = (255, 255, 255, 178)  # ~70% white
FONT_PATH = "/System/Library/Fonts/SFNSRounded.ttf"

HERE = Path(__file__).parent
RAW = HERE / "raw"
OUTPUT = HERE / "output"


def rounded_screenshot(capture: Image.Image, width: int, radius: int) -> Image.Image:
    """Scale a capture to `width`, round its corners, add a hairline border."""
    ratio = width / capture.width
    resized = capture.resize((width, int(capture.height * ratio)), Image.LANCZOS)

    mask = Image.new("L", resized.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *resized.size], radius=radius, fill=255)

    framed = Image.new("RGBA", resized.size, (0, 0, 0, 0))
    framed.paste(resized, (0, 0), mask)
    ImageDraw.Draw(framed).rounded_rectangle(
        [0, 0, resized.width - 1, resized.height - 1],
        radius=radius, outline=(255, 255, 255, 60), width=3,
    )
    return framed


def compose(shot: dict, size: tuple[int, int]) -> Image.Image | None:
    source = RAW / shot["file"]
    if not source.exists():
        print(f"  skip {shot['file']} (not found in raw/)")
        return None

    width, height = size
    canvas = Image.new("RGBA", size, BRAND_BG + (255,))
    draw = ImageDraw.Draw(canvas)

    headline_font = ImageFont.truetype(FONT_PATH, int(width * 0.062))
    subline_font = ImageFont.truetype(FONT_PATH, int(width * 0.030))

    margin = int(width * 0.075)
    y = int(height * 0.045)

    for line in shot["headline"].split("\n"):
        draw.text((margin, y), line, font=headline_font, fill=HEADLINE_COLOR)
        y += int(headline_font.size * 1.14)

    y += int(height * 0.008)
    draw.text((margin, y), shot["subline"], font=subline_font, fill=SUBLINE_COLOR)
    y += int(subline_font.size * 1.5) + int(height * 0.028)

    capture = Image.open(source).convert("RGBA")
    shot_width = int(width * 0.80)
    framed = rounded_screenshot(capture, shot_width, radius=int(width * 0.055))
    canvas.paste(framed, ((width - shot_width) // 2, y), framed)

    return canvas.convert("RGB")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", default="1320x2868", help="WIDTHxHEIGHT (default 6.9-inch)")
    args = parser.parse_args()
    width, height = (int(v) for v in args.size.split("x"))

    manifest = json.loads((HERE / "shots.json").read_text())
    OUTPUT.mkdir(exist_ok=True)

    rendered = 0
    for index, shot in enumerate(manifest["shots"], start=1):
        image = compose(shot, (width, height))
        if image:
            out = OUTPUT / f"appstore-{index:02d}-{width}x{height}.png"
            image.save(out)
            print(f"  wrote {out.name}")
            rendered += 1

    print(f"{rendered} of {len(manifest['shots'])} shots rendered.")
    return 0 if rendered else 1


if __name__ == "__main__":
    sys.exit(main())
