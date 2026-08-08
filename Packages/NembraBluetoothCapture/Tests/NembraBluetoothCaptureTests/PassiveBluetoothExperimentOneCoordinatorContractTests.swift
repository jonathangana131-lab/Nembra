import Foundation
import Testing

@Suite("Experiment One app coordinator authority contract")
struct PassiveBluetoothExperimentOneCoordinatorContractTests {
    private static func coordinatorSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothExperimentOneCoordinator.swift"),
            encoding: .utf8
        )
    }

    private static func admissionSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothExperimentOneRun.swift"),
            encoding: .utf8
        )
    }

    @Test("public coordinator owns one internal run and never exposes admission recorder or vehicle injection")
    func publicSurfaceKeepsMutationAuthorityInsidePackage() throws {
        let source = try Self.coordinatorSource()

        #expect(source.contains("public final class PassiveBluetoothExperimentOneCoordinator"))
        #expect(source.contains("private let run: PassiveBluetoothExperimentOneRun"))
        #expect(source.contains("private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?"))
        #expect(source.contains("public var powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession"))
        #expect(source.contains("package init(controller: ForegroundCoreBluetoothCaptureController) throws"))
        #expect(source.contains("vehicleIdentity: VehicleProfile.aovoproES80.identity"))

        #expect(!source.contains("public var pendingCaptureAdmission"))
        #expect(!source.contains("public let pendingCaptureAdmission"))
        #expect(!source.contains("public func issueCaptureAdmission"))
        #expect(!source.contains("recorder: PassiveCoreBluetoothCaptureRecorder"))
        #expect(!source.contains("public init(controller: ForegroundCoreBluetoothCaptureController) throws"))
        #expect(!source.contains("public init(\n        controller: ForegroundCoreBluetoothCaptureController,\n        vehicleIdentity:"))
    }

    @Test("admission is issued before a fresh controller scan epoch")
    func preparationForcesPostAdmissionRediscovery() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(source.range(of: "    public func prepareCaptureRediscovery(")?.lowerBound)
        let end = try #require(
            source.range(of: "    public func restartPreparedRediscovery()", range: start..<source.endIndex)?.lowerBound
        )
        let preparation = source[start..<end]

        let issue = try #require(preparation.range(of: "run.issueCaptureAdmission("))
        let publish = try #require(preparation.range(of: "pendingCaptureAdmission = admission"))
        let scan = try #require(preparation.range(of: "try restartPreparedRediscovery()"))
        #expect(issue.lowerBound < publish.lowerBound)
        #expect(publish.lowerBound < scan.lowerBound)

        let restartStart = try #require(source.range(of: "    public func restartPreparedRediscovery()")?.lowerBound)
        let connectStart = try #require(source.range(of: "    public func connectPreparedCapture(")?.lowerBound)
        let restart = source[restartStart..<connectStart]
        #expect(restart.contains("controller.startScanning(captureAdvertisementCadence: true)"))
    }

    @Test("connect waits for exact rediscovery before consuming opaque admission")
    func connectionDoesNotBurnAdmissionBeforeTargetReappears() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(source.range(of: "    public func connectPreparedCapture(")?.lowerBound)
        let connection = source[start...]

        let catalogGuard = try #require(connection.range(of: "controller.discoveredPeripherals.first(where: { $0.id == identifier })"))
        let connect = try #require(connection.range(of: "controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)"))
        #expect(catalogGuard.lowerBound < connect.lowerBound)
        #expect(connection.contains("throw CoordinatorError.targetNotRediscovered(identifier)"))
        #expect(connection.contains("throw CoordinatorError.targetNotConnectable(identifier)"))
    }

    @Test("controller staging failure keeps coordinator handoff only while admission is unconsumed")
    func connectionFailurePreservesOnlyUnconsumedAuthority() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(source.range(of: "    public func connectPreparedCapture(")?.lowerBound)
        let connection = source[start...]

        #expect(!connection.contains("defer {"))
        let connect = try #require(connection.range(of: "controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)"))
        let consumed = try #require(connection.range(of: "if admission.isConsumed"))
        let clear = try #require(connection.range(of: "pendingCaptureAdmission = nil", range: consumed.lowerBound..<connection.endIndex))
        #expect(connect.lowerBound < consumed.lowerBound)
        #expect(consumed.lowerBound < clear.lowerBound)
        #expect(connection.contains("preparedCorrelatedTargetIdentifier = nil"))
        #expect(!connection.contains("stagingPreview()"))

        let admission = try Self.admissionSource()
        #expect(admission.contains("var isConsumed: Bool"))
        #expect(admission.contains("hasBeenConsumed"))
        #expect(!admission.contains("public var isConsumed"))
    }
}
