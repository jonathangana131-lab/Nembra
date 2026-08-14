import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture export local-BLE proof state")
struct TuyaExportLocalBLEProofStateSourceTests {
    @Test("schema exports evidence state instead of an ambiguous online Bool")
    func exportUsesEvidenceState() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = try section(
            in: source,
            from: "struct Export: Codable {",
            to: "struct Event: Codable {"
        )
        let body = String(export)

        #expect(body.contains("let sdkLocalBLEEvidenceState: LocalBLEEvidenceState"))
        #expect(!body.contains("let sdkLocalBLEOnline: Bool"))
        #expect(source.contains("case observedOnlineAtLatestDirectSample = \"observed-online-at-latest-direct-sample\""))
        #expect(source.contains("case notProven = \"not-proven\""))
    }

    @Test("schema 11 maps proof absence to not-proven and never to observed offline")
    func exportMappingIsConservative() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let makeExport = String(try section(
            in: source,
            from: "private func makeExport(",
            to: "func prepareExport()"
        ))

        #expect(makeExport.contains("schemaVersion: 11"))
        #expect(makeExport.contains("sdkLocalBLEOnline ? .observedOnlineAtLatestDirectSample : .notProven"))
        #expect(!makeExport.contains("sdkLocalBLEOnline: sdkLocalBLEOnline"))
        #expect(!makeExport.contains("observed-offline"))
    }

    @Test("accepted export remains downstream of a fresh direct online sample")
    func acceptedExportRetainsFreshProofFence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: source,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))

        let packageSeal = try requiredOffset("try await sessionLedger.sealAcceptedObservation(for: token)", in: watchdog)
        let directRead = try requiredOffset("driver.isLocallyConnected(uuid: self.tuyaUUID)", in: watchdog, after: packageSeal)
        let mirror = try requiredOffset("self.sdkLocalBLEOnline = postSealLocalBLEOnline", in: watchdog, after: directRead)
        let onlineFence = try requiredOffset("guard postSealLocalBLEOnline else", in: watchdog, after: mirror)
        let exportFreeze = try requiredOffset("self.sealedAcceptedExport = self.makeExport(", in: watchdog, after: onlineFence)

        #expect(packageSeal < directRead)
        #expect(directRead < mirror)
        #expect(mirror < onlineFence)
        #expect(onlineFence < exportFreeze)
    }

    @Test("observed transport loss stays explicit instead of being inferred from not-proven")
    func observedLossRemainsSeparateEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let loss = String(try section(
            in: source,
            from: "private func recordObservedTransportLoss",
            to: "private func invalidateSourceAuthority"
        ))

        #expect(loss.contains("sessionLedger.endConnection(for: token)"))
        #expect(loss.contains("sdkLocalBLEOnline = false"))
        #expect(loss.contains("sdk_local_ble_dropped"))
        #expect(source.contains("false means\n        // “Not proven”"))
    }

    private func requiredOffset(_ token: String, in source: String, after: String.Index? = nil) throws -> String.Index {
        let lower = after ?? source.startIndex
        guard let range = source.range(of: token, range: lower..<source.endIndex) else {
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
