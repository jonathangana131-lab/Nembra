import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account bridge async custody")
struct TuyaAccountBridgeAsyncCustodySourceTests {
    @Test("reset retires in-flight account work so stale callbacks cannot resurrect a link")
    func resetInvalidatesAsyncAccountWork() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

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

    @Test("approval authority is single-flight and every awaited result is generation fenced")
    func approvalResultsAreGenerationFenced() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let request = try section(in: bridge, from: "func requestApproval()", to: "func checkApprovalNow()")
        let manual = try section(in: bridge, from: "func checkApprovalNow()", to: "func refreshDevices()")
        let poll = try section(in: bridge, from: "private func pollApprovalOnce", to: "private func loadHomesAndDevices")

        // Presentation may still receive a second tap before SwiftUI disables the button;
        // the bridge itself is the authority boundary and must reject duplicate admission.
        #expect(request.contains("guard phase != .requestingApproval else { return }"))
        #expect(request.contains("let generation = operationGeneration"))
        #expect(request.contains("approvalRequestTask = Task"))
        #expect(request.contains("generation == operationGeneration"))

        #expect(manual.contains("let generation = operationGeneration"))
        #expect(manual.contains("manualApprovalTask = Task"))

        #expect(poll.contains("generation: UInt64"))
        #expect(poll.contains("generation == operationGeneration"))
        #expect(poll.contains("qrToken == token"))
    }

    @Test("manual approval cannot silently switch to an edited User Code")
    func manualApprovalUsesCodeBoundToQR() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let request = try section(in: bridge, from: "func requestApproval()", to: "func checkApprovalNow()")
        let manual = try section(in: bridge, from: "func checkApprovalNow()", to: "func refreshDevices()")

        #expect(bridge.contains("approvalUserCode"))
        #expect(request.contains("approvalUserCode = normalized"))
        #expect(manual.contains("let boundUserCode = approvalUserCode"))
        #expect(manual.contains("userCode: boundUserCode"))
        #expect(!manual.contains("userCode.trimmingCharacters"))
    }

    @Test("device list and selection publication cannot escape their owning generation or refresh horizon")
    func deviceResultsAreGenerationAndIdentityFenced() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let refresh = try section(in: bridge, from: "func refreshDevices()", to: "func selectDevice(_ device: LinkedDevice)")
        let selection = try section(in: bridge, from: "func selectDevice(_ device: LinkedDevice)", to: "func prepareRedactedExport()")
        let load = try section(in: bridge, from: "private func loadHomesAndDevices", to: "private func loadSelectedDeviceDetails")
        let details = try section(in: bridge, from: "private func loadSelectedDeviceDetails", to: "private func signedGET")

        #expect(refresh.contains("selectedDeviceTask?.cancel()"))
        #expect(refresh.contains("homes = []"))
        #expect(refresh.contains("devices = []"))
        #expect(refresh.contains("phase = .loadingDevices"))
        #expect(refresh.contains("scheduleDeviceLoad(generation: operationGeneration)"))
        let refreshClear = try #require(refresh.range(of: "devices = []"))
        let refreshSchedule = try #require(refresh.range(of: "scheduleDeviceLoad(generation: operationGeneration)"))
        #expect(refreshClear.lowerBound < refreshSchedule.lowerBound)

        #expect(selection.contains("guard devices.contains(where: { $0.id == device.id }) else"))
        #expect(selection.contains("deviceLoadTask?.cancel()"))
        #expect(selection.contains("deviceLoadTask = nil"))
        #expect(selection.contains("selectedDeviceTask?.cancel()"))
        #expect(selection.contains("let generation = operationGeneration"))
        #expect(selection.contains("phase = .loadingDevices"))
        #expect(selection.contains("selectedDeviceTask = Task"))
        #expect(selection.contains("selectedDeviceID == device.id"))
        let membershipFence = try #require(selection.range(of: "guard devices.contains(where: { $0.id == device.id }) else"))
        let listCancel = try #require(selection.range(of: "deviceLoadTask?.cancel()"))
        let selectionTask = try #require(selection.range(of: "selectedDeviceTask = Task"))
        #expect(membershipFence.lowerBound < listCancel.lowerBound)
        #expect(listCancel.lowerBound < selectionTask.lowerBound)

        #expect(load.contains("generation == operationGeneration"))
        #expect(load.contains("session != nil"))
        #expect(details.contains("generation: UInt64"))
        #expect(details.contains("generation == operationGeneration"))
        #expect(details.contains("selectedDeviceID == device.id"))
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
