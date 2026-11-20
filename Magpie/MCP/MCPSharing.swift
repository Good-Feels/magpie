import ClipboardEngine
import Combine
import Foundation
import Network

@MainActor
final class MCPSharing: ObservableObject {
    static let clipLimit = 50

    enum Status: Equatable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var status = Status.idle
    @Published private(set) var clips: [MCPSharedClip] = []

    private let address: MCPSocketAddress
    private var server: MCPLocalServer?

    init(address: MCPSocketAddress = .current) {
        self.address = address
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard enabled else {
            clear()
            return
        }
        guard server == nil else { return }
        status = .starting
        do {
            server = try MCPLocalServer(address: address, onState: { [weak self] state in
                Task { @MainActor in self?.handle(state) }
            }, respond: { [weak self] request in
                await self?.respond(to: request)
            })
        } catch {
            fail(error)
        }
    }

    var isAvailable: Bool { isEnabled && status == .ready }

    func canToggle(_ entry: ClipHistoryEntry) -> Bool {
        isAvailable && (contains(entry.id) || (
            clips.count < Self.clipLimit
            && Self.canShareText(type: entry.contentType, byteCount: entry.textByteCount)
        ))
    }

    private static func canShareText(type: String, byteCount: Int?) -> Bool {
        (type == "text" || type == "richText") && (1...16_384).contains(byteCount ?? 0)
    }

    func contains(_ historyID: Int64?) -> Bool {
        clips.contains { $0.historyID == historyID }
    }

    func toggle(_ item: ClipItem) {
        guard isAvailable, let id = item.id else { return }
        if contains(id) {
            clips.removeAll { $0.historyID == id }
        } else if clips.count < Self.clipLimit, let text = item.contentText,
                  Self.canShareText(type: item.contentType, byteCount: text.utf8.count) {
            clips.append(MCPSharedClip(historyID: id, text: text, createdAt: item.createdAt))
        }
    }

    func retainClips(withIDs ids: Set<Int64>) {
        guard !clips.isEmpty else { return }
        let retained = clips.filter { ids.contains($0.historyID) }
        if retained.count != clips.count { clips = retained }
    }

    func clear() {
        if !clips.isEmpty { clips = [] }
    }

    private func respond(to request: Data) -> Data? {
        MCPProtocol.respond(to: request, clips: isAvailable ? clips : nil)
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            status = .ready
        case .failed(let error):
            fail(error)
        default:
            break
        }
    }

    private func fail(_ error: Error) {
        server = nil
        isEnabled = false
        clear()
        status = .failed(error.localizedDescription)
    }
}
