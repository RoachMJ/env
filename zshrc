ZSH_DISABLE_COMPFIX="true"
# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$PATH:$HOME/Library/Python/3.10/bin
TERM=xterm-256color
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# ZSH_THEME="robbyrussell"
#
POWERLEVEL9K_MODE='nerdfont-complete'
ZSH_THEME="powerlevel9k/powerlevel9k"
# Set list of themes to pick from when loading at random
#
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in ~/.oh-my-zsh/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to automatically update without prompting.
# DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS=true

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"
CLICOLOR_FORCE=1
# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in ~/.oh-my-zsh/plugins/*
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git docker brew history node npm kubectl argocd fluxcd)

source $ZSH/oh-my-zsh.sh
source ~/.oh-my-zsh/functions
set -o vi
# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
# Set username to consider a default context, which by default will not be shown.
# https://github.com/bhilburn/powerlevel9k/blob/next/segments/context/README.md
source $HOME/.p9kgt
source $HOME/.zsh_profile
source $HOME/.zsh_functions

# https://github.com/bhilburn/powerlevel9k/blob/next/segments/context/README.md
#
#
#     ------------- powerlevel 9k functions config --------------
#
#          .oh-my-zsh/custom/themes/powerlevel9k/powerlevel9k.zsh-theme
#
#          -------------   custom config -------------
# Powerlevel 9k configuration file .oh-my-zsh/custom/powerlvl9k_config
#
#------------------------------------------------------------------
source ${HOME}/.oh-my-zsh/custom/pwr9config

# --------------------  ADDED COMMANDS FOR SIMILAR BASH BINDNGS -----------
bindkey "^?" backward-delete-char

# --------------------- ALIASES -----------------------------------
#
#
#    COLORIZED CAT ALIAS
alias dog='pygmentize -g'
alias remote='ssh -L localhost:30003:localhost:30003 roach@10.90.10.90'
alias docker-containers='docker run -it --privileged --pid=host debian nsenter -t 1 -m -u -n -i sh'

# ---------- ls ---------------------------------------------------
alias ll='ls -al'
alias l='ls -l'
alias sl=ls

# --------------------git ------------------------------------------
alias g='git'
alias gd='git d'
alias gg='git g'
alias gs='git s'
alias gl='git l'
alias wtf='git wtf'
alias fixfirefox='cd ~/Library/Application\ Support/Firefox/Profiles/ && echo "Remove most recent directory"'


# --------------------- Add Keys to Host ---------------------------
# Manual re-trigger if you ever need to force a fresh agent/key load.
# --apple-use-keychain replaces the old (deprecated) -K flag.
alias sagent='eval "$(ssh-agent -s)" && ssh-add --apple-use-keychain ~/.ssh/id_rsa'



# ---------------------- vim bindings ------------------------------
#
bindkey -M viins 'jj' vi-cmd-mode
#
# --------------------- common dislexia commands -------------------
#
alias getsource='source ~/.zshrc && cd -'

alias kindcluster='echo "kind create cluster --name kind-local --config ~/loki-dev/cluster.yaml"'

function kclusterimages() {
    kind_nodes=($(docker ps -a | grep kindest | awk 'NR>=1 {print $1}'));
    for container in ${kind_nodes[@]};
    do;
        echo $container && docker exec -it $container /bin/bash -c "crictl images";
    done;
}

# ---------------------- LOCALSTACK --------------------------------
#
export LOCALSTACK_AUTH_TOKEN="<TOKEN>"

# ---------------------- FUNCTION ALIASES --------------------------
#
#
function mkdirs
{
  command mkdir $1 && cd $1
}

function hubgit() {
    git remote add origin git@github.com:Roach-0351/"$1".git
}

function gitall() {
    git add .
    if [ "$1" != "" ] # or better, if [ -n "$1" ]
    then
        git commit -m "$1"
    else
        git commit -m update
    fi
    git push
}

function gitremall() {
    git add .
    if [ "$1" != "" ]
    then
        git commit -m "$1"
    else
        git commit -m update # default commit message is `update`
    fi # closing statement of if-else block
    git push origin HEAD
}

function fame {
  git ls-tree -r -z --name-only HEAD | xargs -0 -n1 git blame --line-porcelain HEAD \
    | grep "^author " | sort | uniq -c | sort -nr
}

# ping
if [[ -x `which prettyping` ]]; then alias ping='prettyping --nolegend'; fi

#Fastboot
export PATH="$PWD/platform-tools:$PATH"


export PATH="/usr/local/opt/openjdk/bin:$PATH"
export PATH="/usr/local/Cellar/kubernetes-cli/1.31.1/bin:$PATH"

cd ~/dev

