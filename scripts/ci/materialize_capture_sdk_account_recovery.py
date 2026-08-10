from pathlib import Path
import subprocess

EXPECTED_PARENT = "5e96004ec565a5a19df8312f64985862a0443cdc"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")

parent = subprocess.check_output(["git", "rev-parse", "HEAD^"], text=True).strip()
if parent != EXPECTED_PARENT:
    raise SystemExit(f"Refusing stale account-recovery materialization: expected parent {EXPECTED_PARENT}, got {parent}")

source = APP.read_text(encoding="utf-8")

signout_marker = """    private func finishLoginSuccess() {\n"""
if source.count(signout_marker) != 1:
    raise SystemExit("OfficialTuyaAccountAuthorizer finishLoginSuccess marker drifted")

signout = r'''    func signOut() {
        guard !busy else { return }
        guard loggedIn || OfficialTuyaFactory.accountLoggedIn else {
            bootstrap()
            return
        }
#if canImport(ThingSmartHomeKit)
        guard let user = ThingSmartUser.sharedInstance() else {
            loggedIn = false
            status = "Tuya SDK user session is unavailable. Restart account setup before Capture."
            return
        }
        busy = true
        status = "Signing out of the current Tuya SDK account…"
        user.loginOut({ [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.verificationCode = ""
                self.codeSent = false
                self.loggedIn = OfficialTuyaFactory.accountLoggedIn
                if self.loggedIn {
                    self.status = "Tuya returned logout success, but the SDK still reports a current account. Capture remains locked; try again or relaunch Capture."
                } else {
                    self.account = ""
                    self.status = "Signed out. Use the Tuya account that owns this scooter."
                }
            }
        }, failure: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                let submittedIdentity = self.account
                self.busy = false
                self.loggedIn = OfficialTuyaFactory.accountLoggedIn
                self.status = "Tuya could not sign out of the current SDK account: \(Self.redactedError(error, submittedIdentity: submittedIdentity))"
            }
        })
#else
        loggedIn = false
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

'''
source = source.replace(signout_marker, signout + signout_marker, 1)

old_recovery = r'''                if test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized) {
                    Button(test.membershipBusy ? "Checking scooter…" : "Verify this scooter") {
                        test.verifySDKMembership()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(test.membershipBusy)
                }
'''
new_recovery = r'''                if test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(test.membershipStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(test.membershipBusy ? "Checking scooter…" : "Verify this scooter") {
                            test.verifySDKMembership()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(test.membershipBusy || sdkAccount.busy)

                        Button("Use a different Tuya account") {
                            sdkAccount.signOut()
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .disabled(test.membershipBusy || sdkAccount.busy)
                        .accessibilityHint("Signs out of the official Tuya SDK account so you can log in with the account that owns this scooter.")
                    }
                }
'''
if source.count(old_recovery) != 1:
    raise SystemExit("Membership recovery surface drifted")
source = source.replace(old_recovery, new_recovery, 1)

# Product/truth guards: account recovery must not mutate Bluetooth or evidence authority.
authorizer_start = source.index("private final class OfficialTuyaAccountAuthorizer: ObservableObject")
authorizer_end = source.index("@MainActor\nprivate struct SecureLinkView: View", authorizer_start)
authorizer = source[authorizer_start:authorizer_end]
for forbidden in ("connectBLE", "writeValue", "publishDps", "markAuthenticated"):
    if forbidden in authorizer:
        raise SystemExit(f"Account authorizer unexpectedly gained scooter/protocol authority: {forbidden}")
for required in (
    "func signOut()",
    "user.loginOut",
    "OfficialTuyaFactory.accountLoggedIn",
    "Use the Tuya account that owns this scooter.",
):
    if required not in authorizer:
        raise SystemExit(f"Account recovery contract missing: {required}")

preflight_start = source.index("private var preflightPanel: some View")
preflight_end = source.index("private var correlationPanel: some View", preflight_start)
preflight = source[preflight_start:preflight_end]
for required in ("test.membershipStatus", "Use a different Tuya account", "sdkAccount.signOut()"):
    if required not in preflight:
        raise SystemExit(f"Preflight recovery contract missing: {required}")

APP.write_text(source, encoding="utf-8")
