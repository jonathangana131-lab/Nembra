import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("C7D09A22 live preflight exact-token lifecycle custody")
struct C7D09A22DocumentedTransparentLivePreflightExactTokenSourceTests {
    @Test("live preflight retains the exact package token")
    func retainsExactPackageTokenRatherThanOnlyDiagnosticGeneration() throws {
        let source = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/C7D09A22DocumentedTransparentLivePreflight.swift"
        )

        #expect(source.contains("private var activeConnectionToken: TuyaReadOnlyConnectionToken?"))
        #expect(source.contains("self.activeConnectionToken = connectionToken"))
        #expect(source.contains("activeConnectionToken.diagnosticGeneration"))
        #expect(!source.contains("private var activeGeneration: UInt64?"))
    }

    @Test("terminal retirement requires exact token equality")
    func retirementRejectsSameNumberTokenFromAnotherLedger() throws {
        let source = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/C7D09A22DocumentedTransparentLivePreflight.swift"
        )
        let retirement = String(try section(
            in: source,
            from: "public func retire(connectionToken: TuyaReadOnlyConnectionToken) async -> Bool",
            to: "public func retire() async"
        ))

        #expect(retirement.contains("guard activeConnectionToken == connectionToken else { return false }"))
        #expect(!retirement.contains("connectionToken.diagnosticGeneration"))
    }

    @Test("diagnostic generation stays presentation-only")
    func diagnosticGenerationIsDerivedFromExactToken() throws {
        let source = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/C7D09A22DocumentedTransparentLivePreflight.swift"
        )

        #expect(source.contains(
            "public var activeDiagnosticGeneration: UInt64? { activeConnectionToken?.diagnosticGeneration }"
        ))
        #expect(source.contains("Never use this value as lifecycle authority"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
