# cmd: product principles

## What is cmd?

cmd is a Mac menu bar app. It is the one place to control your machine and your project work. It replaces the standalone baa app.

It does four things:

1. **Projects.** It lists every project in a projects folder (`~/Projects` here). One click opens that project in a coding-agent session (omp here).
2. **To-do.** It keeps a local list of to-dos, either global or tied to a project.
3. **References.** It saves pasted URLs for later, either global or tied to a project. Agents working in a project can read them as context.
4. **Mac health.** It shows free RAM in the menu bar, finds leftover processes and dev junk on disk, and frees them in one click. This part is ported from baa.

## Who is it for?

One person first: its author, on an 8GB MacBook. Every decision is made for that one person. It's also shareable: a first-run picker covers the parts that differ between people (projects folder, coding agent, terminal), and nothing else becomes a setting. There are no accounts and no sync.

## What should using it feel like?

- **Calm.** Opening the panel should feel like a deep breath, not a dashboard. It uses quiet colour, lots of space and few words.
- **Fast.** Any common action takes one click or one keystroke: open a project, add a to-do, save a URL.
- **Personal.** Small flourishes give it character, such as soft Japanese gradients, mono labels and a mood that shifts with the machine's health. Personality never gets in the way of a task.

## Rules every design decision must follow

1. **Fewer things on screen.** If it isn't obvious what something does, it doesn't belong in the panel.
2. **Presets over typing.** Pick from a list instead of typing a path. Use smart defaults instead of options.
3. **No surprises.** cmd never deletes, kills or commits anything by itself. Freeing RAM and cleaning disk always need a click. That rule is inherited from baa.
4. **Plain files, owned by you.** To-dos and references live in Markdown files that a person or an agent can read and edit without cmd.
5. **Agents are first-class readers.** Anything saved to a project should be visible to the next omp session in that project.
6. **Light on the machine.** On an 8GB Mac, cmd must stay small. It is native Swift, polls little and has no web runtime.

## What is out of scope for now?

- Tidying `~/Projects`. That is a separate task for later.
- The AI "which folders are safe to delete?" feature from baa, which calls Claude and may cost money.
- A terminal command (`cmd free all` and so on).
- Sync to the work machine or to GitHub. To-do and reference files stay local and are git-ignored.
