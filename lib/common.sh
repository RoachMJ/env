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
# <apt-pkg>/<dnf-pkg> can be "" for a tool with no reliable apt/dnf
# package (see starship's call site) — install/upgrade falls back to
# that tool's own official installer script on Linux in that case.
offer_core_package() {
  local label="$1" bin="$2" mac_pkg="$3" apt_pkg="$4" dnf_pkg="$5"
  local current reply

  if command -v "$bin" >/dev/null 2>&1; then
    current="$("$bin" --version 2>&1 | head -n1)"
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
