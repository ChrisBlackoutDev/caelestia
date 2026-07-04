#!/usr/bin/env python3
"""Generate a temporary cava config using the current Caelestia palette."""

from __future__ import annotations

import configparser
import json
import os
import tempfile
from pathlib import Path


CONFIG_PATH = Path.home() / ".config/cava/config"
SCHEME_PATH = Path.home() / ".local/state/caelestia/scheme.json"
FALLBACK_GRADIENT = (
    "ffd8be",
    "ffdb94",
    "e1df87",
    "f2b2f2",
    "ffa2bd",
    "ffbbc2",
    "ffa9ab",
    "faab9c",
)


def valid_hex(value: str) -> bool:
    value = value.strip().lstrip("#")
    return len(value) == 6 and all(char in "0123456789abcdefABCDEF" for char in value)


def load_gradient() -> list[str]:
    names = ("green", "teal", "sky", "sapphire", "blue", "lavender", "mauve", "maroon")
    try:
        with SCHEME_PATH.open(encoding="utf-8") as handle:
            colours = json.load(handle).get("colours", {})
    except (OSError, json.JSONDecodeError):
        colours = {}

    gradient: list[str] = []
    for name, fallback in zip(names, FALLBACK_GRADIENT, strict=True):
        colour = str(colours.get(name, fallback)).strip().lstrip("#")
        gradient.append(colour if valid_hex(colour) else fallback)
    return gradient


def load_config() -> configparser.ConfigParser:
    parser = configparser.ConfigParser(
        delimiters=("=",),
        comment_prefixes=("#", ";"),
        inline_comment_prefixes=(),
        strict=False,
    )
    parser.optionxform = str
    if CONFIG_PATH.exists():
        parser.read(CONFIG_PATH)
    return parser


def main() -> int:
    parser = load_config()
    if not parser.has_section("color"):
        parser.add_section("color")

    gradient = load_gradient()
    parser["color"]["gradient"] = "1"
    parser["color"]["gradient_count"] = str(len(gradient))
    for index, colour in enumerate(gradient, start=1):
        parser["color"][f"gradient_color_{index}"] = f"'#{colour}'"

    fd, path = tempfile.mkstemp(prefix="caelestia-cava-", suffix=".conf")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        parser.write(handle, space_around_delimiters=True)
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
