import ClipboardEngine
import Combine
import Foundation
import Network

@MainActor
final class MCPHistoryAccess: ObservableObject {
    static let preferenceKey = "mcpClipboardHistoryAccess"

    enum Status: Equatable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var status = Status.idle

    private let repository: ClipItemRepository?
    private let address: MCPSocketAddress
    private let defaults: UserDefaults
    private var server: MCPLocalServer?
    private var accessRevision = 0

    init(repository: ClipItemRepository?, address: MCPSocketAddress = .current, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.address = address
        self.defaults = defaults
    }

    func restorePreference() {
        setEnabled(defaults.bool(forKey: Self.preferenceKey))
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        defaults.set(enabled, forKey: Self.preferenceKey)
        isEnabled = enabled
        accessRevision &+= 1
        guard enabled, server == nil else { return }
        guard repository != nil else {
            status = .failed("Clipboard history is unavailable.")
            return
        }
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

    private func respond(to request: Data) async -> Data? {
        guard isAvailable, let repository else { return MCPProtocol.respond(to: request) }
        let revision = accessRevision
        let response = await Task.detached {
            MCPProtocol.respond(to: request, repository: repository)
        }.value
        guard isAvailable, revision == accessRevision else { return MCPProtocol.respond(to: request) }
        return response
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
        accessRevision &+= 1
        status = .failed(error.localizedDescription)
    }
}
