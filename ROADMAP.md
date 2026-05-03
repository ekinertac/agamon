# Roadmap

## v0.3 — Editor & File Tree Completeness

The focus is closing the gap that forces you to leave the app for basic file operations and editor tasks.

### Editor
- [ ] Tab key indents all selected lines (pairs with existing Shift+Tab de-indent)
- [ ] Line number gutter
- [ ] Line / column indicator in the status bar
- [ ] Auto-closing brackets, parens, and quotes

### File Tree
- [ ] New file / new folder (toolbar button or right-click context menu)
- [ ] Rename file or folder (double-click or context menu)
- [ ] Delete file or folder (with confirmation)

### Session
- [ ] Per-project open editor files (currently global — switching projects mixes tabs)
- [ ] Restore `filePanelVisible` state across launches

### Editor Tabs
- [ ] Drag to reorder tabs
- [ ] Unsaved-changes dot in the tab itself (not just the status bar)

---

## v0.4 — Git Integration

Make the built-in git awareness deeper so you rarely need to open a terminal just for git.

- [ ] Git blame gutter in the editor (author + relative date per line)
- [ ] Stage / unstage individual files from the diff list
- [ ] Inline conflict markers highlighted in the editor
- [ ] Commit panel: message field + stage/commit without leaving the app

---

## v0.5 — AI Pane

- [ ] Dedicated AI chat split pane (Claude)
- [ ] Context-aware: sends selected file, current git diff, or terminal output as context
- [ ] Inline apply: AI-suggested edits applied directly to the open file

---

## Icebox

Ideas that are interesting but not yet scheduled.

- Multiple windows
- Remote SSH sessions (open a pane connected to a remote host)
- Vim keybindings mode in the editor
- Custom keybinding configuration
- Plugin / extension system
