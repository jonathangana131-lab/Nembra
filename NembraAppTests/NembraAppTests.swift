import CoreGraphics
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
    @MainActor
    func testBatteryReadoutPreferencePersistsAcrossSharedCockpitStoreRestoration() {
        let suiteName = "NembraAppTests.battery-readout.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "battery-primary-readout"
        let firstLaunch = HorizonCockpitStore(defaults: defaults, batteryModeKey: key)
        XCTAssertEqual(firstLaunch.batteryPrimaryReadoutState.mode, .percentage)

        firstLaunch.toggleBatteryPrimaryReadout()
        XCTAssertEqual(firstLaunch.batteryPrimaryReadoutState.mode, .estimatedRange)

        let restoredLaunch = HorizonCockpitStore(defaults: defaults, batteryModeKey: key)
        XCTAssertEqual(restoredLaunch.batteryPrimaryReadoutState.mode, .estimatedRange)

        restoredLaunch.toggleBatteryPrimaryReadout()
        let restoredAgain = HorizonCockpitStore(defaults: defaults, batteryModeKey: key)
        XCTAssertEqual(restoredAgain.batteryPrimaryReadoutState.mode, .percentage)
    }

    func testHorizonV4PropulsionGeometryIsSymmetricRaisedAndFullyBounded() {
        for size in [
            CGSize(width: 640, height: 112),
            CGSize(width: 720, height: 132),
            CGSize(width: 896, height: 156)
        ] {
            let geometry = DashboardPropulsionGeometry(size: size)
            let apex = geometry.point(at: 0.5)

            XCTAssertEqual(geometry.start.y, geometry.end.y, accuracy: 0.001)
            XCTAssertEqual(apex.x, size.width / 2, accuracy: 0.001)
            XCTAssertLessThanOrEqual(apex.y, size.height * 0.17)
            XCTAssertGreaterThan(geometry.start.y - apex.y, size.height * 0.70)

            for index in 0...32 {
                let progress = Double(index) / 32
                let mirror = geometry.point(at: 1 - progress)
                let point = geometry.point(at: progress)
                XCTAssertEqual(point.x + mirror.x, size.width, accuracy: 0.001)
                XCTAssertEqual(point.y, mirror.y, accuracy: 0.001)

                let normal = geometry.outwardNormal(at: progress)
                let tickEnd = CGPoint(
                    x: point.x + normal.dx * 15,
                    y: point.y + normal.dy * 15
                )
                XCTAssertGreaterThanOrEqual(tickEnd.x, 0)
                XCTAssertLessThanOrEqual(tickEnd.x, size.width)
                XCTAssertGreaterThanOrEqual(tickEnd.y, 0)
                XCTAssertLessThanOrEqual(tickEnd.y, size.height)
            }
        }
    }

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

    func testDashboardRenderStressAuthorizationFailsClosed() {
        let key = AppBootstrap.simulationDashboardRenderStressEnvironmentKey

        XCTAssertFalse(AppBootstrap.simulatorDashboardRenderStressIsAuthorized(
            scenario: .riding,
            hasExactSimulatorService: true,
            environment: [:]
        ))
        XCTAssertFalse(AppBootstrap.simulatorDashboardRenderStressIsAuthorized(
            scenario: .riding,
            hasExactSimulatorService: true,
            environment: [key: "true"]
        ))
        XCTAssertFalse(AppBootstrap.simulatorDashboardRenderStressIsAuthorized(
            scenario: .riding,
            hasExactSimulatorService: true,
            environment: [key: "0"]
        ))
        XCTAssertFalse(AppBootstrap.simulatorDashboardRenderStressIsAuthorized(
            scenario: .connectedStopped,
            hasExactSimulatorService: true,
            environment: [key: "1"]
        ))
        XCTAssertFalse(AppBootstrap.simulatorDashboardRenderStressIsAuthorized(
            scenario: .riding,
            hasExactSimulatorService: false,
            environment: [key: "1"]
        ))
        XCTAssertFalse(AppBootstrap.simulatorDashboardRenderStressIsAuthorized(
            scenario: .riding,
            hasExactSimulatorService: true,
            environment: [
                key: "1",
                AppBootstrap.simulationAutoCompleteRideEnvironmentKey: "1"
            ]
        ))
    }

