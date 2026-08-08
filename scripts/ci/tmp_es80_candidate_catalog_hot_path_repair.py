#!/usr/bin/env python3
from pathlib import Path

controller_path = Path(
    "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/"
    "ForegroundCoreBluetoothCaptureController.swift"
)
coordinator_path = Path(
    "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/"
    "PassiveBluetoothExperimentOneCoordinator.swift"
)

controller = controller_path.read_text(encoding="utf-8")
coordinator = coordinator_path.read_text(encoding="utf-8")

old_property = "    public private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []\n"
new_property = '''    /// Deterministic presentation snapshot. Sorting is deliberately paid by the
    /// presentation reader, never by CoreBluetooth's high-cadence discovery callback.
    public var discoveredPeripherals: [DiscoveredPeripheral] {
        latestDiscoveryByIdentifier.values.sorted {
            DiscoveredPeripheral.sortsBefore($0, $1)
        }
    }

    /// Exact UUID rediscovery authority is dictionary-backed and does not materialize
    /// or sort the presentation catalog.
    func hasDiscoveredPeripheral(identifier: UUID) -> Bool {
        latestDiscoveryByIdentifier[identifier] != nil
    }

    /// Read-only exact candidate lookup for coordinator connectability policy. This
    /// remains presentation/candidate state, not physical scooter authentication.
    func discoveredPeripheral(identifier: UUID) -> DiscoveredPeripheral? {
        latestDiscoveryByIdentifier[identifier]
    }
'''
if controller.count(old_property) != 1:
    raise SystemExit(f"stored discoveredPeripherals marker count={controller.count(old_property)}")
controller = controller.replace(old_property, new_property, 1)

old_update = '''    private func updateDiscoveryList() {
        discoveredPeripherals = latestDiscoveryByIdentifier.values.sorted {
            DiscoveredPeripheral.sortsBefore($0, $1)
        }
    }

'''
if controller.count(old_update) != 1:
    raise SystemExit(f"updateDiscoveryList marker count={controller.count(old_update)}")
controller = controller.replace(old_update, "", 1)

old_clear = '''        latestDiscoveryByIdentifier.removeAll()
        latestAdvertisementByIdentifier.removeAll()
        updateDiscoveryList()
'''
new_clear = '''        latestDiscoveryByIdentifier.removeAll()
        latestAdvertisementByIdentifier.removeAll()
'''
if controller.count(old_clear) != 1:
    raise SystemExit(f"clear-catalog marker count={controller.count(old_clear)}")
controller = controller.replace(old_clear, new_clear, 1)

old_callback = '''        latestDiscoveryByIdentifier[peripheral.identifier] = discovery
        updateDiscoveryList()

        do {
'''
new_callback = '''        latestDiscoveryByIdentifier[peripheral.identifier] = discovery

        do {
'''
if controller.count(old_callback) != 1:
    raise SystemExit(f"didDiscover callback marker count={controller.count(old_callback)}")
controller = controller.replace(old_callback, new_callback, 1)

old_connect = '''        guard let discovery = controller.discoveredPeripherals.first(where: { $0.id == identifier }) else {
            throw CoordinatorError.targetNotRediscovered
        }
        guard discovery.isConnectable != false else { throw CoordinatorError.targetNotConnectable }
'''
new_connect = '''        guard controller.hasDiscoveredPeripheral(identifier: identifier),
              let discovery = controller.discoveredPeripheral(identifier: identifier) else {
            throw CoordinatorError.targetNotRediscovered
        }
        guard discovery.isConnectable != false else { throw CoordinatorError.targetNotConnectable }
'''
if coordinator.count(old_connect) != 1:
    raise SystemExit(f"connect rediscovery marker count={coordinator.count(old_connect)}")
coordinator = coordinator.replace(old_connect, new_connect, 1)

old_status = '''        return controller.discoveredPeripherals.contains { $0.id == identifier }
'''
new_status = '''        return controller.hasDiscoveredPeripheral(identifier: identifier)
'''
if coordinator.count(old_status) != 1:
    raise SystemExit(f"status rediscovery marker count={coordinator.count(old_status)}")
coordinator = coordinator.replace(old_status, new_status, 1)

controller_path.write_text(controller, encoding="utf-8")
coordinator_path.write_text(coordinator, encoding="utf-8")

# Static acceptance equivalent to the permanent Swift source test, plus stricter
# checks that no hidden mutation of the presentation list survived.
controller = controller_path.read_text(encoding="utf-8")
coordinator = coordinator_path.read_text(encoding="utf-8")

required_controller = (
    "public var discoveredPeripherals: [DiscoveredPeripheral]",
    "latestDiscoveryByIdentifier.values.sorted",
    "DiscoveredPeripheral.sortsBefore($0, $1)",
    "func hasDiscoveredPeripheral(identifier: UUID) -> Bool",
    "latestDiscoveryByIdentifier[identifier] != nil",
    "func discoveredPeripheral(identifier: UUID) -> DiscoveredPeripheral?",
)
for token in required_controller:
    if token not in controller:
        raise SystemExit(f"controller contract missing: {token}")

for forbidden in (
    "public private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []",
    "private func updateDiscoveryList()",
    "discoveredPeripherals =",
    "discoveredPeripherals.removeAll",
):
    if forbidden in controller:
        raise SystemExit(f"callback/presentation architecture residue remains: {forbidden}")

callback_start = controller.index(
    "public func centralManager(\n        _ central: CBCentralManager,\n        didDiscover peripheral: CBPeripheral"
)
callback_end = controller.index(
    "public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)",
    callback_start,
)
callback = controller[callback_start:callback_end]
for token in (
    "latestDiscoveryByIdentifier[peripheral.identifier] = discovery",
    "latestAdvertisementByIdentifier[peripheral.identifier]",
    "enqueue(.advertisement(observation), receipt: receipt)",
):
    if token not in callback:
        raise SystemExit(f"didDiscover evidence/candidate contract missing: {token}")
for forbidden in ("updateDiscoveryList()", ".sorted"):
    if forbidden in callback:
        raise SystemExit(f"didDiscover still performs presentation work: {forbidden}")

for token in (
    "controller.hasDiscoveredPeripheral(identifier: identifier)",
    "controller.discoveredPeripheral(identifier: identifier)",
):
    if token not in coordinator:
        raise SystemExit(f"coordinator O(1) lookup contract missing: {token}")
for forbidden in (
    "controller.discoveredPeripherals.contains { $0.id == identifier }",
    "controller.discoveredPeripherals.first(where: { $0.id == identifier })",
):
    if forbidden in coordinator:
        raise SystemExit(f"coordinator still scans sorted presentation: {forbidden}")

print("candidate catalog callback hot-path repair: PASS")
