import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya historical peripheral identity boundary")
struct TuyaHistoricalPeripheralIdentityBoundaryTests {
    @Test("C7D09A22 CoreBluetooth UUID is capture-local evidence, never durable scooter identity")
    func historicalPeripheralCannotMintTargetAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        // C7D09A22 physically observed this CoreBluetooth identifier, but current
        // canonical physical truth classifies it as capture-local historical evidence.
        // A future run may use it as a descriptive continuity hint only.
        #expect(!source.contains("var likely: Bool { knownID }"))
        #expect(!source.contains("accepted prior physical UUID"))
        #expect(!source.contains("accepted-prior-physical-corebluetooth-uuid"))
        #expect(!source.contains("Accepted prior physical UUID matched"))
    }

    @Test("official same-account exact-device membership owns SDK authentication target authority")
    func sdkMembershipOwnsAuthenticatedTarget() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticate = try section(
            in: source,
            from: "func authenticate()",
            to: "private func beginOfficialConnection"
        )

        #expect(authenticate.contains("verifySDKMembership"))
        #expect(authenticate.contains("accountIdentityLeaseIsAuthorized"))
        #expect(!authenticate.contains("candidate.likely"))
        #expect(!authenticate.contains("accepted prior physical scooter identity"))

        let connection = try section(
            in: source,
            from: "private func beginOfficialConnection",
            to: "private func authenticated(token:"
        )
        #expect(connection.contains("deviceID: self.deviceID"))
        #expect(connection.contains("uuid: self.tuyaUUID"))
        #expect(connection.contains("productID: self.productID"))
        #expect(connection.contains("accountIdentityLeaseIsAuthorized"))
    }

    @Test("CoreBluetooth discovery may describe correlation but cannot label historical UUID as identity authority")
    func discoveryLanguageStaysDescriptive() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("FD50"))
        #expect(source.contains("Tuya company"))
        #expect(source.contains("newAfterPowerOn"))
        #expect(!source.contains("authority\": \"accepted-prior-physical-corebluetooth-uuid"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected field-source section markers missing: \(start) ... \(end)")
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
