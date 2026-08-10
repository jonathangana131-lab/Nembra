from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "private func redactVerifiedAccountUIDFromApplicationUpdate(" in source:
        raise SystemExit("verified account UID application scrubber already present")

    receiver_marker = "    private func receivedApplicationUpdate(\n"
    if source.count(receiver_marker) != 1:
        raise SystemExit(f"application receiver marker count changed: {source.count(receiver_marker)}")

    helper = """    private func redactVerifiedAccountUIDFromApplicationUpdate(
        _ update: [String: String]
    ) -> [String: String] {
        guard let accountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountUID.isEmpty else { return update }

        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(update.count)
        let orderedEntries = update.sorted { lhs, rhs in lhs.key < rhs.key }

        for (index, entry) in orderedEntries.enumerated() {
            let keyContainsAccountUID = entry.key.range(of: accountUID, options: [.caseInsensitive]) != nil
            let baseKey = keyContainsAccountUID
                ? \"<redacted-account-uid-key-\\(index)>\"
                : entry.key
            var sanitizedKey = baseKey
            var collisionIndex = 0
            while sanitized[sanitizedKey] != nil {
                collisionIndex += 1
                sanitizedKey = \"\\(baseKey)-collision-\\(collisionIndex)\"
            }

            sanitized[sanitizedKey] = entry.value.replacingOccurrences(
                of: accountUID,
                with: \"<redacted-account-uid>\",
                options: [.caseInsensitive]
            )
        }
        return sanitized
    }

"""
    source = source.replace(receiver_marker, helper + receiver_marker, 1)

    receiver_start = source.index(receiver_marker)
    receiver_end = source.index("    private func startWatchdog", receiver_start)
    receiver = source[receiver_start:receiver_end]

    insertion_old = """        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
"""
    insertion_new = """        let sanitizedUpdate = redactVerifiedAccountUIDFromApplicationUpdate(update)
        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
"""
    if receiver.count(insertion_old) != 1:
        raise SystemExit(f"sanitization insertion target count changed: {receiver.count(insertion_old)}")
    receiver = receiver.replace(insertion_old, insertion_new, 1)

    log_old = "log(\"tuya_application_update\", update.merging(["
    log_new = "log(\"tuya_application_update\", sanitizedUpdate.merging(["
    if receiver.count(log_old) != 1:
        raise SystemExit(f"raw application event custody target count changed: {receiver.count(log_old)}")
    receiver = receiver.replace(log_old, log_new, 1)
    source = source[:receiver_start] + receiver + source[receiver_end:]

    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    helper_start = source.index("    private func redactVerifiedAccountUIDFromApplicationUpdate(")
    receiver_start = source.index("    private func receivedApplicationUpdate(", helper_start)
    receiver_end = source.index("    private func startWatchdog", receiver_start)
    helper = source[helper_start:receiver_start]
    receiver = source[receiver_start:receiver_end]

    required_helper = (
        "membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)",
        "entry.key.range(of: accountUID, options: [.caseInsensitive])",
        "<redacted-account-uid-key-",
        "entry.value.replacingOccurrences(",
        "with: \"<redacted-account-uid>\"",
        "options: [.caseInsensitive]",
    )
    for token in required_helper:
        if token not in helper:
            raise SystemExit(f"account UID scrubber missing: {token}")

    if "redactVerifiedAccountUIDFromApplicationUpdate(update)" not in receiver:
        raise SystemExit("application receiver does not invoke account UID scrubber")
    if "log(\"tuya_application_update\", sanitizedUpdate.merging([" not in receiver:
        raise SystemExit("application event does not use sanitized update")
    if "log(\"tuya_application_update\", update.merging([" in receiver:
        raise SystemExit("raw application update still enters immutable event custody")
    if "]) { _, trusted in trusted })" not in receiver:
        raise SystemExit("trusted Nembra generation precedence was lost")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
