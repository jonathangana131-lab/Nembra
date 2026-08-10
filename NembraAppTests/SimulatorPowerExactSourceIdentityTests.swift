import XCTest
@testable import Nembra

/// Deliberately forwards a legitimate sealed Simulator source while presenting as
/// a different service instance. This proves that provider conformance + profile
/// metadata are not enough to establish source ownership at the app boundary.
private actor ForwardingSimulatorPowerService: ScooterService, SimulatorPowerEvidenceProvider {
    nonisolated let profile: VehicleProfile = .simulatorQA
    private let source: SimulatedScooterService

    init(source: SimulatedScooterService) {
        self.source = source
    }

    func speedTelemetryUpdates() async -> AsyncStream<SpeedTelemetrySample> {
        await source.speedTelemetryUpdates()
    }

    func stateUpdates() async -> AsyncStream<VehicleState> {
        await source.stateUpdates()
    }

    func snapshot() async -> VehicleState {
        await source.snapshot()
    }

    func connect() async {
        await source.connect()
    }

    func disconnect() async {
        await source.disconnect()
    }

    func setHeadlight(_ enabled: Bool) async throws {
        try await source.setHeadlight(enabled)
    }

    func setLocked(_ locked: Bool) async throws {
        try await source.setLocked(locked)
    }

    func setCruise(_ enabled: Bool) async throws {
        try await source.setCruise(enabled)
    }

    func setRideMode(_ mode: RideMode) async throws {
        try await source.setRideMode(mode)
    }

    func setStartMode(_ mode: StartMode) async throws {
        try await source.setStartMode(mode)
    }

    func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async throws {
        try await source.setSpeedLimit(kilometersPerHour: kilometersPerHour, slot: slot)
    }

    func simulatorPowerEvidenceUpdates() async -> AsyncStream<SimulatorPowerEvidenceAvailability> {
        await source.simulatorPowerEvidenceUpdates()
    }

    func simulatorPowerEvidenceSnapshot() async -> SimulatorPowerEvidenceAvailability {
        await source.simulatorPowerEvidenceSnapshot()
    }
}

final class SimulatorPowerExactSourceIdentityTests: XCTestCase {
    @MainActor
    func testForwardingProviderCannotBecomePositiveStoreSourceAuthority() async throws {
        let source = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let sealedAvailability = await source.simulatorPowerEvidenceSnapshot()
        XCTAssertEqual(sealedAvailability.currentness, .live)
        XCTAssertNotNil(sealedAvailability.observation)

        let wrapper = ForwardingSimulatorPowerService(source: source)
        let initialState = await wrapper.snapshot()
        let store = VehicleStore(
            service: wrapper,
            initialState: initialState,
            shouldAutoConnectOnStart: false,
            speedInstrumentInterpolationPolicy: .simulatorQA
        )

        // The exact source actor, not protocol conformance or profile metadata,
        // must own positive Simulator propulsion authority.
        XCTAssertFalse(
            store.hasSimulatorPowerEvidenceSource,
            "A forwarding/wrapper provider must not inherit source authority from a real Simulator actor."
        )

        await store.start()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(store.simulatorPowerStoreProjection.currentness, .unavailable)
        XCTAssertNil(store.simulatorPowerStoreProjection.observation)
    }
}
