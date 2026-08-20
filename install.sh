#!/usr/bin/env bash
# ------------------------------------------------------------------
# env-config bootstrap installer
# Author: Mike Roach (https://github.com/RoachMJ)
# ------------------------------------------------------------------
# Bootstrap script. What it does, in order:
#   1. Check/offer core packages (git, curl, zsh, starship)
#   2. Prompt for which profile(s) to install (env-personal/env-professional/both)
#   3. Shallow-clone (or pull) each chosen profile's own repo
#   4. Hand off to that profile's own install.sh
#
# Also supports a one-time setup mode: `./install.sh --encrypt`
# provisions a YubiKey (SSH auth key + ECC P-256 encryption key) and
# builds the encrypted piv/repo.env.age bundle used by step 3 above —
# see README.md, "One-time setup: the --encrypt wizard".
#
# And an uninstall mode: `./install.sh --uninstall` asks which
# profile(s) to roll back, then delegates to each one's own
# `install.sh --uninstall` (that's where the actual per-item restore
# logic lives — see env-personal/install.sh / env-professional/install.sh's
# own header comments), then optionally removes the core packages
# (git/curl/zsh/starship) this machine's install run(s) actually
# installed — never anything that was already there. This is the
# "referenced by the main install" half of the manifest/restore system
# in lib/common.sh; see that file's own comments for how the manifest
# and restore_file() work.
#
# Knows nothing about what's inside a profile. Full design/rationale,
# including the two repo-access paths, is in README.md, not here.
#
# Usage: ./install.sh [--help | --encrypt | --uninstall]
# ------------------------------------------------------------------
set -euo pipefail

# 0. Piped in (curl ... | bash)? Self-relocate: clone this repo to
#    disk, re-exec from inside the clone. Normal on-disk runs skip this.
#
# ~/.env-config (ENVCFG_HOME) itself is NEVER a git repo — it's a plain
# container folder. The bootstrap repo gets cloned into env/
# *inside* it, exactly the same way env-personal/ and env-professional/
# each get cloned into their own subfolder later — three independent
# git clones sitting side by side, not one repo wrapping the others.
# This matters: it's what keeps a plaintext repo.env (written later,
# see below) from ever landing inside a git working tree by accident.
if [[ -z "${BASH_SOURCE[0]:-}" || ! -f "${BASH_SOURCE[0]}" ]]; then
  # This repo is public and needs no auth to clone (see README.md's
  # "how safe" writeup), so a real default lives here rather than
  # forcing every piped run to set BOOTSTRAP_REPO_URL by hand — that
  # used to hard-fail with "Piped execution needs BOOTSTRAP_REPO_URL=..."
  # on the plain one-liner. Override it (e.g. running your own fork)
  # with: curl -fsSL <raw-url>/install.sh | BOOTSTRAP_REPO_URL=<url> bash
  BOOTSTRAP_REPO_URL="${BOOTSTRAP_REPO_URL:-https://github.com/RoachMJ/env.git}"
  ENVCFG_HOME="${ENVCFG_HOME:-$HOME/.env-config}"
  BOOTSTRAP_DIR="$ENVCFG_HOME/env"

  if [[ -d "$BOOTSTRAP_DIR/.git" ]]; then
    echo "==> $BOOTSTRAP_DIR already cloned — pulling latest"
    git -C "$BOOTSTRAP_DIR" pull --ff-only
  else
    echo "==> Cloning bootstrap repo to $BOOTSTRAP_DIR"
    mkdir -p "$ENVCFG_HOME"
    git clone --depth 1 "$BOOTSTRAP_REPO_URL" "$BOOTSTRAP_DIR"
  fi

  # Reconnect stdin to the controlling terminal before re-exec'ing.
  # Piped execution (curl ... | bash) leaves stdin as the now-exhausted
  # pipe, so without this, every `[[ -t 0 ]]` check for the REST of
  # this install (profile choice below, git identity, SSH-vs-token
  # auth choice, etc. — all the way through whichever profile
  # install.sh hands off to) would see "no TTY" even though you're
  # sitting at a normal interactive shell, and either silently skip or
  # hard-exit. /dev/tty is the actual controlling terminal, independent
  # of whatever stdin is currently wired to (the curl pipe, in this
  # case) — reattach it if one exists. If it doesn't (genuinely
  # non-interactive: CI, cron, another script piping this one in),
  # leave stdin alone so the existing "No TTY" checks further down
  # keep working as designed instead of hanging on a device that isn't
  # there.
  if [[ -r /dev/tty ]]; then
    exec bash "$BOOTSTRAP_DIR/install.sh" "$@" < /dev/tty
  else
    exec bash "$BOOTSTRAP_DIR/install.sh" "$@"
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ENVCFG_HOME (~/.env-config) is the plain container folder one level
# up from this script — never a git repo itself. env-personal/ and
# env-professional/ get cloned as its other children, siblings of
# env/, each its own independent git clone with its own .git.
ENVCFG_HOME="$(dirname "$SCRIPT_DIR")"

