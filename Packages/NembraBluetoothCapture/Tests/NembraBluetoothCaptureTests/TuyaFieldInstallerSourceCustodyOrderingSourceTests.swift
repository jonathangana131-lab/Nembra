import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field source custody ordering")
struct TuyaFieldInstallerSourceCustodyOrderingSourceTests {
    @Test("exact requested source is canonical and clean before private field admission")
    func exactSourcePrecedesPrivateAdmission() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        guard let input = installer.range(of: "EXPECTED_SOURCE_SHA=\"${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}\""),
              let shape = installer.range(of: "[[ \"$EXPECTED_SOURCE_SHA\" =~ ^[0-9A-Fa-f]{40}$ ]]", range: input.upperBound..<installer.endIndex),
              let normalize = installer.range(of: "EXPECTED_SOURCE_SHA=\"$(printf '%s' \"$EXPECTED_SOURCE_SHA\" | tr '[:upper:]' '[:lower:]')\"", range: shape.upperBound..<installer.endIndex),
              let head = installer.range(of: "SOURCE_SHA=\"$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')\"", range: normalize.upperBound..<installer.endIndex),
              let equality = installer.range(of: "[[ \"$SOURCE_SHA\" == \"$EXPECTED_SOURCE_SHA\" ]]", range: head.upperBound..<installer.endIndex),
              let cleanTree = installer.range(of: "[[ -z \"$(git status --porcelain=v1 --untracked-files=all)\" ]]", range: equality.upperBound..<installer.endIndex),
              let requestedMessage = installer.range(of: "say \"Exact requested Capture source matched: $SOURCE_SHA\"", range: cleanTree.upperBound..<installer.endIndex),
              let privateAdmission = installer.range(of: "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true", range: requestedMessage.upperBound..<installer.endIndex) else {
            Issue.record("The field installer must canonicalize and prove one clean exact requested source before it can admit private intended-device input.")
            throw SourceContractError.sectionMissing
        }

        #expect(input.lowerBound < shape.lowerBound)
        #expect(shape.lowerBound < normalize.lowerBound)
        #expect(normalize.lowerBound < head.lowerBound)
        #expect(head.lowerBound < equality.lowerBound)
        #expect(equality.lowerBound < cleanTree.lowerBound)
        #expect(cleanTree.lowerBound < requestedMessage.lowerBound)
        #expect(requestedMessage.lowerBound < privateAdmission.lowerBound)
        #expect(!installer.contains("Exact accepted Capture source: $SOURCE_SHA"))
        #expect(!installer.contains("Switch to capture/one-time-ble-dump-gpt56 first"))
    }

    @Test("source custody survives private workspace bootstrap build and built-app readback before install")
    func sourceCustodyEnclosesBuildAndReadback() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        guard let initialEquality = installer.range(of: "[[ \"$SOURCE_SHA\" == \"$EXPECTED_SOURCE_SHA\" ]]"),
              let privateAdmission = installer.range(of: "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true", range: initialEquality.upperBound..<installer.endIndex),
              let bootstrap = installer.range(of: "\"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh\"", range: privateAdmission.upperBound..<installer.endIndex),
              let postBootstrapHead = installer.range(of: "Repository HEAD changed during private workspace bootstrap", range: bootstrap.upperBound..<installer.endIndex),
              let postBootstrapTree = installer.range(of: "Private workspace bootstrap changed tracked or unignored accepted-source inputs", range: postBootstrapHead.upperBound..<installer.endIndex),
              let baseline = installer.range(of: "say \"Intended baseline proven: iPhone 12 / iOS $DEVICE_OS_VERSION\"", range: postBootstrapTree.upperBound..<installer.endIndex),
              let buildStage = installer.range(of: "say \"Building SDK-integrated Nembra Capture for the intended iPhone\"", range: baseline.upperBound..<installer.endIndex),
              let postBuildHead = installer.range(of: "Repository HEAD changed while the accepted field build was compiling", range: buildStage.upperBound..<installer.endIndex),
              let postBuildTree = installer.range(of: "Accepted-source inputs changed while the field build was compiling", range: postBuildHead.upperBound..<installer.endIndex),
              let appReadback = installer.range(of: "APP_INFO_PLIST=\"$APP/Info.plist\"", range: postBuildTree.upperBound..<installer.endIndex),
              let builtSource = installer.range(of: "[[ \"$BUILT_SOURCE_SHA\" == \"$SOURCE_SHA\" ]]", range: appReadback.upperBound..<installer.endIndex),
              let install = installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\"", range: builtSource.upperBound..<installer.endIndex) else {
            Issue.record("The field build must remain inside exact-source custody from private bootstrap through built-app provenance readback before installation.")
            throw SourceContractError.sectionMissing
        }

        #expect(initialEquality.lowerBound < privateAdmission.lowerBound)
        #expect(privateAdmission.lowerBound < bootstrap.lowerBound)
        #expect(bootstrap.lowerBound < postBootstrapHead.lowerBound)
        #expect(postBootstrapHead.lowerBound < postBootstrapTree.lowerBound)
        #expect(postBootstrapTree.lowerBound < baseline.lowerBound)
        #expect(baseline.lowerBound < buildStage.lowerBound)
        #expect(buildStage.lowerBound < postBuildHead.lowerBound)
        #expect(postBuildHead.lowerBound < postBuildTree.lowerBound)
        #expect(postBuildTree.lowerBound < appReadback.lowerBound)
        #expect(appReadback.lowerBound < builtSource.lowerBound)
        #expect(builtSource.lowerBound < install.lowerBound)
    }

    @Test("built app identity rendezvous is exact rather than label-only")
    func builtAppIdentityUsesAllThreeExactReadbacks() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let readback = try section(
            in: installer,
            from: "APP_INFO_PLIST=\"$APP/Info.plist\"",
            to: "say \"Installing SDK-integrated Capture on the intended iPhone\""
        )
        let body = String(readback)

        #expect(body.contains("plutil -extract NembraCaptureBuildIdentifier raw -o - \"$APP_INFO_PLIST\""))
        #expect(body.contains("plutil -extract NembraCaptureSourceCommitSHA raw -o - \"$APP_INFO_PLIST\""))
        #expect(body.contains("plutil -extract CFBundleIdentifier raw -o - \"$APP_INFO_PLIST\""))
        #expect(body.contains("[[ \"$BUILT_BUILD_IDENTIFIER\" == \"$BUILD_LABEL\" ]]"))
        #expect(body.contains("[[ \"$BUILT_SOURCE_SHA\" == \"$SOURCE_SHA\" ]]"))
        #expect(body.contains("[[ \"$BUILT_BUNDLE_ID\" == \"$BUNDLE_ID\" ]]"))
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
