import Combine
import Dispatch
import Foundation

#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit
#endif

/// Runtime bridge for the *official* Tuya SmartLife iOS SDK.
///
/// This type intentionally exposes no generic GATT write, DP publish, unbind, pairing, reset,
/// firmware, or control API. Its only accepted positive evidence is produced by the official
/// SDK connection plus passive `ThingSmartDeviceDelegate` DP-update callbacks.
@MainActor
final class TuyaSmartLifeReadOnlyRuntime: NSObject, ObservableObject, TuyaReadOnlyAuthenticationSessionProvider {
    struct DeviceIdentity: Equatable, Sendable {
        let deviceID: String
        let uuid: String
        let productKey: String
        let displayName: String

        var isComplete: Bool {
            !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !productKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    struct DPEvent: Codable, Identifiable, Equatable, Sendable {
        let id: UInt64
        let wallClock: Date
        let monotonicNanoseconds: UInt64
        let source: String
        let deviceID: String
        let values: [String: String]
    }

    struct ExportEnvelope: Codable, Sendable {
        let schemaVersion: Int
        let purpose: String
        let createdAt: Date
        let deviceID: String
        let deviceUUID: String
        let productKey: String
        let authenticationResult: String
        let connectionGeneration: UInt64
        let secureConnectionDurationSeconds: Double?
        let applicationNotificationCount: Int
        let payloadSource: String
        let redactions: [String: Bool]
        let events: [DPEvent]
        let limitations: [String]
    }

    enum Phase: Equatable {
        case sdkUnavailable
        case idle
        case authenticating
        case observing
        case accepted
        case failed(String)
    }

    @Published private(set) var phase: Phase
    @Published private(set) var statusMessage: String
    @Published private(set) var snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    @Published private(set) var dpEvents: [DPEvent] = []
    @Published private(set) var exportData: Data?
    @Published private(set) var exportFilename = "Nembra-Tuya-Authenticated-ReadOnly.json"

    private var selectedDevice: DeviceIdentity?
    private var connectionGeneration: UInt64 = 0
    private var connectionStartedAtUptimeNanoseconds: UInt64?
    private var authenticatedAtUptimeNanoseconds: UInt64?
    private var latestObservedUptimeNanoseconds: UInt64?
    private var nextEventID: UInt64 = 1
    private var hasSDKConnectSuccess = false

    #if canImport(ThingSmartHomeKit)
    private var thingDevice: ThingSmartDevice?
    #endif

    override init() {
        #if canImport(ThingSmartHomeKit)
        phase = .idle
        statusMessage = "Official Tuya SmartLife SDK is available. Select the already-bound scooter to begin the read-only preflight."
        #else
        phase = .sdkUnavailable
        statusMessage = "This build does not contain the official Tuya SmartLife iOS SDK. Authentication stays locked; no raw fallback writes are allowed."
        #endif
        snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .unavailable(reason: "Authenticated Tuya observation has not started."),
            connectionStartedAtUptimeNanoseconds: nil,
            authenticatedAtUptimeNanoseconds: nil,
            latestObservedUptimeNanoseconds: nil,
            applicationPayloadCount: 0,
            connectionGeneration: 0
        )
        super.init()
    }

    static var isOfficialSDKLinked: Bool {
        #if canImport(ThingSmartHomeKit)
        true
        #else
        false
        #endif
    }

    func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        snapshot
    }

