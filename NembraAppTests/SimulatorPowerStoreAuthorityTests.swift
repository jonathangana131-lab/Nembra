import XCTest
@testable import Nembra

final class SimulatorPowerStoreAuthorityTests: XCTestCase {
    func testSealedLiveSourceProjectsLiveOnlyWhileTransportConnected() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let source = await service.simulatorPowerEvidenceSnapshot()
        XCTAssertEqual(source.currentness, .live)
        let sourceObservation = try XCTUnwrap(source.observation)

        var authority = SimulatorPowerStoreAuthority()
        authority.applySource(source, transportIsConnected: true)

        XCTAssertEqual(authority.projection.currentness, .live)
        XCTAssertEqual(authority.projection.observation, sourceObservation)

        authority.transportBecameUnavailable()
        XCTAssertEqual(authority.projection.currentness, .retained)
        XCTAssertEqual(authority.projection.observation, sourceObservation)
    }

    func testDisconnectedTransportCannotPublishSealedLiveSourceAsLive() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let source = await service.simulatorPowerEvidenceSnapshot()
        let sourceObservation = try XCTUnwrap(source.observation)

        var authority = SimulatorPowerStoreAuthority()
        authority.applySource(source, transportIsConnected: false)

        XCTAssertEqual(authority.projection.currentness, .retained)
        XCTAssertEqual(authority.projection.observation, sourceObservation)
    }

    func testReconnectAloneCannotPromoteRetainedPower() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let initial = await service.simulatorPowerEvidenceSnapshot()
        let initialObservation = try XCTUnwrap(initial.observation)

        await service.simulateConnectionDrop()
        let dropped = await service.simulatorPowerEvidenceSnapshot()
        XCTAssertEqual(dropped.currentness, .retained)
        XCTAssertEqual(dropped.observation, initialObservation)

        var authority = SimulatorPowerStoreAuthority()
        authority.applySource(dropped, transportIsConnected: false)
        XCTAssertEqual(authority.projection.currentness, .retained)

        await service.connect()
        let reconnected = await service.simulatorPowerEvidenceSnapshot()
        XCTAssertEqual((await service.snapshot()).connection, .connected)
        XCTAssertEqual(reconnected.currentness, .retained)
        XCTAssertEqual(reconnected.observation, initialObservation)

        authority.applySource(reconnected, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .retained)
        XCTAssertEqual(authority.projection.observation, initialObservation)
    }

    func testFreshSourceReceiptAfterReconnectCanPromoteLive() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let initial = await service.simulatorPowerEvidenceSnapshot()
        let initialObservation = try XCTUnwrap(initial.observation)

        await service.simulateConnectionDrop()
        await service.connect()
        let retained = await service.simulatorPowerEvidenceSnapshot()

        var authority = SimulatorPowerStoreAuthority()
        authority.applySource(retained, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .retained)

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 0)
        let refreshed = await service.simulatorPowerEvidenceSnapshot()
        XCTAssertEqual(refreshed.currentness, .live)
        let refreshedObservation = try XCTUnwrap(refreshed.observation)
        XCTAssertEqual(refreshedObservation.watts, initialObservation.watts)
        XCTAssertGreaterThan(refreshedObservation.receiptSequenceNumber, initialObservation.receiptSequenceNumber)
        XCTAssertGreaterThan(refreshedObservation.continuityGeneration, initialObservation.continuityGeneration)

        authority.applySource(refreshed, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .live)
        XCTAssertEqual(authority.projection.observation, refreshedObservation)
    }

    func testSourceTerminationFailsCompletelyClosed() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let source = await service.simulatorPowerEvidenceSnapshot()

        var authority = SimulatorPowerStoreAuthority()
        authority.applySource(source, transportIsConnected: true)
        XCTAssertEqual(authority.projection.currentness, .live)

        authority.sourceBecameUnavailable()
        XCTAssertEqual(authority.projection, .unavailable)
    }

    func testSourceOwnedRetainedReceiptRemainsByteIdenticalThroughTransportVeto() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = await service.simulatorPowerEvidenceSnapshot()
        let liveObservation = try XCTUnwrap(live.observation)

        var authority = SimulatorPowerStoreAuthority()
        authority.applySource(live, transportIsConnected: true)
        authority.transportBecameUnavailable()

        let retained = authority.projection
        XCTAssertEqual(retained.currentness, .retained)
        XCTAssertEqual(retained.observation?.watts, liveObservation.watts)
        XCTAssertEqual(retained.observation?.receiptSequenceNumber, liveObservation.receiptSequenceNumber)
        XCTAssertEqual(retained.observation?.receivedAtUptimeNanoseconds, liveObservation.receivedAtUptimeNanoseconds)
        XCTAssertEqual(retained.observation?.continuityGeneration, liveObservation.continuityGeneration)
    }
}
