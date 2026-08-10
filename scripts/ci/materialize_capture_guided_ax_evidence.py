from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/GuidedCapturePresentationEvidenceSourceTests.swift")
WORKFLOW = Path(".github/workflows/capture-guided-presentation-evidence.yml")

text = APP.read_text(encoding="utf-8")

def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    text = text.replace(old, new, 1)

root_old = '''@main @MainActor
struct NembraCaptureApp: App {
    var body: some Scene {
        WindowGroup { CaptureP0Root().preferredColorScheme(.dark) }
    }
}
'''
root_new = '''#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
private enum NembraCapturePresentationEvidenceState: String {
    case correlationAccessibility
    case observationAccessibility

    static var requested: Self? {
        let arguments = CommandLine.arguments
        guard let marker = arguments.firstIndex(of: "--nembra-capture-presentation-evidence"),
              arguments.indices.contains(marker + 1) else { return nil }
        return Self(rawValue: arguments[marker + 1])
    }
}

@MainActor
private struct NembraCapturePresentationEvidenceRoot: View {
    let state: NembraCapturePresentationEvidenceState

    var body: some View {
        NavigationStack {
            SecureLinkView(presentationEvidence: state)
        }
    }
}
#endif

@main @MainActor
struct NembraCaptureApp: App {
    var body: some Scene {
        WindowGroup {
#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
            if let state = NembraCapturePresentationEvidenceState.requested {
                NembraCapturePresentationEvidenceRoot(state: state)
                    .preferredColorScheme(.dark)
            } else {
                CaptureP0Root().preferredColorScheme(.dark)
            }
#else
            CaptureP0Root().preferredColorScheme(.dark)
#endif
        }
    }
}
'''
replace_once(root_old, root_new, "app fixture root")

init_old = '''    init(device: TuyaAccountBridge.LinkedDevice) {
        deviceID = device.id
        deviceName = device.name
        productID = device.productID
        tuyaUUID = device.uuid
        super.init()
        log("controller_created")
    }
'''
init_new = '''    init(device: TuyaAccountBridge.LinkedDevice) {
        deviceID = device.id
        deviceName = device.name
        productID = device.productID
        tuyaUUID = device.uuid
        super.init()
        log("controller_created")
    }

#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
    init(presentationEvidence state: NembraCapturePresentationEvidenceState) {
        deviceID = "presentation-only-device"
        deviceName = "AOVOPRO ES80"
        productID = "presentation-only-product"
        tuyaUUID = "presentation-only-uuid"
        super.init()
        switch state {
        case .correlationAccessibility:
            phase = .powerOn
            message = "Power the scooter ON, then begin the next passive correlation window."
        case .observationAccessibility:
            phase = .authenticating
            message = "Finalizing the authenticated read-only session before observation begins."
        }
    }
#endif
'''
replace_once(init_old, init_new, "controller fixture init")

view_props_old = '''    private let stageLabels = ["Target", "Secure link", "Observe", "Seal"]

    init(device: TuyaAccountBridge.LinkedDevice) {
        _test = StateObject(wrappedValue: SecureLinkController(device: device))
    }
'''
view_props_new = '''    private let stageLabels = ["Target", "Secure link", "Observe", "Seal"]
#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
    private let presentationEvidenceState: NembraCapturePresentationEvidenceState?
#endif

    init(device: TuyaAccountBridge.LinkedDevice) {
#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
        presentationEvidenceState = nil
#endif
        _test = StateObject(wrappedValue: SecureLinkController(device: device))
    }

#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
    init(presentationEvidence state: NembraCapturePresentationEvidenceState) {
        presentationEvidenceState = state
        _test = StateObject(wrappedValue: SecureLinkController(presentationEvidence: state))
    }
#endif
'''
replace_once(view_props_old, view_props_new, "view fixture init")

