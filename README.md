# Environment Configuration

**Author:** [Mike Roach](https://github.com/RoachMJ)

> **TL;DR** — This bootstrap repo is public and holds no secrets. It's purpose is for deploying specific profiles for development envioronments via one of two auth paths, then hands off to that profile's own installer. `curl -fsSL <raw-url>/install.sh | bash` on a brand-new machine, everything lands under ~/.env-config — a plain folder, not a git repo itself, holding three independent clones (this repo lands in its env/ subfolder, env-personal/ and env-professional/ alongside it).

<details>
<summary><strong>Why three repos, not one</strong></summary>

One git remote = one auth method, so getting "clone the bootstrap repo with zero credentials, then pull whichever profile with whatever auth it needs" takes three repos, not one.

| Repo | Contains | Auth |
|---|---|---|
| **env** (this repo, bootstrap) | `install.sh`, lib/, this README, optional piv/ | none — safe to be public |
| **env-personal** | per-component subfolders (nvim/, shell/, git-config/, etc.), each with its own README | ENV_PERSONAL_REPO_URL |
| **env-professional** | same layout, plus meeting-alarm/ and piv/ (PIV-encrypted OPENAI_API_KEY) | ENV_PROFESSIONAL_REPO_URL |

Each repo's own root is exactly its own content — no repo wraps another. `install.sh` clones this bootstrap repo into `~/.env-config/env/`, then shallow-clones whichever profile(s) you pick into `~/.env-config/env-personal/` and/or `~/.env-config/env-professional/` — three independent git clones sitting side by side inside a plain `~/.env-config` folder that is itself never a git repo — then `git pull --ff-only` on later runs, then hands off to that profile's own `install.sh`.

Set your real URLs near the top of `install.sh`, replacing the YOUR_GITHUB_USERNAME/REPLACE_ME placeholders — it refuses to run against a placeholder. Or override at runtime: `ENV_PROFESSIONAL_REPO_URL=... ./install.sh`. See "Running it on a brand-new machine" below for the full clone-and-run flow.

</details>

<details>
<summary><strong>Running it on a brand-new machine (curl one-liner)</strong></summary>

No `git clone` by hand needed — `install.sh` detects piped execution and clones the bootstrap repo itself.

1. **Run the one-liner.**

   ```bash
   curl -fsSL https://raw.githubusercontent.com/RoachMJ/env/main/install.sh | bash
   ```

   This has to be a `raw.githubusercontent.com` URL, not a regular `github.com/.../blob/...` one — the latter returns an HTML page, not the script itself, which `bash` can't do anything useful with. `install.sh` already defaults `BOOTSTRAP_REPO_URL` to `https://github.com/RoachMJ/env.git` internally (this repo is public — no auth needed to clone it), so the plain one-liner above works with nothing extra. Forking this for your own dotfiles? Swap in your own raw URL and see step 4 below to also override the clone URL baked into the script.

2. **It clones itself to disk.** Creates ~/.env-config (a hidden folder in your home directory, override with ENVCFG_HOME=...) if it doesn't exist yet — a plain folder, not a git repo — and clones this bootstrap repo into ~/.env-config/env/, then re-execs `install.sh` from inside that clone.

3. **Everything else runs like a normal on-disk run.** Core-package prompts, profile choice, cloning — no difference from running `./install.sh` directly on an already-cloned copy.

4. **(Optional) override the bootstrap repo's own clone URL**, e.g. if you forked this repo and the raw URL above now points at your fork's install.sh but the clone step should still pull from your fork too, not mine:

   ```bash
   curl -fsSL <your-raw-url>/install.sh | BOOTSTRAP_REPO_URL=<your-fork-clone-url> bash
   ```

Piping a script straight into `bash` means you're trusting whoever controls that URL — fine for your own repo, worth a second look before you do it with anyone else's.

</details>

<details>
<summary><strong>Core packages are checked first, then offered</strong></summary>

`install.sh` no longer installs git/curl/zsh/starship unconditionally. For each one it checks whether it's already on PATH:

- **Already installed** — asks "Upgrade to latest? [y/N]" (default: leave it alone).
- **Missing** — asks "Install it? [Y/n]" (default: install, since the rest of this repo assumes these exist, but always skippable).

No TTY on stdin (e.g. a non-interactive CI-style run) means no prompt is possible, so it reports what it would have asked and does nothing — it never assumes an answer for you. See `offer_core_package` in `lib/common.sh` for exactly what "upgrade" runs per package manager.

</details>

<details>
<summary><strong>Repo access: two paths, one encrypted bundle</strong></summary>

Two independent ways to give a brand-new machine access to a private profile repo. Neither requires anything memorized, written down, or stored anywhere outside a single physical YubiKey.

- **Path 1 — SSH, hardware-backed.** A git@ SSH URL; auth comes from whatever's already loaded in `ssh-agent`. No secret in this repo either way — even the encrypted bundle below only ever holds a *plaintext-looking* SSH URL, never key material.
- **Path 2 — a token over HTTPS.** An HTTPS URL plus a personal access token, used as a Basic-auth header at clone time — never embedded in the URL, never written to either profile's git config.

Both live, per profile, in one encrypted file: piv/repo.env.age. It's encrypted to an ECC P-256 key that lives only on your YubiKey (a PIV retired slot, provisioned via `age-plugin-yubikey`) — decrypting it needs the physical key, its PIN, and (depending on touch policy) a touch. `install.sh` decrypts it once per run to ~/.env-config/repo.env, then, for any profile where more than one auth method is available, **asks you interactively which one to use** — it no longer guesses or silently prefers one over the other.

A profile with nothing in the bundle (or a bundle that fails to decrypt — wrong YubiKey, no touch, no PIN) just falls back to that profile's plaintext ENV_PERSONAL_REPO_URL/ENV_PROFESSIONAL_REPO_URL near the top of `install.sh`.

You'll generally provision both PIV slots below regardless of which path(s) you actually use — the SSH slot and the encryption slot are independent, and having both costs nothing extra.

<details>
<summary>The fast way: <code>./install.sh --encrypt</code></summary>

A one-time interactive wizard that does everything below for you: checks which of `ykman`/`age`/`age-plugin-yubikey` are already installed and only installs what's actually missing, checks whether PIV slot 9a and a retired encryption slot are already occupied (and leaves them alone if so), asks for the SSH key's algorithm/PIN-policy/touch-policy/subject/certificate-expiration when provisioning slot 9a, asks for your env-personal/env-professional repo URLs and tokens, and writes the encrypted piv/repo.env.age plus the recipient into piv/recipient — a short, plain-text file `install.sh` reads at runtime; the script's own source is never edited. Generated key material (the SSH pubkey + a backup of its public certificate, the age identity, the recipient) lands in ~/.ssh/.env-config/, separate from the git-tracked repos.

Re-running `--encrypt` after a failed or partial attempt is safe: both slot-provisioning steps check first and leave an already-occupied slot alone rather than re-generating into it, so nothing gets silently recreated or duplicated. The repo-URL/token prompts at the end do get re-asked every run though — nothing about those is saved between runs, so have them ready to retype if you're resuming after a failure partway through.

Treat it as a starting point, not gospel — `age-plugin-yubikey`'s exact flags have shifted across releases, and none of this has been run against physical YubiKey hardware in the environment it was written in. If a step fails, the manual walkthrough below is the same thing broken into individual commands you can run and inspect one at a time.

</details>

<details>
<summary>A note on "backing up" these keys</summary>

Both the SSH key (slot 9a) and the encryption key (the retired slot) are generated *on* the YubiKey's own chip and never leave it, in any form — that's what makes them hardware-backed. There's no private key file anywhere to copy or back up. The wizard's `env-config-cert.pem` (SSH) and `age-identity.txt` (encryption) are both public data, just not the same *kind* of public data: `env-config-cert.pem` is an X.509 certificate wrapping the actual public key — regenerate `env-config.pub` from it any time, on any machine, with `ssh-keygen -f env-config-cert.pem -i -m PKCS8`, no YubiKey needed for that step. `age-identity.txt` is a YubiKey serial + PIV slot *pointer*, not the key itself. Neither file lets you authenticate or decrypt anything without the physical device present — that's what makes both safe to commit to this public repo (see `piv/`).

For the SSH key specifically, if you're locking a server down to key-only login (no password fallback), losing your only YubiKey means losing access — plan for that with **redundancy, not backup**: buy a second physical YubiKey and run `./install.sh --encrypt` again with it inserted. Its certificate gets committed to `piv/` as `env-config-cert-2.pem` (auto-numbered — the first one is left alone), and every later `install.sh` run regenerates a matching pubkey and wires *both* keys into `~/.ssh/config` as separate `IdentityFile` lines for this repo's own git-host aliases (`personal`/`work`) — nothing to register by hand there beyond adding both public keys to GitHub/GitLab once. For any other server you SSH into directly, outside this repo's aliases, you still register `env-config.pub` and `env-config-2.pub` on that server's `authorized_keys` yourself. Either way, losing one YubiKey just means removing that one key from wherever it was registered, not being locked out. The encryption key (for repo.env) doesn't need this — losing it just means re-provisioning and re-encrypting a new repo.env, no standing access depends on it staying available.

</details>

<details>
<summary>One-time YubiKey provisioning by hand (both slots)</summary>

- **Slot 9a (PIV Authentication)** — for the SSH auth path. If this slot already has a key on the YubiKey you're using, decide first: reuse it (skip straight to the export step below) or overwrite it. To overwrite, just run `ykman piv keys generate` again on 9a — it replaces whatever key was already there as part of generating the new one, no separate delete step needed (and note: `ykman piv keys delete`/`ykman piv certificates delete` are a *different*, newer pair of subcommands that need YubiKey firmware 5.7.0+; you don't need them here, so don't reach for them if you're on older firmware). The old key stops working everywhere it was registered the moment you overwrite it, so don't do that on a whim.

  ```bash
  # Generate a key in the PIV Authentication slot (ECCP256 shown; ECCP384
  # and RSA2048 also work if you have a reason to want one of those instead).
  # If slot 9a already has a key, this overwrites it in place:
  ykman piv keys generate 9a pubkey-9a.pem

  # --subject is just a label for this specific key — CN can be anything
  # that helps you tell keys apart later, e.g. "env-config-ssh",
  # "env-config-ssh-laptop", or "jdoe-ssh-backup-1" for a second device.
  # --valid-days sets how long the certificate label is valid for (365 =
  # 1 year is ykman's own default; use something like 36500 for an
  # effectively-permanent ~100-year cert):
  ykman piv certificates generate --subject "CN=env-config-ssh" --valid-days 365 9a pubkey-9a.pem

  # Get it into SSH-public-key form and add it to GitHub/GitLab (or a
  # server's authorized_keys) like any normal SSH key:
  ssh-keygen -f pubkey-9a.pem -i -m PKCS8 > env-config.pub
  ```

  Setting up a second physical YubiKey as a backup login? Repeat this whole slot-9a section with that key inserted instead, then register both `env-config.pub` files — don't reuse the first one's output for the second device. (This is exactly what the `--encrypt` wizard automates: it saves each key's certificate to `piv/` as `env-config-cert.pem`, `env-config-cert-2.pem`, etc., and `install.sh` regenerates and wires in a pubkey for every one it finds.)

  Set a touch policy on the slot if you want a physical touch required per use (`ykman piv keys generate --touch-policy always 9a ...`).

- **A retired slot (e.g. slot 1)** — for the encryption path, deliberately separate from 9a so a persistent SSH agent session and `age-plugin-yubikey` never fight over the same PIV session. `age-plugin-yubikey` has its own slot numbering, 1-20 — **not** the PIV hex slot names ykman uses elsewhere in this doc (slot 1 here is PIV hex slot 0x82, slot 20 is 0x95, and so on). Check what's free first:

  ```bash
  age-plugin-yubikey --list-all
  # shows all 20 slots and whether each already has something in it —
  # pick one that's empty before generating into it
  ```

  Then generate into whichever slot number (1-20) came back empty:

  ```bash
  age-plugin-yubikey --generate --slot 1 --name env-config-repo-access
  # non-interactive if you pass --slot; omit it to be prompted to pick
  # one interactively instead. Add --touch-policy always if you want a
  # physical touch required per decrypt.
  ```

  This is a real ECC P-256 keypair, generated and held entirely on the YubiKey's PIV applet — `age-plugin-yubikey` is just the tool that speaks age's plugin protocol against it. The command above prints two things: an age1yubikey1... recipient (public, used to encrypt) and an identity — a line starting AGE-PLUGIN-YUBIKEY-... (used to decrypt). Save the full output as env/piv/age-identity.txt and commit it — it's a reference to the YubiKey+slot, not key material. Without the physical card and its PIN, it decrypts nothing.

  List what's already provisioned (configured for age) on a key with `age-plugin-yubikey --list`.

</details>

<details>
<summary>Building the encrypted bundle by hand</summary>

1. Build the plaintext file. Only the fields you actually want to use need filling in — SSH-only or token-only per profile is fine, so is a mix:

   ```bash
   cat > /tmp/repo.env.plain << 'EOF'
   ENV_PERSONAL_SSH_URL=git@github.com:YOUR_GITHUB_USERNAME/env-personal.git
   ENV_PROFESSIONAL_HTTPS_URL=https://gitlab.example.com/group/env-professional.git
   ENV_PROFESSIONAL_TOKEN=glpat-...
   EOF
   ```

   This is a plain shell env file, not YAML — `install.sh` sources it directly into its own environment after decrypting it, no parser involved.

2. Encrypt it to the YubiKey recipient from the provisioning step above:

   ```bash
   age -r age1yubikey1YOUR_RECIPIENT_HERE \
       -o env/piv/repo.env.age \
       /tmp/repo.env.plain
   ```

3. Shred the plaintext — it should exist only for this one command:

   ```bash
   shred -u /tmp/repo.env.plain
   ```

4. Write the recipient string (the same `age1yubikey1...` value from step 2) into `env/piv/recipient` — a plain-text file, one line, nothing else — and commit both. `install.sh` reads this file at runtime rather than having the recipient edited into its own source, so the script itself never needs to change when you rotate hardware:

   ```bash
   echo "age1yubikey1YOUR_RECIPIENT_HERE" > env/piv/recipient
   git add env/piv/repo.env.age env/piv/recipient
   ```

5. From here on, `install.sh` decrypts piv/repo.env.age automatically at clone time (PIN + touch happen right there, on the YubiKey), writes the plaintext to ~/.env-config/repo.env, and asks you interactively which auth path to use for any profile where more than one is available.

</details>

</details>

<details>
<summary><strong>Keeping each profile updated later</strong></summary>

Since env-personal/ and env-professional/ are now their own repos, you can update either one directly without going through the bootstrap install.sh at all:

```bash
cd env-personal && git pull        # or: cd env-professional && git pull
```

Each profile's own `install.sh` symlinks every config file back into that folder, so a plain `git pull` there is enough — no re-running any install script needed unless you're adding a new item you hadn't installed yet (in which case: `cd env-personal && ./install.sh` directly, no need to go back through the bootstrap script).

</details>

<details>
<summary><strong>Uninstalling / rolling back for a retest</strong></summary>

`./install.sh --uninstall` here in the bootstrap repo asks which profile(s) to roll back, delegates to each one's own `install.sh --uninstall` (same numbered checklist as a normal install — `--all`/`--only=key1,key2` both work with it too), then offers to remove the core packages (git/curl/zsh/starship) this machine's runs actually installed. You can also run a profile's own `--uninstall` directly: `cd env-personal && ./install.sh --uninstall`.

Per selected item, this restores whatever real file/dir `link_file()` backed up before symlinking (or just removes the symlink if there was nothing to restore), then — its own separate y/N prompt — offers to remove any packages that machine's install run(s) actually installed for that item. It never removes a package that was already on the machine before you ran this repo's installer in the first place; that distinction is tracked per package in `~/.env-config/install-manifest.jsonl` (JSON Lines, one entry per install action, written by `lib/common.sh`'s `install_pkg_one`/`record_manual_install`/`link_file` — see that file's own comments for the exact schema). The manifest lives in `~/.env-config`, a sibling of this repo's own clone, so it's never inside a git working tree by construction; each repo's `.gitignore` also lists it by name as defense in depth.

Left alone by `--uninstall`, on purpose: the repo clones themselves, `~/.env-config/backups` (that's what config restore reads from — deleting it defeats future restores), the manifest file itself, and any real GPG/PIV key material. Two profile items are GLOBAL across every git repo on the machine, not just the one you're testing in, and prompt loudly before touching them: mrmeta's `prepare-commit-msg` hook and the lint item's `pre-commit` hook, both under `~/.githelpers/git-hooks`.

</details>

<details>
<summary><strong>What actually goes in a profile repo</strong></summary>

This repo (the bootstrap) deliberately knows nothing about what's inside env-personal/ or env-professional/ — it just clones them and hands off. A profile repo is wherever you put the actual environment you want reproduced: whatever editor config, shell setup, terminal tools, credential handling, and small helper scripts you'd otherwise have to remember to set up by hand on every new machine.

The two-profile split (env-personal vs. env-professional) is one reasonable way to divide things when you genuinely want different identities, credentials, or tool choices depending on context — but nothing about the bootstrap script requires exactly two, or requires the split to be personal/professional at all. Fork this repo and rename the profiles to whatever separation makes sense for you (by environment, by employer, by machine role), or collapse it to a single profile if you don't need the split.

A profile's own `install.sh` is expected to follow the same shape this repo's does: an interactive checklist of "items" (an item might be a single config file, a whole subfolder, or a small install routine), each independently skippable, each idempotent enough to re-run safely. `lib/common.sh` (in this repo) has the generic pieces — logging, a symlink installer, OS/package-manager detection — so a profile's own install.sh doesn't have to reimplement any of that.

</details>

<details>
<summary><strong>Using this as a template for your own setup</strong></summary>

Nothing in this bootstrap repo (env/) is specific to any one person's tools — it only knows about cloning profile repos and handing off. If you're starting your own environment-config setup rather than adapting an existing one, `env/templates/profile-install.sh` is a minimal, working profile installer with the same item-checklist structure as a real one, but no actual tools wired in — copy it into a new profile repo's `install.sh` and start filling in items one at a time. See that file's own comments for the pattern.

The same YubiKey-backed encryption this repo uses for repo-access tokens (an ECC P-256 key, `age`, one recipient) generalizes beyond just repo.env — any file in a profile repo that shouldn't be plaintext (an API key, a small credentials file, anything you'd otherwise keep out of git entirely) can be encrypted to the same recipient and decrypted the same way at profile-install time, following the pattern in env-professional/piv/README.md. That profile-specific piece isn't something this bootstrap repo builds for you automatically — it's a pattern to copy per-secret, in whichever profile repo needs it.

</details>
