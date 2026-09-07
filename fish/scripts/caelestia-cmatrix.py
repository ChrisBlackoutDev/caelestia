#!/usr/bin/env python3
"""Caelestia-themed matrix rain for transparent terminals."""

from __future__ import annotations

import argparse
import json
import os
import random
import select
import shutil
import signal
import sys
import termios
import tty
from dataclasses import dataclass
from pathlib import Path


CHARS = tuple("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz@#$%&*+-=?/\\|_<>:;,.\"'()[]{}")
JAPANESE_CHARS = tuple("アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン")
DEFAULT_PALETTE = ("f9b7a5", "ffe1b2", "ffdb94", "ffa9ab", "f9e0da")
SCHEME_PATH = Path.home() / ".local/state/caelestia/scheme.json"


@dataclass
class Drop:
    x: int
    y: float
    speed: float
    length: int
    color_index: int


def hex_to_rgb(value: str) -> tuple[int, int, int] | None:
    value = (value or "").strip().lstrip("#")
    if len(value) != 6:
        return None
    try:
        return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return None


def blend(a: tuple[int, int, int], b: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(round(a[i] + (b[i] - a[i]) * amount) for i in range(3))


def fg(rgb: tuple[int, int, int], bold: bool = False) -> str:
    prefix = "1;" if bold else ""
    return f"\x1b[{prefix}38;2;{rgb[0]};{rgb[1]};{rgb[2]}m"


def load_palette() -> list[tuple[int, int, int]]:
    names = (
        "primary",
        "secondary",
        "tertiary",
        "teal",
        "peach",
        "pink",
        "mauve",
        "text",
    )
    values: list[str] = []
    try:
        with SCHEME_PATH.open(encoding="utf-8") as handle:
            colours = json.load(handle).get("colours", {})
        values.extend(str(colours.get(name, "")) for name in names)
    except (OSError, json.JSONDecodeError):
        pass
    values.extend(DEFAULT_PALETTE)

    palette: list[tuple[int, int, int]] = []
    for value in values:
        rgb = hex_to_rgb(value)
        if rgb and rgb not in palette:
            palette.append(rgb)
    return palette[:6] or [hex_to_rgb(DEFAULT_PALETTE[0])]  # type: ignore[list-item]


def make_drops(width: int, height: int, density: float, palette_size: int) -> list[Drop]:
    count = max(1, round(width * density))
    return [
        Drop(
            x=random.randrange(width),
            y=random.uniform(-height * 0.35, height),
            speed=random.uniform(0.45, 1.45),
            length=random.randint(max(8, height // 3), max(12, height * 3 // 4)),
            color_index=random.randrange(max(1, palette_size)),
        )
        for _ in range(count)
    ]


def reset_drop(drop: Drop, height: int, palette_size: int) -> None:
    drop.y = random.uniform(-drop.length, 0)
    drop.speed = random.uniform(0.45, 1.45)
    drop.length = random.randint(max(8, height // 3), max(12, height * 3 // 4))
    drop.color_index = random.randrange(max(1, palette_size))


def render(width: int, height: int, drops: list[Drop], palette: list[tuple[int, int, int]], chars: tuple[str, ...], bold: bool) -> str:
    cells: list[list[tuple[str, tuple[int, int, int], bool] | None]] = [[None for _ in range(width)] for _ in range(height)]
    dark = (0, 0, 0)
    accent = palette[0]

    for drop in drops:
        base = palette[drop.color_index % len(palette)]
        head = int(drop.y)
        for offset in range(drop.length):
            y = head - offset
            if y < 0 or y >= height:
                continue
            fade = 1 - offset / max(1, drop.length)
            color = blend(dark, base, 0.24 + 0.76 * fade)
            is_head = offset == 0
            if is_head:
                color = blend(base, accent, 0.35)
            cells[y][drop.x] = (random.choice(chars), color, bold or is_head)

    lines: list[str] = ["\x1b[H"]
    previous: tuple[int, int, int] | None = None
    previous_bold = False
    for row in cells:
        for cell in row:
            if cell is None:
                lines.append("\x1b[0m ")
                previous = None
                previous_bold = False
                continue
            char, color, cell_bold = cell
            if color != previous or cell_bold != previous_bold:
                lines.append(fg(color, cell_bold))
                previous = color
                previous_bold = cell_bold
            lines.append(char)
        lines.append("\x1b[0m\n")
        previous = None
        previous_bold = False
    return "".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="cmatrix",
        description="Caelestia-themed matrix rain with transparent background and wallpaper-derived gradients.",
        add_help=False,
    )
    parser.add_argument("-h", "-?", "--help", action="store_true")
    parser.add_argument("-V", "--version", action="store_true")
    parser.add_argument("-u", dest="delay", type=int, default=4)
    parser.add_argument("-b", dest="bold", action="store_true")
    parser.add_argument("-B", dest="all_bold", action="store_true")
    parser.add_argument("-n", dest="no_bold", action="store_true")
    parser.add_argument("-c", dest="japanese", action="store_true")
    parser.add_argument("-s", dest="screensaver", action="store_true")
    parser.add_argument("-a", "-f", "-l", "-L", "-o", "-x", "-m", "-r", "-C", dest="ignored", action="append", nargs="?")
    parser.add_argument("--stock", action="store_true")
    args, _unknown = parser.parse_known_args(argv)
    return args


def print_help() -> None:
    print("""Usage: cmatrix [-abBcfhlsmVx] [-u delay] [-C color] [--stock]

Caelestia fork default:
  transparent-background truecolor rain using ~/.local/state/caelestia/scheme.json

Useful options:
  -b, -B       brighter glyphs
  -c           use Japanese-style glyphs
  -n           disable bold glyphs
  -s           screensaver mode, exits on first keypress
  -u delay     update delay 0-10, default 4
  --stock      run /usr/bin/cmatrix instead
""")


def run_stock(argv: list[str]) -> int:
    os.execv("/usr/bin/cmatrix", ["cmatrix", *argv])
    return 127


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.stock:
        return run_stock([arg for arg in argv if arg != "--stock"])
    if args.help:
        print_help()
        return 0
    if args.version:
        print("Caelestia cmatrix 1.0")
        return 0
    if not sys.stdout.isatty() or not sys.stdin.isatty():
        return run_stock(argv)

    palette = load_palette()
    chars = JAPANESE_CHARS if args.japanese else CHARS
    bold = (args.bold or args.all_bold) and not args.no_bold
    delay = min(10, max(0, args.delay))
    frame_time = 0.018 + delay * 0.012
    density = 1.15
    running = True

    def stop(_signum: int, _frame: object) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    old_term = termios.tcgetattr(sys.stdin)
    try:
        tty.setcbreak(sys.stdin.fileno())
        width, height = shutil.get_terminal_size((80, 24))
        drops = make_drops(width, height, density, len(palette))
        sys.stdout.write("\x1b[?1049h\x1b[?25l\x1b[0m\x1b[2J")
        sys.stdout.flush()

        while running:
            new_width, new_height = shutil.get_terminal_size((80, 24))
            if (new_width, new_height) != (width, height):
                width, height = new_width, new_height
                drops = make_drops(width, height, density, len(palette))
                sys.stdout.write("\x1b[2J")

            sys.stdout.write(render(width, height, drops, palette, chars, bold))
            sys.stdout.flush()

            for drop in drops:
                drop.y += drop.speed
                if drop.y - drop.length > height:
                    reset_drop(drop, height, len(palette))

            ready, _, _ = select.select([sys.stdin], [], [], frame_time)
            if ready:
                key = os.read(sys.stdin.fileno(), 1)
                if not key or args.screensaver or key in (b"q", b"Q", b"\x03", b"\x1b"):
                    break
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term)
        sys.stdout.write("\x1b[0m\x1b[2J\x1b[?25h\x1b[?1049l")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
