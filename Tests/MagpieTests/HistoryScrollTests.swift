import AppKit
import ClipboardEngine
import SwiftUI
import XCTest
@testable import Magpie

final class HistoryScrollTests: XCTestCase {
    @MainActor
    func testMAG007SwiftUIScrollLoadsOlderPagesOnDemand() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MagpieHistoryScroll-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try DatabaseManager(directoryURL: directory)
        defer { try? database.dbPool.close() }
        let repo = ClipItemRepository(dbPool: database.dbPool)
        let total = 1_207
        let png = try samplePNG()
        for index in 0..<total {
            var clip = ClipItem(
                contentText: index == 0 ? "Oldest synthetic clipboard item" : "Sample clip \(index)",
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
            if index > 0, index.isMultiple(of: 10) {
                clip.contentType = "image"
                clip.contentImageData = png
            }
            try repo.record(&clip, maxUnpinnedCount: 0)
        }

        let state = AppState(database: .success(database))
        _ = NSApplication.shared
        let controller = NSHostingController(rootView: ClipHistoryList()
            .environmentObject(state)
            .environmentObject(state.mcpSharing))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 360, height: 450))
        window.orderBack(nil)
        defer {
            state.closeHistory()
            window.close()
        }

        state.openHistory()
        guard await waitFor({ state.historyCount == total }) else {
            return XCTFail("History did not load the initial result count")
        }
        XCTAssertEqual(state.historyEntries.count, 60)

        let scrollView = try XCTUnwrap(findScrollView(in: controller.view))
        while state.hasMoreHistory {
            let prior = state.historyEntries.count
            let loadedNextPage = await waitFor {
                if state.historyEntries.count > prior { return true }
                // SwiftUI revises the document height as mixed-height rows
                // enter view. Keep scrolling to the current bottom until a page arrives.
                scrollToBottom(scrollView)
                return false
            }
            guard loadedNextPage else {
                return XCTFail("Scrolling reached \(prior) clips and did not load another page. "
                    + "Document: \(String(describing: scrollView.documentView?.bounds)). "
                    + "Visible: \(scrollView.documentVisibleRect).")
            }
            XCTAssertLessThanOrEqual(state.historyEntries.count - prior, 60)
        }
        XCTAssertEqual(state.historyEntries.count, total)
        XCTAssertEqual(state.historyEntries.last?.previewText, "Oldest synthetic clipboard item")
        XCTAssertEqual(Set(state.historyEntries.map(\.id)).count, total)

        let thumbnail = await state.thumbnail(for: 1_201)
        XCTAssertEqual(thumbnail?.width, 320)
        XCTAssertEqual(thumbnail?.height, 160)
        state.togglePin(id: 1)
        guard await waitFor({ state.historyEntries.first?.id == 1 }) else {
            return XCTFail("Pinning the oldest clip did not reorder the loaded history")
        }
        XCTAssertEqual(state.historyEntries.count, total)

        state.searchText = "a query that does not match"
        state.searchText = "Oldest synthetic clipboard item"
        guard await waitFor({ state.historyCount == 1 }) else {
            return XCTFail("Search did not find the oldest clip")
        }
        XCTAssertEqual(state.historyEntries.map(\.id), [1])
    }

    @MainActor
    private func scrollToBottom(_ scrollView: NSScrollView) {
        scrollView.layoutSubtreeIfNeeded()
        guard let document = scrollView.documentView,
              document.bounds.height > scrollView.contentView.bounds.height else { return }
        let bottom = document.isFlipped
            ? document.bounds.maxY - scrollView.contentView.bounds.height
            : document.bounds.minY
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func samplePNG() throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 640,
            height: 320,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return condition()
    }

    @MainActor
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) { return scrollView }
        }
        return nil
    }
}