task_old = '''        .task {
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
            if loggedIn { test.verifySDKMembership() }
            else { test.invalidateSDKMembership() }
        }
'''
task_new = '''        .task {
#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
            if presentationEvidenceState != nil { return }
#endif
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .onDisappear {
#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
            if presentationEvidenceState == nil {
                test.abandonCorrelationForViewExit()
            }
#else
            test.abandonCorrelationForViewExit()
#endif
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE
            guard presentationEvidenceState == nil else { return }
#endif
            if loggedIn { test.verifySDKMembership() }
            else { test.invalidateSDKMembership() }
        }
'''
replace_once(task_old, task_new, "fixture task isolation")

for required in (
    "membershipRequestID = UUID()",
    "membershipProbe = nil",
    "guard processCorrelationLease != nil || correlationSession != nil else { return }",
    "abandonPackageCorrelation()",
    "private static var officialDriverIssuedForProcess = false",
    "package_correlation_process_claim_rejected",
    "sdk_local_ble_reacquired_during_target_correlation",
    "let appleNickname = credential.fullName?.nickname",
):
    if required not in text:
        raise SystemExit(f"current truth contract missing during fixture composition: {required}")

for forbidden in (
    "ThingSmartBLEManager.sharedInstance().disconnectBLE",
    "publishDps(",
    "queryDps(",
):
    if forbidden in text:
        raise SystemExit(f"presentation fixture must not introduce transport mutation: {forbidden}")

APP.write_text(text, encoding="utf-8")

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture guided presentation evidence isolation")
struct GuidedCapturePresentationEvidenceSourceTests {
    @Test("fixture is compile-time isolated and cannot mint runtime authority")
    func fixtureIsCompileTimeIsolated() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE"))
        #expect(source.contains("--nembra-capture-presentation-evidence"))
        #expect(source.contains("private enum NembraCapturePresentationEvidenceState"))
        #expect(source.contains("case correlationAccessibility"))
        #expect(source.contains("case observationAccessibility"))
        #expect(source.contains("if presentationEvidenceState != nil { return }"))
        #expect(source.contains("guard presentationEvidenceState == nil else { return }"))
    }

    @Test("fixture uses shipped guided panels without scanner or authenticated evidence construction")
    func fixtureUsesShippedPanelsWithoutEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let fixtureInit = String(try section(
            in: source,
            from: "init(presentationEvidence state: NembraCapturePresentationEvidenceState)",
            to: "#endif\n\n    deinit"
        ))
        #expect(fixtureInit.contains("phase = .powerOn"))
        #expect(fixtureInit.contains("phase = .authenticating"))
        #expect(!fixtureInit.contains("PassiveBluetoothPowerCycleObservationSession"))
        #expect(!fixtureInit.contains("beginConnection"))
        #expect(!fixtureInit.contains("markAuthentication"))
        #expect(!fixtureInit.contains("applicationPayloadCount"))
        #expect(!fixtureInit.contains("driver ="))
        #expect(!fixtureInit.contains("exportData"))
    }

    @Test("normal lifecycle truth remains present beside QA-only fixture")
    func normalLifecycleTruthRemainsPresent() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("membershipRequestID = UUID()"))
        #expect(source.contains("guard processCorrelationLease != nil || correlationSession != nil else { return }"))
        #expect(source.contains("private static var officialDriverIssuedForProcess = false"))
        #expect(source.contains("sdk_local_ble_reacquired_during_target_correlation"))
        #expect(!source.contains("ThingSmartBLEManager.sharedInstance().disconnectBLE"))
        #expect(!source.contains("publishDps("))
        #expect(!source.contains("queryDps("))
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
''', encoding="utf-8")

WORKFLOW.parent.mkdir(parents=True, exist_ok=True)
WORKFLOW.write_text(r'''name: Capture Guided Presentation Evidence

on:
  pull_request:
    paths:
      - NembraApp/App/NembraCaptureEntrypoint.swift
      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/GuidedCapturePresentationEvidenceSourceTests.swift
      - .github/workflows/capture-guided-presentation-evidence.yml
  workflow_dispatch:

permissions:
  contents: read

