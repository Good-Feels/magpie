import SwiftUI

struct MCPSettingsView: View {
    @ObservedObject var sharing: MCPSharing

    private var command: String {
        Bundle.main.executableURL?.path ?? "/Applications/Magpie.app/Contents/MacOS/Magpie"
    }

    private var claudeConfig: String {
        let config = ["mcpServers": ["magpie": ["command": command, "args": ["--mcp-stdio"]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private var tunnelCommands: String {
        let mcpCommand = "\(shellQuote(command)) --mcp-stdio"
        return """
        tunnel-client init --sample sample_mcp_stdio_local \\
          --profile magpie --tunnel-id YOUR_TUNNEL_ID \\
          --mcp-command \(shellQuote(mcpCommand))
        tunnel-client doctor --profile magpie --explain
        tunnel-client run --profile magpie
        """
    }

    var body: some View {
        Form {
            Section("Clipboard sharing") {
                Toggle("Enable MCP sharing", isOn: Binding(
                    get: { sharing.isEnabled },
                    set: sharing.setEnabled
                ))
                Text("Right-click a text clip in Magpie and choose Share with AI. Connected clients can read shared clips and may send the text to their AI provider. Turning sharing off or quitting Magpie clears your shared clips.")
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

            Section("Claude Desktop") {
                Text("In Claude Desktop, open Settings → Developer → Edit Config. Add the magpie entry to mcpServers, then quit and reopen Claude.")
                configuration(claudeConfig)
            }

            Section("ChatGPT") {
                Text("Create a private OpenAI Secure MCP Tunnel, install tunnel-client, and set its runtime key. Replace YOUR_TUNNEL_ID below.")
                Link("Set up an OpenAI Secure MCP Tunnel", destination: URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")!)
                configuration(tunnelCommands)
                Text("With the tunnel running, add a custom MCP server in ChatGPT Plugins. Choose Tunnel and No authentication, then install the plugin for your own account.")
                Link("Open ChatGPT Plugins", destination: URL(string: "https://chatgpt.com/plugins")!)
            }
        }
        .formStyle(.grouped)
    }

    private func configuration(_ value: String) -> some View {
        Text(value)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
