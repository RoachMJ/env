#!/usr/bin/env bash
# ------------------------------------------------------------------
# Bootstrap script for the Neovim IDE config (init.lua) + surrounding
# dev environment (Codex CLI, tmux, zsh, Zed, vaulted OPENAI_API_KEY,
# tmux meeting alarm).
#
# By default this runs an interactive checkbox menu so you can pick
# exactly which of the 7 items below to install — nothing outside your
# selection is touched. Existing configs it WOULD overwrite are still
# backed up automatically (timestamped .bak files) regardless of what
# you select.
#
# Items:
#   neovim  Neovim + system deps (ripgrep, fd, node, go, python3, a Nerd
#           Font), installs init.lua, syncs plugins via lazy.nvim,
#           installs LSP servers via Mason, self-heals once if broken.
#   codex   Codex CLI (npm install -g @openai/codex) + an auth check.
#           codex.nvim's keymaps in init.lua are inert without this.
#   tmux    tmux + oh-my-tmux, installs tmux.conf.local (mouse, vi copy
#           mode -> pbcopy, tmux-resurrect/continuum via TPM, Neovim
#           pane-navigation integration), validates it loads.
#   zshrc   Installs zshrc (tmux auto-boot / continuum-resume, gated
#           against nested tmux over SSH, ssh-agent passphrase prompt).
#   zed     Installs Zed + settings.json/keymap.json mirroring the
#           Neovim setup (theme, fonts, vim mode, LSP, keybindings).
#   vault   CAC-gated Ansible Vault MACHINERY for OPENAI_API_KEY
#           (ansible + opensc, ~/.secrets/openai, get_vault_password.sh).
#           Does not create the actual encrypted vault — see
#           README-secrets-vault.md for that one-time manual step.
#   alarm   tmux meeting alarm: meeting_alarm.sh in ~/.tmux/alarms, a
#           macOS launchd LaunchAgent that checks it every 60s. Needs
#           the tmux item too for the prefix+A binding / status line to
#           exist — see README-meeting-alarm.md for the Clock app step.
#
# Non-interactive usage (skips the menu):
#   ./install.sh --all                 install everything
#   ./install.sh --only=neovim,tmux    install just these (comma list of
#                                       the keys above)
#   ./install.sh --help                show this
#
# If stdin isn't a terminal (e.g. piped in some automated context) and
# neither flag is given, it installs everything and prints a warning
# rather than hanging on a prompt.
#
# Codex auth note: the actual sign-in is an interactive OAuth flow (or
# an OPENAI_API_KEY env var for headless use) — this script cannot do
# that part silently for you. It installs the CLI and tells you the
# exact command to run once, either way.
#
# Run this script from the same directory as init.lua / tmux.conf.local
# / zshrc / etc.
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_CONFIG_DIR="$HOME/.config/nvim"

log() { printf "\n\033[1;32m==>\033[0m %s\n" "$1"; }
warn() { printf "\n\033[1;33m!!\033[0m %s\n" "$1"; }

# ------------------------------------------------------------------
# Selectable items + checkbox menu
# ------------------------------------------------------------------
ITEM_KEYS=(neovim codex tmux zshrc zed vault alarm)
ITEM_LABELS=(
  "Neovim (init.lua, plugins via lazy.nvim, LSP servers via Mason)"
  "Codex CLI (npm install -g @openai/codex, login check)"
  "tmux + oh-my-tmux (tmux.conf.local, TPM plugins, mouse/clipboard)"
  "zsh config (~/.zshrc — tmux auto-boot, ssh-agent, argocd/fluxcd)"
  "Zed editor (settings.json/keymap.json mirroring the Neovim setup)"
  "CAC-gated Ansible Vault machinery for OPENAI_API_KEY"
  "tmux meeting alarm (prefix+A, status-bar countdown, launchd check)"
)
SELECTED=(1 1 1 1 1 1 1) # default: everything on

