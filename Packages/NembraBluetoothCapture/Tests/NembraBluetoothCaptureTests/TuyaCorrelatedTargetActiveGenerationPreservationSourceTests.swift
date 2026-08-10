import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlated-target confirmation preserves existing generation authority")
struct TuyaCorrelatedTargetActiveGenerationPreservationSourceTests {
    @Test("confirmation cannot strand an already-owned authenticated generation through generic local failure")
    func activeGenerationGuardPreservesLedgerOwnership() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try function(in: app, startingAt: "func confirmCorrelatedTarget")

        guard let activeGuard = confirmation.range(of: "guard currentConnectionToken == nil else"),
              let selection = confirmation.range(of: "selectedID = id", range: activeGuard.upperBound..<confirmation.endIndex) else {
            Issue.record("Could not isolate active-generation confirmation guard before target selection.")
            throw SourceContractError.sectionMissing
        }

        let blockedPath = confirmation[activeGuard.lowerBound..<selection.lowerBound]

        // This guard is defensive: normal correlation starts only with no current generation.
        // If the invariant is nevertheless violated, a confirmation tap must not send the
        // already-owned ledger generation through generic UI failure. failLocally() cancels
        // watchdog/presentation state but does not terminally retire the package token, which
        // can strand hidden callback authority. Preserve the generation and block promotion.
        #expect(!blockedPath.contains("failLocally("))
        #expect(!blockedPath.contains("currentConnectionToken = nil"))
        #expect(!blockedPath.contains("localBLESettlementToken = nil"))
        #expect(!blockedPath.contains("watchdog?.cancel"))
        #expect(!blockedPath.contains("phase = .failed"))

        // The blocked path still must not promote the correlated candidate.
        #expect(!blockedPath.contains("targetCorrelationOperatorConfirmed = true"))
        #expect(!blockedPath.contains("phase = .selected"))
        #expect(!blockedPath.contains("candidate_selected"))
        #expect(blockedPath.contains("return"))
    }

    private func function(in source: String, startingAt marker: String) throws -> Substring {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source function missing: \(marker)")
            throw SourceContractError.sectionMissing
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
        throw SourceContractError.sectionMissing
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
