import Foundation
import Testing

@Suite("Experiment One app coordinator authority contract")
struct PassiveBluetoothExperimentOneCoordinatorContractTests {
    private static func source(named name: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }

    private static func coordinatorSource() throws -> String {
        try source(named: "PassiveBluetoothExperimentOneCoordinator.swift")
    }

    @Test("public coordinator owns one internal run and never exposes admission recorder or vehicle injection")
    func publicSurfaceKeepsMutationAuthorityInsidePackage() throws {
        let source = try Self.coordinatorSource()

        #expect(source.contains("public final class PassiveBluetoothExperimentOneCoordinator"))
        #expect(source.contains("private let run: PassiveBluetoothExperimentOneRun"))
        #expect(source.contains("private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?"))
        #expect(source.contains("public var powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession"))
        #expect(source.contains("public init(controller: ForegroundCoreBluetoothCaptureController) throws"))
        #expect(source.contains("vehicleIdentity: VehicleProfile.aovoproES80.identity"))

        #expect(!source.contains("public var pendingCaptureAdmission"))
        #expect(!source.contains("public let pendingCaptureAdmission"))
        #expect(!source.contains("public func issueCaptureAdmission"))
        #expect(!source.contains("recorder: PassiveCoreBluetoothCaptureRecorder"))
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

    @Test("connect waits for exact rediscovery before attempting opaque admission")
    func connectionDoesNotBurnAdmissionBeforeTargetReappears() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(source.range(of: "    public func connectPreparedCapture(")?.lowerBound)
        let connection = source[start...]

        let catalogGuard = try #require(connection.range(of: "controller.discoveredPeripherals.first(where: { $0.id == identifier })"))
        let connect = try #require(connection.range(of: "controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)"))
        #expect(catalogGuard.lowerBound < connect.lowerBound)
        #expect(connection.contains("throw CoordinatorError.targetNotRediscovered(identifier)"))
        #expect(connection.contains("throw CoordinatorError.targetNotConnectable(identifier)"))
        #expect(!connection.contains("defer {"))
    }

    @Test("controller rejection keeps coordinator handoff only while sealed admission is unconsumed")
    func connectionFailurePreservesOnlyUnconsumedAuthority() throws {
        let coordinator = try Self.coordinatorSource()
        let run = try Self.source(named: "PassiveBluetoothExperimentOneRun.swift")
        let start = try #require(coordinator.range(of: "    public func connectPreparedCapture(")?.lowerBound)
        let connection = coordinator[start...]

        let connect = try #require(connection.range(of: "controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)"))
        let consumed = try #require(connection.range(of: "if admission.isConsumed {"))
        let clear = try #require(connection.range(of: "pendingCaptureAdmission = nil", range: consumed.lowerBound..<connection.endIndex))
        let rethrow = try #require(connection.range(of: "throw error", range: clear.upperBound..<connection.endIndex))
        #expect(connect.lowerBound < consumed.lowerBound)
        #expect(consumed.lowerBound < clear.lowerBound)
        #expect(clear.lowerBound < rethrow.lowerBound)
        #expect(connection.contains("preparedCorrelatedTargetIdentifier = nil"))
        #expect(!connection.contains("stagingPreview()"))

        // Consumption state is package-internal and derived only from the exact one-shot bit.
        #expect(run.contains("var isConsumed: Bool {\n        hasBeenConsumed\n    }"))
        #expect(!run.contains("public var isConsumed"))
        #expect(run.contains("guard !hasBeenConsumed else"))
        #expect(run.contains("hasBeenConsumed = true"))
    }
}
