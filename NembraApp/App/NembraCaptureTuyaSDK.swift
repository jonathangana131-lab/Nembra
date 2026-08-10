import Foundation
import NembraBluetoothCapture
import SwiftUI
#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit
#endif

@MainActor
protocol OfficialTuyaDriver: AnyObject {
    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @escaping ([String: String]) -> Void,
        success: @escaping () -> Void,
        failure: @escaping (String) -> Void
    )
    func isLocallyConnected(uuid: String) -> Bool
}

@MainActor
enum OfficialTuyaFactory {
    private static var didBootstrap = false

    static var compiled: Bool {
#if canImport(ThingSmartHomeKit)
        true
#else
        false
#endif
    }

    static var configured: Bool {
        compiled
            && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_KEY"] ?? "").isEmpty
            && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_SECRET"] ?? "").isEmpty
    }

    @discardableResult
    static func bootstrap() -> Bool {
#if canImport(ThingSmartHomeKit)
        guard configured else { return false }
        if didBootstrap { return true }
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["NEMBRA_TUYA_APP_KEY"], !key.isEmpty,
              let secret = environment["NEMBRA_TUYA_APP_SECRET"], !secret.isEmpty else { return false }
        ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
        didBootstrap = true
        return true
#else
        false
#endif
    }

    static var accountReady: Bool {
#if canImport(ThingSmartHomeKit)
        guard bootstrap() else { return false }
        return ThingSmartUser.sharedInstance()?.isLogin == true
#else
        return false
#endif
    }

    static func make() -> OfficialTuyaDriver? {
#if canImport(ThingSmartHomeKit)
        guard bootstrap(), accountReady else { return nil }
        return SmartLifeDriver()
#else
        return nil
#endif
    }
}

#if canImport(ThingSmartHomeKit)
@MainActor
final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {
    private var device: ThingSmartDevice?
    private var onApplicationUpdate: (([String: String]) -> Void)?

    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @escaping ([String: String]) -> Void,
        success: @escaping () -> Void,
        failure: @escaping (String) -> Void
    ) {
        guard OfficialTuyaFactory.bootstrap() else {
            failure("Private Tuya SDK credentials are missing.")
            return
        }
        self.onApplicationUpdate = onApplicationUpdate
        device = ThingSmartDevice(deviceId: deviceID)
        device?.delegate = self
        ThingSmartBLEManager.sharedInstance().connectBLE(
            withUUID: uuid,
            productKey: productID,
            success: success,
            failure: { error in
                failure("Tuya SmartLife SDK did not establish the BLE session: \(error?.localizedDescription ?? "unknown error")")
            }
        )
    }

    func isLocallyConnected(uuid: String) -> Bool {
        ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid)
    }

    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            sanitized[String(describing: key)] = String(describing: value)
        }
        onApplicationUpdate?(sanitized)
    }
}
#endif

@MainActor
final class OfficialTuyaMembershipResolver {
#if canImport(ThingSmartHomeKit)
    private let homeManager = ThingSmartHomeManager()
    private var retainedHomes: [ThingSmartHome] = []
#endif

    func evaluate(
        expectedDeviceID: String,
        completion: @escaping (TuyaSDKAccountDeviceMembershipGate.Verdict) -> Void
    ) {
#if canImport(ThingSmartHomeKit)
        guard OfficialTuyaFactory.bootstrap(), OfficialTuyaFactory.accountReady else {
            completion(verdict(
                expectedDeviceID: expectedDeviceID,
                isLoggedIn: false,
                homeEnumerationCompleted: false,
                loadedHomeCount: 0,
                ownedDeviceIDs: [],
                sharedDeviceIDs: [],
                homeLoadFailureCount: 0
            ))
            return
        }

        retainedHomes.removeAll()
        homeManager.getHomeList(success: { [weak self] models in
            Task { @MainActor in
                guard let self else { return }
                self.loadHomes(
                    models ?? [],
                    index: 0,
                    expectedDeviceID: expectedDeviceID,
                    ownedDeviceIDs: [],
                    sharedDeviceIDs: [],
                    loadedHomeCount: 0,
                    homeLoadFailureCount: 0,
                    completion: completion
                )
            }
        }, failure: { _ in
            Task { @MainActor in
                completion(self.verdict(
                    expectedDeviceID: expectedDeviceID,
                    isLoggedIn: true,
                    homeEnumerationCompleted: true,
                    loadedHomeCount: 0,
                    ownedDeviceIDs: [],
                    sharedDeviceIDs: [],
                    homeLoadFailureCount: 1
                ))
            }
        })
#else
        completion(verdict(
            expectedDeviceID: expectedDeviceID,
            isLoggedIn: false,
            homeEnumerationCompleted: false,
            loadedHomeCount: 0,
            ownedDeviceIDs: [],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        ))
#endif
    }

