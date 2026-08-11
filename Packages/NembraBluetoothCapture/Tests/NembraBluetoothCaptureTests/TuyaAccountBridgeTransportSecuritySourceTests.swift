import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account bridge transport security")
struct TuyaAccountBridgeTransportSecuritySourceTests {
    @Test("approval endpoint must normalize to HTTPS with a real host")
    func approvalEndpointRejectsPlaintextTransport() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let approval = try section(in: bridge, from: "private func pollApprovalOnce", to: "private func scheduleDeviceLoad")
        let normalization = try section(in: bridge, from: "private static func normalizedAuthenticatedEndpoint", to: "private static func requestJSON")

        #expect(approval.contains("guard let endpoint = Self.normalizedAuthenticatedEndpoint(rawEndpoint) else"))
        #expect(!approval.contains("rawEndpoint.hasPrefix(\"http\")"))
        #expect(normalization.contains("components.scheme?.lowercased() == \"https\""))
        #expect(normalization.contains("let host = components.host"))
        #expect(normalization.contains("!host.isEmpty"))
        #expect(normalization.contains("components.user == nil"))
        #expect(normalization.contains("components.password == nil"))
    }

    @Test("authenticated requests fail closed on non-HTTPS originals and redirect downgrades")
    func authenticatedRequestsRejectTransportDowngrade() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let requestJSON = try section(in: bridge, from: "private static func requestJSON", to: "private static func compactJSONString")

        #expect(bridge.contains("private final class TuyaHTTPSOnlyRedirectDelegate"))
        #expect(bridge.contains("willPerformHTTPRedirection"))
        #expect(bridge.contains("url.scheme?.lowercased() == \"https\""))
        #expect(bridge.contains("completionHandler(nil)"))
        #expect(requestJSON.contains("requestURL.scheme?.lowercased() == \"https\""))
        #expect(requestJSON.contains("URLSession.shared.data(for: request, delegate: redirectDelegate)"))
        #expect(!requestJSON.contains("URLSession.shared.data(for: request)"))
    }

    @Test("signed device reads revalidate the stored session endpoint")
    func signedReadsRevalidateSessionEndpoint() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let signed = try section(in: bridge, from: "private func signedGET", to: "private static func makeDevice")

        #expect(signed.contains("guard let endpoint = Self.normalizedAuthenticatedEndpoint(session.endpoint) else"))
        #expect(!signed.contains("var endpoint = session.endpoint"))
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
