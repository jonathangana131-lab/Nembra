import Foundation
import NembraCore
import SwiftUI
import UniformTypeIdentifiers

/// Reusable research-only UI for acquiring and exporting passive ES80 Bluetooth
/// evidence. The production Nembra app does not wire this view yet.
///
/// Safety boundary: every action delegates to the passive CoreBluetooth
/// controller. There is no application characteristic-value write control.
@MainActor
public struct ES80PassiveCaptureResearchView: View {
    private let controller: ForegroundCoreBluetoothCaptureController

    @State private var captureAdvertisementCadence = false
    @State private var markerField = MarkerField.battery
    @State private var markerValue = ""
    @State private var markerNote = ""
    @State private var diagnosticMessage: String?
    @State private var analysis: AnalysisSummary?
    @State private var exportDocument: PassiveCaptureJSONDocument?
    @State private var isExporting = false

    public init(controller: ForegroundCoreBluetoothCaptureController) {
        self.controller = controller
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            Form {
                safetySection
                bluetoothSection
                discoveredPeripheralsSection
                stockAppMarkerSection
                analysisSection
                exportSection
            }
        }
        .navigationTitle("ES80 Capture")
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Nembra-ES80-passive-capture"
        ) { result in
            switch result {
            case .success:
                diagnosticMessage = "Capture JSON exported."
            case let .failure(error):
                diagnosticMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private var safetySection: some View {
        Section("Research safety") {
            Label("Passive evidence only", systemImage: "shield.checkered")
                .font(.headline)

            Text("This tool discovers, reads, and subscribes only where GATT properties permit. It does not send application characteristic writes or assume a Tuya DP schema.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Stock-app values are correlation markers. Nembra is not an over-the-air sniffer for another app's private Bluetooth session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var bluetoothSection: some View {
        Section("Bluetooth") {
            LabeledContent("Central state", value: bluetoothStateLabel)
            LabeledContent("Connection", value: connectionLabel)

            Toggle("Capture advertisement cadence", isOn: $captureAdvertisementCadence)
                .disabled(controller.isScanning)

            HStack {
                Button(controller.isScanning ? "Stop scan" : "Start scan") {
                    perform {
                        if controller.isScanning {
                            controller.stopScanning()
                        } else {
                            try controller.startScanning(
                                captureAdvertisementCadence: captureAdvertisementCadence
                            )
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if case .idle = controller.connectionPhase {
                    EmptyView()
                } else {
                    Button("Cancel connection", role: .cancel) {
                        controller.cancelActiveConnection()
                    }
                }
            }

            if controller.captureFailed {
                Label("Capture failed closed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if let message = diagnosticMessage ?? controller.lastDiagnostic {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var discoveredPeripheralsSection: some View {
        Section("Discovered peripherals") {
            if controller.discoveredPeripherals.isEmpty {
                ContentUnavailableView(
                    controller.isScanning ? "Scanning…" : "No discoveries yet",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("The first ES80 fingerprint scan is intentionally not filtered to a guessed service family.")
                )
            } else {
                ForEach(controller.discoveredPeripherals) { peripheral in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peripheral.localName ?? "Unnamed peripheral")
                                    .font(.headline)
                                Text(peripheral.id.uuidString)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            Spacer(minLength: 12)

                            Text("\(peripheral.rssi) dBm")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            if peripheral.isConnectable == false {
                                Text("Not connectable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Connect") {
                                    perform {
                                        try controller.connect(to: peripheral.id)
                                    }
                                }
                                .disabled(!canStartConnection)
                            }

                            Spacer()

                            if peripheral.isConnectable == true {
                                Text("Connectable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var stockAppMarkerSection: some View {
        Section("Stock-app correlation marker") {
            Picker("Field", selection: $markerField) {
                ForEach(MarkerField.allCases) { field in
                    Text(field.title).tag(field)
                }
            }

            TextField(markerField.placeholder, text: $markerValue)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Optional note", text: $markerNote, axis: .vertical)
                .lineLimit(2...4)

            Button("Record marker") {
                perform {
                    try controller.recordStockAppObservation(
                        field: markerField.captureField,
                        displayedValue: markerValue.trimmingCharacters(in: .whitespacesAndNewlines),
                        note: normalizedOptional(markerNote)
                    )
                    markerValue = ""
                    markerNote = ""
                    diagnosticMessage = "Recorded \(markerField.title) marker."
                }
            }
            .disabled(markerValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text("Only record what is actually visible in the stock app or other legitimate reference setup. Timing proximity is not a decoded DP claim.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var analysisSection: some View {
        Section("Evidence summary") {
            Button("Refresh analysis") {
                Task { @MainActor in
                    do {
                        let snapshot = try await controller.captureSnapshot()
                        analysis = AnalysisSummary(session: snapshot)
                        diagnosticMessage = nil
                    } catch {
                        diagnosticMessage = "Analysis failed: \(error.localizedDescription)"
                    }
                }
            }

            if let analysis {
                LabeledContent("Records", value: "\(analysis.recordCount)")
                LabeledContent("Raw value streams", value: "\(analysis.valueStreamCount)")
                LabeledContent("Interruptions", value: "\(analysis.interruptionCount)")

                if analysis.transportCandidates.isEmpty {
                    Text("No researched Tuya transport candidate matched the captured identifiers yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(analysis.transportCandidates, id: \.self) { candidate in
                        Label(candidate, systemImage: "questionmark.diamond")
                            .font(.footnote)
                    }
                }

                if !analysis.fastestStreams.isEmpty {
                    DisclosureGroup("Raw callback streams") {
                        ForEach(analysis.fastestStreams) { stream in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stream.characteristic)
                                    .font(.caption.monospaced())
                                Text(stream.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else {
                Text("Analysis operates only on immutable capture evidence. Candidate fingerprints and callback rates are not decoded scooter telemetry.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportSection: some View {
        Section("Export") {
            Button("Prepare capture JSON") {
                Task { @MainActor in
                    do {
                        let data = try await controller.encodedCaptureJSON(prettyPrinted: true)
                        exportDocument = PassiveCaptureJSONDocument(data: data)
                        isExporting = true
                        diagnosticMessage = nil
                    } catch {
                        diagnosticMessage = "Capture export failed: \(error.localizedDescription)"
                    }
                }
            }

            Text("The versioned JSON contains raw evidence and correlation markers. It must not contain Tuya local keys, auth keys, session keys, or account tokens.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var canStartConnection: Bool {
        if case .idle = controller.connectionPhase { return true }
        return false
    }

    private var bluetoothStateLabel: String {
        switch controller.bluetoothState {
        case .unknown: "Unknown"
        case .resetting: "Resetting"
        case .unsupported: "Unsupported"
        case .unauthorized: "Unauthorized"
        case .poweredOff: "Powered off"
        case .poweredOn: "Powered on"
        @unknown default: "Future state"
        }
    }

    private var connectionLabel: String {
        switch controller.connectionPhase {
        case .idle:
            "Idle"
        case let .connecting(identifier):
            "Connecting · \(shortIdentifier(identifier))"
        case let .connected(identifier):
            "Connected · \(shortIdentifier(identifier))"
        }
    }

    private func shortIdentifier(_ identifier: UUID) -> String {
        String(identifier.uuidString.prefix(8))
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            diagnosticMessage = nil
        } catch {
            diagnosticMessage = error.localizedDescription
        }
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct PassiveCaptureJSONDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public static var writableContentTypes: [UTType] { [.json] }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum MarkerField: String, CaseIterable, Identifiable {
    case battery
    case voltage
    case current
    case power

    var id: Self { self }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .voltage: "Voltage"
        case .current: "Current"
        case .power: "Power"
        }
    }

    var captureField: String { rawValue }

    var placeholder: String {
        switch self {
        case .battery: "Example: 73%"
        case .voltage: "Example: 39.8 V"
        case .current: "Example: 4.2 A"
        case .power: "Example: 167 W"
        }
    }
}

private struct AnalysisSummary {
    struct Stream: Identifiable {
        let id: PassiveBluetoothValueStreamKey
        let characteristic: String
        let summary: String
    }

    let recordCount: Int
    let valueStreamCount: Int
    let interruptionCount: Int
    let transportCandidates: [String]
    let fastestStreams: [Stream]

    init(session: PassiveBluetoothCaptureSession) {
        recordCount = session.records.count
        interruptionCount = session.records.reduce(into: 0) { count, record in
            if case .interruption = record.event { count += 1 }
        }

        let fingerprint = PassiveBluetoothTransportFingerprint.analyze(session)
        transportCandidates = fingerprint.candidateMatches.map { match in
            "\(candidateName(match.family)) · \(strengthName(match.strength))"
        }

        let streams = PassiveBluetoothValueStreamAnalysis.summarize(session)
        valueStreamCount = streams.count
        fastestStreams = streams
            .sorted { lhs, rhs in
                switch (lhs.medianCallbackIntervalSeconds, rhs.medianCallbackIntervalSeconds) {
                case let (.some(left), .some(right)) where left != right:
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.key < rhs.key
                }
            }
            .prefix(8)
            .map { stats in
                let median = stats.medianCallbackIntervalSeconds.map {
                    String(format: "%.3f s median", $0)
                } ?? "interval unavailable"
                return Stream(
                    id: stats.key,
                    characteristic: "\(stats.key.serviceUUID) / \(stats.key.characteristicUUID)",
                    summary: "\(stats.sampleCount) callbacks · \(stats.uniquePayloadCount) unique payloads · \(median)"
                )
            }
    }

    private static func candidateName(_ family: PassiveBluetoothTransportCandidateFamily) -> String {
        switch family {
        case .tuyaModernFD50: "Tuya FD50 candidate"
        case .tuyaLegacyA201: "Tuya A201 candidate"
        case .tuyaLegacy1910: "Tuya 1910 candidate"
        }
    }

    private static func strengthName(_ strength: PassiveBluetoothTransportCandidateStrength) -> String {
        switch strength {
        case .serviceObserved: "service seen"
        case .characteristicFamilyObserved: "partial data path"
        case .expectedDataPathObserved: "expected data path seen"
        }
    }
}
