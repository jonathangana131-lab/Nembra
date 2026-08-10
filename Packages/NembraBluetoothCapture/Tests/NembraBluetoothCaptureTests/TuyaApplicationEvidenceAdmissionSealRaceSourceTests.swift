import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture application evidence admission / seal chronology")
struct TuyaApplicationEvidenceAdmissionSealRaceSourceTests {
    @Test("seal closes new app evidence admissions and waits for already-started admissions")
    func sealCannotOutrunStructuredApplicationEvidence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receipt = try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func startWatchdog"
        )
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let receiptBody = String(receipt)
        let watchdogBody = String(watchdog)

        #expect(app.contains("pendingApplicationEvidenceAdmissions"))
        #expect(app.contains("applicationEvidenceAdmissionClosedGeneration"))

        guard let beginAdmission = receiptBody.range(of: "beginApplicationEvidenceAdmission"),
              let packageAdmission = receiptBody.range(of: "sessionLedger.recordApplicationUpdate"),
              let structuredPromotion = receiptBody.range(of: "log(\"tuya_application_update\"") else {
            Issue.record("Application callback must fence package admission before promoting the structured value.")
            throw SourceContractError.sectionMissing
        }
        #expect(beginAdmission.lowerBound < packageAdmission.lowerBound)
        #expect(packageAdmission.lowerBound < structuredPromotion.lowerBound)
        #expect(receiptBody.contains("defer { endApplicationEvidenceAdmission"))

        guard let pendingFence = watchdogBody.range(of: "hasPendingApplicationEvidenceAdmissions"),
              let closeAdmissions = watchdogBody.range(of: "closeApplicationEvidenceAdmissions"),
              let packageSeal = watchdogBody.range(of: "sessionLedger.sealAcceptedObservation") else {
            Issue.record("Canonical seal must drain started admissions and close new admissions before package seal.")
            throw SourceContractError.sectionMissing
        }
        #expect(pendingFence.lowerBound < packageSeal.lowerBound)
        #expect(closeAdmissions.lowerBound < packageSeal.lowerBound)
    }

    @Test("a seal-closed generation cannot start a new accepted package application mutation")
    func closedGenerationBlocksNewPackageAdmission() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receipt = try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func startWatchdog"
        )
        let body = String(receipt)

        guard let closedCheck = body.range(of: "applicationEvidenceAdmissionClosedGeneration"),
              let beginAdmission = body.range(of: "beginApplicationEvidenceAdmission"),
              let packageAdmission = body.range(of: "sessionLedger.recordApplicationUpdate") else {
            Issue.record("Application receipt must reject a seal-closed generation before package admission.")
            throw SourceContractError.sectionMissing
        }
        #expect(closedCheck.lowerBound < beginAdmission.lowerBound)
        #expect(beginAdmission.lowerBound < packageAdmission.lowerBound)
    }

    @Test("fresh correlation retires admission state from the prior generation")
    func freshCorrelationClearsAdmissionFenceState() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )
        let body = String(reset)

        #expect(body.contains("applicationEvidenceAdmissionClosedGeneration = nil"))
        #expect(body.contains("pendingApplicationEvidenceAdmissions.removeAll()"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
