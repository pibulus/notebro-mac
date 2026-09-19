# NoteBro for Mac 📝

> **Your note bro. Always there.**  
> Menu-bar index-card scratchpad with instant focus. Click the icon or hit `⌥Space` anywhere, and the cursor is already blinking.

---

## ⚡️ The TextEdit Killer

Every notes app requires a preamble:
- TextEdit asks you where to save before you write a single word.
- Apple Notes makes you wait for an H1 title.
- Notion wants you to configure a database view.

**NoteBro doesn't do rituals.**
1. Hit `⌥Space` (or click the menu bar bro).
2. The popover drops with your cursor **already blinking** in an index card.
3. Jot your thought down.
4. Hit `Esc` or click away — it's auto-saved to your local disk immediately.

---

## ⌨️ Shortcuts

| Shortcut | Action |
|---|---|
| `⌥Space` | **Toggle NoteBro** from anywhere on macOS |
| `⌘[` or `⌘←` | **Previous Card** |
| `⌘]` or `⌘→` | **Next Card** |
| `⌘N` | **New Card** (pulls a fresh card from the stack) |
| `⌘⌫` | **Discard Card** (when you have >1 card) |
| `⌘⇧C` | **Copy Active Card** |
| `⌘E` | **Export All to Markdown** (saves directly to `~/Desktop/NoteBro-Export.md`) |
| `Esc` | **Close Popover** (auto-saves) |
| `⌘Q` | **Quit NoteBro** |

---

## 🛠️ Build & Install

```bash
# Compile and sign with Developer ID (Hardened Runtime)
./build.sh direct

# Install to /Applications
ditto build/NoteBro.app /Applications/NoteBro.app

# Open the app
open /Applications/NoteBro.app
```

---

## 🔒 Local-First Architecture

- **Zero Cloud Bloat**: Notes live in `~/Library/Application Support/NoteBro/notes.json`.
- **Zero Lock-In**: Export all your cards anytime via `⌘E` as plain Markdown.
- **Pure Native Swift**: Under 2.5MB standalone binary. Zero Electron, zero WebKit overhead, zero idle battery drain.
- **Signed & Notarization-Ready**: Built with Hardened Runtime and signed with Pablo's Apple Developer ID.

---

*Part of the pibulus indie digital cartridge suite.*
