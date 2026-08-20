#!/usr/bin/env bash
# ------------------------------------------------------------------
# Author: Mike Roach (https://github.com/RoachMJ)
# ------------------------------------------------------------------
# Generalized age-encryption wizard for "one required secret file" in
# a profile repo — run via a profile's own `./install.sh --encrypt-secret
# [name]`. Not tied to any one secret: builds `piv/<name>.age` under
# that profile's own piv/ folder, sealed to a YubiKey age-plugin-yubikey
# identity, the same mechanism the bootstrap repo's `--encrypt` wizard
# (lib/encrypt_wizard.sh) uses for the repo-access bundle. Originally
# written for OPENAI_API_KEY (env-professional/piv/openai-api-key.age)
# but the name/value are both prompted for, so it works for any
# short secret a profile needs at rest: another provider's API key, a
# webhook token, anything you'd otherwise hand-roll the same `age -r
# ... -o ...` one-liner for.
#
# One recipient (one YubiKey identity) can encrypt any number of
# independent secrets — reuses the profile's own piv/age-identity.txt
# if one already exists, offers to copy the bootstrap repo's
# env/piv/age-identity.txt if that exists instead (same physical
# YubiKey, no need to re-provision), and only falls through to
# age-plugin-yubikey's own interactive provisioning as a last resort.
#
# Never writes the plaintext secret to disk: it's read via `read -s`
# straight into a shell variable and piped directly into `age`, the
# same way lib/encrypt_wizard.sh's repo-access bundle step avoids a
# plaintext file lingering on disk (that one uses a temp file + shred
# since it's building a multi-line env file; a single secret value
# doesn't need even that — piping means there's never a plaintext copy
# on disk to shred in the first place).
#
# Sourced by a profile's install.sh, not run directly — expects
# PROFILE_DIR, SCRIPT_DIR, and log/warn/detect_os/install_pkgs (from
# lib/common.sh) already in scope.
# ------------------------------------------------------------------

run_secret_wizard() {
  local name="${1:-}"

  if [[ ! -t 0 ]]; then
    echo "--encrypt-secret needs an interactive terminal (YubiKey PIN/touch, the secret value itself)." >&2
    exit 1
  fi

  detect_os
  _secret_check_age_tools

  if [[ -z "$name" ]]; then
    echo
    echo "What is this secret for? Short, filename-safe label — e.g."
    echo "openai-api-key, some-service-token, a-webhook-secret. Becomes"
    echo "piv/<name>.age:"
    read -r -p "> " name
  fi
  # Filesystem-safe: collapse anything that isn't alnum/underscore/hyphen.
  name="$(printf '%s' "$name" | tr -c 'a-zA-Z0-9_-' '-')"
  if [[ -z "$name" || "$name" == "-" ]]; then
    echo "No usable name given — nothing to do." >&2
    exit 1
  fi

  local piv_dir="$PROFILE_DIR/piv"
  mkdir -p "$piv_dir"
  local out_file="$piv_dir/$name.age"

  if [[ -f "$out_file" ]]; then
    warn "$out_file already exists."
    local reply
    read -r -p "Overwrite it with a new value? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy] ]]; then
      log "Leaving $out_file as-is."
      exit 0
    fi
  fi

  _secret_get_identity "$piv_dir"
  if [[ -z "${SECRET_AGE_RECIPIENT:-}" ]]; then
    echo "No recipient available — can't encrypt. See warnings above and either" >&2
    echo "fix the identity file by hand or re-run --encrypt-secret." >&2
    exit 1
  fi

  echo
  echo "Paste the secret value now (input hidden, Enter when done — this"
  echo "goes straight into age, never written to disk unencrypted):"
  local secret_value
  read -r -s -p "> " secret_value
  echo
  if [[ -z "$secret_value" ]]; then
    echo "Empty value entered — nothing to do." >&2
    exit 1
  fi

  # No trailing newline in the ciphertext — printf, not echo, and no -n
  # needed since printf never adds one. Whatever reads this back later
  # (a load_<name>_key-style shell function, same pattern as
  # load_openai_key in zshrc) gets exactly the bytes typed above.
  printf '%s' "$secret_value" | age -r "$SECRET_AGE_RECIPIENT" -o "$out_file"
  unset secret_value

  log "Wrote $out_file"
  echo
  echo "Commit it (and piv/age-identity.txt too, if this run generated or"
  echo "copied a new one — check 'git status' first):"
  echo "  git add $out_file"
  echo "  git commit -m \"add $name secret\""
  echo
  echo "Decrypt on demand at runtime — never bake the plaintext into a"
  echo "config file or export it automatically at shell startup. See"
  echo "piv/README.md's \"Daily usage\" section (load_openai_key in zshrc"
  echo "is the existing template — copy/rename it for a new secret) or"
  echo "run it directly:"
  echo "  age --decrypt -i $piv_dir/age-identity.txt $out_file"
}

