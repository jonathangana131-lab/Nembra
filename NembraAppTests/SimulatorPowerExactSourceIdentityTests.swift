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

    func testCapturedPreDisconnectLiveReceiptCannotReplayLiveAfterFence() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let capturedLive = await service.simulatorPowerEvidenceSnapshot()
        XCTAssertEqual(capturedLive.currentness, .live)
        let capturedObservation = try XCTUnwrap(capturedLive.observation)

        var authority = SimulatorPowerReceiptFenceAuthority()
        authority.applySource(capturedLive, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .live)

        authority.transportBecameUnavailable()
        XCTAssertEqual(authority.projection.currentness, .retained)
        XCTAssertEqual(authority.projection.observation, capturedObservation)

        // Hostile ordering: the exact authentic LIVE receipt that existed before
        // transport loss arrives again after aggregate reconnect. Authenticity does
        // not make it fresh; the negative receipt fence must keep it retained.
        authority.applySource(capturedLive, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .retained)
        XCTAssertEqual(authority.projection.observation, capturedObservation)
    }

    func testStrictlyNewerSourceReceiptCanReopenLiveAfterFence() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let initialLive = await service.simulatorPowerEvidenceSnapshot()
        let initialObservation = try XCTUnwrap(initialLive.observation)

        var authority = SimulatorPowerReceiptFenceAuthority()
        authority.applySource(initialLive, transportIsConnected: true)
        authority.transportBecameUnavailable()

        await service.simulateConnectionDrop()
        await service.connect()
        let retained = await service.simulatorPowerEvidenceSnapshot()
        XCTAssertEqual(retained.currentness, .retained)
        authority.applySource(retained, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .retained)

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 0)
        let refreshedLive = await service.simulatorPowerEvidenceSnapshot()
        XCTAssertEqual(refreshedLive.currentness, .live)
        let refreshedObservation = try XCTUnwrap(refreshedLive.observation)
        XCTAssertGreaterThan(
            refreshedObservation.continuityGeneration,
            initialObservation.continuityGeneration
        )

        authority.applySource(refreshedLive, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .live)
        XCTAssertEqual(authority.projection.observation, refreshedObservation)
    }

    func testDelayedOlderLiveCannotEraseNewerLiveProjection() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let olderLive = await service.simulatorPowerEvidenceSnapshot()
        let olderObservation = try XCTUnwrap(olderLive.observation)

        await service.simulateRide(speedKilometersPerHour: 17.9, elapsedSeconds: 0)
        let newerLive = await service.simulatorPowerEvidenceSnapshot()
        let newerObservation = try XCTUnwrap(newerLive.observation)
        XCTAssertGreaterThan(
            newerObservation.receiptSequenceNumber,
            olderObservation.receiptSequenceNumber
        )

        var authority = SimulatorPowerReceiptFenceAuthority()
        authority.applySource(newerLive, transportIsConnected: true)
        XCTAssertEqual(authority.projection.observation, newerObservation)

        authority.applySource(olderLive, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .live)
        XCTAssertEqual(authority.projection.observation, newerObservation)
    }

    func testSourceTerminationFencesOldLiveReceipt() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = await service.simulatorPowerEvidenceSnapshot()

        var authority = SimulatorPowerReceiptFenceAuthority()
        authority.applySource(live, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .live)

        authority.sourceBecameUnavailable()
        XCTAssertEqual(authority.projection, .unavailable)

        // An already queued callback remains authentic source evidence, but cannot
        // resurrect Store ownership after the provider has terminated.
        authority.applySource(live, transportIsConnected: true)
        XCTAssertEqual(authority.projection, .unavailable)
    }
}
