#!/usr/bin/env python3
"""Regenerate Nembra's single-size iOS app-icon variants.

Requires Pillow (`python3 -m pip install Pillow`). The artwork is intentionally
built from simple vector-like primitives so geometry and colors remain easy to
review and change without reverse-engineering raster output.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

try:
    from PIL import Image, ImageDraw
except ImportError as error:
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from error

SIZE = 1024
CENTERLINE = ((292, 724), (292, 300), (732, 724), (732, 300))
MARK_WIDTH = 104
ACCENT_BOUNDS = (711, 279, 753, 321)

VARIANTS = {
    "NembraAppIcon-default.png": {
        "mode": "RGB",
        "background": (23, 25, 29),
        "mark": (245, 247, 249),
        "accent": (88, 215, 135),
    },
    "NembraAppIcon-dark.png": {
        "mode": "RGBA",
        "background": (0, 0, 0, 0),
        "mark": (250, 251, 252, 255),
        "accent": (103, 228, 148, 255),
    },
    "NembraAppIcon-tinted.png": {
        "mode": "L",
        "background": 18,
        "mark": 241,
        "accent": 132,
    },
}


def draw_round_polyline(draw: ImageDraw.ImageDraw, points, fill, width: int) -> None:
    draw.line(points, fill=fill, width=width, joint="curve")
    radius = width // 2
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def render(variant: dict) -> Image.Image:
    image = Image.new(variant["mode"], (SIZE, SIZE), variant["background"])
    draw = ImageDraw.Draw(image)
    draw_round_polyline(draw, CENTERLINE, variant["mark"], MARK_WIDTH)
    draw.ellipse(ACCENT_BOUNDS, fill=variant["accent"])
    return image


def encoded_png_bytes(variant: dict) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    render(variant).save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def default_output_dir() -> Path:
    return (
        Path(__file__).resolve().parents[1]
        / "NembraApp"
        / "Resources"
        / "Assets.xcassets"
        / "AppIcon.appiconset"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=default_output_dir())
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if checked-in PNG bytes differ from regenerated artwork.",
    )
    args = parser.parse_args()

    if args.check:
        mismatches = []
        for filename, variant in VARIANTS.items():
            path = args.output / filename
            expected = encoded_png_bytes(variant)
            if not path.is_file() or path.read_bytes() != expected:
                mismatches.append(filename)
        if mismatches:
            print("App icon source mismatch: " + ", ".join(mismatches), file=sys.stderr)
            return 1
        print("Nembra app icon sources match checked-in PNGs.")
        return 0

    args.output.mkdir(parents=True, exist_ok=True)
    for filename, variant in VARIANTS.items():
        (args.output / filename).write_bytes(encoded_png_bytes(variant))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
