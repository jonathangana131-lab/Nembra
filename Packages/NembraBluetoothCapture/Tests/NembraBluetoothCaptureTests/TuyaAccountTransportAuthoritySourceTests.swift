import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Tuya account HTTPS transport authority")
struct TuyaAccountTransportAuthoritySourceTests {
    @Test("server-provided account endpoint is normalized to canonical HTTPS only")
    func serverEndpointIsHTTPSOnly() throws {
        let source = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(!source.contains("rawEndpoint.hasPrefix(\"http\")"))
        #expect(source.contains("let endpoint = try Self.normalizedHTTPSAPIEndpoint(rawEndpoint)"))
        #expect(source.contains("components.scheme?.lowercased() == \"https\""))
        #expect(source.contains("let host = components.host"))
        #expect(source.contains("components.user == nil"))
        #expect(source.contains("components.password == nil"))
        #expect(source.contains("components.query == nil"))
        #expect(source.contains("components.fragment == nil"))
        #expect(source.contains("components.path.isEmpty || components.path == \"/\""))
    }

    @Test("authenticated JSON transport rejects plaintext and redirect replay")
    func authenticatedRequestsFailClosedBeforeTransport() throws {
        let source = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let requestJSON = try section(
            in: source,
            from: "private static func requestJSON(_ request: URLRequest)",
            to: "private static func signedGET"
        )

        #expect(source.contains("private final class TuyaAccountBridgeNoRedirectDelegate"))
        #expect(source.contains("completionHandler(nil)"))
        #expect(requestJSON.contains("requestURL.scheme?.lowercased() == \"https\""))
        #expect(requestJSON.contains("let host = requestURL.host"))
        #expect(requestJSON.contains("!host.isEmpty"))
        #expect(requestJSON.contains("throw BridgeError.invalidURL"))
        #expect(requestJSON.contains("URLSession.shared.data(for: request, delegate: redirectDelegate)"))
        #expect(!requestJSON.contains("URLSession.shared.data(for: request)"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
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
