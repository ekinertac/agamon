// Thin Process wrapper for running git commands on a background thread.
// Returns stdout as a String; stderr is discarded so non-git directories
// produce empty output silently rather than crashing.
// Used by GitStatusView, DiffListView, and DiffEditorView.

import Foundation

func gitOutput(_ args: [String], in directory: String) -> String {
    let proc = Process()
    proc.executableURL      = URL(fileURLWithPath: "/usr/bin/git")
    proc.arguments          = args
    proc.currentDirectoryURL = URL(fileURLWithPath: directory)
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError  = Pipe()  // discard
    guard (try? proc.run()) != nil else { return "" }
    proc.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}
