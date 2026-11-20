import Foundation

struct UpdateNotice: Equatable {
    enum Action: Equatable {
        case openMCPSettings
        case viewReleaseNotes
    }

    static let lastLaunchedVersionKey = "lastLaunchedMarketingVersion"
    private static let firstNoticeVersion = "1.0.21"

    let version: String
    let summary: String
    let action: Action

    var title: String { "What’s New in Magpie \(version)" }
    var releaseNotesURL: URL {
        URL(string: "https://github.com/Good-Feels/magpie/releases/tag/v\(version)")!
    }

    static func forLaunch(
        version: String?,
        onboardingComplete: Bool,
        defaults: UserDefaults,
        releaseNotes: String? = nil
    ) -> Self? {
        guard let version, !version.isEmpty else { return nil }
        let previous = defaults.string(forKey: lastLaunchedVersionKey)
        if let previous, !isOlder(previous, than: version) { return nil }
        defaults.set(version, forKey: lastLaunchedVersionKey)

        guard onboardingComplete, !isOlder(version, than: firstNoticeVersion) else { return nil }
        // Existing installations have completed onboarding before this key is introduced.
        if previous.map({ isOlder($0, than: firstNoticeVersion) }) ?? true {
            return Self(
                version: version,
                summary: "Let connected assistants search and read your clipboard history. Go to **Settings → MCP** and turn on **Allow access to clipboard history**.",
                action: .openMCPSettings
            )
        }
        return Self(
            version: version,
            summary: firstParagraph(of: releaseNotes) ?? "Read the release notes to see what changed in this update.",
            action: .viewReleaseNotes
        )
    }

    private static func isOlder(_ version: String, than other: String) -> Bool {
        version.compare(other, options: .numeric) == .orderedAscending
    }

    private static func firstParagraph(of markdown: String?) -> String? {
        guard let markdown else { return nil }
        let lines = markdown.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let paragraph = lines.drop(while: { $0.isEmpty || $0.hasPrefix("#") })
            .prefix(while: { !$0.isEmpty && !$0.hasPrefix("#") })
        return paragraph.isEmpty ? nil : paragraph.joined(separator: " ")
    }
}
