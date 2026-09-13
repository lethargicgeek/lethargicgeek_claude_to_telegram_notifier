#!/bin/bash
# Claude Code -> Telegram notifier.  v3
# Fired by hooks in ~/.claude/settings.json.
#
# Machine identity + secrets live in a separate config file so this script is
# identical on every machine. Config sourced from the first of:
#   1) $CLAUDE_TELEGRAM_CONF  (if set)
#   2) ~/.claude/scripts/telegram-notify.conf
#
# Config must define:
#   TELEGRAM_TOKEN  - bot token (same on every machine, single shared channel)
#   CHAT_ID         - the one shared chat/channel id
#   MACHINE_NAME    - human label for THIS machine, e.g. "mac-mini-03"
#   MACHINE_COLOR   - free-text color label for reference only (NOT shown in messages)
# Optional:
#   MACHINE_ICON    - any emoji/glyph to tag this machine, e.g. "🖥️" or "🚀"
#   WORK_FINGERPRINT- "1" (default) leads each msg with an emoji derived from a hash
#                     of folder-path + git-branch, repeated WORK_EMOJI_REPEAT times,
#                     so each distinct work context (e.g. per branch) gets a stable,
#                     unique emoji. "0" disables it.
#   WORK_EMOJI_REPEAT - how many times to repeat that emoji (default 5)
#   MACHINE_HEX     - hex like "#E06C75"; drives both the glyph and the swatch image
#   MACHINE_EMOJI   - explicit glyph; overrides the hex-derived one (text mode)
#   NOTIFY_MODE     - "photo" -> send an exact-color swatch image (caption = the alert)
#                     "text"  -> send a text message with a nearest-hue emoji (default)
#   SWATCH_FILE     - override the cached swatch path
#
# v3 changes:
#   * NOTIFY_MODE=photo: pixel-exact color via a cached swatch image (sendPhoto),
#     the only way to render an exact color in Telegram. Falls back to text if the
#     image can't be produced or the photo send fails.

CONF="${CLAUDE_TELEGRAM_CONF:-$HOME/.claude/scripts/telegram-notify.conf}"
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  source "$CONF"
fi

if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "telegram-notify: missing TELEGRAM_TOKEN/CHAT_ID (config: $CONF)" >&2
  exit 0
fi
MACHINE_NAME="${MACHINE_NAME:-$(hostname -s 2>/dev/null || hostname)}"
NOTIFY_MODE="${NOTIFY_MODE:-text}"
WORK_FINGERPRINT="${WORK_FINGERPRINT:-1}"
WORK_EMOJI_REPEAT="${WORK_EMOJI_REPEAT:-9}"

# How much of Claude's message to include. This is OUR cap, not Telegram's
# (Telegram allows 4096 chars for text, 1024 for a photo caption). Clamped below
# to stay under those ceilings — photo mode is the tighter one.
MAX_MSG_CHARS="${MAX_MSG_CHARS:-1200}"
case "$MAX_MSG_CHARS" in ''|*[!0-9]*) MAX_MSG_CHARS=1200;; esac
if [ "$NOTIFY_MODE" = "photo" ]; then __ceil=850; else __ceil=3800; fi
[ "$MAX_MSG_CHARS" -gt "$__ceil" ] && MAX_MSG_CHARS="$__ceil"

# Truncate to N chars, appending an ellipsis only when actually shortened.
trunc() {
  local s="$1" n="$2"
  if [ "${#s}" -gt "$n" ]; then printf '%s…' "$(printf '%s' "$s" | cut -c1-"$n")"; else printf '%s' "$s"; fi
}

