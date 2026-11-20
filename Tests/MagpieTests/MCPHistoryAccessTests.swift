import ClipboardEngine
import Foundation
import XCTest
@testable import Magpie

final class MCPHistoryAccessTests: XCTestCase {
    @MainActor
    func testMAG006FullHistoryAccessAndRevocationOverStdio() async throws {
        let home = URL(fileURLWithPath: "/private/tmp/mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let database = try DatabaseManager(directoryURL: home.appendingPathComponent("history"))
        let repo = ClipItemRepository(dbPool: database.dbPool)
        let suite = "MagpieMCP-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let address = MCPSocketAddress(directory: home.appendingPathComponent(".magpie-mcp-dev"))
        let access = MCPHistoryAccess(repository: repo, address: address, defaults: defaults)

        let text = "Synthetic magpie old clip 🪶 Café\n" + String(repeating: "sample text\n", count: 1_024)
        var oldest = ClipItem(contentText: text, createdAt: Date(timeIntervalSince1970: 0))
        try repo.insert(&oldest)
        for index in 1...72 {
            var newer = ClipItem(contentText: "Fixture clip \(index)", createdAt: Date(timeIntervalSince1970: Double(index)))
            try repo.insert(&newer)
        }
        access.restorePreference()
        XCTAssertFalse(access.isEnabled)
        let offline = try await exchange([call("search_clips")], home: home)
        XCTAssertEqual(try result(offline, at: 0)["isError"] as? Bool, true)

        access.setEnabled(true)
        let deadline = Date().addingTimeInterval(5)
        while access.status == .starting && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(access.status, .ready)
        XCTAssertTrue(address.isPrivate)
        XCTAssertTrue(defaults.bool(forKey: MCPHistoryAccess.preferenceKey))

        var file = ClipItem(contentFilePath: "/tmp/synthetic-first.txt",
                            contentFilePathsJSON: #"["/tmp/synthetic-first.txt","/tmp/synthetic-second.txt"]"#,
                            contentType: "filePath")
        try repo.insert(&file)
        var image = ClipItem(contentImageData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jPXsAAAAASUVORK5CYII="),
                             contentType: "image", previewText: "[Image]")
        try repo.insert(&image)
        var rich = ClipItem(contentRichData: Data(#"{\rtf1\ansi Rich fixture text}"#.utf8),
                            contentType: "richText", previewText: "Rich fixture text")
        try repo.insert(&rich)
        let largePrefix = String(repeating: "\u{0001}", count: 16_384)
        var long = ClipItem(contentText: largePrefix + "Large fixture end 🪶", previewText: "Long fixture")
        try repo.insert(&long)

        let listing = try await exchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"regression","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            call("search_clips", arguments: #"{"query":"CAFÉ"}"#),
            call("search_clips", arguments: #"{"query":"synthetic-second"}"#),
            call("search_clips", arguments: #"{"query":"[Image]"}"#),
            call("search_clips", arguments: #"{"query":"Rich fixture"}"#),
            call("search_clips", arguments: #"{"query":"Large fixture end"}"#),
            call("search_clips"),
            call("search_shared_clips", arguments: #"{"offset":60}"#),
            call("search_clips", arguments: #"{"offset":true}"#),
        ], home: home)
        XCTAssertEqual(listing.count, 10)
        XCTAssertEqual(try result(listing, at: 0)["protocolVersion"] as? String, "2025-06-18")
        let tools = try XCTUnwrap(try result(listing, at: 1)["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["search_clips", "get_clip"])
        XCTAssertTrue(tools.allSatisfy { ($0["annotations"] as? [String: Bool])?["readOnlyHint"] == true })
        let oldPreview = try searchResults(try result(listing, at: 2))
        let oldID = try XCTUnwrap(oldPreview.first?["id"])
        XCTAssertEqual(oldPreview.first?["preview"]?.unicodeScalars.count, 200)
        XCTAssertEqual(try searchPayload(try result(listing, at: 7))["nextOffset"] as? Int, 20)
        XCTAssertEqual(try searchResults(try result(listing, at: 8)).last?["id"], oldID)
        XCTAssertEqual(try result(listing, at: 9)["isError"] as? Bool, true)

        let fetch = call("get_clip", arguments: #"{"id":"\#(oldID)"}"#)
        let types = try (3...6).map { index in
            try XCTUnwrap(searchResults(try result(listing, at: index)).first?["id"])
        }
        let fetchCount = 12
        let contents = try await exchange(Array(repeating: fetch, count: fetchCount) + types.map {
            call("get_clip", arguments: #"{"id":"\#($0)"}"#)
        } + [
            call("get_clip", arguments: #"{"id":"\#(types[3])","offset":16384}"#),
            call("get_shared_clip", arguments: #"{"id":"\#(oldID)"}"#),
        ], home: home)
        for index in 0..<fetchCount {
            XCTAssertEqual(try responseText(try result(contents, at: index)), text)
        }
        let fileJSON = try responseText(try result(contents, at: fetchCount))
        let paths = try JSONSerialization.jsonObject(with: Data(fileJSON.utf8)) as? [String: [String]]
        XCTAssertEqual(paths?["paths"], file.filePaths)
        let imageContent = try XCTUnwrap((try result(contents, at: fetchCount + 1)["content"] as? [[String: String]])?.first)
        XCTAssertEqual(imageContent["mimeType"], "image/png")
        XCTAssertEqual(imageContent["data"].flatMap { Data(base64Encoded: $0) }, image.contentImageData)
        XCTAssertEqual(try responseText(try result(contents, at: fetchCount + 2)), "Rich fixture text")
        let first = try result(contents, at: fetchCount + 3)
        XCTAssertEqual(try responseText(first), largePrefix)
        XCTAssertEqual((first["structuredContent"] as? [String: Int])?["nextOffset"], 16_384)
        XCTAssertEqual(try responseText(try result(contents, at: fetchCount + 4)), "Large fixture end 🪶")
        XCTAssertEqual(try responseText(try result(contents, at: fetchCount + 5)), text)

        try repo.delete(oldest)
        let deleted = try await exchange([fetch, call("search_clips", arguments: #"{"query":"MAGPIE OLD CLIP"}"#)], home: home)
        XCTAssertEqual(try result(deleted, at: 0)["isError"] as? Bool, true)
        XCTAssertTrue(try searchResults(try result(deleted, at: 1)).isEmpty)

        access.setEnabled(false)
        XCTAssertFalse(defaults.bool(forKey: MCPHistoryAccess.preferenceKey))
        let disabled = try await exchange([call("search_clips"), call("get_clip", arguments: #"{"id":"\#(types[0])"}"#)], home: home)
        XCTAssertEqual(try result(disabled, at: 0)["isError"] as? Bool, true)
        XCTAssertEqual(try result(disabled, at: 1)["isError"] as? Bool, true)
        access.setEnabled(true)
        let reenabled = try await exchange([call("search_clips", arguments: #"{"query":"synthetic-second"}"#)], home: home)
        XCTAssertEqual(try searchResults(try result(reenabled, at: 0)).first?["id"], types[0])

        let restartedHome = home.appendingPathComponent("restart")
        try FileManager.default.createDirectory(at: restartedHome, withIntermediateDirectories: false)
        let restarted = MCPHistoryAccess(repository: repo,
                                         address: .init(directory: restartedHome.appendingPathComponent(".magpie-mcp-dev")),
                                         defaults: defaults)
        restarted.restorePreference()
        XCTAssertTrue(restarted.isEnabled)
        let restartDeadline = Date().addingTimeInterval(5)
        while restarted.status == .starting && Date() < restartDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(restarted.status, .ready)
        let restored = try await exchange([call("search_clips", arguments: #"{"query":"synthetic-second"}"#)],
                                          home: restartedHome)
        XCTAssertEqual(try searchResults(try result(restored, at: 0)).first?["id"], types[0])
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
            #"{"jsonrpc":"2.0","id":5,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#,
            #"{"jsonrpc":"2.0","id":6,"method":"tools/list"}"#,
        ], home: home)
        XCTAssertEqual(replies.count, 6)
        XCTAssertEqual((replies.first?["error"] as? [String: Any])?["code"] as? Int, -32700)
        let discovery = try result(replies, at: 1)
        XCTAssertEqual(discovery["resultType"] as? String, "complete")
        XCTAssertEqual(discovery["ttlMs"] as? Int, 0)
        XCTAssertEqual(discovery["cacheScope"] as? String, "private")
        XCTAssertTrue((discovery["supportedVersions"] as? [String])?.contains("2026-07-28") == true)
        XCTAssertEqual((replies.dropFirst(2).first?["error"] as? [String: Any])?["code"] as? Int, -32022)
        XCTAssertEqual((replies.dropFirst(3).first?["error"] as? [String: Any])?["code"] as? Int, -32602)
        let modernTools = try result(replies, at: 4)
        let legacyTools = try result(replies, at: 5)
        XCTAssertEqual(modernTools["resultType"] as? String, "complete")
        XCTAssertEqual(modernTools["ttlMs"] as? Int, 0)
        XCTAssertEqual(modernTools["cacheScope"] as? String, "private")
        XCTAssertNil(legacyTools["ttlMs"])
        XCTAssertNil(legacyTools["cacheScope"])
        XCTAssertEqual((modernTools["tools"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((legacyTools["tools"] as? [[String: Any]])?.count, 2)
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
        try XCTUnwrap(try searchPayload(result)["clips"] as? [[String: String]])
    }

    private func searchPayload(_ result: [String: Any]) throws -> [String: Any] {
        let payload = try JSONSerialization.jsonObject(with: Data(responseText(result).utf8))
        return try XCTUnwrap(payload as? [String: Any])
    }
}
