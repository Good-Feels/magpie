import Foundation

/// Shared retention semantics for capture and Settings. Zero explicitly means unlimited.
public enum HistorySettings {
    public static let key = "maxHistorySize"
    public static let defaultLimit = 200

    /// Run before registering defaults: existing history captured under the old
    /// missing-key/unlimited behavior must never be silently bulk-pruned on upgrade.
    public static func prepare(defaults: UserDefaults, hasExistingHistory: Bool) {
        if defaults.object(forKey: key) == nil, hasExistingHistory {
            defaults.set(0, forKey: key)
        }
        defaults.register(defaults: [key: defaultLimit])
    }

    public static func limit(in defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultLimit }
        let stored = defaults.integer(forKey: key)
        return stored >= 0 ? stored : defaultLimit
    }
}