# ============================================================
# SSH agent — start/reuse + prompt for key passphrase
# ============================================================
# Reuses one ssh-agent per boot (env stashed in $SSH_ENV) instead of
# spawning a new one per terminal tab. On macOS, --apple-use-keychain
# stores the unlocked passphrase in Keychain, so in practice you're only
# prompted once (or after a reboot / Keychain lock), not on every shell.
SSH_ENV="$HOME/.ssh/agent-environment"
SSH_KEY_DEFAULT="$HOME/.ssh/id_ed25519"
[[ -f "$SSH_KEY_DEFAULT" ]] || SSH_KEY_DEFAULT="$HOME/.ssh/id_rsa"

start_ssh_agent() {
    ssh-agent -s | sed 's/^echo/#echo/' > "$SSH_ENV"
    chmod 600 "$SSH_ENV"
    source "$SSH_ENV" > /dev/null
}

load_ssh_key() {
    [[ -f "$SSH_KEY_DEFAULT" ]] || return
    local fp
    fp="$(ssh-keygen -lf "$SSH_KEY_DEFAULT" 2>/dev/null | awk '{print $2}')"
    if [[ -n "$fp" ]] && ssh-add -l 2>/dev/null | grep -q "$fp"; then
        return # key already loaded in the agent, nothing to prompt for
    fi
    if [[ "$(uname -s)" == "Darwin" ]]; then
        ssh-add --apple-use-keychain "$SSH_KEY_DEFAULT"
    else
        ssh-add "$SSH_KEY_DEFAULT"
    fi
}

if [[ $- == *i* ]] && command -v ssh-agent &>/dev/null; then
    if [[ -f "$SSH_ENV" ]]; then
        source "$SSH_ENV" > /dev/null
        ps -p "${SSH_AGENT_PID:-0}" > /dev/null 2>&1 || start_ssh_agent
    else
        start_ssh_agent
    fi
    load_ssh_key
fi

# ============================================================
# OpenAI API key — CAC-gated Ansible Vault, decrypt-on-demand
# ============================================================
# Deliberately NOT run automatically at shell startup — unlike the ssh-agent
# above, this should not prompt for a CAC PIN (or the backup password) on
# every single new terminal/tmux pane. Call `load_openai_key` yourself
# right before you need Codex/the API. See README-secrets-vault.md for the
# one-time setup that creates vault.yml / vault_password.enc — this
# function only ever reads them.
OPENAI_VAULT_DIR="$HOME/.secrets/openai"

load_openai_key() {
    local vault_file="$OPENAI_VAULT_DIR/vault.yml"
    local resolver="$OPENAI_VAULT_DIR/get_vault_password.sh"

    if [[ ! -f "$vault_file" || ! -x "$resolver" ]]; then
        echo "load_openai_key: $OPENAI_VAULT_DIR isn't set up yet." >&2
        echo "  See README-secrets-vault.md for the one-time setup." >&2
        return 1
    fi

    local decrypted key
    decrypted="$(ansible-vault view "$vault_file" --vault-password-file "$resolver" 2>/dev/null)" || {
        echo "load_openai_key: ansible-vault decrypt failed (wrong CAC/password?)." >&2
        return 1
    }

    key="$(printf '%s\n' "$decrypted" | sed -n 's/^openai_api_key:[[:space:]]*//p' | head -n1)"
    if [[ -z "$key" ]]; then
        echo "load_openai_key: decrypted vault.yml but found no 'openai_api_key:' line." >&2
        return 1
    fi

    export OPENAI_API_KEY="$key"
    echo "OPENAI_API_KEY loaded into this shell session." >&2
}

# ============================================================
# TMUX auto-boot — replaces the old "Launch/attach to tmux? y/n" prompt
# ============================================================
# Starting a brand-new tmux server here (no server running yet) triggers
# tmux-continuum's @continuum-restore (set in tmux.conf.local), which
# repopulates your last saved sessions/windows/panes automatically — so a
# fresh terminal after a reboot resumes where you left off instead of
# opening blank. If a server is already running, `tmux attach` with no
# -t reattaches to whatever session was most recently active, so repeated
# new terminal windows/tabs join the same live session instead of piling
# up duplicates.
#
# Nesting guard: `$TMUX` only catches "already inside tmux ON THIS HOST" —
# it's a local env var and does NOT get forwarded over SSH. If you SSH out
# to a remote box from inside a local tmux pane, the remote shell's $TMUX
# is empty, so without a second check it would happily auto-boot ANOTHER
# tmux server on the remote end — nested tmux, double prefix key, broken
# status bar, the works. $TERM *does* get passed through SSH (it's part of
# the pty allocation, not a regular forwarded env var), and tmux always
# sets it to something starting with "tmux" or "screen" for anything
# running inside it — including the remote shell you just SSH'd into from
# a local tmux pane. So checking $TERM catches the cross-host case that
# $TMUX alone misses, on top of the same-host case $TMUX already covers.
if [[ $- == *i* ]] \
    && command -v tmux &>/dev/null \
    && [[ -z "$TMUX" ]] \
    && [[ "$TERM" != screen* && "$TERM" != tmux* ]]; then
    tmux attach 2>/dev/null || tmux new-session -c ~/dev
fi
