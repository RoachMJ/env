#!/usr/bin/env bash
# ------------------------------------------------------------------
# Author: Mike Roach (https://github.com/RoachMJ)
# ------------------------------------------------------------------
# One-time setup wizard, run via `./install.sh --encrypt`. Provisions
# the YubiKey (SSH auth key in PIV slot 9a, ECC P-256 encryption key
# in a retired PIV slot via age-plugin-yubikey) and builds the
# encrypted piv/repo.env.age bundle that step 3 of install.sh reads.
#
# See README.md, "One-time setup: the --encrypt wizard" for the full
# walkthrough, what each step below does, and how to run any of it by
# hand if the automation here doesn't match your installed tool
# versions — age-plugin-yubikey's exact flags have changed across
# releases, so treat this as a starting point, not gospel, and check
# `age-plugin-yubikey --help` against what's actually installed before
# trusting it blindly. None of this has been run against physical
# YubiKey hardware in the environment this was written in.
#
# Sourced by install.sh, not run directly — expects SCRIPT_DIR,
# ENVCFG_HOME, ENCRYPTION_FILES_DIR, and log/warn/detect_os/
# install_pkgs (from lib/common.sh) already in scope.
# ------------------------------------------------------------------

run_encrypt_wizard() {
  if [[ ! -t 0 ]]; then
    echo "--encrypt needs an interactive terminal (PINs, YubiKey touch, repo URLs/tokens)." >&2
    exit 1
  fi

  detect_os
  mkdir -p "$ENCRYPTION_FILES_DIR"
  chmod 700 "$ENCRYPTION_FILES_DIR"

  _encrypt_check_ykman
  _encrypt_check_age_tools
  _encrypt_ssh_slot
  _encrypt_ecc_slot
  _encrypt_build_bundle

  log "Done. Review what changed under piv/ (repo.env.age, age-identity.txt,"
  log "recipient, env-config-cert.pem — numbered variants too if this is a"
  log "second/backup YubiKey) and commit it — install.sh's own source"
  log "doesn't change:"
  log "  git add piv/"
  log "  git commit -m '🔐 provision YubiKey repo-access encryption'"
}

_encrypt_check_ykman() {
  if command -v ykman >/dev/null 2>&1; then
    return 0
  fi
  warn "ykman (YubiKey Manager CLI) not found."
  local reply
  read -r -p "Install it now? [Y/n] " reply
  case "$reply" in
    n | N)
      echo "ykman is required for the rest of this wizard — install it and re-run --encrypt." >&2
      exit 1
      ;;
  esac
  install_pkgs "ykman" "yubikey-manager" "yubikey-manager"
  if ! command -v ykman >/dev/null 2>&1; then
    warn "ykman still not found after install — some package managers ship it"
    warn "as 'yubikey-manager' with no 'ykman' binary alias. Install manually:"
    warn "  pip install --user yubikey-manager   (works everywhere pip does)"
    exit 1
  fi
}

_encrypt_check_age_tools() {
  local need_age=1 need_plugin=1
  command -v age >/dev/null 2>&1 && need_age=0
  command -v age-plugin-yubikey >/dev/null 2>&1 && need_plugin=0

  if [[ "$need_age" == "0" && "$need_plugin" == "0" ]]; then
    log "age and age-plugin-yubikey already installed — skipping."
    return 0
  fi

  # Only pass along the ones actually missing — install_pkgs itself
  # doesn't check, it installs whatever names you hand it (that's on
  # us to get right here, not on it).
  local mac_missing=() apt_missing=()
  [[ "$need_age" == "1" ]] && mac_missing+=(age) && apt_missing+=(age)
  [[ "$need_plugin" == "1" ]] && mac_missing+=(age-plugin-yubikey)
  # apt has no age-plugin-yubikey package as of this writing — Linux
  # users needing it fall through to the manual cargo/GitHub-release
  # instructions below regardless.

  # "${arr[*]:-}", not plain "${arr[*]}": either array can genuinely be
  # empty here (e.g. only age-plugin-yubikey missing -> apt_missing
  # stays empty), and macOS's stock /bin/bash (3.2) treats an empty
  # array reference as unset under this script's `set -u`. `:-`
  # explicitly asks for the empty-string fallback, which is also
  # exactly what install_pkgs expects for "nothing to install" here.
  install_pkgs "${mac_missing[*]:-}" "${apt_missing[*]:-}" ""

  if ! command -v age-plugin-yubikey >/dev/null 2>&1; then
    warn "age-plugin-yubikey not found via package manager — install manually:"
    warn "  cargo install age-plugin-yubikey   (needs Rust/cargo)"
    warn "  or grab a release from https://github.com/str4d/age-plugin-yubikey/releases"
    exit 1
  fi
}

