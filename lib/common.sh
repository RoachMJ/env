#!/usr/bin/env bash
# ------------------------------------------------------------------
# Author: Mike Roach (https://github.com/RoachMJ)
# ------------------------------------------------------------------
# Shared helpers, sourced by root install.sh and by each profile's own
# install.sh (env-personal/install.sh, env-professional/install.sh).
# Lives here (bootstrap repo) since it's generic plumbing — logging,
# the symlink installer, OS/package-manager detection, a cross-platform
# package-install dispatcher — not anything opinionated about what
# either profile actually installs. Nothing in this file should ever
# need to know the word "personal" or "professional".
#
# Subinstall scripts source this via a relative path
# ("$SCRIPT_DIR/../lib/common.sh", since env-personal/ and
# env-professional/ are nested one level under ENVCFG_HOME, the same
# level as env/). If it's ever missing — e.g. a profile repo gets
# cloned and run completely standalone, without the bootstrap wrapper
# present — each subinstall script falls back to a minimal inline copy
# of these functions rather than hard-failing. See the top of
# env-personal/install.sh or env-professional/install.sh for that
# fallback.
# ------------------------------------------------------------------

log() { printf "\n\033[1;32m==>\033[0m %s\n" "$1"; }
warn() { printf "\n\033[1;33m!!\033[0m %s\n" "$1"; }

# All backups link_file() ever creates land here, not scattered next
# to whatever they replaced. Lives inside ~/.env-config (same hidden
# folder the repos get cloned into) but in its own backups/ subfolder,
# as a sibling of the env-personal/env-professional/env clones — not
# inside any of them, so it never shows up as untracked cruft in any
# of those repos' own `git status`. Override with ENV_CONFIG_DIR=... if
# you want them somewhere else.
ENV_CONFIG_DIR="${ENV_CONFIG_DIR:-$HOME/.env-config/backups}"

# ENVCFG_HOME — the same plain (never-a-git-repo) container folder the
# root install.sh derives from its own script location. Redeclared here
# too since this file gets sourced by both profile installers directly,
# not always via the root script. Only used below to place the
# install manifest as a sibling of env/env-personal/env-professional/
# backups, structurally outside every git working tree by construction.
ENVCFG_HOME="${ENVCFG_HOME:-$HOME/.env-config}"

# ------------------------------------------------------------------
# install-manifest.jsonl — best-effort record of what THIS machine's
# install run(s) actually did, so `--uninstall` can tell "a package we
# installed" from "a package you already had" and know what to remove.
# One JSON object per line (JSON Lines — trivially append-only from
# plain bash, no jq needed to write it; read side below uses simple
# grep/sed since every line is flat, single-level JSON we wrote
# ourselves — no real parser needed for that).
#
# Lives in $ENVCFG_HOME, a sibling of the env/env-personal/
# env-professional clones and of backups/ — same reasoning as
# ENV_CONFIG_DIR above, so it structurally can't land inside any of
# those repos' working trees. Each of the three repos' .gitignore also
# lists it by name as defense in depth, but the real guarantee is that
# it never lives inside a git-tracked directory in the first place.
# Never read by anything except this file's own uninstall helpers.
# ------------------------------------------------------------------
MANIFEST_FILE="${MANIFEST_FILE:-$ENVCFG_HOME/install-manifest.jsonl}"

# CURRENT_PROFILE / CURRENT_ITEM — set by each install.sh (CURRENT_PROFILE
# once near the top, CURRENT_ITEM at the start of each is_selected block)
# so manifest entries can be filtered back out per item at uninstall
# time. Left blank ("") rather than failing if a caller never sets
# them — the entry still gets written, just without that attribution.
CURRENT_PROFILE="${CURRENT_PROFILE:-}"
CURRENT_ITEM="${CURRENT_ITEM:-}"

# _json_escape <string> — backslash + double-quote escaping, the only
# two characters that can break a hand-built flat JSON string value
# here (nothing we ever write into the manifest contains control
# characters or unicode that would need more than this).
_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# _manifest_append <extra-fields-json>
#
# Appends one line to $MANIFEST_FILE. <extra-fields-json> is a
# caller-built, already-valid, comma-separated list of "key":value
# pairs (no surrounding braces, no trailing comma) — this function
# wraps it with the common envelope (timestamp, profile, item) and the
# outer braces. Best-effort: if the write fails for any reason (e.g.
# $ENVCFG_HOME not writable), warn once and move on rather than ever
# failing an install/uninstall over bookkeeping.
_manifest_append() {
  if ! mkdir -p "$(dirname "$MANIFEST_FILE")" 2>/dev/null; then
    warn "Couldn't create $(dirname "$MANIFEST_FILE") — install-manifest.jsonl won't be updated this run."
    return 0
  fi
  printf '{"ts":"%s","profile":"%s","item":"%s",%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(_json_escape "$CURRENT_PROFILE")" \
    "$(_json_escape "$CURRENT_ITEM")" \
    "$1" >>"$MANIFEST_FILE" 2>/dev/null ||
    warn "Couldn't write to $MANIFEST_FILE — install-manifest.jsonl won't be updated this run."
}

