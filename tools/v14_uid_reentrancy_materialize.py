from pathlib import Path

source_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = source_path.read_text()

guard_old = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
"""
guard_new = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty,
              let driver else {
"""
if source.count(guard_old) != 1:
    raise SystemExit(f"guard seam drifted: {source.count(guard_old)}")
source = source.replace(guard_old, guard_new, 1)

call_old = "var eventDetails = redactedApplicationEventDetails(update)"
call_new = "var eventDetails = redactedApplicationEventDetails(update, verifiedAccountUID: verifiedAccountUID)"
if source.count(call_old) != 1:
    raise SystemExit(f"custody call drifted: {source.count(call_old)}")
source = source.replace(call_old, call_new, 1)

helper_start = source.index("    private func redactedApplicationEventDetails(")
helper_end = source.index("    private func startWatchdog", helper_start)
helper = source[helper_start:helper_end]
old_prefix = """    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {
        guard let accountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountUID.isEmpty else {
            return update
        }

"""
new_prefix = """    private func redactedApplicationEventDetails(
        _ update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
"""
if helper.count(old_prefix) != 1:
    raise SystemExit("helper authority prefix drifted")
helper = helper.replace(old_prefix, new_prefix, 1)
if helper.count("of: accountUID,") != 2:
    raise SystemExit(f"expected two UID replacements, found {helper.count('of: accountUID,')}")
helper = helper.replace("of: accountUID,", "of: verifiedAccountUID,")
assignment = """            redacted[redactedKey] = value.replacingOccurrences(
                of: verifiedAccountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
"""
collision_safe = """            let redactedValue = value.replacingOccurrences(
                of: verifiedAccountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            var uniqueKey = redactedKey
            var collisionSuffix = 2
            while redacted[uniqueKey] != nil {
                uniqueKey = "\\(redactedKey)#\\(collisionSuffix)"
                collisionSuffix += 1
            }
            redacted[uniqueKey] = redactedValue
"""
if helper.count(assignment) != 1:
    raise SystemExit("redacted-key assignment seam drifted")
helper = helper.replace(assignment, collision_safe, 1)
source = source[:helper_start] + helper + source[helper_end:]
source_path.write_text(source)

test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift")
test_source = test_path.read_text()
old_assertions = """        #expect(receiver.contains("redactedApplicationEventDetails(update)"))
        #expect(receiver.contains("membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("value.replacingOccurrences("))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("log(\\"tuya_application_update\\", update"))
"""
new_assertions = """        #expect(receiver.contains("let verifiedAccountUID = membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("redactedApplicationEventDetails(update, verifiedAccountUID: verifiedAccountUID)"))
        #expect(receiver.contains("verifiedAccountUID: String"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("let redactedValue = value.replacingOccurrences("))
        #expect(receiver.contains("while redacted[uniqueKey] != nil"))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("log(\\"tuya_application_update\\", update"))

        let uidSnapshot = try #require(receiver.range(of: "let verifiedAccountUID = membershipAccountUID?.trimmingCharacters"))
        let firstSuspension = try #require(receiver.range(of: "await "))
        #expect(uidSnapshot.lowerBound < firstSuspension.lowerBound)

        let helper = String(try section(in: receiver, from: "private func redactedApplicationEventDetails(", to: "private func startWatchdog"))
        #expect(!helper.contains("membershipAccountUID"))
        #expect(!helper.contains("return update"))
"""
if test_source.count(old_assertions) != 1:
    raise SystemExit("existing UID test assertion seam drifted")
test_source = test_source.replace(old_assertions, new_assertions, 1)
test_path.write_text(test_source)

receiver = source.split("    private func receivedApplicationUpdate(", 1)[1].split("    private func startWatchdog", 1)[0]
if receiver.index("let verifiedAccountUID = membershipAccountUID?.trimmingCharacters") >= receiver.index("await "):
    raise SystemExit("UID snapshot does not precede actor suspension")
if "redactedApplicationEventDetails(update, verifiedAccountUID: verifiedAccountUID)" not in receiver:
    raise SystemExit("immutable UID snapshot is not passed into custody helper")
helper_check = receiver.split("    private func redactedApplicationEventDetails(", 1)[1]
if "membershipAccountUID" in helper_check or "return update" in helper_check:
    raise SystemExit("custody helper still depends on mutable controller UID authority")
if helper_check.count("of: verifiedAccountUID,") != 2:
    raise SystemExit("key/value UID scrub is incomplete")
if "while redacted[uniqueKey] != nil" not in helper_check or "redacted[uniqueKey] = redactedValue" not in helper_check:
    raise SystemExit("redacted-key collision preservation is missing")
