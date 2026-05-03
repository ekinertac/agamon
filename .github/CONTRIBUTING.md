# Contributing

## Getting started

```bash
git clone https://github.com/ekinertac/agamon
cd agamon
swift build
swift run
```

Requires macOS 14+ and Xcode command-line tools.

## Project structure

```
Sources/Agamon/
  App/          — entry point, menu bar commands
  Models/       — PaneNode, WorkTab, Project
  State/        — AppState (all shared state and actions)
  Theme/        — Theme constants, TerminalTheme (color schemes)
  Views/
    CommandCenter/  — command palette
    Editor/         — syntax highlighting, markdown renderer
    FilePanel/      — file tree, diff list, editor panel, editor view
    Settings/       — settings window
    Sidebar/        — project/tab sidebar
    Styles/         — reusable SwiftUI view styles
    Terminal/       — terminal pane, split container
```

## Guidelines

- All mutation goes through `AppState` — views never mutate models directly
- New views get a file-level comment explaining what they do and what they connect to
- Commit messages explain *why*, not what (the diff covers what)
- Keep PRs focused — one feature or fix per PR

## Reporting bugs

Open an issue with:
- macOS version
- Steps to reproduce
- What you expected vs what happened

## Adding themes

Agamon uses [Ghostty-format](https://ghostty.org/docs/config/reference#theme) theme files. To bundle a new theme, drop the `.conf` file into `Sources/Agamon/Resources/Themes/`.
