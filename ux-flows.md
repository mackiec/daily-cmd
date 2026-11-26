# cmd: UX flows

This file describes what you see and do. How it is built lives in `technical-constraints.md`.

## What lives in the menu bar?

The menu bar shows a sun rising over a horizon, then free RAM: a half disc resting on a thin line, with five rays fanned above it, exactly as tall as the digits. It's wisteria and sakura while the Mac is healthy, amber when RAM is tight or dropping fast, and red when it's critical. Clicking it opens the panel.

## What does the panel look like?

The panel is 360pt wide and the same height on every tab. It has four tabs across the top, and `⌘1`–`⌘4` switch between them. Plain number keys would type into the fields. It always opens on the last tab used, with that tab's field ready to type into.

```
┌──────────────────────────────────────┐
│  ░░ flowing gradient, behind ░░      │
│  PROJECTS [12]  TO-DO [3]  REFS  MAC │
│  [ field ...................... ]    │
│  (tab content)                       │
│                                      │
│                         74% free  ⏻ │
└──────────────────────────────────────┘
```

Tab labels carry counts: projects, open to-dos and saved links. The Mac tab shows the health dot when RAM isn't fine.

The footer always shows free RAM. If RAM is tight and there are leftovers to free, it also shows a one-line nudge such as "1.2 GB of leftovers → Mac", which jumps to the Mac tab. Messages (a saved link that already exists, an iTerm2 permission problem, "Freed 404 MB") show there for 6 seconds. The power icon quits cmd.

## First run and settings

The first time the panel opens, it shows a short welcome instead of the tabs, with three pick-one lists:

1. **Where your projects live:** the code folders that exist in the home folder (`~/Projects`, `~/Developer`, `~/code` and so on), plus "Choose another folder…".
2. **Open projects with:** omp, Claude Code, Codex or Just a shell. Agents cmd can't find are marked "not found". The first one it finds is preselected.
3. **In:** Terminal or iTerm2. iTerm2 is preselected when installed.

Below them, a **Notes for agents** switch (on by default) controls the `AGENTS.md` line. Choices save as they're picked, and **Start**, always in view at the bottom, closes the form. The gear in the footer opens the same form later as **Settings**, with **Done** instead of Start.

## Projects tab

### What does it show?

The tab lists every folder directly inside `~/Projects`, newest activity first. Each row has:

- the project name
- when the last omp session there was ("2d ago"), or nothing if there has never been one
- a small count of open to-dos, shown only if there are any

A filter field at the top takes focus as soon as the tab opens. Typing narrows the list and `Enter` opens the top match.

### What happens when I click a project?

1. cmd opens a new iTerm2 tab in that folder.
2. If the project has an earlier omp session, cmd runs `omp -c` to continue it. Otherwise it runs `omp` to start a new one.
3. The panel closes.

Right-click a row for the other actions: **Pin to top** (or **Unpin**), **Continue last session**, **New session**, **Open in Finder** and **Copy path**.

### How does pinning work?

Pinned projects sit above all the others, in the order you pinned them, each with a small pin after its name. The rest keep their activity order underneath. To-do and Refs groups follow the same order, so pinned projects lead there too. Pins are saved in cmd's settings (the `pinned` key) and survive restarts.

### What happens when I expand a project?

Clicking the chevron at the end of a row shows that project's open to-dos and references inline. You can tick a to-do off from there without leaving the tab.

## To-do tab

### How do I add a to-do?

1. Type into the field at the top and press `Return`.
2. The to-do goes wherever the chip next to the field points: **Inbox** (global) by default, or a project. The chip remembers its last choice.
3. Or add `@name` anywhere in the text to file it under a project, for example `fix the photo grid @garden`. The name can be any part of the project name. A line under the field shows "→ garden-journal" while you type, or "No project matches" if nothing fits. `@inbox` works too.

### How do I work through them?

- Tick the circle to complete a to-do. It moves to a collapsed **Done** group at the bottom, which lists everything ticked in the last 7 days. Untick it there to bring it back. Completed to-dos stay in the file.
- To move a to-do, drag it onto another group, or right-click → **Move to**. Right-click → **Delete** removes it from the file.
- Groups: the Inbox and every project that has open to-dos, in the same order as the Projects tab. An empty Inbox is hidden when other groups have items.

## Refs tab

### How do I save a reference?

