#!/usr/bin/env python3
"""
merge_config_overlay.py — shared config-overlay merge tool for this
repo's "Local machine overlay" mechanism (see each profile's README,
"Local machine overlays"). Generic across any TOML or JSON tool
config, not tied to starship/codex/zed specifically — any future item
that ships a JSON or TOML config can reuse this the same way.

WHY THIS EXISTS: gitconfig, tmux.conf.local, nvim/init.lua, and zshrc
all get a per-machine overlay for free via a native include/source
directive, so their destination stays a plain symlink and a `git
pull` in this repo propagates instantly. TOML and JSON have no such
directive, so a config in either format can't be "included" — it has
to be MERGED into a real, regenerated file instead. That's what this
script does: read a tracked base config + an untracked local overlay,
deep-merge them (overlay wins on conflicts), and write the result to
the destination the real tool actually reads from.

Usage:
  merge_config_overlay.py --format {json,toml} --base BASE --overlay OVERLAY --dest DEST

Merge semantics: a plain recursive dict merge. For any key present in
both files, if both values are tables/objects they merge recursively;
otherwise the overlay's value wins outright, full stop. JSON
additionally follows RFC 7396 (JSON Merge Patch): a null value in the
overlay DELETES that key from the result. TOML has no null literal,
so a TOML overlay can only add or replace keys, never delete one the
base sets — comment it out in the base file itself if you need that.

TOML round-trip limitation, deliberately: this repo has no TOML
*writer* dependency (see the README section above for the full
tomlkit-vs-stdlib trade-off this decision came out of), so TOML
output is produced by the minimal hand-rolled serializer below, not
tomlkit. It handles top-level and nested `[section]` tables, strings
(including triple-quoted multi-line ones), booleans, ints, floats,
and arrays of scalars. Inline tables (`{a = 1}`) and dotted keys
(`a.b = 1`) parse fine and get re-serialized as ordinary `[section]`
blocks — valid, semantically identical TOML, just re-normalized to
one consistent style rather than preserving how the source file wrote
it. The one genuinely unsupported construct is an array-of-tables
(`[[x]]`, i.e. a TOML array whose elements are themselves tables) —
if either input file uses one, this script exits non-zero with a
clear message rather than silently producing a mangled file.
Comments from BOTH input files are NOT preserved in TOML output (the
real cost of skipping tomlkit) — the generated file gets one
explanatory header comment instead, pointing back at the two real
source files to edit.

JSON input may use `//` line comments (JSONC, e.g. Zed's own config
files) — stripped before parsing, outside of string literals. Output
is always plain JSON; comments aren't required for Zed (or anything
else reading JSON) to load a file back.
"""
import argparse
import json
import os
import re
import sys

try:
    import tomllib
except ImportError:  # Python < 3.11
    tomllib = None


def strip_jsonc_comments(text):
    """Strip // line comments outside of string literals. Good enough
    for this repo's own tracked files; not a general-purpose JSONC
    parser (doesn't handle /* */ block comments, which this repo's
    JSON files don't use anyway)."""
    out = []
    in_string = False
    escape = False
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def deep_merge(base, overlay, *, json_null_deletes=False):
    if not isinstance(base, dict) or not isinstance(overlay, dict):
        return overlay
    result = dict(base)
    for k, v in overlay.items():
        if json_null_deletes and v is None:
            result.pop(k, None)
            continue
        if k in result and isinstance(result[k], dict) and isinstance(v, dict):
            result[k] = deep_merge(result[k], v, json_null_deletes=json_null_deletes)
        else:
            result[k] = v
    return result


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.loads(strip_jsonc_comments(f.read()))


def load_toml(path):
    if tomllib is None:
        sys.exit(
            "merge_config_overlay: TOML merging needs Python 3.11+ (the "
            "stdlib tomllib module) — not available on this interpreter."
        )
    with open(path, "rb") as f:
        return tomllib.load(f)