jobs:
  guided-ax-evidence:
    name: Guided AX5 iPhone 12 presentation
    runs-on: xcode-27
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
          persist-credentials: false
          fetch-depth: 2

      - name: Verify exact QA subject and isolation source
        shell: bash
        run: |
          set -euo pipefail
          source_sha="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
          parent_sha="$(git rev-parse HEAD^ | tr '[:upper:]' '[:lower:]')"
          [[ "$source_sha" =~ ^[0-9a-f]{40}$ && "$parent_sha" =~ ^[0-9a-f]{40}$ ]]
          if [[ "${{ github.event_name }}" == "pull_request" ]]; then
            test "$source_sha" = "${{ github.event.pull_request.head.sha }}"
          fi
          test -z "$(git status --porcelain=v1 --untracked-files=all)"
          test "$(git diff --name-only "$parent_sha"...HEAD | wc -l | tr -d ' ')" = 3
          git diff --name-only "$parent_sha"...HEAD | grep -Fxq 'NembraApp/App/NembraCaptureEntrypoint.swift'
          git diff --name-only "$parent_sha"...HEAD | grep -Fxq 'Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/GuidedCapturePresentationEvidenceSourceTests.swift'
          git diff --name-only "$parent_sha"...HEAD | grep -Fxq '.github/workflows/capture-guided-presentation-evidence.yml'
          grep -Fq '#if NEMBRA_CAPTURE_PRESENTATION_EVIDENCE' NembraApp/App/NembraCaptureEntrypoint.swift
          grep -Fq 'if presentationEvidenceState != nil { return }' NembraApp/App/NembraCaptureEntrypoint.swift
          grep -Fq 'phase = .powerOn' NembraApp/App/NembraCaptureEntrypoint.swift
          grep -Fq 'phase = .authenticating' NembraApp/App/NembraCaptureEntrypoint.swift
          printf 'NEMBRA_GUIDED_SOURCE_SHA=%s\nNEMBRA_GUIDED_PRODUCT_PARENT_SHA=%s\n' "$source_sha" "$parent_sha" >> "$GITHUB_ENV"

      - name: Build public presentation-only app
        shell: bash
        run: |
          set -euo pipefail
          procedure='ES80-AUTHENTICATED-STATIONARY-v1'
          label="capture-guided-qa-${NEMBRA_GUIDED_SOURCE_SHA:0:12}"
          rm -rf /tmp/NembraCaptureGuidedDerived
          xcodebuild -project NembraCapture.xcodeproj -scheme 'Nembra Capture' -configuration Debug \
            -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath /tmp/NembraCaptureGuidedDerived CODE_SIGNING_ALLOWED=NO \
            SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) NEMBRA_CAPTURE_PRESENTATION_EVIDENCE' \
            NEMBRA_CAPTURE_BUILD_IDENTIFIER="$label" \
            NEMBRA_CAPTURE_BUILD_COMMIT_SHA="$NEMBRA_GUIDED_SOURCE_SHA" \
            NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="" \
            NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="$procedure" build
          plist='/tmp/NembraCaptureGuidedDerived/Build/Products/Debug-iphonesimulator/Nembra Capture.app/Info.plist'
          test "$(plutil -extract NembraCaptureBuildIdentifier raw -o - "$plist")" = "$label"
          test "$(plutil -extract NembraCaptureSourceCommitSHA raw -o - "$plist")" = "$NEMBRA_GUIDED_SOURCE_SHA"
          test "$(plutil -extract NembraCaptureProcedureIdentifier raw -o - "$plist")" = "$procedure"
          test -z "$(plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$plist" 2>/dev/null || true)"

      - name: Capture guided AX5 states on exact iPhone 12
        shell: bash
        run: |
          set -euo pipefail
          app='/tmp/NembraCaptureGuidedDerived/Build/Products/Debug-iphonesimulator/Nembra Capture.app'
          bundle='com.jonathangana131.nembra.capturelearn'
          out="$RUNNER_TEMP/NembraCaptureGuidedPresentationEvidence"
          mkdir -p "$out/screenshots" "$out/logs"
          runtime="$({ xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; r=json.load(sys.stdin)["runtimes"]; c=[x for x in r if x.get("isAvailable",True) and str(x.get("identifier","")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]; c.sort(key=lambda x: tuple(int(p) for p in str(x.get("version","0")).split(".") if p.isdigit()), reverse=True); print(c[0]["identifier"] if c else "")'; } 2>/dev/null)"
          test -n "$runtime"
          dtype="$({ xcrun simctl list devicetypes -j | /usr/bin/python3 -c 'import json,sys; a=json.load(sys.stdin)["devicetypes"]; print(next((x["identifier"] for x in a if x.get("name")=="iPhone 12"),""))'; } 2>/dev/null)"
          test "$dtype" = 'com.apple.CoreSimulator.SimDeviceType.iPhone-12'
          udid="$(xcrun simctl create "Nembra Guided AX ${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" "$dtype" "$runtime")"
          cleanup() { xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true; xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true; }
          trap cleanup EXIT INT TERM
          xcrun simctl boot "$udid"
          xcrun simctl bootstatus "$udid" -b
          xcrun simctl install "$udid" "$app"
          xcrun simctl ui "$udid" appearance dark
          xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large
          xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 82 --wifiBars 3 --cellularMode active --cellularBars 4 >/dev/null 2>&1 || true

          xcrun simctl launch "$udid" "$bundle" --nembra-capture-presentation-evidence correlationAccessibility > "$out/logs/correlation-launch.log"
          sleep 2
          xcrun simctl io "$udid" screenshot "$out/screenshots/guided-correlation-dark-iphone12-ax5.png"
          test -s "$out/screenshots/guided-correlation-dark-iphone12-ax5.png"
          xcrun simctl terminate "$udid" "$bundle"

          xcrun simctl launch "$udid" "$bundle" --nembra-capture-presentation-evidence observationAccessibility > "$out/logs/observation-launch.log"
          sleep 2
          xcrun simctl io "$udid" screenshot "$out/screenshots/guided-observation-dark-iphone12-ax5.png"
          test -s "$out/screenshots/guided-observation-dark-iphone12-ax5.png"

          corr_sha="$(shasum -a 256 "$out/screenshots/guided-correlation-dark-iphone12-ax5.png" | awk '{print $1}')"
          obs_sha="$(shasum -a 256 "$out/screenshots/guided-observation-dark-iphone12-ax5.png" | awk '{print $1}')"
          /usr/bin/python3 - "$out/NembraCaptureGuidedPresentationEvidence.json" "$NEMBRA_GUIDED_SOURCE_SHA" "$NEMBRA_GUIDED_PRODUCT_PARENT_SHA" "$runtime" "$dtype" "$corr_sha" "$obs_sha" <<'PY'
          import json, sys
          path, source, parent, runtime, dtype, corr, obs = sys.argv[1:]
          record = {
              "schemaVersion": 1,
              "authority": "guided-capture-simulator-presentation-only",
              "sourceCommitSHA": source,
              "productParentSHA": parent,
              "baselineDevice": "iPhone 12",
              "baselineOS": "iOS 27",
              "dynamicType": "Accessibility XXXL",
              "simulatorRuntime": runtime,
              "simulatorDeviceType": dtype,
              "compilerCondition": "NEMBRA_CAPTURE_PRESENTATION_EVIDENCE",
              "presentationFixture": True,
              "privateTuyaDependencyAuthority": False,
              "protocolAuthorityCreated": False,
              "physicalAuthorityCreated": False,
              "visualAcceptanceRequiresHumanReview": True,
              "states": [
                  {"name":"correlationAccessibility","phase":"powerOn","sha256":corr},
                  {"name":"observationAccessibility","phase":"authenticating","sha256":obs},
              ],
          }
          with open(path, "w", encoding="utf-8") as f: json.dump(record, f, indent=2, sort_keys=True); f.write("\n")
          PY

      - name: Upload guided presentation evidence
        uses: actions/upload-artifact@v4
        with:
          name: nembra-capture-guided-presentation-${{ github.event.pull_request.number || github.run_id }}-${{ github.run_attempt }}
          path: ${{ runner.temp }}/NembraCaptureGuidedPresentationEvidence
          if-no-files-found: error
          retention-days: 14
''', encoding="utf-8")