    private func verdict(
        expectedDeviceID: String,
        isLoggedIn: Bool,
        homeEnumerationCompleted: Bool,
        loadedHomeCount: Int,
        ownedDeviceIDs: Set<String>,
        sharedDeviceIDs: Set<String>,
        homeLoadFailureCount: Int
    ) -> TuyaSDKAccountDeviceMembershipGate.Verdict {
        TuyaSDKAccountDeviceMembershipGate.verdict(
            expectedDeviceID: expectedDeviceID,
            snapshot: .init(
                isLoggedIn: isLoggedIn,
                homeEnumerationCompleted: homeEnumerationCompleted,
                loadedHomeCount: loadedHomeCount,
                ownedDeviceIDs: ownedDeviceIDs,
                sharedDeviceIDs: sharedDeviceIDs,
                homeLoadFailureCount: homeLoadFailureCount
            )
        )
    }

#if canImport(ThingSmartHomeKit)
    private func loadHomes(
        _ models: [ThingSmartHomeModel],
        index: Int,
        expectedDeviceID: String,
        ownedDeviceIDs: Set<String>,
        sharedDeviceIDs: Set<String>,
        loadedHomeCount: Int,
        homeLoadFailureCount: Int,
        completion: @escaping (TuyaSDKAccountDeviceMembershipGate.Verdict) -> Void
    ) {
        guard index < models.count else {
            let result = verdict(
                expectedDeviceID: expectedDeviceID,
                isLoggedIn: ThingSmartUser.sharedInstance()?.isLogin == true,
                homeEnumerationCompleted: true,
                loadedHomeCount: loadedHomeCount,
                ownedDeviceIDs: ownedDeviceIDs,
                sharedDeviceIDs: sharedDeviceIDs,
                homeLoadFailureCount: homeLoadFailureCount
            )
            retainedHomes.removeAll()
            completion(result)
            return
        }

        let model = models[index]
        guard let home = ThingSmartHome(homeId: model.homeId) else {
            loadHomes(
                models,
                index: index + 1,
                expectedDeviceID: expectedDeviceID,
                ownedDeviceIDs: ownedDeviceIDs,
                sharedDeviceIDs: sharedDeviceIDs,
                loadedHomeCount: loadedHomeCount,
                homeLoadFailureCount: homeLoadFailureCount + 1,
                completion: completion
            )
            return
        }

        retainedHomes.append(home)
        home.getDataWithSuccess({ [weak self, weak home] _ in
            Task { @MainActor in
                guard let self, let home else { return }
                let owned = Set((home.deviceList ?? []).compactMap { $0.devId })
                let shared = Set((home.sharedDeviceList ?? []).compactMap { $0.devId })
                self.loadHomes(
                    models,
                    index: index + 1,
                    expectedDeviceID: expectedDeviceID,
                    ownedDeviceIDs: ownedDeviceIDs.union(owned),
                    sharedDeviceIDs: sharedDeviceIDs.union(shared),
                    loadedHomeCount: loadedHomeCount + 1,
                    homeLoadFailureCount: homeLoadFailureCount,
                    completion: completion
                )
            }
        }, failure: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.loadHomes(
                    models,
                    index: index + 1,
                    expectedDeviceID: expectedDeviceID,
                    ownedDeviceIDs: ownedDeviceIDs,
                    sharedDeviceIDs: sharedDeviceIDs,
                    loadedHomeCount: loadedHomeCount,
                    homeLoadFailureCount: homeLoadFailureCount + 1,
                    completion: completion
                )
            }
        })
    }