TOML_UNSUPPORTED = (
    "merge_config_overlay: can't serialize the merged result back to "
    "TOML — the merged data now contains {what}, which this repo's "
    "hand-rolled TOML writer deliberately doesn't support (see this "
    "script's own docstring for why). Remove that construct from "
    "whichever of the base or overlay TOML file introduced it, or "
    "this overlay can't be merged."
)


def _toml_scalar(v, path_for_error):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        if "\n" in v:
            escaped = v.replace("\\", "\\\\")
            return f'"""{escaped}"""'
        escaped = v.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if isinstance(v, list):
        if any(isinstance(x, (dict, list)) for x in v):
            sys.exit(TOML_UNSUPPORTED.format(what="an array-of-tables (an array whose elements are themselves tables or arrays)"))
        return "[" + ", ".join(_toml_scalar(x, path_for_error) for x in v) + "]"
    sys.exit(TOML_UNSUPPORTED.format(what=f"a {type(v).__name__} value, which has no TOML representation"))


_BARE_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def _toml_key(k):
    """Bare keys in TOML are restricted to [A-Za-z0-9_-]+ — anything
    else (a key starting with $, containing a space, etc. — e.g.
    starship.toml's own "$schema") needs quoting."""
    if _BARE_KEY_RE.match(k):
        return k
    escaped = k.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _toml_header(section):
    """A dotted table header like a.b.c needs each segment quoted
    independently, not the whole joined string as one unit."""
    return ".".join(_toml_key(part) for part in section.split("."))


def dump_toml(data, path_for_error, _section=None):
    lines = []
    scalars = {k: v for k, v in data.items() if not isinstance(v, dict)}
    tables = {k: v for k, v in data.items() if isinstance(v, dict)}
    for k, v in scalars.items():
        lines.append(f"{_toml_key(k)} = {_toml_scalar(v, path_for_error)}")
    for k, v in tables.items():
        header = f"{_section}.{k}" if _section else k
        if lines and lines[-1] != "":
            lines.append("")
        lines.append(f"[{_toml_header(header)}]")
        lines.extend(dump_toml(v, path_for_error, _section=header))
    return lines


def main():
    ap = argparse.ArgumentParser(description="Merge a tracked base config with a local overlay (see this file's docstring).")
    ap.add_argument("--format", choices=["json", "toml"], required=True)
    ap.add_argument("--base", required=True, help="tracked config in this repo")
    ap.add_argument("--overlay", required=True, help="untracked local overlay file")
    ap.add_argument("--dest", required=True, help="where the real tool reads its config from")
    args = ap.parse_args()

    loader = load_json if args.format == "json" else load_toml
    try:
        base = loader(args.base)
        overlay = loader(args.overlay)
    except SystemExit:
        raise
    except Exception as e:
        sys.exit(f"merge_config_overlay: failed to parse {args.base} or {args.overlay}: {e}")

    merged = deep_merge(base, overlay, json_null_deletes=(args.format == "json"))

    tmp = args.dest + ".tmp"
    try:
        if args.format == "json":
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(
                    f"// GENERATED — do not edit directly. This is "
                    f"{os.path.basename(args.base)} merged with "
                    f"{os.path.basename(args.overlay)}, regenerated on "
                    f"your next new terminal. Edit one of those two "
                    f"instead.\n"
                )
                json.dump(merged, f, indent=2)
                f.write("\n")
        else:
            body = "\n".join(dump_toml(merged, args.base))
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(
                    f"# GENERATED — do not edit directly. This is "
                    f"{os.path.basename(args.base)} merged with "
                    f"{os.path.basename(args.overlay)}, regenerated on "
                    f"your next new terminal. Edit one of those two "
                    f"instead.\n\n"
                )
                f.write(body)
                f.write("\n")
        os.replace(tmp, args.dest)
    except SystemExit:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    except Exception as e:
        if os.path.exists(tmp):
            os.remove(tmp)
        sys.exit(f"merge_config_overlay: failed writing {args.dest}: {e}")


if __name__ == "__main__":
    main()
