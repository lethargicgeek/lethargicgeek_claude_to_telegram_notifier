# Claude → Telegram notifier

A tiny [Claude Code](https://claude.com/claude-code) hook that sends you a Telegram
message **only when Claude is actually waiting on you** — never on every turn. Built
for running Claude across several machines and branches through **one shared Telegram
channel**, where each message is tagged so you can tell *which machine* and *which
piece of work* pinged you.

- **Fires only when you're needed:** 🔐 needs permission / ⏳ waiting for you
  (no per-turn "finished" spam).
- **Per-machine identity:** name, an icon, and a color shown visually (a nearest-hue
  square in text mode, or a pixel-exact color swatch image in photo mode).
- **Per-work fingerprint:** an emoji derived from a hash of folder path + git branch,
  so each branch/worktree gets its own stable banner.
- **One script, many machines:** all machine-specific values live in a small config
  file; the script is identical everywhere.

> One channel, many machines. A message looks like:
>
> ```
> ⚾⚾⚾⚾⚾⚾⚾⚾⚾
> 🖥️ mac-mini-03 — 🔐 needs permission
> 📁 myproject
> 🌿 feature/payments-v2
> ❓ Claude wants to run: git push --force
> ```

## Quick install

**With Claude Code** — clone the repo and just ask:

> "Install this repo on my machine."

Claude runs `install.sh`, which asks for your bot token, auto-detects your chat
id, wires the hooks, and sends a test message. You provide the token and restart
Claude Code — that's it. (See the LLM note at the top of `install.sh`; an
assistant should skim the files first to confirm intent.)

**By hand:**

```bash
git clone https://github.com/lethargicgeek/lethargicgeek_claude_to_telegram_notifier.git
cd lethargicgeek_claude_to_telegram_notifier
bash install.sh          # prompts for token + machine identity, wires hooks, tests
# then restart Claude Code
```

The only secret you supply is your **Telegram bot token** (from @BotFather). The
installer derives the **chat id** for you from the bot, as long as you've sent
the bot a message first. Everything else (manual steps, options, multi-machine)
is documented below.

## Message format

```
🟥 mac-mini-03 · pastel red (#FFB3B3) — 🔐 needs permission
📁 0_clauding/myproject
🌿 main
❓ Claude wants to run: rm -rf build/
💬 <last thing Claude said, for context>
```

The colored square matches that machine's desktop background so you can identify
the source at a glance.

## Color

The color is conveyed **visually, never as text** — the message itself never
prints a color name or hex. `MACHINE_HEX` drives how color is shown:

- **Photo mode** (`NOTIFY_MODE="photo"`) — each notification is a **pixel-exact
  color swatch image** filled with `MACHINE_HEX`, labeled only with the machine
  name (no hex on it). This is the only way Telegram can render an exact color.
- **Text mode** (`NOTIFY_MODE="text"`, default) — the message leads with a small
  colored square, auto-picked as the *nearest hue* of your hex using HSV, from the
  9 Telegram provides (🟥🟧🟨🟩🟦🟪🟫⬛⬜). HSV (not raw RGB) keeps pastels on the
  right family — `#FFB3B3` → 🟥, `#B2F2BB` → 🟩. Set `MACHINE_EMOJI` to force one.

The swatch is **rendered once and cached** at
`~/.claude/scripts/swatch-<HEX>-<machine>-n.png`, then re-sent on every ping, so
there's no per-notification image cost. Change the hex and a new swatch is built
automatically. Photo mode needs **ImageMagick** or **python3 + Pillow**; if
neither is present (or a send fails) it falls back to a text alert.

`MACHINE_COLOR` is now just a human label you can keep in your config for
reference / background detection — it is not shown in messages.

## Auto-detecting the background color (macOS)

`install.sh` runs `detect-bg-color.sh` to pre-fill the color from your desktop
wallpaper:

- **Image wallpaper** → the exact **average color** (a hex) is detected and
  offered as the default; photo mode is preselected.
