@preconcurrency import CoreBluetooth
import CoreTransferable
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit
#endif

let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable

@main @MainActor
struct NembraCaptureApp: App {
    var body: some Scene { WindowGroup { CaptureP0Root().preferredColorScheme(.dark) } }
}

@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("P0 · TUYA AUTHENTICATION").font(.caption.monospaced().bold()).foregroundStyle(.green)
                    Text("Prove the secure scooter link first.").font(.largeTitle.bold())
                    Text("No ride calibration is available here. The next physical run is stationary and only proves supported Tuya authentication, >45 s continuity, and real FD50 notification bytes.").foregroundStyle(.secondary)
                    safety
                    account
                    if tuya.isLinked { devices }
                }.frame(maxWidth: 760).padding(18).frame(maxWidth: .infinity)
            }.background(Color.black.ignoresSafeArea()).navigationTitle("Nembra Capture")
        }
    }
    private var safety: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read-only control boundary", systemImage: "shield.checkered").font(.headline)
            Text("The existing QR account link is metadata/ownership discovery only. Nembra does not turn local_key into a BLE login key or synthesize/fuzz FD50 authentication frames.").foregroundStyle(.secondary)
            Text("No unbind, reset, lock, speed, light, mode, throttle, brake, firmware, or other DP command is sent.").font(.footnote.bold()).foregroundStyle(.green)
        }.card()
    }
    private var account: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1 · Identify your bound Tuya device", systemImage: "person.badge.key").font(.headline)
            Text(tuya.statusMessage).font(.footnote).foregroundStyle(.secondary)
            if !tuya.isLinked {
                TextField("Tuya Smart User Code", text: $tuya.userCode).textInputAutocapitalization(.never).autocorrectionDisabled().padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button("Create approval QR") { tuya.requestApproval() }.buttonStyle(.borderedProminent).disabled(tuya.phase == .requestingApproval)
            }
            if let data = tuya.qrPNGData, let image = UIImage(data: data), !tuya.isLinked {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 230).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                Button("I approved it · check now") { tuya.checkApprovalNow() }.buttonStyle(.bordered)
            }
            if tuya.phase == .failed { Button("Reset account link") { tuya.resetLink() }.buttonStyle(.bordered) }
        }.card()
    }
    private var devices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Choose the scooter", systemImage: "bicycle").font(.headline)
            if tuya.devices.isEmpty { Button("Refresh Tuya devices") { tuya.refreshDevices() }.buttonStyle(.bordered) }
            ForEach(tuya.devices) { d in
                VStack(alignment: .leading, spacing: 7) {
                    Text(d.name.isEmpty ? "Unnamed Tuya device" : d.name).font(.headline)
                    Text([d.productName, d.category].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(tuya.selectedDeviceID == d.id ? "Refresh metadata" : "Use this device") { tuya.selectDevice(d) }.buttonStyle(.bordered)
                        if tuya.selectedDeviceID == d.id, tuya.phase == .ready, !d.productID.isEmpty, !d.uuid.isEmpty {
                            NavigationLink("Secure link test") { SecureLinkView(device: d) }.buttonStyle(.borderedProminent)
                        }
                    }
                }.padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Only Tuya device UUID + product ID enter the secure-link controller; local_key does not.").font(.footnote).foregroundStyle(.secondary)
        }.card()
    }
}

