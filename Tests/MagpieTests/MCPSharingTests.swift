import ClipboardEngine
import Foundation
import XCTest
@testable import Magpie

final class MCPSharingTests: XCTestCase {
    @MainActor
    func testMAG006SharedTextCanBeReadAndRevokedOverStdio() async throws {
        let home = URL(fileURLWithPath: "/private/tmp/mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let address = MCPSocketAddress(directory: home.appendingPathComponent(".magpie-mcp-dev"))
        let sharing = MCPSharing(address: address)
        let text = "Synthetic magpie test 🪶\n" + String(repeating: "sample text\n", count: 1_024)
        let shared = ClipItem(id: 101, contentText: text, isPinned: true)
        let unshared = ClipItem(id: 102, contentText: "synthetic unshared text")
        let file = ClipItem(id: 103, contentText: "synthetic file", contentType: "filePath")

        XCTAssertFalse(sharing.isEnabled)
        sharing.toggle(shared)
        XCTAssertTrue(sharing.clips.isEmpty)
        let offline = try await exchange([call("search_shared_clips")], home: home)
        XCTAssertEqual(try result(offline, at: 0)["isError"] as? Bool, true)

        sharing.setEnabled(true)
        let deadline = Date().addingTimeInterval(5)
        while sharing.status == .starting && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(sharing.status, .ready)
        XCTAssertTrue(address.isPrivate)

        sharing.toggle(shared)
        sharing.toggle(file)
        sharing.retainClips(in: [shared, unshared, file])

        let listing = try await exchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"regression","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            call("search_shared_clips", arguments: #"{"query":"MAGPIE"}"#),
            call("search_shared_clips", arguments: #"{"query":"unshared"}"#),
        ], home: home)
        XCTAssertEqual(listing.count, 4)
        XCTAssertEqual(try result(listing, at: 0)["protocolVersion"] as? String, "2025-06-18")
        let tools = try XCTUnwrap(try result(listing, at: 1)["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["search_shared_clips", "get_shared_clip"])
        XCTAssertTrue(tools.allSatisfy { ($0["annotations"] as? [String: Bool])?["readOnlyHint"] == true })
        let previews = try searchResults(try result(listing, at: 2))
        XCTAssertEqual(previews.count, 1)
        let id = try XCTUnwrap(previews.first?["id"])
        XCTAssertEqual(previews.first?["preview"]?.unicodeScalars.count, 200)
        XCTAssertTrue(try searchResults(try result(listing, at: 3)).isEmpty)

        let fetch = call("get_shared_clip", arguments: #"{"id":"\#(id)"}"#)
        let fetchCount = 12
        let contents = try await exchange(Array(repeating: fetch, count: fetchCount) + [call("search_shared_clips")], home: home)
        for index in 0..<fetchCount {
            XCTAssertTrue(try responseText(try result(contents, at: index)) == text, "Incomplete fetch at index \(index)")
        }
        XCTAssertEqual(try searchResults(try result(contents, at: fetchCount)).count, 1)

        sharing.toggle(shared)
        let revoked = try await exchange([fetch], home: home)
        XCTAssertEqual(try result(revoked, at: 0)["isError"] as? Bool, true)

        sharing.toggle(shared)
        XCTAssertNotEqual(sharing.clips.first?.id.uuidString, id)
        sharing.retainClips(in: [unshared, file])
        let deleted = try await exchange([call("search_shared_clips")], home: home)
        XCTAssertTrue(try searchResults(try result(deleted, at: 0)).isEmpty)

        sharing.toggle(shared)
        sharing.setEnabled(false)
        XCTAssertTrue(sharing.clips.isEmpty)
        let disabled = try await exchange([call("search_shared_clips")], home: home)
        XCTAssertEqual(try result(disabled, at: 0)["isError"] as? Bool, true)
        sharing.setEnabled(true)
        let reenabled = try await exchange([call("search_shared_clips")], home: home)
        XCTAssertTrue(try searchResults(try result(reenabled, at: 0)).isEmpty)
    }

    @MainActor
    func testMAG006ModernDiscoveryAndInvalidRequestsOverStdio() async throws {
        let home = URL(fileURLWithPath: "/private/tmp/mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }

        let replies = try await exchange([
            "{",
            #"{"jsonrpc":"2.0","id":"modern","method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2027-01-01"}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"delete_clip"}}"#,
        ], home: home)
        XCTAssertEqual(replies.count, 4)
        XCTAssertEqual((replies.first?["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertEqual(try result(replies, at: 1)["resultType"] as? String, "complete")
        XCTAssertTrue((try result(replies, at: 1)["supportedVersions"] as? [String])?.contains("2026-07-28") == true)
        XCTAssertEqual((replies.dropFirst(2).first?["error"] as? [String: Any])?["code"] as? Int, -32022)
        XCTAssertEqual((replies.last?["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    private func call(_ tool: String, arguments: String = "{}") -> String {
        #"{"jsonrpc":"2.0","id":"tool","method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#
    }

    @MainActor
    private func exchange(_ lines: [String], home: URL) async throws -> [[String: Any]] {
        let app = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("Magpie")
        let input = home.appendingPathComponent("input")
        let output = home.appendingPathComponent("output")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: input)
        try Data().write(to: output)
        let stdin = try FileHandle(forReadingFrom: input)
        let stdout = try FileHandle(forWritingTo: output)
        defer {
            try? stdin.close()
            try? stdout.close()
        }

        let completed = expectation(description: "Magpie stdio process exits")
        let process = Process()
        process.executableURL = app
        process.arguments = ["--mcp-stdio"]
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path]) { _, testHome in testHome }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.terminationHandler = { _ in completed.fulfill() }
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        await fulfillment(of: [completed], timeout: 10)
        guard !process.isRunning else { throw CocoaError(.executableLoad) }
        XCTAssertEqual(process.terminationStatus, 0)
        return try Data(contentsOf: output).split(separator: 10).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }

    private func result(_ replies: [[String: Any]], at index: Int) throws -> [String: Any] {
        try XCTUnwrap(replies.dropFirst(index).first?["result"] as? [String: Any])
    }

    private func responseText(_ result: [String: Any]) throws -> String {
        try XCTUnwrap((result["content"] as? [[String: String]])?.first?["text"])
    }

    private func searchResults(_ result: [String: Any]) throws -> [[String: String]] {
        let payload = try JSONSerialization.jsonObject(with: Data(responseText(result).utf8))
        return try XCTUnwrap((payload as? [String: Any])?["clips"] as? [[String: String]])
    }
}
