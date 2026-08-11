#!/usr/bin/env python3
from pathlib import Path

SOURCE = Path("NembraApp/Features/Research/TuyaAccountBridge.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAccountBridgeTransportSecuritySourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


text = SOURCE.read_text(encoding="utf-8")

text = replace_once(
    text,
    """import UniformTypeIdentifiers

/// Official Tuya Smart account-link preflight for the one-time Nembra Capture utility.
""",
    """import UniformTypeIdentifiers

private final class TuyaHTTPSOnlyRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// Official Tuya Smart account-link preflight for the one-time Nembra Capture utility.
""",
    "redirect delegate insertion",
)

text = replace_once(
    text,
    """            let rawEndpoint = result["endpoint"] as? String ?? ""
            let endpoint = rawEndpoint.hasPrefix("http") ? rawEndpoint : "https://\\(rawEndpoint)"
            guard !access.isEmpty, !refresh.isEmpty, !uid.isEmpty, !endpoint.isEmpty else {
                throw BridgeError.malformed("Tuya approval succeeded but the account session was incomplete.")
            }
""",
    """            let rawEndpoint = result["endpoint"] as? String ?? ""
            guard !access.isEmpty, !refresh.isEmpty, !uid.isEmpty else {
                throw BridgeError.malformed("Tuya approval succeeded but the account session was incomplete.")
            }
            guard let endpoint = Self.normalizedAuthenticatedEndpoint(rawEndpoint) else {
                throw BridgeError.malformed("Tuya approval returned an insecure account endpoint.")
            }
""",
    "approval endpoint admission",
)

text = replace_once(
    text,
    """        var endpoint = session.endpoint
        while endpoint.hasSuffix("/") { endpoint.removeLast() }
        guard var components = URLComponents(string: endpoint + path) else { throw BridgeError.invalidURL }
""",
    """        guard let endpoint = Self.normalizedAuthenticatedEndpoint(session.endpoint) else {
            throw BridgeError.invalidURL
        }
        guard var components = URLComponents(string: endpoint + path) else { throw BridgeError.invalidURL }
""",
    "signed endpoint revalidation",
)

text = replace_once(
    text,
    """    private static func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
""",
    """    private static func normalizedAuthenticatedEndpoint(_ rawEndpoint: String) -> String? {
        let trimmed = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\\(trimmed)"
        guard let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url else { return nil }
        var normalized = url.absoluteString
        while normalized.hasSuffix("/") { normalized.removeLast() }
        return normalized
    }

    private static func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        guard let requestURL = request.url,
              requestURL.scheme?.lowercased() == "https",
              let requestHost = requestURL.host,
              !requestHost.isEmpty else {
            throw BridgeError.invalidURL
        }
        let redirectDelegate = TuyaHTTPSOnlyRedirectDelegate()
        let (data, response) = try await URLSession.shared.data(for: request, delegate: redirectDelegate)
""",
    "request transport fence",
)

SOURCE.write_text(text, encoding="utf-8")

test = TEST.read_text(encoding="utf-8")
required_source = (
    "private final class TuyaHTTPSOnlyRedirectDelegate",
    'url.scheme?.lowercased() == "https"',
    "completionHandler(nil)",
    "guard let endpoint = Self.normalizedAuthenticatedEndpoint(rawEndpoint) else",
    "guard let endpoint = Self.normalizedAuthenticatedEndpoint(session.endpoint) else",
    "private static func normalizedAuthenticatedEndpoint",
    'components.scheme?.lowercased() == "https"',
    "components.user == nil",
    "components.password == nil",
    'requestURL.scheme?.lowercased() == "https"',
    "URLSession.shared.data(for: request, delegate: redirectDelegate)",
)
for sentinel in required_source:
    if sentinel not in text:
        raise SystemExit(f"missing HTTPS source sentinel: {sentinel}")
if 'rawEndpoint.hasPrefix("http")' in text:
    raise SystemExit("legacy prefix-based endpoint admission remains")
if "URLSession.shared.data(for: request)" in text:
    raise SystemExit("authenticated request path can bypass redirect delegate")
if "approvalEndpointRejectsPlaintextTransport" not in test:
    raise SystemExit("plaintext-endpoint regression test is missing")
if "authenticatedRequestsRejectTransportDowngrade" not in test:
    raise SystemExit("redirect-downgrade regression test is missing")
