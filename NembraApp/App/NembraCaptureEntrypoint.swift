@preconcurrency import CoreBluetooth
import Security
import SwiftUI

// Shared by the legacy raw capture implementation that remains compiled for later targeted BLE work.
let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable

@main
@MainActor
struct NembraCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            NembraTuyaMetadataTestView()
                .preferredColorScheme(.dark)
        }
    }
}

/// The next physical test is deliberately small and indoor-only.
/// It links the user's own Tuya Smart account, reads the scooter's cloud metadata/DP definitions,
/// prepares a redacted JSON, and then stops. It does not launch the old 17-step ride capture.
struct NembraTuyaMetadataTestView: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @State private var candidateCredentialSaved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    safetyCard
                    accountCard
                    if tuya.qrPayload != nil { approvalCard }
                    if tuya.isLinked { deviceCard }
                    if tuya.selectedDevice != nil { finishCard }
                }
                .padding(18)
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("Nembra Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT TEST · INDOORS")
                .font(.caption.monospaced().weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.green)
            Text("Teach Nembra the Tuya identity")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("No riding this time. Link Tuya Smart, choose the scooter, then send me the JSON this app makes. After that I can build the authenticated Bluetooth test from the device evidence instead of making you repeat the long ride capture.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ABOUT 2–5 MINUTES", systemImage: "clock.fill")
                .font(.headline)
            Label("Stay indoors — scooter riding is NOT needed", systemImage: "house.fill")
            Label("Do not enter your Tuya password", systemImage: "key.slash.fill")
            Label("No unbind, reset, lock, speed-limit, motor, or mode command", systemImage: "shield.checkered")
            Text("This build only reads your account's device metadata/status/specification information. The Bluetooth command path stays locked for this test.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .nextTestCard()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle("1", "Get your Tuya User Code")

            if tuya.isLinked {
                Label("Tuya approved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Refresh devices") { tuya.refreshDevices() }
                    .buttonStyle(.bordered)
            } else {
                Text("Open Tuya Smart → Me → Settings → Account and Security → User Code. Copy that User Code and paste it below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Paste User Code", text: $tuya.userCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    tuya.requestApproval()
                } label: {
                    HStack {
                        if tuya.phase == .requestingApproval { ProgressView().tint(.black) }
                        Text("Make approval QR")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }

            Text(tuya.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .nextTestCard()
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle("2", "Approve Nembra in Tuya Smart")

            if let data = tuya.qrPNGData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 240)
                    .frame(maxWidth: .infinity)

                Text("Because Tuya Smart is on this same iPhone: save/share this QR image, open Tuya Smart's scanner, choose the QR from Photos/Album, and approve it. Then come straight back here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ShareLink(item: TuyaQRCodeExport(data: data), preview: SharePreview("Tuya approval QR")) {
                    Label("Save / share approval QR", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button("I approved it · check now") { tuya.checkApprovalNow() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .nextTestCard()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle("3", "Choose your scooter")

            if tuya.phase == .loadingDevices {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading your Tuya devices…")
                        .foregroundStyle(.secondary)
                }
            } else if tuya.devices.isEmpty {
                Text("No devices are listed yet. Tap Refresh devices above once Tuya approval is complete.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tuya.devices) { device in
                    Button {
                        candidateCredentialSaved = TuyaCaptureCredentialCandidateStore.save(device: device)
                        tuya.selectDevice(device)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: device.id == tuya.selectedDeviceID ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(device.id == tuya.selectedDeviceID ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                let detail = [device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(device.online ? "ONLINE" : "OFFLINE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(device.online ? .green : .secondary)
                        }
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .nextTestCard()
    }

    private var finishCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle("4", "Send me the metadata JSON")

            if let device = tuya.selectedDevice {
                Label(device.name, systemImage: "scooter")
                    .font(.headline)
                Text("Nembra reads the device identity, current Tuya status, DP specifications, and local strategy. Secret account tokens and the cloud local_key candidate are excluded from the file you share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if candidateCredentialSaved {
                    Label("Tuya cloud local_key candidate saved securely on this iPhone. Its BLE-authentication role is NOT verified yet.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else if device.localKey.isEmpty {
                    Label("Tuya did not provide a cloud local_key candidate for this device; the JSON is still useful", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let data = tuya.redactedExportData {
                Label("NEXT TEST COMPLETE", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                ShareLink(item: TuyaMetadataExport(data: data, filename: tuya.redactedExportFilename), preview: SharePreview("Nembra Tuya metadata")) {
                    Label("Share metadata JSON", systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                Text("STOP HERE. Send that JSON to me. Do NOT redo the Bluetooth ride calibration yet.")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
            } else if tuya.phase == .loadingDevices {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading scooter metadata…")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Prepare metadata JSON") { tuya.prepareRedactedExport() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .nextTestCard()
    }

    private func stepTitle(_ number: String, _ title: String) -> some View {
        HStack(spacing: 9) {
            Text(number)
                .font(.caption.monospaced().bold())
                .frame(width: 25, height: 25)
                .background(.white.opacity(0.12), in: Circle())
            Text(title)
                .font(.headline)
        }
    }
}

private enum TuyaCaptureCredentialCandidateStore {
    private static let service = "com.jonathangana131.nembra.capturelearn.tuya"
    private static let account = "selected-scooter"

    struct StoredCandidate: Codable, Equatable {
        let schemaVersion: Int
        let credentialKind: String
        let sourceField: String
        let deviceID: String
        let productID: String
        let uuid: String
        let localKey: String

        init(device: TuyaAccountBridge.LinkedDevice) {
            schemaVersion = 1
            credentialKind = "tuya_cloud_local_key_candidate_unverified_for_ble_auth"
            sourceField = "local_key"
            deviceID = device.id
            productID = device.productID
            uuid = device.uuid
            localKey = device.localKey
        }
    }

    static func save(device: TuyaAccountBridge.LinkedDevice) -> Bool {
        guard !device.localKey.isEmpty else { return false }
        guard let data = try? JSONEncoder().encode(StoredCandidate(device: device)) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> StoredCandidate? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredCandidate.self, from: data)
    }
}

private extension View {
    func nextTestCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08)))
    }
}

/// Kept as a deliberate lock screen for the next phase after the metadata JSON is analyzed.
/// The authenticated Bluetooth write handshake is not exposed by this metadata-only build.
struct TuyaSecureLinkPreflightView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TUYA SECURE LINK")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.green)
            Text("Metadata first")
                .font(.largeTitle.bold())
            Text("Send the redacted metadata JSON first. Nembra can retain the cloud local_key candidate privately, but its BLE-authentication role remains unverified. The secure Bluetooth test stays locked until the protocol evidence supports the exact handshake.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
    }
}
