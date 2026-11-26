# cmd: technical constraints

This file covers how cmd is built and where its data lives. What the user sees lives in `ux-flows.md`.

## What is it built with?

cmd is a native SwiftUI menu bar app (`MenuBarExtra` with `.menuBarExtraStyle(.window)`), the same approach baa uses.

- It builds with `swiftc` from the Xcode Command Line Tools (Swift 6.4 on this machine). Full Xcode is not needed.
- It targets macOS 15 or later, on arm64. macOS 15 is the first version with `MeshGradient`, which draws the flowing header. This machine runs macOS 27.
- It has no third-party dependencies. Fonts (SF Pro, SF Mono) and sounds come from the system or the repo.
- **No `@State`.** In the macOS 27 SDK, `@State` is a macro whose plugin only ships with full Xcode, so it won't compile with the Command Line Tools. View state lives in `ObservableObject`s held with `@StateObject` (see `PanelState` in `Sources/UI/Panel.swift`). `@StateObject`, `@ObservedObject`, `@Binding`, `@FocusState` and `@Environment` all work.
- **The panel hides silently.** The `MenuBarExtra` window posts an occlusion change when it opens, but nothing (no occlusion change, no resign-key) when it hides. While it's showing, `WindowEvents` checks every half second whether the window is still on screen, so the header animation stops when the panel closes. Measured: about 9% of one core while open, 0% when closed.
- `LSUIElement` is set, so cmd has no Dock icon.
- The bundle id is `xyz.mackiec.cmd`. The app installs to `~/Applications/cmd.app`.
- A LaunchAgent (`~/Library/LaunchAgents/xyz.mackiec.cmd.plist`) starts it at login.

