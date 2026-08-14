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

    @Test("SDK application callback receipts and owns admission before the first async hop")
    func sdkCallbackAdmissionPrecedesAsyncScheduling() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let connect = app.range(of: "newDriver.connect("),
              let callback = app.range(of: "onApplicationUpdate:", range: connect.lowerBound..<app.endIndex),
              let success = app.range(of: "success:", range: callback.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the official Tuya application callback closure.")
            throw SourceContractError.sectionMissing
        }
        let body = String(app[callback.lowerBound..<success.lowerBound])

        let receipt = try #require(body.range(of: "let applicationReceipt = TuyaReadOnlyApplicationReceipt.capture(for: token)"))
        let increment = try #require(body.range(of: "applicationUpdateAdmissionsInFlight += 1", range: receipt.upperBound..<body.endIndex))
        let predecessor = try #require(body.range(of: "let predecessor = self.applicationUpdateAdmissionTail", range: increment.upperBound..<body.endIndex))
        let task = try #require(body.range(of: "Task { @MainActor", range: predecessor.upperBound..<body.endIndex))
        let wait = try #require(body.range(of: "await predecessor?.value", range: task.upperBound..<body.endIndex))
        let release = try #require(body.range(of: "defer { self.applicationUpdateAdmissionsInFlight -= 1 }", range: wait.upperBound..<body.endIndex))
        let receiver = try #require(body.range(of: "receivedApplicationUpdate(", range: release.upperBound..<body.endIndex))

        #expect(receipt.lowerBound < increment.lowerBound)
        #expect(increment.lowerBound < predecessor.lowerBound)
        #expect(predecessor.lowerBound < task.lowerBound)
        #expect(task.lowerBound < wait.lowerBound)
        #expect(wait.lowerBound < release.lowerBound)
        #expect(release.lowerBound < receiver.lowerBound)
    }

    @Test("receiver consumes the opaque receipt without reminting application chronology")
    func receiverUsesPackageOwnedReceipt() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: app, from: "private func receivedApplicationUpdate(", to: "private func redactedApplicationEventDetails("))

        #expect(receiver.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(receiver.contains("receipt: receipt"))
        #expect(!receiver.contains("applicationUpdateAdmissionsInFlight += 1"))
        #expect(!receiver.contains("applicationUpdateAdmissionsInFlight -= 1"))
        #expect(!receiver.contains("TuyaReadOnlyApplicationReceipt.capture"))
    }

    @Test("package-owned horizon poll cannot overtake an already-receipted application callback")
    func packageHorizonWaitsForApplicationAdmissionDrain() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = String(watchdog)

        guard let drainGate = body.range(of: "guard self.applicationUpdateAdmissionsInFlight == 0 else {"),
              let packagePoll = body.range(of: "try await self.sessionLedger.observeCurrentConnection(for: token)") else {
            Issue.record("The package-owned horizon poll must defer while a synchronously receipted SDK application callback is still draining.")
            throw SourceContractError.sectionMissing
        }

        #expect(drainGate.lowerBound < packagePoll.lowerBound)
        #expect(body.contains("catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached"))
        #expect(body.contains("mirrorAlreadyTerminalIncompleteObservationHorizon"))
        #expect(!body.contains("markApplicationObservationTimedOut"))
    }

    @Test("application receipt owns its scalar clock and exact token inside the package")
    func applicationReceiptCannotSmuggleCallerSelectedTime() throws {
        let ledger = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift")
        let receipt = String(try section(in: ledger, from: "public struct TuyaReadOnlyApplicationReceipt", to: "public actor TuyaAuthenticatedReadOnlySessionLedger"))
        let record = String(try section(in: ledger, from: "public func recordApplicationUpdate(", to: "public func observeCurrentConnection("))

        #expect(receipt.contains("fileprivate let token: TuyaReadOnlyConnectionToken"))
        #expect(receipt.contains("fileprivate let receivedAtUptimeNanoseconds: UInt64"))
        #expect(receipt.contains("public static func capture(for token: TuyaReadOnlyConnectionToken)"))
        #expect(receipt.contains("DispatchTime.now().uptimeNanoseconds"))
        #expect(!receipt.contains("public init("))
        #expect(!receipt.contains("public static func capture(for token: TuyaReadOnlyConnectionToken, receivedAtUptimeNanoseconds:"))
        #expect(record.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(record.contains("guard receipt.token == token else"))
        #expect(record.contains("let now = receipt.receivedAtUptimeNanoseconds"))
        #expect(!record.contains("let now = try nextMonotonicObservation()"))
        #expect(record.contains("try requireContinuousAuthenticatedObservation(at: now)"))
        #expect(record.contains("try requireIncompleteObservationHorizonOpen(at: now)"))
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