is_selected() { # $1 = item key
  local i key
  key="$1"
  for i in "${!ITEM_KEYS[@]}"; do
    if [[ "${ITEM_KEYS[$i]}" == "$key" ]]; then
      [[ "${SELECTED[$i]}" == "1" ]] && return 0 || return 1
    fi
  done
  return 1
}

print_menu() {
  echo
  echo "Select what to install — nothing outside this list gets touched:"
  local i mark
  for i in "${!ITEM_KEYS[@]}"; do
    mark=" "
    [[ "${SELECTED[$i]}" == "1" ]] && mark="x"
    printf "  %d) [%s] %s\n" "$((i + 1))" "$mark" "${ITEM_LABELS[$i]}"
  done
  echo
  echo "Numbers toggle (space-separated, e.g. '1 3 5'), 'a' = all, 'n' = none, 'd' = done, 'q' = quit"
}

run_menu() {
  local reply tok idx any
  while true; do
    print_menu
    read -r -p "> " reply || { echo; echo "Aborted — nothing installed."; exit 0; }
    case "$reply" in
      d | D) break ;;
      q | Q) echo "Aborted — nothing installed."; exit 0 ;;
      a | A) for idx in "${!SELECTED[@]}"; do SELECTED[$idx]=1; done ;;
      n | N) for idx in "${!SELECTED[@]}"; do SELECTED[$idx]=0; done ;;
      "") : ;;
      *)
        for tok in $reply; do
          if [[ "$tok" =~ ^[0-9]+$ ]] && ((tok >= 1 && tok <= ${#ITEM_KEYS[@]})); then
            idx=$((tok - 1))
            if [[ "${SELECTED[$idx]}" == "1" ]]; then SELECTED[$idx]=0; else SELECTED[$idx]=1; fi
          else
            warn "Ignoring '$tok' — not a valid item number (1-${#ITEM_KEYS[@]})."
          fi
        done
        ;;
    esac
  done

  any=0
  for idx in "${SELECTED[@]}"; do [[ "$idx" == "1" ]] && any=1; done
  if [[ "$any" == "0" ]]; then
    echo "Nothing selected — exiting."
    exit 0
  fi
}

MODE="interactive"
for arg in "$@"; do
  case "$arg" in
    --all)
      MODE="flag"
      for idx in "${!SELECTED[@]}"; do SELECTED[$idx]=1; done
      ;;
    --only=*)
      MODE="flag"
      for idx in "${!SELECTED[@]}"; do SELECTED[$idx]=0; done
      only="${arg#--only=}"
      IFS=',' read -ra want <<<"$only"
      for w in "${want[@]}"; do
        found=0
        for idx in "${!ITEM_KEYS[@]}"; do
          if [[ "${ITEM_KEYS[$idx]}" == "$w" ]]; then
            SELECTED[$idx]=1
            found=1
          fi
        done
        [[ "$found" == "1" ]] || warn "Unknown item '$w' in --only — ignoring. Valid keys: ${ITEM_KEYS[*]}"
      done
      ;;
    -h | --help)
      echo "Usage: ./install.sh [--all | --only=key1,key2,...]"
      echo "Keys: ${ITEM_KEYS[*]}"
      echo "No flags: interactive checkbox menu."
      exit 0
      ;;
  esac
done

if [[ "$MODE" == "interactive" ]]; then
  if [[ -t 0 ]]; then
    run_menu
  else
    warn "No TTY on stdin — can't show the interactive menu. Installing everything."
    warn "Pass --only=key1,key2 next time to pick specific items non-interactively."
  fi
fi

CHOSEN=""
for idx in "${!ITEM_KEYS[@]}"; do
  [[ "${SELECTED[$idx]}" == "1" ]] && CHOSEN="$CHOSEN ${ITEM_KEYS[$idx]}"
done
log "Installing:$CHOSEN"

# ------------------------------------------------------------------
# Directories lazy.nvim / Mason / Treesitter cache plugins, parsers, and
# LSP servers in. Wiping these forces a completely clean reinstall
# without touching init.lua itself.
# ------------------------------------------------------------------
NVIM_STATE_DIRS=(
  "$HOME/.local/share/nvim"
  "$HOME/.local/state/nvim"
  "$HOME/.cache/nvim"
)

