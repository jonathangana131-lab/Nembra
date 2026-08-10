@preconcurrency import CoreBluetooth
import SwiftUI

// Shared by the legacy raw capture implementation that remains compiled for later targeted BLE work.
let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable

@main
@MainActor
struct NembraCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            NembraCaptureNextGateRouter()
                .preferredColorScheme(.dark)
        }
    }
}

/// Routes the field build straight to the next unfinished physical gate when the
/// already-bound scooter identity is present in Keychain. This intentionally avoids
/// making the user repeat the metadata authorization/select-device step on every build.
struct NembraCaptureNextGateRouter: View {
    @State private var hasStoredCredential = TuyaCaptureCredentialVault.load() != nil

    var body: some View {
        NavigationStack {
            if hasStoredCredential {
                TuyaSecureLinkPreflightView()
            } else {
                TuyaCredentialBootstrapView {
                    hasStoredCredential = true
                }
            }
        }
    }
}

/// Small indoor-only recovery path for a clean install or missing Keychain item.
/// It reads the user's own Tuya device list, stores the selected scooter credential
/// with ThisDeviceOnly Keychain protection, and immediately advances to secure-link
/// preflight. It never pairs, activates, resets, unbinds, or sends a control DP.
struct TuyaCredentialBootstrapView: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @State private var saveError: String?
    let onCredentialSaved: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                safetyCard
                accountCard
                if tuya.qrPayload != nil { approvalCard }
                if tuya.isLinked { deviceCard }
            }
            .padding(18)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("Nembra Capture")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ONE-TIME RECOVERY · INDOORS")
                .font(.caption.monospaced().weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.green)
            Text("Recover the bound scooter identity")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("This screen appears only because the private scooter credential is not in this install's Keychain. No riding or Bluetooth re-pairing is needed.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("READ-ONLY ACCOUNT LINK", systemImage: "lock.shield.fill")
                .font(.headline)
            Label("Stay indoors — riding is not needed", systemImage: "house.fill")
            Label("Do not reset, unbind, or re-pair the scooter", systemImage: "arrow.triangle.2.circlepath.circle")
            Label("No lock, mode, speed-limit, motor, light, brake, or cruise command", systemImage: "shield.checkered")
        }
        .bootstrapCard()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tuya.isLinked ? "Tuya account approved" : "Authorize device-list access", systemImage: tuya.isLinked ? "checkmark.circle.fill" : "person.badge.key.fill")
                .font(.headline)
                .foregroundStyle(tuya.isLinked ? .green : .primary)

            if tuya.isLinked {
                Button("Refresh devices") { tuya.refreshDevices() }
                    .buttonStyle(.bordered)
            } else {
                Text("In Tuya Smart: Me → Settings → Account and Security → User Code. Paste only that User Code here. Nembra does not ask for your Tuya password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Paste Tuya User Code", text: $tuya.userCode)
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
        .bootstrapCard()
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Approve in Tuya Smart", systemImage: "qrcode")
                .font(.headline)

            if let data = tuya.qrPNGData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 240)
                    .frame(maxWidth: .infinity)

                Text("On this same iPhone, save/share the QR, open Tuya Smart's scanner, choose it from Photos/Album, approve, then return here.")
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
        }
        .bootstrapCard()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Choose the already-bound scooter", systemImage: "scooter")
                    .font(.headline)
                Spacer()
                if tuya.phase == .loadingDevices { ProgressView() }
            }

            if tuya.devices.isEmpty {
                Text("No Tuya devices are available yet. Refresh after approval completes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tuya.devices) { device in
                    Button {
                        saveError = nil
                        guard TuyaCaptureCredentialVault.save(device: device) else {
                            saveError = device.localKey.isEmpty
                                ? "Tuya did not provide the bound-device credential for this device. Nembra will not guess it."
                                : "The private scooter credential could not be saved to this iPhone's Keychain."
                            return
                        }
                        tuya.selectDevice(device)
                        onCredentialSaved()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
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
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(device.online ? .green : .secondary)
                        }
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .bootstrapCard()
    }
}

private extension View {
    func bootstrapCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08)))
    }
}