# SSH auth key — PIV slot 9a. Same PIV mechanism the CAC-backed signing
# section of git-config/README.md uses, just on a YubiKey instead of a
# CAC, and used here for repo-access SSH rather than commit signing.
#
# NOTE on "passphrase": there isn't one, on purpose. This is a
# hardware-resident key — the private key never leaves the YubiKey, so
# there's no local key file for a software passphrase to protect (unlike
# a normal `ssh-keygen` key, which ships as a file on disk that a
# passphrase encrypts). The equivalent protections here are the PIV PIN
# (required to use the key at all) and the pin-policy/touch-policy
# below, which control *how often* that PIN/touch is re-demanded.
_encrypt_ssh_slot() {
  log "Checking PIV slot 9a (SSH auth key)..."
  echo "One device per run. If you're setting up a second physical YubiKey"
  echo "as a backup login (recommended if any server only trusts SSH keys,"
  echo "no password fallback), just re-run './install.sh --encrypt' later"
  echo "with that key inserted, then register its env-config.pub on the"
  echo "same servers alongside this one — losing one YubiKey then only"
  echo "means removing that one key from each server's authorized_keys,"
  echo "not being locked out."
  echo
  echo "Insert the YubiKey you want to use, then press Enter."
  read -r -p "> " _

  local overwrite_occupied=0
  if ykman piv info 2>/dev/null | grep -qi "slot 9a"; then
    warn "This YubiKey's slot 9a already has a key."
    echo "  1) Leave it alone — just re-export its existing public key"
    echo "  2) Overwrite it with a new key (the old key stops working"
    echo "     immediately, on every server it was registered on, the"
    echo "     moment the new one is generated)"
    local reply
    read -r -p "> [1] " reply
    case "$reply" in
      2)
        overwrite_occupied=1
        # NOTE on how this overwrite works: we deliberately never call
        # `ykman piv keys delete` / `ykman piv certificates delete` here.
        # Those are a newer, separate ykman subcommand pair that requires
        # YubiKey firmware 5.7.0+ ("This action requires YubiKey 5.7.0 or
        # later" if you're on older firmware — this is what the earlier
        # bug report hit). They're unnecessary for what we're doing:
        # `ykman piv keys generate` / `ykman piv certificates generate`
        # perform PIV's standard GENERATE ASYMMETRIC KEY PAIR command,
        # which replaces whatever was already in the slot as part of
        # generating the new key — supported on every YubiKey PIV
        # firmware version, going back to the YubiKey 4. This is also
        # almost certainly what the desktop YubiKey Manager GUI's
        # "generate new key" button does under the hood, which is why it
        # works there even when the CLI's dedicated `delete` subcommand
        # doesn't on the same hardware. So: no separate delete step, no
        # firmware-version gate to check — just generate straight over
        # the old key below.
        log "Slot 9a will be overwritten by the new key generated below"
        log "(no separate delete step — see comment in encrypt_wizard.sh"
        log "if you're curious why)."
        ;;
      *)
        (
          cd "$ENCRYPTION_FILES_DIR" &&
            ykman piv certificates export 9a env-config-cert.pem &&
            # env-config-cert.pem is an X.509 CERTIFICATE — ssh-keygen's
            # `-m PKCS8` import can't read one directly ("not a
            # recognised public key format"). Pull just the
            # SubjectPublicKeyInfo block out with openssl first.
            openssl x509 -in env-config-cert.pem -pubkey -noout >env-config-pubkey.pkcs8.tmp &&
            ssh-keygen -f env-config-pubkey.pkcs8.tmp -i -m PKCS8 >env-config.pub &&
            rm -f env-config-pubkey.pkcs8.tmp
        ) || warn "Couldn't re-export the existing key — see output above."
        log "Public key (re-exported from the existing slot 9a key) written"
        log "to $ENCRYPTION_FILES_DIR/env-config.pub"
        if [[ -f "$ENCRYPTION_FILES_DIR/env-config-cert.pem" ]]; then
          mkdir -p "$SCRIPT_DIR/piv"
          local piv_cert_dest
          piv_cert_dest="$(_next_numbered_dest "$SCRIPT_DIR/piv/env-config-cert.pem")"
          cp "$ENCRYPTION_FILES_DIR/env-config-cert.pem" "$piv_cert_dest"
          log "Also copied to $piv_cert_dest — commit it (git add piv/) so"
          log "install.sh can regenerate this pubkey on any machine from a"
          log "bare clone plus this physical YubiKey."
        fi
        return 0
        ;;
    esac
  fi

  if [[ -f "$ENCRYPTION_FILES_DIR/env-config.pub" ]]; then
    warn "$ENCRYPTION_FILES_DIR/env-config.pub already exists (from a"
    warn "previous run — a different YubiKey, most likely) and is about to"
    warn "be overwritten. If you still need that old public key on file"
    warn "(e.g. to double check what you registered on a server), copy it"
    warn "somewhere else first — Ctrl-C now, otherwise Enter to continue."
    read -r -p "> " _
  fi

  echo
  echo "A few options for the SSH key (defaults shown — just press Enter to"
  echo "accept any of them):"
  echo

  local algorithm pin_policy touch_policy subject_cn subject_email comment

  echo "Algorithm — ECCP256 is what the rest of this repo's docs assume and"
  echo "is supported on every YubiKey PIV-capable model; only pick something"
  echo "else if you have a specific reason to (e.g. a server that requires"
  echo "RSA):"
  echo "  1) ECCP256 (default)   2) ECCP384   3) RSA2048"
  read -r -p "> [1] " _alg_choice
  case "$_alg_choice" in
    2) algorithm="ECCP384" ;;
    3) algorithm="RSA2048" ;;
    *) algorithm="ECCP256" ;;
  esac

  echo
  echo "PIN policy — how often the PIV PIN is re-demanded to use this key."
  echo "Example: DEFAULT/ONCE both mean 'enter the PIN once when you load"
  echo "the key into ssh-agent (ssh-add -s ...), not again until that agent"
  echo "session ends' — that's what the rest of this repo's docs assume:"
  echo "  1) DEFAULT (device default — usually same as ONCE)"
  echo "  2) ONCE    3) ALWAYS (re-prompt every single SSH connection)"
  echo "  4) NEVER (no PIN ever required — not recommended)"
  read -r -p "> [1] " _pin_choice
  case "$_pin_choice" in
    2) pin_policy="ONCE" ;;
    3) pin_policy="ALWAYS" ;;
    4) pin_policy="NEVER" ;;
    *) pin_policy="DEFAULT" ;;
  esac

  echo
  echo "Touch policy — whether a physical touch on the YubiKey is also"
  echo "required, separate from the PIN. Example: ALWAYS means every SSH"
  echo "connection needs a touch, even within the same agent session —"
  echo "CACHED relaxes that to one touch per ~15 seconds of activity:"
  echo "  1) DEFAULT (device default — usually off)"
  echo "  2) ALWAYS   3) CACHED (touch once, reused for ~15s)   4) NEVER"
  read -r -p "> [1] " _touch_choice
  case "$_touch_choice" in
    2) touch_policy="ALWAYS" ;;
    3) touch_policy="CACHED" ;;
    4) touch_policy="NEVER" ;;
    *) touch_policy="DEFAULT" ;;
  esac

  echo
  echo "Certificate subject CN — a label identifying this specific key,"
  echo "e.g. env-config-ssh, env-config-ssh-laptop, or jdoe-ssh-backup-1 if"
  echo "you're distinguishing a primary key from a backup one:"
  read -r -p "> [env-config-ssh] " subject_cn
  subject_cn="${subject_cn:-env-config-ssh}"

  echo
  echo "Email to embed in the certificate subject, and as the comment on"
  echo "the exported public key — e.g. you@example.com. Optional, mainly"
  echo "useful for telling keys apart later in a server's authorized_keys"
  echo "file or an SSH provider's key list:"
  read -r -p "> " subject_email

  local subject="CN=$subject_cn"
  [[ -n "$subject_email" ]] && subject="$subject/emailAddress=$subject_email"
  comment="${subject_email:-$subject_cn}"

  echo
  echo "Certificate validity — how long before this key needs to be"
  echo "reprovisioned (the certificate is just a label on the key; you can"
  echo "always re-run this wizard early to rotate it sooner than this):"
  echo "  1) 1 year (default)   2) 2 years   3) 3 years   4) 4 years"
  echo "  5) 5 years            6) Never (effectively permanent — 100 years)"
  local _valid_choice valid_days
  read -r -p "> [1] " _valid_choice
  case "$_valid_choice" in
    2) valid_days=730 ;;
    3) valid_days=1095 ;;
    4) valid_days=1460 ;;
    5) valid_days=1825 ;;
    6) valid_days=36500 ;;
    *) valid_days=365 ;;
  esac

  if [[ "$overwrite_occupied" == "1" ]]; then
    warn "About to overwrite the existing key in slot 9a. This cannot be"
    warn "undone — Ctrl-C now if you want to back out, otherwise Enter to"
    warn "continue."
    read -r -p "> " _
  fi

  log "Generating a $algorithm key in PIV slot 9a for SSH (pin-policy=$pin_policy, touch-policy=$touch_policy)..."
  (
    cd "$ENCRYPTION_FILES_DIR" &&
      ykman piv keys generate --algorithm "$algorithm" --pin-policy "$pin_policy" --touch-policy "$touch_policy" 9a pubkey-9a.pem &&
      ykman piv certificates generate --subject "$subject" --valid-days "$valid_days" 9a pubkey-9a.pem &&
      ykman piv certificates export 9a env-config-cert.pem &&
      ssh-keygen -f pubkey-9a.pem -i -m PKCS8 >env-config.pub.tmp &&
      awk -v c="$comment" '{print $1, $2, c}' env-config.pub.tmp >env-config.pub &&
      rm -f pubkey-9a.pem env-config.pub.tmp
  ) || {
    warn "SSH slot provisioning failed partway through — see the output above."
    warn "The manual command sequence is in README.md if you'd rather run it"
    warn "yourself step by step. Nothing before the failed command was left"
    warn "half-configured on the key itself; ykman's own steps are atomic."
    return 0
  }
  log "SSH public key written to $ENCRYPTION_FILES_DIR/env-config.pub —"
  log "add it to GitHub/GitLab (or a server's authorized_keys) as an SSH key"
  log "(see README.md)."
  log "Also saved $ENCRYPTION_FILES_DIR/env-config-cert.pem — a backup of the"
  log "PUBLIC certificate only, letting you re-export env-config.pub later"
  log "(openssl x509 -in env-config-cert.pem -pubkey -noout | ssh-keygen -f"
  log "/dev/stdin -i -m PKCS8) without needing the physical YubiKey present"
  log "— install.sh's regenerate_yubikey_ssh_pubkeys does exactly this"
  log "automatically. There's no equivalent for the private key,"
  log "on purpose: it's generated on the YubiKey's own chip and never"
  log "leaves it, in any form — that's what \"hardware-backed\" means here."

  mkdir -p "$SCRIPT_DIR/piv"
  local piv_cert_dest
  piv_cert_dest="$(_next_numbered_dest "$SCRIPT_DIR/piv/env-config-cert.pem")"
  cp "$ENCRYPTION_FILES_DIR/env-config-cert.pem" "$piv_cert_dest"
  log "Also copied to $piv_cert_dest — commit it (git add piv/) so"
  log "install.sh can regenerate this pubkey on any machine from a bare"
  log "clone plus this physical YubiKey, no wizard re-run needed there."

  log "For a backup login path, provision a second physical YubiKey (re-run"
  log "this wizard with it inserted) — its cert lands in piv/ alongside"
  log "this one (auto-numbered) and install.sh wires both in as valid"
  log "IdentityFile entries, so losing either key alone doesn't lock you"
  log "out. Register both public keys on your git host either way."
}

