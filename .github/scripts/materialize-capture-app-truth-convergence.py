from pathlib import Path

app = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = app.read_text(encoding="utf-8")

revoked = """        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false"""
repaired = """        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership must be verified again after Capture leaves the foreground or Secure Link."
        membershipRequestID = UUID()
        membershipBusy = false"""
if source.count(revoked) != 2:
    raise SystemExit(f"expected two view/foreground membership revocation seams, found {source.count(revoked)}")
source = source.replace(revoked, repaired)

transport_guard = """        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        applicationUpdateAdmissionsInFlight += 1"""
transport_repair = """        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }
        guard let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "Verified Tuya account UID authority was unavailable before application evidence could enter custody.",
                kind: "sdk_account_uid_authority_missing_during_observation"
            )
            return
        }
        let custodySafeUpdate = Self.redactingVerifiedAccountUID(verifiedAccountUID, from: update)

        applicationUpdateAdmissionsInFlight += 1"""
if source.count(transport_guard) != 1:
    raise SystemExit("authenticated application transport guard seam did not match exactly once")
source = source.replace(transport_guard, transport_repair, 1)

old_record = "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"
new_record = "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !custodySafeUpdate.isEmpty, for: token)"
if source.count(old_record) != 1:
    raise SystemExit("application ledger admission seam did not match exactly once")
source = source.replace(old_record, new_record, 1)

old_log = """            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })"""
new_log = """            log("tuya_application_update", custodySafeUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })"""
if source.count(old_log) != 1:
    raise SystemExit("untrusted-first application event merge seam did not match exactly once")
source = source.replace(old_log, new_log, 1)

watchdog_marker = "    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {"
helper = """    private static func redactingVerifiedAccountUID(
        _ verifiedAccountUID: String,
        from update: [String: String]
    ) -> [String: String] {
        let marker = "<redacted-account-uid>"
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(update.count)

        for (rawKey, rawValue) in update {
            let key = rawKey.replacingOccurrences(
                of: verifiedAccountUID,
                with: marker,
                options: [.literal]
            )
            let value = rawValue.replacingOccurrences(
                of: verifiedAccountUID,
                with: marker,
                options: [.literal]
            )

            var retainedKey = key
            var collisionIndex = 2
            while sanitized[retainedKey] != nil {
                retainedKey = "\\(key)#\\(collisionIndex)"
                collisionIndex += 1
            }
            sanitized[retainedKey] = value
        }
        return sanitized
    }

"""
if source.count(watchdog_marker) != 1:
    raise SystemExit("startWatchdog insertion seam did not match exactly once")
source = source.replace(watchdog_marker, helper + watchdog_marker, 1)

duplicate = """        "refreshtoken",
        "sessionkey",
        "authkey","""
simplified = """        "refreshtoken",
        "authkey","""
if source.count(duplicate) != 1:
    raise SystemExit("duplicate sessionkey cleanup seam did not match exactly once")
source = source.replace(duplicate, simplified, 1)

app.write_text(source, encoding="utf-8")

status_test = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkViewMembershipStatusRevocationSourceTests.swift")
status_source = status_test.read_text(encoding="utf-8")
insertion_marker = "    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {"
foreground_test = """    @Test("foreground loss cannot retain verified membership copy after revoking account authority")
    func foregroundLossRevokesMembershipStatusWithProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let foreground = String(try section(
            in: source,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))
        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: foreground)
        let statusReset = try requiredOffset(containing: "membershipStatus =", in: foreground)
        let revokeRequest = try requiredOffset(containing: "membershipRequestID = UUID()", in: foreground)
        #expect(clearVerified < statusReset)
        #expect(statusReset < revokeRequest)
        #expect(foreground.lowercased().contains("verif"))
        #expect(!foreground.lowercased().contains("membership verified and leased"))
    }

"""
if status_source.count(insertion_marker) != 1:
    raise SystemExit("membership test insertion seam did not match exactly once")
status_test.write_text(status_source.replace(insertion_marker, foreground_test + insertion_marker, 1), encoding="utf-8")

uid_test = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift")
uid_source = uid_test.read_text(encoding="utf-8")
old_expect = """        #expect(source.contains("<redacted-account-uid>"))
        #expect(!updateAdmission.contains("log(\\"tuya_application_update\\", update.merging(["))"""
new_expect = """        #expect(source.contains("<redacted-account-uid>"))
        #expect(updateAdmission.contains("membershipAccountUID"))
        #expect(updateAdmission.contains("rawKey.replacingOccurrences"))
        #expect(updateAdmission.contains("rawValue.replacingOccurrences"))
        #expect(updateAdmission.contains("custodySafeUpdate.merging(["))
        #expect(!updateAdmission.contains("log(\\"tuya_application_update\\", update.merging(["))"""
if uid_source.count(old_expect) != 1:
    raise SystemExit("account UID RED contract extension seam did not match exactly once")
uid_test.write_text(uid_source.replace(old_expect, new_expect, 1), encoding="utf-8")

final = app.read_text(encoding="utf-8")
assert final.count('membershipStatus = "Exact scooter membership must be verified again after Capture leaves the foreground or Secure Link."') == 2
receiver = final[final.index('private func receivedApplicationUpdate('):final.index('private func startWatchdog')]
assert ') { current, _ in current })' not in receiver
assert 'custodySafeUpdate.merging([' in receiver
assert ') { _, trusted in trusted })' in receiver
assert '<redacted-account-uid>' in receiver
assert 'rawKey.replacingOccurrences' in receiver
assert 'rawValue.replacingOccurrences' in receiver
fragments = final[final.index('private static let secretKeyFragments'):final.index('private static func redactApplicationSecrets')]
assert fragments.count('"sessionkey"') == 1
assert '"uid"' not in fragments
print("current app truth convergence source contract: PASS")
