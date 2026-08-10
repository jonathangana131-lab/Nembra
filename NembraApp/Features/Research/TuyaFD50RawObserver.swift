@preconcurrency import CoreBluetooth
import Foundation

/// Passive raw-notification observer for the exact CoreBluetooth peripheral proven by
/// physical capture C7D09A22 on this iPhone.
///
/// Authentication remains owned by Tuya's official SDK. This observer never calls
/// `writeValue`, never reads a control characteristic, and never publishes a DP. Its
/// only ATT-side mutation is CoreBluetooth's required CCCD notification subscription
/// on the already-verified FD50 notify characteristic.
@MainActor
final class TuyaFD50RawObserver: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Event: Equatable {
        let receivedAtUptimeNanoseconds: UInt64
        let receivedAtWallClock: Date
        let characteristicUUID: String
        let payload: Data
    }

    enum State: Equatable {
        case idle
        case waitingForBluetooth
        case retrievingVerifiedPeripheral
        case connecting
        case discovering
        case subscribing
        case observing
        case failed(String)
        case stopped
    }

    static let verifiedPeripheralIdentifier = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let serviceUUID = CBUUID(string: "FD50")
    static let notifyCharacteristicUUID = CBUUID(string: "00000002-0000-1001-8001-00805F9B07D0")

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    var onStateChange: ((State) -> Void)?
    var onPayload: ((Event) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var active = false

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    func start() {
        guard !active else { return }
        active = true
        switch central.state {
        case .poweredOn:
            retrieveVerifiedPeripheral()
        case .unknown, .resetting:
            state = .waitingForBluetooth
        case .poweredOff:
            fail("Bluetooth is off. Raw FD50 capture did not start.")
        case .unauthorized:
            fail("Bluetooth permission is not authorized for Nembra Capture.")
        case .unsupported:
            fail("Bluetooth LE is not supported on this device.")
        @unknown default:
            fail("Bluetooth entered an unsupported state.")
        }
    }

    func stop() {
        active = false
        if let characteristic = notifyCharacteristic,
           characteristic.isNotifying,
           let peripheral {
            peripheral.setNotifyValue(false, for: characteristic)
        }
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        notifyCharacteristic = nil
        peripheral = nil
        state = .stopped
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard active else { return }
        switch central.state {
        case .poweredOn:
            retrieveVerifiedPeripheral()
        case .unknown, .resetting:
            state = .waitingForBluetooth
        case .poweredOff:
            fail("Bluetooth turned off during the authenticated raw-capture gate.")
        case .unauthorized:
            fail("Bluetooth permission became unavailable during the authenticated raw-capture gate.")
        case .unsupported:
            fail("Bluetooth LE became unavailable during the authenticated raw-capture gate.")
        @unknown default:
            fail("Bluetooth entered an unsupported state during the authenticated raw-capture gate.")
        }
    }

    private func retrieveVerifiedPeripheral() {
        guard active else { return }
        state = .retrievingVerifiedPeripheral
        let matches = central.retrievePeripherals(withIdentifiers: [Self.verifiedPeripheralIdentifier])
        guard matches.count == 1, let match = matches.first else {
            fail("The exact CoreBluetooth peripheral from physical capture C7D09A22 is not currently known to this iPhone. Nembra will not substitute a nearby Tuya device by name or RSSI.")
            return
        }
        peripheral = match
        match.delegate = self
        state = .connecting
        central.connect(match, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: false])
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active, peripheral.identifier == Self.verifiedPeripheralIdentifier else { return }
        state = .discovering
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard active, peripheral.identifier == Self.verifiedPeripheralIdentifier else { return }
        fail("The read-only FD50 observer could not attach to the authenticated scooter session: \(error?.localizedDescription ?? "unknown CoreBluetooth error")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard active, peripheral.identifier == Self.verifiedPeripheralIdentifier else { return }
        fail("The read-only FD50 observer disconnected before the authenticated evidence gate completed: \(error?.localizedDescription ?? "connection ended")")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard active, peripheral.identifier == Self.verifiedPeripheralIdentifier else { return }
        if let error {
            fail("FD50 service discovery failed: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services,
              let fd50 = services.first(where: { $0.uuid == Self.serviceUUID }) else {
            fail("The verified physical peripheral did not expose FD50 in this session.")
            return
        }
        state = .discovering
        peripheral.discoverCharacteristics([Self.notifyCharacteristicUUID], for: fd50)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard active,
              peripheral.identifier == Self.verifiedPeripheralIdentifier,
              service.uuid == Self.serviceUUID else { return }
        if let error {
            fail("FD50 notify-characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.notifyCharacteristicUUID }),
              characteristic.properties.contains(.notify) else {
            fail("The verified FD50 notify characteristic is missing or no longer advertises Notify.")
            return
        }
        notifyCharacteristic = characteristic
        state = .subscribing
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard active,
              peripheral.identifier == Self.verifiedPeripheralIdentifier,
              characteristic.uuid == Self.notifyCharacteristicUUID else { return }
        if let error {
            fail("FD50 notification subscription failed: \(error.localizedDescription)")
            return
        }
        guard characteristic.isNotifying else {
            fail("FD50 notification subscription did not become active.")
            return
        }
        state = .observing
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard active,
              peripheral.identifier == Self.verifiedPeripheralIdentifier,
              characteristic.uuid == Self.notifyCharacteristicUUID,
              characteristic.isNotifying else { return }
        if let error {
            fail("FD50 notification delivery failed: \(error.localizedDescription)")
            return
        }
        guard let payload = characteristic.value, !payload.isEmpty else { return }
        onPayload?(
            Event(
                receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                receivedAtWallClock: Date(),
                characteristicUUID: characteristic.uuid.uuidString,
                payload: payload
            )
        )
    }

    private func fail(_ reason: String) {
        guard active else { return }
        active = false
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        notifyCharacteristic = nil
        self.peripheral = nil
        state = .failed(reason)
    }
}
