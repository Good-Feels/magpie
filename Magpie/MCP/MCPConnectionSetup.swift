import Foundation

enum MCPConnectionSetup {
    static func claudeExtension(executable: URL, version: String, cacheDirectory: URL) throws -> URL {
        let files = FileManager.default
        let staging = cacheDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }

        let manifest: [String: Any] = [
            "manifest_version": "0.3",
            "name": "magpie-clipboard",
            "display_name": "Magpie",
            "version": version,
            "description": "Search and read text clips you choose to share from Magpie.",
            "author": ["name": "Good Feels Inc"],
            "homepage": "https://github.com/Good-Feels/magpie",
            "compatibility": ["platforms": ["darwin"]],
            "tools_generated": true,
            "server": [
                "type": "node",
                "entry_point": "server.js",
                "mcp_config": [
                    "command": "node",
                    "args": ["${__dirname}/server.js"],
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: staging.appendingPathComponent("manifest.json"))
        // The path lives in JSON, outside Claude's manifest variable substitution.
        try JSONSerialization.data(withJSONObject: ["executable": executable.path])
            .write(to: staging.appendingPathComponent("bridge.json"))
        try launcher.write(to: staging.appendingPathComponent("server.js"), atomically: true, encoding: .utf8)

        let archive = staging.appendingPathComponent("Magpie.mcpb")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = staging
        zip.arguments = ["-q", "-X", archive.path, "manifest.json", "bridge.json", "server.js"]
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }

        // Claude may read the archive after the open request returns.
        let installer = cacheDirectory.appendingPathComponent("Magpie.mcpb")
        try Data(contentsOf: archive).write(to: installer, options: .atomic)
        return installer
    }

    static func chatGPTSetupPrompt(executable: URL) -> String {
        let path = executable.path.replacingOccurrences(of: "'", with: "'\\''")
        return """
        Help me connect Magpie to ChatGPT on this Mac using a private OpenAI Secure MCP Tunnel. Use a local Codex session so you can run the tunnel client on this Mac. Run the following MCP stdio command on this Mac.

        '\(path)' --mcp-stdio

        Follow https://developers.openai.com/api/docs/guides/secure-mcp-tunnels. Check which OpenAI Platform organization and ChatGPT account or workspace I want to use. Use an existing tunnel only if it already belongs to this Magpie setup. Otherwise, guide me through creating a dedicated tunnel and connecting a personal Magpie plugin in ChatGPT. Ask me to complete any required account approvals and enter credentials locally using the official instructions. Keep credentials out of the chat and command arguments. Keep the connection private.

        When the plugin is connected, ask me to share a synthetic test clip from Magpie. Verify that ChatGPT can find and read that clip using Magpie’s search_shared_clips and get_shared_clip tools.
        """
    }

    private static let launcher = """
    const { spawn } = require("node:child_process");
    const { executable } = require("./bridge.json");

    const child = spawn(executable, ["--mcp-stdio"], { stdio: "pipe" });
    process.stdin.pipe(child.stdin);
    child.stdout.pipe(process.stdout);
    child.stderr.pipe(process.stderr);
    child.stdin.on("error", (error) => {
      if (error.code !== "EPIPE") console.error("Could not send a request to Magpie.");
    });
    child.on("error", () => {
      console.error("Could not start Magpie. If you moved it, reconnect from Magpie Settings.");
    });
    child.on("close", (code) => {
      process.stdin.unpipe(child.stdin);
      process.stdin.pause();
      process.exitCode = code ?? 1;
    });
    for (const signal of ["SIGINT", "SIGTERM"]) {
      process.on(signal, () => child.kill(signal));
    }
    """
}
