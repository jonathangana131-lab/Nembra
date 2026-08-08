@preconcurrency import CoreBluetooth
import Foundation
import NembraBluetoothCapture
import NembraCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Product-facing, foreground-only shell for passive ES80 evidence capture.
///
/// The shell deliberately owns presentation and operator sequencing only. Durable
/// Ready/Horizon chronology, exact queue cutoffs, artifact authority, and immutable
/// finalization remain controller/package authority. The local 60-second wait is a
/// conservative UI admission aid that starts only after the controller reports its
/// durable Ready epoch; it is never represented as evidence and does not replace
/// final artifact assessment.
@MainActor
struct ES80CaptureShellView: View {
    private enum Phase: Equatable {
        case bluetoothUnavailable(String)
        case ready
        case scanning
        case candidateSelected
        case connecting
        case preparingEvidence
        case waitingForReady
        case observing
        case readyToSeal
        case finalizing
        case finished
        case failed(String)
    }

    private struct PreparedCaptureSummary: Equatable {
        let recordCount: Int
        let valueObservationCount: Int
        let continuityBreakCount: Int
        let receiptTimelineSpanSeconds: TimeInterval
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

            guard let first = session.records.first,
                  let last = session.records.last,
                  last.receivedAtUptimeNanoseconds >= first.receivedAtUptimeNanoseconds else {
                receiptTimelineSpanSeconds = 0
                return
            }
            receiptTimelineSpanSeconds = TimeInterval(
                last.receivedAtUptimeNanoseconds - first.receivedAtUptimeNanoseconds
            ) / 1_000_000_000
        }

