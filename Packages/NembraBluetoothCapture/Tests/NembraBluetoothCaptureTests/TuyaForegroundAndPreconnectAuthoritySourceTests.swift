import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground + pre-connect authority")
struct TuyaForegroundAndPreconnectAuthoritySourceTests {
    @Test("field shell consumes foreground loss explicitly")
    func fieldShellCannotUsePollingGapAsForegroundAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let shell = try declarationBody(in: source, signature: "private struct SecureLinkView: View")

        #expect(shell.contains("@Environment(\\.scenePhase)"))
        #expect(shell.contains(".onChange(of: scenePhase)"))
        #expect(shell.contains("newPhase != .active"))
        #expect(shell.contains("test.handleForegroundIntegrityLoss()"))
    }

    @Test("authentication owns an opaque attempt across every pre-connect suspension")
    func staleAsyncContinuationCannotIssueTuyaConnect() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try declarationBody(in: source, signature: "private final class SecureLinkController")
        let begin = try declarationBody(in: source, signature: "private func beginOfficialConnection(candidate: Candidate)")

        #expect(controller.contains("private var authenticationAttemptID: UUID?"))
        #expect(controller.contains("private var authenticationConnectRequestIssued"))
        #expect(begin.contains("let attemptID = UUID()"))
        #expect(begin.contains("authenticationAttemptID = attemptID"))
        #expect(begin.contains("authenticationConnectRequestIssued = false"))
        #expect(begin.contains("authenticationAttemptStillAuthorized(attemptID, candidate: candidate)"))
        #expect(begin.contains("retireCancelledPreconnectGeneration"))

        let beginConnection = try #require(begin.range(of: "sessionLedger.beginConnection()"))
        let firstRecheck = try #require(begin.range(
            of: "authenticationAttemptStillAuthorized(attemptID, candidate: candidate)",
            range: beginConnection.upperBound..<begin.endIndex
        ))
        let authStarted = try #require(begin.range(of: "sessionLedger.markAuthenticationStarted(for: token)"))
        let secondRecheck = try #require(begin.range(
            of: "authenticationAttemptStillAuthorized(attemptID, candidate: candidate)",
            range: authStarted.upperBound..<begin.endIndex
        ))
        let refresh = try #require(begin.range(of: "await self.refreshLedgerSnapshot()", range: secondRecheck.upperBound..<begin.endIndex))
        let finalRecheck = try #require(begin.range(
            of: "authenticationAttemptStillAuthorized(attemptID, candidate: candidate)",
            range: refresh.upperBound..<begin.endIndex
        ))
        let issued = try #require(begin.range(of: "authenticationConnectRequestIssued = true", range: finalRecheck.upperBound..<begin.endIndex))
        let connect = try #require(begin.range(of: "newDriver.connect(", range: issued.upperBound..<begin.endIndex))

        #expect(beginConnection.lowerBound < firstRecheck.lowerBound)
        #expect(authStarted.lowerBound < secondRecheck.lowerBound)
        #expect(refresh.lowerBound < finalRecheck.lowerBound)
        #expect(finalRecheck.lowerBound < issued.lowerBound)
        #expect(issued.lowerBound < connect.lowerBound)
    }

    @Test("foreground and account invalidation cancel tokenless authentication attempts")
    func tokenlessAuthenticatingWindowCannotSurviveAuthorityLoss() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let foreground = try declarationBody(in: source, signature: "func handleForegroundIntegrityLoss()")
        let membership = try declarationBody(in: source, signature: "func invalidateSDKMembership()")

        for body in [foreground, membership] {
            #expect(body.contains("authenticationAttemptID = nil"))
            #expect(body.contains("authenticationConnectRequestIssued"))
            #expect(body.contains("phase == .authenticating") || body.contains(".authenticating"))
        }

        #expect(foreground.contains("foreground_integrity_lost"))
        #expect(foreground.contains("invalidateInternalLifecycle("))
        #expect(foreground.contains("invalidateObservationContinuity("))
        #expect(!foreground.contains("endConnection(for:"))
        #expect(!foreground.contains("invalidateSourceAuthority("))
        #expect(!foreground.contains("markSourceAuthorityInvalidated(for:"))

        #expect(membership.contains("sdk_source_authority_lost"))
        #expect(membership.contains("phase = .failed"))
    }

    @Test("accepted prefix and inactive non-attempt states are not rewritten by scene loss")
    func foregroundLossPreservesTerminalAndLandingStates() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let foreground = try declarationBody(in: source, signature: "func handleForegroundIntegrityLoss()")

        #expect(foreground.contains(".idle"))
        #expect(foreground.contains(".failed"))
        #expect(foreground.contains(".accepted"))
    }

    private func declarationBody(in source: String, signature: String) throws -> Substring {
        guard let signatureRange = source.range(of: signature),
              let openingBrace = source[signatureRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source declaration missing: \(signature)")
            throw SourceContractError.declarationMissing
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[openingBrace...index] }
            default: break
            }
            index = source.index(after: index)
        }

        Issue.record("Unbalanced source declaration: \(signature)")
        throw SourceContractError.declarationMissing
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
        case declarationMissing
    }
}
