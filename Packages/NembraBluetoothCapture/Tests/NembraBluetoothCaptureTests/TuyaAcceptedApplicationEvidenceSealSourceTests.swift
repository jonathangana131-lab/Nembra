import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application evidence export seal")
struct TuyaAcceptedApplicationEvidenceSealSourceTests {
    @Test("acceptance closes application admission and freezes a quiescent event prefix before the package sealing await")
    func acceptanceSealFreezesQuiescentExportPrefixBeforeAwait() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = String(watchdog)

        guard let noInflight = body.range(of: "guard self.applicationUpdateAdmissionsInFlight == 0"),
              let closeCut = body.range(of: "self.acceptanceCutIsClosed = true", range: noInflight.upperBound..<body.endIndex),
              let frozenPrefix = body.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", range: closeCut.upperBound..<body.endIndex),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: frozenPrefix.upperBound..<body.endIndex),
              let publishPrefix = body.range(of: "self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Canonical acceptance must close admission, freeze the quiescent app prefix before the sealing await, then publish that exact prefix after package seal succeeds.")
            throw SourceContractError.sectionMissing
        }

        #expect(noInflight.lowerBound < closeCut.lowerBound)
        #expect(closeCut.lowerBound < frozenPrefix.lowerBound)
        #expect(frozenPrefix.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < publishPrefix.lowerBound)
        #expect(!body.contains("self.sealedAcceptedEventPrefix = self.events"))
    }


    @Test("the full accepted envelope is frozen before package seal suspension and published only after seal succeeds")
    func fullAcceptedEnvelopeSharesTheImmutableSealCut() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = String(watchdog)

        guard let eventCut = body.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))"),
              let envelopeCut = body.range(of: "let acceptedExportAtCut = self.makeExport(", range: eventCut.upperBound..<body.endIndex),
              let acceptedPhase = body.range(of: "phase: .accepted", range: envelopeCut.upperBound..<body.endIndex),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: acceptedPhase.upperBound..<body.endIndex),
              let publish = body.range(of: "self.sealedAcceptedExport = acceptedExportAtCut", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Canonical acceptance must freeze the whole accepted envelope at the pre-await cut and publish it only after package seal succeeds.")
            throw SourceContractError.sectionMissing
        }

        #expect(eventCut.lowerBound < envelopeCut.lowerBound)
        #expect(envelopeCut.lowerBound < acceptedPhase.lowerBound)
        #expect(acceptedPhase.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < publish.lowerBound)
    }


    @Test("application callbacks cannot cross the acceptance cut and in-flight admissions remain owned until async ledger work finishes")
    func applicationAdmissionIsQuiescedBeforeSeal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(in: app, from: "private func receivedApplicationUpdate", to: "private func startWatchdog")
        let body = String(receive)

        guard let cutGuard = body.range(of: "guard !acceptanceCutIsClosed"),
              let increment = body.range(of: "applicationUpdateAdmissionsInFlight += 1", range: cutGuard.upperBound..<body.endIndex),
              let decrement = body.range(of: "defer { applicationUpdateAdmissionsInFlight -= 1 }", range: increment.upperBound..<body.endIndex),
              let mutation = body.range(of: "try await sessionLedger.recordApplicationUpdate", range: decrement.upperBound..<body.endIndex) else {
            Issue.record("Application evidence admission must be cut-gated and tracked across its async package mutation.")
            throw SourceContractError.sectionMissing
        }

        #expect(cutGuard.lowerBound < increment.lowerBound)
        #expect(increment.lowerBound < decrement.lowerBound)
        #expect(decrement.lowerBound < mutation.lowerBound)
        #expect(body.contains("application_update_after_acceptance_cut_ignored"))
    }

    @Test("no-application timeout cannot retire a generation while an application admission is still in flight")
    func timeoutWaitsForApplicationAdmissionQuiescence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = String(watchdog)

        guard let timeoutGate = body.range(of: "if self.applicationUpdateAdmissionsInFlight == 0,"),
              let ageGate = body.range(of: "(self.canonicalObservedAgeSeconds ?? 0) > 60", range: timeoutGate.upperBound..<body.endIndex),
              let noApplication = body.range(of: "self.applicationUpdateCount == 0", range: ageGate.upperBound..<body.endIndex),
              let terminal = body.range(of: "try await sessionLedger.markApplicationObservationTimedOut", range: noApplication.upperBound..<body.endIndex) else {
            Issue.record("The no-application terminal must require zero in-flight application admissions before it can retire the generation.")
            throw SourceContractError.sectionMissing
        }

        #expect(timeoutGate.lowerBound < ageGate.lowerBound)
        #expect(ageGate.lowerBound < noApplication.lowerBound)
        #expect(noApplication.lowerBound < terminal.lowerBound)
    }

    @Test("accepted export uses the fully frozen envelope instead of rebuilding from mutable live state")
    func acceptedExportUsesFrozenEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))
        #expect(app.contains("private var sealedAcceptedExport: Export?"))
        #expect(app.contains("private var applicationUpdateAdmissionsInFlight = 0"))
        #expect(app.contains("private var acceptanceCutIsClosed = false"))

        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        let body = String(export)

        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("guard let acceptedEnvelope = self.sealedAcceptedExport"))
        #expect(body.contains("envelope = acceptedEnvelope"))
        #expect(body.contains("envelope = makeExport(events: events, phase: phase, exportedAt: Date())"))
        #expect(!body.contains("guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix"))
    }

    @Test("starting a fresh correlation life reopens admission and clears the prior accepted export prefix")
    func freshCorrelationClearsPriorAcceptedPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")

        #expect(reset.contains("acceptanceCutIsClosed = false"))
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
        #expect(reset.contains("sealedAcceptedExport = nil"))
    }


    @Test("accepted export starts at the current physical attempt boundary")
    func acceptedExportCannotInheritOlderFailedAttemptEvents() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(in: app, from: "func startBaseline()", to: "private func beginCorrelationSeries")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let startBody = String(start)
        let watchdogBody = String(watchdog)

        guard let boundary = startBody.range(of: "captureAttemptEventStartIndex = events.count"),
              let membership = startBody.range(of: "verifySDKMembership", range: boundary.upperBound..<startBody.endIndex),
              let closeCut = watchdogBody.range(of: "self.acceptanceCutIsClosed = true"),
              let freeze = watchdogBody.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", range: closeCut.upperBound..<watchdogBody.endIndex),
              let packageSeal = watchdogBody.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: freeze.upperBound..<watchdogBody.endIndex) else {
            Issue.record("Accepted evidence must establish a fresh-attempt boundary before membership and freeze only that suffix before package seal.")
            throw SourceContractError.sectionMissing
        }

        #expect(app.contains("private var captureAttemptEventStartIndex = 0"))
        #expect(boundary.lowerBound < membership.lowerBound)
        #expect(closeCut.lowerBound < freeze.lowerBound)
        #expect(freeze.lowerBound < packageSeal.lowerBound)
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
