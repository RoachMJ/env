# tmux meeting alarm

Set a same-day meeting alarm from a tmux key combo, see a countdown in the
status bar for the last 15 minutes before it, get a macOS notification at
T-0, and optionally have that same alarm show up in the native Clock app.

## How it fits together

- `meeting_alarm.sh` (installed to `~/.tmux/alarms/meeting_alarm.sh`) holds
  all the logic: `set`, `status`, `check`, `list`, `clear`.
- `tmux.conf.local` wires two pieces to it:
  - `prefix + A` prompts for `HH:MM` and calls `meeting_alarm.sh set`.
  - `status-format[2]` (the status bar's 3rd line) calls `meeting_alarm.sh
    status` on a timer, which prints a countdown once 15 minutes remain and
    prints nothing otherwise.
- `install.sh` registers a macOS `launchd` LaunchAgent that runs
  `meeting_alarm.sh check` every 60 seconds **independent of tmux** — so
  the alarm still fires (notification + Clock app) even if tmux isn't
  attached or the terminal is closed. On Linux, `install.sh` prints the
  equivalent `crontab` line instead, since `launchd` is macOS-only.

## Daily usage

Inside tmux: `prefix + A`, type a 24-hour time like `14:30`, Enter.

- Nothing happens visibly until 15 minutes remain — then the status bar's
  bottom line shows a countdown like `⏰ 14:15 - meeting`.
- At T-0, a macOS notification fires (`osascript display notification`)
  and, if the Shortcuts setup below is done, the alarm also gets added to
  the Clock app.
- Each alarm is one-shot — it's removed from the list once it fires.

Other subcommands, run directly if you want to check state by hand:

```bash
~/.tmux/alarms/meeting_alarm.sh list    # see what's currently set
~/.tmux/alarms/meeting_alarm.sh clear   # wipe everything
```

## One-time setup: mirroring into the Clock app

**Read this first:** macOS's Clock app has no AppleScript dictionary and
no CLI of its own — there is no way to script it directly. The one real
integration point is the Shortcuts app's built-in "Add Alarm" action,
which `meeting_alarm.sh` invokes via the `shortcuts run` CLI (macOS 12+,
Monterey and later). That action has to exist as a Shortcut you build by
hand, once — it can't be created headlessly by a script.

Without this step, everything else still works fully: the tmux countdown
and the T-0 notification don't depend on it. This step only adds "also
show up as a real alarm in Clock.app."

### Steps

1. Open the **Shortcuts** app.
2. Click **+** to create a new shortcut.
3. Name it exactly **`Set Meeting Alarm`** (or pick your own name and set
   `MEETING_ALARM_SHORTCUT` to match — see below).
4. Add the **"Receive text input"** setup: with the shortcut open, the
   "Shortcut Input" is available automatically as a variable — no extra
   action needed for this part.
5. Add the **"Add Alarm"** action (search for it in the action library).
   Set its time field to the **Shortcut Input** variable (the text passed
   in) rather than a fixed time.
6. Save.

Test it manually first, outside of tmux:

```bash
echo "14:30" | shortcuts run "Set Meeting Alarm"
```

Open Clock.app and confirm a 2:30 PM alarm appeared. If it did, the
integration is live — `meeting_alarm.sh set` will call this same Shortcut
every time going forward.

### If you used a different Shortcut name

Export `MEETING_ALARM_SHORTCUT` before the script runs, e.g. in your
`.zshrc`:

```zsh
export MEETING_ALARM_SHORTCUT="My Custom Alarm Shortcut"
```

### If it's not set up (or `shortcuts` isn't available)

`meeting_alarm.sh set` still records the alarm and drives the tmux
countdown + T-0 notification normally — it just logs a warning to
`~/.tmux/alarms/meeting_alarm.log` and skips the Clock app step. Nothing
fails loudly in the tmux status bar because of this.

## Troubleshooting

- **No countdown ever appears:** confirm `status-format[2]` is actually
  rendering — run `~/.tmux/alarms/meeting_alarm.sh status` by hand within
  15 minutes of a set alarm and confirm it prints something. If that
  works but tmux shows nothing, check `set -ag status 3` is present in
  `tmux.conf.local` (3 status-bar lines: main, k8s context, alarm).
- **Alarm never fires as a notification:** the LaunchAgent may not be
  loaded. Check with `launchctl list | grep meeting-alarm`. If it's
  missing, re-run `launchctl load ~/Library/LaunchAgents/com.mikeroach.meeting-alarm-check.plist`.
  Logs land in `~/.tmux/alarms/launchd.out.log` / `launchd.err.log`.
- **Clock app never gets the alarm:** almost always the Shortcut name
  mismatch or the Shortcut missing the "Add Alarm" action. Re-run the
  manual test command above and check `~/.tmux/alarms/meeting_alarm.log`
  for the exact warning.
