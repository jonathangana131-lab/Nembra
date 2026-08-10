import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture final field authority")
struct TuyaFieldFinalAuthoritySourceTests {
    @Test("canonical preflight verdict is the sole product acceptance authority")
    func canonicalVerdictOwnsAcceptance() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for: ledgerSnapshot)"))
        #expect(!source.contains("var passed: Bool"))
        #expect(!source.contains("authoritativePreflightReady"))

        guard let seal = source.range(of: "sessionLedger.sealAcceptedObservation(for: token)"),
              let accepted = source.range(of: "phase = .accepted", range: seal.lowerBound..<source.endIndex) else {
            Issue.record("Canonical ready prefix must be sealed before UI acceptance.")
            return
        }
        #expect(seal.lowerBound < accepted.lowerBound)
    }

    @Test("OFF scan is mechanically downstream of current SDK account and exact membership authority")
    func scanCannotStartFromUIStateAlone() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(in: source, from: "func startBaseline()", to: "private func beginBaselineScan()")
        let begin = try section(in: source, from: "private func beginBaselineScan()", to: "func startNextCorrelationWindow()")

        #expect(start.contains("guard privateConfig, sdkAccountLoggedIn"))
        #expect(start.contains("verifySDKMembership"))
        #expect(start.contains("beginBaselineScan()"))
        #expect(begin.contains("sdkAccountLoggedIn"))
        #expect(begin.contains("sdkDeviceMembershipVerified"))
        #expect(begin.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        #expect(begin.contains("startCurrentCorrelationWindow"))
    }

    @Test("only fresh repeated correlation plus explicit confirmation can authorize a local candidate")
    func descriptiveRadioHintsCannotAuthorizeTarget() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("var likely: Bool { freshlyCorrelated }"))
        #expect(source.contains("historicalCapturePeripheral"))
        #expect(source.contains("matches C7D09A22 capture-local UUID descriptive"))
        #expect(source.contains("case let .singleRepeatableCandidate(id):"))
        #expect(source.contains("func confirmCorrelatedTarget"))
        #expect(source.contains("operator-confirmed-fresh-power-cycle-correlation"))
        #expect(!source.contains("var likely: Bool { knownID }"))
        #expect(!source.contains("accepted-prior-physical-corebluetooth-uuid"))
        #expect(!source.contains("fd50 && tuyaCompany"))
    }

    @Test("login success re-reads SDK authority and account errors redact the submitted identifier")
    func sdkAccountAuthorityIsNotCallerMinted() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = try section(
            in: source,
            from: "private final class OfficialTuyaAccountAuthorizer",
            to: "private struct SecureLinkView"
        )
        let success = try section(
            in: String(authorizer),
            from: "private func finishLoginSuccess()",
            to: "private func finishLoginFailure"
        )

        #expect(success.contains("loggedIn = OfficialTuyaFactory.accountLoggedIn"))
        #expect(!success.contains("loggedIn = true"))
        #expect(authorizer.contains("redactedError"))
        #expect(authorizer.contains("<redacted-account>"))
        #expect(!authorizer.contains("Tuya SDK login failed: \\(error?.localizedDescription"))
        #expect(!authorizer.contains("Tuya could not send the verification code: \\(error?.localizedDescription"))
    }

    @Test("terminal observation facts remain distinct and accepted callbacks are frozen")
    func terminalAPIsAreConsumedByTheFieldController() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("sessionLedger.markObservationContinuityInvalidated(for: token)"))
        #expect(source.contains("sessionLedger.markApplicationObservationTimedOut(for: token)"))
        #expect(source.contains("sessionLedger.sealAcceptedObservation(for: token)"))
        #expect(source.contains("sessionLedger.endConnection(for: token)"))
        #expect(source.contains("recordObservedTransportLoss(token: token)"))
        #expect(source.contains("maximumObservationPollGapNanoseconds"))
    }

    @Test("SDK application observations are structured truth, not fabricated raw transport bytes")
    func applicationEvidenceDoesNotPretendToBeFD50Bytes() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("recordApplicationUpdate(isNonEmpty:"))
        #expect(!source.contains("recordApplicationPayload("))
        #expect(source.contains("rawFD50BytesCaptured: false"))
        #expect(source.contains("dpQueriesSent: false"))
        #expect(source.contains("dpCommandsSent: false"))
        #expect(!source.contains("central.connect("))
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
