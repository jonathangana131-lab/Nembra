import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture post-handoff foreground reactivation")
struct TuyaCapturePostHandoffReactivationSourceTests {
    @Test("active transition cannot reopen membership after official Tuya handoff")
    func reactivationRemainsClosedAfterHandoff() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))

        let processGate = try requiredOffset(
            containing: "OfficialTuyaFactory.packageCorrelationMayStart",
            in: activation
        )
        let tokenGate = try requiredOffset(
            containing: "currentConnectionToken == nil",
            in: activation
        )
        let resetLossFence = try requiredOffset(
            containing: "foregroundIntegrityLossHandled = false",
            in: activation
        )
        let reopenMembership = try requiredOffset(
            containing: "acceptsViewScopedMembershipRequests = true",
            in: activation
        )

        #expect(processGate < resetLossFence)
        #expect(tokenGate < resetLossFence)
        #expect(resetLossFence < reopenMembership)

        // make() permanently flips this process authority before the async package token exists;
        // token-nil alone therefore cannot authorize foreground recovery.
        let factory = String(try section(
            in: source,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        ))
        #expect(factory.contains("packageCorrelationRetiredForProcess = true"))
        #expect(factory.contains("static var packageCorrelationMayStart"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
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
