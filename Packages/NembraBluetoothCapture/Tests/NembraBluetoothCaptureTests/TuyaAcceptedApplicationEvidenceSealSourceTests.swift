import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application evidence export seal")
struct TuyaAcceptedApplicationEvidenceSealSourceTests {
    @Test("acceptance closes application admission and freezes a quiescent event prefix before package seal")
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

    @Test("SmartLife callback asks the exact ledger for a receipt before the first new task")
    func sdkCallbackReceiptPrecedesAsyncScheduling() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let connect = app.range(of: "newDriver.connect("),
              let callback = app.range(of: "onApplicationUpdate:", range: connect.lowerBound..<app.endIndex),
              let success = app.range(of: "success:", range: callback.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the official Tuya application callback closure.")
            throw SourceContractError.sectionMissing
        }
        let body = String(app[callback.lowerBound..<success.lowerBound])

        let receipt = try #require(body.range(of: "self.sessionLedger.captureApplicationReceipt("))
        let increment = try #require(body.range(of: "applicationUpdateAdmissionsInFlight += 1", range: receipt.upperBound..<body.endIndex))
        let predecessor = try #require(body.range(of: "let predecessor = self.applicationUpdateAdmissionTail", range: increment.upperBound..<body.endIndex))
        let task = try #require(body.range(of: "Task { @MainActor", range: predecessor.upperBound..<body.endIndex))
        let packageRelease = try #require(body.range(of: "defer { ledger.releaseApplicationReceipt(applicationReceipt) }", range: task.upperBound..<body.endIndex))
        let localRelease = try #require(body.range(of: "defer { self.applicationUpdateAdmissionsInFlight -= 1 }", range: packageRelease.upperBound..<body.endIndex))
        let receiver = try #require(body.range(of: "receivedApplicationUpdate(", range: localRelease.upperBound..<body.endIndex))