# Starts Nvim headless against the installed config and checks whether it
# threw any errors on startup (stale plugin caches, a broken plugin API,
# etc. all surface here). Prints the raw output and returns non-zero if
# something looks wrong.
check_nvim_health() {
  local output status
  output="$(nvim --headless -c "qa" 2>&1)"
  status=$?
  if [[ $status -ne 0 ]]; then
    printf "%s\n" "$output"
    return 1
  fi
  if printf "%s" "$output" | grep -qE "Error executing lua|E5108|Failed to run .config. for|stack traceback:|module '.*' not found"; then
    printf "%s\n" "$output"
    return 1
  fi
  return 0
}

if is_selected neovim && [[ ! -f "$SCRIPT_DIR/init.lua" ]]; then
  echo "init.lua not found next to install.sh — put them in the same folder, or deselect 'neovim'." >&2
  exit 1
fi

# ------------------------------------------------------------------
# System dependencies — scoped to whatever you selected above
# ------------------------------------------------------------------
OS="$(uname -s)"

if [[ "$OS" == "Darwin" ]]; then
  log "Detected macOS — using Homebrew"

  if ! command -v brew >/dev/null 2>&1; then
    log "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  BREW_PKGS=(git curl)
  is_selected neovim && BREW_PKGS+=(neovim ripgrep fd node go python3 lazygit tree-sitter)
  is_selected codex && BREW_PKGS+=(node)
  is_selected tmux && BREW_PKGS+=(tmux reattach-to-user-namespace)
  is_selected vault && BREW_PKGS+=(ansible opensc)
  BREW_PKGS=($(printf '%s\n' "${BREW_PKGS[@]}" | sort -u))

  log "Installing via Homebrew: ${BREW_PKGS[*]}"
  brew install "${BREW_PKGS[@]}"

  if is_selected neovim; then
    if ! xcode-select -p >/dev/null 2>&1; then
      warn "Xcode Command Line Tools not detected (needed to build telescope-fzf-native)."
      warn "Run: xcode-select --install"
    fi

    # Installing both since "JetBrains Hack" isn't a single real font name —
    # Hack Nerd Font is set as the one you actually use; JetBrains Mono Nerd
    # Font is installed too in case you want to switch later.
    brew tap homebrew/cask-fonts 2>/dev/null || true

    if ! brew list --cask font-hack-nerd-font >/dev/null 2>&1; then
      log "Installing Hack Nerd Font"
      brew install --cask font-hack-nerd-font
    fi

    if ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
      log "Installing JetBrainsMono Nerd Font (backup option)"
      brew install --cask font-jetbrains-mono-nerd-font
    fi

    if ! command -v tree-sitter >/dev/null 2>&1; then
      echo "tree-sitter installed via Homebrew but still not found on \$PATH." >&2
      echo "This is almost always a GUI-vs-shell PATH mismatch on macOS —" >&2
      echo "make sure your shell rc file (~/.zshrc or ~/.zprofile) exports" >&2
      echo "Homebrew's bin dir, e.g.: eval \"\$(/opt/homebrew/bin/brew shellenv)\"" >&2
      echo "Fix that, open a NEW terminal, then re-run this script." >&2
      exit 1
    fi
  fi