- **Solid color** → macOS stores only the color's **name** (e.g. `dusty rose`),
  not an RGB value, so the name is auto-filled and you confirm/paste the hex.

You can always override the detected value. Run it standalone anytime:

```bash
./detect-bg-color.sh            # inspect the live desktop
./detect-bg-color.sh img.jpg    # average a specific image
```

(macOS only; it's read-only and makes no network calls.)

## Per-machine icon

Set `MACHINE_ICON` to any emoji/glyph (🖥️ 💻 🚀 🐳 🍎 …) and it leads the header,
so each machine has both a color and an icon:

```
🖥️ mac-mini-03 — 🔐 needs permission
```

Standard Unicode emoji work everywhere and are free. Telegram Premium "custom
emoji" packs (`tg-emoji`) are **not** usable in bot messages, so this is a normal
emoji of your choice, not an animated pack sticker.

## Work fingerprint (per branch/worktree emoji)

With `WORK_FINGERPRINT="1"` (default), each message **leads with an emoji derived
from a hash of `folder-path + git-branch`**, repeated 9× (`WORK_EMOJI_REPEAT`):

```
🦉🦉🦉🦉🦉🦉🦉🦉🦉
🖥️ mac-mini-03 — 🔐 needs permission
📁 myproject
🌿 feature/auth
❓ Claude wants to run: npm run deploy
```

- **Deterministic:** the same folder+branch always maps to the same emoji, so a
  given piece of work keeps its icon across notifications.
- **Unique per context:** a different branch (or a different folder) hashes to a
  different emoji — so once you run several branches at once, each has its own
  glanceable banner. Picked from a curated set of ~472 distinct, deduped emoji
  (SHA-256 of the key, mod palette size), so collisions stay negligible.
- The hash uses the **absolute `$PWD`**, so the same branch checked out in two
  locations gets two emoji (by design — they're different worktrees). Set
  `WORK_FINGERPRINT="0"` to turn the banner off.

## Git branch

Every notification includes a `🌿 <branch>` line automatically **when Claude's
working directory is a git repo** — it runs `git rev-parse --abbrev-ref HEAD` in
that directory. In a non-repo folder there's simply no branch, so the line is
omitted.

## Message length

How much of Claude's message is shown is set by `MAX_MSG_CHARS` (default `1200`)
— this is the notifier's own cap, **not** a Telegram limit. It's auto-clamped to
Telegram's ceilings: up to **3800** chars in text mode and **850** in photo mode
(Telegram allows 4096 for a text message but only 1024 for a photo caption).
Longer messages are truncated with an `…`.

## Reliability

All dynamic text (Claude's message, paths, branch) is **MarkdownV2-escaped**, so
backticks, asterisks, brackets etc. in a message can never break the payload and
silently drop the notification — a failure mode the earlier version had.

---

## Architecture

The script is **identical on every machine**. All machine-specific values
(machine name, color) and the shared secrets live in a separate config file that
the script sources:

- `~/.claude/scripts/telegram-notify.sh` — the notifier (same everywhere)
- `~/.claude/scripts/telegram-notify.conf` — **per-machine** config (name, emoji, color) + shared token/chat id

This means to add a new machine you copy the same script and just drop in a
different `.conf`.

---

## Prerequisites

- [Claude Code](https://claude.com/claude-code) installed.
- `jq` and `curl` on `PATH` (macOS: `brew install jq`; curl ships with macOS).
- Optional, for exact-color photo mode: **ImageMagick** or **python3 + Pillow**.

## Setup

On **each machine**:

**1. Create a Telegram bot and get your chat id (one-time).**
   - Message [@BotFather](https://t.me/BotFather), send `/newbot`, and copy the
     **bot token**.
   - Send your new bot any message, then open
     `https://api.telegram.org/bot<TOKEN>/getUpdates` and copy the `chat.id`.
   - Opening the bot and sending a message is required — a bot can't message you
     until you've started it.

**2. Install the script:**
   ```bash
   mkdir -p ~/.claude/scripts
   cp telegram-notify.sh ~/.claude/scripts/telegram-notify.sh
   chmod +x ~/.claude/scripts/telegram-notify.sh
   ```

**3. Install this machine's config:**
   ```bash
   cp telegram-notify.conf.example ~/.claude/scripts/telegram-notify.conf
   # then edit ~/.claude/scripts/telegram-notify.conf:
   #   MACHINE_NAME  = a short label for this machine
   #   MACHINE_COLOR = the color name (any words)
   #   MACHINE_HEX   = this machine's background hex; glyph auto-picks nearest hue
   #   MACHINE_EMOJI = (optional) force a specific glyph
   ```
   For a full photo-mode example (exact color swatch + fingerprint), start from:
   ```bash
   cp telegram-notify.conf.photo-example ~/.claude/scripts/telegram-notify.conf
   ```

**4. Wire up the hooks** in `~/.claude/settings.json` — merge in the `hooks` block
   from `settings-hooks-snippet.json`. Only "waiting on you" triggers are used:

   ```json
   "hooks": {
     "Notification": [
       { "matcher": "permission_prompt",
         "hooks": [{ "type": "command", "command": "bash ~/.claude/scripts/telegram-notify.sh" }] },
       { "matcher": "idle_prompt",
         "hooks": [{ "type": "command", "command": "bash ~/.claude/scripts/telegram-notify.sh" }] }
     ]
   }
   ```

**5. Restart Claude Code** — hooks load at startup; a running session won't pick
   up changes.

## Test

Simulate each event without waiting for a real one:

```bash
# permission prompt
echo '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude wants to run: git push --force"}' \
  | bash ~/.claude/scripts/telegram-notify.sh

# idle / waiting for input
echo '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Which approach do you want?"}' \
  | bash ~/.claude/scripts/telegram-notify.sh
```

You should receive both in Telegram, tagged with this machine's name + color.

---

## Updating a machine

When the project changes, refresh a machine with **one command** (or just tell
Claude *"update the telegram notifier"*):

```bash
cd <your-checkout>
bash update.sh          # git pull + refresh scripts + re-check hooks
# then restart Claude Code
```

`update.sh` pulls the latest, copies the refreshed `telegram-notify.sh` /
`detect-bg-color.sh` into `~/.claude/scripts/`, and re-ensures the hooks — while
**leaving your `telegram-notify.conf` (token + identity) and swatch cache
untouched.** New config options always have defaults, so old configs keep working.

## Adding another machine later

1. Start your bot from that machine's Telegram account (if it's a different
   account than one that has already started the bot).
2. Copy `telegram-notify.sh` → `~/.claude/scripts/`.
3. Copy `telegram-notify.conf.example` → `~/.claude/scripts/telegram-notify.conf`
   and set that machine's `MACHINE_NAME` / `MACHINE_ICON` / `MACHINE_COLOR` /
   `MACHINE_HEX`. (Keep `TELEGRAM_TOKEN` and `CHAT_ID` the same — that's what makes
   every machine share the one channel.)
4. Add the hooks block, restart Claude Code.

## Security

- Your bot token and chat id live in `~/.claude/scripts/telegram-notify.conf`, which
  is **not** part of this repo. The tracked `*.conf.*` files contain only
  placeholders — **never commit a real token.** Anyone with the token can send
  messages as your bot; rotate it via @BotFather → `/revoke` if it leaks.

## Files

- `install.sh` — one-command installer (prereq check, token/chat-id, hooks, test)
- `update.sh` — pull latest + refresh scripts/hooks (keeps your config)
- `detect-bg-color.sh` — macOS desktop-background color detector (used by install.sh)
- `telegram-notify.sh` — the notifier script (config-driven, identical on all machines)
- `telegram-notify.conf.example` — config template (placeholders)
- `telegram-notify.conf.photo-example` — filled example: photo mode + swatch + fingerprint
- `settings-hooks-snippet.json` — the `hooks` block to merge into `settings.json`
- `LICENSE` — MIT

## License

MIT — see [LICENSE](LICENSE).
