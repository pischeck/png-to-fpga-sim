#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hex2png.py - odwrotnosc png2hex.py: rekonstrukcja obrazu PNG z pliku .hex (RGB565).

Plik wejsciowy: jedno 16-bitowe slowo na linie (cztery cyfry hex), kolejnosc rastrowa
(gora -> dol, lewo -> prawo). Plik .hex nie przechowuje rozdzielczosci,
wiec szerokosc trzeba podac recznie; wysokosc liczy sie z liczby slow.

UWAGA: konwersja RGB565 jest stratna, wiec odzyskane kolory moga sie nieznacznie
roznic od oryginalu - to normalne, a nie blad.

Skladnia zgodna z Python 2.7 oraz 3.x.

Wymaga: Pillow  ->  pip install pillow

Przyklad uzycia:
    python3 hex2png.py obraz.hex 128                 # szerokosc 128, wysokosc auto
    python3 hex2png.py obraz.hex 128 podglad.png
    python3 hex2png.py obraz.hex 128 --height 64

    3617
"""

import argparse
import sys
from PIL import Image


def rgb565_to_888(value):
    """Rozwija 16-bitowa wartosc RGB565 na trojke (R, G, B) w skali 0..255."""
    r5 = (value >> 11) & 0x1F
    g6 = (value >> 5) & 0x3F
    b5 = value & 0x1F
    # replikacja najstarszych bitow na mlodsze daje pelny zakres 0..255
    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g6 << 2) | (g6 >> 4)
    b8 = (b5 << 3) | (b5 >> 2)
    return (r8, g8, b8)


def read_words(in_path):
    """Wczytuje liste 16-bitowych wartosci z pliku .hex (ignoruje puste linie, // oraz @)."""
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
        description="Konwersja .hex (RGB565, 16-bitowe slowo na linie) -> PNG."
    )
    parser.add_argument("input", help="sciezka do pliku .hex")
    parser.add_argument("width", type=int, help="szerokosc obrazu w pikselach")
    parser.add_argument(
        "output",
        nargs="?",
        help="sciezka wyjsciowa .png (domyslnie: nazwa wejscia z rozszerzeniem .png)",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=None,
        help="wysokosc (domyslnie liczona z liczby slow / szerokosc)",
    )
    args = parser.parse_args()

    if args.width <= 0:
        sys.stderr.write("Blad: szerokosc musi byc dodatnia\n")
        sys.exit(1)

    try:
        words = read_words(args.input)
    except IOError:
        sys.stderr.write("Blad: nie mozna otworzyc pliku '{0}'\n".format(args.input))
        sys.exit(1)
    except ValueError:
        sys.stderr.write("Blad: plik zawiera linie ktora nie jest poprawna liczba hex\n")
        sys.exit(1)

    n = len(words)
    if n == 0:
        sys.stderr.write("Blad: plik nie zawiera zadnych danych\n")
        sys.exit(1)

    if args.height is None:
        if n % args.width != 0:
            sys.stderr.write(
                "Blad: liczba slow ({0}) nie dzieli sie przez szerokosc ({1}). "
                "Podaj poprawna szerokosc lub --height.\n".format(n, args.width)
            )
            sys.exit(1)
        height = n // args.width
    else:
        height = args.height
        if height <= 0:
            sys.stderr.write("Blad: wysokosc musi byc dodatnia\n")
            sys.exit(1)
        if args.width * height > n:
            sys.stderr.write(
                "Blad: szerokosc x wysokosc ({0}) przekracza liczbe slow w pliku ({1}).\n".format(
                    args.width * height, n
                )
            )
            sys.exit(1)

    out_path = args.output or (args.input.rsplit(".", 1)[0] + ".png")

    img = Image.new("RGB", (args.width, height))
    px = img.load()
    i = 0
    for y in range(height):           # kolejnosc rastrowa: gora -> dol
        for x in range(args.width):   # lewo -> prawo
            px[x, y] = rgb565_to_888(words[i])
            i += 1
    img.save(out_path)

    print("Zapisano: {0}".format(out_path))
    print("Rozdzielczosc: {0} x {1} px".format(args.width, height))
    print("Wczytano slow: {0}".format(n))


if __name__ == "__main__":
    main()