#if targetEnvironment(simulator)
    func testDashboardRenderStressAuthorizationRequiresExactRidingSimulatorOptIn() {
        XCTAssertTrue(AppBootstrap.simulatorDashboardRenderStressIsAuthorized(
            scenario: .riding,
            hasExactSimulatorService: true,
            environment: [AppBootstrap.simulationDashboardRenderStressEnvironmentKey: "1"]
        ))
    }

    func testHomeStateFixtureAuthorizationFailsClosed() {
        let key = AppBootstrap.simulationHomeStateFixtureEnvironmentKey

        XCTAssertNil(AppBootstrap.simulatorHomeStateFixture(
            scenario: nil,
            hasExactSimulatorService: false,
            environment: [key: "retain-after-live"]
        ))
        XCTAssertNil(AppBootstrap.simulatorHomeStateFixture(
            scenario: .riding,
            hasExactSimulatorService: true,
            environment: [key: "retain-after-live"]
        ))
        XCTAssertNil(AppBootstrap.simulatorHomeStateFixture(
            scenario: .connectedStopped,
            hasExactSimulatorService: false,
            environment: [key: "retain-after-live"]
        ))
        XCTAssertNil(AppBootstrap.simulatorHomeStateFixture(
            scenario: .connectedStopped,
            hasExactSimulatorService: true,
            environment: [key: "unknown"]
        ))
        XCTAssertNil(AppBootstrap.simulatorHomeStateFixture(
            scenario: .connectedStopped,
            hasExactSimulatorService: true,
            environment: [
                key: "command-rejected",
                AppBootstrap.simulationSpeedEvidenceGapEnvironmentKey: "1"
            ]
        ))
    }

    func testHomeStateFixturesRequireExactConnectedSimulatorOptIn() {
        let key = AppBootstrap.simulationHomeStateFixtureEnvironmentKey

        XCTAssertEqual(AppBootstrap.simulatorHomeStateFixture(
            scenario: .connectedStopped,
            hasExactSimulatorService: true,
            environment: [key: "retain-after-live"]
        ), .retainAfterLive)
        XCTAssertEqual(AppBootstrap.simulatorHomeStateFixture(
            scenario: .connectedStopped,
            hasExactSimulatorService: true,
            environment: [key: "command-pending"]
        ), .commandPending)
        XCTAssertEqual(AppBootstrap.simulatorHomeStateFixture(
            scenario: .connectedStopped,
            hasExactSimulatorService: true,
            environment: [key: "command-rejected"]
        ), .commandRejected)
        XCTAssertEqual(AppBootstrap.simulatorHomeStateFixture(
            scenario: .connectedStopped,
            hasExactSimulatorService: true,
            environment: [key: "persistence-failure"]
        ), .persistenceFailure)
    }

    @MainActor
    func testRetainedFixtureDemotesLiveBatteryWithoutRedatingIt() async {
        let runtime = AppBootstrap.makeRuntime(
            arguments: ["Nembra"],
            environment: homeFixtureEnvironment("retain-after-live")
        )
        let originalObservationDate = runtime.vehicleStore.state.lastUpdated

        await runtime.start()
        let didBecomeRetained = await waitUntil {
            runtime.vehicleStore.state.connection == .reconnecting
        }
        XCTAssertTrue(didBecomeRetained)

        XCTAssertEqual(runtime.vehicleStore.state.connection, .reconnecting)
        XCTAssertEqual(runtime.vehicleStore.batteryDisplayPercent, 92)
        XCTAssertEqual(runtime.vehicleStore.batteryDataAvailability, .retained)
        XCTAssertEqual(runtime.vehicleStore.retainedBatteryAuthority, .displayOnly)
        XCTAssertEqual(runtime.vehicleStore.retainedBatteryObservedAt, originalObservationDate)
        XCTAssertEqual(runtime.vehicleStore.state.lastUpdated, originalObservationDate)
    }

    @MainActor
    func testPendingFixtureNeverPublishesAnUnconfirmedCommand() async {
        let runtime = AppBootstrap.makeRuntime(
            arguments: ["Nembra"],
            environment: homeFixtureEnvironment("command-pending")
        )
        await runtime.start()
        XCTAssertEqual(runtime.vehicleStore.state.isHeadlightOn, false)

        let command = Task { await runtime.vehicleStore.setHeadlight(true) }
        let didBeginCommand = await waitUntil {
            runtime.vehicleStore.pendingCommands.contains(.headlight)
        }
        XCTAssertTrue(didBeginCommand)

        XCTAssertTrue(runtime.vehicleStore.pendingCommands.contains(.headlight))
        XCTAssertEqual(runtime.vehicleStore.state.isHeadlightOn, false)
        command.cancel()
        await command.value
        XCTAssertEqual(runtime.vehicleStore.state.isHeadlightOn, false)
    }

    @MainActor
    func testRejectedFixtureKeepsConfirmedStateAndExposesFailure() async {
        let runtime = AppBootstrap.makeRuntime(
            arguments: ["Nembra"],
            environment: homeFixtureEnvironment("command-rejected")
        )
        await runtime.start()

        await runtime.vehicleStore.setHeadlight(true)

        XCTAssertFalse(runtime.vehicleStore.isVehicleCommandPending)
        XCTAssertEqual(runtime.vehicleStore.state.isHeadlightOn, false)
        XCTAssertEqual(
            runtime.vehicleStore.lastErrorMessage,
            "The scooter rejected that command in its current state."
        )
    }

    @MainActor
    func testPersistenceFailureFixtureKeepsVehicleTruthIndependent() async {
        let runtime = AppBootstrap.makeRuntime(
            arguments: ["Nembra"],
            environment: homeFixtureEnvironment("persistence-failure")
        )

        await runtime.start()
        await runtime.rideHistoryStore.refresh()
        await runtime.dailyRideStore.refresh(
            now: .now,
            calendar: .current,
            currentRideSessionID: nil
        )

        XCTAssertEqual(runtime.vehicleStore.state.connection, .connected)
        XCTAssertEqual(runtime.vehicleStore.batteryDisplayPercent, 92)
        XCTAssertEqual(runtime.rideStore.status, .persistenceUnavailable)
        XCTAssertEqual(runtime.rideHistoryStore.status, .unavailable)
        XCTAssertEqual(runtime.dailyRideStore.status, .unavailable)
        XCTAssertEqual(runtime.automaticCaptureReadiness.facts.storage, .unavailable)
    }