# Normalize hex: strip '#', expand 3-digit shorthand -> 6-digit.
HEXCLEAN="${MACHINE_HEX#\#}"
if [ ${#HEXCLEAN} -eq 3 ]; then
  HEXCLEAN="${HEXCLEAN:0:1}${HEXCLEAN:0:1}${HEXCLEAN:1:1}${HEXCLEAN:1:1}${HEXCLEAN:2:1}${HEXCLEAN:2:1}"
fi
[ ${#HEXCLEAN} -ne 6 ] && HEXCLEAN=""

# --- Nearest-hue glyph from a hex (text mode) -------------------------------
pick_emoji() {
  local hex="$1"
  [ -z "$hex" ] && { printf '⬜'; return; }
  local r g b
  r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
  awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN{
    max=r; if(g>max)max=g; if(b>max)max=b; min=r; if(g<min)min=g; if(b<min)min=b; d=max-min;
    if(max<40){ print "⬛"; exit }
    if(d < max*0.12){ if(max>200)print "⬜"; else if(max>90)print "🟫"; else print "⬛"; exit }
    if(max==r) hue=60*((g-b)/d); else if(max==g) hue=60*(2+(b-r)/d); else hue=60*(4+(r-g)/d);
    if(hue<0) hue+=360;
    if(hue<15||hue>=345) e="🟥"; else if(hue<45) e="🟧"; else if(hue<70) e="🟨";
    else if(hue<170) e="🟩"; else if(hue<255) e="🟦"; else e="🟪";
    print e }'
}

# --- Work fingerprint: hash(folder path + branch) -> a stable, unique emoji ---
# Same folder+branch always yields the same emoji; a new branch yields a new one.
work_emoji() {
  local key="$1" h n
  h=$(printf '%s' "$key" | shasum -a 256 2>/dev/null | cut -c1-8)
  if [ -z "$h" ]; then
    # portable fallback if shasum is unavailable
    h=$(printf '%08x' "$(printf '%s' "$key" | cksum | cut -d' ' -f1)")
  fi
  n=$((16#$h))
  # Curated set of ~472 visually distinct, deduped emoji (avoids the color squares
  # used for machine color). Large palette -> collisions stay negligible even with
  # many concurrent branches/worktrees.
  local p=(\
           🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 \
           🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🦗 🕷 🦂 \
           🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🐊 \
           🐅 🐆 🦓 🦍 🦧 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🐃 🐄 🐎 🐖 🐏 🐑 \
           🦙 🐐 🦌 🐕 🐩 🦮 🐈 🐓 🦃 🦚 🦜 🦢 🦩 🕊 🐇 🦝 🦨 🦡 \
           🦦 🦥 🐁 🐀 🐿 🦔 🦭 🦤 🪶 🦫 🌵 🎄 🌲 🌳 🌴 🌱 🌿 ☘️ \
           🍀 🎍 🎋 🍃 🍂 🍁 🍄 🌾 💐 🌷 🌹 🥀 🌺 🌸 🌼 🌻 🌞 🌝 \
           🌛 🌜 🌚 🌕 🌗 🌑 🌒 🌓 🌔 🌙 🌎 🌍 🌏 🪐 💫 ⭐ 🌟 ✨ \
           ⚡ ☄️ 💥 🔥 🌪 🌈 ☀️ 🌤 ⛅ 🌥 ☁️ 🌦 🌧 ⛈ 🌩 🌨 ❄️ ☃️ \
           ⛄ 🌬 💨 💧 💦 ☔ 🌊 🏵 🌐 🍇 🍈 🍏 🍎 🍐 🍊 🍋 🍌 🍉 \
           🍓 🫐 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶 🫑 🌽 🥕 \
           🫒 🧄 🧅 🥔 🍠 🥐 🥯 🍞 🥖 🥨 🧀 🥚 🍳 🥞 🧇 🥓 🥩 🍗 \
           🍖 🌭 🍔 🍟 🍕 🥪 🥙 🧆 🌮 🌯 🥗 🥘 🫕 🍝 🍜 🍲 🍛 🍣 \
           🍱 🥟 🦪 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 \
           🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 ⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 \
           🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🥅 ⛳ 🪁 🏹 🎣 🤿 🥊 🥋 \
           🎽 🛹 🛼 🛷 ⛸ 🥌 🎿 ⛷ 🏂 🏆 🥇 🥈 🥉 🏅 🎖 🎪 🤹 🎭 \
           🩰 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🪕 🎻 🎲 🎯 🎳 🎮 🚗 \
           🚕 🚙 🚌 🚎 🏎 🚓 🚑 🚒 🚐 🚚 🚛 🚜 🛴 🚲 🛵 🏍 🛺 🚨 \
           🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 \
           🚉 ✈️ 🛫 🛬 🛩 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥 🛳 ⛴ 🚢 ⚓ ⛽ 🚦 \
           🚥 🗺 🗿 🗽 🗼 🏰 🏯 🎡 🎢 🎠 ⛲ 🏖 🏝 🏜 🌋 ⛰ 🏔 💎 \
           🔮 🧿 🪬 🔭 🔬 🕹 💡 🔦 🏮 📿 🧸 🎈 🎏 🎐 🎀 🎁 🪄 🪅 \
           🧵 🧶 🪡 👑 🎩 🧢 ⛑ 📯 🔔 💰 ⚗️ 🧪 🧫 🧬 🔑 🗝 🛎 🧭 \
           ⏰ ⏳ ⌛ 🧨 🪔 🛒 🎊 🎉 🎃 👾 🤖 🐲 🧩 🪗 🪘 🪙 🧲 🪚 \
           🪛 🔧 🔨 ⚙️ 🧰 🧱 🪜 🧴 🧷 🧹 🧺 🧻 🚽 🪠 🚿 🛁 🪣 🧼 \
           🪥 🧽 🔩 🪝)
  local count=${#p[@]}
  printf '%s' "${p[$(( n % count ))]}"
}

# --- Exact-color swatch image (photo mode), cached on disk -------------------
ensure_swatch() {
  local hex="$1" name="$2" out="$3" glyph="$4"
  [ -f "$out" ] && return 0
  local r g b lum txt dr dg db dark
  r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
  lum=$(( (299*r + 587*g + 114*b) / 1000 ))   # perceived brightness
  txt="white"; [ "$lum" -gt 150 ] && txt="black"
  # Right third is a slightly darker shade of the color, to set off the status.
  dr=$((r*72/100)); dg=$((g*72/100)); db=$((b*72/100))
  dark=$(printf '%02X%02X%02X' "$dr" "$dg" "$db")
  # Layout (660x220): left 2/3 = color + machine name; right 1/3 = status glyph.
  # No hex printed — the color itself is the signal.
  if command -v magick >/dev/null 2>&1; then
    magick -size 660x220 xc:"#$hex" -fill "#$dark" -draw "rectangle 440,0 660,220" \
      -gravity center -fill "$txt" \
      -pointsize 44 -annotate -110+0 "$name" \
      -pointsize 140 -annotate +218+0 "$glyph" "$out" 2>/dev/null && return 0
  fi
  if command -v convert >/dev/null 2>&1; then
    convert -size 660x220 xc:"#$hex" -fill "#$dark" -draw "rectangle 440,0 660,220" \
      -gravity center -fill "$txt" \
      -pointsize 44 -annotate -110+0 "$name" \
      -pointsize 140 -annotate +218+0 "$glyph" "$out" 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$hex" "$name" "$out" "$txt" "$glyph" <<'PY' 2>/dev/null && return 0
import sys
from PIL import Image, ImageDraw, ImageFont
hx, name, out, txt, glyph = sys.argv[1:6]
img = Image.new("RGB", (660, 220), "#"+hx)
d = ImageDraw.Draw(img)
base = img.getpixel((0, 0))
d.rectangle([440, 0, 660, 220], fill=tuple(int(c*0.72) for c in base))
def font(sz):
    for p in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/System/Library/Fonts/SFNS.ttf"):
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()
def centered(text, sz, cx):
    f = font(sz); bb = d.textbbox((0, 0), text, font=f)
    d.text((cx-(bb[2]-bb[0])/2, 110-(bb[3]-bb[1])/2-bb[1]), text, fill=txt, font=f)
centered(name, 44, 220)     # left 2/3
centered(glyph, 140, 550)   # right 1/3
img.save(out)
PY
  fi
  return 1
}

if [ -n "$MACHINE_EMOJI" ]; then
  EMOJI="$MACHINE_EMOJI"
elif [ -n "$HEXCLEAN" ]; then
  EMOJI="$(pick_emoji "$HEXCLEAN")"
else
  EMOJI="⬜"
fi

CONTEXT_PATH=$(echo "$PWD" | rev | cut -d"/" -f1-2 | rev)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

INPUT=$(cat)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Notification"')
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "idle_prompt"')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
SESSION_MSG=$(echo "$INPUT" | jq -r '.message // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
LAST_ASSISTANT=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' | tr '\n' ' ')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

# A Stop hook that already triggered a continuation re-fires with this set — we
# never block, but exit cleanly if we ever see it (docs-recommended hygiene).
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Suppress mid-task "done" pings from the orchestrator. When the main agent runs
# background SUBAGENTS, each one finishing wakes the main agent for a short
# narration turn, and every such turn ends with its own Stop event. We only want
# the FINAL stop. So on a Stop, if a background *subagent* is still running, stay
# quiet. We deliberately scope this to type=="subagent" ONLY — long-running
# processes Claude launched (e.g. `mix phx.server`, a dev server, a watcher) are a
# different background-task type and must NOT silence notifications; otherwise
# you'd hear nothing the whole time your server is up. (Set
# NOTIFY_IGNORE_RUNNING_SUBAGENTS=0 to notify on every stop regardless.)
if [ "$HOOK_EVENT" = "Stop" ] && [ "${NOTIFY_IGNORE_RUNNING_SUBAGENTS:-1}" = "1" ]; then
  RUNNING_SUB=$(echo "$INPUT" | jq -r '[.background_tasks[]? | select(.type=="subagent" and .status=="running")] | length' 2>/dev/null || echo 0)
  [ "${RUNNING_SUB:-0}" -gt 0 ] && exit 0
fi

SESSION_SLUG=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9' '_')

# --- Trailing coalesce for Stop events --------------------------------------
# The background_tasks snapshot doesn't always list every running subagent, so a
# burst of narration Stops can still leak through. To collapse them reliably: on
# a Stop, stamp a per-session marker with a unique token and schedule a DETACHED
# delayed re-run of ourselves. If a newer Stop lands first, it overwrites the
# marker, so this delayed run finds a mismatch and stays silent — only the LAST
# Stop in a burst actually sends. Cost: a small delay on "done" pings. Disable
# with NOTIFY_COALESCE_SECONDS=0. The re-run sets COALESCE_BYPASS=1 to send now.
COALESCE="${NOTIFY_COALESCE_SECONDS:-8}"
if [ "$HOOK_EVENT" = "Stop" ] && [ "${COALESCE_BYPASS:-0}" != "1" ] && [ "$COALESCE" -gt 0 ] 2>/dev/null; then
  CMARK="${TMPDIR:-/tmp}/telegram-notify-${SESSION_SLUG}.coalesce"
  TOKEN="$$-$(date +%s 2>/dev/null || echo 0)-${RANDOM}"
  printf '%s' "$TOKEN" > "$CMARK"
  PAYLOAD_FILE=$(mktemp "${TMPDIR:-/tmp}/telegram-notify-payload.XXXXXX")
  printf '%s' "$INPUT" > "$PAYLOAD_FILE"
  SELF="$0"
  ( trap '' HUP INT TERM
    sleep "$COALESCE"
    if [ "$(cat "$CMARK" 2>/dev/null)" = "$TOKEN" ]; then
      COALESCE_BYPASS=1 bash "$SELF" < "$PAYLOAD_FILE" >/dev/null 2>&1
    fi
    rm -f "$PAYLOAD_FILE"
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  exit 0
fi

# Debounce: collapse near-simultaneous NON-Stop events (e.g. permission + idle)
# into one, per session. Stop events use the trailing coalesce above instead.
# Off with NOTIFY_DEBOUNCE_SECONDS=0.
DEBOUNCE="${NOTIFY_DEBOUNCE_SECONDS:-6}"
if [ "$HOOK_EVENT" != "Stop" ] && [ "$DEBOUNCE" -gt 0 ] 2>/dev/null; then
  MARKER="${TMPDIR:-/tmp}/telegram-notify-${SESSION_SLUG}.ts"
  NOW=$(date +%s 2>/dev/null || echo 0)
  LAST=0; [ -f "$MARKER" ] && LAST=$(cat "$MARKER" 2>/dev/null || echo 0)
  if [ "$NOW" -gt 0 ] && [ $((NOW - LAST)) -lt "$DEBOUNCE" ]; then exit 0; fi
  [ "$NOW" -gt 0 ] && printf '%s' "$NOW" > "$MARKER"
fi

LAST_MSG=""
if [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_MSG=$(jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""' "$TRANSCRIPT_PATH" 2>/dev/null | tr '\n' ' ')
fi

# HEADER = message text; STATUS/GLYPH = the status shown on the photo swatch.
if [ "$HOOK_EVENT" = "Stop" ]; then
  HEADER="✅ done"; STATUS="done"; GLYPH="√"
  PROMPT_LINE="${LAST_ASSISTANT:-${LAST_MSG:-Task complete}}"
elif [ "$NOTIFICATION_TYPE" = "permission_prompt" ]; then
  HEADER="🔐 needs permission"; STATUS="answer"; GLYPH="?"
  PROMPT_LINE="${SESSION_MSG:-Waiting for tool approval}"
else
  HEADER="⏳ waiting for you"; STATUS="idle"; GLYPH="…"
  PROMPT_LINE="${SESSION_MSG:-${LAST_MSG:-Idle and waiting for input}}"
fi

# Apply the message-length cap (ours, not Telegram's).
PROMPT_LINE="$(trunc "$PROMPT_LINE" "$MAX_MSG_CHARS")"
LAST_MSG="$(trunc "$LAST_MSG" "$MAX_MSG_CHARS")"

# --- MarkdownV2 escaping ----------------------------------------------------
esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/[][_*()~`>#+=|{}.!-]/\\&/g'
}
# Inside a MarkdownV2 link URL, ')' and '\' must be escaped.
esc_url() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/)/\\)/g'
}

# "Open in Claude Code" link. The claude.ai/code URL uses the cloud session id
# (bridgeSessionId), which Claude Code records in ~/.claude/sessions/<pid>.json
# alongside the local sessionId (present when remote control is enabled). We map
# the hook's session_id -> bridgeSessionId and build the URL. Omitted if there's
# no bridge id for this session. Disable with NOTIFY_SHOW_SESSION_LINK=0.
SESSION_LINK_LINE=""
if [ "${NOTIFY_SHOW_SESSION_LINK:-1}" = "1" ] && [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "default" ]; then
  _sessdir="$HOME/.claude/sessions"
  BRIDGE=""
  if ls "$_sessdir"/*.json >/dev/null 2>&1; then
    BRIDGE=$(jq -rs --arg sid "$SESSION_ID" '[.[] | select(.sessionId==$sid and .bridgeSessionId)] | sort_by(.updatedAt // 0) | last | .bridgeSessionId // empty' "$_sessdir"/*.json 2>/dev/null)
  fi
  if [ -n "$BRIDGE" ]; then
    # Show the raw URL as the clickable text. It's wrapped as [url](url) so the
    # '_' and '.' inside it don't trip MarkdownV2 while still rendering the URL.
    _sess_url="https://claude.ai/code/${BRIDGE}"
    SESSION_LINK_LINE=$'\n'"🔗 [$(esc "$_sess_url")]($(esc_url "$_sess_url"))"
  else
    # No cloud session id — the session isn't remote-control/claude.ai connected,
    # so there's no shareable link. Say so instead of silently dropping the line.
    SESSION_LINK_LINE=$'\n'"🔗 $(esc "no link — remote control not enabled for this session")"
  fi
fi

E_NAME=$(esc "$MACHINE_NAME")
E_ICON=$(esc "$MACHINE_ICON")
E_HEADER=$(esc "$HEADER")
E_PATH=$(esc "$CONTEXT_PATH")
E_BRANCH=$(esc "$GIT_BRANCH")
E_PROMPT=$(esc "$PROMPT_LINE")
E_LAST=$(esc "$LAST_MSG")

ICON_SEG=""
[ -n "$MACHINE_ICON" ] && ICON_SEG="${E_ICON} "
# The color square is only useful in text mode; in photo mode the swatch image
# already conveys the color, so we drop it. Color name / hex are never shown.
SQUARE_SEG=""
[ "$NOTIFY_MODE" != "photo" ] && SQUARE_SEG="${EMOJI} "

FP_LINE=""
if [ "$WORK_FINGERPRINT" = "1" ]; then
  WE=$(work_emoji "${PWD}|${GIT_BRANCH}")
  reps="$WORK_EMOJI_REPEAT"; case "$reps" in ''|*[!0-9]*) reps=9;; esac
  fp=""; i=0; while [ "$i" -lt "$reps" ]; do fp="${fp}${WE}"; i=$((i+1)); done
  FP_LINE="${fp}"$'\n'
fi

TEXT="${FP_LINE}${SQUARE_SEG}${ICON_SEG}*${E_NAME}* — ${E_HEADER}
📁 ${E_PATH}${SESSION_LINK_LINE}"
[ -n "$GIT_BRANCH" ] && TEXT="${TEXT}
🌿 ${E_BRANCH}"
TEXT="${TEXT}
❓ ${E_PROMPT}"
if [ -n "$LAST_MSG" ] && [ "$PROMPT_LINE" != "$LAST_MSG" ]; then
  TEXT="${TEXT}
💬 ${E_LAST}"
fi

# --- Send -------------------------------------------------------------------
send_text() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" -d parse_mode="MarkdownV2" \
    -d disable_web_page_preview=true --data-urlencode text="$TEXT" > /dev/null
}

SENT=0
if [ "$NOTIFY_MODE" = "photo" ] && [ -n "$HEXCLEAN" ]; then
  NAMESLUG=$(printf '%s' "$MACHINE_NAME" | tr -c 'A-Za-z0-9' '_')
  # Cache key includes the status so each state (done/answer/idle) has its own
  # swatch; the scheme suffix bumps the cache when the drawing changes.
  SWATCH="${SWATCH_FILE:-$HOME/.claude/scripts/swatch-${HEXCLEAN}-${NAMESLUG}-${STATUS}.png}"
  if ensure_swatch "$HEXCLEAN" "$MACHINE_NAME" "$SWATCH" "$GLYPH"; then
    RESP=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendPhoto" \
      -F chat_id="$CHAT_ID" -F parse_mode="MarkdownV2" \
      -F photo=@"$SWATCH" --form-string caption="$TEXT")
    printf '%s' "$RESP" | grep -q '"ok":true' && SENT=1
  fi
fi
[ "$SENT" -ne 1 ] && send_text   # text mode, or photo unavailable/failed -> fall back

exit 0
