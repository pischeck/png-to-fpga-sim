#!/usr/bin/env python3
"""
png2hex.py - convert PNG image to .hex file (RGB888) for FPGA.

Output format: clean hex compatible with Verilog $readmemh,
one 32-bit word per line.

Requires: Pillow  ->  pip install pillow

Usage example:
    python png2hex.py image.png             # -> image.hex
    python png2hex.py image.png rom.hex
"""

import argparse
import sys
from PIL import Image


def rgb_to_888(r, g, b):
    """Packs 8-bit RGB888 components into a 32-bit value (0x00RRGGBB)."""
    return (r << 16) | (g << 8) | b


def convert(in_path, out_path):
    """Saves the .hex file; returns (width, height)."""
    img = Image.open(in_path).convert("RGB")
    width, height = img.size
    pixels = img.load()

    with open(out_path, "w") as f:
        for y in range(height):          # raster order: top -> bottom
            for x in range(width):       # left -> right
                r, g, b = pixels[x, y]
                value = rgb_to_888(r, g, b)
                f.write(f"{value:08X}\n")   # one 32-bit word per line

    return width, height


def main():
    parser = argparse.ArgumentParser(
        description="Convert PNG -> .hex (RGB888, $readmemh format, one 32-bit word per line)."
    )
    parser.add_argument("input", help="path to the input .png file")
    parser.add_argument(
        "output",
        nargs="?",
        help="output .hex path (default: input name with .hex extension)",
    )
    args = parser.parse_args()

    out_path = args.output or (args.input.rsplit(".", 1)[0] + ".hex")

    try:
        w, h = convert(args.input, out_path)
    except FileNotFoundError:
        print(f"Error: file not found '{args.input}'", file=sys.stderr)
        sys.exit(1)

    total_words = w * h
    # Stable, machine-readable contract line for run.do (DO NOT change format):
    #   "DIMS <width> <height>"
    print(f"DIMS {w} {h}")
    # Human-readable info:
    print(f"Saved: {out_path}")
    print(f"Resolution: {w} x {h} px")
    print(f"Total words (= number of lines): {total_words}  (one 32-bit word per pixel)")


if __name__ == "__main__":
    main()