        #expect(receipt.lowerBound < increment.lowerBound)
        #expect(increment.lowerBound < predecessor.lowerBound)
        #expect(predecessor.lowerBound < task.lowerBound)
        #expect(task.lowerBound < packageRelease.lowerBound)
        #expect(packageRelease.lowerBound < localRelease.lowerBound)
        #expect(localRelease.lowerBound < receiver.lowerBound)
        #expect(!body.contains("TuyaReadOnlyApplicationReceipt.capture"))
    }

    @Test("receiver consumes the exact-ledger receipt without reminting delivery chronology")
    func receiverUsesLedgerReceipt() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: app, from: "private func receivedApplicationUpdate(", to: "private func redactedApplicationEventDetails("))

        #expect(receiver.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(receiver.contains("receipt: receipt"))
        #expect(!receiver.contains("captureApplicationReceipt("))
        #expect(!receiver.contains("applicationUpdateAdmissionsInFlight += 1"))
    }

    @Test("watchdog liveness is package-arbitrated and receipted before its actor mutation")
    func packageArbitratesLivenessAgainstPendingApplicationDelivery() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss"))

        let localDrain = try #require(watchdog.range(of: "guard self.applicationUpdateAdmissionsInFlight == 0 else {"))
        let directBLE = try #require(watchdog.range(of: "driver.isLocallyConnected(uuid: self.tuyaUUID)", range: localDrain.upperBound..<watchdog.endIndex))
        let packageReceipt = try #require(watchdog.range(of: "captureLivenessReceipt(for: token)", range: directBLE.upperBound..<watchdog.endIndex))
        let pendingCatch = try #require(watchdog.range(of: "MutationError.applicationAdmissionPending", range: packageReceipt.upperBound..<watchdog.endIndex))
        let ledgerMutation = try #require(watchdog.range(of: "self.sessionLedger.observeCurrentConnection(", range: pendingCatch.upperBound..<watchdog.endIndex))
        let receiptArgument = try #require(watchdog.range(of: "receipt: livenessReceipt", range: ledgerMutation.upperBound..<watchdog.endIndex))

        #expect(localDrain.lowerBound < directBLE.lowerBound)
        #expect(directBLE.lowerBound < packageReceipt.lowerBound)
        #expect(packageReceipt.lowerBound < pendingCatch.lowerBound)
        #expect(pendingCatch.lowerBound < ledgerMutation.lowerBound)
        #expect(ledgerMutation.lowerBound < receiptArgument.lowerBound)
        #expect(!watchdog.contains("sessionLedger.observeCurrentConnection(for: token)"))
    }

    @Test("receipt authority is exact-ledger one-shot and has no public scalar/static mint surface")
    func packageOwnsReceiptIssuerReplayAndClockDomain() throws {
        let ledger = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift")
        let applicationReceipt = String(try section(in: ledger, from: "public struct TuyaReadOnlyApplicationReceipt", to: "public struct TuyaReadOnlyLivenessReceipt"))

        #expect(!applicationReceipt.contains("public init("))
        #expect(!applicationReceipt.contains("public static func capture"))
        #expect(applicationReceipt.contains("fileprivate let issuerID: UUID"))
        #expect(applicationReceipt.contains("fileprivate let deliverySequence: UInt64"))
        #expect(applicationReceipt.contains("fileprivate let receivedAtUptimeNanoseconds: UInt64"))

        #expect(ledger.contains("nonisolated private let receiptAuthority: ReceiptAuthority"))
        #expect(ledger.contains("self.receiptAuthority = ReceiptAuthority(nowUptimeNanoseconds: clock)"))
        #expect(ledger.contains("self.receiptAuthority = ReceiptAuthority(nowUptimeNanoseconds: nowUptimeNanoseconds)"))
        #expect(ledger.contains("public nonisolated func captureApplicationReceipt("))
        #expect(ledger.contains("public nonisolated func captureLivenessReceipt("))
        #expect(ledger.contains("private let issuerID = UUID()"))
        #expect(ledger.contains("private var nextDeliverySequence: UInt64 = 0"))
        #expect(ledger.contains("pendingApplicationSequences.remove(receipt.deliverySequence) != nil"))
        #expect(ledger.contains("guard pendingApplicationSequences.isEmpty else"))
        #expect(ledger.contains("throw MutationError.applicationAdmissionPending"))
        #expect(ledger.contains("throw MutationError.observationAdmissionInvalidOrConsumed"))
        #expect(!ledger.contains("public func observeCurrentConnection(for token:"))
    }

    @Test("accepted export consumes the frozen whole envelope instead of mutable controller state")
    func acceptedExportUsesFrozenWholeEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))
        #expect(app.contains("private var sealedAcceptedExport: Export?"))

        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        let body = String(export)
        guard let acceptedBranch = body.range(of: "if phase == .accepted"),
              let sealedGuard = body.range(of: "guard let sealedAcceptedExport", range: acceptedBranch.upperBound..<body.endIndex),
              let sealedUse = body.range(of: "envelope = sealedAcceptedExport", range: sealedGuard.upperBound..<body.endIndex),
              let mutableElse = body.range(of: "} else {", range: sealedUse.upperBound..<body.endIndex),
              let mutableBuild = body.range(of: "envelope = makeExport(", range: mutableElse.upperBound..<body.endIndex) else {
            Issue.record("Accepted Prepare must consume the immutable accepted envelope; only non-accepted diagnostics may rebuild mutable state.")
            throw SourceContractError.sectionMissing
        }
        #expect(acceptedBranch.lowerBound < sealedGuard.lowerBound)
        #expect(sealedGuard.lowerBound < sealedUse.lowerBound)
        #expect(sealedUse.lowerBound < mutableElse.lowerBound)
        #expect(mutableElse.lowerBound < mutableBuild.lowerBound)
        #expect(!body[acceptedBranch.lowerBound..<mutableElse.lowerBound].contains("makeExport("))
    }

    @Test("fresh correlation reopens the app cut without manufacturing package receipt quiescence")
    func freshCorrelationPreservesControllerLifetimeDrain() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")
        #expect(reset.contains("acceptanceCutIsClosed = false"))
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
        #expect(!reset.contains("applicationUpdateAdmissionsInFlight = 0"))
    }

    @Test("accepted export starts at the current physical attempt boundary")
    func acceptedExportCannotInheritOlderAttemptEvents() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = String(try section(in: app, from: "func startBaseline()", to: "private func beginCorrelationSeries"))
        let watchdog = String(try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss"))
        let boundary = try #require(start.range(of: "captureAttemptEventStartIndex = events.count"))
        let membership = try #require(start.range(of: "verifySDKMembership", range: boundary.upperBound..<start.endIndex))
        let closeCut = try #require(watchdog.range(of: "self.acceptanceCutIsClosed = true"))
        let freeze = try #require(watchdog.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", range: closeCut.upperBound..<watchdog.endIndex))
        let seal = try #require(watchdog.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: freeze.upperBound..<watchdog.endIndex))
        #expect(boundary.lowerBound < membership.lowerBound)
        #expect(closeCut.lowerBound < freeze.lowerBound)
        #expect(freeze.lowerBound < seal.lowerBound)
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

    private enum SourceContractError: Error { case sectionMissing }
}
