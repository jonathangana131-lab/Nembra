import Combine
import Foundation
#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit
#endif

/// Passwordless SmartLife App SDK account authorization for the Capture field utility.
///
/// This object deliberately never asks for, persists, logs, or exports a Tuya password, SDK
/// access token, AppSecret, local_key, device key, or BLE session key. The only user-entered
/// secret is the short-lived email verification code, which is cleared after successful login.
@MainActor
final class TuyaSDKAccountAuthorizer: ObservableObject {
    enum Phase: Equatable {
        case unavailable
        case ready
        case sendingCode
        case codeSent
        case authorizing
        case authorized
        case failed
    }

    @Published var email = ""
    @Published var countryCode = ""
    @Published var verificationCode = ""
    @Published private(set) var phase: Phase = .unavailable
    @Published private(set) var message = "Official Tuya SDK account authorization is not ready."

    init() {
        refresh()
    }

    var isAuthorized: Bool {
#if canImport(ThingSmartHomeKit)
        ThingSmartUser.sharedInstance()?.isLogin == true
#else
        false
#endif
    }

    var canSendCode: Bool {
        Self.normalizedEmail(email) != nil && Self.normalizedCountryCode(countryCode) != nil && phase != .sendingCode && phase != .authorizing
    }

    var canAuthorize: Bool {
        canSendCode && !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refresh() {
#if canImport(ThingSmartHomeKit)
        guard startSDKIfConfigured() else {
            phase = .unavailable
            message = "Private Tuya AppKey/AppSecret are not provisioned for this local build."
            return
        }
        if ThingSmartUser.sharedInstance()?.isLogin == true {
            phase = .authorized
            message = "Official Tuya SDK account session is authorized."
        } else {
            phase = .ready
            message = "Authorize the same Tuya account with a one-time email code. Nembra does not need your password."
        }
#else
        phase = .unavailable
        message = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func sendEmailLoginCode() {
#if canImport(ThingSmartHomeKit)
        guard startSDKIfConfigured() else {
            fail("Private Tuya SDK configuration is missing.")
            return
        }
        guard let email = Self.normalizedEmail(email) else {
            fail("Enter the email address used by the Tuya account.")
            return
        }
        guard let countryCode = Self.normalizedCountryCode(countryCode) else {
            fail("Enter the Tuya account country code, for example 1 for the US/Canada.")
            return
        }
        guard let user = ThingSmartUser.sharedInstance() else {
            fail("Tuya SDK user service is unavailable.")
            return
        }

        phase = .sendingCode
        message = "Requesting a one-time Tuya login code…"
        user.sendVerifyCode(withUserName: email, countryCode: countryCode, type: 2) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.phase = .codeSent
                self.message = "Tuya sent the login code. Enter it below to authorize this SDK session."
            }
        } failure: { [weak self] error in
            Task { @MainActor in
                self?.fail("Tuya could not send the login code: \(Self.safeError(error))")
            }
        }
#else
        fail("Official Tuya SmartLife SDK is not compiled into this build.")
#endif
    }

    func authorizeWithEmailCode() {
#if canImport(ThingSmartHomeKit)
        guard startSDKIfConfigured() else {
            fail("Private Tuya SDK configuration is missing.")
            return
        }
        guard let email = Self.normalizedEmail(email), let countryCode = Self.normalizedCountryCode(countryCode) else {
            fail("Email and country code are required.")
            return
        }
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            fail("Enter the one-time verification code from Tuya.")
            return
        }
        guard let user = ThingSmartUser.sharedInstance() else {
            fail("Tuya SDK user service is unavailable.")
            return
        }

        phase = .authorizing
        message = "Authorizing the official Tuya SDK session…"
        user.login(withEmail: email, countryCode: countryCode, code: code) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.verificationCode = ""
                self.phase = .authorized
                self.message = "Official Tuya SDK account session authorized. The stationary secure-link test can now use SDK authority."
            }
        } failure: { [weak self] error in
            Task { @MainActor in
                self?.verificationCode = ""
                self?.fail("Tuya account authorization failed: \(Self.safeError(error))")
            }
        }
#else
        fail("Official Tuya SmartLife SDK is not compiled into this build.")
#endif
    }

#if canImport(ThingSmartHomeKit)
    @discardableResult
    private func startSDKIfConfigured() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let appKey = environment["NEMBRA_TUYA_APP_KEY"], !appKey.isEmpty,
              let appSecret = environment["NEMBRA_TUYA_APP_SECRET"], !appSecret.isEmpty else {
            return false
        }
        ThingSmartSDK.sharedInstance()?.start(withAppKey: appKey, secretKey: appSecret)
        return true
    }
#endif

    private func fail(_ text: String) {
        phase = .failed
        message = text
    }

    private static func normalizedEmail(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.contains("@"), value.contains("."), !value.contains(" ") else { return nil }
        return value
    }

    private static func normalizedCountryCode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : trimmed
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), digits.count <= 4 else { return nil }
        return digits
    }

    private static func safeError(_ error: Error?) -> String {
        guard let error else { return "unknown Tuya SDK error" }
        return error.localizedDescription
    }
}