# record_manual_install <type> <manager> <name-or-path> <pre_existing:0|1>
#
# For install steps that DON'T go through install_pkgs/install_pkg_one
# below — brew casks with their own inline "already installed?" check
# (Codex, Zed, Git Credential Manager, fonts), npm -g installs, or a
# git-cloned tool (oh-my-tmux, TPM) — call this right after, so
# --uninstall's picture of "what did this run actually add" stays
# complete. <type> is "package" (reuses the package schema — <manager>
# is a free-form label like "brew_cask" or "npm_global", doesn't need
# to be one install_pkg_one itself understands, though uninstall_package
# only knows how to reverse a fixed set — see below) or "cloned_repo"
# (<name-or-path> is the clone's path, no <manager> needed).
record_manual_install() {
  local type="$1" mgr="$2" nameorpath="$3" pre_existing="$4"
  case "$type" in
    cloned_repo)
      _manifest_append "\"type\":\"cloned_repo\",\"path\":\"$(_json_escape "$nameorpath")\",\"pre_existing\":$pre_existing"
      ;;
    *)
      _manifest_append "\"type\":\"package\",\"manager\":\"$mgr\",\"name\":\"$(_json_escape "$nameorpath")\",\"pre_existing\":$pre_existing"
      ;;
  esac
}

# link_file <source-in-repo> <destination-path>
#
# Idempotent symlink installer. If $dest is already a symlink pointing
# at $src, does nothing (no redundant backup, no re-touching it, no
# manifest entry — nothing changed). If it's a symlink pointing
# somewhere else (stale repo location, manually changed), re-points it
# and says so (also no manifest entry — re-pointing isn't something
# --uninstall needs to reverse differently). If it's a real file or
# directory, backs it up first (timestamped, into $ENV_CONFIG_DIR) then
# symlinks — this is the only case that ever creates a backup, and is
# logged to the manifest as had_backup:true so restore_file's caller
# knows one exists (restore_file itself doesn't actually need the
# manifest — see below — this is just for the record). A dest that
# didn't exist at all gets logged had_backup:false.
link_file() {
  local src="$1" dest="$2" current backup dest_flat
  if [[ -L "$dest" ]]; then
    current="$(readlink "$dest")"
    if [[ "$current" == "$src" ]]; then
      return 0
    fi
    log "Re-pointing existing symlink $dest (was -> $current)"
    ln -sf "$src" "$dest"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    mkdir -p "$ENV_CONFIG_DIR"
    dest_flat="$(printf '%s' "$dest" | sed 's|^/||; s|/|_|g')"
    backup="$ENV_CONFIG_DIR/$dest_flat.bak.$(date +%Y%m%d%H%M%S)"
    log "Existing $dest found (a real file/dir, not a symlink) — backing up to $backup (see $ENV_CONFIG_DIR)"
    mv "$dest" "$backup"
    _manifest_append "\"type\":\"symlink\",\"dest\":\"$(_json_escape "$dest")\",\"had_backup\":true"
  else
    _manifest_append "\"type\":\"symlink\",\"dest\":\"$(_json_escape "$dest")\",\"had_backup\":false"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -sf "$src" "$dest"
}

