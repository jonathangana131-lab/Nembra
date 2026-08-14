import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("current callback grammar owns exact-ledger application receipt and drain before async work")
    func currentCallbackGrammarOwnsLedgerReceiptBeforeAsyncWork() throws {
        let app = try callbackChronologyRead("NembraApp/App/NembraCaptureEntrypoint.swift")
        let connection = String(try callbackChronologySection(
            in: app,
            from: "newDriver.connect(",
            to: "private func authenticated(token:"
        ))
        let callback = String(try callbackChronologySection(
            in: connection,
            from: "onApplicationUpdate: { [weak self] update in",
            to: "sourceAuthorityFailure:"
        ))

        #expect(callback.contains("self?.admitApplicationUpdateCallback(update, token: token)"))
        #expect(!callback.contains("Task { @MainActor"))

        let admission = String(try callbackChronologySection(
            in: app,
            from: "private func admitApplicationUpdateCallback",
            to: "private func receivedApplicationUpdate"
        ))
        let cut = try callbackChronologyRequired("guard !acceptanceCutIsClosed else", in: admission)
        let receipt = try callbackChronologyRequired(
            "let applicationReceipt = sessionLedger.captureApplicationReceipt(for: token)",
            in: admission,
            after: cut
        )
        let inFlight = try callbackChronologyRequired(
            "applicationUpdateAdmissionsInFlight += 1",
            in: admission,
            after: receipt
        )
        let task = try callbackChronologyRequired("Task { @MainActor", in: admission, after: inFlight)
        let release = try callbackChronologyRequired(
            "defer { self.applicationUpdateAdmissionsInFlight -= 1 }",
            in: admission,
            after: task
        )
        let receiver = try callbackChronologyRequired(
            "receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)",
            in: admission,
            after: release
        )
        #expect(cut < receipt)
        #expect(receipt < inFlight)
        #expect(inFlight < task)
        #expect(task < release)
        #expect(release < receiver)
        #expect(app.components(separatedBy: "captureApplicationReceipt(for: token)").count - 1 == 1)

        let asyncReceiver = String(try callbackChronologySection(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))
        #expect(asyncReceiver.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(asyncReceiver.contains("recordApplicationUpdate(isNonEmpty: !update.isEmpty, receipt: receipt, for: token)"))
        #expect(!asyncReceiver.contains("applicationUpdateAdmissionsInFlight += 1"))
        #expect(!asyncReceiver.contains("applicationUpdateAdmissionsInFlight -= 1"))
    }

    @Test("watchdog proves app drain then asks exact ledger for liveness receipt before actor hop")
    func watchdogOwnsLedgerLivenessReceiptBeforeActorScheduling() throws {
        let app = try callbackChronologyRead("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try callbackChronologySection(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))

        let positiveDrain = try callbackChronologyRequired(
            "self.applicationUpdateAdmissionsInFlight > 0",
            in: watchdog
        )
        let zeroFence = try callbackChronologyRequired(
            "guard self.applicationUpdateAdmissionsInFlight == 0 else {",
            in: watchdog,
            after: positiveDrain
        )
        let receipt = try callbackChronologyRequired(
            "guard let livenessReceipt = self.sessionLedger.captureLivenessReceipt(for: token) else {",
            in: watchdog,
            after: zeroFence
        )
        let mutation = try callbackChronologyRequired(
            "try await self.sessionLedger.observeCurrentConnection(receipt: livenessReceipt, for: token)",
            in: watchdog,
            after: receipt
        )
        #expect(positiveDrain < zeroFence)
        #expect(zeroFence < receipt)
        #expect(receipt < mutation)
        #expect(app.components(separatedBy: "captureLivenessReceipt(for: token)").count - 1 == 1)
    }

    @Test("package receipt authority is exact-ledger issued, one-shot, and not caller-mintable")
    func packageReceiptAuthorityIsLedgerIssuedAndOneShot() throws {
        let ledger = try callbackChronologyRead(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let applicationReceipt = String(try callbackChronologySection(
            in: ledger,
            from: "public struct TuyaReadOnlyApplicationReceipt",
            to: "public struct TuyaReadOnlyLivenessReceipt"
        ))
        let livenessReceipt = String(try callbackChronologySection(
            in: ledger,
            from: "public struct TuyaReadOnlyLivenessReceipt",
            to: "private final class TuyaReadOnlyCallbackChronologyArbiter"
        ))

        for typeBody in [applicationReceipt, livenessReceipt] {
            #expect(typeBody.contains("fileprivate let token: TuyaReadOnlyConnectionToken"))
            #expect(typeBody.contains("fileprivate let issuerID: UUID"))
            #expect(typeBody.contains("fileprivate let deliveryID: UUID"))
            #expect(typeBody.contains("fileprivate let receivedAtUptimeNanoseconds: UInt64"))
            #expect(!typeBody.contains("public init("))
            #expect(!typeBody.contains("public static func capture"))
            #expect(!typeBody.contains("public static func testingCapture"))
        }

        #expect(ledger.contains("nonisolated private let applicationReceiptIssuerID: UUID"))
        #expect(ledger.contains("nonisolated private let callbackChronologyArbiter: TuyaReadOnlyCallbackChronologyArbiter"))
        #expect(ledger.contains("private var consumedApplicationDeliveryIDs: Set<UUID>"))
        #expect(ledger.contains("private var consumedLivenessDeliveryIDs: Set<UUID>"))
        #expect(ledger.contains("public nonisolated func captureApplicationReceipt("))
        #expect(ledger.contains("public nonisolated func captureLivenessReceipt("))

        let captureApplication = String(try callbackChronologySection(
            in: ledger,
            from: "public nonisolated func captureApplicationReceipt(",
            to: "public nonisolated func captureLivenessReceipt("
        ))
        #expect(captureApplication.contains("applicationReceiptIssuerID"))
        #expect(captureApplication.contains("DispatchTime.now().uptimeNanoseconds"))
        #expect(captureApplication.contains("callbackChronologyArbiter.captureApplication"))

        let captureLiveness = String(try callbackChronologySection(
            in: ledger,
            from: "public nonisolated func captureLivenessReceipt(",
            to: "@discardableResult"
        ))
        #expect(captureLiveness.contains("applicationReceiptIssuerID"))
        #expect(captureLiveness.contains("DispatchTime.now().uptimeNanoseconds"))
        #expect(captureLiveness.contains("callbackChronologyArbiter.captureLivenessIfUnblocked"))
    }

    @Test("package arbiter prevents watchdog receipt issuance across pending application delivery")
    func packageArbiterSerializesApplicationDeliveryAgainstLivenessSampling() throws {
        let ledger = try callbackChronologyRead(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let arbiter = String(try callbackChronologySection(
            in: ledger,
            from: "private final class TuyaReadOnlyCallbackChronologyArbiter",
            to: "public actor TuyaAuthenticatedReadOnlySessionLedger"
        ))

        #expect(arbiter.contains("private var pendingApplicationByDeliveryID"))
        #expect(arbiter.contains("pendingApplicationByDeliveryID[deliveryID] = token"))
        #expect(arbiter.contains("guard !pendingApplicationByDeliveryID.values.contains(token) else"))
        #expect(arbiter.contains("pendingApplicationByDeliveryID.removeValue(forKey: receipt.deliveryID)"))
        #expect(arbiter.contains("lock.lock()"))
        #expect(arbiter.contains("lock.unlock()"))
    }

    @Test("application and liveness mutations consume exact receipt authority before evidence moves")
    func packageMutationsConsumeExactReceiptAuthority() throws {
        let ledger = try callbackChronologyRead(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let applicationMutation = String(try callbackChronologySection(
            in: ledger,
            from: "public func recordApplicationUpdate(",
            to: "public func observeCurrentConnection("
        ))
        #expect(applicationMutation.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(applicationMutation.contains("receipt.token == token"))
        #expect(applicationMutation.contains("receipt.issuerID == applicationReceiptIssuerID"))
        #expect(applicationMutation.contains("consumedApplicationDeliveryIDs.insert(receipt.deliveryID).inserted"))
        #expect(applicationMutation.contains("callbackChronologyArbiter.consumeApplication(receipt)"))
        #expect(applicationMutation.contains("let now = receipt.receivedAtUptimeNanoseconds"))
        #expect(applicationMutation.contains("try requireContinuousAuthenticatedReceipt(at: now)"))
        #expect(applicationMutation.contains("try requireIncompleteObservationHorizonOpen(at: now)"))
        #expect(!applicationMutation.contains("receivedAtUptimeNanoseconds: UInt64"))
        #expect(!applicationMutation.contains("let now = try nextMonotonicObservation()"))

        let livenessMutation = String(try callbackChronologySection(
            in: ledger,
            from: "public func observeCurrentConnection(",
            to: "func recordApplicationUpdate(isNonEmpty: Bool, for token:"
        ))
        #expect(livenessMutation.contains("receipt: TuyaReadOnlyLivenessReceipt"))
        #expect(livenessMutation.contains("receipt.token == token"))
        #expect(livenessMutation.contains("receipt.issuerID == applicationReceiptIssuerID"))
        #expect(livenessMutation.contains("consumedLivenessDeliveryIDs.insert(receipt.deliveryID).inserted"))
        #expect(livenessMutation.contains("let now = receipt.receivedAtUptimeNanoseconds"))
        #expect(livenessMutation.contains("try requireContinuousAuthenticatedReceipt(at: now)"))
        #expect(livenessMutation.contains("try requireIncompleteObservationHorizonOpen(at: now)"))
        #expect(!livenessMutation.contains("receivedAtUptimeNanoseconds: UInt64"))
        #expect(!livenessMutation.contains("let now = try nextMonotonicObservation()"))
    }

    @Test("out-of-order actor execution cannot roll accepted receipt chronology backward")
    func receiptContinuityHelperPreservesAcceptedEnvelope() throws {
        let ledger = try callbackChronologyRead(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let chronologyHelper = String(try callbackChronologySection(
            in: ledger,
            from: "private func requireContinuousAuthenticatedReceipt",
            to: "private func requireIncompleteObservationHorizonOpen"
        ))
        #expect(chronologyHelper.contains("receivedAtUptimeNanoseconds >= authenticatedAt"))
        #expect(chronologyHelper.contains("guard receivedAtUptimeNanoseconds >= latest else"))
        #expect(chronologyHelper.contains("return"))
        #expect(chronologyHelper.contains("receivedAtUptimeNanoseconds - latest <= Self.maximumContinuousObservationGapNanoseconds"))
    }
}

private func callbackChronologySection(
    in source: String,
    from start: String,
    to end: String
) throws -> Substring {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        Issue.record("Expected callback-chronology source section missing: \(start) ... \(end)")
        throw CallbackChronologySourceContractError.sectionMissing
    }
    return source[startRange.lowerBound..<endRange.lowerBound]
}

private func callbackChronologyRequired(
    _ needle: String,
    in source: String,
    after lowerBound: String.Index? = nil
) throws -> String.Index {
    let lower = lowerBound ?? source.startIndex
    guard let range = source.range(of: needle, range: lower..<source.endIndex) else {
        Issue.record("Expected callback-chronology contract missing: \(needle)")
        throw CallbackChronologySourceContractError.requiredContractMissing
    }
    return range.lowerBound
}

private func callbackChronologyRead(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum CallbackChronologySourceContractError: Error {
    case sectionMissing
    case requiredContractMissing
}
