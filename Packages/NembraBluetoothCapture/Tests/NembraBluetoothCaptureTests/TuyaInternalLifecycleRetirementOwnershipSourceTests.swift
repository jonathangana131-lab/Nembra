import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture internal-lifecycle terminal ownership")
struct TuyaInternalLifecycleRetirementOwnershipSourceTests {
    @Test("failed package retirement cannot discard the app-owned generation")
    func internalLifecycleFailureKeepsTokenUntilRetirementSucceeds() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let terminal = try section(
            in: app,
            from: "private func invalidateInternalLifecycle",
            to: "private func refreshLedgerSnapshot"
        )

        #expect(terminal.contains("guard currentConnectionToken == token else { return }"))
        #expect(terminal.contains("try await sessionLedger.markInternalLifecycleFailure(for: token)"))
        #expect(!terminal.contains("try? await sessionLedger.markInternalLifecycleFailure(for: token)"))
        #expect(terminal.contains("Relaunch Capture before another attempt"))

        guard let catchRange = terminal.range(of: "catch {") else {
            Issue.record("Internal-lifecycle terminal no longer handles package retirement failure explicitly.")
            return
        }
        let afterCatch = terminal[catchRange.lowerBound...]
        guard let ownershipClear = afterCatch.range(of: "currentConnectionToken = nil") else {
            Issue.record("Successful terminal path no longer releases app token ownership.")
            return
        }
        let failedRetirementPath = afterCatch[..<ownershipClear.lowerBound]

        #expect(failedRetirementPath.contains("return"))
        #expect(!failedRetirementPath.contains("currentConnectionToken = nil"))
    }

    @Test("new ledger generation is app-owned before authentication-start can fail")
    func authenticationStartOwnsTokenBeforeMutation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let connection = try section(
            in: app,
            from: "let token = try await self.sessionLedger.beginConnection()",
            to: "self.log(\"official_connect_requested\""
        )

        guard let ownership = connection.range(of: "self.currentConnectionToken = token"),
              let authStart = connection.range(of: "try await self.sessionLedger.markAuthenticationStarted(for: token)") else {
            Issue.record("Authentication-start ownership markers are missing.")
            return
        }
        #expect(ownership.lowerBound < authStart.lowerBound)
        #expect(connection.contains("markInternalLifecycleFailure(for: token)"))
        #expect(connection.contains("terminal retirement failed") || connection.contains("could not be retired"))
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
