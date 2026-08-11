"""Minimal CLI: `archdocs list-icons` and `archdocs render <script.py>`.

Diagram scripts written against this package are plain Python (see
examples/platform_stack.py) — `render` just executes the given file, so
you can equally run `python examples/platform_stack.py` directly. The CLI
exists mainly for `list-icons` and for a slightly friendlier error if
Graphviz's `dot` binary isn't on PATH.
"""

from __future__ import annotations

import argparse
import runpy
import shutil
import sys

from archdocs.icons import list_icons


def _check_graphviz() -> None:
    if shutil.which("dot") is None:
        print(
            "error: Graphviz's 'dot' binary isn't on your PATH.\n"
            "diagrams renders through Graphviz — it's a system dependency,\n"
            "not a pip package. Run install.sh, or install it directly:\n"
            "  macOS:  brew install graphviz\n"
            "  Debian/Ubuntu: sudo apt-get install graphviz\n",
            file=sys.stderr,
        )
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(prog="archdocs")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list-icons", help="Print every available icon key")

    render = sub.add_parser("render", help="Run a diagram script")
    render.add_argument("script", help="Path to a Python file that builds an Architecture()")

    args = parser.parse_args()

    if args.command == "list-icons":
        list_icons()
        return

    if args.command == "render":
        _check_graphviz()
        runpy.run_path(args.script, run_name="__main__")
        return


if __name__ == "__main__":
    main()