@MainActor
private final class SecureLinkController: NSObject, ObservableObject {
    struct Candidate: Identifiable, Codable, Equatable {
        let id: UUID; var name: String?; var rssi: Int?; var ads: Int
        var newAfterPowerOn: Bool; var fd50: Bool; var tuyaCompany: Bool; var knownID: Bool; var expectedName: Bool
        var score: Int; var evidence: [String]
        var title: String { name?.isEmpty == false ? name! : "Unnamed peripheral" }
        var likely: Bool { knownID || (fd50 && tuyaCompany) || score >= 600 }
    }
    enum Phase: String, Codable { case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed }
    struct Event: Codable { let at: Date; let kind: String; let details: [String:String]; let hex: String?; let base64: String? }
    struct Export: Codable {
        let schemaVersion: Int; let purpose: String; let exportedAt: Date; let tuyaDeviceID: String; let tuyaUUID: String; let productID: String
        let selectedPeripheralID: String?; let phase: Phase; let sdkCompiled: Bool; let privateConfigPresent: Bool; let sdkAccountAuthorized: Bool
        let secureSessionEstablished: Bool; let secureSessionAgeSeconds: Double?; let applicationNotificationCount: Int; let candidates: [Candidate]
        let secretsRedacted: Bool; let dpCommandsSent: Bool; let events: [Event]
    }
    static let known = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
    static let notify = CBUUID(string: "00000002-0000-1001-8001-00805F9B07D0")
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. This is only an identification + authentication test."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var packetCount = 0
    @Published private(set) var secure = false
    @Published private(set) var exportData: Data?
    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"
    let deviceID: String; let deviceName: String; let productID: String; let tuyaUUID: String
    private var central: CBCentralManager!; private var peripherals: [UUID:CBPeripheral] = [:]; private var byID: [UUID:Candidate] = [:]; private var baseline = Set<UUID>()
    private var selectedPeripheral: CBPeripheral?; private var driver: OfficialTuyaDriver?; private var authUptime: UInt64?; private var acceptRaw = false; private var events: [Event] = []; private var watchdog: Task<Void,Never>?
    init(device: TuyaAccountBridge.LinkedDevice) {
        deviceID = device.id; deviceName = device.name; productID = device.productID; tuyaUUID = device.uuid
        super.init(); central = CBCentralManager(delegate: self, queue: .main); log("controller_created")
    }
    deinit { watchdog?.cancel() }
    var sdkCompiled: Bool { OfficialTuyaFactory.compiled }
    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var sdkAccountAuthorized: Bool { OfficialTuyaFactory.accountReady }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var age: Double? { guard let a = authUptime else { return nil }; let n = DispatchTime.now().uptimeNanoseconds; return n >= a ? Double(n-a)/1e9 : nil }
    var passed: Bool { secure && (phase == .observing || phase == .accepted) && packetCount > 0 && (age ?? 0) > 45 }
    func startBaseline() {
        guard central.state == .poweredOn else { fail("Bluetooth is not ready.", "bluetooth_unavailable"); return }
        resetDiscovery(); phase = .baseline; message = "Keep the scooter OFF for a few seconds."; log("baseline_started"); central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey:true])
    }
    func saveBaseline() { guard phase == .baseline else { return }; central.stopScan(); baseline = Set(byID.keys); phase = .powerOn; message = "Baseline saved. Turn the scooter ON."; log("baseline_saved", ["count":String(baseline.count)]) }
    func scanOn() { guard central.state == .poweredOn else { fail("Bluetooth is not ready.", "bluetooth_unavailable"); return }; phase = .scanning; message = "Ranking OFF→ON delta, known UUID, FD50, Tuya company ID, name, and RSSI."; central.scanForPeripherals(withServices:nil, options:[CBCentralManagerScanOptionAllowDuplicatesKey:true]); log("power_on_scan_started") }
    func stopScan() { central.stopScan(); if selectedID == nil, let c = candidates.first, c.likely { choose(c) }; if selectedID == nil { message = "No candidate has enough scooter/Tuya evidence yet." }; log("scan_stopped") }
    func choose(_ c: Candidate) { central.stopScan(); selectedID = c.id; selectedPeripheral = peripherals[c.id]; phase = .selected; message = c.likely ? "Likely scooter selected automatically from evidence." : "Evidence is not strong enough; re-scan instead of guessing."; log("candidate_selected", ["id":c.id.uuidString,"score":String(c.score),"evidence":c.evidence.joined(separator:",")]) }
    func authenticate() {
        guard let p = selectedPeripheral, let c = selected, c.likely else { fail("A strongly matched scooter candidate is required.", "candidate_not_confident"); return }
        guard !tuyaUUID.isEmpty, !productID.isEmpty else { fail("Tuya UUID/product ID is missing.", "tuya_identity_incomplete"); return }
        guard sdkCompiled, privateConfig else { fail("Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.", "sdk_unavailable"); return }
        guard sdkAccountAuthorized else { fail("The official Tuya SDK has no authorized account session. The metadata QR session cannot substitute for SDK login.", "sdk_account_not_authorized"); return }
        guard let d = OfficialTuyaFactory.make() else { fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable"); return }
        driver = d; phase = .authenticating; message = "Tuya is establishing its supported secure BLE session. Nembra sends no DP command."; log("official_connect_requested", ["coreBluetoothID":p.identifier.uuidString,"tuyaUUID":tuyaUUID,"productID":productID])
        d.connect(uuid: tuyaUUID, productID: productID, success: { [weak self] in Task { @MainActor in self?.authenticated() } }, failure: { [weak self] m in Task { @MainActor in self?.fail(m,"official_connect_failed") } })
    }
    private func authenticated() {
        guard phase == .authenticating, let p = selectedPeripheral else { return }
        secure = true; acceptRaw = true; authUptime = DispatchTime.now().uptimeNanoseconds; phase = .observing; message = "Secure scooter link established. Attaching passive FD50 notification observer…"; log("official_session_ready")
        p.delegate = self; central.connect(p); startWatchdog()
    }
    private func startWatchdog() {
        watchdog?.cancel(); watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled { guard let self, self.secure else { return }; if self.passed { self.phase = .accepted; self.message = "Receiving scooter data. Secure link passed the 45-second gate."; self.log("acceptance_passed",["packets":String(self.packetCount)]); return }; if (self.age ?? 0) > 60 && self.packetCount == 0 { self.fail("Secure session survived, but no post-auth FD50 notification arrived within 60 seconds.","no_notifications"); return }; try? await Task.sleep(for:.seconds(1)) }
        }
    }
    func prepareExport() {
        let x = Export(schemaVersion:1,purpose:"Sanitized Tuya authenticated read-only preflight",exportedAt:Date(),tuyaDeviceID:deviceID,tuyaUUID:tuyaUUID,productID:productID,selectedPeripheralID:selectedID?.uuidString,phase:phase,sdkCompiled:sdkCompiled,privateConfigPresent:privateConfig,sdkAccountAuthorized:sdkAccountAuthorized,secureSessionEstablished:secure,secureSessionAgeSeconds:age,applicationNotificationCount:packetCount,candidates:candidates,secretsRedacted:true,dpCommandsSent:false,events:events)
        do { let e=JSONEncoder(); e.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]; e.dateEncodingStrategy = .iso8601; exportData=try e.encode(x); exportName="Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"; message="Sanitized diagnostics ready; passwords, tokens, local_key and AppSecret are excluded." } catch { message="Diagnostic export failed: \(error.localizedDescription)" }
    }
    private func resetDiscovery() { central.stopScan(); watchdog?.cancel(); watchdog=nil; peripherals.removeAll(); byID.removeAll(); candidates.removeAll(); baseline.removeAll(); selectedID=nil; selectedPeripheral=nil; secure=false; acceptRaw=false; authUptime=nil; packetCount=0; exportData=nil }
    private func fail(_ m:String,_ kind:String) { watchdog?.cancel(); watchdog=nil; acceptRaw=false; phase = .failed; message=m; log(kind,["message":sanitize(m)]) }
    private func log(_ kind:String,_ details:[String:String]=[:],raw:Data?=nil) { events.append(Event(at:Date(),kind:kind,details:details.mapValues(sanitize),hex:raw.map{ $0.map{String(format:"%02X",$0)}.joined() },base64:raw?.base64EncodedString())) }
    private func sanitize(_ s:String)->String { var r=s; for k in ["NEMBRA_TUYA_APP_KEY","NEMBRA_TUYA_APP_SECRET"] { if let v=ProcessInfo.processInfo.environment[k],!v.isEmpty { r=r.replacingOccurrences(of:v,with:"<redacted>") } }; return r }
    private static func tuyaCompany(_ d:Data?)->Bool { guard let d,d.count>=2 else{return false}; return (UInt16(d[d.startIndex]) | UInt16(d[d.index(after:d.startIndex)])<<8) == 0x07D0 }
    private func update(_ p:CBPeripheral,_ ad:[String:Any],_ n:NSNumber) {
        let id=p.identifier; peripherals[id]=p; if phase == .baseline { baseline.insert(id) }
        let old=byID[id]; let name=(ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? old?.name; let r=n.intValue == 127 ? old?.rssi : n.intValue
        let uuids=((ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []) + ((ad[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []) + ((ad[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]) ?? [])
        let sd=ad[CBAdvertisementDataServiceDataKey] as? [CBUUID:Data]; let fd=(uuids.contains(Self.fd50) || sd?.keys.contains(Self.fd50) == true || old?.fd50 == true)
        let co=(Self.tuyaCompany(ad[CBAdvertisementDataManufacturerDataKey] as? Data) || old?.tuyaCompany == true); let kn=id==Self.known; let nw=(phase == .scanning && !baseline.contains(id)) || old?.newAfterPowerOn == true
        let nm=(name?.localizedCaseInsensitiveContains("demo") == true || name?.localizedCaseInsensitiveContains("tuya") == true || old?.expectedName == true)
        var score=0; var ev:[String]=[]; if kn{score+=1000;ev.append("known previous UUID")}; if fd{score+=500;ev.append("FD50")}; if co{score+=350;ev.append("Tuya company 0x07D0")}; if nw{score+=180;ev.append("appeared after power-on")}; if nm{score+=100;ev.append("expected name")}; if let r { if r >= -50{score+=80;ev.append("very close RSSI")} else if r >= -65{score+=50;ev.append("nearby RSSI")} else if r >= -80{score+=20} }
        byID[id]=Candidate(id:id,name:name,rssi:r,ads:(old?.ads ?? 0)+1,newAfterPowerOn:nw,fd50:fd,tuyaCompany:co,knownID:kn,expectedName:nm,score:score,evidence:ev)
        candidates=byID.values.sorted { $0.score == $1.score ? (($0.rssi ?? -999) > ($1.rssi ?? -999)) : $0.score > $1.score }
    }
}

extension SecureLinkController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central:CBCentralManager) { log("central_state",["raw":String(central.state.rawValue)]) }
    func centralManager(_ central:CBCentralManager,didDiscover p:CBPeripheral,advertisementData ad:[String:Any],rssi:NSNumber) { update(p,ad,rssi) }
    func centralManager(_ central:CBCentralManager,didConnect p:CBPeripheral) { guard acceptRaw,selectedID==p.identifier else{return}; log("observer_connected"); p.delegate=self; p.discoverServices([Self.fd50]); message="Secure scooter link established. Looking for FD50 notify 0002…" }
    func centralManager(_ central:CBCentralManager,didFailToConnect p:CBPeripheral,error:Error?) { guard acceptRaw,selectedID==p.identifier else{return}; fail("Passive observer could not attach: \(error?.localizedDescription ?? "unknown")","observer_connect_failed") }
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral p:CBPeripheral,error:Error?) { guard selectedID==p.identifier else{return}; log("observer_disconnected",["error":error?.localizedDescription ?? ""]); if secure && phase != .accepted { fail("Secure link disconnected before acceptance. Export diagnostics; do not repeat the ride capture.","disconnect_before_acceptance") } }
}

