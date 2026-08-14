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
            to: "    private func authenticated(token: TuyaReadOnlyConnectionToken) async"
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

        // Application payloads are part of physical-readiness evidence. The driver therefore
        // needs an explicit fail-closed source-authority channel rather than treating any
        // non-empty callback delivered to this delegate as evidence from the selected device.
        #expect(protocolBody.contains("sourceAuthorityFailure: @escaping @MainActor () -> Void"))
        #expect(connectCall.contains("sourceAuthorityFailure:"))
        #expect(connectCall.contains("acceptanceCutIsClosed = true"))
        #expect(connectCall.contains("watchdog?.cancel()"))
        #expect(connectCall.contains("phase = .failed"))
        #expect(connectCall.contains("invalidateSourceAuthority("))

        // Bind callback admission to the exact Tuya device ID selected for this connection.
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

        // A nil/wrong callback source is not merely ignored: latch the driver closed before
        // scheduling controller retirement so another callback cannot slip into evidence first.
        let failureFence = String(callback[..<payloadGuard.lowerBound])
        #expect(failureFence.contains("onApplicationUpdate = nil"))
        #expect(failureFence.contains("onSourceAuthorityFailure?()"))

        // Source attribution is evidence custody only. It must not add a device command path.
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