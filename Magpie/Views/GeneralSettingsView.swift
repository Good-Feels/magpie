import SwiftUI

/// General tab in the preferences window.
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    @StateObject private var launchService = LaunchAtLoginService()
    @StateObject private var softwareUpdater = SoftwareUpdater()
    @ObservedObject private var analyticsService = AnalyticsService.shared

    @AppStorage("maxHistorySize") private var maxHistorySize: Int = 200
    @AppStorage("showSourceApp") private var showSourceApp: Bool = true
    @AppStorage("showTimestamps") private var showTimestamps: Bool = true

    @State private var moveFeedback: String?
    @State private var showClearConfirmStep1 = false
    @State private var showClearConfirmStep2 = false
    @State private var showClearConfirmStep3 = false

    private let historyOptions = [50, 100, 200, 500, 1000]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                startupSection
                updatesSection
                historySection
                displaySection
                analyticsSection
                dataSection
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var startupSection: some View {
        sectionCard("Startup") {
            Toggle("Launch at Login", isOn: $launchService.isEnabled)

            if shouldShowMoveAction {
                HStack(spacing: 10) {
                    Button("Move Magpie to /Applications") {
                        moveFeedback = nil
                        launchService.moveToApplicationsAndRelaunch { result in
                            switch result {
                            case .moved:
                                moveFeedback = "Magpie moved and relaunched from /Applications."
                            case .alreadyInApplications:
                                moveFeedback = "Magpie is already in /Applications."
                            case .destinationExists:
                                moveFeedback = "A Magpie.app already exists in /Applications."
                            case .failed(let reason):
                                moveFeedback = reason
                            }
                        }
                    }

                    Button("Reveal Current App") {
                        launchService.revealCurrentAppInFinder()
                    }
                    .buttonStyle(.link)
                }

                Text(moveFeedback ?? "Run Magpie from /Applications to make Login Items registration reliable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(startupStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var updatesSection: some View {
        sectionCard("Updates") {
            Toggle("Auto-check for updates", isOn: $softwareUpdater.automaticallyChecksForUpdates)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button("Check for Updates Now") {
                    softwareUpdater.checkForUpdates()
                }
                .disabled(!softwareUpdater.canCheckForUpdates)

                if let last = softwareUpdater.lastUpdateCheckDate {
                    Text("Last checked: \(relativeTime(from: last))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var historySection: some View {
        sectionCard("History") {
            Picker("Keep", selection: $maxHistorySize) {
                ForEach(historyOptions, id: \.self) { count in
                    Text("\(count) clips").tag(count)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 180, alignment: .leading)
        }
    }

    private var displaySection: some View {
        sectionCard("Display") {
            Toggle("Show source app name", isOn: $showSourceApp)
            Toggle("Show timestamps", isOn: $showTimestamps)
        }
    }

    private var dataSection: some View {
        sectionCard("Data") {
            Text("Delete all saved clipboard history from this Mac.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Clear All History") {
                showClearConfirmStep1 = true
            }
            .tint(.red)
            .alert("Clear all history?", isPresented: $showClearConfirmStep1) {
                Button("Cancel", role: .cancel) {}
                Button("Continue", role: .destructive) {
                    showClearConfirmStep2 = true
                }
            } message: {
                Text("This will delete every saved clip.")
            }
            .alert("This cannot be undone", isPresented: $showClearConfirmStep2) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) {
                    showClearConfirmStep3 = true
                }
            } message: {
                Text("Pinned and unpinned clips will all be removed.")
            }
            .alert("Final confirmation", isPresented: $showClearConfirmStep3) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All History", role: .destructive) {
                    appState.clearAll()
                }
            } message: {
                Text("Are you absolutely sure?")
            }
        }
    }

    private var analyticsSection: some View {
        sectionCard("Analytics") {
            Toggle(
                "Share anonymous usage metrics",
                isOn: Binding(
                    get: { analyticsService.isTrackingEnabled },
                    set: { analyticsService.setTrackingEnabled($0) }
                )
            )

            Text("Tracks aggregate events like app opens, searches, and restored clips. Clipboard contents, file paths, and copied text are never sent.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var shouldShowMoveAction: Bool {
        StartupUIRules.shouldShowMoveAction(
            isRunningFromApplicationsFolder: launchService.isRunningFromApplicationsFolder
        )
    }

    private var startupStatusText: String {
        StartupUIRules.startupStatusText(
            isRunningFromApplicationsFolder: launchService.isRunningFromApplicationsFolder,
            statusDescription: launchService.statusDescription
        )
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
