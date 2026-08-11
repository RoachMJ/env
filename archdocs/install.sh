#!/usr/bin/env bash
# ------------------------------------------------------------------
# Bootstrap script for archdocs.
#
# What it does:
#   1. Installs Graphviz (system dependency — `diagrams` renders through
#      Graphviz's `dot` binary; this is NOT a pip package and is the
#      #1 reason a fresh diagrams install fails).
#   2. Creates a .venv in this directory.
#   3. Installs archdocs into it (editable, plus dev/test deps).
#   4. Validates the install by running the test suite and rendering the
#      example diagram — if either fails, prints the real error instead
#      of leaving you with a silently broken venv.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#
# Run this from the archdocs project root (same directory as pyproject.toml).
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() { printf "\n\033[1;32m==>\033[0m %s\n" "$1"; }
warn() { printf "\n\033[1;33m!!\033[0m %s\n" "$1"; }

if [[ ! -f "$SCRIPT_DIR/pyproject.toml" ]]; then
  echo "pyproject.toml not found — run this script from the archdocs project root." >&2
  exit 1
fi

# ------------------------------------------------------------------
# 1. Graphviz (system dependency)
# ------------------------------------------------------------------
OS="$(uname -s)"

if ! command -v dot >/dev/null 2>&1; then
  log "Installing Graphviz"
  if [[ "$OS" == "Darwin" ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      echo "Homebrew not found — install it first: https://brew.sh" >&2
      exit 1
    fi
    brew install graphviz
  elif [[ "$OS" == "Linux" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update
      # python3-venv/python3-pip are needed too — stock Debian/Ubuntu ships
      # a system python with ensurepip disabled, so `python3 -m venv`
      # fails outright without these ("ensurepip is disabled in
      # Debian/Ubuntu for the system python").
      sudo apt-get install -y graphviz python3-venv python3-pip
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y graphviz python3-pip
    else
      warn "Unrecognized package manager — install graphviz manually, then re-run."
      exit 1
    fi
  else
    echo "Unsupported OS: $OS" >&2
    exit 1
  fi
else
  log "Graphviz already installed ($(dot -V 2>&1))"
fi

# ------------------------------------------------------------------
# 2. Create the venv
# ------------------------------------------------------------------
if [[ ! -d "$SCRIPT_DIR/.venv" ]]; then
  log "Creating venv at .venv"
  python3 -m venv "$SCRIPT_DIR/.venv"
else
  log ".venv already exists — reusing it"
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/.venv/bin/activate"

# ------------------------------------------------------------------
# 3. Install archdocs (editable) + dev deps
# ------------------------------------------------------------------
log "Installing archdocs into the venv"
pip install --upgrade pip >/dev/null
pip install -e ".[dev]"

# ------------------------------------------------------------------
# 4. Validate — run tests + render the example diagram
# ------------------------------------------------------------------
validate() {
  log "Running test suite"
  pytest -q

  log "Rendering example diagram (examples/platform_stack.py)"
  python examples/platform_stack.py

  if [[ -f "output/platform_stack.png" ]]; then
    log "Rendered output/platform_stack.png — install looks healthy."
    return 0
  else
    warn "Test suite passed but no output/platform_stack.png was produced."
    return 1
  fi
}

if ! validate; then
  warn "Validation failed. Wiping the venv and retrying once from a clean state..."
  deactivate 2>/dev/null || true
  rm -rf "$SCRIPT_DIR/.venv" "$SCRIPT_DIR/output"
  python3 -m venv "$SCRIPT_DIR/.venv"
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.venv/bin/activate"
  pip install --upgrade pip >/dev/null
  pip install -e ".[dev]"

  if ! validate; then
    warn "Still failing after a clean reinstall. This is likely a real bug"
    warn "(e.g. an icon class that moved in your installed diagrams"
    warn "version) rather than a stale venv — run 'archdocs list-icons'"
    warn "inside the venv to see exactly which icons failed to load."
    exit 1
  fi
fi

log "Done. Activate with: source .venv/bin/activate"
log "Then try: archdocs list-icons"
log "      or: archdocs render examples/platform_stack.py"
