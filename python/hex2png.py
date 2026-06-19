#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hex2png.py - reverse of png2hex.py: reconstructs a PNG image from a .hex file (RGB888).

Input file: one 32-bit word per line, raster order (top -> bottom, left -> right).
The .hex file does not store resolution, so width must be provided manually;
height is calculated from the number of words.

Compatible with Python 2.7 and 3.x.

Requires: Pillow  ->  pip install pillow

Usage example:
    python3 hex2png.py image.hex 128                 # width 128, height auto
    python3 hex2png.py image.hex 128 preview.png
    python3 hex2png.py image.hex 128 --height 64
"""

import argparse
import sys
from PIL import Image


def val32_to_rgb888(value):
    """Extracts (R, G, B) components from a 32-bit value 0x00RRGGBB."""
    r = (value >> 16) & 0xFF
    g = (value >> 8) & 0xFF
    b = value & 0xFF
    return (r, g, b)


def read_words(in_path):
    """Reads a list of 32-bit values from a .hex file (ignores empty lines, //, and @)."""
    words = []
    with open(in_path, "r") as f:
        for line in f:
            token = line.strip()
            if not token or token.startswith("//") or token.startswith("@"):
                continue
            words.append(int(token, 16))
    return words


def main():
    parser = argparse.ArgumentParser(
        description="Convert .hex (RGB888, 32-bit word per line) to PNG."
    )
    parser.add_argument("input", help="path to the input .hex file")
    parser.add_argument("width", type=int, help="image width in pixels")
    parser.add_argument(
        "output",
        nargs="?",
        help="output .png path (default: input name with .png extension)",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=None,
        help="image height (default: calculated from word count / width)",
    )
    args = parser.parse_args()

    if args.width <= 0:
        sys.stderr.write("Error: width must be positive\n")
        sys.exit(1)

    try:
        words = read_words(args.input)
    except IOError:
        sys.stderr.write("Error: cannot open file '{0}'\n".format(args.input))
        sys.exit(1)
    except ValueError:
        sys.stderr.write("Error: file contains a line that is not a valid hex number\n")
        sys.exit(1)

    n = len(words)
    if n == 0:
        sys.stderr.write("Error: file contains no data\n")
        sys.exit(1)

    if args.height is None:
        if n % args.width != 0:
            sys.stderr.write(
                "Error: word count ({0}) is not divisible by width ({1}). "
                "Provide a valid width or specify --height.\n".format(n, args.width)
            )
            sys.exit(1)
        height = n // args.width
    else:
        height = args.height
        if height <= 0:
            sys.stderr.write("Error: height must be positive\n")
            sys.exit(1)
        if args.width * height > n:
            sys.stderr.write(
                "Error: width x height ({0}) exceeds the number of words in the file ({1}).\n".format(
                    args.width * height, n
                )
            )
            sys.exit(1)

    out_path = args.output or (args.input.rsplit(".", 1)[0] + ".png")

    img = Image.new("RGB", (args.width, height))
    px = img.load()
    i = 0
    for y in range(height):           # raster order: top -> bottom
        for x in range(args.width):   # left -> right
            px[x, y] = val32_to_rgb888(words[i])
            i += 1
    img.save(out_path)

    print("Saved: {0}".format(out_path))
    print("Resolution: {0} x {1} px".format(args.width, height))
    print("Words read: {0}".format(n))


if __name__ == "__main__":
    main()