"""markitdown conversion CLI.

Invoked by the `markitdown-convert` Claude Code skill. Reads a file path or URL
and emits Markdown either to stdout or to the path given by -o/--output.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from markitdown import MarkItDown


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="convert",
        description="Convert a file or URL to Markdown via Microsoft markitdown.",
    )
    parser.add_argument("input", help="File path or URL (PDF/Word/Excel/PowerPoint/audio/YouTube).")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output Markdown file path. Defaults to stdout.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    md = MarkItDown()
    result = md.convert(args.input)
    text = result.text_content
    if args.output is None:
        sys.stdout.write(text)
        if not text.endswith("\n"):
            sys.stdout.write("\n")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
