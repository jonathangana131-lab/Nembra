import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture physical field-build stamp verification")
struct TuyaFieldPhysicalBuildStampVerificationSourceTests {
    @Test("installer verifies built iPhone app provenance before installation")
    func builtPhysicalAppStampIsCheckedBeforeInstall() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let preinstall = try section(
            in: installer,
            from: "APP=\"$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app\"",
            to: "say \"Installing SDK-integrated Capture on $DEVICE_NAME\""
        )
        let body = String(preinstall)

        #expect(body.contains("APP_PLIST=\"$APP/Info.plist\""))
        #expect(body.contains("plutil -extract NembraCaptureBuildIdentifier raw -o - \"$APP_PLIST\""))
        #expect(body.contains("plutil -extract NembraCaptureSourceCommitSHA raw -o - \"$APP_PLIST\""))
        #expect(body.contains("[[ \"$BUILT_BUILD_LABEL\" == \"$BUILD_LABEL\" ]]"))
        #expect(body.contains("[[ \"$BUILT_SOURCE_SHA\" == \"$SOURCE_SHA\" ]]"))
        #expect(body.contains("Refusing installation."))
    }

    @Test("stamp verification happens after build and before devicectl install")
    func stampVerificationOwnsThePhysicalInstallBoundary() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        guard let build = installer.range(of: "xcodebuild \\") ,
              let verification = installer.range(of: "BUILT_BUILD_LABEL=", range: build.upperBound..<installer.endIndex),
              let install = installer.range(of: "xcrun devicectl device install app", range: verification.upperBound..<installer.endIndex) else {
            Issue.record("Expected build -> stamp verification -> physical install ordering was not found.")
            throw SourceContractError.sectionMissing
        }

        #expect(build.lowerBound < verification.lowerBound)
        #expect(verification.lowerBound < install.lowerBound)
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}