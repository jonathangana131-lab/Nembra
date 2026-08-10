import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed-state account recovery")
struct TuyaSecureLinkFailedAccountRecoverySourceTests {
    @Test("recoverable failed state cannot hide the SDK login control behind its restart action")
    func recoverableFailureKeepsSDKLoginReachable() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )
        let primary = try section(
            in: String(surface),
            from: "private var primarySurface: some View",
            to: "private var preflightPanel: some View"
        )
        let body = String(primary)

        #expect(!body.contains("case .failed:\n            failurePanel"))
        #expect(body.contains("case .failed:"))
        #expect(body.contains("sdkAccount.loggedIn"))
        #expect(body.contains("sdkAuthorizationPanel"))
    }

    @Test("failed recovery still requires retired package ownership before any in-process OFF1 retry")
    func failedRecoveryPreservesLifecycleAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController: NSObject, ObservableObject",
            to: "private protocol OfficialTuyaDriver"
        )
        let body = String(controller)

        #expect(body.contains("var failedAttemptCanRestartFromOFF1: Bool"))
        #expect(body.contains("phase == .failed"))
        #expect(body.contains("currentConnectionToken == nil"))
        #expect(body.contains("localBLESettlementToken == nil"))
        #expect(body.contains("driver == nil"))
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
