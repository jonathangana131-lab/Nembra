import Foundation

struct NembraCaptureBuildIdentity: Codable, Equatable, Sendable {
    static let buildIdentifierInfoKey = "NembraCaptureBuildIdentifier"
    static let sourceCommitSHAInfoKey = "NembraCaptureSourceCommitSHA"
    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"
    static let fieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"

    let buildIdentifier: String
    let sourceCommitSHA: String
    let tuyaDependencyLockSHA256: String

    static var current: Self {
        from(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    static func from(infoDictionary: [String: Any]) -> Self {
        Self(
            buildIdentifier: (infoDictionary[buildIdentifierInfoKey] as? String) ?? "",
            sourceCommitSHA: ((infoDictionary[sourceCommitSHAInfoKey] as? String) ?? "").lowercased(),
            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased()
        )
    }

    var isAuthoritativeFieldBuild: Bool {
        guard sourceCommitSHA.count == 40,
              sourceCommitSHA.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }),
              tuyaDependencyLockSHA256.count == 64,
              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }) else { return false }

        let expectedIdentifier = "capture-v14-\(sourceCommitSHA.prefix(12))"
        return buildIdentifier == expectedIdentifier
    }

    var blocker: String? {
        guard isAuthoritativeFieldBuild else {
            return "This build has no valid exact Git + reviewed Tuya dependency provenance. Install Capture through the repository field installer before physical evidence collection."
        }
        return nil
    }
}
