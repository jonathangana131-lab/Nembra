import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class TuyaSecureLinkPreflightModel: ObservableObject {
    enum Phase: Equatable {
        case checking
        case blocked(String)
        case ready
        case connecting
        case observing
        case secureChannelProven
        case failed(String)
    }

    struct DecodedDPEvent {
        let observedAt: String
        let values: [String: Any]
    }

    @Published private(set) var phase: Phase = .checking
    @Published private(set) var authenticatedDurationSeconds: Double = 0
    @Published private(set) var decodedDPEventCount = 0
    @Published private(set) var rawCharacteristicPayloadCount = 0
    @Published private(set) var rawObserverStatus = "NOT STARTED"
    @Published private(set) var diagnosticData: Data?
    @Published private(set) var diagnosticFilename = "Nembra-Tuya-Authenticated-Preflight.json"

    private let bridge = NembraTuyaSDKBridge()
    private let rawObserver = TuyaFD50RawObserver()
    private var credential: TuyaCaptureCredential?
    private var connectionGeneration: UInt64 = 0
    private var authenticatedAtUptimeNanoseconds: UInt64?
    private var observationTask: Task<Void, Never>?
    private var decodedEvents: [DecodedDPEvent] = []
    private var rawEvents: [TuyaFD50RawObserver.Event] = []

    init() {
        rawObserver.onStateChange = { [weak self] state in
            self?.consumeRawObserverState(state)
        }
        rawObserver.onPayload = { [weak self] event in
            self?.consumeRawPayload(event)
        }
        refreshReadiness()
    }

    var sdkAvailable: Bool { bridge.sdkAvailable }
    var sdkUserLoggedIn: Bool { bridge.sdkUserLoggedIn }

    var statusTitle: String {
        switch phase {
        case .checking: return "Checking authenticated transport"
        case .blocked: return "Authenticated transport blocked"
        case .ready: return "Ready for stationary authentication"
        case .connecting: return "Authenticating with Tuya"
        case .observing: return "Secure channel + raw FD50 observing"
        case .secureChannelProven: return "Authenticated raw channel proven"
        case .failed: return "Authenticated preflight failed"
        }
    }

    var statusDetail: String {
        switch phase {
        case .checking:
            return "Checking the saved bound-device identity and official Tuya SDK runtime."
        case .blocked(let reason), .failed(let reason):
            return reason
        case .ready:
            return "Scooter identity and official Tuya session are ready. Keep the scooter stationary and powered on, then start the read-only test."
        case .connecting:
            return "Nembra is asking Tuya's supported existing-device BLE API to establish the bound session. Nembra itself has no application write or DP-control path in this test."
        case .observing:
            return "Tuya owns authentication. In parallel, Nembra is passively subscribed to the exact FD50 notify characteristic already proven by physical capture C7D09A22. Acceptance needs raw notify bytes and 45 seconds of continuously live Tuya BLE state."
        case .secureChannelProven:
            return "The Tuya-authenticated BLE session stayed locally connected for the full stability window and Nembra captured genuine raw FD50 notify bytes. DP meanings remain unknown until the next stationary correlation experiment."
        }
    }

    var canStart: Bool {
        if case .ready = phase { return true }
        return false
    }

    var canStop: Bool {
        switch phase {
        case .connecting, .observing: return true
        default: return false
        }
    }

    var canRecheck: Bool {
        switch phase {
        case .blocked, .failed: return true
        default: return false
        }
    }

    var minimumWindowSeconds: Double { 45 }

    func refreshReadiness() {
        observationTask?.cancel()
        observationTask = nil
        if let credential {
            bridge.disconnectUUID(credential.uuid)
        }
        rawObserver.stop()

        authenticatedDurationSeconds = 0
        decodedDPEventCount = 0
        rawCharacteristicPayloadCount = 0
        rawObserverStatus = "NOT STARTED"
        decodedEvents = []
        rawEvents = []
        diagnosticData = nil
        authenticatedAtUptimeNanoseconds = nil

        guard let stored = TuyaCaptureCredentialVault.load() else {
            credential = nil
            phase = .blocked("No saved bound-scooter credential is available. Complete the one-time Tuya device selection first; do not repeat the outdoor ride capture.")
            return
        }
        credential = stored

        guard bridge.sdkAvailable else {
            phase = .blocked("The official Tuya SmartLife SDK is not linked into this standalone field build yet. Raw FD50 authentication writes remain locked; Nembra will not guess the secure handshake.")
            return
        }

        let appKey = Self.bundleSecret(named: "NEMBRA_TUYA_APP_KEY")
        let appSecret = Self.bundleSecret(named: "NEMBRA_TUYA_APP_SECRET")
        guard let appKey, let appSecret else {
            phase = .blocked("The Tuya SDK is present, but this build has no privately provisioned AppKey/AppSecret for its exact bundle identifier.")
            return
        }

        bridge.configure(withAppKey: appKey, appSecret: appSecret)
        guard bridge.sdkUserLoggedIn else {
            phase = .blocked("The Tuya SDK is configured, but its own supported account session is not authorized yet. The existing Tuya Smart binding is preserved; no re-pair, reset, or unbind is allowed.")
            return
        }

        guard !stored.deviceID.isEmpty, !stored.uuid.isEmpty, !stored.productID.isEmpty else {
            phase = .blocked("The saved Tuya device identity is incomplete. Nembra will not choose a different nearby Tuya device by guesswork.")
            return
        }

        phase = .ready
    }

    func start() {
        guard canStart, let credential else { return }
        connectionGeneration &+= 1
        phase = .connecting
        authenticatedDurationSeconds = 0
        decodedDPEventCount = 0
        rawCharacteristicPayloadCount = 0
        rawObserverStatus = "WAITING FOR TUYA AUTH"
        decodedEvents = []
        rawEvents = []
        diagnosticData = nil
        authenticatedAtUptimeNanoseconds = nil

        bridge.connectDeviceID(
            credential.deviceID,
            uuid: credential.uuid,
            productID: credential.productID
        ) { [weak self] authenticated, dps, error in
            Task { @MainActor in
                self?.consumeBridgeUpdate(authenticated: authenticated, dps: dps, error: error)
            }
        }
    }

    func stop() {
        guard canStop else { return }
        observationTask?.cancel()
        observationTask = nil
        rawObserver.stop()
        if let credential {
            bridge.disconnectUUID(credential.uuid)
        }
        prepareDiagnostic(result: "stopped")
        phase = .blocked("The stationary test was stopped safely. No control command was sent. Re-check readiness when you want to retry.")
    }

    private func consumeBridgeUpdate(authenticated: Bool, dps: [AnyHashable: Any]?, error: Error?) {
        if let error {
            failExperiment(error.localizedDescription, result: "rejected")
            return
        }
        guard authenticated else { return }
        guard let credential, bridge.isLocallyConnectedUUID(credential.uuid) else {
            failExperiment("Tuya did not report a live local BLE session for the bound scooter.", result: "not-locally-connected")
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if authenticatedAtUptimeNanoseconds == nil {
            authenticatedAtUptimeNanoseconds = now
            phase = .observing
            rawObserverStatus = "ATTACHING TO VERIFIED FD50"
            rawObserver.start()
            beginObservationClock()
        }

        if let dps, !dps.isEmpty {
            decodedEvents.append(
                DecodedDPEvent(
                    observedAt: ISO8601DateFormatter().string(from: Date()),
                    values: Self.normalizedJSONObject(dps)
                )
            )
            decodedDPEventCount += 1
        }
        evaluateGate(now: now)
    }

    private func consumeRawObserverState(_ state: TuyaFD50RawObserver.State) {
        switch state {
        case .idle:
            rawObserverStatus = "NOT STARTED"
        case .waitingForBluetooth:
            rawObserverStatus = "WAITING FOR BLUETOOTH"
        case .retrievingVerifiedPeripheral:
            rawObserverStatus = "MATCHING C7D09A22 TARGET"
        case .connecting:
            rawObserverStatus = "ATTACHING READ-ONLY"
        case .discovering:
            rawObserverStatus = "VERIFYING FD50"
        case .subscribing:
            rawObserverStatus = "SUBSCRIBING TO NOTIFY"
        case .observing:
            rawObserverStatus = "RAW NOTIFY ACTIVE"
        case .failed(let reason):
            rawObserverStatus = "FAILED"
            if case .observing = phase {
                failExperiment(reason, result: "raw-observer-failed")
            }
        case .stopped:
            rawObserverStatus = "STOPPED"
        }
    }

    private func consumeRawPayload(_ event: TuyaFD50RawObserver.Event) {
        guard case .observing = phase else { return }
        guard let credential, bridge.isLocallyConnectedUUID(credential.uuid) else {
            failExperiment("A raw FD50 notification arrived after Tuya's local BLE authority was lost, so it was rejected from the artifact.", result: "authority-lost-before-raw-receipt")
            return
        }
        rawEvents.append(event)
        rawCharacteristicPayloadCount += 1
        evaluateGate(now: event.receivedAtUptimeNanoseconds)
    }

    private func beginObservationClock() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard case .observing = self.phase else { return }
                    guard let credential = self.credential,
                          self.bridge.isLocallyConnectedUUID(credential.uuid) else {
                        self.failExperiment(
                            "Tuya's own local BLE status dropped before the 45-second stability window completed.",
                            result: "disconnected-before-stability-window"
                        )
                        return
                    }
                    self.evaluateGate(now: DispatchTime.now().uptimeNanoseconds)
                }
            }
        }
    }

    private func evaluateGate(now: UInt64) {
        guard case .observing = phase,
              let authenticatedAtUptimeNanoseconds,
              now >= authenticatedAtUptimeNanoseconds else { return }

        let elapsed = now - authenticatedAtUptimeNanoseconds
        authenticatedDurationSeconds = Double(elapsed) / 1_000_000_000

        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            connectionStartedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: now,
            applicationPayloadCount: rawCharacteristicPayloadCount,
            connectionGeneration: connectionGeneration
        )

        guard case .readyForStationaryMapping = TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) else {
            return
        }

        observationTask?.cancel()
        observationTask = nil
        phase = .secureChannelProven
        prepareDiagnostic(result: "accepted-raw-fd50")
        rawObserver.stop()
        if let credential {
            bridge.disconnectUUID(credential.uuid)
        }
    }

    private func failExperiment(_ reason: String, result: String) {
        guard case .secureChannelProven = phase else {
            observationTask?.cancel()
            observationTask = nil
            prepareDiagnostic(result: result)
            phase = .failed(reason)
            rawObserver.stop()
            if let credential {
                bridge.disconnectUUID(credential.uuid)
            }
            return
        }
    }

    private func prepareDiagnostic(result: String) {
        let encodedDecodedEvents: [[String: Any]] = decodedEvents.map {
            ["observedAt": $0.observedAt, "dps": $0.values]
        }
        let iso = ISO8601DateFormatter()
        let encodedRawEvents: [[String: Any]] = rawEvents.map { event in
            [
                "observedAt": iso.string(from: event.receivedAtWallClock),
                "receiptUptimeNanoseconds": String(event.receivedAtUptimeNanoseconds),
                "characteristicUUID": event.characteristicUUID,
                "payloadHex": Self.hex(event.payload),
                "payloadBase64": event.payload.base64EncodedString(),
                "byteCount": event.payload.count
            ]
        }

        let envelope: [String: Any] = [
            "schemaVersion": 2,
            "purpose": "Tuya authenticated stationary raw FD50 preflight",
            "physicalReferenceCaptureID": "C7D09A22-96DA-4E46-9BEF-E36F670ADB0E",
            "verifiedCoreBluetoothPeripheral": TuyaFD50RawObserver.verifiedPeripheralIdentifier.uuidString,
            "transportFamily": "tuya-fd50",
            "serviceUUID": TuyaFD50RawObserver.serviceUUID.uuidString,
            "notifyCharacteristicUUID": TuyaFD50RawObserver.notifyCharacteristicUUID.uuidString,
            "authMethod": "tuya-smartlife-sdk",
            "authenticationResult": result,
            "secureConnectionDurationSeconds": authenticatedDurationSeconds,
            "rawCharacteristicPayloadCount": rawCharacteristicPayloadCount,
            "sdkDecodedDPEventCount": decodedDPEventCount,
            "rawNotifications": encodedRawEvents,
            "sdkDecodedEvents": encodedDecodedEvents,
            "safety": [
                "nembraApplicationWritesSent": false,
                "nembraControlDPsSent": false,
                "pairingOrActivationAttempted": false,
                "resetOrUnbindAttempted": false,
                "credentialsExported": false,
                "rawObserverUsesVerifiedPeripheralOnly": true
            ],
            "truthBoundary": "Raw notification bytes are preserved exactly as received from FD50 characteristic 00000002 while Tuya's SDK reports the same bound device locally connected. No DP meaning, decryption, telemetry field, command acknowledgement, or physical control semantics are asserted by this artifact."
        ]
        diagnosticData = try? JSONSerialization.data(
            withJSONObject: envelope,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        diagnosticFilename = "Nembra-Tuya-Authenticated-Raw-FD50-\(result).json"
    }

    private static func bundleSecret(named key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    private static func normalizedJSONObject(_ dictionary: [AnyHashable: Any]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        for (key, value) in dictionary {
            normalized[String(describing: key)] = jsonSafe(value)
        }
        return normalized
    }

    private static func jsonSafe(_ value: Any) -> Any {
        if value is NSNull || value is String || value is NSNumber { return value }
        if let dictionary = value as? [AnyHashable: Any] { return normalizedJSONObject(dictionary) }
        if let array = value as? [Any] { return array.map(jsonSafe) }
        return String(describing: value)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

struct TuyaSecureLinkPreflightView: View {
    @StateObject private var model = TuyaSecureLinkPreflightModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AUTHENTICATED GATE · STATIONARY")
                        .font(.caption.monospaced().weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.green)
                    Text("Prove + capture the Tuya secure channel")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("No riding. Tuya handles authentication; Nembra only listens to the exact raw FD50 notify path already identified on your scooter.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(model.statusTitle, systemImage: statusIcon)
                        .font(.headline)
                    Text(model.statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider().overlay(.white.opacity(0.1))
                    metric("Official SDK", model.sdkAvailable ? "PRESENT" : "MISSING")
                    metric("SDK account", model.sdkUserLoggedIn ? "AUTHORIZED" : "NOT AUTHORIZED")
                    metric("Secure duration", String(format: "%.1f / %.0f s", model.authenticatedDurationSeconds, model.minimumWindowSeconds))
                    metric("Raw FD50 observer", model.rawObserverStatus)
                    metric("Raw notify payloads", "\(model.rawCharacteristicPayloadCount)")
                    metric("SDK decoded reports", "\(model.decodedDPEventCount)")
                }
                .authenticatedCard()

                VStack(alignment: .leading, spacing: 10) {
                    Label("READ-ONLY NEMBRA BOUNDARY", systemImage: "lock.shield.fill")
                        .font(.headline)
                    Text("Nembra exposes no generic BLE write, DP publish, pairing, activation, reset, unbind, firmware, speed-limit, lock, mode, light, motor, brake, or cruise command API. CoreBluetooth only enables notifications on the proven FD50 notify characteristic.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .authenticatedCard()

                if model.canStart {
                    Button {
                        model.start()
                    } label: {
                        Label("Start 45-second stationary test", systemImage: "wave.3.right.circle.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                } else if model.canStop {
                    Button(role: .cancel) {
                        model.stop()
                    } label: {
                        Label("Stop test", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else if model.canRecheck {
                    Button("Re-check readiness") { model.refreshReadiness() }
                        .buttonStyle(.bordered)
                }

                if let data = model.diagnosticData {
                    ShareLink(
                        item: TuyaAuthenticatedDiagnosticExport(data: data, filename: model.diagnosticFilename),
                        preview: SharePreview("Nembra authenticated FD50 preflight")
                    ) {
                        Label("Share raw preflight diagnostic", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("Secure Link")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusIcon: String {
        switch model.phase {
        case .ready, .secureChannelProven: return "checkmark.seal.fill"
        case .connecting, .observing, .checking: return "antenna.radiowaves.left.and.right"
        case .blocked, .failed: return "exclamationmark.lock.fill"
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced().weight(.semibold))
        }
    }
}

struct TuyaAuthenticatedDiagnosticExport: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in export.data }
            .suggestedFileName { $0.filename }
    }
}

private extension View {
    func authenticatedCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08)))
    }
}