**Why native Swift?** The machine has 8GB of RAM. A web runtime (Electron, or Tauri's webview) would cost far more memory than a SwiftUI panel. baa's process-scanning code is also Swift already, so it can be reused as it is.

## How is the code laid out?

baa is one 1,948-line file. cmd splits its code by area so each part can change without touching the others. `swiftc` compiles every file in `Sources/` together, so there is still no Xcode project.

```
Sources/
  App.swift            entry point, AppModel (projects, to-dos, refs, drag and drop), menu bar label
  Projects.swift       finding projects, last-session lookup, launching iTerm2
  Notes.swift          reading and writing to-do and reference files, project setup
  Links.swift          link parsing, page-title fetch, @project tokens
  Settings.swift       Env (real or demo), Agent, TerminalApp, Prefs (saved settings)
  Health/              ported from baa: Mem, Procs, Engine, Disk, Health (+ Limits, Notifier), Monitor
  UI/                  Panel (tabs, footer, window tracking), one file per tab, SetupView (first run and settings),
                       Sun (menu bar mark), Components, Aura, Theme
build.sh               build, sign ad hoc, install, restart (adapted from baa)
install.sh             first-time install plus LaunchAgent
tools/shot.sh          capture the panel (optionally each tab) for UI checks
tools/readme-shots.sh  rebuild docs/screenshots/ from made-up data (demo mode)
```

## How do I check a change?

1. `./build.sh` builds, installs and restarts cmd.
2. `tools/shot.sh /tmp/cmd.png 1 2 3 4` opens the panel and captures each tab to `/tmp/cmd-N.png`, then closes it. It only captures cmd's own window. Its keystrokes go straight to cmd's process, so they can't land in another app. It needs Accessibility permission for the terminal.
3. `CMD_FAST=1` (run `~/Applications/cmd.app/Contents/MacOS/cmd` by hand, with the login service stopped) turns every "N minutes" leftover threshold into N seconds, so a test leftover shows up in under a minute.

## Where do projects come from?

- A project is any non-hidden folder directly inside the projects folder chosen on first run (default `~/Projects`).
- **Last session.** The newest file's modification time in the chosen agent's session folder for the project:
  - omp: `~/.omp/agent/sessions/<path relative to ~, "/" as "-">/`, so `~/Projects/my-app` becomes `-Projects-my-app`. Projects outside the home folder get no lookup.
  - Claude Code: `~/.claude/projects/<full path, anything but letters and digits as "-">/`, so `/Users/me/x` becomes `-Users-me-x`. [INFERENCE] The rule for characters other than `/` was inferred from one folder on this Mac.
  - Codex and "Just a shell": none. Codex files sessions by date, not by folder.
- **Sort order.** Pinned projects first (in pin order), then by last session, falling back to the folder's modification time.

## How does opening a project work?

cmd sends AppleScript to the chosen terminal, passing the shell line as an argument, so it never needs AppleScript escaping:

- **iTerm2:** a new tab (or a window, if none is open).
- **Terminal:** a new window. When Terminal wasn't running, cmd reuses the window it opens on launch.

The shell line is `cd '<project path>'`, followed by `&& <agent>` and the agent's continue flag (`-c` for omp and Claude Code) when the project has a session to continue.

- The path is single-quoted, with any embedded `'` escaped.
- The first launch triggers macOS's Automation permission prompt ("cmd wants to control Terminal/iTerm"). `Info.plist` needs `NSAppleEventsUsageDescription`.
- cmd only passes `-c` when a session folder exists. That avoids relying on how an agent behaves when there is nothing to continue.
- The agent picker marks agents it can't find as "not found". It checks the usual install folders (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and a few others), because a menu bar app doesn't get your shell's `PATH`. The terminal still runs the command through your login shell.

## Where are settings kept?

In macOS defaults, domain `xyz.mackiec.cmd`, through `Prefs` in `Sources/Settings.swift`:

- `projectsRoot`, `agent`, `terminal` and `setupDone` come from the first-run picker.
- `agentsPointer` turns the `AGENTS.md` line on or off.
- `pinned` holds the pinned project paths, in pin order.
- Other keys hold the last tab, chip choices, warning levels and mute.

## What is demo mode?

`CMD_DEMO=1` with `CMD_HOME=<folder>` runs the app against a fake home folder. It uses a separate defaults domain (`xyz.mackiec.cmd.demo`) and its own instance lock, so it never touches real settings. The Mac tab shows invented numbers (`Sources/Health/Demo.swift`), and Free/Clear refuse to act. `tools/readme-shots.sh` uses it to rebuild `docs/screenshots/` with made-up data.

## Where do to-dos and references live?

They are stored as plain Markdown, one pair of files per scope.

| Scope | To-dos | References |
|---|---|---|
| Inbox (global) | `~/.cmd/todo.md` | `~/.cmd/refs.md` |
| A project | `<project>/.cmd/todo.md` | `<project>/.cmd/refs.md` |

### What is the file format?

```markdown
# To-do
- [ ] Fix the gallery lightbox · 2026-11-26
- [x] Swap hero image · 2026-11-20 → 2026-11-24
```

```markdown
# References
- [Japanese Gradients for UI — Nuevo.Tokyo](https://www.nuevo.tokyo/japanese-gradients-for-ui) · 2026-11-26
  palette reference for cmd
```

- The parser accepts lines without dates (`- [ ] thing`), so agents and people can add items by hand.
- Square brackets in a page title become parentheses, so the Markdown link stays valid: `[For UI]` → `(For UI)`.
- If an agent edits the file while cmd shows it, cmd finds the item again by its text (to-dos) or link (references) before changing it, so it never edits the wrong line.
- Lines cmd does not recognise are kept exactly as they are when it rewrites the file.
- cmd re-reads the files every time the panel opens, so items an agent added appear the next time the panel is opened. Reading a handful of small files costs almost nothing, and it avoids a file-watching subsystem.

### What happens the first time a project gets an item?

cmd does two things in that repo:

1. **Keeps `.cmd/` out of git.** It adds `.cmd/` to `.git/info/exclude`, git's local-only ignore list. That keeps the files out of git without adding a `.gitignore` change that would then need committing. Folders that aren't git repos skip this step.
2. **Points agents at the files.** It appends this line to the repo's AGENTS.md. If the repo has no AGENTS.md, it creates one containing just this line. The "Notes for agents" switch in settings turns this step off.

   > Open to-dos and saved references for this project live in `.cmd/todo.md` and `.cmd/refs.md` (local only, not in git). Read them at the start of a session; add to them when asked.

   That *is* a tracked change, and you commit it when you choose.

### How are page titles fetched?

cmd sends a plain `URLSession` GET with a 10-second timeout and reads the `<title>` tag. That is free and needs no API. If the fetch fails, the reference keeps the domain as its title.

## What gets ported from baa?

baa is MIT-licensed (© 2026 Selvi Arora). cmd keeps that copyright and licence notice in a `NOTICE` file and in the header of each ported file.

| Keep | Drop or change |
|---|---|
| `Mem`, `Proc`, process reading, `Engine` (leftover detection) | `AI` (the "ask Claude" feature) and "find more space" |
| `Finding`, `Fix`, `apply` (freeing) | `CLI` (the terminal command) |
| `Disk` (dev junk) | the "old installers in Downloads" check (Downloads is off-limits) |
| `Health`, `Limits` (warning levels), `Notifier` | sheep, wool and burst views; `baa.wav` (now the system "Glass" chime) |
| "Using the most" app breakdown and per-app detail | baa's styling (replaced by cmd's theme) |

Additions on top of baa:

- **omp is an agent.** It is labelled like Claude Code and Codex. Dev servers it leaves running are flagged ("started by omp (project)"), and idle omp sessions suggest `omp -c` to pick back up.
- **The node_modules search skips every privacy-protected folder** (Desktop, Documents, Downloads, Pictures, Music, Movies). Walking into Desktop made macOS ask "cmd.app would like to access files in your Desktop folder", and the disk scan sat waiting on that prompt.

The scan cadence stays as it is in baa. Its "never kill anything on its own" rule stays too. The `top` call that splits RAM by user (about 1s of system time) only runs when the Mac tab is shown.

## What if I used baa before?

cmd replaces baa, so running both gives you two RAM monitors. To stop baa, run `launchctl bootout gui/$(id -u)/com.selvi.baa`, then remove `~/Applications/Baa.app`, `~/Library/LaunchAgents/com.selvi.baa.plist` and `~/.local/bin/baa` (or move them aside if you might want baa back). Rebuilding baa from source no longer works with the macOS 27 Command Line Tools, because it uses `@State` (see above).

## What are the known risks?

- **AppleScript to iTerm2** can break if iTerm changes its scripting dictionary. It is a small, well-used API, and it is the only way to open a tab with a command.
- **The omp session folder layout** is omp's internal detail, not a public contract. If it changes, "last session" shows nothing and clicks start a new session. Nothing breaks badly.
- **Unsigned app.** It is signed ad hoc, the same as baa. macOS may ask about Automation and notifications again after rebuilds.
