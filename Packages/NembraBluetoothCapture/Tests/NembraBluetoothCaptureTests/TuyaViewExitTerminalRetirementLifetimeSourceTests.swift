import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture view-exit terminal retirement lifetime")
struct TuyaViewExitTerminalRetirementLifetimeSourceTests {
    @Test("active generation retirement keeps controller alive until package terminal completes")
    func activeGenerationRetirementHasStrongLifetime() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))
        let active = String(try section(
            in: cleanup,
            from: "if let token = currentConnectionToken",
            to: "if phase == .authenticating"
        ))

        #expect(active.contains("invalidateInternalLifecycle("))
        #expect(!active.contains("[weak self]"), "View exit may destroy the StateObject immediately; exact-token terminal retirement cannot depend on a weak controller surviving navigation.")
        #expect(
            active.contains("Task { @MainActor [self] in") || active.contains("Task { @MainActor in\n                await self.invalidateInternalLifecycle("),
            "The finite terminal-retirement task must retain the controller/ledger until the exact package generation is retired."
        )
        #expect(!active.contains("disconnectBLE"))
        #expect(!active.contains("releasePackageCorrelationLease()"))
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

    private enum SourceContractError: Error { case sectionMissing }
}
