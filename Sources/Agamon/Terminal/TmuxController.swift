// Manages the tmux server that backs all terminal sessions.
// Uses a dedicated socket at ~/.agamon/tmux.sock so Agamon's sessions are isolated
// from any tmux sessions the user already has running.
//
// Integration model: SwiftTerm runs `tmux new-session -A -s agamon-{paneUUID}` as the
// PTY process. The `-A` flag attaches to an existing session if one exists, otherwise
// creates a new one. Because pane UUIDs are persisted in projects.json, the same session
// name is used on every app restart → seamless reattachment.
//
// A minimal config at ~/.agamon/tmux.conf suppresses the status bar and sets the correct
// TERM so the user sees only their shell with no tmux chrome.
//
// Related: TerminalPaneView.swift (calls attachArgs), AppState.swift (calls killSession on pane close).

import Foundation

final class TmuxController {
    static let shared = TmuxController()

    private let agamonDir: String
    let socketPath: String
    let configPath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        agamonDir  = "\(home)/.agamon"
        socketPath = "\(agamonDir)/tmux.sock"
        configPath = "\(agamonDir)/tmux.conf"
    }

    // MARK: - Availability

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: tmuxPath)
    }

    // MARK: - Setup

    // Call once at app start. Writes config, ensures the server is running.
    func setup() {
        guard isAvailable else { return }
        try? FileManager.default.createDirectory(atPath: agamonDir,
                                                  withIntermediateDirectories: true)
        writeConfig()
        if !isServerAlive() { startServer() }
    }

    private func writeConfig() {
        // Written fresh each launch so config stays in sync with app expectations.
        // allow-passthrough on: inner programs (Claude Code, etc.) can send OSC escape
        // sequences through tmux to SwiftTerm — needed for OSC 52 clipboard, OSC 8
        // hyperlinks, inline images, and OSC 0/2 title updates. Without it tmux strips
        // those sequences and the features silently break.
        let conf = """
        set -g status off
        set -g default-terminal "xterm-256color"
        set -g escape-time 10
        set -g allow-passthrough on
        """
        try? conf.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Server Lifecycle

    private func isServerAlive() -> Bool {
        run(["-S", socketPath, "list-sessions"]) == 0
    }

    private func startServer() {
        // Boot the server with a throwaway session; killed immediately after.
        run(["-S", socketPath, "-f", configPath, "new-session", "-d", "-s", "agamon-boot"])
    }

    // MARK: - Per-Pane Session

    // Returns (executable, args) to pass to SwiftTerm.startProcess.
    // new-session -A: attach if session exists, create+attach if not.
    // -c workingDir applies only on creation; reattach keeps the shell's existing cwd.
    func attachArgs(for paneID: UUID, workingDir: String) -> (String, [String]) {
        let args = ["-S", socketPath, "-f", configPath,
                    "new-session", "-A", "-s", sessionName(for: paneID), "-c", workingDir]
        return (tmuxPath, args)
    }

    func killSession(for paneID: UUID) {
        guard isAvailable else { return }
        run(["-S", socketPath, "kill-session", "-t", sessionName(for: paneID)])
    }

    private func sessionName(for paneID: UUID) -> String {
        "agamon-\(paneID.uuidString)"
    }

    // MARK: - Helpers

    @discardableResult
    private func run(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tmuxPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    var tmuxPath: String {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "/usr/bin/tmux"
    }
}
