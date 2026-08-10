import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account bridge async custody")
struct TuyaAccountBridgeAsyncCustodySourceTests {
    @Test("reset retires in-flight account work so stale callbacks cannot resurrect a link")
    func resetInvalidatesAsyncAccountWork() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        // The bridge needs one monotonic attempt generation shared by QR creation,
        // manual approval checks, automatic polling, device refresh and selection.
        #expect(bridge.contains("operationGeneration"))
        #expect(bridge.contains("approvalRequestTask"))
        #expect(bridge.contains("manualApprovalTask"))
        #expect(bridge.contains("deviceLoadTask"))
        #expect(bridge.contains("selectedDeviceTask"))

        let reset = try section(in: bridge, from: "func resetLink()", to: "private func createQRToken")
        #expect(reset.contains("invalidateAsyncOperations()"))

        let invalidation = try section(in: bridge, from: "private func invalidateAsyncOperations()", to: "private func createQRToken")
        #expect(invalidation.contains("operationGeneration &+= 1"))
        #expect(invalidation.contains("approvalRequestTask?.cancel()"))
        #expect(invalidation.contains("manualApprovalTask?.cancel()"))
        #expect(invalidation.contains("pollTask?.cancel()"))
        #expect(invalidation.contains("deviceLoadTask?.cancel()"))
        #expect(invalidation.contains("selectedDeviceTask?.cancel()"))
    }

    @Test("every awaited approval result is fenced by the generation that started it")
    func approvalResultsAreGenerationFenced() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let request = try section(in: bridge, from: "func requestApproval()", to: "func checkApprovalNow()")
        let manual = try section(in: bridge, from: "func checkApprovalNow()", to: "func refreshDevices()")
        let poll = try section(in: bridge, from: "private func pollApprovalOnce", to: "private func loadHomesAndDevices")

        #expect(request.contains("let generation = operationGeneration"))
        #expect(request.contains("approvalRequestTask = Task"))
        #expect(request.contains("generation == operationGeneration"))

        #expect(manual.contains("let generation = operationGeneration"))
        #expect(manual.contains("manualApprovalTask = Task"))

        #expect(poll.contains("generation: UInt64"))
        #expect(poll.contains("generation == operationGeneration"))
        #expect(poll.contains("qrToken == token"))
    }

    @Test("device selection cannot become ready from an older async selection")
    func selectedDeviceResultsAreIdentityFenced() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let selection = try section(in: bridge, from: "func selectDevice(_ device: LinkedDevice)", to: "func prepareRedactedExport()")
        let details = try section(in: bridge, from: "private func loadSelectedDeviceDetails", to: "private func signedGET")

        #expect(selection.contains("selectedDeviceTask?.cancel()"))
        #expect(selection.contains("let generation = operationGeneration"))
        #expect(selection.contains("phase = .loadingDevices"))
        #expect(selection.contains("selectedDeviceTask = Task"))
        #expect(selection.contains("selectedDeviceID == device.id"))

        #expect(details.contains("generation: UInt64"))
        #expect(details.contains("generation == operationGeneration"))
        #expect(details.contains("selectedDeviceID == device.id"))
    }

    @Test("guided root also prevents duplicate approval requests while one is starting")
    func rootSerializesApprovalButton() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = try section(in: app, from: "private struct CaptureP0Root: View", to: "@MainActor\nprivate final class SecureLinkController")
        let body = String(root)

        #expect(body.contains("tuya.requestApproval()"))
        #expect(body.contains(".disabled(tuya.phase == .requestingApproval)"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
