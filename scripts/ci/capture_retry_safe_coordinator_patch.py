from pathlib import Path

root = Path("Packages/NembraBluetoothCapture")
run_path = root / "Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift"
controller_path = root / "Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"
coordinator_path = root / "Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator.swift"
recover_test_path = root / "Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests.swift"
coord_test_path = root / "Tests/NembraBluetoothCaptureTests/PassiveBluetoothExperimentOneCoordinatorContractTests.swift"

run = run_path.read_text()
old_preview = '''    struct Preview: Equatable, Sendable {
        let admissionIdentity: UUID
        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence
        let peripheralIdentifier: UUID
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64
    }
'''
new_preview = '''    /// Read-only package-owned staging view used before the one-shot admission is burned.
    /// It deliberately carries no recorder or raw power-cycle evidence and cannot be
    /// constructed outside this producer file.
    struct StagingPreview: Equatable, Sendable {
        let admissionIdentity: UUID
        let peripheralIdentifier: UUID
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64

        fileprivate init(payload: Payload) {
            admissionIdentity = payload.admissionIdentity
            peripheralIdentifier = payload.peripheralIdentifier
            issuedAtUptimeNanoseconds = payload.issuedAtUptimeNanoseconds
        }
    }
'''
if run.count(old_preview) != 1:
    raise SystemExit("Preview anchor changed")
run = run.replace(old_preview, new_preview, 1)
old_accessor = '''    /// Read-only producer-owned staging view. Reading it cannot consume the handoff.
    var preview: Preview {
        Preview(
            admissionIdentity: payload.admissionIdentity,
            powerCycleEvidence: payload.powerCycleEvidence,
            peripheralIdentifier: payload.peripheralIdentifier,
            issuedAtUptimeNanoseconds: payload.issuedAtUptimeNanoseconds
        )
    }
'''
new_accessor = '''    /// Allows package-owned staging checks without consuming the handoff. Once an alias
    /// has consumed the admission, no later caller can obtain a fresh staging view.
    func previewForControllerStaging() throws -> StagingPreview {
        guard !hasBeenConsumed else {
            throw ConsumptionError.alreadyConsumed
        }
        return StagingPreview(payload: payload)
    }
'''
if run.count(old_accessor) != 1:
    raise SystemExit("preview accessor anchor changed")
run = run.replace(old_accessor, new_accessor, 1)
run_path.write_text(run)

controller = controller_path.read_text()
old_stage = '''        let preview = admission.preview
        guard case let .singleRepeatableCandidate(correlatedIdentifier) =
                preview.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == preview.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
        guard let peripheral = peripheralByIdentifier[preview.peripheralIdentifier],
'''
new_stage = '''        let preview = try admission.previewForControllerStaging()
        guard let peripheral = peripheralByIdentifier[preview.peripheralIdentifier],
'''
if controller.count(old_stage) != 1:
    raise SystemExit("controller staging anchor changed")
controller = controller.replace(old_stage, new_stage, 1)
if controller.count("latestAdvertisement.receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds") != 1:
    raise SystemExit("freshness anchor changed")
controller = controller.replace(
    "latestAdvertisement.receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds",
    "latestAdvertisement.receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds",
    1,
)
old_rebind = '''        guard payload.admissionIdentity == preview.admissionIdentity,
              payload.powerCycleEvidence == preview.powerCycleEvidence,
              payload.peripheralIdentifier == preview.peripheralIdentifier,
              payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds else {
            throw ControllerError.targetSessionChanged
        }
'''
new_rebind = '''        guard payload.admissionIdentity == preview.admissionIdentity,
              payload.peripheralIdentifier == preview.peripheralIdentifier,
              payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds,
              case let .singleRepeatableCandidate(correlatedIdentifier) =
                payload.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == preview.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
'''
if controller.count(old_rebind) != 1:
    raise SystemExit("controller rebind anchor changed")
controller = controller.replace(old_rebind, new_rebind, 1)
controller_path.write_text(controller)

coordinator = coordinator_path.read_text()
old_connect = '''        defer {
            pendingCaptureAdmission = nil
            preparedCorrelatedTargetIdentifier = nil
        }
        try controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)
'''
new_connect = '''        do {
            try controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)
        } catch {
            // Controller-local staging failures that happen before consumption are
            // recoverable: keep the exact sealed admission so the app may continue
            // passive scan and retry. Once consumed, any later failure is fail-closed.
            if (try? admission.previewForControllerStaging()) == nil {
                pendingCaptureAdmission = nil
                preparedCorrelatedTargetIdentifier = nil
            }
            throw error
        }

        pendingCaptureAdmission = nil
        preparedCorrelatedTargetIdentifier = nil
'''
if coordinator.count(old_connect) != 1:
    raise SystemExit("coordinator connect anchor changed")
coordinator = coordinator.replace(old_connect, new_connect, 1)
coordinator_path.write_text(coordinator)

recover_test = recover_test_path.read_text()
recover_test = recover_test.replace('method.range(of: "receivedAtUptimeNanoseconds >=")', 'method.range(of: "receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds")')
recover_test = recover_test.replace('let catalog = try #require(method.range(of: "peripheralByIdentifier["))', 'let preview = try #require(method.range(of: "admission.previewForControllerStaging()"))\n        let catalog = try #require(method.range(of: "peripheralByIdentifier[preview.peripheralIdentifier]"))')
recover_test = recover_test.replace('let discovery = try #require(method.range(of: "latestDiscoveryByIdentifier["))', 'let discovery = try #require(method.range(of: "latestDiscoveryByIdentifier[preview.peripheralIdentifier]"))')
recover_test = recover_test.replace('let attempt = try #require(method.range(of: "targetState.validateCanBeginAttempt("))', 'let attempt = try #require(method.range(of: "targetState.validateCanBeginAttempt(for: preview.peripheralIdentifier)"))')
recover_test = recover_test.replace('let advertisement = try #require(method.range(of: "latestAdvertisementByIdentifier["))', 'let advertisement = try #require(method.range(of: "latestAdvertisementByIdentifier[preview.peripheralIdentifier]"))')
recover_test = recover_test.replace('        #expect(catalog.lowerBound < consume.lowerBound)', '        #expect(preview.lowerBound < catalog.lowerBound)\n        #expect(catalog.lowerBound < consume.lowerBound)', 1)
recover_test += '''

@Suite("Experiment One staging preview sealing")
struct PassiveBluetoothExperimentOneStagingPreviewSealingTests {
    @Test("preview is producer-constructed and excludes recorder/evidence authority")
    func sealedPreviewSurface() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "struct StagingPreview: Equatable, Sendable")?.lowerBound)
        let end = try #require(source.range(of: "\n    struct Payload", range: start..<source.endIndex)?.lowerBound)
        let preview = source[start..<end]
        #expect(preview.contains("fileprivate init(payload: Payload)"))
        #expect(!preview.contains("PassiveCoreBluetoothCaptureRecorder"))
        #expect(!preview.contains("PassiveBluetoothExperimentOnePowerCycleEvidence"))
    }
}
'''
recover_test_path.write_text(recover_test)

coord_test = coord_test_path.read_text()
old_expect = '        #expect(connection.contains("defer {"))\n'
new_expect = '''        #expect(!connection.contains("defer {"))
        #expect(connection.contains("try controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)"))
        #expect(connection.contains("if (try? admission.previewForControllerStaging()) == nil"))
        #expect(connection.contains("throw error"))
'''
if coord_test.count(old_expect) != 1:
    raise SystemExit("coordinator test anchor changed")
coord_test = coord_test.replace(old_expect, new_expect, 1)
coord_test_path.write_text(coord_test)
