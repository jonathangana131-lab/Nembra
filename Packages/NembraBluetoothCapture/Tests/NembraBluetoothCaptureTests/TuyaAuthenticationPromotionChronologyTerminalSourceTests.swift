import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture authentication-promotion chronology terminal")
struct TuyaAuthenticationPromotionChronologyTerminalSourceTests {
    @Test("markAuthenticated chronology rejection uses the dedicated no-clock terminal")
    func authenticationPromotionRejectionUsesChronologyIntegrityTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = try section(
            in: app,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken)",
            to: "private func authenticationFailed"
        )
        let observedOnline = try section(
            in: String(authenticated),
            from: "case .observedOnline:",
            to: "case .keepWaiting:"
        )

        guard let promotion = observedOnline.range(of: "try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)"),
              let catchRange = observedOnline.range(of: "} catch {", range: promotion.upperBound..<observedOnline.endIndex) else {
            Issue.record("Could not isolate markAuthenticated promotion and its terminal catch path.")
            throw SourceContractError.sectionMissing
        }
        let catchPath = String(observedOnline[catchRange.lowerBound..<observedOnline.endIndex])

        // A markAuthenticated mutation can reject because chronology/monotonic integrity failed.
        // Source-account drift has already been checked separately before this mutation. Cleanup
        // must therefore retire the owner-bound generation without taking another clock sample.
        #expect(catchPath.contains("invalidateChronologyIntegrity"))
        #expect(!catchPath.contains("invalidateSourceAuthority"))
        #expect(!catchPath.contains("authenticationAcquisitionFailed"))
        #expect(!catchPath.contains("markAuthenticationFailed"))
        #expect(!catchPath.contains("invalidateObservationContinuity"))
        #expect(!catchPath.contains("endConnection"))
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
