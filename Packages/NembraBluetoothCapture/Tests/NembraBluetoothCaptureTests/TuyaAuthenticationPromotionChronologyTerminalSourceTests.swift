import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture authentication chronology retirement")
struct TuyaAuthenticationPromotionChronologyTerminalSourceTests {
    @Test("newly minted generation is app-owned before authentication-start can reject chronology")
    func authenticationStartFailureCannotHideMintedGeneration() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let connectionStart = try section(
            in: app,
            from: "private func beginOfficialConnection(candidate:",
            to: "private func authenticated(token:"
        )
        let source = String(connectionStart)

        guard let minted = source.range(of: "let token = try await self.sessionLedger.beginConnection()"),
              let owned = source.range(of: "self.currentConnectionToken = token", range: minted.upperBound..<source.endIndex),
              let authStarted = source.range(of: "try await self.sessionLedger.markAuthenticationStarted(for: token)", range: minted.upperBound..<source.endIndex),
              let connect = source.range(of: "newDriver.connect(", range: authStarted.upperBound..<source.endIndex) else {
            Issue.record("Could not isolate beginConnection -> auth-start -> SDK-connect chronology.")
            throw SourceContractError.sectionMissing
        }

        // beginConnection mints an owner-bound package generation immediately. The controller must
        // own that token before the next clock-sampling mutation can fail, otherwise the package can
        // retain a current token that the app can no longer name or terminally retire.
        #expect(owned.lowerBound < authStarted.lowerBound)

        let postMintPreConnect = String(source[minted.lowerBound..<connect.lowerBound])
        #expect(postMintPreConnect.contains("invalidateChronologyIntegrity"))
    }

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
