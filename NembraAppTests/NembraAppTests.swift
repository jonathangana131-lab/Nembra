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

    func testDashboardModePersonalityIsVisualOnlyAndDistinct() {
        let unknown = DashboardModePersonality.resolved(for: nil)
        let walk = DashboardModePersonality.resolved(for: .walk)
        let eco = DashboardModePersonality.resolved(for: .eco)
        let drive = DashboardModePersonality.resolved(for: .drive)
        let sport = DashboardModePersonality.resolved(for: .sport)

        XCTAssertNil(unknown.mode)
        XCTAssertEqual(walk.mode, .walk)
        XCTAssertEqual(eco.mode, .eco)
        XCTAssertEqual(drive.mode, .drive)
        XCTAssertEqual(sport.mode, .sport)

        XCTAssertLessThan(walk.speedScale, eco.speedScale)
        XCTAssertLessThan(eco.speedScale, drive.speedScale)
        XCTAssertLessThan(drive.speedScale, sport.speedScale)
        XCTAssertLessThan(walk.ambientOpacity, eco.ambientOpacity)
        XCTAssertLessThan(eco.ambientOpacity, drive.ambientOpacity)
        XCTAssertLessThan(drive.ambientOpacity, sport.ambientOpacity)

        // Mode personality is presentation state only. The verified MAXSHOT
        // protocol model must remain unmapped until real hardware proves a
        // relationship between ride modes and the three speed-limit slots.
        XCTAssertTrue(VehicleProfile.maxshotV1SPro.capabilities.verifiedSpeedLimitSlotByRideMode.isEmpty)
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
        XCTAssertEqual(store.speedInstrumentInterpolationPolicy, .disabled)
    }

    @MainActor
    func testExplicitSimulationInjectsQAInterpolationPolicy() {
        let store = AppBootstrap.makeVehicleStore(
            arguments: ["Nembra"],
            environment: ["NEMBRA_SIMULATION_SCENARIO": "riding"]
        )
        XCTAssertEqual(store.speedInstrumentInterpolationPolicy, .simulatorQA)
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

    @MainActor
    func testSpeedInstrumentUsesConfirmedVehicleStateUntilFreshRawTelemetryArrives() throws {
        let model = SpeedInstrumentModel()
        let frame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_000_000_000,
            fallbackConfirmedKilometersPerHour: 18.4
        ))

        XCTAssertEqual(frame.kilometersPerHour, 18.4, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .confirmedVehicleState)
        XCTAssertNil(frame.latestMeasuredKilometersPerHour)
        XCTAssertNil(model.latestMeasuredKilometersPerHour)
        XCTAssertEqual(model.measurementRevision, 0)
        XCTAssertTrue(model.permitsLiveConfirmedFallback)
    }

    @MainActor
    func testUncalibratedSpeedInstrumentSnapsEvenAcrossCloseMeasurements() throws {
        let model = SpeedInstrumentModel()
        model.accept(try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000))
        model.accept(try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000))

        let frame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_200_000_000,
            fallbackConfirmedKilometersPerHour: nil
        ))
        XCTAssertEqual(frame.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .measuredTelemetry)
        XCTAssertEqual(try XCTUnwrap(model.latestMeasuredKilometersPerHour), 20, accuracy: 0.000_1)
        XCTAssertFalse(model.isAnimationActive)
    }

    @MainActor
    func testQAProfileInterpolatesOnlyBetweenAuthoritativeMeasurements() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)

        model.accept(first)
        let firstFrame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_000_000_000,
            fallbackConfirmedKilometersPerHour: nil
        ))
        XCTAssertEqual(firstFrame.kilometersPerHour, 10, accuracy: 0.000_1)
        XCTAssertEqual(firstFrame.origin, .measuredTelemetry)

        model.accept(second)
        let midpoint = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_280_000_000,
            fallbackConfirmedKilometersPerHour: nil
        ))
        XCTAssertEqual(midpoint.kilometersPerHour, 15, accuracy: 0.000_1)
        XCTAssertEqual(midpoint.latestMeasuredKilometersPerHour, 20)
        XCTAssertEqual(midpoint.origin, .visuallyInterpolated)
        XCTAssertEqual(try XCTUnwrap(model.latestMeasuredKilometersPerHour), 20, accuracy: 0.000_1)

        let settled = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_400_000_000,
            fallbackConfirmedKilometersPerHour: nil
        ))
        XCTAssertEqual(settled.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(settled.origin, .measuredTelemetry)
    }

    @MainActor
    func testReduceMotionSnapsToLatestAuthoritativeSpeedWithoutMutatingInterpolation() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        model.accept(try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000))
        model.accept(try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000))
        let revision = model.measurementRevision

        let reducedMotionFrame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_280_000_000,
            fallbackConfirmedKilometersPerHour: nil,
            prefersReducedMotion: true
        ))
        XCTAssertEqual(reducedMotionFrame.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(reducedMotionFrame.latestMeasuredKilometersPerHour, 20)
        XCTAssertEqual(reducedMotionFrame.origin, .measuredTelemetry)
        XCTAssertEqual(model.measurementRevision, revision)

        let ordinaryFrame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_280_000_000,
            fallbackConfirmedKilometersPerHour: nil
        ))
        XCTAssertEqual(ordinaryFrame.kilometersPerHour, 15, accuracy: 0.000_1)
        XCTAssertEqual(ordinaryFrame.latestMeasuredKilometersPerHour, 20)
        XCTAssertEqual(ordinaryFrame.origin, .visuallyInterpolated)
        XCTAssertEqual(model.measurementRevision, revision)
    }

    @MainActor
    func testSpeedInstrumentRejectsStaleAndEstimatedSamples() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        model.accept(try speedSample(kilometersPerHour: 12, uptimeNanoseconds: 2_000_000_000))
        XCTAssertEqual(model.measurementRevision, 1)
        XCTAssertEqual(try XCTUnwrap(model.latestMeasuredKilometersPerHour), 12, accuracy: 0.000_1)

        model.accept(try speedSample(kilometersPerHour: 30, uptimeNanoseconds: 1_900_000_000))
        XCTAssertEqual(model.measurementRevision, 1)

        let estimate = try SpeedTelemetrySample(
            source: .motionAssist,
            provenance: .shortHorizonEstimate,
            metersPerSecond: 9,
            receivedAtUptimeNanoseconds: 2_100_000_000,
            receivedAtDate: Date(timeIntervalSince1970: 0)
        )
        model.accept(estimate)
        XCTAssertEqual(model.measurementRevision, 1)
        XCTAssertEqual(try XCTUnwrap(model.latestMeasuredKilometersPerHour), 12, accuracy: 0.000_1)

        let frame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 2_500_000_000,
            fallbackConfirmedKilometersPerHour: 99
        ))
        XCTAssertEqual(frame.kilometersPerHour, 12, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .measuredTelemetry)
    }

    @MainActor
    func testQAProfileSnapsAcrossLongTelemetryGap() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        model.accept(try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000))
        model.accept(try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 2_000_000_000))

        let frame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 2_000_000_000,
            fallbackConfirmedKilometersPerHour: nil
        ))
        XCTAssertEqual(frame.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .measuredTelemetry)
        XCTAssertFalse(model.isAnimationActive)
    }

    @MainActor
    func testStoppingObservationDropsRawAnchorButKeepsConfirmedFallbackEligible() throws {
        let model = SpeedInstrumentModel()
        model.accept(try speedSample(kilometersPerHour: 12, uptimeNanoseconds: 2_000_000_000))

        let liveRaw = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 2_000_000_000,
            fallbackConfirmedKilometersPerHour: 7
        ))
        XCTAssertEqual(liveRaw.kilometersPerHour, 12, accuracy: 0.000_1)
        XCTAssertEqual(liveRaw.origin, .measuredTelemetry)

        model.stop()

        XCTAssertNil(model.latestMeasurementSource)
        XCTAssertNil(model.latestMeasuredKilometersPerHour)
        XCTAssertFalse(model.isAnimationActive)
        XCTAssertTrue(model.permitsLiveConfirmedFallback)
        XCTAssertEqual(model.measurementRevision, 1)

        let resumedFallback = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 3_000_000_000,
            fallbackConfirmedKilometersPerHour: 7
        ))
        XCTAssertEqual(resumedFallback.kilometersPerHour, 7, accuracy: 0.000_1)
        XCTAssertEqual(resumedFallback.origin, .confirmedVehicleState)
    }

    @MainActor
    func testConnectionGapInvalidatesRawSpeedAndRejectsGapSamples() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        model.accept(try speedSample(kilometersPerHour: 12, uptimeNanoseconds: 2_000_000_000))
        XCTAssertEqual(model.measurementRevision, 1)
        XCTAssertEqual(try XCTUnwrap(model.latestMeasuredKilometersPerHour), 12, accuracy: 0.000_1)
        XCTAssertTrue(model.permitsLiveConfirmedFallback)

        model.setConnectionContinuityActive(false)
        XCTAssertNil(model.latestMeasurementSource)
        XCTAssertNil(model.latestMeasuredKilometersPerHour)
        XCTAssertFalse(model.isAnimationActive)
        XCTAssertFalse(model.permitsLiveConfirmedFallback)

        let retainedFallback = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 2_100_000_000,
            fallbackConfirmedKilometersPerHour: 7
        ))
        XCTAssertEqual(retainedFallback.kilometersPerHour, 7, accuracy: 0.000_1)
        XCTAssertEqual(retainedFallback.origin, .confirmedVehicleState)

        model.accept(try speedSample(kilometersPerHour: 30, uptimeNanoseconds: 3_000_000_000))
        XCTAssertEqual(model.measurementRevision, 1)
        XCTAssertNil(model.latestMeasuredKilometersPerHour)

        model.setConnectionContinuityActive(true)
        XCTAssertFalse(model.permitsLiveConfirmedFallback)
        model.accept(try speedSample(kilometersPerHour: 8, uptimeNanoseconds: 4_000_000_000))
        XCTAssertEqual(model.measurementRevision, 2)
        XCTAssertEqual(try XCTUnwrap(model.latestMeasuredKilometersPerHour), 8, accuracy: 0.000_1)
    }

    @MainActor
    func testConfirmedFallbackRemainsRetainedAcrossKnownReconnectGap() throws {
        XCTAssertEqual(
            try XCTUnwrap(DashboardSpeedInstrumentView.confirmedFallbackForPresentation(
                kilometersPerHour: 7,
                isRetained: false,
                isConnected: true,
                permitsLiveConfirmedFallback: true
            )),
            7,
            accuracy: 0.000_1
        )

        XCTAssertEqual(
            try XCTUnwrap(DashboardSpeedInstrumentView.confirmedFallbackForPresentation(
                kilometersPerHour: 7,
                isRetained: true,
                isConnected: false,
                permitsLiveConfirmedFallback: false
            )),
            7,
            accuracy: 0.000_1
        )

        XCTAssertNil(DashboardSpeedInstrumentView.confirmedFallbackForPresentation(
            kilometersPerHour: 7,
            isRetained: false,
            isConnected: true,
            permitsLiveConfirmedFallback: false
        ))
        XCTAssertNil(DashboardSpeedInstrumentView.confirmedFallbackForPresentation(
            kilometersPerHour: 7,
            isRetained: false,
            isConnected: false,
            permitsLiveConfirmedFallback: true
        ))
        XCTAssertNil(DashboardSpeedInstrumentView.confirmedFallbackForPresentation(
            kilometersPerHour: .nan,
            isRetained: true,
            isConnected: false,
            permitsLiveConfirmedFallback: false
        ))
    }

    @MainActor
    func testDashboardSpeedDisplayRejectsMalformedValuesInsteadOfManufacturingZero() throws {
        XCTAssertNil(DashboardSpeedInstrumentView.displayedValue(kilometersPerHour: nil, usesMetric: true))
        XCTAssertNil(DashboardSpeedInstrumentView.displayedValue(kilometersPerHour: -0.01, usesMetric: true))
        XCTAssertNil(DashboardSpeedInstrumentView.displayedValue(kilometersPerHour: .nan, usesMetric: true))
        XCTAssertNil(DashboardSpeedInstrumentView.displayedValue(kilometersPerHour: .infinity, usesMetric: true))
        XCTAssertNil(DashboardSpeedInstrumentView.displayedValue(kilometersPerHour: -.infinity, usesMetric: true))

        XCTAssertEqual(
            try XCTUnwrap(DashboardSpeedInstrumentView.displayedValue(kilometersPerHour: -0.0, usesMetric: true)),
            0,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(DashboardSpeedInstrumentView.displayedValue(kilometersPerHour: 10, usesMetric: false)),
            6.213_71,
            accuracy: 0.000_1
        )
    }

    @MainActor
    func testDashboardSpeedAccessibilityPreservesUnavailableAndRetainedTruth() {
        XCTAssertEqual(
            DashboardSpeedInstrumentView.accessibilitySpeedValue(kilometersPerHour: nil, isRetained: false),
            "Unavailable"
        )
        XCTAssertEqual(
            DashboardSpeedInstrumentView.accessibilitySpeedValue(kilometersPerHour: -0.01, isRetained: true),
            "Unavailable"
        )
        XCTAssertEqual(
            DashboardSpeedInstrumentView.accessibilitySpeedValue(kilometersPerHour: .nan, isRetained: false),
            "Unavailable"
        )
        XCTAssertEqual(
            DashboardSpeedInstrumentView.accessibilitySpeedValue(kilometersPerHour: .infinity, isRetained: true),
            "Unavailable"
        )

        let live = DashboardSpeedInstrumentView.accessibilitySpeedValue(
            kilometersPerHour: 0,
            isRetained: false
        )
        XCTAssertNotEqual(live, "Unavailable")
        XCTAssertFalse(live.localizedCaseInsensitiveContains("last known"))

        let retained = DashboardSpeedInstrumentView.accessibilitySpeedValue(
            kilometersPerHour: 7,
            isRetained: true
        )
        XCTAssertTrue(retained.localizedCaseInsensitiveContains("last known"))
        XCTAssertNotEqual(retained, "Unavailable")

        // Compact speed representability is presentation capacity, not a
        // physical maximum. The same accepted semantic projection must fail
        // closed whenever either metric or imperial display would need four
        // integral digits, and retained state must not become punctuation.
        XCTAssertEqual(
            DashboardSpeedInstrumentView.accessibilitySpeedValue(
                kilometersPerHour: 2_000,
                isRetained: false
            ),
            "Unavailable"
        )
        XCTAssertEqual(
            DashboardSpeedInstrumentView.accessibilitySpeedValue(
                kilometersPerHour: 2_000,
                isRetained: true
            ),
            "Unavailable"
        )
        XCTAssertEqual(VehicleDisplayFormatting.speed(kilometersPerHour: 2_000), "—")
        XCTAssertEqual(
            VehicleDisplayFormatting.accessibilitySpeed(
                kilometersPerHour: Double.greatestFiniteMagnitude,
                isRetained: true
            ),
            "Unavailable"
        )

        let halfStep = DashboardSpeedInstrumentView.accessibilitySpeedValue(
            kilometersPerHour: 22.5,
            isRetained: false
        )
        let expectedRoundedInteger = VehicleDisplayFormatting.usesMetric ? "23" : "14"
        XCTAssertTrue(
            halfStep.contains(expectedRoundedInteger),
            "Semantic speed rounding must match the visible nearest-away-from-zero rolling digit."
        )
        XCTAssertNotEqual(
            DashboardSpeedInstrumentView.accessibilitySpeedValue(
                kilometersPerHour: 999.4,
                isRetained: false
            ),
            "Unavailable"
        )
    }

    @MainActor
    func testDashboardReadyStatusRequiresKnownFiniteNonnegativeSpeed() {
        XCTAssertEqual(DashboardSpeedInstrumentView.liveSpeedStatusText(kilometersPerHour: nil), "NO LIVE SPEED")
        XCTAssertEqual(DashboardSpeedInstrumentView.liveSpeedStatusText(kilometersPerHour: -0.01), "NO LIVE SPEED")
        XCTAssertEqual(DashboardSpeedInstrumentView.liveSpeedStatusText(kilometersPerHour: .nan), "NO LIVE SPEED")
        XCTAssertEqual(DashboardSpeedInstrumentView.liveSpeedStatusText(kilometersPerHour: .infinity), "NO LIVE SPEED")
        XCTAssertEqual(DashboardSpeedInstrumentView.liveSpeedStatusText(kilometersPerHour: 0), "READY")
        XCTAssertEqual(DashboardSpeedInstrumentView.liveSpeedStatusText(kilometersPerHour: 0.49), "READY")
        XCTAssertEqual(DashboardSpeedInstrumentView.liveSpeedStatusText(kilometersPerHour: 0.5), "RIDING")
    }

    private func speedSample(
        kilometersPerHour: Double,
        uptimeNanoseconds: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: kilometersPerHour / 3.6,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: Date(timeIntervalSince1970: 0)
        )
    }
}
