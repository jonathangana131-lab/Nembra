@preconcurrency import CoreBluetooth
import Foundation
import NembraCore

/// App-facing owner for one complete passive Experiment One software life.
///
/// The app drives the four bounded OFF/ON observation windows through
/// `powerCycleObservationSession`, then asks this owner to prepare exact-target
/// rediscovery, connect the same sealed run, observe readiness, and finalize the
/// accepted observation Horizon. The generic CoreBluetooth controller remains an
/// implementation detail of this owner.
///
/// The one-shot capture admission, mutable recorder, target authority, and controller
/// admission bridge remain package-internal. App/UI code never receives any of them.
/// This type only closes software ownership; it does not authenticate a physical ES80,
/// prove RF completeness, establish GATT/Tuya/telemetry meaning, or authorize writes.
@MainActor
public final class PassiveBluetoothExperimentOneControllerSession {
    public enum SessionError: Error, Equatable, Sendable {
        case captureRediscoveryNotPrepared
        case restartNotAllowedWhileCaptureActive
    }

    private var run: PassiveBluetoothExperimentOneRun
    private var controller: ForegroundCoreBluetoothCaptureController
    private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?

    /// The exact four-window producer owned by this same Experiment One run.
    public var powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession {
        run.powerCycleObservationSession
    }

    // MARK: - Read-only product state

    public var bluetoothState: CBManagerState {
        controller.bluetoothState
    }

    public var discoveredPeripherals: [ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral] {
        controller.discoveredPeripherals
    }

    public var connectionPhase: ForegroundCoreBluetoothCaptureController.ConnectionPhase {
        controller.connectionPhase
    }

    public var hasTargetSession: Bool {
        controller.hasTargetSession
    }

    public var hasCompleteTargetEvidence: Bool {
        controller.hasCompleteTargetEvidence
    }

    public var canFinalizeObservationHorizon: Bool {
        controller.canFinalizeObservationHorizon
    }

    public var isSelectedTargetAwaitingTerminalCallback: Bool {
        controller.isSelectedTargetAwaitingTerminalCallback
    }

    public var captureFailed: Bool {
        controller.captureFailed
    }

    public var lastDiagnostic: String? {
        controller.lastDiagnostic
    }

    /// Creates one ES80-specific Experiment One software authority and its private
    /// foreground controller. Matching this software vehicle context is not physical
    /// scooter authentication.
    public init() throws {
        run = try Self.makeRun()
        controller = try Self.makeController()
    }

    /// Replaces a failed/pre-capture attempt with a genuinely fresh package-owned run.
    ///
    /// This is allowed before a target capture starts, or after the old controller is
    /// already failed/idle with incomplete evidence. It is intentionally unavailable
    /// while a live/ready capture is still authoritative; normal UI cannot discard good
    /// evidence merely to get a fresh-looking screen.
    public func restartExperimentOne() throws {
        let connectionIsLive: Bool
        switch controller.connectionPhase {
        case .connecting, .connected:
            connectionIsLive = true
        case .idle:
            connectionIsLive = false
        }

        guard !connectionIsLive,
              !controller.hasCompleteTargetEvidence else {
            throw SessionError.restartNotAllowedWhileCaptureActive
        }

        run.powerCycleObservationSession.abandonCurrentWindow()
        controller.stopScanning()
        if controller.hasTargetSession {
            controller.cancelActiveConnection()
        }

        let freshRun = try Self.makeRun()
        let freshController = try Self.makeController()
        pendingCaptureAdmission = nil
        run = freshRun
        controller = freshController
    }

    /// Issues the run-owned capture admission before rediscovery, then starts a fresh
    /// controller scan epoch. `startScanning` clears the private candidate catalog,
    /// so any candidate later exposed by this facade was received after the admission's
    /// monotonic issuance boundary.
    ///
    /// Repeating this method before connection reuses the same one-shot admission and
    /// merely starts another fresh scan epoch; it never mints a second recorder.
    public func prepareCaptureAndStartExactTargetRediscovery(
        startedAt: Date = Date()
    ) throws {
        if pendingCaptureAdmission == nil {
            pendingCaptureAdmission = try run.issueCaptureAdmission(startedAt: startedAt)
        }

        controller.stopScanning()
        try controller.startScanning(captureAdvertisementCadence: false)
    }

    public func stopExactTargetRediscovery() {
        controller.stopScanning()
    }

    /// Consumes the hidden run-owned admission after the app has observed the exact
    /// correlated target in the fresh post-admission candidate epoch.
    ///
    /// The local reference is cleared before handoff. Any thrown connection/admission
    /// failure therefore fails this run closed instead of letting UI code replay a
    /// possibly consumed authority token. A fresh Experiment One run is required.
    public func connectReacquiredTarget(timeout: TimeInterval = 12) throws {
        guard let admission = pendingCaptureAdmission else {
            throw SessionError.captureRediscoveryNotPrepared
        }
        pendingCaptureAdmission = nil
        try controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)
    }

    /// Permanently invalidates the current foreground-only capture evidence before
    /// transport teardown. A later app foreground event cannot revive that evidence.
    public func invalidateActiveCaptureForForegroundLoss() {
        controller.invalidateActiveCaptureForForegroundLoss()
    }

    /// Produces the exact immutable H-bounded JSON from the same run that owned
    /// correlation and target admission. The controller's trusted monotonic duration
    /// gate remains the only finalization authority.
    public func encodedFinalizedObservationHorizonJSON(
        prettyPrinted: Bool = true
    ) async throws -> Data {
        try await controller.encodedFinalizedObservationHorizonJSON(
            prettyPrinted: prettyPrinted
        )
    }

    /// Tears down transport only after immutable artifact freeze has succeeded.
    public func teardownActiveConnectionAfterFinalization() throws {
        try controller.teardownActiveConnectionAfterFinalization()
    }

    private static func makeRun() throws -> PassiveBluetoothExperimentOneRun {
        try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }

    private static func makeController() throws -> ForegroundCoreBluetoothCaptureController {
        try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }
}
