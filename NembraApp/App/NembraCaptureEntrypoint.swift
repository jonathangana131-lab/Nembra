@preconcurrency import CoreBluetooth
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
    @State private var savedCredential = TuyaCaptureCredentialStore.load()

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
        .onChange(of: tuya.phase) { _, phase in
            guard phase == .ready, let device = tuya.selectedDevice else { return }
            _ = TuyaCaptureCredentialStore.save(
                device: device,
                detailMetadata: tuya.selectedDeviceMetadata
            )
            savedCredential = TuyaCaptureCredentialStore.load()
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
            Text("No riding this time. Link Tuya Smart, choose the scooter, then send me the JSON this app makes. After that I can build the authenticated Bluetooth test instead of making you repeat the long ride capture.")
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
                    .textInputAutitalizationNever()
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
                        _ = TuyaCaptureCredentialStore.save(device: device)
                        savedCredential = TuyaCaptureCredentialStore.load()
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
                Text("Nembra reads the device identity, current Tuya status, DP specifications, and local strategy. Secret account tokens, local_key, and secKey are excluded from the file you share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if savedCredential?.deviceID == device.id {
                    Label("Private scooter credential saved in this iPhone's Keychain for the next Nembra test", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                    if savedCredential?.hasCandidateBoundSessionMaterial == true {
                        Label("Tuya returned both private bound-session key inputs", systemImage: "checkmark.shield.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Label("Local key retained; this authorized route did not return the separate Tuya secKey yet", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if device.localKey.isEmpty {
                    Label("Tuya did not provide a private local key for this device; the JSON is still useful", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Private credential could not be saved. The previous Keychain credential was preserved.", systemImage: "exclamationmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.orange)
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

private extension View {
    func nextTestCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08)))
    }

    func textInputAutitalizationNever() -> some View {
        textInputAutocapitalization(.never)
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
            Text("Send the redacted metadata JSON first. The secure Bluetooth test stays locked until Nembra can build it from your actual bound-device information instead of guessing.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
    }
}
