import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture navigation BLE lease retirement source contract")
struct TuyaNavigationBLELeaseRetirementSourceTests {
    @Test("leaving Secure Link deterministically retires package correlation before controller loss")
    func secureLinkNavigationExitRetiresCorrelationLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let hook = String(try section(
            in: source,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))
        let viewLifecycle = String(try section(
            in: source,
            from: ".task {",
            to: ".onChange(of: sdkAccount.loggedIn)"
        ))

        let guardLine = try requiredLine(
            containing: "guard processCorrelationLease != nil || correlationSession != nil else { return }",
            in: hook
        )
        let abandonLine = try requiredLine(containing: "abandonPackageCorrelation()", in: hook)
        let failureLine = try requiredLine(containing: "phase = .failed", in: hook)
        let recoveryLine = try requiredLine(containing: "Restart from OFF1", in: hook)
        let logLine = try requiredLine(containing: "target_correlation_abandoned_on_view_exit", in: hook)

        #expect(guardLine < abandonLine)
        #expect(abandonLine < failureLine)
        #expect(failureLine < recoveryLine)
        #expect(recoveryLine < logLine)

        let disappearLine = try requiredLine(containing: ".onDisappear", in: viewLifecycle)
        let hookCallLine = try requiredLine(containing: "test.abandonCorrelationForViewExit()", in: viewLifecycle)
        #expect(disappearLine < hookCallLine)
    }

    @Test("cleanup reuses transport-first package abandonment path")
    func packageTransportRetirementPrecedesLeaseRelease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let abandon = String(try section(
            in: source,
            from: "private func abandonPackageCorrelation()",
            to: "private func releasePackageCorrelationLease()"
        ))
        let abandonLine = try requiredLine(containing: "correlationSession?.abandonCurrentWindow()", in: abandon)
        let releaseLine = try requiredLine(containing: "releasePackageCorrelationLease()", in: abandon)
        #expect(abandonLine < releaseLine)
    }

    private func requiredLine(containing token: String, in source: String) throws -> Int {
        guard let index = source.components(separatedBy: "\n").firstIndex(where: { $0.contains(token) }) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return index
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
