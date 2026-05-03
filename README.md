<div align="center">
  <img src="docs/icon.png" width="128" alt="Agamon icon" />
  <h1>Agamon</h1>
  <p>A terminal multiplexer and file editor for macOS — built for developers who live in the terminal.</p>

  <a href="https://github.com/ekinertac/agamon/releases/latest">
    <img src="https://img.shields.io/github/v/release/ekinertac/agamon?style=flat-square&color=5e81f4" alt="Latest release" />
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square" alt="Swift 5.9" />
  <img src="https://img.shields.io/github/license/ekinertac/agamon?style=flat-square&color=green" alt="MIT License" />
</div>

---

![Agamon screenshot](docs/screenshot.png)

## Features

**Terminal**
- Split panes horizontally and vertically — as many as you need
- tmux integration: sessions survive tab switches and app restarts
- Per-pane attention indicators (BEL / bell)
- Zoom any pane to full-screen with ⌘⇧↩
- 50+ built-in themes with live preview

**Editor**
- Typora-style live markdown rendering
- Syntax highlighting for Swift, TypeScript, Python, Rust, and more
- Shift+Tab de-indent, line wrap toggle, native find bar (⌘F)
- Editor files restored across launches

**File panel**
- Git-aware file tree with status badges
- Unified diff viewer
- Resizable sidebar

**Workflow**
- Command palette (⌘P)
- Context-aware shortcuts: ⌘1/2 switches file panel tabs when focused, terminal tabs otherwise
- Spatial pane navigation with ⌃⌥ arrow keys
- Project switching with persistent tab layouts

## Download

Grab the latest build from [Releases](https://github.com/ekinertac/agamon/releases) — unzip and drop `Agamon.app` into `/Applications`.

Signed and notarized — no Gatekeeper prompts.

## Build from source

**Requirements:** macOS 14+, Swift 5.9+, Xcode command-line tools

```bash
git clone https://github.com/ekinertac/agamon
cd agamon
make bundle
open Agamon.app
```

`make bundle` compiles a release build, assembles `Agamon.app`, and signs it with an ad-hoc certificate. Run `make clean` to wipe the build artifacts.

## Themes

Agamon ships with 50+ themes in [Ghostty format](https://ghostty.org/docs/config/reference#theme). To add your own, drop `.conf` theme files into:

```
~/.config/agamon/themes/
```

They appear in **Settings → Appearance** on next launch.

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel
