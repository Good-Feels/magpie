import AppKit
import SwiftUI

struct MCPSettingsView: View {
    @ObservedObject var sharing: MCPSharing

    @State private var preparingClaudeExtension = false
    @State private var claudeStatus: String?
    @State private var showClaudeDownload = false
    @State private var showChatGPTSetup = false

    private var executable: URL {
        Bundle.main.executableURL ?? URL(fileURLWithPath: "/Applications/Magpie.app/Contents/MacOS/Magpie")
    }

    var body: some View {
        Form {
            Section("Clipboard sharing") {
                Toggle("Enable MCP sharing", isOn: Binding(
                    get: { sharing.isEnabled },
                    set: sharing.setEnabled
                ))
                Text("Right-click a text clip in Magpie and choose Share with AI. Connected assistants can send shared text to their provider. Turning sharing off or quitting Magpie clears the selection.")
                    .foregroundStyle(.secondary)
                if case .failed(let message) = sharing.status {
                    Text("Couldn’t start MCP sharing. \(message)")
                        .foregroundStyle(.red)
                } else if sharing.isEnabled {
                    LabeledContent("Status", value: sharing.isAvailable ? "Ready" : "Starting…")
                }
                if sharing.isAvailable {
                    LabeledContent("Shared clips") {
                        HStack {
                            Text("\(sharing.clips.count) of \(MCPSharing.clipLimit)")
                                .foregroundStyle(.secondary)
                            Button("Stop Sharing All", action: sharing.clear)
                                .disabled(sharing.clips.isEmpty)
                        }
                    }
                }
            }

            Section("Connect an assistant") {
                LabeledContent("Claude Desktop") {
                    Button("Connect to Claude", action: connectClaude)
                        .disabled(preparingClaudeExtension)
                }
                if preparingClaudeExtension {
                    ProgressView("Preparing the Magpie extension…").controlSize(.small)
                } else if let claudeStatus {
                    Text(claudeStatus).foregroundStyle(.secondary)
                }
                if showClaudeDownload {
                    Link("Get Claude Desktop", destination: URL(string: "https://claude.ai/download")!)
                }

                LabeledContent("ChatGPT") {
                    Button("Connect to ChatGPT") { showChatGPTSetup = true }
                }

                Link("Manual setup guide", destination: URL(string: "https://github.com/Good-Feels/magpie/blob/main/docs/MCP.md")!)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showChatGPTSetup) {
            ChatGPTSetupView(executable: executable)
        }
    }

    @MainActor
    private func connectClaude() {
        guard let claude = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") else {
            claudeStatus = "Install Claude Desktop, then try again."
            showClaudeDownload = true
            return
        }

        let command = executable
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        preparingClaudeExtension = true
        claudeStatus = nil
        showClaudeDownload = false

        Task {
            defer { preparingClaudeExtension = false }
            do {
                let installer = try await Task.detached(priority: .userInitiated) {
                    let cache = try FileManager.default.url(
                        for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
                    ).appendingPathComponent("Magpie/Claude", isDirectory: true)
                    return try MCPConnectionSetup.claudeExtension(executable: command, version: version, cacheDirectory: cache)
                }.value
                _ = try await NSWorkspace.shared.open([installer], withApplicationAt: claude, configuration: .init())
                claudeStatus = "Approve the Magpie extension in Claude to finish."
            } catch {
                claudeStatus = "Couldn’t open the Claude installer. You can connect using the manual setup guide."
            }
        }
    }
}

private struct ChatGPTSetupView: View {
    let executable: URL
    @Environment(\.dismiss) private var dismiss
    @State private var copyStatus: String?

    private var codex: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to ChatGPT").font(.title2).bold()
            Text("ChatGPT needs a private OpenAI tunnel to reach Magpie. Codex can guide the setup on this Mac. You’ll need access to add tunnels in OpenAI Platform and to install a custom plugin in ChatGPT.")
            Text("Switch to **Codex**, open a local chat, and paste the setup prompt. Codex will guide you through any approvals and help test a sample clip.")
                .foregroundStyle(.secondary)

            if let copyStatus { Text(copyStatus).foregroundStyle(.secondary) }
            if codex == nil {
                Link("Get the ChatGPT desktop app", destination: URL(string: "https://chatgpt.com/download")!)
            }

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(codex == nil ? "Copy Setup Prompt" : "Copy Prompt and Open Codex", action: copySetupPrompt)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func copySetupPrompt() {
        let item = NSPasteboardItem()
        item.setString(MCPConnectionSetup.chatGPTSetupPrompt(executable: executable), forType: .string)
        item.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            copyStatus = "Couldn’t copy the setup prompt."
            return
        }
        copyStatus = "Setup prompt copied."
        if let codex { NSWorkspace.shared.open(codex) }
    }
}