#endif

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
    func testSpeedEvidenceGapKeyAloneCannotEnterSimulation() async {
        let environment = [AppBootstrap.simulationSpeedEvidenceGapEnvironmentKey: "1"]
        XCTAssertNil(AppBootstrap.simulationScenario(arguments: ["Nembra"], environment: environment))

        let store = AppBootstrap.makeVehicleStore(
            arguments: ["Nembra"],
            environment: environment
        )
        await store.start()

        XCTAssertEqual(store.state.connection, .disconnected)
        XCTAssertEqual(store.state.connectionIssue, .unsupportedConfiguration)
        XCTAssertNil(store.state.speedKilometersPerHour)
        XCTAssertNil(store.state.batteryPercent)
        XCTAssertEqual(store.speedInstrumentInterpolationPolicy, .disabled)
        XCTAssertNotEqual(store.profile, .simulatorQA)
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
    func testSpeedInstrumentUsesAcceptedSourceFallbackUntilFreshTelemetryArrives() throws {
        let model = SpeedInstrumentModel()
        let frame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_000_000_000,
            fallbackAcceptedKilometersPerHour: 18.4
        ))

        XCTAssertEqual(frame.kilometersPerHour, 18.4, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .acceptedSourceFallback)
        XCTAssertNil(frame.latestMeasuredKilometersPerHour)
        XCTAssertEqual(model.measurementRevision, 0)
    }

    @MainActor
    func testUncalibratedSpeedInstrumentSnapsEvenAcrossCloseMeasurements() throws {
        let model = SpeedInstrumentModel()
        model.accept(try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000))
        model.accept(try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000))

        let frame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_200_000_000,
            fallbackAcceptedKilometersPerHour: nil
        ))
        XCTAssertEqual(frame.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .measuredTelemetry)
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
            fallbackAcceptedKilometersPerHour: nil
        ))
        XCTAssertEqual(firstFrame.kilometersPerHour, 10, accuracy: 0.000_1)
        XCTAssertEqual(firstFrame.origin, .measuredTelemetry)

        model.accept(second)
        let midpoint = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_280_000_000,
            fallbackAcceptedKilometersPerHour: nil
        ))
        XCTAssertEqual(midpoint.kilometersPerHour, 15, accuracy: 0.000_1)
        XCTAssertEqual(midpoint.latestMeasuredKilometersPerHour, 20)
        XCTAssertEqual(midpoint.origin, .visuallyInterpolated)

        let settled = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_400_000_000,
            fallbackAcceptedKilometersPerHour: nil
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
            fallbackAcceptedKilometersPerHour: nil,
            prefersReducedMotion: true
        ))
        XCTAssertEqual(reducedMotionFrame.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(reducedMotionFrame.latestMeasuredKilometersPerHour, 20)
        XCTAssertEqual(reducedMotionFrame.origin, .measuredTelemetry)
        XCTAssertEqual(model.measurementRevision, revision)

        let ordinaryFrame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 1_280_000_000,
            fallbackAcceptedKilometersPerHour: nil
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

        let frame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 2_500_000_000,
            fallbackAcceptedKilometersPerHour: 99
        ))
        XCTAssertEqual(frame.kilometersPerHour, 12, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .measuredTelemetry)
    }

    @MainActor
    func testSimulatorQASpeedRequiresExplicitSimulatorPresentationProfile() throws {
        let sample = try SpeedTelemetrySample(
            source: .simulatorQA,
            provenance: .absoluteMeasurement,
            metersPerSecond: 5,
            receivedAtUptimeNanoseconds: 2_200_000_000,
            receivedAtDate: Date(timeIntervalSince1970: 0)
        )
        let live = SpeedEvidenceAvailability.live(sample)
        let retained = SpeedEvidenceAvailability.retained(sample)

        XCTAssertEqual(live.dashboardPresentationAvailability, .unavailable)
        XCTAssertEqual(retained.dashboardPresentationAvailability, .unavailable)
        XCTAssertEqual(
            live.dashboardPresentationAvailability(allowsSimulatorQA: true),
            .live(sample)
        )
        XCTAssertEqual(
            retained.dashboardPresentationAvailability(allowsSimulatorQA: true),
            .retained(sample)
        )

        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)

        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)
        model.setSpeedEvidenceAvailability(.live(first))
        model.setSpeedEvidenceAvailability(.live(second))
        XCTAssertTrue(model.isAnimationActive)
        XCTAssertEqual(model.latestAcceptedSample, second)

        // Synthetic Simulator evidence is caller-constructible. Under a normal
        // profile it must fail closed and retire all previously live render
        // continuity rather than leaving an old authoritative target moving.
        model.setSpeedEvidenceAvailability(live)
        XCTAssertFalse(model.isAnimationActive)
        XCTAssertNil(model.latestAcceptedSample)
        XCTAssertNil(model.latestMeasuredKilometersPerHour)
        XCTAssertNil(model.latestMeasurementSource)
        XCTAssertNil(model.latestMeasurementUptimeNanoseconds)
        XCTAssertNil(model.presentationFrame(
            for: live,
            atUptimeNanoseconds: sample.receivedAtUptimeNanoseconds
        ))

        model.setSpeedEvidenceAvailability(live, allowsSimulatorQA: true)
        XCTAssertEqual(model.latestAcceptedSample, sample)
        let frame = try XCTUnwrap(model.presentationFrame(
            for: live,
            atUptimeNanoseconds: sample.receivedAtUptimeNanoseconds,
            allowsSimulatorQA: true
        ))
        XCTAssertEqual(frame.kilometersPerHour, 18, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .measuredTelemetry)
    }

    @MainActor
    func testCallerConstructedEstimatedAvailabilityFailsClosedAndRetiresLiveContinuity() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)

        model.setSpeedEvidenceAvailability(.live(first))
        model.setSpeedEvidenceAvailability(.live(second))
        XCTAssertTrue(model.isAnimationActive)

        let estimate = try SpeedTelemetrySample(
            source: .motionAssist,
            provenance: .shortHorizonEstimate,
            metersPerSecond: 9,
            receivedAtUptimeNanoseconds: 1_300_000_000,
            receivedAtDate: Date(timeIntervalSince1970: 0)
        )
        let forgedLive: SpeedEvidenceAvailability = .live(estimate)
        let forgedRetained: SpeedEvidenceAvailability = .retained(estimate)

        XCTAssertFalse(estimate.isAuthoritativeMeasurement)
        XCTAssertEqual(forgedLive.dashboardPresentationAvailability, .unavailable)
        XCTAssertEqual(forgedRetained.dashboardPresentationAvailability, .unavailable)
        XCTAssertNil(model.presentationFrame(
            for: forgedLive,
            atUptimeNanoseconds: 1_280_000_000
        ))
        XCTAssertNil(model.presentationFrame(
            for: forgedRetained,
            atUptimeNanoseconds: 1_280_000_000
        ))

        // Synchronous projection alone does not mutate render state, but lifecycle
        // admission of the forged live wrapper must retire the old live interpolator.
        XCTAssertTrue(model.isAnimationActive)
        model.setSpeedEvidenceAvailability(forgedLive)
        XCTAssertFalse(model.isAnimationActive)
        XCTAssertNil(model.latestAcceptedSample)
        XCTAssertNil(model.latestMeasuredKilometersPerHour)
        XCTAssertNil(model.latestMeasurementSource)
        XCTAssertNil(model.latestMeasurementUptimeNanoseconds)
        XCTAssertNil(model.presentationFrame(
            for: forgedLive,
            atUptimeNanoseconds: 1_300_000_000
        ))
    }

    @MainActor
    func testQAProfileSnapsAcrossLongTelemetryGap() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        model.accept(try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000))
        model.accept(try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 2_000_000_000))

        let frame = try XCTUnwrap(model.frame(
            atUptimeNanoseconds: 2_000_000_000,
            fallbackAcceptedKilometersPerHour: nil
        ))
        XCTAssertEqual(frame.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .measuredTelemetry)
        XCTAssertFalse(model.isAnimationActive)
    }

    @MainActor
    func testUnavailablePresentationFailsClosedBeforeLifecycleCleanup() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)

        model.setSpeedEvidenceAvailability(.live(first))
        model.setSpeedEvidenceAvailability(.live(second))
        XCTAssertTrue(model.isAnimationActive)

        XCTAssertNil(model.presentationFrame(
            for: .unavailable,
            atUptimeNanoseconds: 1_280_000_000
        ))

        // This proves the result did not depend on `.onChange` cleanup running first.
        XCTAssertTrue(model.isAnimationActive)
        XCTAssertEqual(
            try XCTUnwrap(model.latestMeasuredKilometersPerHour),
            20,
            accuracy: 0.000_1
        )
    }

    @MainActor
    func testRetainedPresentationIgnoresExistingLiveInterpolatorBeforeLifecycleCleanup() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)

        model.setSpeedEvidenceAvailability(.live(first))
        model.setSpeedEvidenceAvailability(.live(second))
        XCTAssertTrue(model.isAnimationActive)

        let retained = try XCTUnwrap(model.presentationFrame(
            for: .retained(first),
            atUptimeNanoseconds: 1_280_000_000
        ))
        XCTAssertEqual(retained.kilometersPerHour, 10, accuracy: 0.000_1)
        XCTAssertEqual(retained.origin, .acceptedSourceFallback)
        XCTAssertNil(retained.latestMeasuredKilometersPerHour)

        // The old live interpolator still exists here; the synchronous gate ignored it.
        XCTAssertTrue(model.isAnimationActive)
        XCTAssertEqual(
            try XCTUnwrap(model.latestMeasuredKilometersPerHour),
            20,
            accuracy: 0.000_1
        )
    }

    @MainActor
    func testNewLiveSourceValueWinsBeforeInterpolatorRetargets() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)
        let third = try speedSample(kilometersPerHour: 30, uptimeNanoseconds: 1_400_000_000)

        model.setSpeedEvidenceAvailability(.live(first))
        model.setSpeedEvidenceAvailability(.live(second))
        XCTAssertTrue(model.isAnimationActive)

        let current = try XCTUnwrap(model.presentationFrame(
            for: .live(third),
            atUptimeNanoseconds: 1_400_000_000
        ))
        XCTAssertEqual(current.kilometersPerHour, 30, accuracy: 0.000_1)
        XCTAssertEqual(current.origin, .acceptedSourceFallback)
        XCTAssertNil(current.latestMeasuredKilometersPerHour)

        // The local display model still targets receipt two; visual truth already moved to receipt three.
        XCTAssertEqual(
            try XCTUnwrap(model.latestMeasurementUptimeNanoseconds),
            second.receivedAtUptimeNanoseconds
        )
        XCTAssertEqual(
            try XCTUnwrap(model.latestMeasuredKilometersPerHour),
            20,
            accuracy: 0.000_1
        )
    }

    @MainActor
    func testDistinctLiveSampleMetadataCannotReuseOldInterpolatorTarget() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)

        model.setSpeedEvidenceAvailability(.live(first))
        model.setSpeedEvidenceAvailability(.live(second))
        XCTAssertTrue(model.isAnimationActive)
        XCTAssertEqual(model.latestAcceptedSample, second)

        // This is a distinct accepted sample that deliberately collides with the old
        // source + monotonic receipt uptime + numeric speed key. Its wall-clock receipt
        // metadata differs, so whole-sample identity must prevent reuse of the old
        // interpolation target during the same-render-before-onChange race window.
        let metadataDistinctSample = try SpeedTelemetrySample(
            source: second.source,
            provenance: second.provenance,
            metersPerSecond: second.metersPerSecond,
            receivedAtUptimeNanoseconds: second.receivedAtUptimeNanoseconds,
            receivedAtDate: Date(timeIntervalSince1970: 1)
        )
        XCTAssertNotEqual(metadataDistinctSample, second)
        XCTAssertEqual(metadataDistinctSample.source, second.source)
        XCTAssertEqual(
            metadataDistinctSample.receivedAtUptimeNanoseconds,
            second.receivedAtUptimeNanoseconds
        )
        XCTAssertEqual(
            metadataDistinctSample.kilometersPerHour,
            second.kilometersPerHour,
            accuracy: 0.000_1
        )

        let frame = try XCTUnwrap(model.presentationFrame(
            for: .live(metadataDistinctSample),
            atUptimeNanoseconds: 1_280_000_000
        ))
        XCTAssertEqual(frame.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(frame.origin, .acceptedSourceFallback)
        XCTAssertNil(frame.latestMeasuredKilometersPerHour)

        // Presentation truth moved to the distinct current sample without mutating
        // the still-old local display target; lifecycle retarget remains a separate step.
        XCTAssertEqual(model.latestAcceptedSample, second)
        XCTAssertTrue(model.isAnimationActive)
    }

    @MainActor
    func testSpeedEvidenceUnavailableRetiresInterpolationImmediately() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)

        model.setSpeedEvidenceAvailability(.live(first))
        model.setSpeedEvidenceAvailability(.live(second))
        let midpoint = try XCTUnwrap(model.presentationFrame(
            for: .live(second),
            atUptimeNanoseconds: 1_280_000_000
        ))
        XCTAssertEqual(midpoint.kilometersPerHour, 15, accuracy: 0.000_1)
        XCTAssertTrue(model.isAnimationActive)

        model.setSpeedEvidenceAvailability(.unavailable)

        XCTAssertNil(model.presentationFrame(
            for: .unavailable,
            atUptimeNanoseconds: 1_290_000_000
        ))
        XCTAssertNil(model.latestAcceptedSample)
        XCTAssertNil(model.latestMeasuredKilometersPerHour)
        XCTAssertNil(model.latestMeasurementSource)
        XCTAssertNil(model.latestMeasurementUptimeNanoseconds)
        XCTAssertFalse(model.isAnimationActive)
    }

    @MainActor
    func testRetainedSpeedEvidenceCannotContinueLiveInterpolation() throws {
        let model = SpeedInstrumentModel()
        model.configureInterpolationPolicy(.simulatorQA)
        let first = try speedSample(kilometersPerHour: 10, uptimeNanoseconds: 1_000_000_000)
        let second = try speedSample(kilometersPerHour: 20, uptimeNanoseconds: 1_200_000_000)

        model.setSpeedEvidenceAvailability(.live(first))
        model.setSpeedEvidenceAvailability(.live(second))
        model.setSpeedEvidenceAvailability(.retained(second))

        let retained = try XCTUnwrap(model.presentationFrame(
            for: .retained(second),
            atUptimeNanoseconds: 1_280_000_000
        ))
        XCTAssertEqual(retained.kilometersPerHour, 20, accuracy: 0.000_1)
        XCTAssertEqual(retained.origin, .acceptedSourceFallback)
        XCTAssertNil(retained.latestMeasuredKilometersPerHour)
        XCTAssertNil(model.latestAcceptedSample)
        XCTAssertNil(model.latestMeasuredKilometersPerHour)
        XCTAssertNil(model.latestMeasurementSource)
        XCTAssertNil(model.latestMeasurementUptimeNanoseconds)
        XCTAssertFalse(model.isAnimationActive)
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

#if targetEnvironment(simulator)
    private func homeFixtureEnvironment(_ fixture: String) -> [String: String] {
        [
            "NEMBRA_SIMULATION_SCENARIO": "connected-stopped",
            AppBootstrap.simulationStorageNamespaceEnvironmentKey:
                "home-fixture-\(fixture)-\(UUID().uuidString)",
            AppBootstrap.simulationHomeStateFixtureEnvironmentKey: fixture
        ]
    }

    @MainActor
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await clock.sleep(for: .milliseconds(10))
        }
        return condition()
    }
#endif
}
