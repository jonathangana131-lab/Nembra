import Foundation
import Observation

@MainActor
@Observable
final class RideStore {
    typealias RuntimeFactory = @Sendable () async throws -> RideApplicationRuntime

    private(set) var snapshot = RideApplicationRuntimeSnapshot(
        phase: .idle,
        pendingCompletedRideID: nil,
        failure: nil
    )
    private(set) var isEnabled: Bool
    private(set) var didStart = false
    var lastErrorMessage: String?

    @ObservationIgnored private let runtimeFactory: RuntimeFactory?
    @ObservationIgnored private var runtime: RideApplicationRuntime?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(runtimeFactory: RuntimeFactory?) {
        self.runtimeFactory = runtimeFactory
        self.isEnabled = runtimeFactory != nil
    }

    deinit {
        updatesTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        guard let runtimeFactory else { return }

        do {
            let runtime = try await runtimeFactory()
            self.runtime = runtime
            snapshot = await runtime.snapshot()

            let stream = await runtime.updates()
            updatesTask = Task { [weak self] in
                for await value in stream {
                    guard let self, !Task.isCancelled else { break }
                    self.snapshot = value
                }
            }

            try await runtime.start()
            snapshot = await runtime.snapshot()
        } catch {
            lastErrorMessage = "Automatic ride tracking could not start safely."
        }
    }

    var presentation: RidePresentation {
        guard isEnabled else { return .unavailable }
        if snapshot.failure != nil { return .blocked }
        if snapshot.pendingCompletedRideID != nil { return .saving }

        switch snapshot.phase {
        case .idle, .candidate:
            return .idle
        case .active:
            return .active
        case .temporarilyDisconnected:
            return .reconnecting
        case .endingCandidate:
            return .finishing
        }
    }

    var activeSessionID: UUID? {
        switch snapshot.phase {
        case let .active(session):
            session.id
        case let .temporarilyDisconnected(disconnected):
            disconnected.session.id
        case let .endingCandidate(ending):
            ending.session.id
        case .idle, .candidate:
            nil
        }
    }

    enum RidePresentation: Equatable {
        case unavailable
        case idle
        case active
        case reconnecting
        case finishing
        case saving
        case blocked

        var isVisibleOnHome: Bool {
            switch self {
            case .active, .reconnecting, .finishing, .saving, .blocked:
                true
            case .unavailable, .idle:
                false
            }
        }
    }
}
