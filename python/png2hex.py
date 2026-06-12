#!/usr/bin/env python3
"""
png2hex.py - konwersja obrazu PNG na plik .hex (RGB565) dla FPGA.

Format wyjsciowy: czysty hex zgodny z Verilog $readmemh,
jedno 16-bitowe slowo na linie (cztery cyfry hex). Kazdy piksel = jedno slowo (RGB565).

Wymaga: Pillow  ->  pip install pillow

Przyklad uzycia:
    python png2hex.py obraz.png            # -> obraz.hex
    python png2hex.py obraz.png rom.hex
"""

import argparse
import sys
from PIL import Image


def rgb_to_565(r, g, b):
    """Zamienia 8-bitowe skladowe RGB888 na 16-bitowa wartosc RGB565."""
    r5 = (r >> 3) & 0x1F
    g6 = (g >> 2) & 0x3F
    b5 = (b >> 3) & 0x1F
    return (r5 << 11) | (g6 << 5) | b5


def convert(in_path, out_path):
    """Zapisuje plik .hex; zwraca (szerokosc, wysokosc)."""
    img = Image.open(in_path).convert("RGB")
    width, height = img.size
    pixels = img.load()

    with open(out_path, "w") as f:
        for y in range(height):          # kolejnosc rastrowa: gora -> dol
            for x in range(width):       # lewo -> prawo
                r, g, b = pixels[x, y]
                value = rgb_to_565(r, g, b)
                f.write(f"{value:04X}\n")   # jedno 16-bitowe slowo na linie

    return width, height


def main():
    parser = argparse.ArgumentParser(
        description="Konwersja PNG -> .hex (RGB565, format $readmemh, jedno 16-bitowe slowo na linie)."
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
    print(f"Liczba slow (= liczba linii): {total_words}  (po jednym 16-bitowym slowie na piksel)")


if __name__ == "__main__":
    main()
