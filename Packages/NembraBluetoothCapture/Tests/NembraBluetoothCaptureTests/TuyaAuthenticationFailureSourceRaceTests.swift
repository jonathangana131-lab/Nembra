import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture SDK failure source-authority race")
struct TuyaAuthenticationFailureSourceRaceTests {
    @Test("current SDK failure cannot overwrite already-drifted account or membership authority")
    func authenticationFailureRechecksSourceAuthorityBeforeChoosingTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let failure = try section(
            in: app,
            from: "private func authenticationFailed(token:",
            to: "private func authenticationAcquisitionFailed"
        )

        #expect(failure.contains("currentConnectionToken == token"))
        #expect(failure.contains("sdkAccountLoggedIn"))
        #expect(failure.contains("sdkDeviceMembershipVerified"))
        #expect(failure.contains("accountIdentityLeaseIsAuthorized"))
        #expect(failure.contains("invalidateSourceAuthority"))
        #expect(failure.contains("authenticationAcquisitionFailed"))
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
