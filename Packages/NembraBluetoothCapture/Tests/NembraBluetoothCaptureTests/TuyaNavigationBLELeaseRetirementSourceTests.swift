import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture navigation BLE lease retirement source contract")
struct TuyaNavigationBLELeaseRetirementSourceTests {
    @Test("leaving Secure Link cancels pending start authority and retires active package correlation")
    func secureLinkNavigationExitRetiresCorrelationLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private extension SecureLinkView"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))

        // Secure Link may disappear while exact-account membership enumeration is still in
        // flight, before any package scanner/lease exists. Revoke that callback authority first.
        let requestRevocationLine = try requiredLine(containing: "membershipRequestID = UUID()", in: cleanup)
        let busyClearLine = try requiredLine(containing: "membershipBusy = false", in: cleanup)
        let probeReleaseLine = try requiredLine(containing: "membershipProbe = nil", in: cleanup)
        let activeCorrelationGuardLine = try requiredLine(
            containing: "guard processCorrelationLease != nil || correlationSession != nil else { return }",
            in: cleanup
        )
        #expect(requestRevocationLine < activeCorrelationGuardLine)
        #expect(busyClearLine < activeCorrelationGuardLine)
        #expect(probeReleaseLine < activeCorrelationGuardLine)

        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("target_correlation_abandoned_on_view_exit"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))
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
