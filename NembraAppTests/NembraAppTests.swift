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
        XCTAssertEqual(model.measurementRevision, 0)
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

/// V14 Capture authority regression for the current authenticated stationary field target.
/// These source checks live in the already-wired NembraAppTests target, but they intentionally
/// inspect the separate standalone Nembra Capture target rather than recreating the retired
/// ES80-FINGERPRINT launch router inside the normal Nembra app.
extension NembraAppTests {
    func testCaptureShellUsesBoundedPresentationPolling() {
        XCTAssertEqual(ES80CaptureRefreshPolicy.statusPollInterval, 0.5)
    }

    func testStandaloneCaptureTargetOwnsAuthenticatedStationaryEntrypoint() throws {
        let root = repositoryRoot()
        let project = try String(
            contentsOf: root.appendingPathComponent("NembraCapture.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let entrypoint = try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
        let identity = try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureBuildIdentity.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(project.contains("NembraCaptureEntrypoint.swift in Sources"))
        XCTAssertTrue(project.contains("NembraCaptureBuildIdentity.swift in Sources"))
        XCTAssertTrue(project.contains("ES80CaptureShellView.swift in Sources"))
        XCTAssertTrue(project.contains("NembraBluetoothCapture in Frameworks"))
        XCTAssertFalse(project.contains("NembraApp.swift in Sources"))

        XCTAssertTrue(entrypoint.contains("struct NembraCaptureApp: App"))
        XCTAssertTrue(entrypoint.contains("WindowGroup { CaptureP0Root().preferredColorScheme(.dark) }"))
        XCTAssertTrue(entrypoint.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        XCTAssertTrue(identity.contains("static let requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        XCTAssertFalse(entrypoint.contains("NembraCaptureFieldRecipe"))
    }

    func testAuthenticatedStationaryPreflightFailsClosedBeforeOff1() throws {
        let entrypoint = try String(
            contentsOf: repositoryRoot().appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(entrypoint.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        XCTAssertTrue(entrypoint.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))
        XCTAssertTrue(entrypoint.contains("field_build_identity_unavailable"))
        XCTAssertTrue(entrypoint.contains("sdkDeviceMembershipVerified"))
        XCTAssertTrue(entrypoint.contains("accountIdentityLeaseIsAuthorized"))
        XCTAssertTrue(entrypoint.contains("Only the full OFF → ON → OFF → ON pattern can authorize the nearby signal for this attempt."))
        XCTAssertTrue(entrypoint.contains("Nembra can now open the secure Tuya link. Capture stays read-only and cannot send scooter commands."))
    }

    func testAuthenticatedStationaryAcceptedExportIsSealedBeforeSharePreparation() throws {
        let entrypoint = try String(
            contentsOf: repositoryRoot().appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(entrypoint.contains("self.sealedAcceptedExport = self.makeExport("))
        XCTAssertTrue(entrypoint.contains("phase: .accepted"))
        XCTAssertTrue(entrypoint.contains("self.exportData = nil"))
        XCTAssertTrue(entrypoint.contains("self.phase = .accepted"))
        XCTAssertTrue(entrypoint.contains("self.prepareExport()"))
        XCTAssertTrue(entrypoint.contains("CAPTURE COMPLETE"))
        XCTAssertTrue(entrypoint.contains("Ready for analysis"))
        XCTAssertTrue(entrypoint.contains("Label(\"Share Capture\""))
        XCTAssertFalse(entrypoint.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