extension SecureLinkController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ p:CBPeripheral,didDiscoverServices error:Error?) { if let error{fail("FD50 discovery failed: \(error.localizedDescription)","fd50_discovery_failed");return}; guard let s=p.services?.first(where:{$0.uuid==Self.fd50}) else{fail("FD50 service missing.","fd50_missing");return}; p.discoverCharacteristics([Self.notify],for:s); log("fd50_found") }
    func peripheral(_ p:CBPeripheral,didDiscoverCharacteristicsFor s:CBService,error:Error?) { if let error{fail("Notify discovery failed: \(error.localizedDescription)","notify_discovery_failed");return}; guard let c=s.characteristics?.first(where:{$0.uuid==Self.notify}),c.properties.contains(.notify)||c.properties.contains(.indicate) else{fail("FD50 notify characteristic 0002 missing.","notify_missing");return}; p.setNotifyValue(true,for:c); log("notify_subscription_requested") }
    func peripheral(_ p:CBPeripheral,didUpdateNotificationStateFor c:CBCharacteristic,error:Error?) { if let error{fail("Notification subscription failed: \(error.localizedDescription)","subscription_failed");return}; log("notify_state",["enabled":c.isNotifying ? "true":"false"]); if c.isNotifying{message="Secure scooter link established. Waiting for post-auth FD50 bytes…"} }
    func peripheral(_ p:CBPeripheral,didUpdateValueFor c:CBCharacteristic,error:Error?) { guard acceptRaw,c.uuid==Self.notify,c.isNotifying else{return}; if let error{log("notification_error",["error":error.localizedDescription]);return}; guard let v=c.value,!v.isEmpty else{return}; packetCount+=1; log("post_auth_fd50_notification",["bytes":String(v.count)],raw:v); if passed{phase = .accepted;message="Receiving scooter data. Secure link passed."} else{message="Receiving scooter data · \(packetCount) packet(s). Keep it stationary until >45 s."} }
}

