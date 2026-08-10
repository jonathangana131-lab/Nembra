import Foundation

extension TuyaSecureLinkPreflightModel {
    enum TuyaCaptureCredentialStore {
        static func load() -> TuyaCaptureCredential? {
            TuyaCaptureCredentialVault.load()
        }
    }
}