# Where `--encrypt` writes generated key material (SSH pubkey + its
# certificate, age identity, recipient) — under ~/.ssh alongside every
# other SSH-related file on the machine, hidden (dot-prefixed) since
# it's not meant to be browsed casually, and outside any git-tracked
# repo, same idea as env-professional/piv's ~/.secrets/openai.
#
# NOTE: three similarly-named things, three different jobs — don't mix
# them up:
#   - ENVCFG_HOME    ($HOME/.env-config)          plain container, NOT
#                                                  a git repo — holds
#                                                  env/, env-personal/,
#                                                  env-professional/
#                                                  (each its own git
#                                                  clone), plus repo.env
#                                                  and backups/ below,
#                                                  none of which are
#                                                  tracked by any of
#                                                  those repos
#   - ENV_CONFIG_DIR ($HOME/.env-config/backups)  link_file()'s backup
#                                                  dir (lib/common.sh) —
#                                                  a plain subfolder of
#                                                  ENVCFG_HOME, sibling
#                                                  of the env-personal/
#                                                  env-professional/
#                                                  env clones
#   - ENCRYPTION_FILES_DIR ($HOME/.ssh/.env-config) generated key
#     material — under ~/.ssh, a completely separate tree
ENCRYPTION_FILES_DIR="$HOME/.ssh/.env-config"

HELP=0
ENCRYPT=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    -h | --help) HELP=1 ;;
    --encrypt) ENCRYPT=1 ;;
    --uninstall) UNINSTALL=1 ;;
    *)
      echo "Unrecognized argument: $arg" >&2
      echo "This script takes no profile/item flags — run './install.sh --help'." >&2
      exit 1
      ;;
  esac
done

if [[ "$HELP" == "1" ]]; then
  echo "Usage: ./install.sh [--encrypt | --uninstall]"
  echo
  echo "No profile/item flags — everything else is interactive. What it does:"
  echo "  1. Check/offer core packages (git, curl, zsh, starship)"
  echo "     - each install/upgrade is its own prompt, nothing silent"
  echo "  2. Prompt for which profile(s) to set up (env-personal, env-professional, or both)"
  echo "  3. Clone/pull each chosen profile's repo — asks SSH vs. token per"
  echo "     profile when both are available (see README.md, 'Repo access')"
  echo "  4. Hand off to that profile's own install.sh for component selection"
  echo
  echo "--encrypt: one-time setup wizard instead of the above — provisions a"
  echo "  YubiKey (SSH auth key + ECC P-256 encryption key) and builds the"
  echo "  encrypted piv/repo.env.age bundle used by step 3. See README.md."
  echo
  echo "--uninstall: asks which already-installed profile(s) to roll back,"
  echo "  delegates to each one's own './install.sh --uninstall' (same"
  echo "  checklist UX as a normal install — restores backed-up configs,"
  echo "  optionally removes packages), then optionally removes the core"
  echo "  packages above too. Never touches the repo clones themselves or"
  echo "  ~/.env-config/backups — see lib/common.sh's restore_file()/"
  echo "  manifest comments for exactly what this does and doesn't do."
  exit 0
fi

if [[ "$ENCRYPT" == "1" ]]; then
  # shellcheck source=lib/encrypt_wizard.sh
  source "$SCRIPT_DIR/lib/encrypt_wizard.sh"
  run_encrypt_wizard
  exit 0
fi

detect_os
log "Detected OS: $OS_KERNEL${PKG_MGR:+ ($PKG_MGR)}"

