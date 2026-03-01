import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut to toggle the clipboard history popover.
    static let toggleClipboardHistory = Self(
        "toggleClipboardHistory",
        default: .init(.v, modifiers: [.command, .shift])
    )
}
