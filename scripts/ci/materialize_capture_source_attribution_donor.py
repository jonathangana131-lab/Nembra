#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one target, found {count}: {old[:180]!r}")
    p.write_text(text.replace(old, new, 1))


app_path = "NembraApp/App/NembraCaptureEntrypoint.swift"

# 1) Carry source-authority failure as an explicit synchronous MainActor channel.
replace_once(
    app_path,
    '''        onApplicationUpdate: @escaping @MainActor ([String: String]) -> Void,\n        success: @escaping () -> Void,''',
    '''        onApplicationUpdate: @escaping @MainActor ([String: String]) -> Void,\n        sourceAuthorityFailure: @escaping @MainActor () -> Void,\n        success: @escaping () -> Void,'''
)

# 2) On callback source failure, close app acceptance synchronously before scheduling package retirement.
replace_once(
    app_path,
    '''                        self.applicationUpdateAdmissionTail = admissionTask\n                    },\n                    success: { [weak self] in''',
    '''                        self.applicationUpdateAdmissionTail = admissionTask\n                    },\n                    sourceAuthorityFailure: { [weak self] in\n                        guard let self,\n                              self.currentConnectionToken == token else { return }\n\n                        // The driver has already synchronously latched application forwarding\n                        // closed. Close rider-visible acceptance on the same MainActor turn before\n                        // scheduling exact-token package retirement so no watchdog continuation can\n                        // promote this generation while source authority is merely queued to retire.\n                        self.acceptanceCutIsClosed = true\n                        self.watchdog?.cancel()\n                        self.watchdog = nil\n                        self.phase = .failed\n                        self.message = "Tuya application evidence arrived from a device source that did not match the selected scooter. The exact session is being retired; relaunch Capture before another attempt."\n\n                        Task { @MainActor [weak self] in\n                            await self?.invalidateSourceAuthority(\n                                token: token,\n                                message: "Tuya application evidence came from a source other than the exact selected scooter. The generation was retired without counting that payload or claiming Bluetooth disconnected.",\n                                kind: "sdk_application_source_identity_rejected"\n                            )\n                        }\n                    },\n                    success: { [weak self] in'''
)

# 3) Bind SmartLifeDriver to the exact selected device and latch forwarding closed on mismatch.
replace_once(
    app_path,
    '''private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {\n    private var device: ThingSmartDevice?\n    private var onApplicationUpdate: (@MainActor ([String: String]) -> Void)?\n\n    func connect(''',
    '''private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {\n    private var device: ThingSmartDevice?\n    private var expectedDeviceID: String?\n    private var onApplicationUpdate: (@MainActor ([String: String]) -> Void)?\n    private var onSourceAuthorityFailure: (@MainActor () -> Void)?\n\n    func connect('''
)
replace_once(
    app_path,
    '''        onApplicationUpdate: @escaping @MainActor ([String: String]) -> Void,\n        success: @escaping () -> Void,\n        failure: @escaping () -> Void\n    ) {\n        guard OfficialTuyaFactory.bootstrap() else {\n            failure()\n            return\n        }\n        self.onApplicationUpdate = onApplicationUpdate\n        device = ThingSmartDevice(deviceId: deviceID)''',
    '''        onApplicationUpdate: @escaping @MainActor ([String: String]) -> Void,\n        sourceAuthorityFailure: @escaping @MainActor () -> Void,\n        success: @escaping () -> Void,\n        failure: @escaping () -> Void\n    ) {\n        guard OfficialTuyaFactory.bootstrap() else {\n            failure()\n            return\n        }\n        expectedDeviceID = deviceID\n        self.onApplicationUpdate = onApplicationUpdate\n        onSourceAuthorityFailure = sourceAuthorityFailure\n        device = ThingSmartDevice(deviceId: deviceID)'''
)
replace_once(
    app_path,
    '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {\n        guard let dps, !dps.isEmpty else { return }''',
    '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {\n        guard let callbackDeviceID = device?.deviceModel.devId,\n              callbackDeviceID == expectedDeviceID else {\n            // Application DPS participates in physical-readiness evidence. A nil/wrong SDK\n            // callback source therefore retires source authority instead of being ignored. Close\n            // forwarding before invoking the controller so a later callback cannot slip into the\n            // accepted prefix while exact-token package retirement is only scheduled.\n            onApplicationUpdate = nil\n            expectedDeviceID = nil\n            let sourceAuthorityFailure = onSourceAuthorityFailure\n            onSourceAuthorityFailure = nil\n            sourceAuthorityFailure?()\n            return\n        }\n        guard let dps, !dps.isEmpty else { return }'''
)

# 4) Add the reviewed red-team oracle, strengthened for MainActor custody, into the donor tree.
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSmartLifeApplicationSourceAttributionSourceTests.swift")
if test_path.exists():
    raise SystemExit(f"unexpected pre-existing path: {test_path}")
test_path.write_text(r'''import Foundation
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
        #expect(connectCall.contains("acceptanceCutIsClosed = true"))
        #expect(connectCall.contains("invalidateSourceAuthority("))

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
        #expect(failureFence.contains("onApplicationUpdate = nil"))
        #expect(failureFence.contains("expectedDeviceID = nil"))
        #expect(failureFence.contains("onSourceAuthorityFailure?"))
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
''')

app = Path(app_path).read_text()
assert app.count("sourceAuthorityFailure: @escaping @MainActor () -> Void") == 2
assert app.count("sessionLedger.captureApplicationReceipt(") == 1
assert "guard let callbackDeviceID = device?.deviceModel.devId" in app
assert "callbackDeviceID == expectedDeviceID" in app
assert "acceptanceCutIsClosed = true" in app
assert "onApplicationUpdate = nil" in app

Path(".github/workflows/capture-source-attribution-donor-materializer.yml").unlink()
Path(__file__).unlink()
