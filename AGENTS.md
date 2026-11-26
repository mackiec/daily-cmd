# cmd

A personal Mac menu bar app with four tabs: projects (open in omp), to-dos, references, and Mac health (ported from baa).

Read these before changing anything:

- `product-principles.md`: what cmd is for, and the rules every decision follows
- `ux-flows.md`: what the user sees and does, plus the look and feel
- `technical-constraints.md`: stack, code layout, data files, and the baa port

Working mode: careful. All four tabs are built (Projects, To-do, Refs, Mac) and baa is retired. Any new feature gets its docs updated first, then is built and checked on screen with `tools/shot.sh` before it is called done.

Build and install with `./build.sh` (`./install.sh` the first time). To check the UI, run `tools/shot.sh [out.png]`: it opens the panel, captures only cmd's window, and closes it again. Never capture the whole screen. To refresh the README screenshots, run `tools/readme-shots.sh`; it uses demo mode, so only made-up data appears. Never put real projects, notes or process names in a committed screenshot.
