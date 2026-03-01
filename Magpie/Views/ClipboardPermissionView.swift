import SwiftUI
import ClipboardEngine

/// Shown in the popover when Magpie doesn't have clipboard access permission.
/// Guides the user to System Settings to grant "Always Allow" access.
struct ClipboardPermissionView: View {
    @ObservedObject var accessChecker: ClipboardAccessChecker

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: accessChecker.accessState == .denied
                  ? "xmark.shield.fill"
                  : "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(accessChecker.accessState == .denied ? .red : .orange)

            Text("Clipboard Access Required")
                .font(.headline)

            Text(descriptionText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                if accessChecker.accessState == .denied {
                    Button {
                        accessChecker.openPrivacySettings()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                            Text("Open System Settings")
                        }
                        .frame(maxWidth: 200)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }

                Button("Try Prompt Again") {
                    accessChecker.requestAccess()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button("Check Again") {
                    accessChecker.checkAccess()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }

            Text(footerText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var descriptionText: String {
        if accessChecker.accessState == .denied {
            return "Clipboard access has been denied. Magpie needs permission to read your clipboard to save your copy history."
        } else {
            return "Magpie needs permission to read your clipboard so it can save everything you copy. Without this, clipboard history won't work."
        }
    }

    private var footerText: String {
        if accessChecker.accessState == .denied {
            return "If available on your macOS build, allow Magpie in Privacy & Security. Then click Check Again."
        }
        return "Copy text or an image in another app, then click Try Prompt Again."
    }
}
