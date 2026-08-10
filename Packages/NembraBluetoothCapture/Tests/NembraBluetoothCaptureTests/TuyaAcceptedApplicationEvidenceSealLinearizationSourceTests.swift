import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application evidence seal linearization")
struct TuyaAcceptedApplicationEvidenceSealLinearizationSourceTests {
    @Test("controller owns explicit application-admission quiescence and acceptance-cut state")
    func controllerHasApplicationAdmissionFence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )
        let body = String(controller)

        #expect(body.contains("private var applicationUpdateAdmissionsInFlight = 0"))
        #expect(body.contains("private var acceptanceCutIsClosed = false"))
    }

    @Test("application update is fenced before package admission and remains in flight through app-event append")
    func applicationMutationSpansPackageAwaitAndAppEventAppend() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let update = try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func startWatchdog"
        )
        let body = String(update)

        guard let cutGuard = body.range(of: "guard !acceptanceCutIsClosed else"),
              let mutationBegin = body.range(of: "applicationUpdateAdmissionsInFlight += 1"),
              let mutationEnd = body.range(of: "defer { applicationUpdateAdmissionsInFlight -= 1 }"),
              let packageMutation = body.range(of: "try await sessionLedger.recordApplicationUpdate"),
              let acceptedEvent = body.range(of: "log(\"tuya_application_update\"") else {
            Issue.record("Application updates must be fenced and counted across the package actor hop through the accepted app-event append.")
            throw SourceContractError.sectionMissing
        }

        #expect(cutGuard.lowerBound < mutationBegin.lowerBound)
        #expect(mutationBegin.lowerBound < mutationEnd.lowerBound)
        #expect(mutationEnd.lowerBound < packageMutation.lowerBound)
        #expect(packageMutation.lowerBound < acceptedEvent.lowerBound)
        #expect(body.contains("application_update_after_acceptance_cut_ignored"))
    }

    @Test("watchdog freezes one quiescent event prefix before package seal suspension")
    func acceptedPrefixCutoffPrecedesPackageSealSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let noMutationGate = body.range(of: "guard self.applicationUpdateAdmissionsInFlight == 0 else"),
              let closeAdmission = body.range(of: "self.acceptanceCutIsClosed = true", range: noMutationGate.upperBound..<body.endIndex),
              let frozenCandidate = body.range(of: "let acceptedEventPrefixAtCut = self.events", range: closeAdmission.upperBound..<body.endIndex),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: frozenCandidate.upperBound..<body.endIndex),
              let publishFrozen = body.range(of: "self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Acceptance must drain in-flight app mutations, close admission, freeze the prefix synchronously, then await package seal and publish only that frozen prefix on success.")
            throw SourceContractError.sectionMissing
        }

        #expect(noMutationGate.lowerBound < closeAdmission.lowerBound)
        #expect(closeAdmission.lowerBound < frozenCandidate.lowerBound)
        #expect(frozenCandidate.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < publishFrozen.lowerBound)
    }

    @Test("application timeout also waits for app-side admission quiescence")
    func applicationTimeoutCannotRaceAnAdmittedUpdate() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let quiescence = body.range(of: "if self.applicationUpdateAdmissionsInFlight == 0,"),
              let timeout = body.range(of: "try await sessionLedger.markApplicationObservationTimedOut(for: token)", range: quiescence.upperBound..<body.endIndex) else {
            Issue.record("The no-application terminal must not race an already-admitted application update.")
            throw SourceContractError.sectionMissing
        }
        #expect(quiescence.lowerBound < timeout.lowerBound)
    }

    @Test("fresh discovery clears the prior acceptance cut before a new physical attempt")
    func freshDiscoveryResetsAcceptanceCut() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly",
            to: "private func failLocally"
        )
        let body = String(reset)

        guard let reopen = body.range(of: "acceptanceCutIsClosed = false"),
              let clearPrefix = body.range(of: "sealedAcceptedEventPrefix = nil") else {
            Issue.record("A fresh OFF1 attempt must reopen application admission and clear the prior immutable accepted prefix.")
            throw SourceContractError.sectionMissing
        }
        #expect(reopen.lowerBound < clearPrefix.lowerBound)
    }

    @Test("post-seal mutable event snapshot remains forbidden")
    func packageSealCannotBeFollowedByMutableEventsCopy() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        #expect(!body.contains("self.sealedAcceptedEventPrefix = self.events"), Comment(rawValue: "Copying mutable app events after the package seal await reopens the actor-interleaving race."))
        #expect(body.contains("self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut"))
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
