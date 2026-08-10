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
/// specifications, and local DP strategy before the next Bluetooth experiment.
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
        let localKey: String
        let raw: [String: AnyHashable]

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
    @Published private(set) var selectedDeviceLocalStrategy: [String: Any]?
    @Published private(set) var redactedExportData: Data?
    @Published private(set) var redactedExportFilename = "Nembra-Tuya-ReadOnly-Metadata.json"

    private let clientID = "HA_3y9q4ak7g4ephrvke"
    private let schema = "haauthorize"
    private let loginBaseURL = "https://apigw.iotbing.com"
    private var qrToken: String?
    private var session: Session?
    private var pollTask: Task<Void, Never>?

    deinit {
        pollTask?.cancel()
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

        pollTask?.cancel()
        phase = .requestingApproval
        statusMessage = "Creating a private Tuya approval QR…"
        qrPayload = nil
        qrPNGData = nil
        session = nil
        homes = []
        devices = []
        selectedDeviceID = nil
        selectedDeviceMetadata = nil
        selectedDeviceStatus = nil
        selectedDeviceSpecifications = nil
        selectedDeviceLocalStrategy = nil
        redactedExportData = nil

        Task {
            do {
                let token = try await createQRToken(userCode: normalized)
                qrToken = token
                let payload = "tuyaSmart--qrLogin?token=\(token)"
                qrPayload = payload
                qrPNGData = Self.makeQRCodePNG(payload)
                phase = .waitingForApproval
                statusMessage = "Approve this QR in Tuya Smart. Nembra will notice automatically when approval finishes."
                startPolling(userCode: normalized, token: token)
            } catch {
                phase = .failed
                statusMessage = "Tuya approval setup failed: \(Self.readable(error))"
            }
        }
    }

    func checkApprovalNow() {
        guard let qrToken else {
            requestApproval()
            return
        }
        let normalized = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await pollApprovalOnce(userCode: normalized, token: qrToken) }
    }

    func refreshDevices() {
        guard session != nil else {
            phase = .failed
            statusMessage = "Tuya is not linked yet."
            return
        }
        Task { await loadHomesAndDevices() }
    }

    func selectDevice(_ device: LinkedDevice) {
        selectedDeviceID = device.id
        statusMessage = "Reading \(device.name)'s Tuya status and DP definitions…"
        redactedExportData = nil
        Task {
            do {
                try await loadSelectedDeviceDetails(device)
                phase = .ready
                statusMessage = "Tuya metadata is ready. No scooter control command was sent."
            } catch {
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
            "status": selectedDeviceStatus ?? [:],
            "specifications": selectedDeviceSpecifications ?? [:],
            "localStrategy": selectedDeviceLocalStrategy ?? [:],
            "safety": [
                "readOnlyCloudCalls": true,
                "localKeyExported": false,
                "accessTokenExported": false,
                "refreshTokenExported": false,
                "commandsSent": false
            ]
        ]

        if let selectedDeviceMetadata {
            envelope["deviceDetailRedacted"] = Self.redactSecrets(selectedDeviceMetadata)
        }

        do {
            redactedExportData = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            redactedExportFilename = "Nembra-Tuya-\(Self.safeFilename(device.name))-Metadata.json"
            statusMessage = "Redacted Tuya metadata is ready to share. Account tokens and local_key are excluded."
        } catch {
            statusMessage = "Could not prepare metadata JSON: \(Self.readable(error))"
        }
    }

    func resetLink() {
        pollTask?.cancel()
        pollTask = nil
        session = nil
        qrToken = nil
        qrPayload = nil
        qrPNGData = nil
        homes = []
        devices = []
        selectedDeviceID = nil
        selectedDeviceMetadata = nil
        selectedDeviceStatus = nil
        selectedDeviceSpecifications = nil
        selectedDeviceLocalStrategy = nil
        redactedExportData = nil
        phase = .needsUserCode
        statusMessage = "Tuya link cleared from this Capture session."
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

    private func startPolling(userCode: String, token: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<90 {
                if Task.isCancelled { return }
                await self.pollApprovalOnce(userCode: userCode, token: token)
                if self.session != nil { return }
                try? await Task.sleep(for: .seconds(2))
            }
            if self.session == nil {
                self.phase = .failed
                self.statusMessage = "Tuya approval timed out. Tap Try again to make a fresh QR."
            }
        }
    }

    private func pollApprovalOnce(userCode: String, token: String) async {
        guard session == nil else { return }
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
            guard Self.bool(object["success"]), let result = object["result"] as? [String: Any] else {
                if phase == .waitingForApproval {
                    statusMessage = "Waiting for approval in Tuya Smart…"
                }
                return
            }

            let issued = Self.int64(object["t"]) ?? Int64(Date().timeIntervalSince1970 * 1000)
            let access = result["access_token"] as? String ?? ""
            let refresh = result["refresh_token"] as? String ?? ""
            let uid = result["uid"] as? String ?? ""
            let terminal = result["terminal_id"] as? String ?? ""
            let expire = Self.int64(result["expire_time"]) ?? 0
            let rawEndpoint = result["endpoint"] as? String ?? ""
            let endpoint = rawEndpoint.hasPrefix("http") ? rawEndpoint : "https://\(rawEndpoint)"
            guard !access.isEmpty, !refresh.isEmpty, !endpoint.isEmpty else {
                throw BridgeError.malformed("Tuya approval succeeded but the account session was incomplete.")
            }

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
            pollTask?.cancel()
            pollTask = nil
            phase = .loadingDevices
            statusMessage = "Tuya approved. Reading your device list…"
            await loadHomesAndDevices()
        } catch {
            if phase == .waitingForApproval {
                statusMessage = "Still waiting for Tuya approval…"
            }
        }
    }

    private func loadHomesAndDevices() async {
        guard session != nil else { return }
        phase = .loadingDevices
        do {
            let homeResponse = try await signedGET(path: "/v1.0/m/life/users/homes")
            guard let homeArray = homeResponse["result"] as? [[String: Any]] else {
                throw BridgeError.malformed("Tuya returned no homes for this account.")
            }
            homes = homeArray.compactMap { item in
                guard let owner = Self.string(item["ownerId"]) else { return nil }
                return Home(id: owner, name: Self.string(item["name"]) ?? "Tuya Home")
            }

            var discovered: [LinkedDevice] = []
            var seen = Set<String>()
            for home in homes {
                let response = try await signedGET(path: "/v1.0/m/life/ha/home/devices", params: ["homeId": home.id])
                guard let array = response["result"] as? [[String: Any]] else { continue }
                for rawDevice in array {
                    guard let id = Self.string(rawDevice["id"]), !id.isEmpty, seen.insert(id).inserted else { continue }
                    discovered.append(Self.makeDevice(rawDevice))
                }
            }
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
            phase = .failed
            statusMessage = "Tuya device read failed: \(Self.readable(error))"
        }
    }

    private func loadSelectedDeviceDetails(_ device: LinkedDevice) async throws {
        async let detailResponse = signedGET(path: "/v1.0/m/life/ha/devices/detail", params: ["devIds": device.id])
        async let specResponse = signedGET(path: "/v1.1/m/life/\(device.id)/specifications")
        async let strategyResponse = signedGET(path: "/v1.0/m/life/devices/\(device.id)/status")

        let (detail, specs, strategy) = try await (detailResponse, specResponse, strategyResponse)
        let detailArray = detail["result"] as? [[String: Any]] ?? []
        let rawDetail = detailArray.first ?? [:]
        selectedDeviceMetadata = rawDetail
        selectedDeviceSpecifications = specs["result"] as? [String: Any] ?? [:]
        selectedDeviceLocalStrategy = strategy["result"] as? [String: Any] ?? [:]

        var statusMap: [String: Any] = [:]
        if let statuses = rawDetail["status"] as? [[String: Any]] {
            for status in statuses {
                if let code = Self.string(status["code"]), let value = status["value"] {
                    statusMap[code] = value
                }
            }
        }
        selectedDeviceStatus = statusMap
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
        var hashableRaw: [String: AnyHashable] = [:]
        for (key, value) in raw {
            if let value = value as? AnyHashable { hashableRaw[key] = value }
        }
        return LinkedDevice(
            id: string(raw["id"]) ?? "",
            name: string(raw["name"]) ?? string(raw["product_name"]) ?? "Unnamed Tuya device",
            category: string(raw["category"]) ?? "",
            productID: string(raw["product_id"]) ?? "",
            productName: string(raw["product_name"]) ?? "",
            uuid: string(raw["uuid"]) ?? "",
            assetID: string(raw["asset_id"]) ?? "",
            online: bool(raw["online"]),
            localKey: string(raw["local_key"]) ?? "",
            raw: hashableRaw
        )
    }

    private static func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
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
            for (key, value) in dictionary {
                let normalized = key.lowercased()
                if normalized == "local_key" || normalized == "localkey" || normalized.contains("access_token") || normalized.contains("refresh_token") || normalized == "seckey" || normalized == "sec_key" || normalized == "auth_key" || normalized == "authkey" {
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

struct NembraCaptureRootView: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    accountCard
                    if tuya.qrPayload != nil { approvalCard }
                    if tuya.isLinked { deviceCard }
                    if tuya.selectedDevice != nil { readyCard }
                }
                .padding(18)
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationDestination(isPresented: $showCapture) {
                ES80OneTimeBluetoothDumpView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEMBRA CAPTURE")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Text("Link Tuya first")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("We already proved this scooter uses Tuya FD50. This step reads your own Tuya device metadata so the next Bluetooth test can stop guessing.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("TUYA ACCOUNT", systemImage: tuya.isLinked ? "checkmark.shield.fill" : "person.badge.key.fill")
                .font(.headline)
            if !tuya.isLinked {
                Text("In Tuya Smart: Me → Settings → Account and Security → User Code. Copy that code here. Do NOT enter your Tuya password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("User Code", text: $tuya.userCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    tuya.requestApproval()
                } label: {
                    HStack {
                        if tuya.phase == .requestingApproval { ProgressView().tint(.black) }
                        Text(tuya.qrPayload == nil ? "Create Tuya approval QR" : "Make a fresh approval QR")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            } else {
                Label("Tuya approved for this Capture session", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Refresh Tuya devices") { tuya.refreshDevices() }
                    .buttonStyle(.bordered)
            }
            Text(tuya.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .captureCard()
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("APPROVE IN TUYA SMART")
                .font(.headline)
            if let data = tuya.qrPNGData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 260)
                    .frame(maxWidth: .infinity)

                Text("On this same iPhone: share/save the QR image, open Tuya Smart's scanner, choose the QR from Photos/Album, then approve. Come back here afterward.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ShareLink(item: TuyaQRCodeExport(data: data), preview: SharePreview("Tuya approval QR")) {
                    Label("Share / save approval QR", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button("I approved it · check now") { tuya.checkApprovalNow() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .captureCard()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CHOOSE THE SCOOTER")
                    .font(.headline)
                Spacer()
                if tuya.phase == .loadingDevices { ProgressView() }
            }
            if tuya.devices.isEmpty {
                Text("Reading Tuya devices…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tuya.devices) { device in
                    Button {
                        tuya.selectDevice(device)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: device.id == tuya.selectedDeviceID ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                    .font(.headline)
                                Text([device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(device.online ? "ONLINE" : "OFFLINE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(device.online ? .green : .secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if device.id != tuya.devices.last?.id { Divider().overlay(.white.opacity(0.08)) }
                }
            }
        }
        .captureCard()
    }

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("READ-ONLY METADATA READY", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            if let device = tuya.selectedDevice {
                Text(device.name)
                    .font(.title3.bold())
                Text("Nembra has the Tuya device identity, current cloud status, DP specifications, and local-strategy metadata. Secret local_key stays inside this session and is never put in the export.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let data = tuya.redactedExportData {
                ShareLink(item: TuyaMetadataExport(data: data, filename: tuya.redactedExportFilename), preview: SharePreview("Nembra Tuya metadata")) {
                    Label("Share Tuya metadata JSON", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button("Prepare redacted metadata JSON") { tuya.prepareRedactedExport() }
                    .buttonStyle(.bordered)
            }
            Button {
                showCapture = true
            } label: {
                Label("Continue to Bluetooth Capture", systemImage: "dot.radiowaves.left.and.right")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .captureCard()
    }
}

private extension View {
    func captureCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08)))
    }
}
