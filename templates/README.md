# Env-Config Deployment

**Author:** [Mike Roach](https://github.com/RoachMJ)

<details>
<summary><strong>1. Rename folders</strong></summary>

Run this from a plain local shell, not through a tool that mounts/syncs this folder from elsewhere — renaming through an indirect mount can orphan the original reference instead of moving it.

```bash
cd /path/to/Env-Config   # the parent folder containing Env-setup/, personal/, professional/
mv Env-setup env
mv personal env-personal
mv professional env-professional
```

</details>

<details>
<summary><strong>2. Repo contents</strong></summary>

| Repo | Visibility | Host | Contents |
|---|---|---|---|
| `env` | Public | GitHub | `install.sh`, `lib/`, `README.md`, `templates/`, `piv/recipient`, `piv/repo.env.age` |
| `env-personal` | Private | any | `install.sh`, `nvim/`, `shell/`, `git-config/`, `tmux/`, `zed/`, `codex/`, `archdocs/`, `mr-metadata/`, `git-remotes/`, `issues/` |
| `env-professional` | Private | work GitLab/Gitea | same as `env-personal` + `meeting-alarm/`, `piv/` (PIV-encrypted `OPENAI_API_KEY`) |

`env` holds no secrets. `env-professional/piv/` holds only `.age`-encrypted files and `age-identity.txt` (a YubiKey+slot reference, not key material) — never a raw token.

</details>

<details>
<summary><strong>3. Create three empty remotes</strong></summary>

No auto-init README/`.gitignore`/license from the host.

</details>

<details>
<summary><strong>4. Push each folder as first commit</strong></summary>

None of the three folders have git history yet.

```bash
cd /path/to/Env-Config/env
git init
git add -A
git commit -m "✨ initial commit — env bootstrap"
git branch -M main
git remote add origin <env-repo-url>
git push -u origin main
```

Repeat for `env-personal` and `env-professional` with their own remote URLs.

</details>

<details>
<summary><strong>5. Set real URLs</strong></summary>

In `env/install.sh`:

```bash
ENV_PERSONAL_REPO_URL="${ENV_PERSONAL_REPO_URL:-<env-personal-url>}"
ENV_PROFESSIONAL_REPO_URL="${ENV_PROFESSIONAL_REPO_URL:-<env-professional-url>}"
```

Commit and push to `env`.

</details>

<details>
<summary><strong>6. Run the install</strong></summary>

First run: spare machine or a fresh macOS user account, not your daily driver.

```bash
curl -fsSL <raw-url-to-env>/install.sh | bash
```

Override without editing the file:

```bash
curl -fsSL <raw-url-to-env>/install.sh | ENV_PERSONAL_REPO_URL=... ENV_PROFESSIONAL_REPO_URL=... bash
```

</details>

<details>
<summary><strong>7. Smoke tests</strong></summary>

<details>
<summary>Folder structure</summary>

```bash
ls -la ~/.env-config
git -C ~/.env-config status                     # expect: not a git repository
git -C ~/.env-config/env status -sb
git -C ~/.env-config/env-personal status -sb     # if installed
```

</details>

<details>
<summary>Symlinks</summary>

```bash
for f in ~/.zshrc ~/.gitconfig ~/.tmux.conf.local ~/.config/nvim/init.lua ~/.config/nvim/templates ~/.config/starship.toml ~/.codex/config.toml; do
  [ -L "$f" ] && echo "OK  $f -> $(readlink "$f")" || echo "MISSING: $f"
done
```

</details>

<details>
<summary>Aliases</summary>

```bash
git aliases
git lint
git mr push       # no target arg -> usage message, exit 1
git pr push       # same
```

</details>

<details>
<summary>Global hooks</summary>

```bash
git config --get core.hooksPath          # expect: ~/.githelpers/git-hooks
ls -la ~/.githelpers/git-hooks/           # expect: prepare-commit-msg, pre-commit, both +x
```

</details>

<details>
<summary>Lint hook blocks bad commits</summary>

```bash
mkdir -p /tmp/lint-smoke-test && cd /tmp/lint-smoke-test && git init -q
printf '{"a":1,' > bad.json && git add bad.json
git commit -m test                        # expect: blocked, jq error shown
SKIP_LINT=1 git commit -m test            # expect: succeeds
cd /tmp && rm -rf lint-smoke-test
```

</details>

<details>
<summary>PIV / encryption</summary>

```bash
age-plugin-yubikey --list
cat ~/.env-config/env/piv/recipient
```

</details>

<details>
<summary>Codex</summary>

```bash
codex --version
codex login status
cat ~/.codex/config.toml                  # expect: sandbox_mode = "read-only", approval_policy = "untrusted"
```

</details>

<details>
<summary>Neovim</summary>

```bash
nvim --headless -c "checkhealth" -c "qa" 2>&1 | grep -i error   # expect: no output
```

Then manually: open a new `test.py`, confirm skeleton auto-fills; `<leader>cc` (needs `codex login`) should open a Telescope dropdown for any file-edit approval.

</details>

<details>
<summary>mrmeta</summary>

```bash
mkdir -p /tmp/mrmeta-smoke-test && cd /tmp/mrmeta-smoke-test && git init -q
git mr-labels-refresh
```

</details>

</details>

<details>
<summary><strong>8. Uninstall (for retesting)</strong></summary>

Rolls back a previous install so you can retest cleanly. Restores whatever real file/dir was backed up before symlinking (or just removes the symlink if nothing was backed up), then — separate y/N prompt, per item — offers to remove packages that run's own install actually installed (never something already on the machine before you ran this).

```bash
cd ~/.env-config/env
./install.sh --uninstall              # choose profile(s), each hands off to its own checklist
```

Or per-profile directly:

```bash
cd ~/.env-config/env-personal && ./install.sh --uninstall
cd ~/.env-config/env-professional && ./install.sh --uninstall
```

Same numbered checklist as install, combinable with `--all`/`--only=key1,key2`.

Tracking: `~/.env-config/install-manifest.jsonl` (JSON Lines, one entry per package/symlink install action, records whether each was pre-existing or freshly installed by this machine's runs). Never committed — structurally outside all three repo clones, plus listed in each `.gitignore` as defense in depth.

Left alone by `--uninstall`: the repo clones themselves, `~/.env-config/backups` (restore reads from here), `install-manifest.jsonl` itself, actual GPG/PIV key material. Two items are GLOBAL across every repo on the machine, not just this one, and prompt loudly before touching them: `mrmeta`'s `prepare-commit-msg` hook and `lint`'s `pre-commit` hook (both live in `~/.githelpers/git-hooks`).

</details>

<details>
<summary><strong>9. Utilization reference</strong></summary>

<details>
<summary>Git aliases</summary>

| Alias | Does |
|---|---|
| `git st` | `status -sb` |
| `git last` | `log -1 HEAD --stat` |
| `git co` / `git br` / `git ci` | checkout / branch / commit |
| `git cane` | `commit --amend --no-edit` |
| `git amend` | `commit --amend` |
| `git unstage [path]` | `restore --staged` (defaults to everything) |
| `git undo` | `reset --soft HEAD~1` |
| `git wip` | `commit -am "🚧 wip"` |
| `git lg` | colorized one-line graph log |
| `git graph` | `log --all --graph --decorate --oneline` |
| `git please` | `push --force-with-lease` |
| `git conflicts` | list files still in conflict |
| `git mr push [target]` | push + open a GitLab MR (one-time per branch) |
| `git pr push [target]` | push + open a GitHub PR, needs `gh` (one-time per branch) |
| `git remotes` | clone/pull everything in `~/.git-remotes.list` |
| `git remotes add <name> <url> [path]` | register + clone a repo now |
| `git remotes list` / `remove <name>` | show / deregister |
| `git issue-push` | push `issues/queue/*.md` to GitLab/GitHub/Gitea |
| `git mr-labels-refresh` | fetch + cache labels/milestones/assignees for this repo |
| `git mr-labels-show` | print the cached JSON |
| `git mr-labels-pick` | run the picker manually, outside a commit |
| `git lint` | run the pre-commit lint/format hook manually |
| `git emoji` | print the gitmoji legend |
| `git aliases` | list every alias |

Follow-on commits on an already-open MR/PR: plain `git push`, not `git mr push`/`git pr push` again.

</details>

<details>
<summary>Git hooks (global, <code>~/.githelpers/git-hooks</code>)</summary>

| Hook | Fires on | Does | Bypass |
|---|---|---|---|
| `prepare-commit-msg` | editor-based `git commit` | mrmeta label/milestone/assignee picker | `SKIP_MRMETA=1 git commit` |
| `pre-commit` | every `git commit` | formats + lints staged files, gitleaks secret scan | `SKIP_LINT=1 git commit` |
| both | — | — | `git commit --no-verify` |

</details>

<details>
<summary>Linters/formatters (installed by <code>install.sh</code>'s <code>lint</code> item)</summary>

| Tool | Covers |
|---|---|
| `ruff` | Python — lint + format |
| `shellcheck` / `shfmt` | Shell — lint / format |
| `golangci-lint` / `gofmt` | Go — lint / format |
| `terraform fmt` / `tflint` | Terraform |
| `terragrunt hclfmt` | Terragrunt/HCL |
| `yamllint` | YAML |
| `kubeconform` / `kube-linter` | Kubernetes manifests — schema / policy |
| `helm lint` | Helm charts, incl. Big Bang packages |
| `jq` | JSON — validate + format |
| `taplo` | TOML — lint + format |
| `markdownlint-cli2` | Markdown |
| `actionlint` | GitHub Actions workflows |
| `gitleaks` | secret scan, every commit |

</details>

<details>
<summary>Codex</summary>

```bash
codex login                 # or export OPENAI_API_KEY
codex login status
codex --version
```

Sandbox: `~/.codex/config.toml` — read-only/untrusted globally; loosen per-project with a nested `.codex/config.toml` (`sandbox_mode = "workspace-write"`).

</details>

<details>
<summary>PIV / encryption</summary>

```bash
./install.sh --encrypt              # one-time wizard: provisions YubiKey + writes piv/repo.env.age
age-plugin-yubikey --list-all       # see free/used slots
age-plugin-yubikey --list           # see what's provisioned for age
```

A generalized version of this same mechanism (`./install.sh --encrypt-secret [name]`, on the `env-personal`/`env-professional` profiles) encrypts any other secret to `piv/<name>.age` — see `env-professional/piv/README.md`.

</details>

<details>
<summary>archdocs</summary>

```bash
archdocs list-icons
archdocs render examples/platform_stack.py [--drawio]
```

</details>

<details>
<summary>Neovim plugins</summary>

The colorscheme (Desert Mesa) isn't in this table — it's a bundled
`colors/desert-mesa.lua` file, not a third-party plugin, so there's
nothing external to install or keep in sync for it.

| Plugin | For |
|---|---|
| nvim-tree | file explorer |
| telescope.nvim (+fzf-native, +ui-select) | fuzzy find; renders Codex's approval prompts |
| gitsigns.nvim | gutter diff signs, hunk stage/undo |
| vim-fugitive / vim-rhubarb | `:Git` commands |
| nvim-treesitter | syntax highlighting/indent |
| vim-terraform, ansible-vim, vim-go | per-language extras (fmt-on-save, docs, Delve debugging) |
| nvim-lspconfig + mason.nvim | LSP servers: gopls, pyright, terraformls, bashls, yamlls, jsonls, dockerls, ansiblels |
| nvim-cmp + LuaSnip + friendly-snippets | completion + snippets (`def`, `class`, etc.) |
| nvim-lint | shellcheck/yamllint on save (gaps LSP doesn't cover) |
| aerial.nvim | code outline |
| lualine.nvim / bufferline.nvim | statusline / tabline |
| undotree, nvim-surround, Comment.nvim, nvim-autopairs, vim-repeat, targets.vim, vim-illuminate, vim-lastplace, vim-obsession, vim-signature, vim-better-whitespace, indent-blankline.nvim | editor utilities |
| which-key.nvim | leader-key popup menu |
| codex.nvim | Codex CLI integration |
| vim-tmux-navigator | `<C-hjkl>` across tmux panes |

</details>

<details>
<summary>Neovim keymaps</summary>

Leader is `Space`. `jj`/`kk` also exits insert mode.

| Key | Does |
|---|---|
| `<leader>e` / `ef` | toggle file tree / find current file in it |
| `<leader>ff` / `fg` / `fb` / `fh` / `fc` / `fm` | find files / grep / buffers / history / commands / keymaps |
| `<leader>a` | live grep |
| `gd` / `gD` / `gi` / `gr` / `K` | LSP goto def/decl/impl, references, hover |
| `<leader>rn` | LSP rename |
| `<leader>ca` | LSP code action |
| `[d` / `]d` | prev/next diagnostic |
| `<leader>cd` | line diagnostics |
| `]h` / `[h` | next/prev git hunk |
| `<leader>gu` / `ghs` | undo / stage hunk |
| `<leader>gs` / `gb` / `gd` / `gl` / `gp` | Git status / blame / diff / log / push |
| `<leader>gf` | open file under cursor |
| `<leader>db` / `ds` / `dc` / `dn` / `do` / `dt` | Go debug: breakpoint / start / continue / next / step out / stop |
| `<leader>gr` / `gt` | Go run / test |
| `<leader>tt` | toggle outline |
| `<leader>u` | toggle undo tree |
| `<leader>sv` / `sh` / `se` | vsplit / split / equalize |
| `<leader>bd` / `bn` / `bp` | delete / next / prev buffer |
| `<leader>/`, `<Esc>` | clear search highlight |
| `<leader>w` / `q` / `Q` | save / quit / quit all |
| `<A-j>` / `<A-k>` | move line/selection down/up |
| `<C-h/j/k/l>` | move across tmux panes/nvim splits |
| `<leader>os` / `oS` | start / stop session (Obsession) |
| `<leader>cc` | Codex: ask about context/selection |
| `<leader>cx` | Codex: prompt/action picker |
| `<leader>co` | Codex: toggle full output |
| `<C-t>` | `gt` (next tab) |

</details>

<details>
<summary>New-file skeletons</summary>

Create a new `.py`/`.go`/`.sh`/`.tf`/`terragrunt.hcl`/`Dockerfile`/`.md` and it auto-fills from `nvim/templates/`. No keybind needed — fires on `BufNewFile`.

</details>

</details>
