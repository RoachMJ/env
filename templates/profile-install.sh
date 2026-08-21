#!/usr/bin/env bash
# ------------------------------------------------------------------
# TEMPLATE profile installer — copy this into a new profile repo's
# install.sh and start replacing the example items with your own. This
# file intentionally installs nothing real; it exists to show the
# checklist/symlink/package-install pattern the bootstrap repo
# (env/install.sh) expects a profile's own install.sh to follow,
# without wiring in any specific person's tools.
#
# What a profile repo is: wherever you put the actual environment you
# want reproduced on a new machine — editor config, shell setup,
# terminal tools, credential handling, small helper scripts. The
# bootstrap repo clones this repo and then just runs this file; it
# doesn't know or care what's inside.
#
# Shows an interactive numbered checklist of this profile's
# components ("items"), installs whatever packages each selected item
# needs (OS-diagnostic: Homebrew on macOS, apt or dnf on Linux), and
# symlinks that item's config file(s) into place. Add a new item by:
#   1. Adding its key to ITEM_KEYS and a one-line description to
#      ITEM_LABELS (same index).
#   2. Adding an `if is_selected <key>; then ... fi` block in the
#      "Item implementations" section below.
#
# Items in this template (replace these):
#   example-symlink   Just symlinks one config file — the simplest
#                     possible item. No packages, nothing to install.
#   example-package   Installs a package via install_pkgs, then
#                     symlinks its config file.
#   example-script    Delegates to its own install.sh in a subfolder —
#                     use this shape for anything complex enough to
#                     want its own multi-step installer (a Python venv,
#                     a build step, etc.), matching this repo's
#                     archdocs/ and mr-metadata/ pattern.
#
# Usage:
#   ./install.sh                    interactive checklist (default)
#   ./install.sh --all               everything, no prompt
#   ./install.sh --only=key1,key2   just these items (comma list of the keys above)
#   ./install.sh --help             show this
#
# If stdin isn't a terminal and neither --all nor --only was given,
# this installs everything and prints a warning rather than hanging on
# the checklist prompt.
#
# SYMLINKS, NOT COPIES: every config file an item installs should be
# symlinked back into this folder rather than copied, so a plain `git
# pull` here updates every deployed config immediately — no
# re-running install.sh needed. Re-running is only for adding items
# you didn't install the first time or fixing a symlink that got
# clobbered. link_file() (below, from the bootstrap repo's
# lib/common.sh) is idempotent: an already-correct symlink is left
# alone, a symlink pointing somewhere else gets re-pointed, and only a
# genuine pre-existing real file/directory gets backed up (timestamped)
# before being replaced with a symlink.
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="REPLACE_ME"   # e.g. "personal", "professional", "work", "home"
PROFILE_DIR="$SCRIPT_DIR"

# Shared log/warn/link_file/detect_os/install_pkgs helpers live in the
# bootstrap repo's env/lib/common.sh, a sibling of this profile
# folder (this repo names its bootstrap folder "env" and its two
# profile folders "env-personal"/"env-professional" — rename to
# whatever fits your own fork, just keep this relative path in sync).
# Falls back to a minimal inline copy if this script is ever run
# standalone, without the bootstrap repo alongside it — copy this
# fallback block verbatim from env-personal/install.sh or
# env-professional/install.sh in this same bootstrap repo if you need
# the exact current version; kept short here since it's just a safety
# net.
COMMON_LIB="$SCRIPT_DIR/../env/lib/common.sh"
if [[ -f "$COMMON_LIB" ]]; then
  # shellcheck source=../env/lib/common.sh
  source "$COMMON_LIB"
else
  echo "Note: lib/common.sh not found (running standalone) — using a" >&2
  echo "built-in fallback with less functionality than the real one." >&2
  log() { printf "\n\033[1;32m==>\033[0m %s\n" "$1"; }
  warn() { printf "\n\033[1;33m!!\033[0m %s\n" "$1"; }
  ENV_CONFIG_DIR="${ENV_CONFIG_DIR:-$HOME/.env-config/backups}"
  link_file() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    ln -sf "$src" "$dest"
  }
  detect_os() {
    OS_KERNEL="$(uname -s)"
    PKG_MGR=""
    [[ "$OS_KERNEL" == "Linux" ]] && command -v apt-get >/dev/null 2>&1 && PKG_MGR="apt"
  }
  install_pkgs() {
    # || true on both branches matters under this script's `set -e`: a
    # bare failing command here (a renamed formula, a network blip)
    # would otherwise kill this whole script instead of just that one
    # package install — see lib/common.sh's real install_pkgs/
    # install_pkg_one for the fuller version of this same idea (per-
    # package pre-existence check + manifest recording), which any real
    # profile install.sh should use instead of this minimal stub.
    local mac_pkgs="$1" apt_pkgs="$2"
    case "$OS_KERNEL" in
      Darwin) [[ -n "$mac_pkgs" ]] && { brew install $mac_pkgs || echo "warn: brew install failed for: $mac_pkgs" >&2; } ;;
      Linux) [[ -n "$apt_pkgs" ]] && { sudo apt-get install -y $apt_pkgs || echo "warn: apt-get install failed for: $apt_pkgs" >&2; } ;;
    esac
  }
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: ./install.sh [--all | --only=key1,key2,...]"
  echo
  echo "  (no flags)          interactive checklist"
  echo "  --all               install every item"
  echo "  --only=key1,key2    install just these items (comma list)"
  echo
  echo "Keys: example-symlink example-package example-script"
  exit 0
