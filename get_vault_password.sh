#!/usr/bin/env bash
# ------------------------------------------------------------------
# Ansible Vault password resolver — CAC-primary, password-fallback.
#
# Contract Ansible expects from a --vault-password-file that's executable:
# run it, use stdout (whitespace-trimmed) as the password. Nothing else
# this script prints to stdout matters — everything else goes to stderr.
#
# Resolution order:
#   1. CAC present + readable -> decrypt vault_password.enc via the card's
#      PIV private key over PKCS#11. The card's own middleware prompts
#      for the PIN directly (masked) — the PIN never touches this script,
#      is never stored, and is never passed as a CLI argument (which
#      would leak it into `ps` output).
#   2. CAC missing, no reader, wrong card, decrypt fails for any reason
#      -> fall back to typing the vault password directly at a masked
#      prompt. This is the documented backup path, not an error state.
#
# Install location: ~/.secrets/openai/get_vault_password.sh
# (co-located with vault_password.enc and vault.yml — see README-secrets-vault.md)
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENC_VAULT_PW="$SCRIPT_DIR/vault_password.enc"

# --- Adjust these two to match your actual card/reader/middleware ---------
# PKCS11_MODULE: OpenSC's PKCS#11 module. install.sh installs OpenSC via
#   Homebrew; this is the standard path it lands at on Apple Silicon.
#   Intel Macs: /usr/local/lib/opensc-pkcs11.so
# CAC_KEY_ID: the PIV key slot id for the certificate you encrypted
#   vault_password.enc against. "01" (PIV Authentication) is the common
#   default, but confirm with:
#     pkcs11-tool --module "$PKCS11_MODULE" -O
#   which lists every object on the card along with its ID.
PKCS11_MODULE="${PKCS11_MODULE:-/opt/homebrew/lib/opensc-pkcs11.so}"
CAC_KEY_ID="${CAC_KEY_ID:-01}"
# ---------------------------------------------------------------------------

try_cac() {
    command -v pkcs11-tool >/dev/null 2>&1 || return 1
    [[ -f "$ENC_VAULT_PW" ]] || return 1
    [[ -f "$PKCS11_MODULE" ]] || return 1

    # Confirm a card is actually inserted before attempting a decrypt —
    # avoids a confusing PKCS#11 error when the reader is just empty.
    # The exact substring here ("token present") matches OpenSC's default
    # pkcs11-tool output; verify against your own `--list-slots` output
    # if this check ever silently skips a card that IS present.
    pkcs11-tool --module "$PKCS11_MODULE" --list-slots 2>/dev/null \
        | grep -qi "token present" || return 1

    # No -p/--pin flag on purpose: pkcs11-tool prompts for it directly
    # (masked) when login is required and none is supplied on the CLI.
    pkcs11-tool \
        --module "$PKCS11_MODULE" \
        --decrypt \
        --id "$CAC_KEY_ID" \
        -m RSA-PKCS \
        --input-file "$ENC_VAULT_PW" \
        2>/dev/null
}

PASSWORD="$(try_cac || true)"

if [[ -n "$PASSWORD" ]]; then
    printf '%s' "$PASSWORD"
    exit 0
fi

# -- Fallback: CAC unavailable or decrypt failed ----------------------------
# This IS the vault password itself, typed by hand. It's never written to
# disk by this script — it exists only in this process's memory for the
# moment ansible-vault reads it back off stdout.
>&2 printf "CAC not available (or decrypt failed) — falling back to password.\n"
>&2 printf "Vault password: "
read -r -s PASSWORD < /dev/tty
>&2 printf "\n"

if [[ -z "$PASSWORD" ]]; then
    >&2 printf "No password entered — aborting.\n"
    exit 1
fi

printf '%s' "$PASSWORD"