elif [[ "$OS" == "Linux" ]]; then
  log "Detected Linux"

  APT_PKGS=(git curl unzip build-essential)
  is_selected neovim && APT_PKGS+=(neovim ripgrep fd-find nodejs npm golang python3 python3-pip)
  is_selected codex && APT_PKGS+=(nodejs npm)
  is_selected tmux && APT_PKGS+=(tmux xclip)
  is_selected vault && APT_PKGS+=(ansible opensc)
  APT_PKGS=($(printf '%s\n' "${APT_PKGS[@]}" | sort -u))

  DNF_PKGS=(git curl unzip gcc make)
  is_selected neovim && DNF_PKGS+=(neovim ripgrep fd-find nodejs golang python3 python3-pip)
  is_selected codex && DNF_PKGS+=(nodejs)
  is_selected tmux && DNF_PKGS+=(tmux xclip)
  is_selected vault && DNF_PKGS+=(ansible opensc)
  DNF_PKGS=($(printf '%s\n' "${DNF_PKGS[@]}" | sort -u))

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y "${APT_PKGS[@]}"
    if is_selected neovim; then
      warn "Ubuntu/Debian's neovim package can lag behind. If plugins complain about"
      warn "version requirements, add the neovim-ppa/unstable PPA and reinstall."
    fi
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "${DNF_PKGS[@]}"
  else
    warn "Unrecognized package manager — install the packages for your selected"
    warn "items manually (see the item list in this script's header), then re-run."
  fi

  if is_selected neovim && ! command -v tree-sitter >/dev/null 2>&1; then
    log "Installing tree-sitter CLI via npm (nvim-treesitter's main branch needs it)"
    sudo npm install -g tree-sitter-cli
  fi

  if is_selected neovim; then
    warn "Nerd Font install is manual on Linux — download one from nerdfonts.com"
    warn "and set it as your terminal's font for icons to render correctly."
  fi
else
  echo "Unsupported OS: $OS" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Codex CLI
#    (codex.nvim in init.lua is just a UI wrapper around this binary —
#    without it installed and logged in, the Codex keymaps do nothing)
# ------------------------------------------------------------------
if is_selected codex; then
  if ! command -v codex >/dev/null 2>&1; then
    log "Installing Codex CLI (npm install -g @openai/codex)"
    npm install -g @openai/codex
  else
    log "Codex CLI already installed ($(codex --version 2>/dev/null || echo 'version unknown'))"
  fi

  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    log "OPENAI_API_KEY is set in this shell — Codex CLI will use it automatically."
  elif codex login status >/dev/null 2>&1; then
    log "Codex CLI already authenticated."
  else
    warn "Codex CLI is installed but NOT authenticated yet."
    warn "This step is interactive (opens a browser for OAuth) and can't be"
    warn "scripted — run one of these yourself after this script finishes:"
    warn "  codex login                     # sign in with your ChatGPT account"
    warn "  export OPENAI_API_KEY=\"sk-...\"   # or use an API key instead (good for headless/CI)"
  fi
elif is_selected neovim; then
  if ! command -v codex >/dev/null 2>&1; then
    warn "'codex' item not selected and no codex CLI found on \$PATH — the"
    warn "Codex keymaps in init.lua will be inert until you install it"
    warn "(run this script again with the 'codex' item selected, or"
    warn "'npm install -g @openai/codex' yourself)."
  fi
fi