# restore_file <dest> — the reverse of link_file. Deliberately does NOT
# read the manifest — it works purely off link_file's deterministic
# backup-naming scheme ($ENV_CONFIG_DIR/<dest-flattened>.bak.<timestamp>),
# so config restore stays robust even if install-manifest.jsonl is
# missing, stale, or was never written (e.g. configs symlinked by an
# older version of this repo, before manifest tracking existed).
#
#   - $dest is a symlink (ours or not): remove it.
#   - $dest doesn't exist at all: nothing to remove, fall through to
#     the restore check below anyway (a backup can exist even if
#     something else already deleted the symlink).
#   - $dest is a real file/dir, not a symlink: leave it alone and warn
#     — this is not a state link_file's own logic would ever have
#     produced, so silently clobbering it would be a guess, not a
#     restore.
# Then: find the newest matching backup (there can be more than one
# across repeated install/uninstall/reinstall cycles — always take the
# latest) and move it back into place if one exists.
restore_file() {
  local dest="$1" dest_flat latest
  if [[ -L "$dest" ]]; then
    log "Removing symlink $dest"
    rm -f "$dest"
  elif [[ -e "$dest" ]]; then
    warn "$dest exists and is a real file/dir, not a symlink — leaving it alone (not something link_file put there)."
    return 0
  fi

  # Bash array glob rather than `ls -1t | head -n1`: no backup existing
  # is the COMMON case (most dests never had one), and under
  # `set -euo pipefail` (every caller of this file runs with that) an
  # `ls` that matches nothing exits non-zero, which pipefail turns into
  # a script-killing failure the instant it happens — a real bug this
  # exact shape hit during testing. Globbing with nullglob just yields
  # an empty array instead, no external command, no non-zero exit to
  # propagate. Lexical sort matches chronological order here because
  # every backup's suffix is a fixed-width `%Y%m%d%H%M%S` timestamp.
  dest_flat="$(printf '%s' "$dest" | sed 's|^/||; s|/|_|g')"
  local -a backups
  shopt -s nullglob
  backups=("$ENV_CONFIG_DIR/$dest_flat".bak.*)
  shopt -u nullglob
  if [[ ${#backups[@]} -gt 0 ]]; then
    latest="${backups[-1]}"
    mkdir -p "$(dirname "$dest")"
    mv "$latest" "$dest"
    log "Restored $dest from backup ($latest)"
  else
    log "No prior backup found for $dest — nothing to restore (symlink removed if one was there)."
  fi
}

# detect_os — sets OS_KERNEL (Darwin/Linux/other) and, for Linux,
# PKG_MGR (apt/dnf/""). Every script in this repo that needs this
# (root install.sh, both subinstall scripts, archdocs' own installer)
# calls this itself rather than importing state from a parent process
# — each is meant to be safely runnable on its own.
detect_os() {
  OS_KERNEL="$(uname -s)"
  PKG_MGR=""
  if [[ "$OS_KERNEL" == "Linux" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      PKG_MGR="apt"
    elif command -v dnf >/dev/null 2>&1; then
      PKG_MGR="dnf"
    fi
  fi
}

_APT_UPDATED=0

# _pkg_installed <manager> <name> — true if already present. Checked
# BEFORE every install below so the manifest can distinguish "this run
# installed it" from "you already had it" — that distinction is the
# whole reason --uninstall can offer package removal without ever
# risking removing something you brought to the machine yourself.
_pkg_installed() {
  local mgr="$1" pkg="$2"
  case "$mgr" in
    brew) brew list --formula "$pkg" >/dev/null 2>&1 ;;
    brew_cask) brew list --cask "$pkg" >/dev/null 2>&1 ;;
    apt) dpkg -s "$pkg" >/dev/null 2>&1 ;;
    dnf) rpm -q "$pkg" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# install_pkg_one <manager> <name>
#
# Per-package install with a pre-existence check and a manifest entry
# either way (pre_existing:true if it was already there — nothing
# installed, nothing to remove later — or pre_existing:false if this
# call is the one that put it there). <manager> is brew, apt, or dnf
# (brew_cask is checked by _pkg_installed but installed the same way
# call sites like the 'codex'/'zed' items handle themselves via
# record_manual_install instead — see that function's comment). Public
# on its own (not just via install_pkgs below) for call sites that need
# to install a single package outside a mac/apt/dnf triple, e.g. the
# 'lint' item's per-tool loop.
install_pkg_one() {
  local mgr="$1" pkg="$2"
  if _pkg_installed "$mgr" "$pkg"; then
    log "  already installed: $pkg"
    _manifest_append "\"type\":\"package\",\"manager\":\"$mgr\",\"name\":\"$(_json_escape "$pkg")\",\"pre_existing\":true"
    return 0
  fi
  log "  installing $pkg"
  case "$mgr" in
    brew) HOMEBREW_NO_AUTO_UPDATE=1 brew install "$pkg" || { warn "  failed to install $pkg"; return 1; } ;;
    apt) sudo apt-get install -y --no-install-recommends "$pkg" || { warn "  failed to install $pkg"; return 1; } ;;
    dnf) sudo dnf install -y --setopt=install_weak_deps=False "$pkg" || { warn "  failed to install $pkg"; return 1; } ;;
    *) warn "  install_pkg_one: unknown manager '$mgr' for $pkg"; return 1 ;;
  esac
  _manifest_append "\"type\":\"package\",\"manager\":\"$mgr\",\"name\":\"$(_json_escape "$pkg")\",\"pre_existing\":false"
}

