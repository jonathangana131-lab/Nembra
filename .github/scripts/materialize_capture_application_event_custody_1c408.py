from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()

old_log = """            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })"""
new_log = """            let exportSafeUpdate = redactedApplicationUpdateForEventCustody(update)
            log("tuya_application_update", exportSafeUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })"""

if source.count(old_log) != 1:
    raise SystemExit(
        f"expected one untrusted-precedence application log, found {source.count(old_log)}"
    )
source = source.replace(old_log, new_log, 1)

marker = "    private func startWatchdog(for token: TuyaReadOnlyConnectionToken) {"
if source.count(marker) != 1:
    raise SystemExit(f"expected one startWatchdog insertion marker, found {source.count(marker)}")

helper = """    private func redactedApplicationUpdateForEventCustody(_ update: [String: String]) -> [String: String] {
        guard let rawAccountUID = membershipAccountUID else { return [:] }
        let accountUID = rawAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else { return [:] }

        var redacted: [String: String] = [:]
        for (key, value) in update {
            var redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )

            if redacted[redactedKey] != nil {
                var suffix = 2
                while redacted["\(redactedKey)#\(suffix)"] != nil {
                    suffix += 1
                }
                redactedKey = "\(redactedKey)#\(suffix)"
            }
            redacted[redactedKey] = redactedValue
        }
        return redacted
    }

"""

source = source.replace(marker, helper + marker, 1)
path.write_text(source)
