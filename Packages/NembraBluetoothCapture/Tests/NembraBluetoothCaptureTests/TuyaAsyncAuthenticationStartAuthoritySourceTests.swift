import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture asynchronous authentication-start authority")
struct TuyaAsyncAuthenticationStartAuthoritySourceTests {
    @Test("membership recheck callback must revalidate selected confirmation before BLE ownership")
    func membershipCallbackCannotResurrectAStoppedAttempt() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticate = try section(
            in: app,
            from: "func authenticate()",
            to: "private func beginOfficialConnection"
        )

        #expect(authenticate.contains("self.phase == .selected"))
        #expect(authenticate.contains("self.targetCorrelationOperatorConfirmed"))
        #expect(authenticate.contains("self.selectedID == candidate.id"))
    }

    @Test("official connection cannot begin from a failed controller phase")
    func failedPhaseCannotStartOfficialConnection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let connectionStart = try section(
            in: app,
            from: "private func beginOfficialConnection",
            to: "private func authenticated"
        )

        #expect(connectionStart.contains("guard phase == .selected"))
        #expect(!connectionStart.contains("phase == .selected || phase == .failed"))
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
