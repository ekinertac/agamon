// Manages the tmux server that backs all terminal sessions.
// Uses a dedicated Unix socket at ~/.agamon/tmux.sock so Agamon's sessions are isolated
// from any tmux sessions the user already has running in their own socket.
// Control mode (-CC) is the eventual target — it lets us attach SwiftTerm PTYs to named panes
// and get structured events back. For now, basic server lifecycle only.
// Related: TerminalSession.swift (per-pane sessions), TerminalPaneView.swift (SwiftTerm integration).

import Foundation

final class TmuxController {
    static let shared = TmuxController()

    // Isolated socket — doesn't interfere with user's existing tmux sessions.
    private let socketPath: String

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agamon").path
        socketPath = "\(dir)/tmux.sock"
    }

    // MARK: - Server Lifecycle

    func ensureServerRunning() {
        try? FileManager.default.createDirectory(
            atPath: (socketPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        guard !isServerAlive() else { return }
        startServer()
    }

    private func isServerAlive() -> Bool {
        let p = Process()
        p.executableURL = tmuxURL
        p.arguments = ["-S", socketPath, "list-sessions"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func startServer() {
        let p = Process()
        p.executableURL = tmuxURL
        p.arguments = ["-S", socketPath, "new-session", "-d", "-s", "agamon-boot"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: - Session Management

    func sessionName(for projectID: UUID) -> String {
        "ag-\(projectID.uuidString.prefix(8))"
    }

    func createSession(projectID: UUID, workingDirectory: String) {
        ensureServerRunning()
        let name = sessionName(for: projectID)
        guard !sessionExists(name) else { return }

        let p = Process()
        p.executableURL = tmuxURL
        p.arguments = ["-S", socketPath, "new-session", "-d", "-s", name, "-c", workingDirectory]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private func sessionExists(_ name: String) -> Bool {
        let p = Process()
        p.executableURL = tmuxURL
        p.arguments = ["-S", socketPath, "has-session", "-t", name]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    // MARK: - Helpers

    private var tmuxURL: URL {
        for path in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"] {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: path) { return url }
        }
        return URL(fileURLWithPath: "/usr/bin/tmux")
    }
}
