import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture-local CoreBluetooth UUID truth")
struct TuyaCaptureLocalUUIDAuthoritySourceTests {
    @Test("C7D09A22 capture-local UUID cannot mint durable target authority")
    func historicalPeripheralUUIDIsDescriptiveOnly() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(
            !app.contains("var likely: Bool { knownID }"),
            Comment(rawValue: "main@b1ac247 canonical physical truth says the C7D09A22 CoreBluetooth UUID is historical capture-local evidence, not durable scooter identity. The final field app must not authorize a target solely because that UUID matches.")
        )
        #expect(
            !app.contains("\"authority\": \"accepted-prior-physical-corebluetooth-uuid\""),
            Comment(rawValue: "Do not export or log the capture-local UUID as accepted durable physical target authority.")
        )
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
}
