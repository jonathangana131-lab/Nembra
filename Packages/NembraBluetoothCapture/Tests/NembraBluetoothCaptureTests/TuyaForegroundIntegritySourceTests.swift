import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity authority")
struct TuyaForegroundIntegritySourceTests {
    @Test("field shell observes scene activity and forwards foreground loss immediately")
    func fieldShellCannotRelyOnPollingGapAsForegroundAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let shell = try declarationBody(in: app, signature: "private struct SecureLinkView: View")

        #expect(shell.contains("@Environment(\\.scenePhase)"))
        #expect(shell.contains(".onChange(of: scenePhase)"))
        #expect(shell.contains("newPhase != .active"))
        #expect(shell.contains("test.handleForegroundIntegrityLoss()") || shell.contains("controller.handleForegroundIntegrityLoss()"))
    }

    @Test("foreground loss invalidates only a live attempt without inventing another terminal fact")
    func foregroundLossUsesExistingTruthfulLifecycleBoundaries() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let handler = try declarationBody(in: app, signature: "func handleForegroundIntegrityLoss()")

        // Landing/login, an already-failed attempt, and an already-sealed accepted prefix
        // are not rewritten merely because the scene becomes inactive.
        #expect(handler.contains(".idle"))
        #expect(handler.contains(".failed"))
        #expect(handler.contains(".accepted"))

        // Discovery/correlation loses authority immediately and must return through the
        // existing fail-closed path so the next attempt starts from a genuinely fresh OFF1.
        #expect(handler.contains("correlationSession?.abandonCurrentWindow()") || handler.contains("failLocally("))
        #expect(handler.contains("foreground_integrity_lost"))

        // Pre-auth package ownership and authenticated observation are different facts.
        // Reuse the controller's existing truthful retirement helpers; foreground loss is
        // neither proof of Tuya local-BLE disconnect nor account/source-identity drift.
        #expect(handler.contains("invalidateInternalLifecycle("))
        #expect(handler.contains("invalidateObservationContinuity("))
        #expect(!handler.contains("endConnection(for:"))
        #expect(!handler.contains("invalidateSourceAuthority("))
        #expect(!handler.contains("markSourceAuthorityInvalidated(for:"))
    }

    @Test("five second watchdog remains a separate continuity defense")
    func watchdogGapCannotReplaceExplicitSceneAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("maximumContinuousObservationGapNanoseconds") || app.contains("maximumObservationPollGapNanoseconds"))
        #expect(app.contains("handleForegroundIntegrityLoss"))
        #expect(app.contains("scenePhase"))
    }

    private func declarationBody(in source: String, signature: String) throws -> Substring {
        guard let signatureRange = source.range(of: signature),
              let openingBrace = source[signatureRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source declaration missing: \(signature)")
            throw SourceContractError.declarationMissing
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[openingBrace...index] }
            default: break
            }
            index = source.index(after: index)
        }

        Issue.record("Unbalanced source declaration: \(signature)")
        throw SourceContractError.declarationMissing
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
        case declarationMissing
    }
}
