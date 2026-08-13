import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation restart lifecycle")
struct TuyaCorrelationRestartLifecycleSourceTests {
    @Test("OFF1 restart cannot hide a package-owned authenticated generation")
    func correlationRestartRetiresUnexpectedGeneration() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let function = try sourceFunction(in: app, marker: "private func beginCorrelationSeries()")

        guard let guardRange = function.range(of: "currentConnectionToken == nil") else {
            Issue.record("Correlation restart no longer fences an already-active session generation.")
            return
        }
        let tail = function[guardRange.lowerBound...]
        guard let returnRange = tail.range(of: "return") else {
            Issue.record("Active-generation restart branch has no terminal return.")
            return
        }
        let activeGenerationBranch = tail[..<returnRange.upperBound]

        #expect(activeGenerationBranch.contains("invalidateInternalLifecycle"))
        #expect(!activeGenerationBranch.contains("failLocally"))
    }

    @Test("ordinary OFF1 restart stays evidence-neutral")
    func ordinaryCorrelationRestartDoesNotManufactureSessionEvidence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let function = try sourceFunction(in: app, marker: "private func beginCorrelationSeries()")

        #expect(function.contains("PassiveBluetoothPowerCycleObservationSession"))
        #expect(function.contains("resetDiscoverySessionOnly()"))
        #expect(!function.contains("markAuthenticated(for:"))
        #expect(!function.contains("recordApplicationUpdate"))
        #expect(!function.contains("endConnection(for:"))
    }

    private func sourceFunction(in source: String, marker: String) throws -> Substring {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source function missing: \(marker)")
            throw SourceContractError.functionMissing
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[markerRange.lowerBound...index] }
            default: break
            }
            index = source.index(after: index)
        }

        Issue.record("Expected balanced source function body: \(marker)")
        throw SourceContractError.functionMissing
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

    private enum SourceContractError: Error { case functionMissing }
}
