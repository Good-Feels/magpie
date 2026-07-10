import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts

/// Resolves characters to key codes under the user's CURRENT keyboard
/// layout. Carbon key codes name physical key positions (ANSI/QWERTY),
/// so `Key.v` is the QWERTY V position — which types "k" on Dvorak and
/// sits elsewhere on AZERTY. A default shortcut meant as a mnemonic
/// ("V" as in paste) must follow the printed keycap, not the position.
enum KeyboardLayoutResolver {
    /// The Carbon key code of the key that types `character` (unmodified)
    /// under the current keyboard layout, or nil if no key produces it.
    static func keyCode(forCharacter character: Character) -> Int? {
        guard
            let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(
                inputSource,
                kTISPropertyUnicodeKeyLayoutData
            )
        else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer)
            .takeUnretainedValue() as Data
        let target = String(character).lowercased()

        return layoutData.withUnsafeBytes { rawBuffer -> Int? in
            guard let keyLayout = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }

            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0

                let error = UCKeyTranslate(
                    keyLayout,
                    UInt16(code),
                    UInt16(kUCKeyActionDisplay),
                    0, // no modifiers
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )

                guard error == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: characters, count: length).lowercased() == target {
                    return code
                }
            }

            return nil
        }
    }
}

extension KeyboardShortcuts.Shortcut {
    /// ⌘⇧ + the key that TYPES "v" on the user's layout. Falls back to
    /// the physical QWERTY V position when the layout has no "v" key
    /// (e.g. non-Latin layouts, where the position is the best guess).
    static var layoutAwareDefault: Self {
        let keyCode = KeyboardLayoutResolver.keyCode(forCharacter: "v")
            ?? KeyboardShortcuts.Key.v.rawValue
        return Self(.init(rawValue: keyCode), modifiers: [.command, .shift])
    }

    /// The pre-1.0.10 hardcoded default: physical QWERTY V position.
    static var legacyPhysicalDefault: Self {
        Self(.v, modifiers: [.command, .shift])
    }
}

enum ShortcutLayoutRules {
    /// Early builds stored the physical QWERTY-V shortcut for everyone.
    /// Migrate a stored value only when it IS that legacy default and the
    /// current layout types "v" on a different key — a user-customized
    /// shortcut never matches and is left alone.
    static func shouldMigrateStoredShortcut(
        stored: KeyboardShortcuts.Shortcut?,
        legacyDefault: KeyboardShortcuts.Shortcut,
        layoutAwareDefault: KeyboardShortcuts.Shortcut
    ) -> Bool {
        stored == legacyDefault && layoutAwareDefault != legacyDefault
    }
}
