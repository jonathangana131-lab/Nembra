import Foundation

/// Main-actor lifecycle bridge for Tuya's documented
/// `ThingSmartBLEManagerDelegate.bleReceiveTransparentData(_:devId:)` callback.
///
/// The app adapter owns one instance for the exact official Smart Life BLE attempt.
/// `capture(...)` is intentionally synchronous so the package connection generation is
/// sealed at the SDK delegate boundary before any actor hop. `record(...)` then admits
/// that immutable receipt through the actor-owned authenticated session.
///
/// This bridge is read-only. It has no API for publishing DPs, transparent writes,
/// pairing, reset, removal, or unbind. Recorded SDK-transparent bytes remain diagnostic
/// evidence only because Tuya's documented callback does not expose the underlying GATT
/// service/characteristic tuple required for raw FD50 physical first acceptance.
@MainActor
public final class C7D09A22DocumentedTransparentReceiveIngress {
    public typealias Receipt = C7D09A22GenerationBoundTransparentReceiveReceipt
    public typealias RecordResult = C7D09A22AuthenticatedTransparentReceiveSession.RecordResult

    private var activeConnectionToken: TuyaReadOnlyConnectionToken?
    private var session: C7D09A22AuthenticatedTransparentReceiveSession?

    public init() {}

    /// Arms ingress for exactly one package-issued authenticated BLE generation.
    /// A second begin always retires the previous generation first.
    @discardableResult
    public func begin(
        connectionToken: TuyaReadOnlyConnectionToken,
        expectedDeviceID: String,
        sdkConnectionStartedAtUptimeNanoseconds: UInt64
    ) async -> Bool {
        await retire()

        guard let nextSession = C7D09A22AuthenticatedTransparentReceiveSession(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            sdkConnectionStartedAtUptimeNanoseconds: sdkConnectionStartedAtUptimeNanoseconds
        ) else {
            return false
        }

        activeConnectionToken = connectionToken
        session = nextSession
        return true
    }

    /// Call synchronously inside Tuya's documented BLE-manager delegate callback.
    /// Invalid, empty, unowned, or post-retirement callbacks are discarded here.
    public func capture(payload: Data, callbackDeviceID: String) -> Receipt? {
        C7D09A22GenerationBoundTransparentReceiveReceipt.capture(
            payload: payload,
            callbackDeviceID: callbackDeviceID,
            activeConnectionToken: activeConnectionToken
        )
    }

    /// Actor-serialized admission for one already sealed callback receipt.
    /// The caller supplies the package-owned authenticated snapshot for this same
    /// connection generation; cross-generation and stale callbacks fail closed.
    public func record(
        _ receipt: Receipt,
        preflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> RecordResult? {
        guard let session else { return nil }
        return await session.recordDocumentedTransparentReceive(
            receipt,
            preflightSnapshot: preflightSnapshot,
            activeConnectionToken: activeConnectionToken
        )
    }

    /// Permanently retires the active generation before releasing its token.
    /// Delayed process-global Tuya callbacks therefore cannot be borrowed by a later attempt.
    public func retire() async {
        if let session {
            await session.retire()
        }
        session = nil
        activeConnectionToken = nil
    }

    public var hasActiveGeneration: Bool {
        activeConnectionToken != nil && session != nil
    }

    // SDK-transparent callback custody is diagnostic-only and cannot mint protocol truth.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