# Encryption key — one of age-plugin-yubikey's 20 "retired slots"
# (its own --slot numbering, 1-20 — NOT the same numbers as the PIV
# hex slot names ykman uses; slot 1 here is PIV hex slot 0x82, slot 20
# is 0x95). ECC P-256, provisioned via age-plugin-yubikey. This is the
# key piv/repo.env.age gets encrypted to.
_encrypt_ecc_slot() {
  log "Checking for an existing age-plugin-yubikey recipient on this key..."
  local existing
  existing="$(age-plugin-yubikey --list 2>/dev/null || true)"

  if [[ -n "$existing" ]]; then
    warn "This YubiKey already has at least one age-plugin-yubikey identity:"
    printf '%s\n' "$existing" | sed 's/^/    /'
    echo
    local reply
    read -r -p "Reuse one of these? [Y/n] " reply
    case "$reply" in
      n | N) _encrypt_generate_ecc_slot ;;
      *)
        warn "Reusing an existing identity needs its exact slot number (1-20,"
        warn "age-plugin-yubikey's own numbering, shown in the '--list' output above)."
        local slot
        read -r -p "Slot number (e.g. 1), or blank to generate a new one instead: " slot
        if [[ -n "$slot" ]]; then
          age-plugin-yubikey --identity --slot "$slot" >"$ENCRYPTION_FILES_DIR/age-identity.txt"
        else
          _encrypt_generate_ecc_slot
        fi
        ;;
    esac
  else
    _encrypt_generate_ecc_slot
  fi

  # This comment line (not the AGE-PLUGIN-YUBIKEY-... identity line
  # itself) is what we parse the recipient back out of — see the note
  # on age-identity.txt's format above _encrypt_generate_ecc_slot below.
  AGE_RECIPIENT="$(grep -i '^# *recipient:' "$ENCRYPTION_FILES_DIR/age-identity.txt" 2>/dev/null | sed 's/^# *[Rr]ecipient: *//' | head -n1)"
  if [[ -z "$AGE_RECIPIENT" ]]; then
    warn "Couldn't find a '# Recipient: age1yubikey1...' line in the generated"
    warn "identity file — run 'age-plugin-yubikey --list' yourself and copy the"
    warn "recipient into piv/recipient (one line, just the age1yubikey1..."
    warn "string, no quotes) by hand."
    return 0
  fi

  log "Recipient: $AGE_RECIPIENT"
  mkdir -p "$SCRIPT_DIR/piv"
  local piv_identity_dest
  piv_identity_dest="$(_next_numbered_dest "$SCRIPT_DIR/piv/age-identity.txt")"
  cp "$ENCRYPTION_FILES_DIR/age-identity.txt" "$piv_identity_dest"
  log "Copied to $piv_identity_dest"
  if [[ "$piv_identity_dest" != "$SCRIPT_DIR/piv/age-identity.txt" ]]; then
    warn "Note: install.sh's decrypt step only reads piv/age-identity.txt"
    warn "(the unnumbered one) — this numbered copy is a record of the"
    warn "second key, not yet an alternate decrypt path. repo.env.age"
    warn "itself is still encrypted to whichever single recipient is in"
    warn "piv/recipient (just overwritten above), so decrypt still needs"
    warn "that specific key's YubiKey. Ask if you want multi-recipient"
    warn "decrypt too — that's a bigger change to _encrypt_build_bundle."
  fi

  # A short, well-known, plain-text file — not a literal edited into
  # install.sh's own source. It's a public key, so it's fine to commit;
  # keeping it out of install.sh means the script's source never
  # changes just because you rotated hardware.
  printf '%s\n' "$AGE_RECIPIENT" >"$SCRIPT_DIR/piv/recipient"
  log "Wrote the recipient to piv/recipient."
}