@MainActor private protocol OfficialTuyaDriver: AnyObject { func connect(uuid:String,productID:String,success:@escaping()->Void,failure:@escaping(String)->Void) }
@MainActor private enum OfficialTuyaFactory {
    static var compiled:Bool {
#if canImport(ThingSmartHomeKit)
        true
#else
        false
#endif
    }
    static var configured:Bool { compiled && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_KEY"] ?? "").isEmpty && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_SECRET"] ?? "").isEmpty }
    static var accountReady:Bool {
#if canImport(ThingSmartHomeKit)
        ThingSmartUser.sharedInstance()?.isLogin == true
#else
        false
#endif
    }
    static func make()->OfficialTuyaDriver? {
#if canImport(ThingSmartHomeKit)
        guard configured,accountReady else{return nil}
        return SmartLifeDriver()
#else
        return nil
#endif
    }
}
#if canImport(ThingSmartHomeKit)
@MainActor private final class SmartLifeDriver: NSObject, OfficialTuyaDriver {
    func connect(uuid:String,productID:String,success:@escaping()->Void,failure:@escaping(String)->Void) {
        let env=ProcessInfo.processInfo.environment; guard let key=env["NEMBRA_TUYA_APP_KEY"],!key.isEmpty,let secret=env["NEMBRA_TUYA_APP_SECRET"],!secret.isEmpty else{failure("Private Tuya SDK credentials are missing.");return}
        ThingSmartSDK.sharedInstance()?.start(withAppKey:key,secretKey:secret)
        ThingSmartBLEManager.sharedInstance().connectBLE(withUUID:uuid,productKey:productID,success:success,failure:{ failure("Tuya SmartLife SDK did not establish the BLE session.") })
    }
}
#endif

