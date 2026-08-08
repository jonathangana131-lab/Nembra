import Foundation
import Testing
@testable import NembraBluetoothCapture

struct ForegroundCoreBluetoothCaptureControllerSourceContractTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture package root
        let controller = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift")
        return try String(contentsOf: controller, encoding: .utf8)
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }

    private static func offset(of needle: String, in haystack: Substring) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    @Test
    func discoveryAdmissionGuardPrecedesEveryCandidateMutation() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    public func centralManager(\n        _ central: CBCentralManager,\n        didDiscover peripheral: CBPeripheral,",
            to: "    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)"
        )

        let guardOffset = try Self.offset(
            of: "guard PassiveCoreBluetoothDiscoveryAdmissionPolicy.accepts(",
            in: body
        )
        for mutation in [
            "peripheralByIdentifier[peripheral.identifier] = peripheral",
            "latestDiscoveryByIdentifier[peripheral.identifier] = discovery",
            "updateDiscoveryList()",
            "latestAdvertisementByIdentifier[peripheral.identifier] = CandidateAdvertisement(",
            "enqueue(.advertisement(observation), receipt: receipt)",
            "lastDiagnostic = Self.diagnostic(error, fallback: \"Candidate advertisement mapping failed.\")",
        ] {
            #expect(guardOffset < (try Self.offset(of: mutation, in: body)))
        }
    }

    @Test
    func cancellationCallGraphKeepsEvidenceBoundaryBeforeRetirement() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    public func cancelActiveConnection() {",
            to: "    /// Adds a human-observed stock-app value"
        )

        #expect(body.contains("cancelActiveConnection(cause: .operatorRequest)"))
        #expect(body.contains("cancelActiveConnection(cause: .foregroundIntegrityLoss)"))
        #expect(body.contains("cancelActiveConnection(cause: .finalizedArtifactTeardown)"))
        #expect(!body.contains("PassiveCoreBluetoothCancellationBoundary"))

        let interruptionOffset = try Self.offset(
            of: "if let interruptionReason = cause.interruptionReason {",
            in: body
        )
        let pendingOffset = try Self.offset(
            of: "selectedTargetCancellationPending = true",
            in: body
        )
        let authorityOffset = try Self.offset(
            of: "guard advanceArtifactAuthority() else { return }",
            in: body
        )
        let retirementOffset = try Self.offset(
            of: "_ = targetState.retireActiveAttempt()",
            in: body
        )
        let transportCancelOffset = try Self.offset(
            of: "centralManager.cancelPeripheralConnection(peripheral)",
            in: body
        )

        #expect(interruptionOffset < pendingOffset)
        #expect(interruptionOffset < authorityOffset)
        #expect(interruptionOffset < retirementOffset)
        #expect(interruptionOffset < transportCancelOffset)
    }

    @Test
    func finalizedTeardownRequiresFrozenCurrentAuthorityAndAuthorityChangesRevokeIt() throws {
        let source = try Self.controllerSource()
        let teardown = try Self.section(
            in: source,
            from: "    public func teardownActiveConnectionAfterFinalization() throws {",
            to: "    private func cancelActiveConnection(cause:"
        )
        let authorizationOffset = try Self.offset(
            of: "guard let finalizedAuthority = lastFinalizedArtifactAuthority,",
            in: teardown
        )
        let rejectionOffset = try Self.offset(
            of: "throw ControllerError.artifactNotFinalized",
            in: teardown
        )
        let transportOffset = try Self.offset(
            of: "cancelActiveConnection(cause: .finalizedArtifactTeardown)",
            in: teardown
        )
        #expect(authorizationOffset < rejectionOffset)
        #expect(rejectionOffset < transportOffset)

        let artifactReads = try Self.section(
            in: source,
            from: "    public func captureSnapshot() async throws -> PassiveBluetoothCaptureSession {",
            to: "    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {"
        )
        #expect(
            artifactReads.components(separatedBy: "lastFinalizedArtifactAuthority = context.authority").count - 1 == 2
        )

        let authorityAdvance = try Self.section(
            in: source,
            from: "    private func advanceArtifactAuthority() -> Bool {",
            to: "    private func scheduleConnectionTimeout("
        )
        let revokeOffset = try Self.offset(
            of: "lastFinalizedArtifactAuthority = nil",
            in: authorityAdvance
        )
        let generationOffset = try Self.offset(
            of: "artifactAuthorityGeneration += 1",
            in: authorityAdvance
        )
        #expect(revokeOffset < generationOffset)
    }

    @Test
    func acquisitionWatchdogRetainsOneSpecificFenceWithoutGenericCancel() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    private func refreshAcquisitionWatchdog() {",
            to: "    private func cancelAcquisitionWatchdog() {"
        )
        let timeoutFence = "self.enqueueInterruption(\"finite GATT acquisition progress timed out\")"
        #expect(body.components(separatedBy: timeoutFence).count - 1 == 1)

        let fenceOffset = try Self.offset(of: timeoutFence, in: body)
        let cancelOffset = try Self.offset(
            of: "self.cancelActiveConnection(cause: .interruptionAlreadyRecorded)",
            in: body
        )
        #expect(fenceOffset < cancelOffset)
        #expect(!body.contains(".operatorRequest"))
    }
}
