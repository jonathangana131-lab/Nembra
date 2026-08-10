import Foundation

struct NembraCaptureBuildIdentity: Codable, Equatable, Sendable {
    static let buildIdentifierInfoKey = "NembraCaptureBuildIdentifier"
    static let sourceCommitSHAInfoKey = "NembraCaptureSourceCommitSHA"

    let buildIdentifier: String
    let sourceCommitSHA: String

    static var current: Self {
        from(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    static func from(infoDictionary: [String: Any]) -> Self {
        Self(
            buildIdentifier: (infoDictionary[buildIdentifierInfoKey] as? String) ?? "",
            sourceCommitSHA: ((infoDictionary[sourceCommitSHAInfoKey] as? String) ?? "").lowercased()
        )
    }

    var isAuthoritativeFieldBuild: Bool {
        guard sourceCommitSHA.count == 40,
              sourceCommitSHA.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }) else { return false }

        let expectedIdentifier = "Authenticated stationary capture \(sourceCommitSHA.prefix(12))"
        return buildIdentifier == expectedIdentifier
    }

    var blocker: String? {
        guard isAuthoritativeFieldBuild else {
            return "This build has no valid exact Git provenance. Install Capture through the repository field installer before physical evidence collection."
        }
        return nil
    }
}
