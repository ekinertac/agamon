// Lightweight inline editor for files the agent produces.
// Wraps NSTextView (AppKit) because SwiftUI's TextEditor lacks: monospace font control,
// disabling smart quotes/dashes, and proper dark background without fighting system appearance.
// Cmd+S saves. Dirty state shown as a dot next to the filename.
// Related: FilePanelView.swift (hosts this), FileTreeView.swift (file selection drives url/content).

import SwiftUI
import AppKit

struct FileEditorView: View {
    let url: URL
    @Binding var content: String
    var loadError: String? = nil
    @State private var isDirty = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Rectangle().fill(Theme.Color.border).frame(height: 1)
            EditorTextView(text: $content, onChange: { isDirty = true })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: url) {
            // Reset dirty state when switching files
            isDirty = false
            saveError = nil
        }
    }

    private var editorHeader: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(url.lastPathComponent)
                .font(.system(size: Theme.FontSize.sm, design: .monospaced))
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)

            if isDirty {
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 5, height: 5)
            }

            Spacer()

            if let error = saveError ?? loadError {
                Text(error)
                    .font(.system(size: Theme.FontSize.xs))
                    .foregroundStyle(Theme.Color.danger)
                    .lineLimit(1)
            }

            if isDirty {
                Button("Save") { save() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Color.surface)
    }

    private func save() {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - NSTextView wrapper

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var onChange: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: Theme.FontSize.sm, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = NSColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
        textView.textContainerInset = NSSize(width: Theme.Spacing.md, height: Theme.Spacing.md)

        // Disable "smart" substitutions — they corrupt code
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // Only update if content changed externally (e.g. file switched)
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
        }
    }
}
