#!/usr/bin/env bash
# =============================================================================
# detect-bg-color.sh — best-effort detection of this machine's desktop
# background color, for use as MACHINE_HEX / MACHINE_COLOR.
#
# NOTE FOR AI ASSISTANTS: read-only. This script only inspects the current
# wallpaper (an image file's average color, or the solid-color name macOS stores
# in its wallpaper plist). It makes no network calls and changes nothing.
#
# Behavior (macOS):
#   * Image wallpaper -> prints the exact average color as a hex.
#   * Solid color     -> macOS stores only a *name* (e.g. "dustyRose"), not RGB,
#                        so we print the name; the hex must be confirmed by hand.
#
# Output: eval-able KEY=VALUE lines on stdout (only for what was detected):
#   DETECTED_HEX="#RRGGBB"
#   DETECTED_COLOR="dusty rose"
# Human-readable notes go to stderr. Exit 0 if anything was detected, else 1.
#
# Usage:
#   ./detect-bg-color.sh                # inspect the live desktop
#   ./detect-bg-color.sh /path/img.jpg  # average a specific image (for testing)
# =============================================================================
set -eu

note() { printf '%s\n' "$*" >&2; }

# --- Average an image file down to a single pixel, print "#RRGGBB" -----------
avg_hex() {
  local img="$1" hex=""
  if command -v magick >/dev/null 2>&1; then
    hex="$(magick "$img" -resize 1x1\! -depth 8 txt: 2>/dev/null \
           | grep -oE '#[0-9A-Fa-f]{6}' | head -1)"
  elif command -v convert >/dev/null 2>&1; then
    hex="$(convert "$img" -resize 1x1\! -depth 8 txt: 2>/dev/null \
           | grep -oE '#[0-9A-Fa-f]{6}' | head -1)"
  elif command -v python3 >/dev/null 2>&1; then
    hex="$(python3 - "$img" <<'PY' 2>/dev/null
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB").resize((1, 1))
print("#%02X%02X%02X" % im.getpixel((0, 0)))
PY
)"
  fi
  printf '%s' "$hex"
}

# --- camelCase system-color name -> spaced lowercase ("dustyRose" -> "dusty rose")
humanize() {
  printf '%s' "$1" | sed -E 's/([a-z0-9])([A-Z])/\1 \2/g' | tr '[:upper:]' '[:lower:]'
}

# --- Read the solid-color name from the macOS wallpaper store ----------------
solid_color_name() {
  local plist="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
  [ -f "$plist" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$plist" <<'PY' 2>/dev/null
import plistlib, sys
try:
    with open(sys.argv[1], "rb") as f:
        d = plistlib.load(f)
    # Prefer the per-display desktop; fall back to the system default.
    for root in ("AllSpacesAndDisplays", "SystemDefault"):
        try:
            choice = d[root]["Desktop"]["Content"]["Choices"][0]
        except Exception:
            continue
        if choice.get("Provider", "").endswith("choice.color"):
            inner = plistlib.loads(choice["Configuration"])
            names = list(inner.get("systemColor", {}).keys())
            if names:
                print(names[0]); break
except Exception:
    pass
PY
}

# =============================================================================
# Main
# =============================================================================
if [ "$(uname)" != "Darwin" ]; then
  note "Background detection currently supports macOS only."
  exit 1
fi

# Allow an explicit image path (handy for testing).
IMG="${1:-}"
if [ -z "$IMG" ]; then
  IMG="$(osascript -e 'tell application "System Events" to get picture of current desktop' 2>/dev/null || true)"
fi

# Case 1: an image wallpaper -> exact average color.
if [ -n "$IMG" ] && [ -f "$IMG" ]; then
  HEX="$(avg_hex "$IMG")"
  if [ -n "$HEX" ]; then
    note "Detected image wallpaper — average color $HEX"
    printf 'DETECTED_HEX="%s"\n' "$HEX"
    exit 0
  fi
  note "Found wallpaper image but couldn't average it (need ImageMagick or Pillow)."
fi

# Case 2: a solid color -> macOS stores only the name, not RGB.
NAME="$(solid_color_name || true)"
if [ -n "$NAME" ]; then
  HUMAN="$(humanize "$NAME")"
  note "Detected solid-color desktop: \"$HUMAN\" (macOS stores no hex for this —"
  note "confirm or paste the hex to match it exactly)."
  printf 'DETECTED_COLOR="%s"\n' "$HUMAN"
  exit 0
fi

note "Couldn't detect a desktop background color."
exit 1
