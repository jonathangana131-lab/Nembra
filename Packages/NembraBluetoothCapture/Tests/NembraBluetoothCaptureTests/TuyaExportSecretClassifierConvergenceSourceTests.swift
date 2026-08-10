import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture export secret classifier convergence")
struct TuyaExportSecretClassifierConvergenceSourceTests {
    private let promisedSecretFragments = [
        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]

    @Test("application and metadata classifiers cover one coherent export-secret set")
    func classifiersStayConverged() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driverList = String(try section(
            in: app,
            from: "private static let secretKeyFragments = [",
            to: "private static func redactApplicationSecrets(_ object: Any) -> Any"
        ))
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let bridgeRedactor = String(try section(
            in: bridge,
            from: "private static func redactSecrets(_ object: Any) -> Any",
            to: "private static func remoteMessage(_ object: [String: Any]) -> String"
        ))

        for fragment in promisedSecretFragments {
            #expect(driverList.components(separatedBy: "\"\(fragment)\"").count - 1 == 1)
            #expect(bridgeRedactor.components(separatedBy: "\"\(fragment)\"").count - 1 == 1)
        }
        #expect(bridgeRedactor.contains("key.lowercased().filter"))
        #expect(bridgeRedactor.contains("redactSecrets(value)"))
        #expect(bridgeRedactor.contains("array.map(redactSecrets)"))
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