if [[ "$UNINSTALL" == "1" ]]; then
  CURRENT_PROFILE="env"
  CURRENT_ITEM="core"

  if [[ ! -t 0 ]]; then
    echo "No TTY on stdin — --uninstall always prompts interactively (which" >&2
    echo "profile(s), then each profile's own checklist). Run it from an" >&2
    echo "interactive shell." >&2
    exit 1
  fi

  echo
  echo "Which already-installed profile(s) do you want to roll back?"
  echo "  1) env-personal"
  echo "  2) env-professional"
  echo "  3) both"
  read -r -p "> " uninstall_choice

  UNINSTALL_PROFILES=()
  case "$uninstall_choice" in
    1 | env-personal) UNINSTALL_PROFILES=(env-personal) ;;
    2 | env-professional) UNINSTALL_PROFILES=(env-professional) ;;
    3 | both) UNINSTALL_PROFILES=(env-personal env-professional) ;;
    *)
      echo "Unrecognized choice '$uninstall_choice' — expected 1/2/3 or env-personal/env-professional/both." >&2
      exit 1
      ;;
  esac

  ENVCFG_HOME_FOR_UNINSTALL="$(dirname "$SCRIPT_DIR")"
  for up in "${UNINSTALL_PROFILES[@]}"; do
    up_dir="$ENVCFG_HOME_FOR_UNINSTALL/$up"
    up_install="$up_dir/install.sh"
    if [[ -x "$up_install" ]]; then
      log "Handing off to $up/install.sh --uninstall..."
      "$up_install" --uninstall
    else
      warn "$up_install not found (or not executable) — '$up' doesn't look installed here, skipping."
    fi
  done

  log "Profile rollback(s) done."
  uninstall_item_packages "core"

  log "Done. The repo clones under $ENVCFG_HOME_FOR_UNINSTALL and its"
  log "backups/ folder were left alone — remove those by hand if you want a"
  log "completely clean slate before re-testing an install."
  exit 0
fi

# 1. Core packages — checked first, offered second, never silent.
#    See offer_core_package in lib/common.sh.
CURRENT_PROFILE="env"
CURRENT_ITEM="core"

offer_core_package "git" git "git" "git" "git"
offer_core_package "curl" curl "curl" "curl" "curl"
offer_core_package "zsh" zsh "zsh" "zsh" "zsh"
offer_core_package "Starship" starship "starship" "" ""

if ! command -v zsh >/dev/null 2>&1; then
  warn "zsh still not found on \$PATH — some profile components assume it's present."
fi

# 2. Profile choice — always interactive, no --profile= flag.
if [[ ! -t 0 ]]; then
  echo "No TTY on stdin — this script always prompts interactively for which" >&2
  echo "profile(s) to install and refuses to guess. Run it from an interactive" >&2
  echo "shell." >&2
  exit 1
fi

echo
echo "Which profile(s) do you want to install?"
echo "  1) env-personal"
echo "  2) env-professional"
echo "  3) both"
read -r -p "> " profile_choice

PROFILES=()
case "$profile_choice" in
  1 | env-personal) PROFILES=(env-personal) ;;
  2 | env-professional) PROFILES=(env-professional) ;;
  3 | both) PROFILES=(env-personal env-professional) ;;
  *)
    echo "Unrecognized choice '$profile_choice' — expected 1/2/3 or env-personal/env-professional/both." >&2
    exit 1
    ;;
esac

# 3. Shallow-clone (or pull) each chosen profile's repo — separate
#    repos, not folders in this one. Two places a profile's URL can
#    come from, checked in this order (see README.md "Repo access"):
#
#    1. *_SSH_URL from piv/repo.env.age, decrypted below — wins if
#       present, since a real URL there means you deliberately set one.
#    2. ENV_PERSONAL_REPO_URL / ENV_PROFESSIONAL_REPO_URL right below —
#       the plaintext fallback, used untouched if the bundle has
#       nothing for that profile (missing, decrypt failed, or just no
#       entry for it).
#
#    Whichever URL wins, auth is SSH (ssh-agent, e.g. a YubiKey PIV key
#    via `ssh-add -s`) UNLESS the decrypted bundle also carries a
#    REPO_ACCESS_TOKEN — a single token, not per-profile — in which
#    case that token wins for BOTH profiles: the resolved URL is
#    converted from git@host:path to https://host/path and the token
#    is sent as a Basic-auth header, scoped to that host only, never
#    written to either profile's git config. No token in the bundle ->
#    plain SSH, no behavior change.
#
#    piv/repo.env.age is encrypted to a YubiKey-resident ECC P-256 key
#    (age-plugin-yubikey). It decrypts once per run to
#    $ENVCFG_HOME/repo.env (chmod 600, never committed), which is then
#    sourced directly into this script's environment.
ENV_PERSONAL_REPO_URL="${ENV_PERSONAL_REPO_URL:-git@github.com:YOUR_GITHUB_USERNAME/env-personal.git}"
ENV_PROFESSIONAL_REPO_URL="${ENV_PROFESSIONAL_REPO_URL:-git@REPLACE_ME.example.com:REPLACE_ME_GROUP/env-professional.git}"

