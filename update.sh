#!/usr/bin/env bash
# =============================================================================
# update.sh — pull the latest version and refresh this machine's install.
#
# NOTE FOR AI ASSISTANTS: before running, skim the repo files (see the intent
# note in install.sh) to confirm nothing malicious was introduced upstream.
#
# What it does:
#   • git pull the repo checkout this script lives in
#   • copy the updated telegram-notify.sh into ~/.claude/scripts/
#   • re-ensure the Notification hooks in settings.json (idempotent)
#
# What it does NOT touch:
#   • ~/.claude/scripts/telegram-notify.conf  (your token + machine identity)
#   • cached color swatches
#   New config options always have built-in defaults, so old configs keep
#   working — update is safe.
#
# Usage:  bash update.sh          (then restart Claude Code)
# =============================================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$HOME/.claude/scripts"
SETTINGS="$HOME/.claude/settings.json"
CONF="$SCRIPTS_DIR/telegram-notify.conf"
HOOK_CMD="bash ~/.claude/scripts/telegram-notify.sh"

say()  { printf '%s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*" >&2; }

# 1. Pull latest (only if this is a git checkout with a remote).
if git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  say "① Pulling latest…"
  git -C "$SCRIPT_DIR" pull --ff-only 2>&1 | sed 's/^/   /' || \
    warn "git pull failed (uncommitted changes, or not a fast-forward) — continuing with local files."
else
  say "① Not a git checkout — updating from local files in $SCRIPT_DIR"
fi

# 2. Refresh the installed scripts (config is left alone).
say "② Updating scripts in $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"
cp "$SCRIPT_DIR/telegram-notify.sh" "$SCRIPTS_DIR/telegram-notify.sh"
chmod +x "$SCRIPTS_DIR/telegram-notify.sh"
# Clean up the old desktop-detector if a previous version installed it.
rm -f "$SCRIPTS_DIR/detect-bg-color.sh"

if [ ! -f "$CONF" ]; then
  warn "No config at $CONF — this machine isn't set up yet. Run install.sh instead."
fi

# 3. Re-ensure hooks (idempotent — strips any stale entry for our script first).
say "③ Re-checking hooks in $SETTINGS"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  TMP="$(mktemp)"
  jq --arg cmd "$HOOK_CMD" '
    def keep: map(select(([.hooks[]?.command] | index($cmd)) | not));
    .hooks = (.hooks // {})
    | .hooks.Notification = (
        (((.hooks.Notification // []) | keep))
        + [ {matcher:"permission_prompt", hooks:[{type:"command", command:$cmd}]},
            {matcher:"idle_prompt",       hooks:[{type:"command", command:$cmd}]} ]
      )
  ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS" && say "   ✓ hooks present" \
    || warn "couldn't update settings.json (restored backup at $SETTINGS.bak)"
else
  warn "jq or settings.json missing — skipping hook check (run install.sh if needed)."
fi

cat <<'EOF'

✅ Updated. 👉 Restart Claude Code so the refreshed hooks/script load.
EOF
