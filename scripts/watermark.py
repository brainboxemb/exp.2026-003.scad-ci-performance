#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--text", default="SCAD CI performance benchmark")
    args = parser.parse_args()

    image = Image.open(args.image).convert("RGBA")
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), args.text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    pad_x = 12
    pad_y = 8
    margin = 16
    x1 = image.width - margin
    y1 = image.height - margin
    x0 = x1 - text_w - 2 * pad_x
    y0 = y1 - text_h - 2 * pad_y

    draw.rounded_rectangle((x0, y0, x1, y1), radius=8, fill=(0, 0, 0, 150))
    draw.text((x0 + pad_x, y0 + pad_y), args.text, font=font, fill=(255, 255, 255, 230))

    Image.alpha_composite(image, overlay).convert("RGB").save(args.image)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
