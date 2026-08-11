import CoreImage
import CoreImage.CIFilterBuiltins
import CoreTransferable
import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Official Tuya Smart account-link preflight for the one-time Nembra Capture utility.
///
/// This deliberately does NOT send scooter commands. It uses Tuya's QR account authorization
/// and read-only Device Sharing endpoints to collect the device's cloud metadata, current status,
/// and specifications before the next Bluetooth experiment.
private final class TuyaAccountBridgeNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Authenticated Tuya headers are never replayed across redirects. A redirect is
        // returned to requestJSON as the original 3xx response and therefore fails closed.
        completionHandler(nil)
    }
}

@MainActor
final class TuyaAccountBridge: ObservableObject {
    struct LinkedDevice: Identifiable, Equatable {
        let id: String
        let name: String
        let category: String
        let productID: String
        let productName: String
        let uuid: String
        let assetID: String
        let online: Bool

        static func == (lhs: LinkedDevice, rhs: LinkedDevice) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.online == rhs.online
        }
    }

    struct Home: Identifiable, Equatable {
        let id: String
        let name: String
    }

    enum Phase: Equatable {
        case needsUserCode
        case requestingApproval
        case waitingForApproval
        case loadingDevices
        case ready
        case failed
    }

    private struct Session {
        let userCode: String
        let accessToken: String
        let refreshToken: String
        let uid: String
        let endpoint: String
        let terminalID: String
        let issuedAtMilliseconds: Int64
        let expiresInSeconds: Int64
    }

    @Published var userCode = ""
    @Published private(set) var phase: Phase = .needsUserCode
    @Published private(set) var statusMessage = "Link your Tuya Smart account first. Nembra only reads device metadata here — it does not change scooter settings."
    @Published private(set) var qrPayload: String?
    @Published private(set) var qrPNGData: Data?
    @Published private(set) var homes: [Home] = []
    @Published private(set) var devices: [LinkedDevice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var selectedDeviceMetadata: [String: Any]?
    @Published private(set) var selectedDeviceStatus: [String: Any]?
    @Published private(set) var selectedDeviceSpecifications: [String: Any]?
    @Published private(set) var redactedExportData: Data?
    @Published private(set) var redactedExportFilename = "Nembra-Tuya-ReadOnly-Metadata.json"

    private let clientID = "HA_3y9q4ak7g4ephrvke"
    private let schema = "haauthorize"
    private let loginBaseURL = "https://apigw.iotbing.com"
    private var qrToken: String?
    private var approvalUserCode: String?
    private var session: Session?
    private var operationGeneration: UInt64 = 0
    private var approvalRequestTask: Task<Void, Never>?
    private var manualApprovalTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var deviceLoadTask: Task<Void, Never>?
    private var selectedDeviceTask: Task<Void, Never>?

    deinit {
        approvalRequestTask?.cancel()
        manualApprovalTask?.cancel()
        pollTask?.cancel()
        deviceLoadTask?.cancel()
        selectedDeviceTask?.cancel()
    }

    var isLinked: Bool { session != nil }
    var selectedDevice: LinkedDevice? { devices.first(where: { $0.id == selectedDeviceID }) }

    func requestApproval() {
        let normalized = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            phase = .failed
            statusMessage = "Paste the User Code from Tuya Smart → Me → Settings → Account and Security → User Code."
            return
        }
        guard phase != .requestingApproval else { return }

        invalidateAsyncOperations()
        let generation = operationGeneration
        phase = .requestingApproval
        statusMessage = "Creating a private Tuya approval QR…"
        qrPayload = nil
        qrPNGData = nil
        qrToken = nil
        approvalUserCode = nil
        session = nil
        homes = []
        devices = []
        selectedDeviceID = nil
        clearSelectedDeviceDetails()

        approvalRequestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await createQRToken(userCode: normalized)
                guard !Task.isCancelled, generation == operationGeneration else { return }
                qrToken = token
                approvalUserCode = normalized
                let payload = "tuyaSmart--qrLogin?token=\(token)"
                qrPayload = payload
                qrPNGData = Self.makeQRCodePNG(payload)
                phase = .waitingForApproval
                statusMessage = "Approve this QR in Tuya Smart. Nembra will notice automatically when approval finishes."
                startPolling(userCode: normalized, token: token, generation: generation)
            } catch {
                guard !Task.isCancelled, generation == operationGeneration else { return }
                phase = .failed
                statusMessage = "Tuya approval setup failed: \(Self.readable(error))"
            }
        }
    }

    func checkApprovalNow() {
        guard let token = qrToken, let boundUserCode = approvalUserCode else {
            requestApproval()
            return
        }
        manualApprovalTask?.cancel()
        let generation = operationGeneration
        manualApprovalTask = Task { [weak self] in
            guard let self else { return }
            await pollApprovalOnce(userCode: boundUserCode, token: token, generation: generation)
        }
    }

    func refreshDevices() {
        guard session != nil else {
            phase = .failed
            statusMessage = "Tuya is not linked yet."
            return
        }
        selectedDeviceTask?.cancel()
        selectedDeviceTask = nil
        selectedDeviceID = nil
        clearSelectedDeviceDetails()
        homes = []
        devices = []
        phase = .loadingDevices
        statusMessage = "Refreshing the linked Tuya device list…"
        scheduleDeviceLoad(generation: operationGeneration)
    }

    func selectDevice(_ device: LinkedDevice) {
        guard devices.contains(where: { $0.id == device.id }) else {
            selectedDeviceTask?.cancel()
            selectedDeviceTask = nil
            selectedDeviceID = nil
            clearSelectedDeviceDetails()
            phase = .loadingDevices
            statusMessage = "The Tuya device list changed. Wait for refresh to finish, then choose the scooter again."
            return
        }
        deviceLoadTask?.cancel()
        deviceLoadTask = nil
        selectedDeviceTask?.cancel()
        selectedDeviceID = device.id
        clearSelectedDeviceDetails()
        phase = .loadingDevices
        statusMessage = "Reading \(device.name)'s Tuya status and DP definitions…"
        let generation = operationGeneration
        selectedDeviceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await loadSelectedDeviceDetails(device, generation: generation)
                guard !Task.isCancelled,
                      generation == operationGeneration,
                      selectedDeviceID == device.id else { return }
                phase = .ready
                statusMessage = "Tuya metadata is ready. No scooter control command was sent."
            } catch {
                guard !Task.isCancelled,
                      generation == operationGeneration,
                      selectedDeviceID == device.id else { return }
                phase = .failed
                statusMessage = "Device metadata read failed: \(Self.readable(error))"
            }
        }
    }

    func prepareRedactedExport() {
        guard let device = selectedDevice else {
            statusMessage = "Choose the scooter first."
            return
        }
        guard let session else {
            redactedExportData = nil
            statusMessage = "The linked Tuya account session is unavailable. Link the account again before exporting metadata."
            return
        }
        let accountUID = session.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else {
            redactedExportData = nil
            statusMessage = "The linked Tuya account identity is unavailable. Link the account again before exporting metadata."
            return
        }

        var envelope: [String: Any] = [
            "schemaVersion": 1,
            "purpose": "Read-only Tuya Smart metadata for Nembra scooter protocol learning",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "device": [
                "id": device.id,
                "name": device.name,
                "category": device.category,
                "productID": device.productID,
                "productName": device.productName,
                "uuid": device.uuid,
                "assetID": device.assetID,
                "online": device.online
            ],
            "status": Self.redactSecrets(selectedDeviceStatus ?? [:]),
            "specifications": Self.redactSecrets(selectedDeviceSpecifications ?? [:]),
            "safety": [
                "readOnlyCloudCalls": true,
                "localKeyRetained": false,
                "localKeyExported": false,
                "accessTokenExported": false,
                "refreshTokenExported": false,
                "commandsSent": false
            ]
        ]

        if let selectedDeviceMetadata {
            envelope["deviceDetailRedacted"] = Self.redactSecrets(selectedDeviceMetadata)
        }

        guard let custodySafeEnvelope = Self.redactAccountUID(envelope, accountUID: accountUID) as? [String: Any] else {
            redactedExportData = nil
            statusMessage = "Could not establish account-identity-safe metadata export custody."
            return
        }

        do {
            redactedExportData = try JSONSerialization.data(withJSONObject: custodySafeEnvelope, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            redactedExportFilename = "Nembra-Tuya-\(Self.safeFilename(device.name))-Metadata.json"
            statusMessage = "Redacted Tuya metadata is ready to share. Account tokens and local_key are not retained in device UI state or exported."
        } catch {
            statusMessage = "Could not prepare metadata JSON: \(Self.readable(error))"
        }
    }

    func resetLink() {
        invalidateAsyncOperations()
        session = nil
        qrToken = nil
        approvalUserCode = nil
        qrPayload = nil
        qrPNGData = nil
        homes = []
        devices = []
        selectedDeviceID = nil
        clearSelectedDeviceDetails()
        phase = .needsUserCode
        statusMessage = "Tuya link cleared from this Capture session."
    }

    private func invalidateAsyncOperations() {
        operationGeneration &+= 1
        approvalRequestTask?.cancel()
        approvalRequestTask = nil
        manualApprovalTask?.cancel()
        manualApprovalTask = nil
        pollTask?.cancel()
        pollTask = nil
        deviceLoadTask?.cancel()
        deviceLoadTask = nil
        selectedDeviceTask?.cancel()
        selectedDeviceTask = nil
    }

    private func clearSelectedDeviceDetails() {
        selectedDeviceMetadata = nil
        selectedDeviceStatus = nil
        selectedDeviceSpecifications = nil
        redactedExportData = nil
    }

    private func createQRToken(userCode: String) async throws -> String {
        var components = URLComponents(string: "\(loginBaseURL)/v1.0/m/life/home-assistant/qrcode/tokens")!
        components.queryItems = [
            URLQueryItem(name: "clientid", value: clientID),
            URLQueryItem(name: "usercode", value: userCode),
            URLQueryItem(name: "schema", value: schema)
        ]
        guard let url = components.url else { throw BridgeError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        let object = try await Self.requestJSON(request)
        guard Self.bool(object["success"]) else {
            throw BridgeError.remote(Self.remoteMessage(object))
        }
        guard let result = object["result"] as? [String: Any], let token = result["qrcode"] as? String, !token.isEmpty else {
            throw BridgeError.malformed("Tuya did not return a QR token.")
        }
        return token
    }

    private func startPolling(userCode: String, token: String, generation: UInt64) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<90 {
                guard !Task.isCancelled,
                      generation == operationGeneration,
                      qrToken == token,
                      session == nil else { return }
                await pollApprovalOnce(userCode: userCode, token: token, generation: generation)
                if session != nil { return }
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled,
                  generation == operationGeneration,
                  qrToken == token,
                  session == nil else { return }
            phase = .failed
            statusMessage = "Tuya approval timed out. Reset the account link, then create a fresh QR."
        }
    }

    private func pollApprovalOnce(userCode: String, token: String, generation: UInt64) async {
        guard generation == operationGeneration,
              qrToken == token,
              session == nil else { return }
        var approvalSucceeded = false
        do {
            var components = URLComponents(string: "\(loginBaseURL)/v1.0/m/life/home-assistant/qrcode/tokens/\(token)")!
            components.queryItems = [
                URLQueryItem(name: "clientid", value: clientID),
                URLQueryItem(name: "usercode", value: userCode)
            ]
            guard let url = components.url else { throw BridgeError.invalidURL }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            let object = try await Self.requestJSON(request)
            guard !Task.isCancelled,
                  generation == operationGeneration,
                  qrToken == token,
                  session == nil else { return }
            guard Self.bool(object["success"]) else {
                if phase == .waitingForApproval {
                    statusMessage = "Waiting for approval in Tuya Smart…"
                }
                return
            }
            approvalSucceeded = true
            guard let result = object["result"] as? [String: Any] else {
                throw BridgeError.malformed("Tuya approval succeeded but account-session data was missing.")
            }

            let issued = Self.int64(object["t"]) ?? Int64(Date().timeIntervalSince1970 * 1000)
            let access = result["access_token"] as? String ?? ""
            let refresh = result["refresh_token"] as? String ?? ""
            let uid = result["uid"] as? String ?? ""
            let terminal = result["terminal_id"] as? String ?? ""
            let expire = Self.int64(result["expire_time"]) ?? 0
            let rawEndpoint = result["endpoint"] as? String ?? ""
            let endpoint = try Self.normalizedHTTPSAPIEndpoint(rawEndpoint)
            guard !access.isEmpty, !refresh.isEmpty, !uid.isEmpty else {
                throw BridgeError.malformed("Tuya approval succeeded but the account session was incomplete.")
            }
            guard !Task.isCancelled,
                  generation == operationGeneration,
                  qrToken == token,
                  session == nil else { return }

            session = Session(
                userCode: userCode,
                accessToken: access,
                refreshToken: refresh,
                uid: uid,
                endpoint: endpoint,
                terminalID: terminal,
                issuedAtMilliseconds: issued,
                expiresInSeconds: expire
            )
            phase = .loadingDevices
            statusMessage = "Tuya approved. Reading your device list…"
            scheduleDeviceLoad(generation: generation)
            pollTask?.cancel()
            pollTask = nil
            manualApprovalTask?.cancel()
            manualApprovalTask = nil
        } catch {
            guard !Task.isCancelled,
                  generation == operationGeneration,
                  qrToken == token,
                  session == nil else { return }
            if approvalSucceeded {
                // Make every sibling approval callback stale before publishing the terminal.
                invalidateAsyncOperations()
                phase = .failed
                statusMessage = "Tuya approved, but the account session was rejected: \(Self.readable(error)) Reset the account link, then create a fresh QR."
            } else if phase == .waitingForApproval {
                statusMessage = "Still waiting for Tuya approval…"
            }
        }
    }

    private func scheduleDeviceLoad(generation: UInt64) {
        deviceLoadTask?.cancel()
        deviceLoadTask = Task { [weak self] in
            guard let self else { return }
            await loadHomesAndDevices(generation: generation)
        }
    }

    private func loadHomesAndDevices(generation: UInt64) async {
        guard generation == operationGeneration, session != nil else { return }
        phase = .loadingDevices
        do {
            let homeResponse = try await signedGET(path: "/v1.0/m/life/users/homes")
            guard !Task.isCancelled,
                  generation == operationGeneration,
                  session != nil else { return }
            guard let homeArray = homeResponse["result"] as? [[String: Any]] else {
                throw BridgeError.malformed("Tuya returned no homes for this account.")
            }
            let loadedHomes = homeArray.compactMap { item -> Home? in
                guard let owner = Self.string(item["ownerId"]) else { return nil }
                return Home(id: owner, name: Self.string(item["name"]) ?? "Tuya Home")
            }

            var discovered: [LinkedDevice] = []
            var seen = Set<String>()
            for home in loadedHomes {
                let response = try await signedGET(path: "/v1.0/m/life/ha/home/devices", params: ["homeId": home.id])
                guard !Task.isCancelled,
                      generation == operationGeneration,
                      session != nil else { return }
                guard let array = response["result"] as? [[String: Any]] else { continue }
                for rawDevice in array {
                    guard let id = Self.string(rawDevice["id"]), !id.isEmpty, seen.insert(id).inserted else { continue }
                    discovered.append(Self.makeDevice(rawDevice))
                }
            }

            guard !Task.isCancelled,
                  generation == operationGeneration,
                  session != nil else { return }
            homes = loadedHomes
            devices = discovered.sorted { lhs, rhs in
                if lhs.online != rhs.online { return lhs.online && !rhs.online }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            phase = .ready
            if devices.isEmpty {
                statusMessage = "Tuya is linked, but this account returned no devices."
            } else if devices.count == 1, let only = devices.first {
                statusMessage = "Found \(only.name). Tap it to read its status and DP definitions."
            } else {
                statusMessage = "Found \(devices.count) Tuya devices. Tap the scooter."
            }
        } catch {
            guard !Task.isCancelled,
                  generation == operationGeneration,
                  session != nil else { return }
            phase = .failed
            statusMessage = "Tuya device read failed: \(Self.readable(error))"
        }
    }

    private func loadSelectedDeviceDetails(_ device: LinkedDevice, generation: UInt64) async throws {
        guard let session else { throw BridgeError.notLinked }
        let accountUID = session.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else {
            throw BridgeError.malformed("Tuya account identity is unavailable for metadata custody.")
        }

        async let detailResponse = signedGET(path: "/v1.0/m/life/ha/devices/detail", params: ["devIds": device.id])
        async let specResponse = signedGET(path: "/v1.1/m/life/\(device.id)/specifications")
        let (detail, specs) = try await (detailResponse, specResponse)
        guard !Task.isCancelled,
              generation == operationGeneration,
              selectedDeviceID == device.id else { return }
        let detailArray = detail["result"] as? [[String: Any]] ?? []
        let rawDetail = detailArray.first ?? [:]
        selectedDeviceMetadata = Self.redactAccountUID(
            Self.redactSecrets(rawDetail),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        selectedDeviceSpecifications = Self.redactAccountUID(
            Self.redactSecrets(specs["result"] as? [String: Any] ?? [:]),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]

        var statusMap: [String: Any] = [:]
        if let statuses = rawDetail["status"] as? [[String: Any]] {
            for status in statuses {
                if let code = Self.string(status["code"]), let value = status["value"] {
                    statusMap[code] = value
                }
            }
        }
        guard !Task.isCancelled,
              generation == operationGeneration,
              selectedDeviceID == device.id else { return }
        selectedDeviceStatus = Self.redactAccountUID(
            Self.redactSecrets(statusMap),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        prepareRedactedExport()
    }

    private func signedGET(path: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        guard let session else { throw BridgeError.notLinked }
        let rid = UUID().uuidString.lowercased()
        let hashKey = Self.md5Hex(rid + session.refreshToken)
        let secret = Self.hmacHex(key: rid, message: hashKey).prefix(16).lowercased()

        var queryEncdata = ""
        var queryItems: [URLQueryItem] = []
        if let params, !params.isEmpty {
            let json = try Self.compactJSONString(params)
            queryEncdata = try Self.aesGCMEncrypt(json, secret: String(secret))
            queryItems = [URLQueryItem(name: "encdata", value: queryEncdata)]
        }

        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        var headers: [String: String] = [
            "X-appKey": clientID,
            "X-requestId": rid,
            "X-sid": "",
            "X-time": timestamp,
            "X-token": session.accessToken
        ]
        headers["X-sign"] = Self.restfulSign(hashKey: hashKey, queryEncdata: queryEncdata, bodyEncdata: "", headers: headers)

        var endpoint = session.endpoint
        while endpoint.hasSuffix("/") { endpoint.removeLast() }
        guard var components = URLComponents(string: endpoint + path) else { throw BridgeError.invalidURL }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw BridgeError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        for (key, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let response = try await Self.requestJSON(request)
        guard Self.bool(response["success"]) else {
            throw BridgeError.remote(Self.remoteMessage(response))
        }
        guard let cipher = response["result"] as? String else {
            return response
        }
        let plaintext = try Self.aesGCMDecrypt(cipher, secret: String(secret))
        guard let data = plaintext.data(using: .utf8) else { throw BridgeError.malformed("Tuya response was not UTF-8.") }
        let resultObject = try JSONSerialization.jsonObject(with: data)
        var decoded = response
        decoded["result"] = resultObject
        return decoded
    }

    private static func makeDevice(_ raw: [String: Any]) -> LinkedDevice {
        LinkedDevice(
            id: string(raw["id"]) ?? "",
            name: string(raw["name"]) ?? string(raw["product_name"]) ?? "Unnamed Tuya device",
            category: string(raw["category"]) ?? "",
            productID: string(raw["product_id"]) ?? "",
            productName: string(raw["product_name"]) ?? "",
            uuid: string(raw["uuid"]) ?? "",
            assetID: string(raw["asset_id"]) ?? "",
            online: bool(raw["online"])
        )
    }

    static func normalizedHTTPSAPIEndpoint(_ rawEndpoint: String) throws -> String {
        let trimmed = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BridgeError.invalidURL }

        let parsed = URLComponents(string: trimmed)
        let candidate = parsed?.scheme == nil ? "https://\(trimmed)" : trimmed
        guard var components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw BridgeError.invalidURL
        }
        components.scheme = "https"
        components.path = ""
        guard let url = components.url,
              url.scheme?.lowercased() == "https",
              let normalizedHost = url.host,
              !normalizedHost.isEmpty else {
            throw BridgeError.invalidURL
        }
        var normalized = url.absoluteString
        while normalized.hasSuffix("/") { normalized.removeLast() }
        return normalized
    }

    private static func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        guard let requestURL = request.url,
              requestURL.scheme?.lowercased() == "https",
              let host = requestURL.host,
              !host.isEmpty else {
            throw BridgeError.invalidURL
        }
        let redirectDelegate = TuyaAccountBridgeNoRedirectDelegate()
        let (data, response) = try await URLSession.shared.data(for: request, delegate: redirectDelegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BridgeError.remote("HTTP request failed.")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.malformed("Server response was not a JSON object.")
        }
        return object
    }

    private static func compactJSONString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        guard let value = String(data: data, encoding: .utf8) else { throw BridgeError.malformed("Could not encode JSON.") }
        return value
    }

    private static func aesGCMEncrypt(_ plaintext: String, secret: String) throws -> String {
        let nonceString = randomNonce(length: 12)
        let nonceData = Data(nonceString.utf8)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let key = SymmetricKey(data: Data(secret.utf8))
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key, nonce: nonce)
        var cipherAndTag = sealed.ciphertext
        cipherAndTag.append(sealed.tag)
        return nonceData.base64EncodedString() + cipherAndTag.base64EncodedString()
    }

    private static func aesGCMDecrypt(_ cipherData: String, secret: String) throws -> String {
        guard let combined = Data(base64Encoded: cipherData), combined.count > 28 else {
            throw BridgeError.malformed("Encrypted Tuya response was malformed.")
        }
        let nonceData = combined.prefix(12)
        let remainder = combined.dropFirst(12)
        guard remainder.count >= 16 else { throw BridgeError.malformed("Encrypted Tuya response was too short.") }
        let ciphertext = remainder.dropLast(16)
        let tag = remainder.suffix(16)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let clear = try AES.GCM.open(box, using: SymmetricKey(data: Data(secret.utf8)))
        guard let string = String(data: clear, encoding: .utf8) else { throw BridgeError.malformed("Decrypted Tuya response was not UTF-8.") }
        return string
    }

    private static func md5Hex(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacHex(key: String, message: String) -> String {
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: symmetricKey)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    private static func restfulSign(hashKey: String, queryEncdata: String, bodyEncdata: String, headers: [String: String]) -> String {
        let order = ["X-appKey", "X-requestId", "X-sid", "X-time", "X-token"]
        let headerParts = order.compactMap { key -> String? in
            guard let value = headers[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }
        let signString = headerParts.joined(separator: "||") + queryEncdata + bodyEncdata
        return hmacHex(key: hashKey, message: signString)
    }

    private static func randomNonce(length: Int) -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    private static func makeQRCodePNG(_ payload: String) -> Data? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceGray()
        return context.pngRepresentation(of: image, format: .L8, colorSpace: colorSpace)
    }

    private static func redactSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            var output: [String: Any] = [:]
            let secretKeyFragments = ["localkey", "sessionkey", "appkey", "appsecret", "password", "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey"]
            for (key, value) in dictionary {
                let normalized = String(key.lowercased().filter { $0.isLetter || $0.isNumber })
                if secretKeyFragments.contains(where: normalized.contains) {
                    output[key] = "<redacted>"
                } else {
                    output[key] = redactSecrets(value)
                }
            }
            return output
        }
        if let array = object as? [Any] { return array.map(redactSecrets) }
        return object
    }

    private static func redactAccountUID(_ object: Any, accountUID: String) -> Any {
        let marker = "<redacted-account-uid>"
        if let dictionary = object as? [String: Any] {
            var output: [String: Any] = [:]
            output.reserveCapacity(dictionary.count)
            for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
                let redactedKey = key.replacingOccurrences(
                    of: accountUID,
                    with: marker,
                    options: [.caseInsensitive, .literal]
                )
                let redactedValue = redactAccountUID(value, accountUID: accountUID)
                var custodyKey = redactedKey
                var collisionOrdinal = 2
                while output[custodyKey] != nil {
                    custodyKey = "\(redactedKey)#\(collisionOrdinal)"
                    collisionOrdinal += 1
                }
                output[custodyKey] = redactedValue
            }
            return output
        }
        if let array = object as? [Any] {
            return array.map { redactAccountUID($0, accountUID: accountUID) }
        }
        if let string = object as? String {
            return string.replacingOccurrences(
                of: accountUID,
                with: marker,
                options: [.caseInsensitive, .literal]
            )
        }
        return object
    }

    private static func remoteMessage(_ object: [String: Any]) -> String {
        let msg = string(object["msg"]) ?? "Tuya rejected the request."
        if let code = string(object["code"]), !code.isEmpty { return "\(msg) (\(code))" }
        return msg
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return ["true", "1", "yes"].contains(value.lowercased()) }
        return false
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
    }

    private static func readable(_ error: Error) -> String {
        if let bridge = error as? BridgeError { return bridge.description }
        return error.localizedDescription
    }

    enum BridgeError: Error {
        case invalidURL
        case notLinked
        case malformed(String)
        case remote(String)

        var description: String {
            switch self {
            case .invalidURL: return "Invalid Tuya URL."
            case .notLinked: return "Tuya account is not linked."
            case .malformed(let message), .remote(let message): return message
            }
        }
    }
}

struct TuyaQRCodeExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { export in export.data }
            .suggestedFileName("Nembra-Tuya-Approval-QR.png")
    }
}

struct TuyaMetadataExport: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in export.data }
            .suggestedFileName { $0.filename }
    }
}
