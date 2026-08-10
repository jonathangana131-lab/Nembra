import XCTest
@testable import Nembra

/// Adversarial app-module fake: this service can satisfy the public Simulator power
/// provider protocol and can construct a syntactically valid observation because the
/// package sources are also direct-compiled into the Nembra app module.
///
/// It is deliberately *not* `SimulatedScooterService`, so production app authority
/// must reject it even though its profile/capability/value tuple looks plausible.
private actor ProtocolOnlySimulatorPowerService: ScooterService, SimulatorPowerEvidenceProvider {
    nonisolated let profile = VehicleProfile.simulatorQA

    private let currentState: VehicleState
    private let currentPowerAvailability: SimulatorPowerEvidenceAvailability

    init() throws {
        currentState = SimulatedScooterService.state(for: .riding)
        currentPowerAvailability = .live(try SimulatorPowerObservation(
            watts: 356,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 1
        ))
    }

    func stateUpdates() async -> AsyncStream<VehicleState> {
        let state = currentState
        return AsyncStream { continuation in
            continuation.yield(state)
            continuation.finish()
        }
    }

    func snapshot() async -> VehicleState {
        currentState
    }

    func speedTelemetryUpdates() async -> AsyncStream<SpeedTelemetrySample> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func simulatorPowerEvidenceUpdates() async -> AsyncStream<SimulatorPowerEvidenceAvailability> {
        let availability = currentPowerAvailability
        return AsyncStream { continuation in
            continuation.yield(availability)
            continuation.finish()
        }
    }

    func simulatorPowerEvidenceSnapshot() async -> SimulatorPowerEvidenceAvailability {
        currentPowerAvailability
    }

    func connect() async {}
    func disconnect() async {}

    func setHeadlight(_ enabled: Bool) async throws {}
    func setLocked(_ locked: Bool) async throws {}
    func setCruise(_ enabled: Bool) async throws {}
    func setRideMode(_ mode: RideMode) async throws {}
    func setStartMode(_ mode: StartMode) async throws {}
    func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async throws {}
}

final class VehicleStoreSimulatorPowerProvenanceTests: XCTestCase {
    @MainActor
    func testProtocolOnlyProviderCannotBecomeProductPowerAuthority() async throws {
        let service = try ProtocolOnlySimulatorPowerService()
        let initialState = await service.snapshot()
        let store = VehicleStore(
            service: service,
            initialState: initialState,
            shouldAutoConnectOnStart: false
        )

        // Positive Simulator propulsion authority must be bound to Nembra's actual
        // source owner, not merely to caller-conformable protocol shape. Otherwise a
        // same-module fake can wrap a constructed observation and enter product UI.
        XCTAssertFalse(store.hasSimulatorPowerEvidenceSource)

        await store.start()
        XCTAssertEqual(store.simulatorPowerEvidenceAvailability, .unavailable)
    }
}