# The recipient piv/repo.env.age is encrypted to — an age-plugin-yubikey
# identity backed by an ECC P-256 key in a YubiKey PIV retired slot.
# `./install.sh --encrypt` writes this to a short, well-known file
# (piv/recipient — a single line, just the age1yubikey1... public key)
# rather than editing this script's own source. It's only ever used to
# encrypt (by that wizard), never needed to decrypt — decrypt reads the
# identity file below instead. Public key, safe to commit.
AGE_RECIPIENT_FILE="$SCRIPT_DIR/piv/recipient"
AGE_RECIPIENT=""
[[ -f "$AGE_RECIPIENT_FILE" ]] && AGE_RECIPIENT="$(<"$AGE_RECIPIENT_FILE")"

AGE_BUNDLE="$SCRIPT_DIR/piv/repo.env.age"
# A local copy in ENCRYPTION_FILES_DIR (this machine just provisioned
# the YubiKey) takes priority over the repo-committed copy — falls
# back to the latter for a fresh machine that has the physical YubiKey
# but hasn't run --encrypt here.
if [[ -f "$ENCRYPTION_FILES_DIR/age-identity.txt" ]]; then
  AGE_IDENTITY="$ENCRYPTION_FILES_DIR/age-identity.txt"
else
  AGE_IDENTITY="$SCRIPT_DIR/piv/age-identity.txt"
fi

# Optional encrypted bundle. Missing file -> silent no-op, every
# profile just uses the plaintext ENV_PERSONAL_REPO_URL/
# ENV_PROFESSIONAL_REPO_URL above instead. If the bundle DOES exist but
# age/age-plugin-yubikey aren't installed yet, that's worth an offer to
# install them (ensure_age_decrypt_tools, lib/common.sh) rather than
# silently skipping straight to the placeholder default and leaving you
# to puzzle out a confusing "no usable entry" error further down with
# no clue why the bundle was never even tried.
REPO_ENV_FILE="$ENVCFG_HOME/repo.env"
HAVE_REPO_ENV=0
if [[ -f "$AGE_BUNDLE" && -f "$AGE_IDENTITY" ]]; then
  ensure_age_decrypt_tools

  if command -v age >/dev/null 2>&1 && command -v age-plugin-yubikey >/dev/null 2>&1; then
    if age --decrypt -i "$AGE_IDENTITY" -o "$REPO_ENV_FILE" "$AGE_BUNDLE" 2>/dev/null; then
      chmod 600 "$REPO_ENV_FILE"
      # shellcheck source=/dev/null
      source "$REPO_ENV_FILE"
      HAVE_REPO_ENV=1
      log "Decrypted piv/repo.env.age -> $REPO_ENV_FILE"
    else
      warn "piv/repo.env.age exists but couldn't be decrypted (YubiKey present? touch confirmed?) — falling back to plaintext ENV_PERSONAL_REPO_URL/ENV_PROFESSIONAL_REPO_URL for every profile."
    fi
  else
    warn "age/age-plugin-yubikey still not available — can't decrypt piv/repo.env.age this run. Falling back to plaintext ENV_PERSONAL_REPO_URL/ENV_PROFESSIONAL_REPO_URL for every profile."
  fi
fi

# Regenerate env-config*.pub from piv/env-config-cert*.pem (one cert per
# physical YubiKey provisioned via --encrypt, numbered when there's
# more than one — see encrypt_wizard.sh). Both are public data; this
# needs no decrypt and no private key, so it runs unconditionally,
# ahead of each profile's install.sh 'git' item further down, which is
# what actually wires the resulting pubkey(s) into ~/.ssh/config via
# wire_yubikey_ssh_config().
regenerate_yubikey_ssh_pubkeys "$SCRIPT_DIR/piv"

# ssh_to_https <ssh_url> — best-effort git@host:path -> https://host/path.
# Only needed when REPO_ACCESS_TOKEN is set: a token attaches to an
# HTTPS remote as a Basic-auth header, but every URL in this script
# (bundle or plaintext default) is written in git@host:path SSH form.
# Anything not matching that exact shape passes through unchanged.
ssh_to_https() {
  local url="$1"
  if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
    printf 'https://%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s\n' "$url"
  fi
}

