@preconcurrency import CoreBluetooth
import Foundation
import NembraBluetoothCapture
import NembraCore
import SwiftUI

/// A product-facing shell around the passive ES80 research controller.
///
/// This view deliberately does not create a second evidence model. Selecting
/// Start Capture invokes the controller's real target-session/connect boundary;
/// Finish Capture prepares the controller's versioned export while the phone is
/// safely stopped, then ends the CoreBluetooth connection.
@MainActor
struct ES80CaptureShellView: View {
    private enum Phase: Equatable {
        case bluetoothUnavailable(String)
        case ready
        case scanning
        case candidateSelected
        case connecting
        case preparingEvidence
        case capturing
        case disconnectedCaptureReady
        case finishing
        case finished
        case failed(String)
    }

    private struct PreparedCaptureSummary: Equatable {
        let recordCount: Int
        let valueObservationCount: Int
        let continuityBreakCount: Int
        let observedSpanSeconds: TimeInterval
        let schemaVersion: Int

        init(session: PassiveBluetoothCaptureSession) {
            recordCount = session.records.count
            valueObservationCount = session.records.reduce(into: 0) { count, record in
                if case .value = record.event { count += 1 }
            }
            continuityBreakCount = session.records.reduce(into: 0) { count, record in
                if record.event.breaksByteContinuity { count += 1 }
            }
            schemaVersion = PassiveBluetoothCaptureJSON.currentSchemaVersion

            if let first = session.records.first, let last = session.records.last {
                let elapsedNanoseconds = last.receivedAtUptimeNanoseconds - first.receivedAtUptimeNanoseconds
                observedSpanSeconds = TimeInterval(elapsedNanoseconds) / 1_000_000_000
            } else {
                observedSpanSeconds = 0
            }
        }

        var observedSpanDescription: String {
            if observedSpanSeconds < 1 {
                return String(format: "%.2f s", observedSpanSeconds)
            }
            if observedSpanSeconds < 60 {
                return String(format: "%.1f s", observedSpanSeconds)
            }

            let wholeSeconds = Int(observedSpanSeconds.rounded(.down))
            return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
        }
    }

