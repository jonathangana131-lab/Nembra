from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TESTS = (
    ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegritySourceTests.swift",
    ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationUpdateSecretRedactionSourceTests.swift",
    ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaStationaryFailureCopySourceTests.swift",
)

ACTIVATE_OLD = '''    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }
'''

ACTIVATE_NEW = '''    func activateMembershipRequestsForView() {
        // A foreground-integrity failure requires leaving Secure Link before membership admission can reopen.
        guard phase != .failed else { return }
        acceptsViewScopedMembershipRequests = true
    }
'''

FOREGROUND_METHOD = '''    func appDidLoseForeground() {
        // Capture evidence is foreground-only. Close view-scoped admission before revoking every
        // already-issued asynchronous grant so no account callback can mint fresh off-screen work.
        acceptsViewScopedMembershipRequests = false
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

        if processCorrelationLease != nil || correlationSession != nil {
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Relaunch Capture and start a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch Capture before another authenticated attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch Capture before another authenticated attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch Capture before another authenticated attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        Task { @MainActor [self] in
            guard self.currentConnectionToken == token else { return }
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Relaunch Capture before another authenticated attempt; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch Capture before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

'''

DPS_OLD = '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            sanitized[String(describing: key)] = String(describing: value)
        }
        onApplicationUpdate?(sanitized)
    }
'''

DPS_NEW = '''    private static let secretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "seckey", "authkey"]

    private static func normalizedApplicationKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            var output: [String: Any] = [:]
            for (key, value) in dictionary {
                let normalized = normalizedApplicationKey(key)
                if secretKeyFragments.contains(where: normalized.contains) {
                    output[key] = "<redacted>"
                } else {
                    output[key] = redactApplicationSecrets(value)
                }
            }
            return output
        }
        if let dictionary = object as? [AnyHashable: Any] {
            var output: [String: Any] = [:]
            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalized = normalizedApplicationKey(keyString)
                if secretKeyFragments.contains(where: normalized.contains) {
                    output[keyString] = "<redacted>"
                } else {
                    output[keyString] = redactApplicationSecrets(value)
                }
            }
            return output
        }
        if let array = object as? [Any] { return array.map(redactApplicationSecrets) }
        return object
    }

    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalized = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: normalized.contains) {
                sanitized[keyString] = "<redacted>"
            } else {
                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))
            }
        }
        onApplicationUpdate?(sanitized)
    }
'''

COPY_REPLACEMENTS = {
    "Source authority changed while canonical acceptance was sealing. Restart from OFF1; the sealed package chronology is diagnostic only.":
        "Source authority changed while canonical acceptance was sealing. Relaunch Capture before a new stationary read-only attempt; the sealed package chronology is diagnostic only.",
    "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Restart from OFF1; no disconnect time is inferred.":
        "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
    "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Restart from OFF1; no disconnect time is inferred.":
        "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
    "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture.":
        "Authenticated session produced no application update before the observation deadline. Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
    "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture.":
        "Tuya's current local-BLE session ended before acceptance. Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
    "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Restart from OFF1 rather than rebuilding accepted evidence from mutable post-seal state.":
        "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Relaunch Capture before a new stationary read-only attempt; do not rebuild accepted evidence from mutable post-seal state.",
}

SCENE_ENV_OLD = '''    @State private var showEngineeringDetails = false
    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize
'''
SCENE_ENV_NEW = '''    @State private var showEngineeringDetails = false
    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\\.scenePhase) private var scenePhase
'''

SCENE_HANDLER_OLD = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''
SCENE_HANDLER_NEW = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                test.appDidLoseForeground()
            } else {
                test.activateMembershipRequestsForView()
                if sdkAccount.loggedIn { test.verifySDKMembership() }
            }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''


def replace_exact(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one old block, found {count}")
    return source.replace(old, new, 1)


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "func appDidLoseForeground()" in source:
        raise SystemExit("foreground-integrity method already exists; re-inspect the live product")
    if "private static func redactApplicationSecrets(_ object: Any) -> Any" in source:
        raise SystemExit("application secret redaction already exists; re-inspect the live product")

    source = replace_exact(source, ACTIVATE_OLD, ACTIVATE_NEW, "membership admission activation")
    marker = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
    if source.count(marker) != 1:
        raise SystemExit(f"foreground insertion marker changed: found {source.count(marker)}")
    source = source.replace(marker, FOREGROUND_METHOD + marker, 1)
    source = replace_exact(source, DPS_OLD, DPS_NEW, "SmartLife dpsUpdate boundary")
    source = replace_exact(source, SCENE_ENV_OLD, SCENE_ENV_NEW, "Secure Link scene environment")
    source = replace_exact(source, SCENE_HANDLER_OLD, SCENE_HANDLER_NEW, "Secure Link scene handler")

    for old, new in COPY_REPLACEMENTS.items():
        source = replace_exact(source, old, new, f"stationary recovery copy: {old[:40]}")

    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    required = (
        "func appDidLoseForeground()",
        "acceptsViewScopedMembershipRequests = false",
        "Task { @MainActor [self] in",
        "@Environment(\\.scenePhase) private var scenePhase",
        ".onChange(of: scenePhase)",
        "private static func redactApplicationSecrets(_ object: Any) -> Any",
        "String(describing: Self.redactApplicationSecrets(value))",
        'sanitized[keyString] = "<redacted>"',
        "Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"required convergence token missing: {token}")

    forbidden = (
        "sanitized[String(describing: key)] = String(describing: value)",
        "do not repeat the ride capture",
        "do not repeat the outdoor ride capture",
        "Source authority changed while canonical acceptance was sealing. Restart from OFF1",
        "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Restart from OFF1",
        "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Restart from OFF1",
        "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Restart from OFF1",
    )
    for token in forbidden:
        if token in source:
            raise SystemExit(f"forbidden stale convergence token remains: {token}")

    start = source.index("func appDidLoseForeground()")
    end = source.index("var privateConfig: Bool", start)
    cleanup = source[start:end]
    if "Task { @MainActor [weak self]" in cleanup:
        raise SystemExit("foreground terminal retirement still depends on weak controller lifetime")
    if "disconnectBLE(" in cleanup or "endConnection(" in cleanup or "recordObservedTransportLoss" in cleanup:
        raise SystemExit("foreground loss must not be promoted into transport-loss authority")

    for test in TESTS:
        if not test.exists():
            raise SystemExit(f"required source regression missing: {test.relative_to(ROOT)}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
