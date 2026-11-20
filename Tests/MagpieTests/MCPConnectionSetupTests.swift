import Foundation
import XCTest
@testable import Magpie

final class MCPConnectionSetupTests: XCTestCase {
    func testMAG008ClaudeExtensionPackagesTheCurrentMagpiePath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MagpieConnection-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = URL(fileURLWithPath: "/Applications/Test Folder's ${__dirname}/Magpie.app/Contents/MacOS/Magpie")
        let installer = try MCPConnectionSetup.claudeExtension(
            executable: executable, version: "1.2.3", cacheDirectory: directory
        )
        XCTAssertEqual(installer.lastPathComponent, "Magpie.mcpb")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Magpie.mcpb"])

        let manifest = try json(from: extract("manifest.json", from: installer))
        let server = try XCTUnwrap(manifest["server"] as? [String: Any])
        let config = try XCTUnwrap(server["mcp_config"] as? [String: Any])
        XCTAssertEqual(manifest["manifest_version"] as? String, "0.3")
        XCTAssertEqual(manifest["version"] as? String, "1.2.3")
        XCTAssertEqual(manifest["tools_generated"] as? Bool, true)
        XCTAssertEqual(server["type"] as? String, "node")
        XCTAssertEqual(server["entry_point"] as? String, "server.js")
        XCTAssertEqual(config["args"] as? [String], ["${__dirname}/server.js"])
        XCTAssertEqual(try json(from: extract("bridge.json", from: installer))["executable"] as? String, executable.path)
        XCTAssertTrue(try String(decoding: extract("server.js", from: installer), as: UTF8.self).contains("--mcp-stdio"))

        let moved = URL(fileURLWithPath: "/Applications/Magpie.app/Contents/MacOS/Magpie")
        let replacement = try MCPConnectionSetup.claudeExtension(
            executable: moved, version: "1.2.3", cacheDirectory: directory
        )
        XCTAssertEqual(replacement, installer)
        XCTAssertEqual(try json(from: extract("bridge.json", from: replacement))["executable"] as? String, moved.path)
    }

    func testMAG008ChatGPTPromptUsesActualPathAndPrivateSetup() {
        let executable = URL(fileURLWithPath: "/Applications/Jason's Apps/Magpie")
        let prompt = MCPConnectionSetup.chatGPTSetupPrompt(executable: executable)
        XCTAssertTrue(prompt.contains(#"'/Applications/Jason'\''s Apps/Magpie' --mcp-stdio"#))
        XCTAssertTrue(prompt.contains("private OpenAI Secure MCP Tunnel"))
        XCTAssertTrue(prompt.contains("Keep credentials out of the chat"))
        XCTAssertTrue(prompt.contains("synthetic test clip"))
    }

    private func json(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func extract(_ name: String, from archive: URL) throws -> Data {
        let output = Pipe()
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", archive.path, name]
        unzip.standardOutput = output
        try unzip.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)
        return data
    }
}
