import SwiftUI
import AppKit

/// Settings view for managing which apps are excluded from clipboard capture.
struct AppExclusionsView: View {
    @EnvironmentObject var exclusionManager: ExclusionListManager
    @State private var showingAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Excluded Apps")
                .font(.headline)
            Text("Clips copied from these apps will not be recorded.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Current exclusions list
            if exclusionManager.excludedBundleIDs.isEmpty {
                Text("No apps excluded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                List {
                    ForEach(
                        Array(exclusionManager.excludedBundleIDs).sorted(),
                        id: \.self
                    ) { bundleID in
                        HStack {
                            appRow(bundleID: bundleID)
                            Spacer()
                            Button {
                                exclusionManager.include(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 160)
            }

            // Add app button
            Button {
                showingAppPicker = true
            } label: {
                Label("Add App\u{2026}", systemImage: "plus.circle")
            }
            .popover(isPresented: $showingAppPicker) {
                appPickerPopover
            }
        }
        .padding()
    }

    // MARK: - Subviews

    @ViewBuilder
    private func appRow(bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(displayName(for: bundleID))
                .font(.system(size: 12))
        }
    }

    private var appPickerPopover: some View {
        VStack(spacing: 0) {
            Text("Select an app to exclude")
                .font(.subheadline)
                .padding(8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(
                        exclusionManager.runningApps().filter {
                            !exclusionManager.excludedBundleIDs.contains($0.bundleID)
                        },
                        id: \.bundleID
                    ) { app in
                        Button {
                            exclusionManager.exclude(app.bundleID)
                            showingAppPicker = false
                        } label: {
                            HStack(spacing: 8) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                }
                                Text(app.name)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 250, height: 200)
        }
    }

    // MARK: - Helpers

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}
