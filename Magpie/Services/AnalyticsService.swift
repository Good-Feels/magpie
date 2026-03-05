import Foundation
import Combine
import Mixpanel

@MainActor
final class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()

    private enum Keys {
        static let analyticsEnabled = "analyticsEnabled"
        static let mixpanelToken = "MIXPANEL_TOKEN"
    }

    @Published private(set) var isTrackingEnabled: Bool

    private var isConfigured = false

    private init(userDefaults: UserDefaults = .standard) {
        if userDefaults.object(forKey: Keys.analyticsEnabled) == nil {
            userDefaults.set(true, forKey: Keys.analyticsEnabled)
        }

        isTrackingEnabled = userDefaults.bool(forKey: Keys.analyticsEnabled)
    }

    func configure() {
        guard !isConfigured else {
            syncTrackingPreference()
            return
        }

        guard let token = Bundle.main.object(forInfoDictionaryKey: Keys.mixpanelToken) as? String else {
            return
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            return
        }

        Mixpanel.initialize(
            token: trimmedToken,
            flushInterval: 60,
            optOutTrackingByDefault: !isTrackingEnabled,
            useUniqueDistinctId: false
        )
        isConfigured = true

        Mixpanel.mainInstance().useIPAddressForGeoLocation = false
        registerSuperProperties()
        syncTrackingPreference()
    }

    func setTrackingEnabled(_ enabled: Bool) {
        let wasTrackingEnabled = isTrackingEnabled
        isTrackingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.analyticsEnabled)

        if isConfigured, enabled, !wasTrackingEnabled, Mixpanel.mainInstance().hasOptedOutTracking() {
            Mixpanel.mainInstance().optInTracking()
        }

        syncTrackingPreference()
    }

    func trackAppOpened(hasCompletedOnboarding: Bool) {
        track(
            event: "app_opened",
            properties: [
                "has_completed_onboarding": hasCompletedOnboarding,
            ]
        )
    }

    func trackPopoverOpened(itemCount: Int) {
        track(
            event: "popover_opened",
            properties: [
                "visible_items_bucket": AnalyticsBuckets.resultCountBucket(for: itemCount),
            ]
        )
    }

    func trackSearchPerformed(queryLength: Int, resultCount: Int) {
        track(
            event: "search_performed",
            properties: [
                "query_length_bucket": AnalyticsBuckets.queryLengthBucket(for: queryLength),
                "result_count_bucket": AnalyticsBuckets.resultCountBucket(for: resultCount),
            ]
        )
    }

    func trackClipRestored(contentType: String) {
        track(
            event: "clip_restored",
            properties: [
                "content_type": normalizedContentType(contentType),
            ]
        )
    }

    func flush() {
        guard isConfigured, isTrackingEnabled else { return }
        Mixpanel.mainInstance().flush()
    }

    private func track(event: String, properties: Properties? = nil) {
        guard isConfigured, isTrackingEnabled else { return }
        Mixpanel.mainInstance().track(event: event, properties: properties)
    }

    private func syncTrackingPreference() {
        guard isConfigured else { return }

        if !isTrackingEnabled && !Mixpanel.mainInstance().hasOptedOutTracking() {
            Mixpanel.mainInstance().optOutTracking()
        }
    }

    private func registerSuperProperties() {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        Mixpanel.mainInstance().registerSuperProperties([
            "app_name": "Magpie",
            "app_version": appVersion,
            "build_number": buildNumber,
            "platform": "macOS",
            "os_version": osVersionString,
            "build_configuration": buildConfiguration,
            "distribution_channel": distributionChannel,
        ])
    }

    private func normalizedContentType(_ contentType: String) -> String {
        switch contentType {
        case "text", "richText", "image", "filePath":
            return contentType
        default:
            return "unknown"
        }
    }

    private var buildConfiguration: String {
#if DEBUG
        return "debug"
#else
        return "release"
#endif
    }

    private var distributionChannel: String {
        let bundlePath = Bundle.main.bundleURL.path
        let userApplicationsPath = "\(NSHomeDirectory())/Applications/"

        if bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(userApplicationsPath) {
            return "installed"
        }

        return "local"
    }
}
