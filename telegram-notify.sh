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
#   MACHINE_COLOR   - free-text color name, e.g. "salmon red"  (any color, shown in msg)
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
WORK_EMOJI_REPEAT="${WORK_EMOJI_REPEAT:-13}"

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
  local hex="$1" name="$2" out="$3"
  [ -f "$out" ] && return 0
  local r g b lum txt
  r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
  lum=$(( (299*r + 587*g + 114*b) / 1000 ))   # perceived brightness
  txt="white"; [ "$lum" -gt 150 ] && txt="black"
  if command -v magick >/dev/null 2>&1; then
    magick -size 640x220 xc:"#$hex" -gravity center -fill "$txt" \
      -pointsize 46 -annotate +0-20 "$name" -pointsize 28 -annotate +0+36 "#$hex" "$out" 2>/dev/null && return 0
  fi
  if command -v convert >/dev/null 2>&1; then
    convert -size 640x220 xc:"#$hex" -gravity center -fill "$txt" \
      -pointsize 46 -annotate +0-20 "$name" -pointsize 28 -annotate +0+36 "#$hex" "$out" 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$hex" "$name" "$out" "$txt" <<'PY' 2>/dev/null && return 0
import sys
from PIL import Image, ImageDraw, ImageFont
hx, name, out, txt = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
img = Image.new("RGB", (640, 220), "#"+hx)
d = ImageDraw.Draw(img)
def font(sz):
    for p in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/System/Library/Fonts/SFNS.ttf"):
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()
for text, f, dy in ((name, font(46), -20), ("#"+hx, font(28), 36)):
    bb = d.textbbox((0, 0), text, font=f); w = bb[2]-bb[0]; h = bb[3]-bb[1]
    d.text(((640-w)/2, (220-h)/2+dy), text, fill=txt, font=f)
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

COLOR_DISP="$MACHINE_COLOR"
if [ -n "$MACHINE_HEX" ]; then
  [ -n "$COLOR_DISP" ] && COLOR_DISP="$COLOR_DISP ($MACHINE_HEX)" || COLOR_DISP="$MACHINE_HEX"
fi

CONTEXT_PATH=$(echo "$PWD" | rev | cut -d"/" -f1-2 | rev)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

INPUT=$(cat)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Notification"')
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "idle_prompt"')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
SESSION_MSG=$(echo "$INPUT" | jq -r '.message // ""')

LAST_MSG=""
if [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_MSG=$(jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""' "$TRANSCRIPT_PATH" 2>/dev/null | tr '\n' ' ' | cut -c1-300)
fi

if [ "$HOOK_EVENT" = "Stop" ]; then
  HEADER="✅ finished"
  PROMPT_LINE="${LAST_MSG:-Task complete}"
elif [ "$NOTIFICATION_TYPE" = "permission_prompt" ]; then
  HEADER="🔐 needs permission"
  PROMPT_LINE="${SESSION_MSG:-Waiting for tool approval}"
else
  HEADER="⏳ waiting for you"
  PROMPT_LINE="${SESSION_MSG:-${LAST_MSG:-Idle and waiting for input}}"
fi

# --- MarkdownV2 escaping ----------------------------------------------------
esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/[][_*()~`>#+=|{}.!-]/\\&/g'
}

E_NAME=$(esc "$MACHINE_NAME")
E_ICON=$(esc "$MACHINE_ICON")
E_COLOR=$(esc "$COLOR_DISP")
E_HEADER=$(esc "$HEADER")
E_PATH=$(esc "$CONTEXT_PATH")
E_BRANCH=$(esc "$GIT_BRANCH")
E_PROMPT=$(esc "$PROMPT_LINE")
E_LAST=$(esc "$LAST_MSG")

COLOR_SEG=""
[ -n "$COLOR_DISP" ] && COLOR_SEG=" · ${E_COLOR}"
ICON_SEG=""
[ -n "$MACHINE_ICON" ] && ICON_SEG="${E_ICON} "

FP_LINE=""
if [ "$WORK_FINGERPRINT" = "1" ]; then
  WE=$(work_emoji "${PWD}|${GIT_BRANCH}")
  reps="$WORK_EMOJI_REPEAT"; case "$reps" in ''|*[!0-9]*) reps=13;; esac
  fp=""; i=0; while [ "$i" -lt "$reps" ]; do fp="${fp}${WE}"; i=$((i+1)); done
  FP_LINE="${fp}"$'\n'
fi

TEXT="${FP_LINE}${EMOJI} ${ICON_SEG}*${E_NAME}*${COLOR_SEG} — ${E_HEADER}
📁 ${E_PATH}"
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
    -d chat_id="$CHAT_ID" -d parse_mode="MarkdownV2" --data-urlencode text="$TEXT" > /dev/null
}

SENT=0
if [ "$NOTIFY_MODE" = "photo" ] && [ -n "$HEXCLEAN" ]; then
  NAMESLUG=$(printf '%s' "$MACHINE_NAME" | tr -c 'A-Za-z0-9' '_')
  SWATCH="${SWATCH_FILE:-$HOME/.claude/scripts/swatch-${HEXCLEAN}-${NAMESLUG}.png}"
  if ensure_swatch "$HEXCLEAN" "$MACHINE_NAME" "$SWATCH"; then
    RESP=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendPhoto" \
      -F chat_id="$CHAT_ID" -F parse_mode="MarkdownV2" \
      -F photo=@"$SWATCH" --form-string caption="$TEXT")
    printf '%s' "$RESP" | grep -q '"ok":true' && SENT=1
  fi
fi
[ "$SENT" -ne 1 ] && send_text   # text mode, or photo unavailable/failed -> fall back

exit 0
