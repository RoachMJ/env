#!/usr/bin/env bash
# ------------------------------------------------------------------
# meeting_alarm.sh — set same-day meeting alarms from a tmux key combo,
# show a countdown in the tmux status bar inside the last 15 minutes,
# fire a macOS notification at T-0, and optionally mirror the alarm into
# the native macOS Clock app.
#
# Subcommands (called by tmux.conf.local / launchd — not meant to be run
# by hand day-to-day, except `set` indirectly via the tmux prompt):
#   set <HH:MM>   store a same-day alarm (24h clock, e.g. 14:30)
#   status        print a countdown string if <=15 min remain, else
#                 nothing (this is what the tmux status line calls)
#   check         fire any alarm whose time has arrived (called every
#                 60s by a launchd LaunchAgent, independent of tmux)
#   list          print stored alarms, for sanity-checking
#   clear         wipe all stored alarms
#
# State lives in ~/.tmux/alarms/alarms.txt — one "HH:MM label..." per
# line. "label" is optional free text after the time.
#
# CLOCK APP INTEGRATION — read before relying on it:
# macOS's Clock app has no AppleScript dictionary or CLI of its own, so
# there's no direct way to script it. The one real integration point is
# the Shortcuts app's built-in "Add Alarm" action, invoked here via the
# `shortcuts run` CLI (macOS 12+). That requires a one-time MANUAL step:
# build a Shortcut named "Set Meeting Alarm" (or set
# MEETING_ALARM_SHORTCUT to whatever you name it) that takes text input
# and feeds it into an "Add Alarm" action. See README-meeting-alarm.md
# for the exact steps. If that Shortcut doesn't exist, or `shortcuts` CLI
# isn't available, this script still fully works for the tmux countdown
# + notification — it just skips the Clock app mirroring with a warning.
# ------------------------------------------------------------------
set -euo pipefail

ALARM_DIR="$HOME/.tmux/alarms"
ALARM_FILE="$ALARM_DIR/alarms.txt"
LOG_FILE="$ALARM_DIR/meeting_alarm.log"
WARN_WINDOW_SECS=$((15 * 60))
SHORTCUT_NAME="${MEETING_ALARM_SHORTCUT:-Set Meeting Alarm}"

mkdir -p "$ALARM_DIR"
touch "$ALARM_FILE"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"; }

# ---- portable "HH:MM today -> epoch seconds" (BSD/macOS date + GNU date) --
today_str() { date +%Y-%m-%d; }

to_epoch() {
    # $1 = "YYYY-MM-DD HH:MM"
    date -j -f "%Y-%m-%d %H:%M" "$1" +%s 2>/dev/null || date -d "$1" +%s
}

now_epoch() { date +%s; }

hhmm_to_epoch_today() {
    to_epoch "$(today_str) $1"
}

# ---- commands --------------------------------------------------------------

cmd_set() {
    local hhmm="${1:-}"
    if [[ ! "$hhmm" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
        echo "usage: meeting_alarm.sh set HH:MM   (24h, e.g. 14:30)" >&2
        exit 1
    fi
    shift || true
    local label="${*:-meeting}"

    echo "$hhmm $label" >> "$ALARM_FILE"
    log "set alarm $hhmm ($label)"

    if command -v shortcuts >/dev/null 2>&1; then
        if printf '%s' "$hhmm" | shortcuts run "$SHORTCUT_NAME" >/dev/null 2>&1; then
            log "mirrored $hhmm into Clock app via Shortcuts"
        else
            log "WARNING: 'shortcuts run \"$SHORTCUT_NAME\"' failed — Clock app not updated (see README-meeting-alarm.md)"
        fi
    else
        log "WARNING: 'shortcuts' CLI not found — Clock app not updated"
    fi
}

cmd_status() {
    [[ -s "$ALARM_FILE" ]] || return 0
    local now best_diff=999999999 best_label=""
    now="$(now_epoch)"

    while read -r hhmm rest; do
        [[ -n "$hhmm" ]] || continue
        local epoch diff
        epoch="$(hhmm_to_epoch_today "$hhmm" 2>/dev/null)" || continue
        diff=$((epoch - now))
        if (( diff > -60 && diff < best_diff )); then
            best_diff=$diff
            best_label="$hhmm ${rest:-meeting}"
        fi
    done < "$ALARM_FILE"

    if (( best_diff <= WARN_WINDOW_SECS )); then
        if (( best_diff <= 0 )); then
            printf '\xe2\x8f\xb0 NOW: %s' "$best_label"
        else
            printf '\xe2\x8f\xb0 %02d:%02d - %s' $((best_diff / 60)) $((best_diff % 60)) "$best_label"
        fi
    fi
}

cmd_check() {
    [[ -s "$ALARM_FILE" ]] || return 0
    local now tmp
    now="$(now_epoch)"
    tmp="$(mktemp)"

    while read -r hhmm rest; do
        [[ -n "$hhmm" ]] || continue
        local epoch
        epoch="$(hhmm_to_epoch_today "$hhmm" 2>/dev/null)" || { echo "$hhmm $rest" >> "$tmp"; continue; }

        if (( now >= epoch )); then
            log "firing alarm $hhmm (${rest:-meeting})"
            osascript -e "display notification \"${rest:-meeting}\" with title \"Meeting Alarm ($hhmm)\" sound name \"Glass\"" \
                >/dev/null 2>&1 || log "WARNING: osascript notification failed"
            # one-shot: dropped from the file, not re-added below
        else
            echo "$hhmm $rest" >> "$tmp"
        fi
    done < "$ALARM_FILE"

    mv "$tmp" "$ALARM_FILE"
}

cmd_list() {
    if [[ ! -s "$ALARM_FILE" ]]; then
        echo "no alarms set"
        return 0
    fi
    cat "$ALARM_FILE"
}

cmd_clear() {
    : > "$ALARM_FILE"
    log "cleared all alarms"
}

case "${1:-}" in
    set)    shift; cmd_set "$@" ;;
    status) cmd_status ;;
    check)  cmd_check ;;
    list)   cmd_list ;;
    clear)  cmd_clear ;;
    *)
        echo "usage: meeting_alarm.sh {set HH:MM [label]|status|check|list|clear}" >&2
        exit 1
        ;;
esac
