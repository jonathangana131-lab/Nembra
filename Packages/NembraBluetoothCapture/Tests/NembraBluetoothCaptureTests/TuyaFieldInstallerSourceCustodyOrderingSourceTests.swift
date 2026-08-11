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
              let gitDirectory = installer.range(of: "AUTHORITY_GIT_DIR=\"$ROOT/.git\"", range: normalize.upperBound..<installer.endIndex),
              let authority = installer.range(of: "run_authority_git() {", range: gitDirectory.upperBound..<installer.endIndex),
              let head = installer.range(of: "SOURCE_SHA=\"$(run_authority_git rev-parse --verify 'HEAD^{commit}' | tr '[:upper:]' '[:lower:]')\"", range: authority.upperBound..<installer.endIndex),
              let equality = installer.range(of: "[[ \"$SOURCE_SHA\" == \"$EXPECTED_SOURCE_SHA\" ]]", range: head.upperBound..<installer.endIndex),
              let sourceAudit = installer.range(of: "verify_accepted_checkout_source \"Current checkout is not the exact accepted Capture source.\"", range: equality.upperBound..<installer.endIndex),
              let requestedMessage = installer.range(of: "say \"Exact requested Capture source matched under isolated Git + raw-byte authority: $SOURCE_SHA\"", range: sourceAudit.upperBound..<installer.endIndex),
              let privateAdmission = installer.range(of: "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true", range: requestedMessage.upperBound..<installer.endIndex) else {
            Issue.record("The field installer must canonicalize and prove one clean exact requested source before it can admit private intended-device input.")
            throw SourceContractError.sectionMissing
        }

        #expect(input.lowerBound < shape.lowerBound)
        #expect(shape.lowerBound < normalize.lowerBound)
        #expect(normalize.lowerBound < gitDirectory.lowerBound)
        #expect(gitDirectory.lowerBound < authority.lowerBound)
        #expect(authority.lowerBound < head.lowerBound)
        #expect(head.lowerBound < equality.lowerBound)
        #expect(equality.lowerBound < sourceAudit.lowerBound)
        #expect(sourceAudit.lowerBound < requestedMessage.lowerBound)
        #expect(requestedMessage.lowerBound < privateAdmission.lowerBound)
        #expect(installer.contains("GIT_NO_REPLACE_OBJECTS=1"))
        #expect(installer.contains("GIT_CONFIG_NOSYSTEM=1"))
        #expect(installer.contains("GIT_CONFIG_GLOBAL=/dev/null"))
        #expect(installer.contains("[\"/usr/bin/git\", \"ls-tree\", \"-r\", \"-z\", source_sha]"))
        #expect(installer.contains("raw accepted checkout blob mismatch"))
        #expect(installer.contains("untracked accepted-source path outside field-input allowlist"))
        #expect(!installer.contains("Exact accepted Capture source: $SOURCE_SHA"))
        #expect(!installer.contains("Switch to capture/one-time-ble-dump-gpt56 first"))
    }

    @Test("source custody survives private workspace bootstrap build and built-app readback before install")
    func sourceCustodyEnclosesBuildAndReadback() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        guard let initialAudit = installer.range(of: "verify_accepted_checkout_source \"Current checkout is not the exact accepted Capture source.\""),
              let privateAdmission = installer.range(of: "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true", range: initialAudit.upperBound..<installer.endIndex),
              let bootstrap = installer.range(of: "run_accepted_source_bash \"Scripts/bootstrap_capture_tuya_sdk.sh\"", range: privateAdmission.upperBound..<installer.endIndex),
              let postBootstrapAudit = installer.range(of: "verify_accepted_checkout_source \"Private workspace bootstrap changed accepted-source inputs.\"", range: bootstrap.upperBound..<installer.endIndex),
              let baseline = installer.range(of: "say \"Intended baseline proven: iPhone 12 / iOS $DEVICE_OS_VERSION\"", range: postBootstrapAudit.upperBound..<installer.endIndex),
              let buildStage = installer.range(of: "say \"Building SDK-integrated Nembra Capture for the intended iPhone\"", range: baseline.upperBound..<installer.endIndex),
              let guardedBuild = installer.range(of: "run_accepted_source_python \"$TUYA_BUILD_WINDOW_GUARD_RELATIVE\"", range: buildStage.upperBound..<installer.endIndex),
              let postBuildAudit = installer.range(of: "verify_accepted_checkout_source \"Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart.\"", range: guardedBuild.upperBound..<installer.endIndex),
              let appReadback = installer.range(of: "APP_INFO_PLIST=\"$APP/Info.plist\"", range: postBuildAudit.upperBound..<installer.endIndex),
              let builtSource = installer.range(of: "[[ \"$BUILT_SOURCE_SHA\" == \"$SOURCE_SHA\" ]]", range: appReadback.upperBound..<installer.endIndex),
              let install = installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\"", range: builtSource.upperBound..<installer.endIndex) else {
            Issue.record("The field build must remain inside exact-source custody from private bootstrap through built-app provenance readback before installation.")
            throw SourceContractError.sectionMissing
        }

        #expect(initialAudit.lowerBound < privateAdmission.lowerBound)
        #expect(privateAdmission.lowerBound < bootstrap.lowerBound)
        #expect(bootstrap.lowerBound < postBootstrapAudit.lowerBound)
        #expect(postBootstrapAudit.lowerBound < baseline.lowerBound)
        #expect(baseline.lowerBound < buildStage.lowerBound)
        #expect(buildStage.lowerBound < guardedBuild.lowerBound)
        #expect(guardedBuild.lowerBound < postBuildAudit.lowerBound)
        #expect(postBuildAudit.lowerBound < appReadback.lowerBound)
        #expect(appReadback.lowerBound < builtSource.lowerBound)
        #expect(builtSource.lowerBound < install.lowerBound)
        #expect(installer.contains("run_authority_git show \"$SOURCE_SHA:$relative_path\""))
        #expect(installer.contains("/bin/bash --noprofile --norc -p -c 'source /dev/stdin'"))
        #expect(!installer.contains("\"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh\""))
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