# install_pkgs "<mac pkgs>" "<apt pkgs>" "<dnf pkgs>"
#
# Cross-platform package-install dispatcher — each argument is a
# single space-separated string (build it from a bash array with
# "${arr[*]}" at the call site), and can be "" if that platform has no
# equivalent for this particular install. Requires detect_os to have
# been called first in this shell. `apt-get update` only runs once per
# script run no matter how many times install_pkgs is called.
#
# BEHAVIOR CHANGE from earlier versions of this repo: this used to be
# one bulk `brew install $mac_pkgs` (etc.) call per platform, with no
# per-package pre-existence check. It's now a loop over install_pkg_one
# per package — needed so the install-manifest can record, per
# package, whether THIS run installed it (and can therefore offer to
# remove it later via --uninstall) or it was already on the machine
# (and therefore never gets touched by --uninstall). Net effect for a
# normal install run is the same set of packages ending up installed;
# the only visible difference is more, per-package log lines instead of
# one bulk line.
#
# Deliberately scoped to install ONLY what was asked for, nothing else:
#   - Homebrew: HOMEBREW_NO_AUTO_UPDATE=1 stops `brew install` from
#     first running a full `brew update` (which can trigger unrelated
#     formula upgrades/relinks as a side effect of just installing one
#     package you asked for).
#   - apt: --no-install-recommends skips apt's "recommended" (not
#     strictly required) extra packages that ride along with a normal
#     install — you get the package you asked for, not its whole
#     suggested ecosystem.
#   - dnf: --setopt=install_weak_deps=False is the dnf equivalent.
# None of this ever upgrades a package that's already installed and
# wasn't part of this call — `apt-get install`/`dnf install`/
# `brew install` only touch the names you pass them.
install_pkgs() {
  local mac_pkgs="$1" apt_pkgs="$2" dnf_pkgs="$3" pkg
  case "$OS_KERNEL" in
    Darwin)
      [[ -z "$mac_pkgs" ]] && return 0
      if ! command -v brew >/dev/null 2>&1; then
        log "Installing Homebrew"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      log "Installing via Homebrew: $mac_pkgs"
      for pkg in $mac_pkgs; do install_pkg_one brew "$pkg"; done
      ;;
    Linux)
      case "$PKG_MGR" in
        apt)
          [[ -z "$apt_pkgs" ]] && return 0
          if [[ "$_APT_UPDATED" == "0" ]]; then
            sudo apt-get update
            _APT_UPDATED=1
          fi
          log "Installing via apt: $apt_pkgs"
          for pkg in $apt_pkgs; do install_pkg_one apt "$pkg"; done
          ;;
        dnf)
          [[ -z "$dnf_pkgs" ]] && return 0
          log "Installing via dnf: $dnf_pkgs"
          for pkg in $dnf_pkgs; do install_pkg_one dnf "$pkg"; done
          ;;
        *)
          [[ -z "$apt_pkgs" && -z "$dnf_pkgs" ]] && return 0
          warn "Unrecognized Linux package manager (no apt-get or dnf found) —"
          warn "install manually: $apt_pkgs"
          ;;
      esac
      ;;
    *)
      [[ -z "$mac_pkgs$apt_pkgs$dnf_pkgs" ]] && return 0
      warn "Unsupported OS '$OS_KERNEL' — install manually. macOS pkgs:"
      warn "  $mac_pkgs"
      warn "Linux (apt) pkgs: $apt_pkgs"
      warn "Linux (dnf) pkgs: $dnf_pkgs"
      ;;
  esac
}

