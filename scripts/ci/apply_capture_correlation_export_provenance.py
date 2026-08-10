#!/usr/bin/env python3
from pathlib import Path

SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelationProvenanceExportSourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


source = SOURCE.read_text()

source = replace_once(
    source,
    """        let selectedPeripheralID: String?\n        let phase: Phase\n""",
    """        let selectedPeripheralID: String?\n        let targetCorrelationProvenance: CorrelationProvenance?\n        let phase: Phase\n""",
    "Export correlation provenance field",
)

source = replace_once(
    source,
    """    struct Event: Codable {\n        let at: Date\n        let kind: String\n        let details: [String: String]\n    }\n\n""",
    """    struct Event: Codable {\n        let at: Date\n        let kind: String\n        let details: [String: String]\n    }\n\n    /// Sanitized, replayable projection of the exact package-issued four-window\n    /// target-correlation result. This preserves why a full UUID was correlated;\n    /// it does not promote that UUID into permanent scooter identity.\n    struct CorrelationProvenance: Codable, Equatable {\n        struct Window: Codable, Equatable {\n            let phase: String\n            let operatorExpectedPowerOn: Bool\n            let windowSequence: UInt64\n            let startedAtUptimeNanoseconds: UInt64\n            let endedAtUptimeNanoseconds: UInt64\n            let observedCandidateCount: Int\n        }\n\n        struct Snapshot: Codable, Equatable {\n            struct Candidate: Codable, Equatable {\n                let peripheralID: String\n                let isConnectable: Bool?\n            }\n\n            let observationSeriesID: String\n            let windowSequence: UInt64\n            let candidates: [Candidate]\n        }\n\n        let method: String\n        let windows: [Window]\n        let observationSnapshots: [Snapshot]\n        let disposition: String\n        let repeatableCandidateIDs: [String]\n\n        init(result: PassiveBluetoothPowerCycleObservationResult) {\n            method = \"package-owned-fresh-manager-off1-on1-off2-on2\"\n            windows = result.windows.map { receipt in\n                Window(\n                    phase: Self.phaseLabel(receipt.phase),\n                    operatorExpectedPowerOn: receipt.phase.operatorExpectedPowerOn,\n                    windowSequence: receipt.windowSequence.rawValue,\n                    startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,\n                    endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,\n                    observedCandidateCount: receipt.observedCandidateCount\n                )\n            }\n            observationSnapshots = result.observationSnapshots.map { snapshot in\n                Snapshot(\n                    observationSeriesID: snapshot.observationSeriesIdentity.rawValue.uuidString,\n                    windowSequence: snapshot.windowSequence.rawValue,\n                    candidates: snapshot.candidates.map { candidate in\n                        Snapshot.Candidate(\n                            peripheralID: candidate.id.uuidString,\n                            isConnectable: candidate.isConnectable\n                        )\n                    }\n                )\n            }\n            disposition = Self.dispositionLabel(result.correlation.disposition)\n            repeatableCandidateIDs = result.correlation.repeatableCandidateIdentifiers.map(\\.uuidString)\n        }\n\n        private static func phaseLabel(_ phase: PassiveBluetoothPowerCycleObservationPhase) -> String {\n            switch phase {\n            case .firstPoweredOff: return \"OFF1\"\n            case .firstPoweredOn: return \"ON1\"\n            case .secondPoweredOff: return \"OFF2\"\n            case .secondPoweredOn: return \"ON2\"\n            }\n        }\n\n        private static func dispositionLabel(\n            _ disposition: PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition\n        ) -> String {\n            switch disposition {\n            case .invalidObservationAuthority: return \"invalidObservationAuthority\"\n            case .invalidObservationWindowOrder: return \"invalidObservationWindowOrder\"\n            case .noRepeatableCandidate: return \"noRepeatableCandidate\"\n            case .ambiguousRepeatableCandidates: return \"ambiguousRepeatableCandidates\"\n            case .singleRepeatableCandidate: return \"singleRepeatableCandidate\"\n            }\n        }\n    }\n\n""",
    "Correlation provenance model",
)

source = replace_once(
    source,
    """    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var driver: OfficialTuyaDriver?\n""",
    """    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationProvenance: CorrelationProvenance?\n    private var driver: OfficialTuyaDriver?\n""",
    "Correlation provenance custody",
)

source = replace_once(
    source,
    """    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {\n        switch result.correlation.disposition {\n""",
    """    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {\n        // Preserve the package-issued receipts + exact catalogs before releasing the live scanner.\n        // The artifact can therefore audit/replay correlation without trusting a detached UUID.\n        correlationProvenance = CorrelationProvenance(result: result)\n        switch result.correlation.disposition {\n""",
    "Preserve final correlation result",
)

source = replace_once(
    source,
    """            schemaVersion: 7,\n""",
    """            schemaVersion: 8,\n""",
    "Export schema bump",
)

source = replace_once(
    source,
    """            selectedPeripheralID: selectedID?.uuidString,\n            phase: phase,\n""",
    """            selectedPeripheralID: selectedID?.uuidString,\n            targetCorrelationProvenance: correlationProvenance,\n            phase: phase,\n""",
    "Export preserved provenance",
)

source = replace_once(
    source,
    """        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        central.stopScan()\n""",
    """        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        correlationProvenance = nil\n        central.stopScan()\n""",
    "Reset provenance with discovery attempt",
)

SOURCE.write_text(source)

TEST.parent.mkdir(parents=True, exist_ok=True)
TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation provenance export")
struct TuyaCorrelationProvenanceExportSourceTests {
    @Test("final package-issued correlation evidence survives scanner retirement and enters schema v8 export")
    func packageResultRemainsAuditableInExport() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("struct CorrelationProvenance: Codable, Equatable"))
        #expect(source.contains("let targetCorrelationProvenance: CorrelationProvenance?"))
        #expect(source.contains("private var correlationProvenance: CorrelationProvenance?"))
        #expect(source.contains("correlationProvenance = CorrelationProvenance(result: result)"))
        #expect(source.contains("targetCorrelationProvenance: correlationProvenance"))
        #expect(source.contains("schemaVersion: 8"))

        // Preserve the exact package-issued receipt boundaries and full candidate catalogs.
        #expect(source.contains("result.windows.map"))
        #expect(source.contains("receipt.startedAtUptimeNanoseconds"))
        #expect(source.contains("receipt.endedAtUptimeNanoseconds"))
        #expect(source.contains("receipt.windowSequence.rawValue"))
        #expect(source.contains("result.observationSnapshots.map"))
        #expect(source.contains("snapshot.observationSeriesIdentity.rawValue.uuidString"))
        #expect(source.contains("candidate.id.uuidString"))
        #expect(source.contains("candidate.isConnectable"))
        #expect(source.contains("result.correlation.repeatableCandidateIdentifiers"))

        // The app preserves/reports the package result; it does not mint a second assessor authority.
        #expect(!source.contains("PassiveBluetoothPowerCycleTargetCorrelation.assess("))
    }

    @Test("a new discovery attempt cannot inherit prior target-correlation provenance")
    func resetClearsPriorSeriesEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let reset = source.range(of: "private func resetDiscoverySessionOnly()"),
              let next = source.range(of: "private func failLocally", range: reset.upperBound..<source.endIndex) else {
            Issue.record("Could not isolate discovery reset.")
            return
        }
        let body = String(source[reset.lowerBound..<next.lowerBound])
        #expect(body.contains("correlationProvenance = nil"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
''')

print("capture correlation provenance patch staged")