_encrypt_generate_ecc_slot() {
  log "Generating an ECC P-256 key in a retired PIV slot for encryption..."
  log "(age-plugin-yubikey's own slot numbering: 1-20, not the PIV hex names"
  log "ykman uses for the SSH slot above — slot 1 here is PIV hex slot 0x82.)"

  local all_slots recommended=""
  all_slots="$(age-plugin-yubikey --list-all 2>/dev/null || true)"
  if [[ -n "$all_slots" ]]; then
    echo "Current state of all 20 slots on this key:"
    printf '%s\n' "$all_slots" | sed 's/^/    /'
    echo
    # Best-effort: age-plugin-yubikey's own output format for an unused
    # slot has varied across releases, so this is a guess, not gospel —
    # look for the first "Slot N" line that also mentions "empty" on
    # the same line (case-insensitive). Read the printout above
    # yourself before trusting this recommendation.
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
    echo "No slot chosen and nothing to recommend — re-run and pick one from the list above." >&2
    return 1
  fi

  age-plugin-yubikey --generate --slot "$slot" --name env-config-repo-access \
    >"$ENCRYPTION_FILES_DIR/age-identity.txt"
}

_encrypt_build_bundle() {
  if [[ -z "${AGE_RECIPIENT:-}" ]]; then
    warn "No recipient available — skipping piv/repo.env.age. Fix the"
    warn "encryption-key step above and re-run --encrypt."
    return 0
  fi

  echo
  echo "Now the repo SSH URLs to encrypt. Leave a field blank to skip it —"
  echo "you don't need both filled in, and this is only ever readable with"
  echo "the physical YubiKey that generated the recipient above."
  echo

  local personal_ssh professional_ssh repo_access_token

  read -r -p "env-personal repo — SSH URL (git@..., or blank): " personal_ssh
  read -r -p "env-professional repo — SSH URL (git@..., or blank): " professional_ssh

  echo
  echo "Optional: a single repo-access token, shared by both profiles,"
  echo "used instead of SSH (over HTTPS) if set. Leave blank to stick with"
  echo "plain SSH — that's the normal case if ssh-agent already has your"
  echo "key loaded."
  read -r -s -p "Repo access token (or blank): " repo_access_token
  echo

  local plain
  plain="$(mktemp)"
  {
    echo "# repo.env — decrypted at clone time by install.sh and sourced"
    echo "# directly into its environment. Only piv/repo.env.age (the"
    echo "# encrypted form of this file) is ever committed — never this."
    [[ -n "$personal_ssh" ]] && echo "PERSONAL_SSH_URL=$personal_ssh"
    [[ -n "$professional_ssh" ]] && echo "PROFESSIONAL_SSH_URL=$professional_ssh"
    [[ -n "$repo_access_token" ]] && echo "REPO_ACCESS_TOKEN=$repo_access_token"
  } >"$plain"

  mkdir -p "$SCRIPT_DIR/piv"
  age -r "$AGE_RECIPIENT" -o "$SCRIPT_DIR/piv/repo.env.age" "$plain"
  shred -u "$plain" 2>/dev/null || rm -f "$plain"

  log "Wrote $SCRIPT_DIR/piv/repo.env.age"
}
