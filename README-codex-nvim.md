# Codex + Neovim setup

How the Codex CLI is wired into this Neovim config, how to authenticate it, and how to keep a work and personal account separate.

## How it fits together

`codex.nvim` (declared in `init.lua`) is a thin UI wrapper — it does not do any authentication or model calls itself. It shells out to the `codex` binary (the Codex CLI) that `install.sh` installs via `npm install -g @openai/codex`. If the CLI isn't installed or isn't authenticated, the Neovim keymaps (`<leader>cc`, `<leader>cs`) will fail even though the plugin loaded fine — always check the CLI directly first when something's not working.

```
Neovim (codex.nvim) --shells out to--> codex CLI --auths as--> your OpenAI/ChatGPT account
```

## Authenticating the CLI

Run this once per machine (or per account profile, see below):

```bash
codex login
```

This opens a browser for an OAuth sign-in against your ChatGPT account and stores the session under `~/.codex` (`$CODEX_HOME`). For headless boxes (SSH-only servers, CI), use an API key instead:

```bash
export OPENAI_API_KEY="sk-..."
```

`install.sh` checks for both and prints a reminder if neither is set up yet — it can't complete this step for you since the OAuth flow requires a browser.

## Two auth modes, and why it matters

Codex CLI supports two distinct ways to authenticate, and they bill completely differently:

| Mode | How | Billing |
|---|---|---|
| Sign in with ChatGPT | `codex login` | Draws from your ChatGPT plan's included usage |
| API key | `OPENAI_API_KEY` env var | Pay-per-token against an OpenAI Platform project |

This matters for the next section — project-level segregation only applies to the API-key mode.

## Keeping work and personal usage separate

**Short answer: yes, on the same OpenAI account, using API-key mode plus OpenAI Platform Projects — but not with "Sign in with ChatGPT" mode.**

- If you're using `codex login` (ChatGPT sign-in), all usage draws from one plan-level bucket tied to that ChatGPT account. There's no per-project split available in this mode — the only way to fully separate that is genuinely separate ChatGPT accounts (see the account-switching notes elsewhere in this setup).
- If you switch to API-key mode, OpenAI Platform lets you create multiple **Projects** under a single account/org (Platform → Settings → Projects). Each project gets its own scoped API key, its own rate limits, its own spend/budget limits, and its own line in the usage dashboard. Create a "Personal" project and a "Work" project, generate one key per project, and point Codex CLI at whichever key matches the context you're in:

```bash
export OPENAI_API_KEY="sk-proj-...work-key..."
# or
export OPENAI_API_KEY="sk-proj-...personal-key..."
```

- `OPENAI_PROJECT_ID` can also be set explicitly to scope a request/session to a specific project if you're using an org-level key rather than a project-scoped one.

### Making the switch low-friction

Manually re-exporting `OPENAI_API_KEY` every time you change context is easy to forget. Two options used earlier in this setup:

1. **`CODEX_HOME` per profile** — keep entirely separate `~/.codex-work` and `~/.codex-personal` directories (each with its own `auth.json`), and alias a launcher for each:

   ```bash
   alias codex-work='CODEX_HOME=$HOME/.codex-work codex'
   alias codex-personal='CODEX_HOME=$HOME/.codex-personal codex'
   ```

2. **Per-project `.env` / direnv** — drop `OPENAI_API_KEY=sk-proj-...work-key...` in a work repo's `.envrc` (direnv) so it's scoped automatically by directory, with no manual switching at all.

Either approach keeps usage, spend, and rate limits cleanly separated on the OpenAI Platform side, without needing two separate logins.

## Troubleshooting

- **Codex keymaps do nothing in Neovim**: run `codex --version` in a plain terminal first. If that fails, the CLI itself isn't installed/on `$PATH` — fix that before touching Neovim.
- **`codex login status` fails**: not authenticated yet — run `codex login` or set `OPENAI_API_KEY`.
- **Wrong account/project active**: check `echo $OPENAI_API_KEY` (or `echo $CODEX_HOME` if using the profile-alias approach) to confirm which context the current shell is in before launching Neovim from it — Neovim inherits whatever `codex` sees in that shell's environment at launch time.
- **Command names in Neovim don't match**: `codex.nvim` has a few independent community implementations with slightly different command names. Run `:Lazy` inside Neovim, open the codex.nvim entry, and check its README for the actual command names if `<leader>cc`/`<leader>cs` don't do what's expected — update the two keymaps near the bottom of `init.lua` to match.
