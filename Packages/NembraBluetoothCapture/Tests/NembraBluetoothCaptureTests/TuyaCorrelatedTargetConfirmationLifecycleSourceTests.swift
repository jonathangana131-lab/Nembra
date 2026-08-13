import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlated-target confirmation lifecycle")
struct TuyaCorrelatedTargetConfirmationLifecycleSourceTests {
    @Test("unexpected active generation cannot be hidden by local confirmation failure")
    func activeGenerationAtConfirmationUsesLedgerTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try function(in: app, startingAt: "func confirmCorrelatedTarget")

        #expect(confirmation.contains("currentConnectionToken"))
        #expect(confirmation.contains("invalidateInternalLifecycle"))

        guard let activeGuard = confirmation.range(of: "currentConnectionToken == nil") else {
            Issue.record("Confirmation no longer fences an already-active authenticated generation.")
            return
        }
        let tail = confirmation[activeGuard.lowerBound...]
        guard let returnRange = tail.range(of: "return") else {
            Issue.record("Active-generation confirmation branch has no terminal return.")
            return
        }
        let activeBranch = tail[..<returnRange.upperBound]

        // `failLocally` cancels app presentation/watchdog state but does not retire the package
        // ledger token. It must never be the cleanup path for a generation that already exists.
        #expect(!activeBranch.contains("failLocally"))
        #expect(activeBranch.contains("invalidateInternalLifecycle"))
    }

    @Test("normal operator confirmation remains a pure pending-to-selected promotion")
    func ordinaryConfirmationDoesNotManufactureLifecycleEvidence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try function(in: app, startingAt: "func confirmCorrelatedTarget")

        #expect(confirmation.contains("pendingCorrelatedTargetID"))
        #expect(confirmation.contains("targetCorrelationOperatorConfirmed = true"))
        #expect(confirmation.contains("selectedID = id"))
        #expect(confirmation.contains("phase = .selected"))
        #expect(confirmation.contains("candidate_selected"))

        // Confirmation itself is not a BLE/authentication/telemetry receipt.
        #expect(!confirmation.contains("markAuthenticated(for:"))
        #expect(!confirmation.contains("recordApplicationUpdate"))
        #expect(!confirmation.contains("observeCurrentConnection"))
    }

    private func function(in source: String, startingAt marker: String) throws -> Substring {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source function missing: \(marker)")
            throw SourceContractError.functionMissing
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[markerRange.lowerBound...index] }
            default: break
            }
            index = source.index(after: index)
        }

        Issue.record("Expected balanced source function body: \(marker)")
        throw SourceContractError.functionMissing
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

    private enum SourceContractError: Error { case functionMissing }
}
