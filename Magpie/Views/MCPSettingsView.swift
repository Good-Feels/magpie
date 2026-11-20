import AppKit
import SwiftUI

struct MCPSettingsView: View {
    @ObservedObject var history: MCPHistoryAccess

    @State private var preparingClaudeExtension = false
    @State private var claudeStatus: String?
    @State private var showClaudeDownload = false
    @State private var showChatGPTSetup = false

    private var executable: URL {
        Bundle.main.executableURL ?? URL(fileURLWithPath: "/Applications/Magpie.app/Contents/MacOS/Magpie")
    }

    var body: some View {
        Form {
            Section("Clipboard history access") {
                Toggle("Allow access to clipboard history", isOn: Binding(
                    get: { history.isEnabled },
                    set: history.setEnabled
                ))
                Text("Connected assistants can read all clips in your Magpie history, including new clips. They may send clips to their provider. Turn this off to block access.")
                    .foregroundStyle(.secondary)
                if history.isEnabled {
                    if case .failed(let message) = history.status {
                        Text("Couldn’t start clipboard history access. \(message)")
                            .foregroundStyle(.red)
                    } else {
                        LabeledContent("Status", value: history.isAvailable ? "Ready" : "Starting…")
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
