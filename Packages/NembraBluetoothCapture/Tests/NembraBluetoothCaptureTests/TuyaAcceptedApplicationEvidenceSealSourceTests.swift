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
              let frozenPrefix = body.range(of: "let acceptedEventPrefixAtCut = self.events", range: closeCut.upperBound..<body.endIndex),
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

    @Test("accepted export fails closed onto the frozen prefix instead of the mutable live event log")
    func acceptedExportUsesFrozenEventPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))
        #expect(app.contains("private var applicationUpdateAdmissionsInFlight = 0"))
        #expect(app.contains("private var acceptanceCutIsClosed = false"))

        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        let body = String(export)

        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix"))
        #expect(body.contains("sealedAcceptedEventPrefix = acceptedEventPrefix"))
        #expect(body.contains("events: sealedAcceptedEventPrefix"))
        #expect(!body.contains("events: events\n"))
    }

    @Test("starting a fresh correlation life reopens admission and clears the prior accepted export prefix")
    func freshCorrelationClearsPriorAcceptedPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")

        #expect(reset.contains("acceptanceCutIsClosed = false"))
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
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
