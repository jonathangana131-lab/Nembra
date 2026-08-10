import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture navigation BLE lease retirement source contract")
struct TuyaNavigationBLELeaseRetirementSourceTests {
    @Test("leaving Secure Link revokes pending start authority and retires active package correlation")
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
        #expect(cleanup.contains("membershipRequestID = UUID()"))
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("guard processCorrelationLease != nil || correlationSession != nil else { return }"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("target_correlation_abandoned_on_view_exit"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))
    }

    @Test("view exit revokes pending official authentication and terminally retires active generation")
    func viewExitRevokesOfficialAuthenticationAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))
        #expect(controller.contains("private var officialConnectionRequestID = UUID()"))
        #expect(cleanup.contains("officialConnectionRequestID = UUID()"))
        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("if let token = currentConnectionToken"))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("if phase == .authenticating"))
        #expect(cleanup.contains("authentication_start_abandoned_on_view_exit"))
        #expect(!cleanup.contains("disconnectBLE"))

        let begin = String(try section(
            in: controller,
            from: "private func beginOfficialConnection(candidate: Candidate)",
            to: "private func authenticated(token: TuyaReadOnlyConnectionToken)"
        ))
        #expect(begin.contains("let connectionRequestID = UUID()"))
        #expect(begin.contains("officialConnectionRequestID = connectionRequestID"))
        #expect(begin.components(separatedBy: "self.officialConnectionRequestID == connectionRequestID").count - 1 == 2)
        let finalFence = try requiredLine(containing: "self.currentConnectionToken == token", in: begin)
        let sdkConnect = try requiredLine(containing: "newDriver.connect(", in: begin)
        #expect(finalFence < sdkConnect)
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
