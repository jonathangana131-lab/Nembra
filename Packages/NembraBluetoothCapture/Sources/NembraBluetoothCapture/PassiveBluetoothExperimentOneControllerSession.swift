import Foundation

/// App-facing owner for one complete passive Experiment One software life.
///
/// The app may drive the four bounded OFF/ON observation windows through
/// `powerCycleObservationSession`, then ask this owner to begin an exact-target
/// rediscovery and, only after that fresh rediscovery, connect the same package-owned
/// run to the foreground controller.
///
/// The one-shot capture admission remains package-internal. App/UI code never receives
/// a recorder, admission token, target UUID authority, or caller-mintable provenance.
/// This type only closes software ownership; it does not authenticate a physical ES80
/// or establish any GATT/Tuya/telemetry meaning.
@MainActor
public final class PassiveBluetoothExperimentOneControllerSession {
    public enum SessionError: Error, Equatable, Sendable {
        case captureRediscoveryNotPrepared
    }

    private let run: PassiveBluetoothExperimentOneRun
    private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?

    /// The exact four-window producer owned by this same Experiment One run.
    public var powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession {
        run.powerCycleObservationSession
    }

    /// Creates one ES80-specific Experiment One software authority.
    /// Matching this software vehicle context is not physical scooter authentication.
    public init() throws {
        run = try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }

    /// Issues the run-owned capture admission before rediscovery, then starts a fresh
    /// controller scan epoch. `startScanning` clears the controller candidate catalog,
    /// so any candidate later visible to the app/controller must have been received
    /// after this admission's monotonic issuance boundary.
    ///
    /// Repeating this method before connection reuses the same one-shot admission and
    /// merely starts another fresh scan epoch; it never mints a second recorder.
    public func prepareCaptureAndStartExactTargetRediscovery(
        using controller: ForegroundCoreBluetoothCaptureController,
        startedAt: Date = Date()
    ) throws {
        if pendingCaptureAdmission == nil {
            pendingCaptureAdmission = try run.issueCaptureAdmission(startedAt: startedAt)
        }

        controller.stopScanning()
        try controller.startScanning(captureAdvertisementCadence: false)
    }

    /// Consumes the hidden run-owned admission into the foreground controller after the
    /// app has observed the exact correlated target in the fresh post-admission scan epoch.
    ///
    /// The local reference is cleared before handoff. Any thrown connection/admission
    /// failure therefore fails this run closed instead of letting UI code replay a possibly
    /// consumed authority token. A new Experiment One session is required to retry.
    public func connectReacquiredTarget(
        using controller: ForegroundCoreBluetoothCaptureController,
        timeout: TimeInterval = 12
    ) throws {
        guard let admission = pendingCaptureAdmission else {
            throw SessionError.captureRediscoveryNotPrepared
        }
        pendingCaptureAdmission = nil
        try controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)
    }
}
