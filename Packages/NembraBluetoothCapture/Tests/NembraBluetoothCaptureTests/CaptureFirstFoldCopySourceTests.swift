import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture first-fold copy source contract")
struct CaptureFirstFoldCopySourceTests {
    @Test("standalone Capture bundles the compact standard sighted copy")
    func compactStandardCopyIsBundled() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let strings = try readRepositoryFile("NembraApp/Resources/Localizable.strings")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        let heroKey = "Link the Tuya Smart account that owns this scooter. Bluetooth and physical evidence stay locked until the reviewed field build and fresh scooter authority are verified."
        let heroValue = "Link the Tuya Smart account that owns this scooter."
        let readOnlyKey = "This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."
        let readOnlyValue = "Account metadata only. This step does not start Bluetooth or change scooter settings."

        // The resource keys must stay anchored to the exact SwiftUI literals they replace.
        #expect(app.contains("Text(\"Prepare the scooter link\")"))
        #expect(app.contains(heroKey))
        #expect(app.contains(readOnlyKey))

        #expect(strings.contains("\"Prepare the scooter link\" = \"Link this scooter\";"))
        #expect(strings.contains("\"\(heroKey)\" = \"\(heroValue)\";"))
        #expect(strings.contains("\"\(readOnlyKey)\" = \"\(readOnlyValue)\";"))
        #expect(heroValue.count < heroKey.count / 2)
        #expect(readOnlyValue.count < readOnlyKey.count)

        // A copy file that is not in the target bundle is not a product change.
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */"))
        #expect(project.contains("B10000000000000000000008 /* Localizable.strings */"))
        #expect(project.contains("path = NembraApp/Resources/Localizable.strings"))
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */,"))
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