# ------------------------------------------------------------------
# Neovim: back up existing config, install, sync plugins, install LSP
# servers, validate (self-heals once if broken)
# ------------------------------------------------------------------
if is_selected neovim; then
  if [[ -d "$NVIM_CONFIG_DIR" || -L "$NVIM_CONFIG_DIR" ]]; then
    BACKUP_DIR="$HOME/.config/nvim.bak.$(date +%Y%m%d%H%M%S)"
    log "Existing ~/.config/nvim found — backing up to $BACKUP_DIR"
    mv "$NVIM_CONFIG_DIR" "$BACKUP_DIR"
  fi

  log "Installing init.lua to $NVIM_CONFIG_DIR"
  mkdir -p "$NVIM_CONFIG_DIR"
  cp "$SCRIPT_DIR/init.lua" "$NVIM_CONFIG_DIR/init.lua"

  log "Installing plugins via lazy.nvim (headless — this can take a minute)"
  nvim --headless "+Lazy! sync" +qa

  log "Installing LSP servers via Mason (headless)"
  nvim --headless "+MasonInstallAll" +qa || true
  sleep 5
  nvim --headless "+MasonToolsUpdateSync" +qa 2>/dev/null || true

  log "Validating installation (starting Nvim headless and checking for errors)"
  if HEALTH_OUTPUT="$(check_nvim_health)"; then
    log "Install looks healthy — Neovim starts clean."
  else
    warn "Detected a faulty install. Output:"
    printf "%s\n" "$HEALTH_OUTPUT" | sed 's/^/    /'
    warn "Wiping cached plugin/parser/LSP state and reinstalling once..."

    for d in "${NVIM_STATE_DIRS[@]}"; do
      rm -rf "$d"
    done

    log "Re-syncing plugins via lazy.nvim"
    nvim --headless "+Lazy! sync" +qa

    log "Re-installing LSP servers via Mason"
    nvim --headless "+MasonInstallAll" +qa || true
    sleep 5
    nvim --headless "+MasonToolsUpdateSync" +qa 2>/dev/null || true

    log "Re-validating"
    if HEALTH_OUTPUT="$(check_nvim_health)"; then
      log "Reinstall succeeded — Neovim now starts clean."
    else
      warn "Still failing after one clean reinstall attempt. Output:"
      printf "%s\n" "$HEALTH_OUTPUT" | sed 's/^/    /'
      warn "This is likely a real error in init.lua itself, not a stale cache —"
      warn "open 'nvim' interactively to see the full error and fix that line."
      exit 1
    fi
  fi

  log "Open 'nvim' once interactively so Treesitter can finish pulling parsers,"
  log "then run ':checkhealth' to confirm everything is wired up."
  warn "Codex integration: run ':Lazy' and check the codex.nvim README for"
  warn "exact command names — if they differ from <leader>cc / <leader>cs,"
  warn "update the two Codex keymaps near the bottom of init.lua."
  if [[ -z "${OPENAI_API_KEY:-}" ]] && ! codex login status >/dev/null 2>&1; then
    warn "Reminder: Codex CLI is still not authenticated — run 'codex login'"
    warn "before the Codex keymaps in Neovim will actually work."
  fi
fi

# ------------------------------------------------------------------
# tmux + oh-my-tmux with your tmux.conf.local
# ------------------------------------------------------------------
TMUX_DIR="$HOME/.tmux"
TPM_DIR="$TMUX_DIR/plugins/tpm"

if is_selected tmux; then
  if [[ ! -f "$SCRIPT_DIR/tmux.conf.local" ]]; then
    warn "tmux.conf.local not found next to install.sh — skipping tmux setup."
  else
    if [[ ! -d "$TMUX_DIR" ]]; then
      log "Cloning oh-my-tmux (gpakosz/.tmux)"
      git clone --single-branch https://github.com/gpakosz/.tmux.git "$TMUX_DIR"
    else
      log "oh-my-tmux already present at $TMUX_DIR — pulling latest"
      git -C "$TMUX_DIR" pull --ff-only || true
    fi
    ln -sf "$TMUX_DIR/.tmux.conf" "$HOME/.tmux.conf"

    if [[ -f "$HOME/.tmux.conf.local" && ! -L "$HOME/.tmux.conf.local" ]]; then
      BACKUP_TMUX_LOCAL="$HOME/.tmux.conf.local.bak.$(date +%Y%m%d%H%M%S)"
      log "Existing ~/.tmux.conf.local found — backing up to $BACKUP_TMUX_LOCAL"
      mv "$HOME/.tmux.conf.local" "$BACKUP_TMUX_LOCAL"
    fi
    log "Installing tmux.conf.local to ~/.tmux.conf.local"
    cp "$SCRIPT_DIR/tmux.conf.local" "$HOME/.tmux.conf.local"

    if [[ ! -d "$TPM_DIR" ]]; then
      log "Installing TPM (tmux plugin manager) — needed for tmux-resurrect/continuum"
      git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    fi

    log "Installing tmux plugins headlessly via TPM"
    TMUX_PLUGIN_MANAGER_PATH="$TMUX_DIR/plugins" "$TPM_DIR/bin/install_plugins" || true

    log "Validating tmux config"
    if tmux -f "$HOME/.tmux.conf" new-session -d -s __install_check 2>/tmp/tmux_check.log; then
      tmux kill-session -t __install_check 2>/dev/null || true
      log "tmux config loads clean."
    else
      warn "tmux config failed to load:"
      sed 's/^/    /' /tmp/tmux_check.log
      warn "There's likely a typo in the Neovim-integration additions at the"
      warn "bottom of ~/.tmux.conf.local — check that file directly."
      exit 1
    fi

    log "tmux is ready. Start it with 'tmux', then <prefix> I inside tmux once"
    log "if you add more TPM plugins later (this run already installed the"
    log "ones already in tmux.conf.local headlessly)."
  fi
