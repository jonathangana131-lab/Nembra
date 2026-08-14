import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red source contract for the exact boundary where SmartLife delivers an application
/// callback before the app creates a new Task. A callback delivered before the package-owned
/// incomplete-observation cutoff must not become "late" merely because its async ledger admission
/// is scheduled after the watchdog. The receipt time must be package-owned/opaque rather than a
/// freely caller-selected scalar timestamp.
extension TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("SmartLife delivery is receipted before the first async hop and blocks watchdog overtaking")
    func deliveredApplicationCallbackOwnsItsCutoffBeforeTaskScheduling() throws {
        let app = try deliveryCutoffReadRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let connection = String(try deliveryCutoffSection(
            in: app,
            from: "newDriver.connect(",
            to: "private func authenticated(token:"
        ))
        let callback = String(try deliveryCutoffSection(
            in: connection,
            from: "onApplicationUpdate: { [weak self] update in",
            to: "success: { [weak self] in"
        ))

        let receipt = try deliveryCutoffRequiredOffset(
            "let applicationReceipt = TuyaReadOnlyApplicationReceipt.capture(for: token)",
            in: callback
        )
        let inFlight = try deliveryCutoffRequiredOffset(
            "applicationUpdateAdmissionsInFlight += 1",
            in: callback,
            after: receipt
        )
        let asyncHop = try deliveryCutoffRequiredOffset(
            "Task { @MainActor",
            in: callback,
            after: inFlight
        )
        let admission = try deliveryCutoffRequiredOffset(
            "receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)",
            in: callback,
            after: asyncHop
        )
        let release = try deliveryCutoffRequiredOffset(
            "applicationUpdateAdmissionsInFlight -= 1",
            in: callback,
            after: admission
        )

        #expect(receipt < inFlight)
        #expect(inFlight < asyncHop)
        #expect(asyncHop < admission)
        #expect(admission < release)

        let receiver = String(try deliveryCutoffSection(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))
        #expect(receiver.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(receiver.contains("recordApplicationUpdate(isNonEmpty: !update.isEmpty, receipt: receipt, for: token)"))
        #expect(!receiver.contains("applicationUpdateAdmissionsInFlight += 1"))
        #expect(!receiver.contains("applicationUpdateAdmissionsInFlight -= 1"))

        let watchdog = String(try deliveryCutoffSection(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))
        let pendingFence = try deliveryCutoffRequiredOffset(
            "guard self.applicationUpdateAdmissionsInFlight == 0 else {",
            in: watchdog
        )
        let livenessMutation = try deliveryCutoffRequiredOffset(
            "try await self.sessionLedger.observeCurrentConnection(for: token)",
            in: watchdog,
            after: pendingFence
        )
        #expect(pendingFence < livenessMutation)
    }

    @Test("application receipt owns its clock and exact connection token")
    func applicationReceiptCannotSmuggleCallerSelectedCutoffTime() throws {
        let ledger = try deliveryCutoffReadRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let receiptType = String(try deliveryCutoffSection(
            in: ledger,
            from: "public struct TuyaReadOnlyApplicationReceipt",
            to: "public actor TuyaAuthenticatedReadOnlySessionLedger"
        ))

        #expect(receiptType.contains("fileprivate let token: TuyaReadOnlyConnectionToken"))
        #expect(receiptType.contains("fileprivate let receivedAtUptimeNanoseconds: UInt64"))
        #expect(receiptType.contains("public static func capture(for token: TuyaReadOnlyConnectionToken)"))
        #expect(receiptType.contains("DispatchTime.now().uptimeNanoseconds"))
        #expect(!receiptType.contains("public init("))
        #expect(!receiptType.contains("public static func capture(for token: TuyaReadOnlyConnectionToken, receivedAtUptimeNanoseconds:"))

        let record = String(try deliveryCutoffSection(
            in: ledger,
            from: "public func recordApplicationUpdate(",
            to: "public func observeCurrentConnection("
        ))
        #expect(record.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(record.contains("receipt.token == token"))
        #expect(record.contains("let now = receipt.receivedAtUptimeNanoseconds"))
        #expect(!record.contains("receivedAtUptimeNanoseconds: UInt64"))
        #expect(!record.contains("let now = try nextMonotonicObservation()"))
        #expect(record.contains("try requireContinuousAuthenticatedObservation(at: now)"))
        #expect(record.contains("try requireIncompleteObservationHorizonOpen(at: now)"))
    }

    private func deliveryCutoffRequiredOffset(
        _ token: String,
        in source: String,
        after lowerBound: String.Index? = nil
    ) throws -> String.Index {
        let lower = lowerBound ?? source.startIndex
        guard let range = source.range(of: token, range: lower..<source.endIndex) else {
            Issue.record("Expected delivered-callback cutoff contract missing: \(token)")
            throw DeliveryCutoffSourceContractError.requiredTokenMissing
        }
        return range.lowerBound
    }

    private func deliveryCutoffSection(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw DeliveryCutoffSourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func deliveryCutoffReadRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum DeliveryCutoffSourceContractError: Error {
        case sectionMissing
        case requiredTokenMissing
    }
}