@MainActor
private struct SecureLinkView: View {
    @StateObject private var test:SecureLinkController
    init(device:TuyaAccountBridge.LinkedDevice){_test=StateObject(wrappedValue:SecureLinkController(device:device))}
    var body:some View {
        TimelineView(.periodic(from:.now,by:0.5)){_ in ScrollView{VStack(alignment:.leading,spacing:14){
            Text("SMALLEST INDOOR TEST").font(.caption.monospaced().bold()).foregroundStyle(.green); Text("Authenticate. Wait. Capture.").font(.largeTitle.bold()); Text("Keep the scooter stationary. Do not run the old 17-step sequence.").foregroundStyle(.secondary)
            status; sdk; discovery; if let c=test.selected{selected(c)}; acceptance; export
        }.frame(maxWidth:760).padding(18).frame(maxWidth:.infinity)}.background(Color.black.ignoresSafeArea())}.navigationTitle("Secure Link")
    }
    private var status:some View { VStack(alignment:.leading,spacing:8){HStack{Text(test.passed ? "Secure scooter link established" : test.phase == .failed ? "Secure-link test stopped" : "Authentication preflight").font(.headline);Spacer();Text("\(test.packetCount)").monospacedDigit()};Text(test.message).font(.footnote).foregroundStyle(.secondary);if let a=test.age{LabeledContent("Secure-session age",value:String(format:"%.1f s",a));ProgressView(value:min(a/45,1))};LabeledContent("Post-auth FD50 packets",value:String(test.packetCount))}.card() }
    private var sdk:some View { VStack(alignment:.leading,spacing:7){Label("Official Tuya gate",systemImage:"checkmark.shield").font(.headline);LabeledContent("SDK compiled in",value:test.sdkCompiled ? "Yes":"No");LabeledContent("Private app config",value:test.privateConfig ? "Yes":"No");LabeledContent("SDK account authorized",value:test.sdkAccountAuthorized ? "Yes":"No");if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized{Text("NO PHYSICAL TEST YET: official SDK/security component, matching private app credentials, and an authorized SDK account session must all be ready.").font(.footnote.bold()).foregroundStyle(.orange)}}.card() }
    private var discovery:some View { VStack(alignment:.leading,spacing:10){Label("Find the known scooter",systemImage:"scope").font(.headline);switch test.phase{case .idle,.failed:Button("Start scooter-OFF baseline"){test.startBaseline()}.buttonStyle(.borderedProminent);case .baseline:Button("Save OFF baseline"){test.saveBaseline()}.buttonStyle(.borderedProminent);case .powerOn:Text("Turn scooter ON, keep it still.").foregroundStyle(.secondary);Button("Scan after power-on"){test.scanOn()}.buttonStyle(.borderedProminent);case .scanning:Button("Stop scan / use best evidence"){test.stopScan()}.buttonStyle(.bordered);default:EmptyView()};ForEach(test.candidates.prefix(8)){c in Button{test.choose(c)}label:{VStack(alignment:.leading,spacing:4){HStack{Text(c.title).bold();if c.likely{Text("LIKELY SCOOTER").font(.caption2.bold()).padding(.horizontal,6).padding(.vertical,2).background(.green,in:Capsule()).foregroundStyle(.black)};Spacer();Text("\(c.score)").monospacedDigit()};Text("\(c.rssi.map{String($0)+" dBm"} ?? "RSSI ?") · \(c.id.uuidString)").font(.caption2).foregroundStyle(.secondary).lineLimit(1);Text(c.evidence.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)}}.buttonStyle(.plain)}}.card() }
    private func selected(_ c:SecureLinkController.Candidate)->some View { VStack(alignment:.leading,spacing:8){Label("Authentication gate",systemImage:"key.horizontal").font(.headline);Text(c.evidence.joined(separator:" · ")).font(.footnote).foregroundStyle(.secondary);Button("Start secure read-only test"){test.authenticate()}.buttonStyle(.borderedProminent).disabled(!c.likely || !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || [.authenticating,.observing,.accepted].contains(test.phase))}.card() }
    private var acceptance:some View { VStack(alignment:.leading,spacing:7){Label("Acceptance",systemImage:test.passed ? "checkmark.seal.fill":"hourglass").font(.headline).foregroundStyle(test.passed ? .green:.white);Text("Pass only when Tuya's official session succeeds, it survives >45 seconds, and at least one genuine post-auth FD50 notification is captured. No DP meaning is inferred here.").font(.footnote).foregroundStyle(.secondary);if test.passed{Text("Secure scooter link established\nReceiving scooter data").font(.title3.bold()).foregroundStyle(.green)}}.card() }
    private var export:some View { VStack(alignment:.leading,spacing:8){Button("Prepare sanitized diagnostic JSON"){test.prepareExport()}.buttonStyle(.bordered);if let d=test.exportData{ShareLink(item:SecureTransfer(data:d,name:test.exportName),preview:SharePreview(test.exportName)){Label("Share diagnostic JSON",systemImage:"square.and.arrow.up")}.buttonStyle(.borderedProminent)};Text("Export includes candidate evidence, timings, failures, and post-auth raw bytes; it excludes passwords, tokens, local_key, and AppSecret.").font(.footnote).foregroundStyle(.secondary)}.card() }
}

private struct SecureTransfer:Transferable{let data:Data;let name:String;static var transferRepresentation:some TransferRepresentation{DataRepresentation(exportedContentType:.json){$0.data}.suggestedFileName{$0.name}}}
private extension View{func card()->some View{padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:20))}}
