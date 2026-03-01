import SwiftUI
import ClipboardEngine

/// First-launch onboarding sheet. Prompts the user to enable Launch at Login
/// and (on macOS 15.4+) grant clipboard access permission.
struct OnboardingView: View {
    @StateObject private var loginService = LaunchAtLoginService()
    @ObservedObject var accessChecker: ClipboardAccessChecker
    let onComplete: () -> Void

    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Branding
            Text("🐦‍⬛")
                .font(.system(size: 64))

            Text("Welcome to Magpie")
                .font(.title.bold())

            Text("Copy freely. Everything is saved.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer().frame(height: 4)

            // Settings
            VStack(alignment: .leading, spacing: 16) {
                // Launch at Login
                HStack(spacing: 12) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                            .font(.body.weight(.medium))
                        Text("Start Magpie automatically when you log in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Clipboard permission (macOS 15.4+ only)
                if accessChecker.isPrivacyControlAvailable {
                    HStack(spacing: 12) {
                        Image(systemName: accessChecker.hasAccess
                              ? "checkmark.shield.fill" : "lock.shield.fill")
                            .font(.system(size: 18))
                            .foregroundColor(accessChecker.hasAccess ? .green : .orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clipboard Access")
                                .font(.body.weight(.medium))

                            if accessChecker.hasAccess {
                                Text("Permission granted")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Magpie needs clipboard access to save your copy history")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    Button("Open System Settings") {
                                        accessChecker.openPrivacySettings()
                                    }
                                    .controlSize(.small)

                                    Button("Check Again") {
                                        accessChecker.checkAccess()
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 20)

            Spacer()

            // Get Started
            Button {
                // Apply login preference
                if launchAtLogin {
                    loginService.setLoginItem(enabled: true)
                }
                onComplete()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Spacer().frame(height: 8)
        }
        .frame(width: 400, height: 480)
    }
}
