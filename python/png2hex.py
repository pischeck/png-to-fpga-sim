#!/usr/bin/env python3
"""
png2hex.py - konwersja obrazu PNG na plik .hex (RGB888) dla FPGA.

Format wyjsciowy: czysty hex zgodny z Verilog $readmemh,
jedno 32-bitowe slowo na linie.

Wymaga: Pillow  ->  pip install pillow

Przyklad uzycia:
    python png2hex.py obraz.png            # -> obraz.hex
    python png2hex.py obraz.png rom.hex
"""

import argparse
import sys
from PIL import Image


def rgb_to_888(r, g, b):
    """Pakuje 8-bitowe skladowe RGB888 w 32-bitowa wartosc (0x00RRGGBB). """
    return (r << 16) | (g << 8) | b


def convert(in_path, out_path):
    """Zapisuje plik .hex; zwraca (szerokosc, wysokosc)."""
    img = Image.open(in_path).convert("RGB")
    width, height = img.size
    pixels = img.load()

    with open(out_path, "w") as f:
        for y in range(height):          # kolejnosc rastrowa: gora -> dol
            for x in range(width):       # lewo -> prawo
                r, g, b = pixels[x, y]
                value = rgb_to_888(r, g, b)
                f.write(f"{value:08X}\n")   # jedno 32-bitowe slowo na linie

    return width, height


def main():
    parser = argparse.ArgumentParser(
        description="Konwersja PNG -> .hex (RGB888, format $readmemh, jedno 32-bitowe slowo na linie)."
    )
    parser.add_argument("input", help="sciezka do pliku .png")
    parser.add_argument(
        "output",
        nargs="?",
        help="sciezka wyjsciowa .hex (domyslnie: nazwa wejscia z rozszerzeniem .hex)",
    )
    args = parser.parse_args()

    out_path = args.output or (args.input.rsplit(".", 1)[0] + ".hex")

    try:
        w, h = convert(args.input, out_path)
    except FileNotFoundError:
        print(f"Blad: nie znaleziono pliku '{args.input}'", file=sys.stderr)
        sys.exit(1)

    total_words = w * h
    # Stabilna, maszynowa linia kontraktu dla run.do (NIE zmieniac formatu):
    #   "DIMS <szerokosc> <wysokosc>"
    print(f"DIMS {w} {h}")
    # Czytelne dla czlowieka:
    print(f"Zapisano: {out_path}")
    print(f"Rozdzielczosc: {w} x {h} px")
    print(f"Liczba slow (= liczba linii): {total_words}  (po jednym 32-bitowym slowie na piksel)")


if __name__ == "__main__":
    main()
