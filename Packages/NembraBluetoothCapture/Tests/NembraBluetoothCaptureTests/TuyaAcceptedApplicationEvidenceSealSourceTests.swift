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

    @Test("SDK application callback enters admission synchronously before any new MainActor task can reorder it")
    func sdkCallbackAdmissionPrecedesAsyncScheduling() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let connect = app.range(of: "newDriver.connect("),
              let callback = app.range(of: "onApplicationUpdate:", range: connect.lowerBound..<app.endIndex),
              let success = app.range(of: "success:", range: callback.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the official Tuya application callback closure.")
            throw SourceContractError.sectionMissing
        }
        let body = String(app[callback.lowerBound..<success.lowerBound])

        #expect(body.contains("admitApplicationUpdateCallback(update, token: token)"),
                Comment(rawValue: "A callback already delivered by the official SDK must synchronously cross Nembra's admission boundary before control returns to the MainActor scheduler."))
        #expect(!body.contains("Task { @MainActor"),
                Comment(rawValue: "Spawning a new task before admission lets the watchdog overtake an already-delivered callback at the package-owned 60-second horizon."))
    }

    @Test("application admission owns the in-flight drain before asynchronous ledger work begins")
    func applicationAdmissionIsOwnedBeforeAsyncLedgerWork() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let admission = try section(in: app, from: "private func admitApplicationUpdateCallback", to: "private func receivedApplicationUpdate")
        let body = String(admission)

        guard let cutGuard = body.range(of: "guard !acceptanceCutIsClosed"),
              let increment = body.range(of: "applicationUpdateAdmissionsInFlight += 1", range: cutGuard.upperBound..<body.endIndex),
              let task = body.range(of: "Task { @MainActor", range: increment.upperBound..<body.endIndex),
              let decrement = body.range(of: "applicationUpdateAdmissionsInFlight -= 1", range: task.upperBound..<body.endIndex),
              let receiver = body.range(of: "receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)", range: task.upperBound..<body.endIndex) else {
            Issue.record("Application callback admission must synchronously own the drain before scheduling its asynchronous package mutation.")
            throw SourceContractError.sectionMissing
        }

        #expect(cutGuard.lowerBound < increment.lowerBound)
        #expect(increment.lowerBound < task.lowerBound)
        #expect(task.lowerBound < receiver.lowerBound)
        #expect(task.lowerBound < decrement.lowerBound)
    }

    @Test("package-owned horizon poll cannot overtake an already-admitted application callback")
    func packageHorizonWaitsForApplicationAdmissionDrain() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = String(watchdog)

        guard let drainGate = body.range(of: "applicationUpdateAdmissionsInFlight > 0"),
              let packagePoll = body.range(of: "try await self.sessionLedger.observeCurrentConnection(for: token)") else {
            Issue.record("The package-owned horizon poll must defer while a synchronously admitted SDK application callback is still draining.")
            throw SourceContractError.sectionMissing
        }

        #expect(drainGate.lowerBound < packagePoll.lowerBound)
        #expect(body.contains("catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached"))
        #expect(body.contains("mirrorAlreadyTerminalIncompleteObservationHorizon"))
        #expect(!body.contains("markApplicationObservationTimedOut"),
                Comment(rawValue: "The app must not recreate a second timeout terminal now that the package owns the bounded incomplete-observation horizon."))
    }

    @Test("accepted export consumes the frozen whole envelope instead of reconstructing from mutable controller state")
    func acceptedExportUsesFrozenWholeEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))
        #expect(app.contains("private var sealedAcceptedExport: Export?"))
        #expect(app.contains("private var applicationUpdateAdmissionsInFlight = 0"))
        #expect(app.contains("private var acceptanceCutIsClosed = false"))

        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        let body = String(export)

        guard let acceptedBranch = body.range(of: "if phase == .accepted"),
              let sealedGuard = body.range(of: "guard let sealedAcceptedExport", range: acceptedBranch.upperBound..<body.endIndex),
              let sealedUse = body.range(of: "envelope = sealedAcceptedExport", range: sealedGuard.upperBound..<body.endIndex),
              let mutableElse = body.range(of: "} else {", range: sealedUse.upperBound..<body.endIndex),
              let mutableBuild = body.range(of: "envelope = makeExport(", range: mutableElse.upperBound..<body.endIndex) else {
            Issue.record("Accepted Prepare must consume the immutable whole accepted envelope; only non-accepted diagnostics may rebuild from mutable controller state.")
            throw SourceContractError.sectionMissing
        }

        #expect(acceptedBranch.lowerBound < sealedGuard.lowerBound)
        #expect(sealedGuard.lowerBound < sealedUse.lowerBound)
        #expect(sealedUse.lowerBound < mutableElse.lowerBound)
        #expect(mutableElse.lowerBound < mutableBuild.lowerBound)

        let acceptedSlice = body[acceptedBranch.lowerBound..<mutableElse.lowerBound]
        #expect(!acceptedSlice.contains("makeExport("))
        #expect(!acceptedSlice.contains("events: events"))
    }

    @Test("starting a fresh correlation life reopens admission and clears the prior accepted export prefix")
    func freshCorrelationClearsPriorAcceptedPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")

        #expect(reset.contains("acceptanceCutIsClosed = false"))
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
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
