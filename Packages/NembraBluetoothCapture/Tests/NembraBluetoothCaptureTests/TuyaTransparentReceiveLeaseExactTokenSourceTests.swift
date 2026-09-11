import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya transparent receive lease exact-token custody")
struct TuyaTransparentReceiveLeaseExactTokenSourceTests {
    @Test("idempotent arm requires exact token and retained delegate ownership")
    func idempotentArmCannotSurviveTokenCollisionOrDelegateDisplacement() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")
        let arm = String(try section(
            in: source,
            from: "func armAndInstallAfterSmartLifeAuthentication(",
            to: "func fieldAttemptEvidence(for connectionToken: Generation)"
        ))

        #expect(arm.contains("return generation == connectionToken && ownsManagerDelegateSlot ? generation : nil"))
        #expect(!arm.contains("generation.diagnosticGeneration == connectionToken.diagnosticGeneration"))
    }

    @Test("evidence and diagnostics require the exact package token")
    func evidenceReadsRejectSameNumberTokensFromAnotherLedger() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")
        let evidence = String(try section(
            in: source,
            from: "func fieldAttemptEvidence(for connectionToken: Generation)",
            to: "func diagnosticSnapshot("
        ))
        let diagnostic = String(try section(
            in: source,
            from: "func diagnosticSnapshot(",
            to: "func terminalLifecycleDidOccur(for connectionToken: Generation)"
        ))

        #expect(evidence.contains("guard generation == connectionToken,"))
        #expect(evidence.contains("ownsManagerDelegateSlot else"))
        #expect(diagnostic.contains("guard generation == connectionToken,"))
        #expect(diagnostic.contains("ownsManagerDelegateSlot else"))
    }

    @Test("terminal retirement cannot clear a lease for a colliding generation number")
    func terminalRetirementRequiresExactPackageToken() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")
        let terminal = String(try section(
            in: source,
            from: "func terminalLifecycleDidOccur(for connectionToken: Generation)",
            to: "func terminalOwnerTeardown()"
        ))

        #expect(terminal.contains("guard generation == connectionToken else"))
        #expect(!terminal.contains("generation?.diagnosticGeneration == connectionToken.diagnosticGeneration"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