fi

# ------------------------------------------------------------------
# Selectable items + checkbox menu — this whole block is generic,
# copy it as-is into a new profile repo.
# ------------------------------------------------------------------
ITEM_KEYS=(example-symlink example-package example-script)
ITEM_LABELS=(
  "Example: symlink one config file, nothing to install"
  "Example: install a package, then symlink its config"
  "Example: delegate to a subfolder's own install.sh"
)
SELECTED=()
for _k in "${ITEM_KEYS[@]}"; do SELECTED+=(1); done # default: everything on

is_selected() { # $1 = item key
  local i key
  key="$1"
  for i in "${!ITEM_KEYS[@]}"; do
    if [[ "${ITEM_KEYS[$i]}" == "$key" ]]; then
      [[ "${SELECTED[$i]}" == "1" ]] && return 0 || return 1
    fi
  done
  return 1
}

print_menu() {
  echo
  echo "Select what to install — nothing outside this list gets touched:"
  local i mark
  for i in "${!ITEM_KEYS[@]}"; do
    mark=" "
    [[ "${SELECTED[$i]}" == "1" ]] && mark="x"
    printf "  %d) [%s] %s\n" "$((i + 1))" "$mark" "${ITEM_LABELS[$i]}"
  done
  echo
  echo "Numbers toggle (space-separated, e.g. '1 3'), 'a' = all, 'n' = none, 'd' = done, 'q' = quit"
}

run_menu() {
  local reply tok idx
  while true; do
    print_menu
    read -r -p "> " reply || { echo; echo "Aborted — nothing installed."; exit 0; }
    case "$reply" in
      d | D) break ;;
      q | Q) echo "Aborted — nothing installed."; exit 0 ;;
      a | A) for idx in "${!SELECTED[@]}"; do SELECTED[$idx]=1; done ;;
      n | N) for idx in "${!SELECTED[@]}"; do SELECTED[$idx]=0; done ;;
      "") : ;;
      *)
        for tok in $reply; do
          if [[ "$tok" =~ ^[0-9]+$ ]] && ((tok >= 1 && tok <= ${#ITEM_KEYS[@]})); then
            idx=$((tok - 1))
            if [[ "${SELECTED[$idx]}" == "1" ]]; then SELECTED[$idx]=0; else SELECTED[$idx]=1; fi
          fi
        done
        ;;
    esac
  done
}

ONLY=""
ALL=0
for arg in "$@"; do
  case "$arg" in
    --all) ALL=1 ;;
    --only=*) ONLY="${arg#--only=}" ;;
  esac
done

if [[ "$ALL" == "1" ]]; then
  : # SELECTED already defaults to all-on
elif [[ -n "$ONLY" ]]; then
  for idx in "${!SELECTED[@]}"; do SELECTED[$idx]=0; done
  IFS=',' read -ra want <<<"$ONLY"
  for key in "${want[@]}"; do
    for i in "${!ITEM_KEYS[@]}"; do
      [[ "${ITEM_KEYS[$i]}" == "$key" ]] && SELECTED[$i]=1
    done
  done
elif [[ -t 0 ]]; then
  run_menu
else
  warn "No TTY on stdin and neither --all nor --only was given — installing everything."
fi

detect_os
log "Profile: $PROFILE — detected OS: $OS_KERNEL${PKG_MGR:+ ($PKG_MGR)}"

# ------------------------------------------------------------------
# Item implementations — replace these with your own.
# ------------------------------------------------------------------

# --- example-symlink ------------------------------------------------
# The simplest item: no packages, just puts one config file where a
# real tool expects to find it.
if is_selected example-symlink; then
  log "example-symlink: linking exampleconfig"
  link_file "$PROFILE_DIR/exampleconfig" "$HOME/.exampleconfig"
fi

# --- example-package -------------------------------------------------
# install_pkgs takes three space-separated package-name strings: macOS
# (Homebrew), apt, dnf — leave any of them "" if that platform has no
# equivalent package for this item.
if is_selected example-package; then
  log "example-package: installing + linking config"
  install_pkgs "example-tool" "example-tool" "example-tool"
  link_file "$PROFILE_DIR/example-tool.conf" "$HOME/.config/example-tool/config"
fi

# --- example-script ----------------------------------------------------
# For anything complex enough to want its own multi-step installer
# (a Python venv, a build step, validation) — give it its own subfolder
# with its own install.sh, and just delegate to it here. See this
# bootstrap repo's sibling profiles for real examples of this shape.
if is_selected example-script; then
  log "example-script: delegating to example-script/install.sh"
  if [[ -f "$PROFILE_DIR/example-script/install.sh" ]]; then
    (cd "$PROFILE_DIR/example-script" && ./install.sh)
  else
    warn "example-script/install.sh not found — nothing to run."
  fi
fi

log "Done."
