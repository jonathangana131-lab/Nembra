import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture view-exit terminal retirement lifetime source contract")
struct TuyaViewExitTerminalRetirementLifetimeSourceTests {
    @Test("active-generation view exit retains controller until package terminal retirement completes")
    func activeGenerationExitCannotDropRetirementWithControllerLifetime() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "if let token = currentConnectionToken {",
            to: "if phase == .authenticating {"
        ))

        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(cleanup.contains("await self.invalidateInternalLifecycle("))
        #expect(!cleanup.contains("[weak self]"))
        #expect(!cleanup.contains("guard let self else { return }"))
    }

    @Test("lifetime hardening does not invent physical disconnect or command authority")
    func lifetimeHardeningRemainsAppPackageRetirementOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "if let token = currentConnectionToken {",
            to: "if phase == .authenticating {"
        ))

        #expect(cleanup.contains("invalidateInternalLifecycle"))
        for forbidden in ["disconnectBLE", "publishDps", "queryDps", "writeValue", "endConnection(for:"] {
            #expect(!cleanup.contains(forbidden), "view-exit lifetime repair must not add physical/protocol authority: \(forbidden)")
        }
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