1. Paste a link into the field (it has focus as soon as the tab opens) and press `Return`. A bare domain like `nuevo.tokyo/agbr` works.
2. Any words after the link become its note: `nuevo.tokyo/japanese-gradients-for-ui palette for cmd`.
3. The chip and `@name` work the same way as on the To-do tab.
4. cmd fetches the page title in the background. Until it arrives, the row shows the domain.

### How do I use a reference?

- Click it to open it in the browser.
- Right-click for **Open**, **Copy link**, **Add note** or **Edit note**, **Move to** and **Delete**. Drag works for moving too.
- Agents in the project see it through the project's `.cmd/refs.md` (see `technical-constraints.md`).

## Mac tab (ported from baa)

The tab shows the following, top to bottom:

1. **Free RAM.** A large figure, a health line ("room to breathe"), and a 30-minute sparkline with swap use.
2. **Leftovers.** Everything baa would flag: ghosts 👻, things agents left behind 🤖 (Claude Code, Codex and omp), idle hogs 💤 and CPU runaways 🔥. Each one has a "Free 404 MB" button, and a card on top frees all of them. While RAM is fine, they collapse into one "2 leftovers still running" line, so they stay out of the way.
3. **Where the RAM went.** A bar split into apps, squeezed (compressed), macOS, cache and free. When someone else is logged in to this Mac, it also shows how much each person uses.
4. **Using the most.** The top apps by memory. Tap one to see what it runs, for example Chrome's tabs and extensions.
5. **Disk.** Free space, and dev junk (old builds, package caches, stale `node_modules`) with a Trash or Clear button for each.
6. **Sound on / off** and **Warning levels**: baa's steppers (🟡 at 15% free, 🔴 at 8% by default) and the "dropping fast" toggle.

baa's notifications stay: a ping when RAM gets tight (at most every 30 minutes), when it's dropping fast, when a big leftover appears (every 6 hours) and when the disk is almost full. Each one has a one-click Free or Clear button.

cmd never frees or deletes anything by itself. Trashed junk goes to the Trash, so it can be put back.

## Look and feel

Reference: Nuevo.Tokyo and their *Japanese Gradients [For UI]* and *Japanese Colours [For UI]* series.

### Colour

The base is near-white (`#F7F7F6`) with soft greys taken from the traditional Japanese palette. The hex values below come from Nuevo's colour card.

| Role | Colour | Hex |
|---|---|---|
| Surface tint | Shiro Nezu 白鼠 (white grey) | `#DCDDDD` |
| Soft panels | Usukumo Nezu 薄雲鼠 (light grey cloud) | `#D4DCDA` |
| Accent gradient, start | Fuji Nezu 藤鼠 (wisteria grey) | `#A6A5C4` |
| Accent gradient, end | soft sakura pink | `#EDCAD4` |
| Calm health | Yanagi Nezumi 柳鼠 (willow grey) | `#C8D5BB` |
| Small decorative labels | Minato Nezumi 湊鼠 | `#80989B` |
| Secondary text, counts | deeper Minato and Fuji, for legibility (4.5:1 or more on the base) | `#5E7275`, `#5F5B8C` |
| Primary text | Sabi Nezu 錆鼠 (rust grey) | `#47585C` |

cmd is light-only. There is no dark mode.

### Type

- Labels and tab names use SF Mono, uppercase, small and widely spaced: `PROJECTS [11]`. This echoes Nuevo's `JAPANESE GRADIENTS [FOR UI]™` captions.
- Body text uses SF Pro at normal weight. Large numbers use SF Pro at a light weight, never bold.
- Both fonts ship with macOS, so nothing needs to be bundled.

### Flourishes

- **Flowing aura.** A soft mesh gradient sits behind the tab bar. It keeps flowing for as long as the panel is open, slowly morphing into new shapes and colour mixes, and every time the panel opens it starts from a fresh configuration. It is wisteria and pink when the Mac is healthy and warms toward amber as RAM gets tight. It stops animating when the panel closes, so it costs nothing in the background. It replaces baa's sheep as the app's "mood".
- **Freeing feedback.** When something is freed, the aura pulses once. baa's bleat is replaced by a soft chime, and it can be muted.
- **Brackets.** Counts use Nuevo-style brackets, such as `TO-DO [4]`. The footer has no mark or divider: just free RAM and the quit icon.
- **No kanji or katakana.** Labels stay in English.

## Decided against

- A global keyboard shortcut to open the panel. The menu bar click is enough.
- Dark mode.