# clone_or_pull_profile <profile> — profile is "env-personal" or
# "env-professional". The bundle's own variable names drop the "env-"
# prefix (PERSONAL_SSH_URL / PROFESSIONAL_SSH_URL — see
# encrypt_wizard.sh and README.md "Building the encrypted bundle by
# hand"), so that's what gets checked via indirect expansion below.
# Bundle value wins when present; otherwise falls back to the
# plaintext ENV_PERSONAL_REPO_URL/ENV_PROFESSIONAL_REPO_URL default
# above. If the bundle also set REPO_ACCESS_TOKEN (one token, shared
# by both profiles — not per-profile), it wins over SSH entirely: the
# resolved URL gets rewritten to https:// and the token rides along as
# a host-scoped Basic-auth header. No token -> plain SSH, unchanged.
clone_or_pull_profile() {
  local profile="$1" profile_dir="$ENVCFG_HOME/$1"
  local repo_url="" short upper ssh_var url_var auth_note
  local -a token_args=()

  # "env-personal" -> "personal" -> "PERSONAL"; "env-professional" ->
  # "professional" -> "PROFESSIONAL".
  short="${profile#env-}"
  upper="$(printf '%s' "$short" | tr '[:lower:]' '[:upper:]')"
  ssh_var="${upper}_SSH_URL"

  if [[ -n "${!ssh_var:-}" ]]; then
    repo_url="${!ssh_var}"
  elif [[ "$profile" == "env-personal" ]]; then
    repo_url="$ENV_PERSONAL_REPO_URL"
  else
    repo_url="$ENV_PROFESSIONAL_REPO_URL"
  fi

  auth_note="SSH auth — your SSH agent/key handles this"
  if [[ -n "${REPO_ACCESS_TOKEN:-}" ]]; then
    local https_url host user
    https_url="$(ssh_to_https "$repo_url")"
    host="${https_url#https://}"
    host="${host%%/*}"
    case "$host" in
      github.com) user="x-access-token" ;;
      *) user="oauth2" ;;
    esac
    token_args=(-c "http.https://$host/.extraheader=Authorization: Basic $(printf '%s:%s' "$user" "$REPO_ACCESS_TOKEN" | base64 | tr -d '\n')")
    repo_url="$https_url"
    auth_note="HTTPS auth — using REPO_ACCESS_TOKEN from the decrypted bundle"
  fi

  if [[ -d "$profile_dir" && -d "$profile_dir/.git" ]]; then
    log "'$profile' already cloned — pulling latest (shallow)"
    if ! git "${token_args[@]}" -C "$profile_dir" pull --ff-only >/tmp/profile_pull.log 2>&1; then
      warn "git pull in $profile_dir failed — continuing with what's already on disk:"
      sed 's/^/    /' /tmp/profile_pull.log
    fi
    return 0
  fi

  if [[ -d "$profile_dir" ]]; then
    log "'$profile_dir' already exists (not a git repo) — using it as-is."
    return 0
  fi

  if [[ "$repo_url" == *"REPLACE_ME"* || "$repo_url" == *"YOUR_GITHUB_USERNAME"* ]]; then
    url_var="${upper}_REPO_URL"
    echo "$url_var still has a placeholder value, and piv/repo.env.age has" >&2
    echo "no usable entry for '$profile' either — set one or the other. See README.md." >&2
    exit 1
  fi

  log "Shallow-cloning '$profile' from:"
  log "  $repo_url"
  log "  ($auth_note)"
  if ! git "${token_args[@]}" clone --depth 1 "$repo_url" "$profile_dir"; then
    echo "Clone of $repo_url into $profile_dir failed — check the URL and your" >&2
    echo "auth (SSH key loaded / REPO_ACCESS_TOKEN valid) and try again." >&2
    exit 1
  fi
}

for p in "${PROFILES[@]}"; do
  clone_or_pull_profile "$p"
done

# 4. Hand off to each profile's own install.sh — generic dispatch,
#    no component knowledge here.
for p in "${PROFILES[@]}"; do
  profile_dir="$ENVCFG_HOME/$p"
  sub_install="$profile_dir/install.sh"

  if [[ -f "$sub_install" ]]; then
    chmod +x "$sub_install"
    log "Handing off to $p/install.sh for component selection..."
    "$sub_install"
  else
    warn "$sub_install not found — nothing to hand off to for profile '$p'."
    warn "The repo cloned fine, but it has no install.sh of its own yet."
  fi
done

log "Done."
