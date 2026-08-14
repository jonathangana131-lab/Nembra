import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaSecureLinkProductSurfaceSourceTests {
    @Test("SmartLife application evidence requires exact selected-device source attribution")
    func smartLifeApplicationEvidenceRequiresExactSelectedDeviceSource() throws {
        let source = try readApplicationSourceAttributionRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let protocolBody = String(try applicationSourceAttributionSection(
            in: source,
            from: "private protocol OfficialTuyaDriver: AnyObject",
            to: "private enum OfficialTuyaFactory"
        ))
        let connectCall = String(try applicationSourceAttributionSection(
            in: source,
            from: "newDriver.connect(",
            to: "            } catch {"
        ))
        let driverBody = String(try applicationSourceAttributionSection(
            in: source,
            from: "private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate",
            to: "#endif"
        ))
        let driverConnect = String(try applicationSourceAttributionSection(
            in: driverBody,
            from: "    func connect(",
            to: "    func isLocallyConnected"
        ))
        let callback = String(try applicationSourceAttributionSection(
            in: driverBody,
            from: "    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?)",
            to: "    // Assign collision suffixes"
        ))

        #expect(protocolBody.contains("sourceAuthorityFailure: @escaping @MainActor () -> Void"))
        #expect(connectCall.contains("sourceAuthorityFailure:"))
        let synchronousCut = try applicationSourceAttributionRequiredRange(
            "acceptanceCutIsClosed = true",
            in: connectCall
        )
        let watchdogCancel = try applicationSourceAttributionRequiredRange(
            "watchdog?.cancel()",
            in: connectCall
        )
        let failedPhase = try applicationSourceAttributionRequiredRange(
            "phase = .failed",
            in: connectCall
        )
        let retirementTask = try applicationSourceAttributionRequiredRange(
            "Task { @MainActor [weak self] in",
            in: connectCall
        )
        let retirement = try applicationSourceAttributionRequiredRange(
            "invalidateSourceAuthority(",
            in: connectCall
        )
        #expect(synchronousCut.lowerBound < watchdogCancel.lowerBound)
        #expect(watchdogCancel.lowerBound < failedPhase.lowerBound)
        #expect(failedPhase.lowerBound < retirementTask.lowerBound)
        #expect(retirementTask.lowerBound < retirement.lowerBound)
        #expect(driverBody.contains("private var expectedDeviceID: String?"))
        #expect(driverBody.contains("private var onSourceAuthorityFailure: (@MainActor () -> Void)?"))
        #expect(driverConnect.contains("expectedDeviceID = deviceID"))
        #expect(driverConnect.contains("onSourceAuthorityFailure = sourceAuthorityFailure"))

        let sourceGuard = try applicationSourceAttributionRequiredRange(
            "guard let callbackDeviceID = device?.deviceModel.devId",
            in: callback
        )
        let identityFence = try applicationSourceAttributionRequiredRange(
            "callbackDeviceID == expectedDeviceID",
            in: callback
        )
        let payloadGuard = try applicationSourceAttributionRequiredRange(
            "guard let dps, !dps.isEmpty else { return }",
            in: callback
        )
        let forward = try applicationSourceAttributionRequiredRange(
            "onApplicationUpdate?(sanitized)",
            in: callback
        )

        #expect(sourceGuard.lowerBound < identityFence.lowerBound)
        #expect(identityFence.lowerBound < payloadGuard.lowerBound)
        #expect(payloadGuard.lowerBound < forward.lowerBound)

        let failureFence = String(callback[..<payloadGuard.lowerBound])
        let forwardingCut = try applicationSourceAttributionRequiredRange(
            "onApplicationUpdate = nil",
            in: failureFence
        )
        let failureCallback = try applicationSourceAttributionRequiredRange(
            "onSourceAuthorityFailure?()",
            in: failureFence
        )
        #expect(forwardingCut.lowerBound < failureCallback.lowerBound)
        #expect(!callback.contains("publishDps"))
        #expect(!callback.contains("writeValue"))
    }
}

private func applicationSourceAttributionSection(
    in source: String,
    from start: String,
    to end: String
) throws -> Substring {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        Issue.record("Expected source section missing: \(start) ... \(end)")
        throw ApplicationSourceAttributionSourceContractError.sectionMissing
    }
    return source[startRange.lowerBound..<endRange.lowerBound]
}

private func applicationSourceAttributionRequiredRange(
    _ needle: String,
    in source: String
) throws -> Range<String.Index> {
    guard let range = source.range(of: needle) else {
        Issue.record("Expected source contract missing: \(needle)")
        throw ApplicationSourceAttributionSourceContractError.requiredContractMissing
    }
    return range
}

private func readApplicationSourceAttributionRepositoryFile(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum ApplicationSourceAttributionSourceContractError: Error {
    case sectionMissing
    case requiredContractMissing
}
