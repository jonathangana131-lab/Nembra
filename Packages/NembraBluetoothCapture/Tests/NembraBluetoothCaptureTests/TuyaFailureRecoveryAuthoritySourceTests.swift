import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failure recovery authority")
struct TuyaFailureRecoveryAuthoritySourceTests {
    @Test("guided failure UI cannot offer OFF1 restart while a package generation is still retained")
    func failureRecoveryUsesControllerAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        )
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )

        let controllerBody = String(controller)
        let surfaceBody = String(surface)

        // Some terminal-retirement failures intentionally retain currentConnectionToken and
        // require a process relaunch. Generic build/account readiness must never mint recovery
        // authority in those states. The controller owns this decision because only it owns the
        // package generation token.
        #expect(controllerBody.contains("canRestartFromFreshOFF1"))
        guard let recoveryProperty = controllerBody.range(of: "canRestartFromFreshOFF1") else {
            throw SourceContractError.sectionMissing
        }
        let recoveryTail = controllerBody[recoveryProperty.lowerBound...]
        #expect(recoveryTail.prefix(400).contains("currentConnectionToken == nil"))

        guard let failurePanel = surfaceBody.range(of: "private var failurePanel"),
              let completionPanel = surfaceBody.range(
                of: "private var completionPanel",
                range: failurePanel.upperBound..<surfaceBody.endIndex
              ) else {
            Issue.record("Could not isolate guided failure panel.")
            throw SourceContractError.sectionMissing
        }
        let failureBody = String(surfaceBody[failurePanel.lowerBound..<completionPanel.lowerBound])

        #expect(failureBody.contains("test.canRestartFromFreshOFF1"))
        #expect(failureBody.contains("Restart from scooter OFF"))
        #expect(
            failureBody.contains("Relaunch Capture") || failureBody.contains("relaunch"),
            Comment(rawValue: "Retained-generation failures must present the controller's relaunch-only recovery truth rather than a false in-app restart.")
        )
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
