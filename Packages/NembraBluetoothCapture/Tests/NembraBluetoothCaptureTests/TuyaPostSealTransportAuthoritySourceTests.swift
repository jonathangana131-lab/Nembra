import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture post-seal local-BLE authority")
struct TuyaPostSealTransportAuthoritySourceTests {
    @Test("accepted artifact requires a synchronous local-BLE recheck after package seal")
    func acceptedArtifactRechecksTransportAfterSeal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let envelopeFreeze = body.range(of: "self.sealedAcceptedExport = self.makeExport(", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Could not isolate canonical package seal and complete accepted-envelope freeze.")
            throw SourceContractError.sectionMissing
        }

        let postSealAuthority = String(body[packageSeal.upperBound..<envelopeFreeze.lowerBound])

        // The watchdog's previous isLocallyConnected sample occurred before actor suspension.
        // A physical disconnect can become observable while sealAcceptedObservation is suspended.
        // Before presenting accepted UI, the app must synchronously re-read the official SDK's
        // same-device local-BLE state. This recheck is presentation/source authority only; the
        // package token is already sealed and must not receive a manufactured second terminal.
        #expect(postSealAuthority.contains("driver.isLocallyConnected(uuid: self.tuyaUUID)"))
        #expect(postSealAuthority.contains("self.sdkLocalBLEOnline"))
        #expect(postSealAuthority.contains("self.phase = .failed"))
        #expect(postSealAuthority.contains("return"))

        #expect(!postSealAuthority.contains("sessionLedger.endConnection"))
        #expect(!postSealAuthority.contains("markAuthenticationFailed"))
        #expect(!postSealAuthority.contains("markSourceAuthorityInvalidated"))
        #expect(!postSealAuthority.contains("markObservationContinuityInvalidated"))
        #expect(!postSealAuthority.contains("markInternalLifecycleFailure"))
    }

    @Test("post-seal transport recheck happens before accepted phase is presented")
    func transportRecheckPrecedesAcceptedPresentation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let transportRecheck = body.range(of: "driver.isLocallyConnected(uuid: self.tuyaUUID)", range: packageSeal.upperBound..<body.endIndex),
              let acceptedPhase = body.range(of: "self.phase = .accepted", range: transportRecheck.upperBound..<body.endIndex) else {
            Issue.record("Expected package seal -> transport recheck -> accepted presentation ordering is missing.")
            throw SourceContractError.sectionMissing
        }

        #expect(packageSeal.lowerBound < transportRecheck.lowerBound)
        #expect(transportRecheck.lowerBound < acceptedPhase.lowerBound)

        let betweenSealAndRecheck = body[packageSeal.upperBound..<transportRecheck.lowerBound]
        #expect(!betweenSealAndRecheck.contains("await "), Comment(rawValue: "Do not introduce another suspension before post-seal transport authority is re-sampled."))
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