    let controller: ForegroundCoreBluetoothCaptureController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedCandidateIdentifier: UUID?
    @State private var diagnosticMessage: String?
    @State private var exportDocument: PassiveCaptureJSONDocument?
    @State private var preparedSummary: PreparedCaptureSummary?
    @State private var isExporting = false
    @State private var isPreparingExport = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    safetyStrip
                    primaryContent
                    if let diagnosticMessage {
                        diagnosticBanner(diagnosticMessage)
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
        }
        .navigationTitle("Nembra Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canShowAdvancedConsole {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ES80PassiveCaptureResearchView(controller: controller)
                    } label: {
                        Label("Advanced details", systemImage: "waveform.path.ecg")
                    }
                    .accessibilityIdentifier("es80.capture.advanced")
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Nembra-passive-bluetooth-capture"
        ) { result in
            switch result {
            case .success:
                diagnosticMessage = "Capture file exported. Keep it unchanged for offline analysis."
            case let .failure(error):
                diagnosticMessage = "The capture is still prepared, but export did not finish: \(error.localizedDescription)"
            }
        }
        .accessibilityIdentifier("es80.capture-shell")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 52, height: 52)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("NEMBRA / ES80 RESEARCH")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    Text("Capture real Bluetooth evidence.")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text("PASSIVE ONLY")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var safetyStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Passive evidence only")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Set up while stationary. Once capture is active, put the phone away and do not interact with it while riding. Nembra does not send application characteristic writes from this tool.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var primaryContent: some View {
        switch phase {
        case let .bluetoothUnavailable(message):
            statePanel(
                eyebrow: "PREFLIGHT",
                title: "Bluetooth is not ready",
                message: message,
                symbol: "antenna.radiowaves.left.and.right.slash"
            )
            primaryButton("Scan for scooter", systemImage: "dot.radiowaves.left.and.right", disabled: true) {}

        case .ready:
            statePanel(
                eyebrow: "STEP 1",
                title: "Find the scooter",
                message: "Keep the ES80 powered on and close to the iPhone. Scanning lists nearby candidates; a name or UUID is not proof of vehicle identity.",
                symbol: "scope"
            )
            primaryButton("Scan for scooter", systemImage: "dot.radiowaves.left.and.right") {
                beginScan()
            }

        case .scanning:
            statePanel(
                eyebrow: "STEP 1",
                title: controller.discoveredPeripherals.isEmpty ? "Looking for nearby devices" : "Choose the candidate you physically identified",
                message: controller.discoveredPeripherals.isEmpty
                    ? "No candidate is selected automatically. Keep the scooter stationary and nearby."
                    : "Use physical correlation before choosing. Local names and signal strength remain candidate evidence only.",
                symbol: "dot.radiowaves.left.and.right"
            )

            candidateList

            secondaryButton("Stop scan", systemImage: "stop.fill") {
                controller.stopScanning()
                selectedCandidateIdentifier = nil
            }

        case .candidateSelected:
            statePanel(
                eyebrow: "STEP 2",
                title: "Ready to start a target session",
                message: "Start Capture creates the controller's real target-scoped evidence session and begins the connection. It does not mark this peripheral as a verified ES80 protocol identity.",
                symbol: "checkmark.circle"
            )

            if let selected = selectedCandidate {
                candidateRow(selected, selected: true)
            }

            primaryButton("Start Capture", systemImage: "record.circle") {
                startCapture()
            }

            secondaryButton("Choose another candidate", systemImage: "arrow.counterclockwise") {
                selectedCandidateIdentifier = nil
            }

        case .connecting:
            statePanel(
                eyebrow: "CONNECTING",
                title: "Opening the passive session",
                message: "Nembra is connecting only to the candidate you selected. Keep the scooter stationary until setup completes.",
                symbol: "link"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("This research shell does not offer an in-session cancel/retry until the controller exposes its terminal-callback quarantine state. If setup cannot finish, relaunch Nembra Capture rather than starting another attempt inside this evidence session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .preparingEvidence:
            statePanel(
                eyebrow: "VERIFYING SESSION",
                title: "Preparing trustworthy capture",
                message: "Service discovery plus permitted reads and subscriptions must finish without ambiguity before the capture can be exported.",
                symbol: "checkmark.shield"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .capturing:
            captureActivePanel

            primaryButton("Finish Capture", systemImage: "stop.circle") {
                Task { await finishCapture() }
            }

            Text("Finish only after you are safely stopped. The export is prepared before Nembra ends the selected connection.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .disconnectedCaptureReady:
            statePanel(
                eyebrow: "CONNECTION ENDED",
                title: "Evidence retained — finish when safely stopped",
                message: "The selected target disconnected or transport became unavailable after finite setup had completed. Nembra retains that break in this session. Do not reconnect inside this capture if you want a clean evidence boundary.",
                symbol: "link"
            )

            primaryButton("Finish Capture", systemImage: "stop.circle") {
                Task { await finishCapture() }
            }

            Text("If you are moving, ignore the phone. Return here and finish only after you are safely stopped.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .finishing:
            statePanel(
                eyebrow: "FINALIZING",
                title: "Preparing the capture file",
                message: "Nembra is preparing one versioned JSON artifact from the selected target session. Keep the app open until the share sheet appears.",
                symbol: "doc.badge.clock"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .finished:
            statePanel(
                eyebrow: "COMPLETE",
                title: "Capture file is ready",
                message: "Share the versioned file unchanged for offline analysis. Relaunch Nembra Capture before beginning a separate session with this same scooter.",
                symbol: "checkmark.seal"
            )

            if let preparedSummary {
                preparedCaptureSummaryPanel(preparedSummary)
            }

            primaryButton("Share Capture File", systemImage: "square.and.arrow.up") {
                isExporting = true
            }

        case let .failed(message):
            statePanel(
                eyebrow: "CAPTURE STOPPED",
                title: "Evidence integrity failed closed",
                message: message,
                symbol: "exclamationmark.triangle"
            )

            Text("Do not treat this session as usable physical evidence. Relaunch the research build before attempting another capture.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var candidateList: some View {
        VStack(spacing: 10) {
            ForEach(controller.discoveredPeripherals) { peripheral in
                Button {
                    selectedCandidateIdentifier = peripheral.id
                } label: {
                    candidateRow(peripheral, selected: selectedCandidateIdentifier == peripheral.id)
                }
                .buttonStyle(.plain)
                .disabled(peripheral.isConnectable == false)
                .accessibilityIdentifier("es80.capture.candidate.\(peripheral.id.uuidString)")
            }
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.2),
            value: controller.discoveredPeripherals
        )
    }

    private func candidateRow(
        _ peripheral: ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral,
        selected: Bool
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(selected ? .white : .white.opacity(0.08))
                    .frame(width: 42, height: 42)

                Image(systemName: selected ? "checkmark" : "scooter")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(selected ? .black : .white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidateName(peripheral))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(String(peripheral.id.uuidString.prefix(8)))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(peripheral.rssiDescription)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(peripheral.isConnectable == false ? "Not connectable" : "Candidate")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(peripheral.isConnectable == false ? .orange : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            selected ? .white.opacity(0.12) : .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? .white.opacity(0.35) : .clear, lineWidth: 1)
        }
        .opacity(peripheral.isConnectable == false ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(candidateAccessibilityLabel(peripheral, selected: selected))
    }

    private var captureActivePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(.green.opacity(0.28), lineWidth: 7)
                        .frame(width: 58, height: 58)

                    Circle()
                        .fill(.green)
                        .frame(width: 14, height: 14)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CAPTURE ACTIVE")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.green)

                    Text("Put the phone away.")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            Divider().overlay(.white.opacity(0.12))

            Text("Nembra is retaining passive events from the explicitly selected target. Do not touch or look at the phone while riding. Return here only after you are safely stopped.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture active. Put the phone away while riding and finish only when safely stopped.")
    }

    private func preparedCaptureSummaryPanel(_ summary: PreparedCaptureSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PREPARED FILE")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("FORMAT v\(summary.schemaVersion)")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                preparedSummaryRow("Recorded events", value: "\(summary.recordCount)")
                preparedSummaryRow("Value observations", value: "\(summary.valueObservationCount)")
                preparedSummaryRow("Continuity breaks", value: "\(summary.continuityBreakCount)")
                preparedSummaryRow("Observed span", value: summary.observedSpanDescription)
            }

            Text("These describe the exact prepared JSON file. They do not identify scooter fields or prove protocol semantics.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Prepared capture file. Format version \(summary.schemaVersion). \(summary.recordCount) recorded events. \(summary.valueObservationCount) value observations. \(summary.continuityBreakCount) continuity breaks. Observed span \(summary.observedSpanDescription)."
        )
    }

    private func preparedSummaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statePanel(
        eyebrow: String,
        title: String,
        message: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(eyebrow)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func diagnosticBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func primaryButton(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .foregroundStyle(disabled ? .secondary : .black)
                .background(
                    disabled ? .white.opacity(0.08) : .white,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier(primaryActionIdentifier)
    }

    private func secondaryButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .foregroundStyle(.white)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var phase: Phase {
        if controller.captureFailed {
            return .failed(controller.lastDiagnostic ?? "The passive acquisition controller rejected this session.")
        }
        if isPreparingExport {
            return .finishing
        }
        if exportDocument != nil {
            return .finished
        }
        if controller.hasTargetSession,
           controller.hasCompleteTargetEvidence,
           case .idle = controller.connectionPhase {
            return .disconnectedCaptureReady
        }
        if controller.bluetoothState != .poweredOn {
            return .bluetoothUnavailable(bluetoothUnavailableMessage)
        }

        switch controller.connectionPhase {
        case .connecting:
            return .connecting
        case .connected:
            return controller.hasCompleteTargetEvidence ? .capturing : .preparingEvidence
        case .idle:
            if controller.isScanning {
                return selectedCandidateIdentifier == nil ? .scanning : .candidateSelected
            }
            if selectedCandidateIdentifier != nil {
                return .candidateSelected
            }
            return .ready
        }
    }

    private var selectedCandidate: ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral? {
        guard let selectedCandidateIdentifier else { return nil }
        return controller.discoveredPeripherals.first { $0.id == selectedCandidateIdentifier }
    }

    private var canShowAdvancedConsole: Bool {
        guard exportDocument == nil,
              !controller.isScanning,
              !controller.hasCompleteTargetEvidence else { return false }
        if case .idle = controller.connectionPhase { return true }
        return false
    }

    private var statusTitle: String {
        switch phase {
        case .bluetoothUnavailable: "Preflight required"
        case .ready: "Ready for stationary setup"
        case .scanning: "Scanning nearby devices"
        case .candidateSelected: "Candidate selected"
        case .connecting: "Connecting"
        case .preparingEvidence: "Verifying passive session"
        case .capturing: "Capture active"
        case .disconnectedCaptureReady: "Connection ended — evidence retained"
        case .finishing: "Preparing evidence"
        case .finished: "Capture complete"
        case .failed: "Capture failed closed"
        }
    }

    private var statusColor: Color {
        switch phase {
        case .capturing, .finished:
            .green
        case .failed:
            .red
        case .bluetoothUnavailable, .connecting, .preparingEvidence, .disconnectedCaptureReady, .finishing:
            .orange
        case .ready, .scanning, .candidateSelected:
            .white.opacity(0.72)
        }
    }

    private var bluetoothUnavailableMessage: String {
        switch controller.bluetoothState {
        case .unknown:
            "Waiting for CoreBluetooth to report its state."
        case .resetting:
            "Bluetooth is resetting. Keep the app open and retry when the radio is ready."
        case .unsupported:
            "This device does not expose the Bluetooth capability required for passive capture."
        case .unauthorized:
            "Bluetooth permission is unavailable. Allow Nembra to use Bluetooth before starting a physical capture."
        case .poweredOff:
            "Turn Bluetooth on before starting a physical capture."
        case .poweredOn:
            "Bluetooth is ready."
        @unknown default:
            "CoreBluetooth reported an unknown future state. Capture remains unavailable."
        }
    }

    private var primaryActionIdentifier: String {
        switch phase {
        case .ready, .bluetoothUnavailable:
            "es80.capture.scan"
        case .candidateSelected:
            "es80.capture.start"
        case .capturing, .disconnectedCaptureReady:
            "es80.capture.finish"
        case .finished:
            "es80.capture.share"
        default:
            "es80.capture.primary"
        }
    }

    private func beginScan() {
        selectedCandidateIdentifier = nil
        diagnosticMessage = nil
        do {
            try controller.startScanning(captureAdvertisementCadence: false)
        } catch {
            diagnosticMessage = error.localizedDescription
        }
    }

    private func startCapture() {
        guard let selectedCandidateIdentifier else { return }
        diagnosticMessage = nil
        do {
            try controller.connect(to: selectedCandidateIdentifier)
        } catch {
            diagnosticMessage = error.localizedDescription
        }
    }

    private func finishCapture() async {
        guard controller.hasCompleteTargetEvidence else {
            diagnosticMessage = "Capture is not yet complete enough to export."
            return
        }

        isPreparingExport = true
        diagnosticMessage = nil
        do {
            let data = try await controller.encodedCaptureJSON(prettyPrinted: true)
            let finalizedSession = try PassiveBluetoothCaptureJSON.decode(data)
            preparedSummary = PreparedCaptureSummary(session: finalizedSession)
            exportDocument = PassiveCaptureJSONDocument(data: data)
            controller.cancelActiveConnection()
            isExporting = true
        } catch {
            diagnosticMessage = "Capture could not be finalized: \(error.localizedDescription)"
        }
        isPreparingExport = false
    }

    private func candidateName(
        _ peripheral: ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral
    ) -> String {
        guard let localName = peripheral.localName, !localName.isEmpty else {
            return "Nearby Bluetooth candidate"
        }
        return localName
    }

    private func candidateAccessibilityLabel(
        _ peripheral: ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral,
        selected: Bool
    ) -> String {
        let connection = peripheral.isConnectable == false ? "not connectable" : "candidate"
        let selection = selected ? ", selected" : ""
        return "\(candidateName(peripheral)), \(peripheral.rssiDescription), \(connection)\(selection)."
    }
}