#endif
}

@MainActor
final class OfficialTuyaAccountAuthorizer: ObservableObject {
    enum LoginMethod: String, CaseIterable, Identifiable {
        case email = "Email"
        case phone = "Phone"
        var id: String { rawValue }
    }

    @Published var method: LoginMethod = .email
    @Published var countryCode = "1"
    @Published var account = ""
    @Published var verificationCode = ""
    @Published private(set) var status = "Initialize the official Tuya SDK to authorize this Capture build."
    @Published private(set) var codeSent = false
    @Published private(set) var busy = false
    @Published private(set) var authorized = false

    func bootstrap() {
        guard OfficialTuyaFactory.compiled else {
            status = "Official Tuya SmartLife SDK is not compiled into this build."
            authorized = false
            return
        }
        guard OfficialTuyaFactory.configured else {
            status = "Private Tuya AppKey/AppSecret are not provisioned for this build."
            authorized = false
            return
        }
        guard OfficialTuyaFactory.bootstrap() else {
            status = "Tuya SDK initialization failed closed."
            authorized = false
            return
        }
        authorized = OfficialTuyaFactory.accountReady
        status = authorized
            ? "Official Tuya SDK account session is authorized."
            : "SDK initialized. Sign in with a verification code; metadata QR approval does not count as BLE authentication authority."
    }

    func sendCode() {
        bootstrap()
        guard !authorized else { return }
        let identity = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty, !country.isEmpty else {
            status = "Enter the Tuya account and country code first."
            return
        }
#if canImport(ThingSmartHomeKit)
        busy = true
        codeSent = false
        status = "Requesting a Tuya login verification code…"
        let user = ThingSmartUser.sharedInstance()
        let success: () -> Void = { [weak self] in
            Task { @MainActor in
                self?.busy = false
                self?.codeSent = true
                self?.status = "Verification code sent by Tuya. Enter it below to authorize the SDK session."
            }
        }
        let failure: (Error?) -> Void = { [weak self] error in
            Task { @MainActor in
                self?.busy = false
                self?.status = "Tuya could not send the verification code: \(error?.localizedDescription ?? "unknown error")"
            }
        }
        switch method {
        case .email:
            user?.sendVerifyCode(withUserName: identity, countryCode: country, type: 2, success: success, failure: failure)
        case .phone:
            let region = user?.getDefaultRegionWithCountryCode(country) ?? ""
            user?.sendVerifyCode(withUserName: identity, region: region, countryCode: country, type: 2, success: success, failure: failure)
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func login() {
        bootstrap()
        guard !authorized else { return }
        let identity = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty, !country.isEmpty, !code.isEmpty else {
            status = "Enter the account, country code, and Tuya verification code."
            return
        }
#if canImport(ThingSmartHomeKit)
        busy = true
        status = "Authorizing the official Tuya SDK account session…"
        switch method {
        case .email:
            ThingSmartUser.sharedInstance()?.login(
                withEmail: identity,
                countryCode: country,
                code: code,
                success: { [weak self] in Task { @MainActor in self?.finishLoginSuccess() } },
                failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error) } }
            )
        case .phone:
            ThingSmartUser.sharedInstance()?.login(
                withMobile: identity,
                countryCode: country,
                code: code,
                success: { [weak self] in Task { @MainActor in self?.finishLoginSuccess() } },
                failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error) } }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    private func finishLoginSuccess() {
        busy = false
        verificationCode = ""
        authorized = true
        status = "Official Tuya SDK account authorized. Exact scooter membership must still be verified before BLE."
    }

    private func finishLoginFailure(_ error: Error?) {
        busy = false
        verificationCode = ""
        authorized = false
        status = "Tuya SDK login failed: \(error?.localizedDescription ?? "unknown error")"
    }
}
