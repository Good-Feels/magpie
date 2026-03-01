import SwiftUI
import AppKit
import ClipboardEngine

/// Multi-step first-launch onboarding:
///   1. Welcome — branding + Launch at Login toggle
///   2. Clipboard Access — triggers macOS consent dialog (macOS 15.4+ only, skipped otherwise)
///   3. Find Magpie — shows the menu bar icon location
///   4. How It Works — shows key features and the global hotkey
struct OnboardingView: View {
    @StateObject private var loginService = LaunchAtLoginService()
    @ObservedObject var accessChecker: ClipboardAccessChecker
    let onComplete: () -> Void

    private enum Step {
        case welcome, clipboardAccess, findMagpie, howItWorks
    }

    @State private var currentStep: Step = .welcome
    @State private var launchAtLogin = true
    @State private var accessAttempted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                switch currentStep {
                case .welcome:
                    welcomeContent
                case .clipboardAccess:
                    clipboardAccessContent
                case .findMagpie:
                    findMagpieContent
                case .howItWorks:
                    howItWorksContent
                }
            }

            Spacer()

            Button {
                advance()
            } label: {
                Text(currentStep == .howItWorks ? "Get Started" : "Continue")
                    .frame(maxWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Spacer().frame(height: 24)
        }
        .frame(width: 400, height: 480)
        .onAppear {
            print("[Magpie] Onboarding appeared: accessState=\(accessChecker.accessState)")
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeContent: some View {
        VStack(spacing: 20) {
            Text("🐦‍⬛")
                .font(.system(size: 64))

            Text("Welcome to Magpie")
                .font(.title.bold())

            Text("Copy freely. Everything is saved.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                HStack(spacing: 12) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                            .font(.body.weight(.medium))
                        Text("**Recommended** — Magpie runs in the background so your clipboard is always saved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Step 2: Clipboard Access

    private var clipboardAccessContent: some View {
        VStack(spacing: 20) {
            Image(systemName: accessChecker.hasAccess
                  ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(accessChecker.hasAccess ? .green : .orange)

            Text("Clipboard Access")
                .font(.title2.bold())

            if accessChecker.hasAccess {
                // Success
                Text("Permission granted!")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else if !accessAttempted {
                // First time: explain and offer the button
                Text("Magpie needs to read your clipboard to save your copy history.\nTap below and select **Allow** when macOS asks.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Button {
                    accessAttempted = true
                    print("[Magpie] Onboarding: Grant Access tapped")
                    accessChecker.requestAccess()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                        Text("Grant Access")
                    }
                    .frame(maxWidth: 200)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            } else {
                Text(followUpMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

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
                    .buttonStyle(.bordered)
                }

                Button("Try Prompt Again") {
                    print("[Magpie] Onboarding: Try Prompt Again tapped")
                    accessChecker.requestAccess()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button("Check Again") {
                    print("[Magpie] Onboarding: Check Again tapped")
                    accessChecker.checkAccess()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
    }

    private var followUpMessage: String {
        switch accessChecker.accessState {
        case .denied:
            return "Clipboard access is currently denied. Open System Settings and allow access for Magpie, then check again."
        case .needsPermission:
            return "Try prompting again after copying text or an image in another app. On some macOS builds, access prompts and settings links are not shown consistently."
        case .allowed:
            return "Permission granted!"
        }
    }

    // MARK: - Step 3: Find Magpie

    private var findMagpieContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Find Magpie in Your Menu Bar")
                .font(.title2.bold())

            Text("Magpie lives in your menu bar — the row of icons\nin the top-right corner of your screen.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Look for this icon")
                            .font(.body.weight(.medium))
                        Text("Click it anytime to see your clipboard history")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top-right of your screen")
                            .font(.body.weight(.medium))
                        Text("Near Wi-Fi, battery, and clock — it's always there")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Dock icon")
                            .font(.body.weight(.medium))
                        Text("Magpie stays out of the way — menu bar only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Step 4: How It Works

    private var howItWorksContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("You're All Set!")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 16) {
                instructionRow(
                    icon: "doc.on.doc",
                    title: "Copy anything",
                    detail: "Text, images, and files are saved automatically"
                )
                instructionRow(
                    icon: "command",
                    title: "Press ⌘⇧V",
                    detail: "Open your clipboard history from any app"
                )
                instructionRow(
                    icon: "magnifyingglass",
                    title: "Search and pin",
                    detail: "Find any clip instantly, pin your favorites"
                )
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 20)
        }
    }

    private func instructionRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Navigation

    private func advance() {
        print("[Magpie] Onboarding advance: currentStep=\(currentStep)")
        switch currentStep {
        case .welcome:
            if accessChecker.isPrivacyControlAvailable && !accessChecker.hasAccess {
                withAnimation { currentStep = .clipboardAccess }
            } else {
                withAnimation { currentStep = .findMagpie }
            }
        case .clipboardAccess:
            withAnimation { currentStep = .findMagpie }
        case .findMagpie:
            withAnimation { currentStep = .howItWorks }
        case .howItWorks:
            if launchAtLogin {
                loginService.setLoginItem(enabled: true)
            }
            onComplete()
        }
    }
}
