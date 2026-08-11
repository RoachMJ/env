# CAC-gated Ansible Vault for OPENAI_API_KEY

How the API key is stored at rest, why it's structured this way, the
one-time setup, and daily usage.

**Read this before relying on it:** the CAC/PKCS#11 interaction below
couldn't be tested against real smart-card hardware while building this —
there's no physical CAC/reader available in the environment this was
written in. The `ansible-vault` and password-fallback paths were tested;
the `pkcs11-tool` command shapes are correct per OpenSC's documentation,
but the exact `--id` slot number and the `"token present"` string match in
`get_vault_password.sh` should be verified against your actual card and
reader before you trust this for anything real. Run the commands in
"Step 1" below and confirm the output looks sane before wiring the rest
together.

## How it fits together

Two layers, not one:

1. **The API key itself** lives in `~/.secrets/openai/vault.yml`, encrypted with `ansible-vault` (AES256).
2. **The vault password** — what unlocks that file — lives in `~/.secrets/openai/vault_password.enc`, RSA-encrypted against your CAC's PIV certificate. Only the CAC's private key (which never leaves the card) can decrypt it, and using that private key requires your PIN, entered on the card's own prompt.

```
CAC + PIN → decrypts → vault_password.enc → vault password → decrypts → vault.yml → OPENAI_API_KEY
```

If the CAC isn't present — different machine, no reader, card left at
your desk — `get_vault_password.sh` falls back to asking you to type the
vault password directly. Same end result, no CAC required, just a second
factor traded for typing something you know.

## One-time setup

`install.sh` installs `ansible` + `opensc` (for `pkcs11-tool`) and drops
`get_vault_password.sh` into `~/.secrets/openai/`, but it does **not**
create `vault.yml` or `vault_password.enc` — that needs your live CAC and
your real API key present, which isn't something to hand to a script.

### Step 1 — find your PIV key slot

With your CAC inserted:

```bash
pkcs11-tool --module /opt/homebrew/lib/opensc-pkcs11.so -O
```

(Intel Mac: `/usr/local/lib/opensc-pkcs11.so`. Linux: usually
`/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so` — `find / -name 'opensc-pkcs11.so' 2>/dev/null` if unsure.)

This lists every object on the card. Find the **PIV Authentication**
certificate and note its `ID` — commonly `01`, but confirm rather than
assume. That ID is what `CAC_KEY_ID` in `get_vault_password.sh` needs to
match.

### Step 2 — export that certificate's public key

```bash
pkcs11-tool --module /opt/homebrew/lib/opensc-pkcs11.so \
    --read-object --type cert --id 01 -o /tmp/cac_cert.der
openssl x509 -inform DER -in /tmp/cac_cert.der -pubkey -noout > /tmp/cac_pub.pem
```

(Swap `--id 01` for whatever Step 1 actually showed.)

### Step 3 — generate a vault password and RSA-encrypt it against that key

```bash
openssl rand -base64 32 > /tmp/vault_pw.txt
openssl pkeyutl -encrypt -pubin -inkey /tmp/cac_pub.pem \
    -in /tmp/vault_pw.txt -out ~/.secrets/openai/vault_password.enc
```

`vault_password.enc` is safe to keep on disk (even synced/backed up) —
it's useless without the CAC's private key, which never leaves the card.

### Step 4 — encrypt the real API key with that password

```bash
echo 'openai_api_key: sk-...' > /tmp/vault_plain.yml
ansible-vault encrypt /tmp/vault_plain.yml \
    --vault-password-file /tmp/vault_pw.txt \
    --output ~/.secrets/openai/vault.yml
```

### Step 5 — shred every plaintext temp file

```bash
shred -u /tmp/vault_pw.txt /tmp/vault_plain.yml /tmp/cac_cert.der /tmp/cac_pub.pem
```

Nothing unencrypted should survive this process on disk. If `shred` isn't
available (some minimal Linux images lack it), `rm -P` or manually
overwriting before deleting is the fallback — plain `rm` alone just
unlinks the file, the bytes are still recoverable until overwritten.

### Step 6 — confirm CAC_KEY_ID matches

Open `~/.secrets/openai/get_vault_password.sh` and check `CAC_KEY_ID`
matches whatever Step 1 actually showed (defaults to `"01"`). Same for
`PKCS11_MODULE` if your OpenSC install path differs from the Homebrew
default baked in.

## Daily usage

```bash
load_openai_key
```

This is a zsh function (in `.zshrc`, deployed by `install.sh`) — **not**
run automatically at shell startup. Unlike the SSH-agent setup, this
should only prompt for your CAC PIN (or the backup password) when you're
actually about to use it, not on every new terminal tab. Run it once per
shell session before launching `codex` or anything else that needs
`OPENAI_API_KEY`.

What happens when you run it:

1. CAC inserted and readable → `pkcs11-tool` decrypts `vault_password.enc`, prompting for your PIN on its own masked prompt (the PIN never touches any script, is never stored, never appears in `ps` output).
2. CAC missing or the decrypt fails for any reason → falls back to a masked prompt asking for the vault password directly.
3. Either way, the resolved password decrypts `vault.yml` via `ansible-vault view`, and `OPENAI_API_KEY` gets exported into your current shell only — nothing is written back to disk.

## Threat model notes

- **Compromised laptop, no CAC present:** attacker gets `vault.yml` and `vault_password.enc`, both useless without either the physical CAC or the backup password.
- **Stolen CAC, no PIN:** useless — CAC private key operations require the PIN, enforced by the card's own hardware (and most CACs lock after a handful of wrong attempts).
- **Backup password path:** intentionally weaker than the CAC path by design — it's the documented fallback, not a hidden bypass. Treat it like any other password: don't reuse it, don't write it down somewhere the laptop itself would expose.
- **Shell history:** none of the commands above with real secret values should ever be typed with history expansion enabled in a way that logs them — the setup commands write to `/tmp` files precisely so the secret material doesn't end up in `.zsh_history` as a literal `echo 'sk-...'` command.
