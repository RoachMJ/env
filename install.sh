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
  : "${BOOTSTRAP_REPO_URL:?Piped execution needs BOOTSTRAP_REPO_URL=<the bootstrap repo clone URL> — see README.md}"
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

  exec bash "$BOOTSTRAP_DIR/install.sh" "$@"
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
#    repos, not folders in this one. Two independent access patterns,
#    picked interactively per profile when more than one applies (see
#    README.md "Repo access: two paths"):
#
#    - Path 1 (SSH): ENV_PERSONAL_REPO_URL / ENV_PROFESSIONAL_REPO_URL
#      below (or *_SSH_URL from the decrypted bundle) is a git@ URL,
#      auth comes from whatever's already in ssh-agent (e.g. a YubiKey
#      PIV key via `ssh-add -s`). No secret in this repo either way.
#    - Path 2 (token): *_HTTPS_URL / *_TOKEN from the decrypted bundle.
#      Clones over HTTPS using the token as a Basic-auth header — never
#      in the URL, never written to env-personal/.git or
#      env-professional/.git config.
#
#    piv/repo.env.age holds both, encrypted to a YubiKey-resident ECC
#    P-256 key (age-plugin-yubikey). It decrypts once per run to
#    $ENVCFG_HOME/repo.env (chmod 600, never committed), which is then
#    sourced directly into this script's environment.
ENV_PERSONAL_REPO_URL="${ENV_PERSONAL_REPO_URL:-git@github.com:YOUR_GITHUB_USERNAME/env-personal.git}"
ENV_PROFESSIONAL_REPO_URL="${ENV_PROFESSIONAL_REPO_URL:-https://REPLACE_ME.example.com/REPLACE_ME_GROUP/env-professional.git}"

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

# Optional Path 2 bundle. Missing file / missing age or
# age-plugin-yubikey / failed decrypt (wrong YubiKey, no touch, no
# PIN) -> silent no-op, every profile just uses Path 1 (or the
# plaintext ENV_PERSONAL_REPO_URL/ENV_PROFESSIONAL_REPO_URL above)
# instead.
REPO_ENV_FILE="$ENVCFG_HOME/repo.env"
HAVE_REPO_ENV=0
if [[ -f "$AGE_BUNDLE" && -f "$AGE_IDENTITY" ]] &&
  command -v age >/dev/null 2>&1 && command -v age-plugin-yubikey >/dev/null 2>&1; then
  if age --decrypt -i "$AGE_IDENTITY" -o "$REPO_ENV_FILE" "$AGE_BUNDLE" 2>/dev/null; then
    chmod 600 "$REPO_ENV_FILE"
    # shellcheck source=/dev/null
    source "$REPO_ENV_FILE"
    HAVE_REPO_ENV=1
    log "Decrypted piv/repo.env.age -> $REPO_ENV_FILE"
  else
    warn "piv/repo.env.age exists but couldn't be decrypted (YubiKey present? touch confirmed?) — falling back to plaintext ENV_PERSONAL_REPO_URL/ENV_PROFESSIONAL_REPO_URL for every profile."
  fi
fi

# url_host <url> — bare host[:port], no scheme, no path.
url_host() {
  local rest="${1#*://}"
  rest="${rest%%/*}"
  printf '%s' "$rest"
}

# choose_auth_path <profile> — echoes "ssh", "token", or "" (nothing
# usable from the decrypted bundle for this profile). Only prompts
# when both are actually available; picks silently otherwise.
choose_auth_path() {
  local profile="$1" upper ssh_var https_var token_var ssh_val https_val token_val
  # tr '-' '_' matters: profile is "env-personal"/"env-professional" —
  # hyphens aren't legal in bash variable names, so ENV-PERSONAL_SSH_URL
  # would never actually resolve via the ${!ssh_var} indirection below.
  upper="$(printf '%s' "$profile" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
  ssh_var="${upper}_SSH_URL"
  https_var="${upper}_HTTPS_URL"
  token_var="${upper}_TOKEN"
  ssh_val="${!ssh_var:-}"
  https_val="${!https_var:-}"
  token_val="${!token_var:-}"

  local have_ssh=0 have_token=0
  [[ -n "$ssh_val" ]] && have_ssh=1
  [[ -n "$https_val" && -n "$token_val" ]] && have_token=1

  if [[ "$have_ssh" == "1" && "$have_token" == "1" ]]; then
    echo >&2
    echo "Two ways to clone '$profile' — which do you want?" >&2
    echo "  1) SSH (Path 1) — $ssh_val" >&2
    echo "  2) Token over HTTPS (Path 2) — $https_val" >&2
    local reply
    read -r -p "> " reply
    case "$reply" in
      2 | token) printf 'token\n' ;;
      *) printf 'ssh\n' ;;
    esac
    return 0
  elif [[ "$have_ssh" == "1" ]]; then
    printf 'ssh\n'
    return 0
  elif [[ "$have_token" == "1" ]]; then
    printf 'token\n'
    return 0
  fi
  printf '\n'
}

clone_or_pull_profile() {
  local profile="$1" profile_dir="$ENVCFG_HOME/$1"
  local repo_url="" auth_note="" chosen="" upper url_var
  local -a token_args=()

  if [[ "$HAVE_REPO_ENV" == "1" ]]; then
    chosen="$(choose_auth_path "$profile")"
  fi

  upper="$(printf '%s' "$profile" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"

  if [[ "$chosen" == "ssh" ]]; then
    local ssh_var="${upper}_SSH_URL"
    repo_url="${!ssh_var}"
    auth_note="SSH auth — your SSH agent/key handles this (Path 1)"
  elif [[ "$chosen" == "token" ]]; then
    local https_var="${upper}_HTTPS_URL" token_var="${upper}_TOKEN"
    local host user token
    repo_url="${!https_var}"
    token="${!token_var}"
    host="$(url_host "$repo_url")"
    case "$host" in
      github.com) user="x-access-token" ;;
      *) user="oauth2" ;;
    esac
    token_args=(-c "http.https://$host/.extraheader=Authorization: Basic $(printf '%s:%s' "$user" "$token" | base64 | tr -d '\n')")
    auth_note="HTTPS auth — using the decrypted repo.env token (Path 2)"
  else
    if [[ "$profile" == "env-personal" ]]; then
      repo_url="$ENV_PERSONAL_REPO_URL"
    else
      repo_url="$ENV_PROFESSIONAL_REPO_URL"
    fi
    case "$repo_url" in
      git@*) auth_note="SSH auth — your SSH agent/key handles this (Path 1)" ;;
      *) auth_note="HTTPS auth — you'll be prompted for a username/password once, then your credential manager caches it" ;;
    esac
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
    echo "auth (SSH key loaded / repo-access token valid) and try again." >&2
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
