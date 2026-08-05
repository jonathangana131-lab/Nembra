import XCTest
@testable import Nembra

private actor AppCommandAcknowledgementGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

final class NembraAppTests: XCTestCase {
    func testMaxshotIdentityIsHumanReadable() {
        XCTAssertEqual(VehicleProfile.maxshotV1SPro.identity.displayName, "MAXSHOT V1S Pro")
        XCTAssertFalse(VehicleProfile.maxshotV1SPro.identity.displayName.contains("BLE"))
    }

    func testThirdSpeedLimitSlotRetainsVerified35KmhCeiling() {
        let capabilities = VehicleProfile.maxshotV1SPro.capabilities
        let range = capabilities.speedLimitRangesBySlot[.limit3]
        XCTAssertEqual(range?.maximumKilometersPerHour, 35)
        XCTAssertTrue(capabilities.verifiedSpeedLimitSlotByRideMode.isEmpty)
    }

    func testSimulationScenarioLaunchArgumentParsing() {
        let scenario = AppBootstrap.simulationScenario(
            arguments: ["Nembra", "--nembra-simulation=cold-disconnected"],
            environment: [:]
        )
        XCTAssertEqual(scenario, .coldDisconnected)
    }

    func testSimulationScenarioEnvironmentTakesPrecedence() {
        let scenario = AppBootstrap.simulationScenario(
            arguments: ["Nembra", "--nembra-simulation=riding"],
            environment: ["NEMBRA_SIMULATION_SCENARIO": "low-battery"]
        )
        XCTAssertEqual(scenario, .lowBattery)
    }

    func testBluetoothOffSimulationLaunchArgumentParsing() {
        let scenario = AppBootstrap.simulationScenario(
            arguments: ["Nembra", "--nembra-simulation=bluetooth-off"],
            environment: [:]
        )
        XCTAssertEqual(scenario, .bluetoothOff)
    }

    @MainActor
    func testOrdinaryLaunchDoesNotSilentlyEnterSimulation() async {
        let store = AppBootstrap.makeVehicleStore(arguments: ["Nembra"], environment: [:])
        await store.start()
        XCTAssertEqual(store.state.connection, .disconnected)
        XCTAssertEqual(store.state.connectionIssue, .unsupportedConfiguration)
        XCTAssertNil(store.state.speedKilometersPerHour)
        XCTAssertNil(store.state.batteryPercent)
    }

    @MainActor
    func testVehicleStoreSerializesStateChangingCommands() async {
        let initialState = SimulatedScooterService.state(for: .connectedStopped)
        let gate = AppCommandAcknowledgementGate()
        let service = SimulatedScooterService(
            initialState: initialState,
            commandAcknowledgementGate: {
                await gate.waitForRelease()
            }
        )
        let store = VehicleStore(
            service: service,
            initialState: initialState,
            shouldAutoConnectOnStart: false
        )
        await store.start()

        let firstCommand = Task { await store.setHeadlight(true) }
        await gate.waitUntilEntered()
        XCTAssertTrue(store.isVehicleCommandPending)

        await store.setCruise(true)
        await gate.release()
        await firstCommand.value

        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.isHeadlightOn, true)
        XCTAssertEqual(snapshot.isCruiseEnabled, false)
        XCTAssertFalse(store.isVehicleCommandPending)
    }
}
