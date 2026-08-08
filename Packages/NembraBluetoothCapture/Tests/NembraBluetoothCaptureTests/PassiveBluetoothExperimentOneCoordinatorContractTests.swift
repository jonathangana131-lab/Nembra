import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One app coordinator authority contract")
struct PassiveBluetoothExperimentOneCoordinatorContractTests {
    private typealias Coordinator = PassiveBluetoothExperimentOneCoordinator
    private typealias CoordinatorError = PassiveBluetoothExperimentOneCoordinator.CoordinatorError

    private static func coordinatorSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent("Sources").appendingPathComponent("NembraBluetoothCapture").appendingPathComponent("PassiveBluetoothExperimentOneCoordinator.swift"), encoding: .utf8)
    }

    @Test("current NO-GO creates no live controller authority")
    @MainActor
    func noGoIsMechanical() throws {
        let coordinator = try Coordinator()
        let status = coordinator.status
        #expect(status.physicalProcedurePermitted == false)
        #expect(status.fieldExecutionStatus == .noGo(.finalComposedBuildNotAuthorized))
        #expect(status.bluetoothState == nil)
        #expect(status.connection == .unavailable)
        #expect(status.correlation == .incomplete)
        #expect(status.hasPreparedCaptureAdmission == false)
        #expect(coordinator.finalizedArtifact == nil)
    }

    @Test("NO-GO blocks procedure advancement before evidence mutates")
    @MainActor
    func noGoBlocksProcedure() throws {
        let coordinator = try Coordinator()
        let before = coordinator.status.powerCycleProgress
        do {
            try coordinator.startCurrentPowerCycleWindow()
            Issue.record("expected physical procedure lock")
        } catch let error as CoordinatorError {
            #expect(error == .physicalProcedureLocked)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(coordinator.status.powerCycleProgress == before)
        #expect(coordinator.powerCycleResult == nil)
    }

    @Test("ordinary construction stays locked even under a future permissive field gate")
    func futureGateCannotUnlockOrdinaryConstruction() {
        let policy = PassiveBluetoothExperimentOneCoordinatorConstructionPolicy.self

        #expect(policy.permitsPhysicalProcedure(
            hasCanonicalLiveController: false,
            fieldGatePermitsPhysicalProcedure: false
        ) == false)
        #expect(policy.permitsPhysicalProcedure(
            hasCanonicalLiveController: false,
            fieldGatePermitsPhysicalProcedure: true
        ) == false)
        #expect(policy.permitsPhysicalProcedure(
            hasCanonicalLiveController: true,
            fieldGatePermitsPhysicalProcedure: false
        ) == false)
        #expect(policy.permitsPhysicalProcedure(
            hasCanonicalLiveController: true,
            fieldGatePermitsPhysicalProcedure: true
        ) == true)
    }

    @Test("public coordinator construction never creates the live CoreBluetooth controller")
    func ordinaryPublicInitializerIsPermanentlyStatusOnly() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(source.range(of: "    public init() throws {")?.lowerBound)
        let end = try #require(source.range(of: "    package init(controller:", range: start..<source.endIndex)?.lowerBound)
        let initializer = source[start..<end]

        #expect(initializer.contains("controller = nil"))
        #expect(!initializer.contains("ForegroundCoreBluetoothCaptureController("))
        #expect(!initializer.contains("PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(source.contains("hasCanonicalLiveController: controller != nil"))
        #expect(source.contains("guard physicalProcedurePermittedForThisCoordinator else"))
    }

    @Test("public coordinator does not expose caller target controller vehicle timing recorder or admission")
    func publicSurfaceKeepsMutationAuthorityInsidePackage() throws {
        let source = try Self.coordinatorSource()
        #expect(source.contains("public final class PassiveBluetoothExperimentOneCoordinator"))
        #expect(source.contains("private let run: PassiveBluetoothExperimentOneRun"))
        #expect(source.contains("private let controller: ForegroundCoreBluetoothCaptureController?"))
        #expect(source.contains("private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?"))
        #expect(!source.contains("public let controller:"))
        #expect(!source.contains("public var powerCycleObservationSession:"))
        #expect(!source.contains("public init(controller:"))
        #expect(!source.contains("public func issueCaptureAdmission"))
        #expect(!source.contains("public func connectPreparedCapture(\n        timeout:"))
        #expect(!source.contains("recorder: PassiveCoreBluetoothCaptureRecorder"))
    }

    @Test("admission is issued before a fresh controller scan epoch")
    func preparationForcesPostAdmissionRediscovery() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(source.range(of: "    public func confirmCorrelatedTargetAndBeginRediscovery()")?.lowerBound)
        let end = try #require(source.range(of: "    public func restartPreparedRediscovery()", range: start..<source.endIndex)?.lowerBound)
        let preparation = source[start..<end]
        let issue = try #require(preparation.range(of: "run.issueCaptureAdmission()"))
        let publish = try #require(preparation.range(of: "pendingCaptureAdmission = admission"))
        let scan = try #require(preparation.range(of: "controller.startScanning(captureAdvertisementCadence: true)"))
        #expect(issue.lowerBound < publish.lowerBound)
        #expect(publish.lowerBound < scan.lowerBound)
    }

    @Test("connect waits for hidden exact rediscovery before opaque admission consumption")
    func connectionDoesNotBurnAdmissionBeforeTargetReappears() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(source.range(of: "    public func connectPreparedCapture()")?.lowerBound)
        let connection = source[start...]
        let catalogPresence = try #require(connection.range(of: "controller.hasDiscoveredPeripheral(identifier: identifier)"))
        let exactDiscovery = try #require(connection.range(of: "controller.discoveredPeripheral(identifier: identifier)"))
        let connect = try #require(connection.range(of: "controller.connectUsingExperimentOneAdmission(admission, timeout: 12)"))
        #expect(catalogPresence.lowerBound < exactDiscovery.lowerBound)
        #expect(exactDiscovery.lowerBound < connect.lowerBound)
        #expect(connection.contains("throw CoordinatorError.targetNotRediscovered"))
        #expect(connection.contains("throw CoordinatorError.targetNotConnectable"))
    }

    @Test("controller staging failure keeps handoff only while producer proves admission unconsumed")
    func connectionFailurePreservesOnlyUnconsumedAuthority() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(source.range(of: "    public func connectPreparedCapture()")?.lowerBound)
        let connection = source[start...]
        #expect(!connection.contains("defer {"))
        let connect = try #require(connection.range(of: "controller.connectUsingExperimentOneAdmission(admission, timeout: 12)"))
        let preview = try #require(connection.range(of: "admission.previewForControllerStaging()"))
        let clear = try #require(connection.range(of: "pendingCaptureAdmission = nil", range: preview.lowerBound..<connection.endIndex))
        #expect(connect.lowerBound < preview.lowerBound)
        #expect(preview.lowerBound < clear.lowerBound)
        #expect(connection.contains("preparedCorrelatedTargetIdentifier = nil"))
    }
}
