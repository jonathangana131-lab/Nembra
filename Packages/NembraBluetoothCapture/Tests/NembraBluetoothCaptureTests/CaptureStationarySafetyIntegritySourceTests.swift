import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture stationary safety and accepted-artifact source contract")
struct CaptureStationarySafetyIntegritySourceTests {
    @Test("every begin and retry passes through a fresh operator safety confirmation")
    func freshSafetyConfirmationGatesEveryAttempt() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: app,
            from: "private final class SecureLinkController:",
            to: "private final class OfficialTuyaAccountAuthorizer:"
        ))
        let attestation = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/StationaryCaptureOperatorAttestation.swift"
        )
        let view = String(try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        ))

        #expect(view.contains("@State private var stationarySafetyLaunch: StationarySafetyLaunch?"))
        #expect(view.contains(".sheet(item: $stationarySafetyLaunch) { launch in"))
        #expect(view.contains("stationarySafetyLaunch = .begin"))
        #expect(view.contains("stationarySafetyLaunch = .retry"))
        #expect(view.contains("case .begin:\n                    test.recordFreshOperatorAttestationAndBegin()"))
        #expect(view.contains("case .retry:\n                    test.recordFreshOperatorAttestationAndRetry()"))
        #expect(occurrences(of: "test.recordFreshOperatorAttestationAndBegin()", in: view) == 1)
        #expect(occurrences(of: "test.recordFreshOperatorAttestationAndRetry()", in: view) == 1)
        #expect(!view.contains("test.startBaseline()"))
        #expect(!view.contains("test.retry()"))
        #expect(view.contains("nembra.capture.stationary-safety-review"))
        #expect(view.contains("nembra.capture.stationary-safety-confirm"))

        #expect(attestation.contains("public struct StationaryCaptureOperatorAttestation: Codable, Equatable, Sendable"))
        #expect(attestation.contains("public let attemptID: UUID"))
        #expect(attestation.contains("public let receivedAt: Date"))
        #expect(attestation.contains("public let receivedAtUptimeNanoseconds: UInt64"))
        #expect(controller.contains("private var operatorSafetyAttestation: StationaryCaptureOperatorAttestation?"))
        #expect(controller.contains("private var operatorSafetyAttemptID: UUID?"))
        #expect(controller.contains("private var operatorSafetyAttemptStartedAtUptimeNanoseconds: UInt64?"))
        let recorder = String(try section(
            in: controller,
            from: "private func recordFreshOperatorAttestationFromExplicitConfirmation() -> Bool",
            to: "private func beginBaselineAfterCurrentOperatorAttestation()"
        ))
        let baseline = String(try section(
            in: controller,
            from: "private func beginBaselineAfterCurrentOperatorAttestation()",
            to: "private func beginCorrelationSeries()"
        ))
        #expect(recorder.contains("StationaryCaptureOperatorAttestation("))
        #expect(recorder.contains("declarations: .init(\n                stationary: true,\n                poweredOff: true,\n                chargerDisconnected: true,\n                noRiding: true,\n                controlsUntouched: true"))
        #expect(!baseline.contains("StationaryCaptureOperatorAttestation("))
        #expect(baseline.contains("guard operatorSafetyAttestationIsCurrent else"))
        #expect(controller.contains("authority\": \"operator-declared-not-sensed"))
        #expect(controller.contains("var operatorSafetyAttestationIsCurrent: Bool"))
        #expect(controller.contains("StationaryCaptureOperatorAttestationGate.verdict("))
        #expect(controller.contains("== .readyForOperatorDeclaredStationaryCapture"))
        #expect(controller.contains("guard operatorSafetyAttestationIsCurrent else"))
        #expect(controller.contains("func recordFreshOperatorAttestationAndBegin()"))
        #expect(controller.contains("func recordFreshOperatorAttestationAndRetry()"))
        #expect(!controller.contains("func startBaseline()"))
        #expect(!controller.contains("func retry()"))
        #expect(controller.contains("if phase == .failed {\n                operatorSafetyAttemptID = nil"))
        #expect(!controller.contains("if phase == .failed {\n                operatorSafetyAttestation = nil"))
        #expect(controller.contains("operatorSafetyAttemptID = nil"))
        #expect(controller.contains("operatorSafetyAttemptStartedAtUptimeNanoseconds = nil"))
    }

    @Test("accepted COMPLETE is integrity-gated and sharing reuses the exact sealed bytes")
    func completeRequiresVerifiedExactBytesAndShareIsRecoverable() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: app,
            from: "private final class SecureLinkController:",
            to: "private final class OfficialTuyaAccountAuthorizer:"
        ))
        let view = String(try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        ))

        #expect(controller.contains("let operatorSafetyAttestation: StationaryCaptureOperatorAttestation?"))
        #expect(controller.contains("schemaVersion: 13"))
        #expect(controller.contains("operatorSafetyAttestation: operatorSafetyAttestation"))
        #expect(controller.contains("private var sealedAcceptedArtifact: ExactByteArtifactSeal?"))
        #expect(controller.contains("let newSeal = ExactByteArtifactSeal(sealing: exactBytes)"))
        #expect(controller.contains("let exactBytes = try artifactSeal.verifiedBytes()"))
        #expect(controller.contains("guard artifactSeal.verifies(exactBytes) else"))
        #expect(controller.contains("verifiedCanonicalValue("))
        #expect(controller.contains("try validateAcceptedExport(decoded, exactBytes: exactBytes)"))
        #expect(controller.contains("envelope.schemaVersion == 13"))
        #expect(controller.contains("envelope.phase == .accepted"))
        #expect(controller.contains("applicationEvents.count == envelope.applicationUpdateCount"))
        #expect(controller.contains("event.sourceReceivedAtUptimeNanoseconds"))
        #expect(controller.contains("applicationEvents.last?.sourceReceivedAtUptimeNanoseconds == latestPayload"))
        #expect(controller.contains("correlation.windows.count == 4"))
        #expect(controller.contains("correlation.observationSnapshots.map(\\.windowSequence) == [1, 2, 3, 4]"))
        #expect(controller.contains("correlation.repeatableCandidateIDs == [selectedPeripheralID]"))
        #expect(controller.contains("attestation.receivedAtUptimeNanoseconds <= correlation.windows[0].startedAtUptimeNanoseconds"))
        #expect(controller.contains("sealedAcceptedForbiddenSecrets = self.exactKnownSecretsForbiddenFromExport"))
        #expect(controller.contains("secretEncoder.outputFormatting = [.withoutEscapingSlashes]"))
        #expect(controller.contains("knownSecretsRedacted: true"))
        #expect(controller.contains("exportData = exactBytes"))
        #expect(controller.contains("acceptedArtifactSHA256 = artifactSeal.sha256"))
        #expect(controller.contains("acceptedArtifactByteCount = artifactSeal.byteCount"))
        #expect(controller.contains("var acceptedArtifactIntegrityVerified: Bool"))

        let completion = String(try section(
            in: view,
            from: "private var completionPanel: some View",
            to: "private var sdkAuthorizationPanel: some View"
        ))
        let integrityGate = try #require(completion.range(of: "test.acceptedArtifactIntegrityVerified"))
        let complete = try #require(completion.range(of: "Text(\"CAPTURE COMPLETE\")", range: integrityGate.upperBound..<completion.endIndex))
        let share = try #require(completion.range(of: "Label(\"Share Capture\", systemImage: \"square.and.arrow.up\")", range: complete.upperBound..<completion.endIndex))
        let recovery = try #require(completion.range(
            of: "If sharing is cancelled or fails, tap Share Capture again. The same verified bytes remain sealed.",
            range: share.upperBound..<completion.endIndex
        ))

        #expect(integrityGate.lowerBound < complete.lowerBound)
        #expect(complete.lowerBound < share.lowerBound)
        #expect(share.lowerBound < recovery.lowerBound)
        #expect(completion.contains("Label(\"Integrity verified\", systemImage: \"checkmark.shield.fill\")"))
        #expect(completion.contains("SHA-256"))
        #expect(completion.contains("Retry sealed Capture preparation"))
        #expect(completion.contains("Retries encoding only the already sealed immutable Capture artifact."))
        #expect(view.contains("case .accepted: return test.acceptedArtifactIntegrityVerified ? \"Capture complete\" : \"Capture sealed\""))
    }

    @Test("safety surface exposes stop conditions and never claims charger sensing")
    func stopConditionsRemainVisibleAndPhysicalTruthIsOperatorDeclared() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let attestation = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/StationaryCaptureOperatorAttestation.swift"
        )
        let sheet = String(try section(
            in: app,
            from: "struct StationarySafetyConfirmationSheet: View",
            to: "private struct SecureTransfer: Transferable"
        ))
        let secureLink = String(try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "struct StationarySafetyConfirmationSheet: View"
        ))

        #expect(sheet.contains("Confirm these conditions for this attempt only."))
        #expect(sheet.contains("let wording = StationaryCaptureOperatorAttestation.Wording.current"))
        #expect(sheet.contains("safetyRow(wording.stationaryStatement, symbol: \"scooter\")"))
        #expect(sheet.contains("safetyRow(wording.poweredOffStatement, symbol: \"power\")"))
        #expect(sheet.contains("safetyRow(wording.chargerDisconnectedStatement, symbol: \"powerplug\")"))
        #expect(sheet.contains("safetyRow(wording.noRidingStatement, symbol: \"figure.stand\")"))
        #expect(sheet.contains("safetyRow(wording.controlsUntouchedStatement, symbol: \"hand.raised.fill\")"))
        #expect(sheet.contains("Keep Capture open in the foreground for the whole attempt."))
        #expect(sheet.contains("Capture cannot sense or verify the charger or these physical conditions."))
        #expect(sheet.contains("operator declaration, never as scooter telemetry"))
        #expect(attestation.contains("stationaryStatement: \"The scooter is stationary.\""))
        #expect(attestation.contains("poweredOffStatement: \"The scooter is powered OFF.\""))
        #expect(attestation.contains("chargerDisconnectedStatement: \"The charger is disconnected.\""))
        #expect(attestation.contains("noRidingStatement: \"No one will ride the scooter during this capture.\""))
        #expect(attestation.contains("controlsUntouchedStatement: \"No one will touch the scooter controls during this capture.\""))
        #expect(attestation.contains("It is not sensor evidence, scooter telemetry,"))

        #expect(secureLink.contains("private var stopConditionNotice: some View"))
        #expect(secureLink.contains("Stop if the scooter moves, the charger is connected, any control changes, account/build authority changes, or Capture leaves the foreground."))
        #expect(secureLink.contains("Button(\"Stop this attempt\")"))
        #expect(occurrences(of: "stopConditionNotice", in: secureLink) >= 3)

        // Charger state is a physical operator declaration. Never promote it into sensed proof.
        #expect(!app.contains("chargerDisconnectedVerified"))
        #expect(!app.contains("chargerStateVerified"))
        #expect(!app.contains("chargerTelemetry"))
        #expect(!app.contains("Capture verified the charger"))
        #expect(!app.contains("Capture detected the charger"))
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var remainder = haystack[...]
        while let range = remainder.range(of: needle) {
            count += 1
            remainder = remainder[range.upperBound...]
        }
        return count
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
