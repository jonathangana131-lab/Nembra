#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/Features/Research/TuyaAccountBridge.swift")
source = path.read_text(encoding="utf-8")


def replace_exact(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    source = source.replace(old, new, 1)


replace_exact(
    '''            guard !access.isEmpty, !refresh.isEmpty, !endpoint.isEmpty else {
                throw BridgeError.malformed("Tuya approval succeeded but the account session was incomplete.")
            }
''',
    '''            guard !access.isEmpty, !refresh.isEmpty, !uid.isEmpty, !endpoint.isEmpty else {
                throw BridgeError.malformed("Tuya approval succeeded but the account session was incomplete.")
            }
''',
    "require approved account UID",
)

replace_exact(
    '''        guard let device = selectedDevice else {
            statusMessage = "Choose the scooter first."
            return
        }

        var envelope: [String: Any] = [
''',
    '''        guard let device = selectedDevice else {
            statusMessage = "Choose the scooter first."
            return
        }
        guard let session else {
            redactedExportData = nil
            statusMessage = "The linked Tuya account session is unavailable. Link the account again before exporting metadata."
            return
        }
        let accountUID = session.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else {
            redactedExportData = nil
            statusMessage = "The linked Tuya account identity is unavailable. Link the account again before exporting metadata."
            return
        }

        var envelope: [String: Any] = [
''',
    "snapshot account UID before metadata export",
)

replace_exact(
    '''        if let selectedDeviceMetadata {
            envelope["deviceDetailRedacted"] = Self.redactSecrets(selectedDeviceMetadata)
        }

        do {
            redactedExportData = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
''',
    '''        if let selectedDeviceMetadata {
            envelope["deviceDetailRedacted"] = Self.redactSecrets(selectedDeviceMetadata)
        }

        guard let custodySafeEnvelope = Self.redactAccountUID(envelope, accountUID: accountUID) as? [String: Any] else {
            redactedExportData = nil
            statusMessage = "Could not establish account-identity-safe metadata export custody."
            return
        }

        do {
            redactedExportData = try JSONSerialization.data(withJSONObject: custodySafeEnvelope, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
''',
    "scrub account UID across final envelope",
)

replace_exact(
    '''    private func loadSelectedDeviceDetails(_ device: LinkedDevice, generation: UInt64) async throws {
        async let detailResponse = signedGET(path: "/v1.0/m/life/ha/devices/detail", params: ["devIds": device.id])
''',
    '''    private func loadSelectedDeviceDetails(_ device: LinkedDevice, generation: UInt64) async throws {
        guard let session else { throw BridgeError.notLinked }
        let accountUID = session.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else {
            throw BridgeError.malformed("Tuya account identity is unavailable for metadata custody.")
        }

        async let detailResponse = signedGET(path: "/v1.0/m/life/ha/devices/detail", params: ["devIds": device.id])
''',
    "snapshot account UID before metadata acquisition",
)

replace_exact(
    '''        selectedDeviceMetadata = Self.redactSecrets(rawDetail) as? [String: Any] ?? [:]
        selectedDeviceSpecifications = Self.redactSecrets(specs["result"] as? [String: Any] ?? [:]) as? [String: Any] ?? [:]
        selectedDeviceLocalStrategy = Self.redactSecrets(strategy["result"] as? [String: Any] ?? [:]) as? [String: Any] ?? [:]
''',
    '''        selectedDeviceMetadata = Self.redactAccountUID(
            Self.redactSecrets(rawDetail),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        selectedDeviceSpecifications = Self.redactAccountUID(
            Self.redactSecrets(specs["result"] as? [String: Any] ?? [:]),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        selectedDeviceLocalStrategy = Self.redactAccountUID(
            Self.redactSecrets(strategy["result"] as? [String: Any] ?? [:]),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
''',
    "scrub account UID before opaque metadata UI custody",
)

replace_exact(
    '''        selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]
        prepareRedactedExport()
''',
    '''        selectedDeviceStatus = Self.redactAccountUID(
            Self.redactSecrets(statusMap),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        prepareRedactedExport()
''',
    "scrub account UID before status UI custody",
)

anchor = '''    private static func remoteMessage(_ object: [String: Any]) -> String {
'''
helper = '''    private static func redactAccountUID(_ object: Any, accountUID: String) -> Any {
        let marker = "<redacted-account-uid>"
        if let dictionary = object as? [String: Any] {
            var output: [String: Any] = [:]
            output.reserveCapacity(dictionary.count)
            for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
                let redactedKey = key.replacingOccurrences(
                    of: accountUID,
                    with: marker,
                    options: [.caseInsensitive, .literal]
                )
                let redactedValue = redactAccountUID(value, accountUID: accountUID)
                var custodyKey = redactedKey
                var collisionOrdinal = 2
                while output[custodyKey] != nil {
                    custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"
                    collisionOrdinal += 1
                }
                output[custodyKey] = redactedValue
            }
            return output
        }
        if let array = object as? [Any] {
            return array.map { redactAccountUID($0, accountUID: accountUID) }
        }
        if let string = object as? String {
            return string.replacingOccurrences(
                of: accountUID,
                with: marker,
                options: [.caseInsensitive, .literal]
            )
        }
        return object
    }

'''
replace_exact(anchor, helper + anchor, "add value-bound account UID redactor")

# Fail-closed source assertions.
poll_start = source.index("private func pollApprovalOnce(")
poll_end = source.index("private func scheduleDeviceLoad", poll_start)
poll = source[poll_start:poll_end]
assert "!uid.isEmpty" in poll and "uid: uid" in poll

load_start = source.index("private func loadSelectedDeviceDetails(")
load_end = source.index("private func signedGET(", load_start)
load = source[load_start:load_end]
assert "let accountUID = session.uid.trimmingCharacters" in load
assert load.count("Self.redactAccountUID(") >= 4

export_start = source.index("func prepareRedactedExport()")
export_end = source.index("func resetLink()", export_start)
export = source[export_start:export_end]
assert export.index("let accountUID = session.uid.trimmingCharacters") < export.index("var envelope: [String: Any]")
assert export.index("let custodySafeEnvelope = Self.redactAccountUID(envelope, accountUID: accountUID)") < export.index("JSONSerialization.data(withJSONObject: custodySafeEnvelope")
assert "JSONSerialization.data(withJSONObject: envelope" not in export

redactor_start = source.index("private static func redactAccountUID(")
redactor_end = source.index("private static func remoteMessage", redactor_start)
redactor = source[redactor_start:redactor_end]
for required in (
    "<redacted-account-uid>",
    "options: [.caseInsensitive, .literal]",
    "dictionary.sorted",
    "collisionOrdinal",
    "while output[custodyKey] != nil",
    "redactAccountUID(value, accountUID: accountUID)",
    "array.map { redactAccountUID($0, accountUID: accountUID) }",
):
    assert required in redactor, required
assert 'normalized.contains("uid")' not in redactor

path.write_text(source, encoding="utf-8")