_secret_check_age_tools() {
  local need_age=1 need_plugin=1
  command -v age >/dev/null 2>&1 && need_age=0
  command -v age-plugin-yubikey >/dev/null 2>&1 && need_plugin=0

  if [[ "$need_age" == "0" && "$need_plugin" == "0" ]]; then
    return 0
  fi

  local mac_missing=() apt_missing=()
  [[ "$need_age" == "1" ]] && mac_missing+=(age) && apt_missing+=(age)
  [[ "$need_plugin" == "1" ]] && mac_missing+=(age-plugin-yubikey)
  # apt has no age-plugin-yubikey package — Linux users needing it fall
  # through to the manual cargo/GitHub-release instructions below.
  install_pkgs "${mac_missing[*]}" "${apt_missing[*]}" ""

  if ! command -v age-plugin-yubikey >/dev/null 2>&1; then
    warn "age-plugin-yubikey not found via package manager — install manually:"
    warn "  cargo install age-plugin-yubikey   (needs Rust/cargo)"
    warn "  or grab a release from https://github.com/str4d/age-plugin-yubikey/releases"
    exit 1
  fi
}

# Sets SECRET_AGE_RECIPIENT. Priority, cheapest/most-reused first:
#   1. This profile's own piv/age-identity.txt, if it already exists.
#   2. The bootstrap repo's env/piv/age-identity.txt, offered as a copy
#      (same physical YubiKey, same recipient, zero new provisioning).
#   3. An identity already on the inserted YubiKey (age-plugin-yubikey
#      --list), reusable by slot number.
#   4. A brand-new identity in a fresh retired PIV slot.
_secret_get_identity() {
  local piv_dir="$1" identity_file="$1/age-identity.txt"
  SECRET_AGE_RECIPIENT=""

  if [[ -f "$identity_file" ]]; then
    log "Reusing this profile's existing piv/age-identity.txt."
  else
    local bootstrap_identity="$SCRIPT_DIR/../env/piv/age-identity.txt"
    if [[ -f "$bootstrap_identity" ]]; then
      echo "No piv/age-identity.txt in this profile yet, but the bootstrap repo"
      echo "has one (env/piv/age-identity.txt) — same physical YubiKey; one"
      echo "recipient can encrypt any number of independent secrets."
      local reply
      read -r -p "Reuse that identity for this profile too? [Y/n] " reply
      if [[ ! "$reply" =~ ^[Nn] ]]; then
        cp "$bootstrap_identity" "$identity_file"
        log "Copied to $identity_file."
      fi
    fi
  fi

  if [[ ! -f "$identity_file" ]]; then
    echo
    echo "No existing identity to reuse — checking this YubiKey directly:"
    local existing
    existing="$(age-plugin-yubikey --list 2>/dev/null || true)"
    if [[ -n "$existing" ]]; then
      warn "This YubiKey already has at least one age-plugin-yubikey identity:"
      printf '%s\n' "$existing" | sed 's/^/    /'
      local slot
      read -r -p "Reuse a slot number from above (blank to generate a new one instead): " slot
      if [[ -n "$slot" ]]; then
        age-plugin-yubikey --identity --slot "$slot" >"$identity_file"
      fi
    fi
    if [[ ! -f "$identity_file" ]]; then
      _secret_generate_identity "$identity_file"
    fi
  fi

  if [[ ! -f "$identity_file" ]]; then
    warn "No identity file was produced — can't determine a recipient."
    return 0
  fi

  SECRET_AGE_RECIPIENT="$(grep -i '^# *recipient:' "$identity_file" 2>/dev/null | sed 's/^# *[Rr]ecipient: *//' | head -n1)"
  if [[ -z "$SECRET_AGE_RECIPIENT" ]]; then
    warn "Couldn't find a '# Recipient: age1yubikey1...' line in $identity_file —"
    warn "run 'age-plugin-yubikey --list' yourself and encrypt by hand:"
    warn "  age -r age1yubikey1... -o $piv_dir/<name>.age"
  else
    log "Recipient: $SECRET_AGE_RECIPIENT"
  fi
}

_secret_generate_identity() {
  local identity_file="$1"
  log "Generating a new ECC P-256 identity in a retired PIV slot..."
  log "(age-plugin-yubikey's own slot numbering: 1-20, not the PIV hex names"
  log "used elsewhere for SSH keys — see env/README.md's 'Repo access'"
  log "section for the exact mapping if you need it.)"

  local all_slots recommended=""
  all_slots="$(age-plugin-yubikey --list-all 2>/dev/null || true)"
  if [[ -n "$all_slots" ]]; then
    echo "Current state of all 20 slots on this key:"
    printf '%s\n' "$all_slots" | sed 's/^/    /'
    echo
    # Best-effort, same caveat as lib/encrypt_wizard.sh's identical
    # logic: age-plugin-yubikey's own "empty slot" wording has varied
    # across releases — read the printout above yourself before
    # trusting this recommendation.
    recommended="$(printf '%s\n' "$all_slots" |
      grep -i -m1 'slot.*empty' |
      grep -o -E '[0-9]+' | head -n1 || true)"
  else
    warn "'age-plugin-yubikey --list-all' returned nothing (older version? no"
    warn "key inserted?) — can't suggest a free slot automatically."
  fi

  local prompt="Which slot (1-20)"
  if [[ -n "$recommended" ]]; then
    prompt="$prompt [recommended: $recommended, looks empty above]"
  fi
  local slot
  read -r -p "$prompt: " slot
  slot="${slot:-$recommended}"
  if [[ -z "$slot" ]]; then
    warn "No slot chosen — can't generate an identity. Re-run and pick one from the list above."
    return 1
  fi

  age-plugin-yubikey --generate --slot "$slot" --name "env-config-secret" \
    >"$identity_file"
}
