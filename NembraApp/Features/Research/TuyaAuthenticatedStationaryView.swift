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
    @Published private(set) var diagnosticData: Data?
    @Published private(set) var diagnosticFilename = "Nembra-Tuya-Authenticated-Preflight.json"

    private let bridge = NembraTuyaSDKBridge()
    private var credential: TuyaCaptureCredential?
    private var connectionGeneration: UInt64 = 0
    private var authenticatedAtUptimeNanoseconds: UInt64?
    private var latestObservedUptimeNanoseconds: UInt64?
    private var observationTask: Task<Void, Never>?
    private var events: [DecodedDPEvent] = []

    deinit {
        observationTask?.cancel()
    }

    init() {
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
        case .observing: return "Secure channel observing"
        case .secureChannelProven: return "Secure channel proven"
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
            return "Nembra is asking Tuya's documented existing-device BLE API to establish the bound session. No DP control command is available in this build."
        case .observing:
            return "Authenticated transport is alive. Nembra is waiting for genuine SDK-decoded device reports and the 45-second stability window."
        case .secureChannelProven:
            return "The official Tuya session survived the stability window and delivered application data. This proves authenticated transport, but it does not claim raw FD50 bytes or any ES80 DP meaning yet."
        }
    }

    var canStart: Bool {
        if case .ready = phase { return true }
        return false
    }

    var minimumWindowSeconds: Double { 45 }

    func refreshReadiness() {
        observationTask?.cancel()
        observationTask = nil
        authenticatedDurationSeconds = 0
        decodedDPEventCount = 0
        events = []
        diagnosticData = nil
        authenticatedAtUptimeNanoseconds = nil
        latestObservedUptimeNanoseconds = nil

        guard let stored = TuyaCaptureCredentialStore.load() else {
            credential = nil
            phase = .blocked("No saved bound-scooter credential is available. Complete the one-time Tuya device selection first; do not repeat the outdoor ride capture.")
            return
        }
        credential = stored

        guard bridge.sdkAvailable else {
            phase = .blocked("The official Tuya SmartLife SDK is not linked into this standalone field build yet. Raw FD50 writes remain locked; Nembra will not guess the authentication handshake.")
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
            phase = .blocked("The Tuya SDK is configured, but its own official account session is not authorized yet. The existing Tuya Smart binding is preserved; no re-pair, reset, or unbind is allowed.")
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
        events = []
        diagnosticData = nil
        authenticatedAtUptimeNanoseconds = nil
        latestObservedUptimeNanoseconds = nil

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
        observationTask?.cancel()
        observationTask = nil
        if let credential {
            bridge.disconnectUUID(credential.uuid)
        }
        prepareDiagnostic(result: "stopped")
        refreshReadiness()
    }

    private func consumeBridgeUpdate(authenticated: Bool, dps: [AnyHashable: Any]?, error: Error?) {
        if let error {
            observationTask?.cancel()
            observationTask = nil
            phase = .failed(error.localizedDescription)
            prepareDiagnostic(result: "rejected")
            return
        }
        guard authenticated else { return }

        let now = DispatchTime.now().uptimeNanoseconds
        if authenticatedAtUptimeNanoseconds == nil {
            authenticatedAtUptimeNanoseconds = now
            latestObservedUptimeNanoseconds = now
            phase = .observing
            beginObservationClock()
        } else {
            latestObservedUptimeNanoseconds = now
        }

        if let dps, !dps.isEmpty {
            let normalized = Self.normalizedJSONObject(dps)
            events.append(
                DecodedDPEvent(
                    observedAt: ISO8601DateFormatter().string(from: Date()),
                    values: normalized
                )
            )
            decodedDPEventCount += 1
        }
        evaluateGate(now: now)
    }

    private func beginObservationClock() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                let now = DispatchTime.now().uptimeNanoseconds
                await MainActor.run {
                    guard let self else { return }
                    self.latestObservedUptimeNanoseconds = now
                    self.evaluateGate(now: now)
                }
            }
        }
    }

    private func evaluateGate(now: UInt64) {
        guard let authenticatedAtUptimeNanoseconds else { return }
        let elapsed = now >= authenticatedAtUptimeNanoseconds ? now - authenticatedAtUptimeNanoseconds : 0
        authenticatedDurationSeconds = Double(elapsed) / 1_000_000_000

        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            connectionStartedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: now,
            applicationPayloadCount: decodedDPEventCount,
            connectionGeneration: connectionGeneration
        )

        if case .readyForStationaryMapping = TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) {
            observationTask?.cancel()
            observationTask = nil
            phase = .secureChannelProven
            prepareDiagnostic(result: "accepted-sdk-decoded")
        }
    }

    private func prepareDiagnostic(result: String) {
        let encodedEvents: [[String: Any]] = events.map {
            ["observedAt": $0.observedAt, "dps": $0.values]
        }
        let envelope: [String: Any] = [
            "schemaVersion": 1,
            "purpose": "Tuya authenticated stationary preflight",
            "transportFamily": "tuya-fd50",
            "authMethod": "tuya-smartlife-sdk",
            "authenticationResult": result,
            "secureConnectionDurationSeconds": authenticatedDurationSeconds,
            "sdkDecodedDPEventCount": decodedDPEventCount,
            "rawCharacteristicPayloadCount": 0,
            "decodedEvents": encodedEvents,
            "safety": [
                "readOnly": true,
                "controlDPsSent": false,
                "pairingOrActivationAttempted": false,
                "resetOrUnbindAttempted": false,
                "credentialsExported": false,
                "rawCharacteristicBytesClaimed": false
            ],
            "truthBoundary": "SDK-decoded DP callbacks prove application data only. This artifact does not claim raw FD50 notification bytes or accepted ES80 DP semantics."
        ]
        diagnosticData = try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        diagnosticFilename = "Nembra-Tuya-Authenticated-Preflight-\(result).json"
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
                    Text("Prove the Tuya secure channel")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("No riding. No control DPs. The goal is only to survive the old ~30-second rejection and observe genuine application data through Tuya's supported stack.")
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
                    metric("SDK device reports", "\(model.decodedDPEventCount)")
                    metric("Raw FD50 bytes", "NOT CLAIMED")
                }
                .authenticatedCard()

                VStack(alignment: .leading, spacing: 10) {
                    Label("READ-ONLY BOUNDARY", systemImage: "lock.shield.fill")
                        .font(.headline)
                    Text("This path exposes no generic BLE write, DP publish, pairing, activation, reset, unbind, firmware, speed-limit, lock, mode, light, motor, brake, or cruise command API.")
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
                } else {
                    Button("Re-check readiness") { model.refreshReadiness() }
                        .buttonStyle(.bordered)
                }

                if let data = model.diagnosticData {
                    ShareLink(item: TuyaAuthenticatedDiagnosticExport(data: data, filename: model.diagnosticFilename), preview: SharePreview("Nembra authenticated preflight")) {
                        Label("Share preflight diagnostic", systemImage: "square.and.arrow.up")
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
        DataRepresentation(exportedContentType: .json) { export in
            export.data
        }
        .suggestedFileName { export in export.filename }
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