    /// Begins only an official SDK-owned connection to an already-bound device.
    /// AppKey/AppSecret are supplied by a private local build/operator surface and are never
    /// serialized by this runtime.
    func start(
        device: DeviceIdentity,
        appKey: String,
        appSecret: String
    ) {
        exportData = nil
        dpEvents.removeAll(keepingCapacity: true)
        nextEventID = 1
        selectedDevice = device
        connectionStartedAtUptimeNanoseconds = nil
        authenticatedAtUptimeNanoseconds = nil
        latestObservedUptimeNanoseconds = nil
        hasSDKConnectSuccess = false

        guard device.isComplete else {
            fail("The selected Tuya device identity is incomplete. Re-link the bound scooter instead of guessing identifiers.")
            return
        }

        let normalizedKey = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSecret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty, !normalizedSecret.isEmpty else {
            fail("Private Tuya SDK AppKey/AppSecret are not provisioned in this build session.")
            return
        }

        #if canImport(ThingSmartHomeKit)
        connectionGeneration &+= 1
        if connectionGeneration == 0 { connectionGeneration = 1 }
        let startedAt = Self.monotonicNow()
        connectionStartedAtUptimeNanoseconds = startedAt
        snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticating,
            connectionStartedAtUptimeNanoseconds: startedAt,
            authenticatedAtUptimeNanoseconds: nil,
            latestObservedUptimeNanoseconds: nil,
            applicationPayloadCount: 0,
            connectionGeneration: connectionGeneration
        )
        phase = .authenticating
        statusMessage = "Tuya SDK is establishing the already-bound scooter session. No Nembra-authored DP command will be sent."

        ThingSmartSDK.sharedInstance()?.start(withAppKey: normalizedKey, secretKey: normalizedSecret)
        thingDevice = ThingSmartDevice(deviceId: device.deviceID)
        thingDevice?.delegate = self

        ThingSmartBLEManager.sharedInstance().connectBLE(
            withUUID: device.uuid,
            productKey: device.productKey,
            success: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.hasSDKConnectSuccess = true
                    self.statusMessage = "Official Tuya BLE connection established. Waiting for a passive authenticated DP notification; no controls are being queried or published."
                }
            },
            failure: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.fail("Tuya SDK BLE authentication/connection failed: \(error?.localizedDescription ?? "unknown error")")
                }
            }
        )
        #else
        fail("Official Tuya SmartLife SDK is not linked. Authentication is blocked rather than falling back to guessed BLE writes.")
        #endif
    }

    func stop() {
        #if canImport(ThingSmartHomeKit)
        if let selectedDevice {
            ThingSmartBLEManager.sharedInstance().disconnectBLE(withUUID: selectedDevice.uuid)
        }
        thingDevice?.delegate = nil
        thingDevice = nil
        #endif
        hasSDKConnectSuccess = false
        if case .accepted = phase {
            statusMessage = "Accepted authenticated observation is sealed. The SDK link is stopped."
        } else if case .failed = phase {
            // Preserve the failure reason.
        } else {
            phase = Self.isOfficialSDKLinked ? .idle : .sdkUnavailable
            statusMessage = Self.isOfficialSDKLinked
                ? "Read-only Tuya observation stopped."
                : "Official Tuya SmartLife SDK is unavailable in this build."
        }
    }

    func prepareExport() {
        guard let selectedDevice else {
            statusMessage = "No bound Tuya scooter is selected."
            return
        }

        let duration: Double?
        if let authenticatedAtUptimeNanoseconds,
           let latestObservedUptimeNanoseconds,
           latestObservedUptimeNanoseconds >= authenticatedAtUptimeNanoseconds {
            duration = Double(latestObservedUptimeNanoseconds - authenticatedAtUptimeNanoseconds) / 1_000_000_000
        } else {
            duration = nil
        }

        let verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
        let authenticationResult: String
        switch verdict {
        case .readyForStationaryMapping:
            authenticationResult = "accepted"
        case .blocked:
            authenticationResult = hasSDKConnectSuccess ? "incomplete" : "rejected-or-not-established"
        }

        let envelope = ExportEnvelope(
            schemaVersion: 1,
            purpose: "Tuya-authenticated read-only ES80 preflight",
            createdAt: Date(),
            deviceID: selectedDevice.deviceID,
            deviceUUID: selectedDevice.uuid,
            productKey: selectedDevice.productKey,
            authenticationResult: authenticationResult,
            connectionGeneration: snapshot.connectionGeneration,
            secureConnectionDurationSeconds: duration,
            applicationNotificationCount: snapshot.applicationPayloadCount,
            payloadSource: "official-tuya-smartlife-sdk-decrypted-dp-update",
            redactions: [
                "appKeyExcluded": true,
                "appSecretExcluded": true,
                "accountPasswordExcluded": true,
                "accessTokenExcluded": true,
                "refreshTokenExcluded": true,
                "localKeyExcluded": true,
                "sessionKeyExcluded": true
            ],
            events: dpEvents,
            limitations: [
                "DP update callbacks are SDK-decrypted application evidence, not raw GATT characteristic bytes.",
                "No DP meanings, units, scaling, cadence, or control acknowledgement are inferred by this artifact.",
                "No unbind, reset, pairing, firmware, speed-limit, lock, light, motor, mode, brake, or other control command is exposed by this runtime."
            ]
        )

        do {
            exportData = try JSONEncoder.prettyNembra.encode(envelope)
            exportFilename = "Nembra-Tuya-Authenticated-\(String(selectedDevice.deviceID.prefix(8)))-ReadOnly.json"
            statusMessage = authenticationResult == "accepted"
                ? "Authenticated read-only artifact is ready to share."
                : "Diagnostic read-only artifact is ready. The physical gate remains blocked."
        } catch {
            fail("Could not encode the authenticated read-only artifact: \(error.localizedDescription)")
        }
    }

    private func acceptPassiveDPUpdate(_ dps: [AnyHashable: Any]) {
        guard hasSDKConnectSuccess, let selectedDevice, !dps.isEmpty else { return }
        let now = Self.monotonicNow()
        if authenticatedAtUptimeNanoseconds == nil {
            authenticatedAtUptimeNanoseconds = now
        }
        latestObservedUptimeNanoseconds = now

        var values: [String: String] = [:]
        values.reserveCapacity(dps.count)
        for (key, value) in dps {
            values[String(describing: key)] = Self.safeDPValue(value)
        }
        dpEvents.append(
            DPEvent(
                id: nextEventID,
                wallClock: Date(),
                monotonicNanoseconds: now,
                source: "official-tuya-smartlife-sdk-decrypted-dp-update",
                deviceID: selectedDevice.deviceID,
                values: values
            )
        )
        nextEventID &+= 1

        snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            connectionStartedAtUptimeNanoseconds: connectionStartedAtUptimeNanoseconds,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: latestObservedUptimeNanoseconds,
            applicationPayloadCount: dpEvents.count,
            connectionGeneration: connectionGeneration
        )

        switch TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) {
        case .readyForStationaryMapping:
            phase = .accepted
            statusMessage = "AUTHENTICATED READ-ONLY GATE PASSED · passive Tuya application data survived the required 45-second evidence window."
        case let .blocked(reason):
            phase = .observing
            statusMessage = "Authenticated application data received. Keep the scooter stationary and Capture open. \(reason)"
        }
    }

    private func fail(_ reason: String) {
        phase = .failed(reason)
        statusMessage = reason
        snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .failed(reason: reason),
            connectionStartedAtUptimeNanoseconds: connectionStartedAtUptimeNanoseconds,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: latestObservedUptimeNanoseconds,
            applicationPayloadCount: dpEvents.count,
            connectionGeneration: connectionGeneration
        )
    }

    private static func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func safeDPValue(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        if JSONSerialization.isValidJSONObject(["value": value]),
           let data = try? JSONSerialization.data(withJSONObject: ["value": value], options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "<unsupported-value-type>"
    }
}

#if canImport(ThingSmartHomeKit)
extension TuyaSmartLifeReadOnlyRuntime: ThingSmartDeviceDelegate {
    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps else { return }
        acceptPassiveDPUpdate(dps)
    }
}
#endif

private extension JSONEncoder {
    static var prettyNembra: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
