import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut to toggle the clipboard history popover.
    /// The default follows the key that TYPES "v" on the user's layout
    /// (Dvorak/AZERTY/… differ from the physical QWERTY position).
    static let toggleClipboardHistory = Self(
        "toggleClipboardHistory",
        default: .layoutAwareDefault
    )
}
