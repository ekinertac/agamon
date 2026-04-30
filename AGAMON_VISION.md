# Agamon — Vision

## The Problem

Working with CLI agents today is painful. You juggle multiple terminal windows, lose sessions when you close them, constantly switch to a text editor to view or edit a file an agent touched, and have no way to see what's happening across several parallel agent runs at once. The tools weren't designed for this workflow — we're adapting tools built for humans typing commands one at a time.

## The North Star

Two things should be true when you use Agamon:

1. **Sessions never die.** Close the app, restart your machine, come back a week later — your agents and shells pick up exactly where they left off, in the same directories, with the same history.
2. **You never need to open another editor.** When an agent writes a file, you open it right there. You make a quick edit, save it, and the agent continues. The terminal and the editor are the same place.

## Who It's For

Developers running CLI agents — tools like Claude Code, Aider, or any shell-based agent that operates on a codebase. You might have three agents running in parallel, each in a different project. You want to watch them, intervene when needed, edit a file they produced, and context-switch without losing anything.

## Core Concepts

**Projects** are the top-level unit. A project maps to a codebase or working context. You create one per repo or task. Projects live in a sidebar. Switching projects switches everything — the terminal area, the file explorer, the open editor tabs.

**Tabs** are independent terminal sessions within a project. Each tab is its own shell. You open a new tab for a new agent run, or just to keep things organized. Tabs are cheap — open as many as you want.

**Splits** let you divide a tab into multiple panes — horizontally or vertically, as many levels deep as you need. A split pane is its own shell. This is how you watch an agent run in one pane while tailing a log in another, or run two agents side by side.

**Focus mode** makes a single pane fill the entire terminal area, hiding the surrounding splits. Toggle it when you need to concentrate on one thing. The split layout is still there underneath — toggle back and it returns exactly as you left it.

**The file panel** lives on the right side of the window. It shows the file tree for the active project's directory. Clicking a file opens it in a lightweight editor — enough to read what an agent wrote, make a small edit, and save. This isn't a full IDE; it's a quick-look-and-edit panel.

## What Agamon Is Not

It's not a general-purpose terminal emulator replacing iTerm2 for all your daily work. It's not an IDE. It's not a way to manage remote servers or SSH connections. It's a focused tool for a specific workflow: running agents locally on a codebase and staying in control of what they're doing.

## The Feel

Fast, minimal, native. No Electron, no web tech, no abstraction layers between you and the terminal. The UI gets out of the way. There's no clutter, no status bars you didn't ask for, no configuration maze. You open it, your sessions are there, you work.