# _brew_managed <bin> — true if the binary currently resolved on
# $PATH for <bin> actually lives under Homebrew's own prefix, i.e.
# Homebrew installed/owns the copy that's active right now. False for
# anything on macOS that isn't from brew: Xcode Command Line Tools'
# git, a manually built binary, another package manager (MacPorts,
# asdf, mise, ...), a tool's own official installer script, etc.
# Only meaningful on Darwin — the Linux upgrade path never touches
# brew, so nothing calls this there.
_brew_managed() {
  local bin="$1" resolved brew_prefix
  command -v brew >/dev/null 2>&1 || return 1
  resolved="$(command -v "$bin" 2>/dev/null)"
  [[ -n "$resolved" ]] || return 1
  brew_prefix="$(brew --prefix 2>/dev/null)"
  [[ -n "$brew_prefix" ]] || return 1
  [[ "$resolved" == "$brew_prefix"/* ]]
}

# offer_core_package <label> <bin> <mac-pkg> <apt-pkg> <dnf-pkg>
#
# Interactive, optional install-or-upgrade for one core tool. Never
# acts silently: checks whether <bin> is already on $PATH first, and
# only THEN decides what to ask —
#   already present  -> "Upgrade to latest? [y/N]" (default: leave it)
#   missing           -> "Install it? [Y/n]" (default: install, since
#                         these are things the rest of this repo
#                         assumes exist, but always skippable)
# No TTY on stdin means no prompt is possible, so this reports what it
# would have asked and does nothing — it never assumes an answer.
# On macOS specifically: if the binary already on $PATH isn't actually
# a Homebrew-managed copy (see _brew_managed above), the upgrade offer
# is skipped entirely rather than asked — `brew upgrade` on a package
# name that isn't what's providing the active binary either errors out
# or installs a second, unrelated copy that doesn't change what's
# actually on $PATH. Leave it managed however it already is.
# <apt-pkg>/<dnf-pkg> can be "" for a tool with no reliable apt/dnf
# package (see starship's call site) — install/upgrade falls back to
# that tool's own official installer script on Linux in that case.
offer_core_package() {
  local label="$1" bin="$2" mac_pkg="$3" apt_pkg="$4" dnf_pkg="$5"
  local current reply

  if command -v "$bin" >/dev/null 2>&1; then
    current="$("$bin" --version 2>&1 | head -n1)"
    if [[ "$OS_KERNEL" == "Darwin" ]] && ! _brew_managed "$bin"; then
      log "$label already installed ($current), but not via Homebrew — skipping the upgrade offer rather than risk touching an unrelated copy. Update it however you originally installed it."
      return 0
    fi
    if [[ ! -t 0 ]]; then
      log "$label already installed ($current) — no TTY, skipping upgrade prompt."
      return 0
    fi
    read -r -p "$label already installed ($current). Upgrade to latest? [y/N] " reply
    case "$reply" in
      y | Y) _upgrade_core_package "$label" "$bin" "$mac_pkg" "$apt_pkg" "$dnf_pkg" ;;
      *) log "Leaving $label as-is." ;;
    esac
    return 0
  fi

  if [[ ! -t 0 ]]; then
    warn "$label not found and no TTY to ask — skipping. Install manually or re-run interactively."
    return 0
  fi

  read -r -p "$label not found. Install it? [Y/n] " reply
  case "$reply" in
    n | N) warn "Skipping $label — some things in this repo may not work without it." ;;
    *) _install_core_package "$label" "$bin" "$mac_pkg" "$apt_pkg" "$dnf_pkg" ;;
  esac
}

_install_core_package() {
  local label="$1" bin="$2" mac_pkg="$3" apt_pkg="$4" dnf_pkg="$5"
  if [[ "$OS_KERNEL" == "Linux" && -z "$apt_pkg$dnf_pkg" ]]; then
    log "Installing $label via its official installer (no reliable apt/dnf package)"
    curl -sS "https://starship.rs/install.sh" | sh -s -- -y ||
      warn "$label install script failed — see its own install docs."
    return 0
  fi
  install_pkgs "$mac_pkg" "$apt_pkg" "$dnf_pkg"
}

_upgrade_core_package() {
  local label="$1" bin="$2" mac_pkg="$3" apt_pkg="$4" dnf_pkg="$5"
  case "$OS_KERNEL" in
    Darwin)
      log "Upgrading $label via Homebrew"
      HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade "$mac_pkg" ||
        warn "brew upgrade $mac_pkg reported an issue — check output above."
      ;;
    Linux)
      if [[ -z "$apt_pkg$dnf_pkg" ]]; then
        log "Upgrading $label via its official installer (no reliable apt/dnf package)"
        curl -sS "https://starship.rs/install.sh" | sh -s -- -y ||
          warn "$label upgrade failed — see its own install docs."
      elif [[ "$PKG_MGR" == "apt" ]]; then
        if [[ "$_APT_UPDATED" == "0" ]]; then
          sudo apt-get update
          _APT_UPDATED=1
        fi
        log "Upgrading $label via apt"
        sudo apt-get install -y --only-upgrade "$apt_pkg"
      elif [[ "$PKG_MGR" == "dnf" ]]; then
        log "Upgrading $label via dnf"
        sudo dnf upgrade -y "$dnf_pkg"
      else
        warn "Unrecognized package manager — upgrade $label manually."
      fi
      ;;
    *)
      warn "Unsupported OS '$OS_KERNEL' — upgrade $label manually."
      ;;
  esac
}

# ------------------------------------------------------------------
# Uninstall-side: reading the manifest back out, and removing packages
# it says THIS run (or an earlier one on this machine) installed.
# Best-effort by design — a missing/corrupt manifest just means
# "nothing to offer removing", never a hard failure.
# ------------------------------------------------------------------

# manifest_packages_for_item <item> — prints "manager<TAB>name" lines,
# one per package ever recorded against <item> with pre_existing:false
# (i.e. this machine's install runs actually installed it — never
# something that was already there before we touched it). Deduplicated
# so re-running install.sh several times doesn't produce repeat rows.
# Empty output (no lines, exit 0) if there's no manifest yet or nothing
# matches — always safe to loop over with `while read`.
manifest_packages_for_item() {
  local item="$1"
  [[ -f "$MANIFEST_FILE" ]] || return 0
  # `|| true` at the end matters: under set -euo pipefail (every caller
  # runs with that), any grep stage matching nothing exits non-zero,
  # and pipefail would otherwise turn "nothing matched" (the expected
  # result for most items) into a script-killing failure the instant
  # this runs inside a `rows="$(...)"` assignment — hit for real during
  # testing, same class of bug as restore_file's ls|head fix above.
  grep "\"item\":\"$(_json_escape "$item")\"" "$MANIFEST_FILE" 2>/dev/null |
    grep '"type":"package"' |
    grep '"pre_existing":false' |
    sed -n 's/.*"manager":"\([^"]*\)".*"name":"\([^"]*\)".*/\1\t\2/p' |
    sort -u || true
}

# uninstall_package <manager> <name> — reverse of one install_pkg_one
# call (or record_manual_install "package" call). Best-effort: reports
# a failed removal and moves on rather than aborting the whole
# --uninstall run over one stubborn package.
uninstall_package() {
  local mgr="$1" name="$2"
  # Every branch ends in `|| true` — a failed removal (package has
  # dependents, needs sudo and none available, etc.) must not abort
  # the rest of the uninstall run under set -euo pipefail. The comment
  # above this function says "best-effort... moves to the next
  # package"; without this these calls would silently kill the whole
  # script on the first stubborn package instead.
  case "$mgr" in
    brew) brew uninstall "$name" 2>&1 | sed 's/^/    /' || true ;;
    brew_cask) brew uninstall --cask "$name" 2>&1 | sed 's/^/    /' || true ;;
    apt) sudo apt-get remove -y "$name" 2>&1 | sed 's/^/    /' || true ;;
    dnf) sudo dnf remove -y "$name" 2>&1 | sed 's/^/    /' || true ;;
    npm_global) (sudo npm uninstall -g "$name" 2>&1 || npm uninstall -g "$name" 2>&1) | sed 's/^/    /' || true ;;
    *) warn "  Unknown manager '$mgr' for $name — remove it yourself." ;;
  esac
}

# uninstall_item_packages <item>
#
# Shows every package this machine's install runs actually installed
# for <item> (per the manifest — never anything pre-existing), asks
# once, then removes them all on a yes. No-op, silently, if the
# manifest has nothing recorded for this item (fresh manifest, or the
# item never wrote package entries, e.g. it's config-only). No TTY ->
# leaves packages in place and says so, same "never guess" rule as the
# rest of this file's interactive prompts.
uninstall_item_packages() {
  local item="$1" rows n=0 mgr name reply
  rows="$(manifest_packages_for_item "$item")"
  [[ -z "$rows" ]] && return 0

  echo "Packages this machine's install run(s) installed for '$item' (not things you already had):"
  while IFS=$'\t' read -r mgr name; do
    [[ -z "$mgr" ]] && continue
    echo "  - $name ($mgr)"
    n=$((n + 1))
  done <<<"$rows"
  [[ "$n" -eq 0 ]] && return 0

  if [[ -t 0 ]]; then
    read -r -p "Remove these $n package(s) too? [y/N] " reply
  else
    reply="n"
    warn "No TTY — leaving packages installed. Re-run --uninstall interactively to remove them."
  fi
  if [[ ! "$reply" =~ ^[Yy] ]]; then
    log "Leaving packages in place."
    return 0
  fi

  while IFS=$'\t' read -r mgr name; do
    [[ -z "$mgr" ]] && continue
    log "Removing $name ($mgr)"
    uninstall_package "$mgr" "$name"
  done <<<"$rows"
}

# ------------------------------------------------------------------
# YubiKey-backed SSH (PIV slot 9a) config wiring. Generic on purpose —
# takes a list of hosts as arguments rather than deciding for itself
# which hosts matter, since that's genuinely different per profile:
# env-personal's own gitconfig forces GitHub over SSH (an `insteadOf`
# rewrite), env-professional's deliberately doesn't (HTTPS+PAT is the
# primary there — see that profile's gitconfig header comment), so it
# asks interactively instead. See each profile's install.sh 'git' item
# for exactly how each one decides what to pass in here — that
# decision belongs there, not in this shared file.
#
# Needs the bootstrap repo's `./install.sh --encrypt` to have already
# provisioned PIV slot 9a (env-config.pub present under
# ~/.ssh/.env-config/) — silently does nothing otherwise, since this
# is opt-in, not everyone uses YubiKey-backed SSH.
# ------------------------------------------------------------------

# _yubikey_pkcs11_path — echoes the discovered libykcs11 path (the
# PKCS#11 module SSH needs to talk to the YubiKey's PIV applet), or
# nothing if it can't find one. Installs yubico-piv-tool first if
# missing — the bootstrap repo's --encrypt wizard never installs this
# itself, only ykman/age/age-plugin-yubikey, since this piece is
# SSH-specific and not needed for the repo-access encryption path.
# Path is discovered via 'brew --prefix', not hardcoded, so this works
# the same on Intel (/usr/local) and Apple Silicon (/opt/homebrew)
# without caring which one you're on.
_yubikey_pkcs11_path() {
  local path=""
  case "$OS_KERNEL" in
    Darwin)
      if ! brew list --formula yubico-piv-tool >/dev/null 2>&1; then
        log "Installing yubico-piv-tool (provides libykcs11, the PKCS#11 module SSH needs for the YubiKey)"
        HOMEBREW_NO_AUTO_UPDATE=1 brew install yubico-piv-tool || return 0
      fi
      local prefix
      prefix="$(brew --prefix yubico-piv-tool 2>/dev/null)"
      [[ -n "$prefix" && -f "$prefix/lib/libykcs11.dylib" ]] && path="$prefix/lib/libykcs11.dylib"
      ;;
    Linux)
      if ! (ldconfig -p 2>/dev/null | grep -qi ykcs11); then
        install_pkgs "" "yubico-piv-tool" "yubico-piv-tool"
      fi
      path="$(ldconfig -p 2>/dev/null | grep -im1 ykcs11 | awk '{print $NF}')"
      ;;
  esac
  printf '%s' "$path"
}

# _next_numbered_dest <base-path>
#
# Collision-avoidance helper shared by encrypt_wizard.sh: if <base-path>
# doesn't exist yet, echoes it unchanged. Otherwise echoes the same
# path with "-2", "-3", ... spliced in before the extension (e.g.
# env-config-cert.pem -> env-config-cert-2.pem), stopping at the first
# name that isn't taken. Used so re-running the wizard with a second
# physical YubiKey (a backup login key) never clobbers the first key's
# cert/identity file in piv/ — both end up committed side by side.
_next_numbered_dest() {
  local base="$1" dir stem ext n dest
  dir="$(dirname "$base")"
  stem="$(basename "$base")"
  if [[ "$stem" == *.* ]]; then
    ext=".${stem##*.}"
    stem="${stem%.*}"
  else
    ext=""
  fi
  if [[ ! -e "$base" ]]; then
    printf '%s' "$base"
    return 0
  fi
  n=2
  while [[ -e "$dir/${stem}-${n}${ext}" ]]; do
    n=$((n + 1))
  done
  printf '%s' "$dir/${stem}-${n}${ext}"
}