elif is_selected alarm; then
  warn "'tmux' item not selected — meeting_alarm.sh will still be installed,"
  warn "but the prefix+A binding and status-bar countdown live in"
  warn "tmux.conf.local, so they won't exist until you also install tmux."
fi

# ------------------------------------------------------------------
# zshrc (tmux auto-boot/continuum-resume + ssh-agent prompt)
# ------------------------------------------------------------------
if is_selected zshrc; then
  if [[ ! -f "$SCRIPT_DIR/zshrc" ]]; then
    warn "zshrc not found next to install.sh — skipping shell config."
  else
    if [[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
      BACKUP_ZSHRC="$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
      log "Existing ~/.zshrc found — backing up to $BACKUP_ZSHRC"
      mv "$HOME/.zshrc" "$BACKUP_ZSHRC"
    fi
    log "Installing zshrc to ~/.zshrc"
    cp "$SCRIPT_DIR/zshrc" "$HOME/.zshrc"

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
      warn "~/.oh-my-zsh not found — this zshrc expects Oh My Zsh + the"
      warn "powerlevel9k theme already installed. Install those first:"
      warn '  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
    fi

    ZSH_KEY_DEFAULT="$HOME/.ssh/id_ed25519"
    [[ -f "$ZSH_KEY_DEFAULT" ]] || ZSH_KEY_DEFAULT="$HOME/.ssh/id_rsa"
    if [[ ! -f "$ZSH_KEY_DEFAULT" ]]; then
      warn "No SSH key found at ~/.ssh/id_ed25519 or ~/.ssh/id_rsa — the new"
      warn "ssh-agent block in .zshrc will just silently do nothing until"
      warn "one exists. Generate one with: ssh-keygen -t ed25519"
    fi

    log "zshrc installed. Effects apply on your NEXT new terminal window —"
    log "this running shell won't auto-boot into tmux retroactively."
  fi
fi

# ------------------------------------------------------------------
# Zed + a settings.json/keymap.json mirroring this Neovim setup
# ------------------------------------------------------------------
ZED_CONFIG_DIR="$HOME/.config/zed"

if is_selected zed; then
  if [[ ! -f "$SCRIPT_DIR/zed-settings.json" || ! -f "$SCRIPT_DIR/zed-keymap.json" ]]; then
    warn "zed-settings.json / zed-keymap.json not found next to install.sh —"
    warn "skipping Zed setup."
  else
    log "Installing Zed"
    if [[ "$OS" == "Darwin" ]]; then
      brew install --cask zed
    elif [[ "$OS" == "Linux" ]]; then
      curl -f https://zed.dev/install.sh | sh
    fi

    mkdir -p "$ZED_CONFIG_DIR"

    if [[ -f "$ZED_CONFIG_DIR/settings.json" && ! -L "$ZED_CONFIG_DIR/settings.json" ]]; then
      BACKUP_ZED_SETTINGS="$ZED_CONFIG_DIR/settings.json.bak.$(date +%Y%m%d%H%M%S)"
      log "Existing Zed settings.json found — backing up to $BACKUP_ZED_SETTINGS"
      mv "$ZED_CONFIG_DIR/settings.json" "$BACKUP_ZED_SETTINGS"
    fi
    cp "$SCRIPT_DIR/zed-settings.json" "$ZED_CONFIG_DIR/settings.json"

    if [[ -f "$ZED_CONFIG_DIR/keymap.json" && ! -L "$ZED_CONFIG_DIR/keymap.json" ]]; then
      BACKUP_ZED_KEYMAP="$ZED_CONFIG_DIR/keymap.json.bak.$(date +%Y%m%d%H%M%S)"
      log "Existing Zed keymap.json found — backing up to $BACKUP_ZED_KEYMAP"
      mv "$ZED_CONFIG_DIR/keymap.json" "$BACKUP_ZED_KEYMAP"
    fi
    cp "$SCRIPT_DIR/zed-keymap.json" "$ZED_CONFIG_DIR/keymap.json"

    log "Zed config installed to $ZED_CONFIG_DIR."
    warn "Two things Zed has no headless/CLI install path for — do these once"
    warn "the first time you open Zed:"
    warn "  1. cmd-shift-x -> search 'Catppuccin' -> Install (the theme"
    warn "     referenced in settings.json won't apply until this runs)"
    warn "  2. cmd-? (Agent Panel) -> '+' -> Codex — this runs the same"
    warn "     codex CLI installed above under the hood (ACP protocol),"
    warn "     so it should reuse that login. If it prompts for auth again"
    warn "     anyway, that's a separate session — same 'codex login' fix."
    if ! is_selected codex && ! command -v codex >/dev/null 2>&1; then
      warn "  Note: 'codex' item wasn't selected and no codex CLI was found —"
      warn "  the Agent Panel's Codex option needs it installed first."
    fi
  fi
fi

# ------------------------------------------------------------------
# CAC-gated Ansible Vault storage for OPENAI_API_KEY
#     Installs the MACHINERY only. The actual encrypted secrets need your
#     live CAC + real API key present, so creating them is a one-time
#     manual step this script can't safely do for you — see the printed
#     instructions below and README-secrets-vault.md.
# ------------------------------------------------------------------
OPENAI_VAULT_DIR="$HOME/.secrets/openai"
if [[ "$OS" == "Darwin" ]]; then
  PKCS11_MODULE_HINT="/opt/homebrew/lib/opensc-pkcs11.so"
  [[ -f "$PKCS11_MODULE_HINT" ]] || PKCS11_MODULE_HINT="/usr/local/lib/opensc-pkcs11.so"
else
  PKCS11_MODULE_HINT="/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so"
fi

if is_selected vault; then
  if [[ ! -f "$SCRIPT_DIR/get_vault_password.sh" ]]; then
    warn "get_vault_password.sh not found next to install.sh — skipping vault setup."
  else
    if ! command -v ansible-vault >/dev/null 2>&1; then
      warn "ansible-vault not found even after installing 'ansible' — check that"
      warn "install succeeded above before continuing."
    fi
    if ! command -v pkcs11-tool >/dev/null 2>&1; then
      warn "pkcs11-tool not found even after installing 'opensc' — CAC decrypt"
      warn "won't work until this is resolved (the password fallback still will)."
    fi

    log "Setting up $OPENAI_VAULT_DIR"
    mkdir -p "$OPENAI_VAULT_DIR"
    chmod 700 "$OPENAI_VAULT_DIR"
    cp "$SCRIPT_DIR/get_vault_password.sh" "$OPENAI_VAULT_DIR/get_vault_password.sh"
    chmod 700 "$OPENAI_VAULT_DIR/get_vault_password.sh"

    if [[ -f "$OPENAI_VAULT_DIR/vault.yml" ]]; then
      log "$OPENAI_VAULT_DIR/vault.yml already exists — leaving it alone."
    else
      warn "One-time manual setup still needed — this script will NOT do this"
      warn "part for you, it requires your physical CAC inserted and your"
      warn "real API key. Full walkthrough in README-secrets-vault.md; short"
      warn "version:"
      warn ""
      warn "  # 1. find your PIV auth key's slot id"
      warn "  pkcs11-tool --module $PKCS11_MODULE_HINT -O"
      warn ""
      warn "  # 2. export that cert's public key"
      warn "  pkcs11-tool --module $PKCS11_MODULE_HINT --read-object \\"
      warn "      --type cert --id 01 -o /tmp/cac_cert.der"
      warn "  openssl x509 -inform DER -in /tmp/cac_cert.der -pubkey -noout \\"
      warn "      > /tmp/cac_pub.pem"
      warn ""
      warn "  # 3. generate a random vault password and RSA-encrypt it against"
      warn "  #    that pubkey — this file is safe to keep even off the CAC,"
      warn "  #    since only the CAC's private key (never exported) can open it"
      warn "  openssl rand -base64 32 > /tmp/vault_pw.txt"
      warn "  openssl pkeyutl -encrypt -pubin -inkey /tmp/cac_pub.pem \\"
      warn "      -in /tmp/vault_pw.txt -out $OPENAI_VAULT_DIR/vault_password.enc"
      warn ""
      warn "  # 4. encrypt the real API key with that password"
      warn "  echo 'openai_api_key: sk-...' > /tmp/vault_plain.yml"
      warn "  ansible-vault encrypt /tmp/vault_plain.yml \\"
      warn "      --vault-password-file /tmp/vault_pw.txt \\"
      warn "      --output $OPENAI_VAULT_DIR/vault.yml"
      warn ""
      warn "  # 5. shred every plaintext temp file — none of this should"
      warn "  #    survive on disk unencrypted"
      warn "  shred -u /tmp/vault_pw.txt /tmp/vault_plain.yml /tmp/cac_cert.der /tmp/cac_pub.pem"
      warn ""
      warn "Once vault.yml + vault_password.enc exist, 'load_openai_key' in"
      warn "your new zshrc decrypts on demand — CAC+PIN first, falls back to"
      warn "typing the vault password directly if the CAC isn't available."
    fi
  fi
fi

# ------------------------------------------------------------------
# Meeting alarm (tmux prefix+A) + launchd LaunchAgent for `check`
# ------------------------------------------------------------------
ALARM_DIR="$HOME/.tmux/alarms"

if is_selected alarm; then
  if [[ ! -f "$SCRIPT_DIR/meeting_alarm.sh" ]]; then
    warn "meeting_alarm.sh not found next to install.sh — skipping meeting-alarm setup."
  else
    log "Installing meeting_alarm.sh to $ALARM_DIR"
    mkdir -p "$ALARM_DIR"
    cp "$SCRIPT_DIR/meeting_alarm.sh" "$ALARM_DIR/meeting_alarm.sh"
    chmod +x "$ALARM_DIR/meeting_alarm.sh"

    if [[ "$OS" == "Darwin" ]]; then
      LAUNCHD_LABEL="com.mikeroach.meeting-alarm-check"
      LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
      mkdir -p "$HOME/Library/LaunchAgents"

      log "Registering launchd LaunchAgent to run 'meeting_alarm.sh check' every 60s"
      cat >"$LAUNCHD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$ALARM_DIR/meeting_alarm.sh</string>
        <string>check</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$ALARM_DIR/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>$ALARM_DIR/launchd.err.log</string>
</dict>
</plist>
PLIST

      launchctl unload "$LAUNCHD_PLIST" >/dev/null 2>&1 || true
      if launchctl load "$LAUNCHD_PLIST" >/dev/null 2>&1; then
        log "LaunchAgent loaded — 'meeting_alarm.sh check' now runs every 60s independent of tmux."
      else
        warn "launchctl load failed for $LAUNCHD_PLIST — check it manually with:"
        warn "  launchctl load $LAUNCHD_PLIST"
      fi
    else
      warn "launchd is macOS-only — on Linux, run 'crontab -e' and add:"
      warn "  * * * * * $ALARM_DIR/meeting_alarm.sh check"
      warn "to get the same 'fires even without tmux attached' behavior."
    fi

    warn "Clock app mirroring needs a one-time manual Shortcuts app setup —"
    warn "see README-meeting-alarm.md. Without it, the tmux countdown and the"
    warn "macOS notification at T-0 still work fine on their own."
    log "In tmux: prefix + A to set an alarm (HH:MM, 24h, today). Countdown"
    log "appears in the status bar's third line inside the last 15 minutes."
  fi
fi

log "Done. Re-run './install.sh' any time to add more items — existing"
log "configs are backed up automatically before anything gets overwritten."