        var receiptTimelineSpanDescription: String {
            if receiptTimelineSpanSeconds < 1 {
                return String(format: "%.2f s", receiptTimelineSpanSeconds)
            }
            if receiptTimelineSpanSeconds < 60 {
                return String(format: "%.1f s", receiptTimelineSpanSeconds)
            }
            let wholeSeconds = Int(receiptTimelineSpanSeconds.rounded(.down))
            return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
        }
    }

    private struct CaptureJSONDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.json] }

        let data: Data

        init(data: Data) {
            self.data = data
        }

        init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.data = data
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }

    private static let requiredPresentationObservationNanoseconds: UInt64 = 60_000_000_000

    let controller: ForegroundCoreBluetoothCaptureController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedCandidateIdentifier: UUID?
    @State private var diagnosticMessage: String?
    @State private var lifecycleFailureMessage: String?
    @State private var exportDocument: CaptureJSONDocument?
    @State private var preparedSummary: PreparedCaptureSummary?
    @State private var readyObservedAtUptimeNanoseconds: UInt64?
    @State private var isExporting = false
    @State private var isFinalizing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let canFinalizeHorizon = controller.canFinalizeObservationHorizon
            let currentPhase = phase
            let candidateIDs = controller.discoveredPeripherals.map(\.id)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    safetyStrip
                    primaryContent
                    if let diagnosticMessage {
                        diagnosticBanner(diagnosticMessage)
                    }
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 38)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                synchronizeReadyObservation(canFinalizeHorizon)
                synchronizeIdleTimer(for: currentPhase)
            }
            .onChange(of: canFinalizeHorizon) { _, value in
                synchronizeReadyObservation(value)
            }
            .onChange(of: currentPhase) { _, value in
                synchronizeIdleTimer(for: value)
            }
            .onChange(of: candidateIDs) { _, ids in
                guard let selectedCandidateIdentifier,
                      !ids.contains(selectedCandidateIdentifier) else { return }
                self.selectedCandidateIdentifier = nil
            }
        }
        .navigationTitle("Nembra Capture")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Nembra-passive-bluetooth-capture"
        ) { result in
            switch result {
            case .success:
                diagnosticMessage = "Capture file exported. Keep the exact JSON unchanged for offline analysis."
            case let .failure(error):
                diagnosticMessage = "The sealed capture remains prepared, but export did not finish: \(error.localizedDescription)"
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .accessibilityIdentifier("es80.capture-shell")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 54, height: 54)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("NEMBRA / ES80 RESEARCH")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text("Capture physical Bluetooth evidence.")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 9) {
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
                Text("Set up while stationary. Keep Nembra active in the foreground with the screen awake throughout live evidence collection. This research path never writes an application characteristic value and does not turn a Bluetooth candidate into verified scooter identity.")
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
            statePanel("PREFLIGHT", "Bluetooth is not ready", message, symbol: "antenna.radiowaves.left.and.right.slash")
            primaryButton("Scan for scooter", systemImage: "dot.radiowaves.left.and.right", identifier: "es80.capture.scan", disabled: true) {}

        case .ready:
            statePanel(
                "STEP 1",
                "Find the scooter candidate",
                "Use the accepted physical-correlation procedure before selection. Names, RSSI, services, and short identifiers are candidate evidence only.",
                symbol: "scope"
            )
            primaryButton("Scan for scooter", systemImage: "dot.radiowaves.left.and.right", identifier: "es80.capture.scan") {
                beginScan()
            }

        case .scanning:
            statePanel(
                "STEP 1",
                controller.discoveredPeripherals.isEmpty ? "Looking for nearby devices" : "Choose the physically correlated candidate",
                controller.discoveredPeripherals.isEmpty
                    ? "No candidate is selected automatically. Keep the scooter stationary and nearby."
                    : "Selection is explicit. A candidate UUID is not permanent or authenticated scooter identity.",
                symbol: "dot.radiowaves.left.and.right"
            )
            candidateList
            secondaryButton("Stop scan", systemImage: "stop.fill") {
                controller.stopScanning()
                selectedCandidateIdentifier = nil
            }

        case .candidateSelected:
            statePanel(
                "STEP 2",
                "Ready to open one target session",
                "Start Capture creates the controller's real target-scoped evidence session. It does not promote protocol or telemetry meaning.",
                symbol: "checkmark.circle"
            )
            if let selectedCandidate {
                candidateRow(selectedCandidate, selected: true)
            }
            primaryButton("Start Capture", systemImage: "record.circle", identifier: "es80.capture.start") {
                startCapture()
            }
            secondaryButton("Choose another candidate", systemImage: "arrow.counterclockwise") {
                selectedCandidateIdentifier = nil
            }

        case .connecting:
            progressPanel(
                eyebrow: "CONNECTING",
                title: "Opening the passive target session",
                message: "Keep Nembra foregrounded. The controller is opening only the explicitly selected CoreBluetooth candidate."
            )

        case .preparingEvidence:
            progressPanel(
                eyebrow: "FINITE ACQUISITION",
                title: "Discovering the passive evidence surface",
                message: "Permitted discovery, reads, and subscriptions must finish coherently before the durable Ready boundary can be committed."
            )

        case .waitingForReady:
            progressPanel(
                eyebrow: "READY BOUNDARY",
                title: "Committing the evidence cutoff",
                message: "Finite acquisition is complete. Nembra is waiting for the package-owned Ready boundary to cross the recorder and queue gate under the current artifact authority."
            )

        case .observing:
            observationPanel

        case .readyToSeal:
            statePanel(
                "HORIZON READY",
                "The conservative 60-second UI wait has completed",
                "Finish Capture now asks the controller to record the canonical Horizon, freeze the exact accepted queue prefix, encode the immutable JSON, and retire only proven post-H evidence. The UI timer itself is not evidence.",
                symbol: "checkmark.seal"
            )
            primaryButton("Finish Capture", systemImage: "stop.circle", identifier: "es80.capture.finish") {
                requestFinishCapture()
            }

        case .finalizing:
            progressPanel(
                eyebrow: "SEALING HORIZON",
                title: "Freezing the immutable artifact",
                message: "Keep Nembra foregrounded. Horizon recording, typed queue commit, JSON encoding, and artifact freeze are in progress."
            )

        case .finished:
            statePanel(
                "SEALED",
                "Capture file is ready",
                "The controller completed canonical Horizon finalization before transport teardown. Share the exact versioned JSON unchanged for offline analysis.",
                symbol: "checkmark.seal.fill"
            )
            if let preparedSummary {
                preparedSummaryPanel(preparedSummary)
            }
            primaryButton("Share Capture File", systemImage: "square.and.arrow.up", identifier: "es80.capture.share") {
                isExporting = true
            }

        case let .failed(message):
            statePanel(
                "CAPTURE STOPPED",
                "Evidence integrity failed closed",
                message,
                symbol: "exclamationmark.triangle"
            )
            Text("Do not treat this session as usable physical evidence. Relaunch the research build before starting another capture.")
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: controller.discoveredPeripherals)
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
                Text(shortCandidateIdentifier(peripheral))
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
        .background(selected ? .white.opacity(0.12) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? .white.opacity(0.35) : .clear, lineWidth: 1)
        }
        .opacity(peripheral.isConnectable == false ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(candidateAccessibilityLabel(peripheral, selected: selected))
    }

    private var observationPanel: some View {
        let remaining = presentationObservationSecondsRemaining
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(.green.opacity(0.25), lineWidth: 7)
                        .frame(width: 58, height: 58)
                    Circle()
                        .trim(from: 0, to: observationProgress)
                        .stroke(.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 58, height: 58)
                    Text("\(remaining)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("OBSERVATION READY")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.green)
                    Text("Keep the accepted Ready epoch undisturbed")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Nembra observed the controller's durable Ready state. This 60-second countdown begins only afterward, so it is conservative presentation gating. The final artifact's package-owned Ready/Horizon chronology remains the evidence authority.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(remaining) s minimum UI wait remaining")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityLabel("\(remaining) seconds minimum presentation wait remaining. The timer is not evidence.")
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func preparedSummaryPanel(_ summary: PreparedCaptureSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PREPARED FILE")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("FORMAT v\(summary.schemaVersion)")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            summaryRow("Recorded events", "\(summary.recordCount)")
            summaryRow("Value observations", "\(summary.valueObservationCount)")
            summaryRow("Continuity breaks", "\(summary.continuityBreakCount)")
            summaryRow("Receipt timeline span", summary.receiptTimelineSpanDescription)
            Text("Receipt timeline span is descriptive first-to-last receipt time and may contain explicit continuity gaps. It is not the authoritative Ready-to-Horizon duration.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private func statePanel(_ eyebrow: String, _ title: String, _ message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
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

    private func progressPanel(eyebrow: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            statePanel(eyebrow, title, message, symbol: "waveform.path.ecg")
            ProgressView()
                .tint(.white)
                .controlSize(.large)
        }
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
        identifier: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .foregroundStyle(disabled ? Color.secondary : Color.black)
                .background(disabled ? .white.opacity(0.08) : .white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
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
        if let lifecycleFailureMessage { return .failed(lifecycleFailureMessage) }
        if controller.captureFailed {
            return .failed(controller.lastDiagnostic ?? "The passive acquisition controller rejected this session.")
        }
        if isFinalizing { return .finalizing }
        if exportDocument != nil { return .finished }
        if controller.bluetoothState != .poweredOn {
            return .bluetoothUnavailable(bluetoothUnavailableMessage)
        }

        switch controller.connectionPhase {
        case .connecting:
            return .connecting

        case .connected:
            if !controller.hasCompleteTargetEvidence {
                return .preparingEvidence
            }
            if !controller.canFinalizeObservationHorizon {
                return .waitingForReady
            }
            return presentationObservationWaitComplete ? .readyToSeal : .observing

        case .idle:
            if controller.hasTargetSession {
                return .failed("The selected-target transport ended before canonical Horizon finalization. This shell will not export an unsealed artifact. Relaunch and repeat the capture.")
            }
            if controller.isScanning {
                return selectedCandidate == nil ? .scanning : .candidateSelected
            }
            if selectedCandidate != nil { return .candidateSelected }
            return .ready
        }
    }

    private var selectedCandidate: ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral? {
        guard let selectedCandidateIdentifier else { return nil }
        return controller.discoveredPeripherals.first { $0.id == selectedCandidateIdentifier }
    }

    private var presentationObservationWaitComplete: Bool {
        presentationObservationElapsedNanoseconds >= Self.requiredPresentationObservationNanoseconds
    }

    private var presentationObservationElapsedNanoseconds: UInt64 {
        guard let start = readyObservedAtUptimeNanoseconds else { return 0 }
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= start ? now - start : 0
    }

    private var presentationObservationSecondsRemaining: Int {
        let required = Self.requiredPresentationObservationNanoseconds
        let elapsed = min(presentationObservationElapsedNanoseconds, required)
        let remaining = required - elapsed
        return Int((remaining + 999_999_999) / 1_000_000_000)
    }

    private var observationProgress: Double {
        min(1, Double(presentationObservationElapsedNanoseconds) / Double(Self.requiredPresentationObservationNanoseconds))
    }

    private var liveCaptureRequiresForeground: Bool {
        controller.hasTargetSession && exportDocument == nil
    }

    private var statusTitle: String {
        switch phase {
        case .bluetoothUnavailable: "Preflight required"
        case .ready: "Ready for stationary setup"
        case .scanning: "Scanning nearby devices"
        case .candidateSelected: "Candidate selected"
        case .connecting: "Connecting"
        case .preparingEvidence: "Finite passive acquisition"
        case .waitingForReady: "Committing durable Ready"
        case .observing: "Observation Ready — foreground only"
        case .readyToSeal: "Ready to seal Horizon"
        case .finalizing: "Freezing exact Horizon artifact"
        case .finished: "Canonical artifact sealed"
        case .failed: "Capture failed closed"
        }
    }

    private var statusColor: Color {
        switch phase {
        case .observing, .readyToSeal, .finished: .green
        case .failed: .red
        case .bluetoothUnavailable, .connecting, .preparingEvidence, .waitingForReady, .finalizing: .orange
        case .ready, .scanning, .candidateSelected: .white.opacity(0.72)
        }
    }

    private var bluetoothUnavailableMessage: String {
        switch controller.bluetoothState {
        case .unknown: "Waiting for CoreBluetooth to report its state."
        case .resetting: "Bluetooth is resetting. Keep the app open and retry when the radio is ready."
        case .unsupported: "This device does not expose the Bluetooth capability required for passive capture."
        case .unauthorized: "Bluetooth permission is unavailable. Allow Nembra to use Bluetooth before capture."
        case .poweredOff: "Turn Bluetooth on before starting a physical capture."
        case .poweredOn: "Bluetooth is ready."
        @unknown default: "CoreBluetooth reported an unknown future state. Capture remains unavailable."
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
        guard let selectedCandidate else {
            selectedCandidateIdentifier = nil
            diagnosticMessage = "The selected candidate is no longer in the current scan catalog. Scan again."
            return
        }
        diagnosticMessage = nil
        readyObservedAtUptimeNanoseconds = nil
        do {
            try controller.connect(to: selectedCandidate.id)
        } catch {
            diagnosticMessage = error.localizedDescription
        }
    }

    private func synchronizeReadyObservation(_ canFinalize: Bool) {
        if canFinalize {
            if readyObservedAtUptimeNanoseconds == nil {
                readyObservedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            }
        } else if exportDocument == nil, !isFinalizing {
            readyObservedAtUptimeNanoseconds = nil
        }
    }

    private func requestFinishCapture() {
        guard !isFinalizing,
              exportDocument == nil,
              lifecycleFailureMessage == nil else { return }
        guard controller.canFinalizeObservationHorizon else {
            diagnosticMessage = "The durable Ready epoch is not currently eligible for Horizon finalization."
            return
        }
        guard presentationObservationWaitComplete else {
            diagnosticMessage = "Keep the accepted Ready epoch undisturbed until the conservative 60-second UI wait completes."
            return
        }

        isFinalizing = true
        diagnosticMessage = nil
        Task { await finalizeCanonicalHorizon() }
    }

    private func finalizeCanonicalHorizon() async {
        defer { isFinalizing = false }
        do {
            let data = try await controller.encodedFinalizedObservationHorizonJSON(prettyPrinted: true)
            guard lifecycleFailureMessage == nil else { return }

            let session = try PassiveBluetoothCaptureJSON.decode(data)
            guard lifecycleFailureMessage == nil else { return }

            try controller.teardownActiveConnectionAfterFinalization()
            preparedSummary = PreparedCaptureSummary(session: session)
            exportDocument = CaptureJSONDocument(data: data)
            isExporting = true
        } catch {
            guard lifecycleFailureMessage == nil, exportDocument == nil else { return }
            diagnosticMessage = "Canonical Horizon finalization failed: \(error.localizedDescription)"
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase != .active, liveCaptureRequiresForeground else { return }
        invalidateLiveCaptureForForegroundLoss()
    }

    private func invalidateLiveCaptureForForegroundLoss() {
        guard lifecycleFailureMessage == nil else { return }
        lifecycleFailureMessage = "Nembra left the active foreground before the immutable Horizon artifact was sealed. Foreground-only evidence integrity is lost; this session is not exportable."
        diagnosticMessage = nil
        readyObservedAtUptimeNanoseconds = nil
        controller.invalidateActiveCaptureForForegroundLoss()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func synchronizeIdleTimer(for phase: Phase) {
        switch phase {
        case .connecting, .preparingEvidence, .waitingForReady, .observing, .readyToSeal, .finalizing:
            UIApplication.shared.isIdleTimerDisabled = true
        default:
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func candidateName(_ peripheral: ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral) -> String {
        guard let localName = peripheral.localName, !localName.isEmpty else {
            return "Nearby Bluetooth candidate"
        }
        return localName
    }

    private func shortCandidateIdentifier(_ peripheral: ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral) -> String {
        String(peripheral.id.uuidString.prefix(8))
    }

    private func candidateAccessibilityLabel(
        _ peripheral: ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral,
        selected: Bool
    ) -> String {
        let connection = peripheral.isConnectable == false ? "not connectable" : "candidate"
        let selection = selected ? ", selected" : ""
        return "\(candidateName(peripheral)), candidate ID \(shortCandidateIdentifier(peripheral)), \(peripheral.rssiDescription), \(connection)\(selection)."
    }
}