# regenerate_yubikey_ssh_pubkeys <piv_dir>
#
# For every piv/env-config-cert*.pem committed in <piv_dir> (the
# bootstrap repo's own piv/ folder — one per physical YubiKey
# provisioned via ./install.sh --encrypt; numbered when there's more
# than one, e.g. a backup login key, see _next_numbered_dest() above),
# regenerates the matching env-config*.pub into ~/.ssh/.env-config/.
# Runs on every install, not just --encrypt, so a fresh machine with
# only a git clone and the physical YubiKey(s) in hand ends up with
# the same pubkey(s) as the machine that originally ran the wizard —
# nothing here touches the private key, the cert is public data by
# design (see README.md). Silently does nothing if piv/ has no certs
# yet, or ssh-keygen/openssl isn't installed.
#
# env-config-cert.pem is an X.509 CERTIFICATE (ykman piv certificates
# export), not a bare PKCS8 public key — ssh-keygen's `-m PKCS8` import
# mode can't read a certificate directly (fails with "not a recognised
# public key format"). `openssl x509 -pubkey -noout` pulls just the
# SubjectPublicKeyInfo block back out first, which ssh-keygen *can*
# read — confirmed against a real self-signed EC cert, not assumed.
regenerate_yubikey_ssh_pubkeys() {
  local piv_dir="$1"
  local piv_ssh_dir="$HOME/.ssh/.env-config"
  command -v ssh-keygen >/dev/null 2>&1 || return 0
  command -v openssl >/dev/null 2>&1 || return 0
  [[ -d "$piv_dir" ]] || return 0

  local cert base pub_name pub_path pkcs8_tmp found=0
  for cert in "$piv_dir"/env-config-cert*.pem; do
    [[ -f "$cert" ]] || continue
    found=1
    base="$(basename "$cert" .pem)"
    base="${base/-cert/}"
    pub_name="${base}.pub"
    mkdir -p "$piv_ssh_dir"
    chmod 700 "$piv_ssh_dir"
    pub_path="$piv_ssh_dir/$pub_name"
    pkcs8_tmp="$pub_path.pkcs8.tmp"
    if openssl x509 -in "$cert" -pubkey -noout >"$pkcs8_tmp" 2>/dev/null &&
      ssh-keygen -f "$pkcs8_tmp" -i -m PKCS8 >"$pub_path.tmp" 2>/dev/null; then
      mv "$pub_path.tmp" "$pub_path"
      chmod 644 "$pub_path"
      rm -f "$pkcs8_tmp"
      log "Regenerated $pub_path from $(basename "$cert")"
    else
      rm -f "$pub_path.tmp" "$pkcs8_tmp"
      warn "Couldn't regenerate a pubkey from $cert — skipping it."
    fi
  done
  if [[ "$found" == "0" ]]; then
    log "No piv/env-config-cert*.pem found under $piv_dir — nothing to"
    log "regenerate (run './install.sh --encrypt' first if you want"
    log "YubiKey-backed SSH)."
  fi
  # Explicit — without this, the function's return status is whatever
  # the *last executed command* left behind, which is this if-with-no-
  # else: when $found is "1" (the common case — a cert WAS there,
  # regardless of whether ssh-keygen/openssl above actually succeeded
  # for it), the condition test itself evaluates false, and bash's `if`
  # with no matching branch returns THAT false status as the whole
  # statement's exit code. Called as a bare statement under `set -euo
  # pipefail` (every caller here), a non-zero return killed the entire
  # install — independent of whether pubkey regeneration actually
  # succeeded. This is what was actually causing the script to exit
  # right after "Couldn't regenerate a pubkey...", not the warning
  # itself, which is handled and non-fatal on its own.
  return 0
}

