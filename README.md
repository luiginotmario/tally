# Tally

A Stream Deck that shows your coding agents. One key per session, lit up the moment an agent
wants you, so nothing sits finished for twenty minutes while you're busy somewhere else.

| Key | Means |
| --- | --- |
| dark, ○ | open, nothing happening |
| dark, ● | working |
| warm white | done — your move |
| red | waiting on a permission or a question |
| flashing | it's been wanting you for 5 minutes |

**Press** a key to jump to that session (the exact terminal tab or editor window).
**Hold** a key to forget a session that died without saying so.

No Elgato app, no account, no server. Tally is one small menu bar app (about 11 MB, 0% CPU when
idle) that talks to the deck over USB and hears from agents through a local socket.

## Install

```bash
scripts/install.sh
```

Then **menu bar → Connect Agents…** (or `tally connect`). That adds a hook to every agent
installed on the Mac: Claude Code, Codex, Cursor, Grok and Gemini. Quit Elgato's Stream Deck app
first, since only one app can drive the deck at a time.

- **Codex** asks you to trust new hooks: run `/hooks` once. Until then its `notify` command still
  lights the key when a turn finishes.
- **Any other agent** that can run a shell command: add this to its instructions (`AGENTS.md` or
  similar): *"When you finish a turn, run `tally done`. When you need my input, run
  `tally waiting`."* Without real hooks it can't report being stuck on a permission prompt.

## How it works

```
agent hook ─▶ tally hook <agent> ─▶ ~/Library/Application Support/Tally/inbox.sock ─▶ Tally.app ─▶ USB ─▶ keys
                (reads the hook's JSON,                                                 │
                 notes the terminal tab                                    key press ◀──┘──▶ focus that window
                 or editor it came from)
```

- `Sources/TallyKit`: the logic, all tested. `Hook` reads every agent's payload, `Board` decides
  which key shows which session, `KeyFace` draws a key, `DeckModel` speaks each deck's USB
  protocol, `Connector` writes the hook configs.
- `Sources/Tally`: the app. `Deck` (IOKit HID), `Desk` (paints keys, handles presses, timers),
  `Inbox` (the socket), `Focus+Window` (finding and raising the session's window), `Command` (the CLI).

Decks: Stream Deck (MK.2, v2, scissor keys), Mini, XL, Neo, + and + XL.

```bash
swift test                 # the logic
tally preview ./faces      # every key state as PNGs
```
