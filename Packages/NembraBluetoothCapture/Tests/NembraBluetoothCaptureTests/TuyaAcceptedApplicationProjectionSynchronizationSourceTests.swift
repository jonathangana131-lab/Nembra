import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application projection synchronization")
struct TuyaAcceptedApplicationProjectionSynchronizationSourceTests {
    @Test("ledger admission returns a sealed monotonic application receipt")
    func ledgerAdmissionReturnsReceipt() throws {
        let ledger = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let record = try section(
            in: ledger,
            from: "public func recordApplicationUpdate",
            to: "public func observeCurrentConnection"
        )
        let body = String(record)

        #expect(ledger.contains("public struct TuyaReadOnlyApplicationReceipt"), Comment(rawValue: "Aggregate payload count is insufficient to bind app structured values to exact package admission order."))
        #expect(body.contains("-> TuyaReadOnlyApplicationReceipt"), Comment(rawValue: "A successful package admission must return package-issued receipt identity instead of only mutating hidden aggregate count."))
        #expect(body.contains("applicationPayloadCount += 1"))
        #expect(body.contains("sequence:"), Comment(rawValue: "The returned receipt must carry the exact package admission sequence."))
        #expect(body.contains("generation:"), Comment(rawValue: "The returned receipt must remain bound to the accepted connection generation."))
    }

    @Test("a package-accepted update enters the app receipt-ordered projector before another voluntary suspension")
    func acceptedUpdateProjectsBeforeNextSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func startWatchdog"
        )
        let body = String(receive)

        #expect(app.contains("private var acceptedApplicationProjectionSequence"), Comment(rawValue: "The controller needs a current-attempt contiguous package-receipt projection frontier, not a lifetime diagnostic event count."))
        #expect(app.contains("private var pendingAcceptedApplicationUpdates"), Comment(rawValue: "Out-of-order async task resumptions must wait behind the missing package receipt instead of changing accepted export order."))

        guard let packageAdmission = body.range(of: "let applicationReceipt = try await sessionLedger.recordApplicationUpdate"),
              let projection = body.range(of: "projectAcceptedApplicationUpdate(", range: packageAdmission.upperBound..<body.endIndex) else {
            Issue.record("A successful package admission must return its receipt and feed the receipt-ordered app projector.")
            throw SourceContractError.sectionMissing
        }

        if let nextAwait = body.range(of: "await ", range: packageAdmission.upperBound..<body.endIndex) {
            #expect(projection.lowerBound < nextAwait.lowerBound, Comment(rawValue: "Do not insert another voluntary suspension between package admission and receipt-ordered projection."))
        }
    }

    @Test("receipt projector rejects generation mismatch and flushes only a contiguous package sequence")
    func projectorIsGenerationBoundAndContiguous() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let projector = try section(
            in: app,
            from: "private func projectAcceptedApplicationUpdate",
            to: "private func startWatchdog"
        )
        let body = String(projector)

        #expect(body.contains("applicationReceipt.diagnosticGeneration"), Comment(rawValue: "A receipt from another connection generation must never enter the current app accepted prefix."))
        #expect(body.contains("token.diagnosticGeneration"))
        #expect(body.contains("pendingAcceptedApplicationUpdates"))
        #expect(body.contains("acceptedApplicationProjectionSequence + 1"), Comment(rawValue: "Only the next contiguous package receipt may advance the exported structured-value frontier."))
        #expect(body.contains("applicationReceiptSequence"), Comment(rawValue: "Accepted structured evidence must retain the package admission sequence as provenance."))
    }

    @Test("canonical readiness cannot seal while app structured projection trails package receipts")
    func sealRequiresProjectionReceiptSynchronization() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let ready = try section(
            in: String(watchdog),
            from: "case .readyForStationaryMapping:",
            to: "try await sessionLedger.sealAcceptedObservation(for: token)"
        )
        let body = String(ready)

        #expect(body.contains("acceptedApplicationProjectionSequence"), Comment(rawValue: "The seal path must consult app-side receipt-ordered structured evidence, not package readiness alone."))
        #expect(body.contains("applicationPayloadCount"), Comment(rawValue: "The app projection frontier must be compared with the exact current package accepted count."))
        #expect(body.contains("=="), Comment(rawValue: "The accepted prefix may seal only when the contiguous app receipt frontier equals package accepted receipts."))
        #expect(body.contains("pendingAcceptedApplicationUpdates.isEmpty"), Comment(rawValue: "No out-of-order accepted update may still be waiting when the immutable prefix is sealed."))
    }

    @Test("a fresh correlation life cannot inherit an older generation projection frontier")
    func freshAttemptResetsProjectionState() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(reset.contains("acceptedApplicationProjectionSequence = 0"), Comment(rawValue: "Current-generation accepted application projection state must not survive into a fresh OFF1 correlation life."))
        #expect(reset.contains("pendingAcceptedApplicationUpdates.removeAll"), Comment(rawValue: "A fresh correlation life must discard any unprojected structured value from the retired generation."))
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
