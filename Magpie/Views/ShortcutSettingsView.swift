import SwiftUI
import AppKit
import KeyboardShortcuts

/// Shortcuts tab in the preferences window.
///
/// Uses simple controls instead of `KeyboardShortcuts.Recorder` because
/// Recorder currently crashes in this app on macOS 15 when the tab opens.
struct ShortcutSettingsView: View {
    @State private var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleClipboardHistory)
    @State private var isRecordingShortcut = false
    @State private var errorText: String?
    @State private var suspendedShortcut: KeyboardShortcuts.Shortcut?
    @State private var didSaveCustomShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionCard("Keyboard Shortcut") {
                HStack {
                    Text("Toggle Clipboard History")
                    Spacer()
                    Text(currentShortcut == nil ? "Not set" : "Configured")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Text("Current:")
                        .foregroundColor(.secondary)
                    Text(shortcutLabel(currentShortcut))
                        .font(.system(.body, design: .monospaced))
                }

                HStack(spacing: 10) {
                    Button("Set Default (⌘⇧V)") {
                        KeyboardShortcuts.setShortcut(
                            .init(.v, modifiers: [.command, .shift]),
                            for: .toggleClipboardHistory
                        )
                        refresh()
                    }

                    Button("Set Custom...") {
                        errorText = nil
                        beginCustomShortcutCapture()
                    }

                    Button("Clear Shortcut") {
                        KeyboardShortcuts.setShortcut(nil, for: .toggleClipboardHistory)
                        refresh()
                    }
                }

                Text(ShortcutSettingsCopy.helperText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer(minLength: 6)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isRecordingShortcut) {
            ShortcutCaptureSheet(
                initialShortcut: currentShortcut
            ) { shortcut in
                KeyboardShortcuts.setShortcut(shortcut, for: .toggleClipboardHistory)
                didSaveCustomShortcut = true
                refresh()
            }
        }
        .onChange(of: isRecordingShortcut) { isPresented in
            if !isPresented {
                endCustomShortcutCapture()
            }
        }
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleClipboardHistory)
    }

    private func beginCustomShortcutCapture() {
        suspendedShortcut = currentShortcut
        didSaveCustomShortcut = false

        // Suspend the active global trigger while the recorder is focused.
        if currentShortcut != nil {
            KeyboardShortcuts.setShortcut(nil, for: .toggleClipboardHistory)
        }
        refresh()
        isRecordingShortcut = true
    }

    private func endCustomShortcutCapture() {
        if !didSaveCustomShortcut, let suspendedShortcut {
            KeyboardShortcuts.setShortcut(suspendedShortcut, for: .toggleClipboardHistory)
        }

        suspendedShortcut = nil
        didSaveCustomShortcut = false
        refresh()
    }

    @MainActor
    private func shortcutLabel(_ shortcut: KeyboardShortcuts.Shortcut?) -> String {
        guard let shortcut else {
            return "Not set"
        }

        return shortcut.description
    }

    private func sectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

private struct ShortcutCaptureSheet: View {
    let initialShortcut: KeyboardShortcuts.Shortcut?
    let onSave: (KeyboardShortcuts.Shortcut) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var capturedShortcut: KeyboardShortcuts.Shortcut?
    @State private var validationMessage: String?
    @State private var liveText = "Type shortcut..."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Custom Shortcut")
                .font(.title3.weight(.semibold))

            Text("Press the key combination you want to use.")
                .foregroundColor(.secondary)

            ShortcutCaptureView { shortcut in
                capturedShortcut = shortcut
                validationMessage = ShortcutSettingsRules.validationMessage(for: shortcut)
                liveText = shortcut?.description ?? "Unsupported key"
            } onPreview: { preview in
                liveText = preview
            }
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )

            Text(liveText)
                .font(.system(.title3, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                Text("Selected:")
                    .foregroundColor(.secondary)
                Text(shortcutLabel(capturedShortcut ?? initialShortcut))
                    .font(.system(.body, design: .monospaced))
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    guard let shortcut = capturedShortcut else {
                        validationMessage = ShortcutSettingsRules.validationMessage(for: nil)
                        return
                    }

                    if let message = ShortcutSettingsRules.validationMessage(for: shortcut) {
                        validationMessage = message
                        return
                    }

                    onSave(shortcut)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 430)
    }

    @MainActor
    private func shortcutLabel(_ shortcut: KeyboardShortcuts.Shortcut?) -> String {
        guard let shortcut else {
            return "Not set"
        }

        return shortcut.description
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (KeyboardShortcuts.Shortcut?) -> Void
    let onPreview: (String) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onPreview = onPreview
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onPreview = onPreview
        nsView.window?.makeFirstResponder(nsView)
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onCapture: ((KeyboardShortcuts.Shortcut?) -> Void)?
    var onPreview: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        let text = "Type shortcut..."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCapture?(nil)
            onPreview?("Type shortcut...")
            return
        }

        let shortcut = KeyboardShortcuts.Shortcut(event: event)
        onCapture?(shortcut)
        onPreview?(shortcut?.description ?? "Unsupported key")
    }

    override func flagsChanged(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty {
            onPreview?("Type shortcut...")
        } else {
            onPreview?(modifiers.ks_symbolicRepresentation)
        }
    }
}
