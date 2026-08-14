import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaAppChronologyIntegrityTerminalSourceTests {
    @Test("SDK application callback captures admission chronology before spawning async ledger work")
    func sdkCallbackReceiptPrecedesTaskHop() throws {
        let app = try readReceiptCutRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = String(try receiptCutSection(
            in: app,
            from: "newDriver.connect(",
            to: "            } catch {"
        ))
        let callback = String(try receiptCutSection(
            in: begin,
            from: "onApplicationUpdate:",
            to: "success:"
        ))

        let task = try receiptCutRequiredRange("Task { @MainActor", in: callback)
        let synchronousPrefix = String(callback[..<task.lowerBound])

        // Preserve the SDK callback ordering point before creating another MainActor task;
        // otherwise the watchdog can cross the bounded observation horizon first because of
        // scheduling rather than evidence order.
        #expect(
            synchronousPrefix.contains("DispatchTime.now().uptimeNanoseconds") ||
            synchronousPrefix.contains("makeApplicationUpdateReceipt") ||
            synchronousPrefix.contains("beginApplicationUpdateAdmission")
        )
        #expect(
            synchronousPrefix.contains("applicationUpdateAdmissionsInFlight += 1") ||
            synchronousPrefix.contains("beginApplicationUpdateAdmission")
        )

        #expect(
            callback.contains("receivedAtUptimeNanoseconds:") ||
            callback.contains("applicationReceipt:") ||
            callback.contains("admission:")
        )
    }

    @Test("watchdog cannot cross the incomplete horizon while a delivered SDK callback is pending admission")
    func deliveredCallbackAdmissionFencesWatchdogHorizonMutation() throws {
        let app = try readReceiptCutRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try receiptCutSection(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))

        let observe = try receiptCutRequiredRange(
            "try await self.sessionLedger.observeCurrentConnection(for: token)",
            in: watchdog
        )
        let preObserve = String(watchdog[..<observe.lowerBound])

        #expect(
            preObserve.contains("applicationUpdateAdmissionsInFlight == 0") ||
            preObserve.contains("applicationUpdateAdmissionsInFlight != 0") ||
            preObserve.contains("applicationUpdateAdmissionsInFlight > 0") ||
            preObserve.contains("hasPendingApplicationUpdateAdmission")
        )

        #expect(watchdog.contains("guard self.applicationUpdateAdmissionsInFlight == 0 else"))
        #expect(watchdog.contains("self.acceptanceCutIsClosed = true"))
    }

    @Test("ledger application chronology uses delivered receipt time instead of delayed task execution time")
    func ledgerDoesNotResampleApplicationReceiptAfterTaskHop() throws {
        let ledger = try readReceiptCutRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let record = String(try receiptCutSection(
            in: ledger,
            from: "public func recordApplicationUpdate(",
            to: "    /// Advances only the non-secret liveness observation"
        ))

        // A stronger equivalent opaque receipt object is acceptable. A fresh package clock sample
        // only after delayed async processing is not equivalent to the already-delivered callback.
        #expect(
            record.contains("receivedAtUptimeNanoseconds") ||
            record.contains("applicationReceipt") ||
            record.contains("receipt:")
        )
        #expect(!record.contains("let now = try nextMonotonicObservation()"))
        #expect(record.contains("requireContinuousAuthenticatedObservation"))
        #expect(record.contains("requireIncompleteObservationHorizonOpen"))

        let app = try readReceiptCutRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = String(try receiptCutSection(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))
        #expect(
            receive.contains("receivedAtUptimeNanoseconds") ||
            receive.contains("applicationReceipt") ||
            receive.contains("admission")
        )
        #expect(
            receive.contains("recordApplicationUpdate(") &&
            (receive.contains("receivedAtUptimeNanoseconds:") ||
             receive.contains("applicationReceipt:") ||
             receive.contains("receipt:"))
        )
    }
}

private func receiptCutSection(
    in source: String,
    from start: String,
    to end: String
) throws -> Substring {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        Issue.record("Expected source section missing: \(start) ... \(end)")
        throw ReceiptCutSourceContractError.sectionMissing
    }
    return source[startRange.lowerBound..<endRange.lowerBound]
}

private func receiptCutRequiredRange(
    _ needle: String,
    in source: String
) throws -> Range<String.Index> {
    guard let range = source.range(of: needle) else {
        Issue.record("Expected source contract missing: \(needle)")
        throw ReceiptCutSourceContractError.requiredContractMissing
    }
    return range
}

private func readReceiptCutRepositoryFile(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum ReceiptCutSourceContractError: Error {
    case sectionMissing
    case requiredContractMissing
}