# wire_yubikey_ssh_config <alias:realhost> [alias:realhost...]
#
# Each argument is "ALIAS:REALHOST" — ALIAS is an SSH config Host
# alias (e.g. "personal"), distinct from REALHOST, the actual hostname
# it connects to (e.g. "github.com"). This alias indirection is what
# lets gitconfig's `[url "ALIAS:PATH/"] insteadOf` rewrite ONLY your
# own repos (whatever matches the insteadOf patterns) through the
# YubiKey identity, while any other SSH connection to REALHOST — e.g.
# cloning someone else's repo via a literal git@REALHOST:... URL that
# doesn't match an insteadOf pattern — falls through to normal SSH
# resolution instead of being forced through this key too.
#
# For the alias(es) given: writes (or rewrites) a Host block per alias
# into a dedicated SSH-config-syntax file at
# ~/.ssh/.env-config/config — deliberately not named *.env; an SSH
# Include target has to be real ssh_config syntax, not a shell
# KEY=VALUE file, so a .env-style name would misdescribe what's
# actually in it. Ensures ~/.ssh/config exists and Include's that
# file, prepended at the very top — Include has to come before any
# catch-all "Host *" block further down in an existing config to
# actually take effect. Fully regenerates the managed file every call,
# so it always matches whatever alias list you pass — safe to re-run
# (e.g. every time the 'git' item installs).
#
# Every env-config*.pub found under ~/.ssh/.env-config/ (regenerated by
# regenerate_yubikey_ssh_pubkeys() from piv/env-config-cert*.pem — one
# per physical YubiKey provisioned) gets its own IdentityFile line in
# each Host block, primary key first. PKCS11Provider stays a single
# line — it's a path to the shared PKCS#11 module, not tied to any one
# physical key, so it works no matter which of the registered YubiKeys
# is actually plugged in for a given connection; SSH just tries each
# IdentityFile in turn until one matches what's inserted. This is what
# makes a lost/broken primary key recoverable with a registered backup
# instead of a hard lockout.
wire_yubikey_ssh_config() {
  local piv_ssh_dir="$HOME/.ssh/.env-config"
  local pub_keys=() f numbered=()

  [[ -f "$piv_ssh_dir/env-config.pub" ]] && pub_keys+=("$piv_ssh_dir/env-config.pub")
  for f in "$piv_ssh_dir"/env-config-*.pub; do
    [[ -f "$f" ]] && numbered+=("$f")
  done
  if [[ ${#numbered[@]} -gt 0 ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] && pub_keys+=("$f")
    done < <(printf '%s\n' "${numbered[@]}" | sort)
  fi

  if [[ ${#pub_keys[@]} -eq 0 ]]; then
    log "No env-config*.pub found under $piv_ssh_dir — YubiKey SSH key not"
    log "provisioned yet (run the bootstrap repo's './install.sh --encrypt'"
    log "first, or re-run install.sh so piv/env-config-cert*.pem gets"
    log "regenerated into pubkeys here)."
    return 0
  fi

  if [[ $# -eq 0 ]]; then
    return 0
  fi

  local pkcs11_path
  pkcs11_path="$(_yubikey_pkcs11_path)"
  if [[ -z "$pkcs11_path" ]]; then
    warn "Couldn't locate libykcs11 (the YubiKey's PKCS#11 module) — skipping"
    warn "SSH config wiring. Find it yourself (e.g. 'brew --prefix yubico-piv-tool')"
    warn "and add it to $piv_ssh_dir/config by hand."
    return 0
  fi

  mkdir -p "$piv_ssh_dir"
  chmod 700 "$piv_ssh_dir"
  local snippet_file="$piv_ssh_dir/config"
  {
    echo "# Managed by install.sh's 'git' item — safe to regenerate by"
    echo "# re-running it. Each Host below is an ALIAS (not the real"
    echo "# hostname — see its HostName line), routed through the"
    echo "# YubiKey's hardware-resident PIV key (slot 9a) instead of"
    echo "# any file-based key. gitconfig rewrites your own repo URLs"
    echo "# to use the alias — see that profile's git-config/gitconfig"
    echo "# [url] block — so only those get this key; other SSH"
    echo "# connections to the same real host aren't affected."
    local pair alias_name realhost
    for pair in "$@"; do
      alias_name="${pair%%:*}"
      realhost="${pair#*:}"
      echo
      echo "Host $alias_name"
      echo "    HostName $realhost"
      echo "    User git"
      echo "    PKCS11Provider $pkcs11_path"
      for f in "${pub_keys[@]}"; do
        echo "    IdentityFile $f"
      done
      echo "    IdentitiesOnly yes"
    done
  } >"$snippet_file"
  chmod 600 "$snippet_file"
  local pub_key_names="" pk
  for pk in "${pub_keys[@]}"; do
    pub_key_names="$pub_key_names ${pk##*/}"
  done
  log "Wrote $snippet_file ($# alias(es): $*, ${#pub_keys[@]} YubiKey(s) wired:$pub_key_names)"

  local ssh_dir="$HOME/.ssh" main_config="$HOME/.ssh/config"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  if [[ ! -f "$main_config" ]]; then
    log "No ~/.ssh/config found — creating one."
    : >"$main_config"
    chmod 600 "$main_config"
  fi

  if ! grep -qF "Include $snippet_file" "$main_config" 2>/dev/null; then
    { echo "Include $snippet_file"; echo; cat "$main_config"; } >"$main_config.tmp"
    mv "$main_config.tmp" "$main_config"
    log "Added 'Include $snippet_file' to the top of ~/.ssh/config"
  else
    log "~/.ssh/config already includes $snippet_file."
  fi

  local first_alias="${1%%:*}"
  log "Test with: ssh -T $first_alias"
}

# unwire_yubikey_ssh_config — reverse of wire_yubikey_ssh_config, used
# by --uninstall. Removes the Include line from ~/.ssh/config (leaves
# the rest of that file alone) and deletes the managed snippet file.
# Never touches the YubiKey itself, env-config.pub, or anything under
# ~/.ssh/.env-config/ besides that one generated config file.
unwire_yubikey_ssh_config() {
  local piv_ssh_dir="$HOME/.ssh/.env-config"
  local snippet_file="$piv_ssh_dir/config"
  local main_config="$HOME/.ssh/config"

  if [[ -f "$main_config" ]] && grep -qF "Include $snippet_file" "$main_config" 2>/dev/null; then
    grep -vF "Include $snippet_file" "$main_config" >"$main_config.tmp"
    mv "$main_config.tmp" "$main_config"
    log "Removed the Include line for $snippet_file from ~/.ssh/config."
  fi
  if [[ -f "$snippet_file" ]]; then
    rm -f "$snippet_file"
    log "Removed $snippet_file."
  fi
}
