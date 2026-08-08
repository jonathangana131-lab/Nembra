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

    private static func researchViewSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture package root
        let view = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent("ES80PassiveCaptureResearchView.swift")
        return try String(contentsOf: view, encoding: .utf8)
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
            "latestAdvertisementByIdentifier[peripheral.identifier] = CandidateAdvertisement(",
            "enqueue(.advertisement(observation), receipt: receipt)",
            "lastDiagnostic = Self.diagnostic(error, fallback: \"Candidate advertisement mapping failed.\")",
        ] {
            #expect(guardOffset < (try Self.offset(of: mutation, in: body)))
        }
    }

    @Test
    func discoveryAdmissionRequiresRequestIntentAndCurrentManagerScanState() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    public func centralManager(\n        _ central: CBCentralManager,\n        didDiscover peripheral: CBPeripheral,",
            to: "    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)"
        )

        let admissionOffset = try Self.offset(
            of: "guard PassiveCoreBluetoothDiscoveryAdmissionPolicy.accepts(",
            in: body
        )
        let managerIdentityOffset = try Self.offset(
            of: "callbackIsFromActiveManager: central === centralManager",
            in: body
        )
        let poweredOnOffset = try Self.offset(
            of: "isPoweredOn: central.state == .poweredOn",
            in: body
        )
        let currentScanOffset = try Self.offset(
            of: "isScanning: scanRequested && central.isScanning",
            in: body
        )
        let horizonMutationGuardOffset = try Self.offset(
            of: "guard !observationBoundaryBlocksArtifactMutation else { return }",
            in: body
        )
        let receiptOffset = try Self.offset(of: "let receipt = callbackReceipt()", in: body)
        let candidateMutationOffset = try Self.offset(
            of: "peripheralByIdentifier[peripheral.identifier] = peripheral",
            in: body
        )

        #expect(admissionOffset < managerIdentityOffset)
        #expect(managerIdentityOffset < poweredOnOffset)
        #expect(poweredOnOffset < currentScanOffset)
        #expect(currentScanOffset < horizonMutationGuardOffset)
        #expect(horizonMutationGuardOffset < receiptOffset)
        #expect(horizonMutationGuardOffset < candidateMutationOffset)
    }

    @Test
    func scanStateSeparatesRequestIntentFromFrameworkCurrentness() throws {
        let source = try Self.controllerSource()
        #expect(source.contains("private var scanRequested = false"))
        #expect(source.contains("public var isScanRequested: Bool"))
        #expect(source.contains("scanRequested && centralManager?.isScanning == true"))
        #expect(!source.contains("isScanning = true"))
        #expect(!source.contains("isScanning = false"))

        let scanControls = try Self.section(
            in: source,
            from: "    public func startScanning(captureAdvertisementCadence: Bool = false) throws {",
            to: "    /// Explicitly selects the observed peripheral"
        )
        let requestOffset = try Self.offset(of: "scanRequested = true", in: scanControls)
        let startOffset = try Self.offset(of: "centralManager.scanForPeripherals(", in: scanControls)
        let stopIntentOffset = try Self.offset(of: "scanRequested = false", in: scanControls)
        let stopTransportOffset = try Self.offset(of: "centralManager.stopScan()", in: scanControls)
        #expect(requestOffset < startOffset)
        #expect(startOffset < stopIntentOffset)
        #expect(stopIntentOffset < stopTransportOffset)

        let centralState = try Self.section(
            in: source,
            from: "    public func centralManagerDidUpdateState(_ central: CBCentralManager) {",
            to: "    public func centralManager(\n        _ central: CBCentralManager,\n        didDiscover peripheral: CBPeripheral,"
        )
        let clearIntentOffset = try Self.offset(of: "scanRequested = false", in: centralState)
        let frameworkStateOffset = try Self.offset(of: "if central.isScanning {", in: centralState)
        #expect(clearIntentOffset < frameworkStateOffset)
    }

    @Test
    func researchUIUsesIntentForControlsAndLiveStateForPresentation() throws {
        let source = try Self.researchViewSource()
        #expect(source.contains(".disabled(controller.isScanRequested || artifactInteractionLocked)"))
        #expect(source.contains("Button(controller.isScanRequested ? \"Stop scan\" : \"Start scan\")"))
        #expect(source.contains("if controller.isScanRequested {"))
        #expect(source.contains("if controller.isScanning {\n            return \"Scanning…\""))
        #expect(source.contains("if controller.isScanRequested {\n            return \"Scan requested — not active\""))
    }

    @Test
    func cancellationCallGraphKeepsEvidenceBoundaryBeforeOrdinaryRetirement() throws {
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

        let closingStart = try #require(body.range(of: "if observationBoundaryBlocksArtifactMutation {")?.lowerBound)
        let ordinaryStart = try #require(
            body.range(
                of: "if targetState.selectedTargetIdentifier == peripheral.identifier {",
                range: closingStart..<body.endIndex
            )?.lowerBound
        )
        let closing = body[closingStart..<ordinaryStart]
        #expect(!closing.contains("enqueueInterruption"))
        let closingRetirementOffset = try Self.offset(of: "_ = targetState.retireActiveAttempt()", in: closing)
        let closingTransportOffset = try Self.offset(of: "centralManager.cancelPeripheralConnection(peripheral)", in: closing)
        #expect(closingRetirementOffset < closingTransportOffset)

        let ordinary = body[ordinaryStart..<body.endIndex]
        let interruptionOffset = try Self.offset(
            of: "if let interruptionReason = cause.interruptionReason {",
            in: ordinary
        )
        let pendingOffset = try Self.offset(
            of: "selectedTargetCancellationPending = true",
            in: ordinary
        )
        let authorityOffset = try Self.offset(
            of: "guard advanceArtifactAuthority() else { return }",
            in: ordinary
        )
        let retirementOffset = try Self.offset(
            of: "_ = targetState.retireActiveAttempt()",
            in: ordinary
        )
        let transportCancelOffset = try Self.offset(
            of: "centralManager.cancelPeripheralConnection(peripheral)",
            in: ordinary
        )

        #expect(interruptionOffset < pendingOffset)
        #expect(pendingOffset < authorityOffset)
        #expect(authorityOffset < retirementOffset)
        #expect(retirementOffset < transportCancelOffset)
    }

    @Test
    func finalizedTeardownRequiresFrozenCurrentAuthorityAndAuthorityChangesRevokeIt() throws {
        let source = try Self.controllerSource()
        let teardown = try Self.section(
            in: source,
            from: "    public func teardownActiveConnectionAfterFinalization() throws {",
            to: "    private func cancelActiveConnection(cause:"
        )
        let terminalOffset = try Self.offset(
            of: "guard observationBoundaryQueueGate.isTerminal else {",
            in: teardown
        )
        let authorizationOffset = try Self.offset(
            of: "guard let finalizedAuthority = lastFinalizedArtifactAuthority,",
            in: teardown
        )
        let transportOffset = try Self.offset(
            of: "cancelActiveConnection(cause: .finalizedArtifactTeardown)",
            in: teardown
        )
        #expect(terminalOffset < authorizationOffset)
        #expect(authorizationOffset < transportOffset)

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
        let fenceOffset = try Self.offset(
            of: "try artifactAuthorityFence.transition(",
            in: authorityAdvance
        )
        let generationOffset = try Self.offset(
            of: "artifactAuthorityGeneration = nextAuthority.authorityGeneration",
            in: authorityAdvance
        )
        let revokeOffset = try Self.offset(
            of: "lastFinalizedArtifactAuthority = nil",
            in: authorityAdvance
        )
        #expect(fenceOffset < generationOffset)
        #expect(generationOffset < revokeOffset)
        let synchronousPublication = authorityAdvance[
            authorityAdvance.index(authorityAdvance.startIndex, offsetBy: fenceOffset)..<
            authorityAdvance.index(authorityAdvance.startIndex, offsetBy: revokeOffset)
        ]
        #expect(!synchronousPublication.contains("await "))
    }

    @Test
    func finalizedTeardownQuarantineRejectsMarkersBeforeTerminalCallback() throws {
        let source = try Self.controllerSource()

        let artifactReads = try Self.section(
            in: source,
            from: "    public func captureSnapshot() async throws -> PassiveBluetoothCaptureSession {",
            to: "    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {"
        )
        #expect(artifactReads.contains("lastFinalizedArtifactAuthority = context.authority"))

        let teardown = try Self.section(
            in: source,
            from: "    public func teardownActiveConnectionAfterFinalization() throws {",
            to: "    private func cancelActiveConnection(cause:"
        )
        let finalizationAuthorizationOffset = try Self.offset(
            of: "guard let finalizedAuthority = lastFinalizedArtifactAuthority,",
            in: teardown
        )
        let finalizedTeardownOffset = try Self.offset(
            of: "cancelActiveConnection(cause: .finalizedArtifactTeardown)",
            in: teardown
        )
        #expect(finalizationAuthorizationOffset < finalizedTeardownOffset)

        let cancellation = try Self.section(
            in: source,
            from: "    private func cancelActiveConnection(cause:",
            to: "    /// Adds a human-observed stock-app value"
        )
        let ordinaryStart = try #require(
            cancellation.range(of: "if targetState.selectedTargetIdentifier == peripheral.identifier {")?.lowerBound
        )
        let ordinary = cancellation[ordinaryStart..<cancellation.endIndex]
        let pendingOffset = try Self.offset(
            of: "selectedTargetCancellationPending = true",
            in: ordinary
        )
        let retirementOffset = try Self.offset(
            of: "_ = targetState.retireActiveAttempt()",
            in: ordinary
        )
        #expect(pendingOffset < retirementOffset)

        let marker = try Self.section(
            in: source,
            from: "    public func recordStockAppObservation(",
            to: "    public func captureSnapshot() async throws"
        )
        let pendingGuardOffset = try Self.offset(
            of: "!selectedTargetCancellationPending",
            in: marker
        )
        let quarantineGuardOffset = try Self.offset(
            of: "!targetState.isAwaitingTerminalCallback(for: selectedTargetIdentifier)",
            in: marker
        )
        let rejectionOffset = try Self.offset(
            of: "throw ControllerError.peripheralAwaitingTerminalCallback(selectedTargetIdentifier)",
            in: marker
        )
        let observationOffset = try Self.offset(
            of: "let observation = try PassiveBluetoothStockAppObservation(",
            in: marker
        )
        let enqueueOffset = try Self.offset(
            of: "enqueue(.stockAppState(observation))",
            in: marker
        )

        #expect(pendingGuardOffset < observationOffset)
        #expect(quarantineGuardOffset < observationOffset)
        #expect(rejectionOffset < observationOffset)
        #expect(observationOffset < enqueueOffset)
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
