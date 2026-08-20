import CryptoKit
import Foundation

public extension AuthenticatedStationaryCaptureInstallManifest {
    /// Verifies that the exact authorization-envelope bytes presented to the running app are the
    /// same bounded bytes cross-bound by the retained-install manifest.
    ///
    /// This is evidence matching only. It does not validate the envelope signature, mint physical
    /// authority, consume replay state, or weaken the independently pinned trust-root requirement.
    func matchesAuthorizationEnvelope(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= AuthenticatedStationaryCaptureFieldAuthorizationVerifier.maximumEnvelopeByteCount else {
            return false
        }

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return digest == authorizationEnvelopeSHA256
    }
}
