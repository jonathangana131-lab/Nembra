#!/usr/bin/env python3
"""Validation-only witness for Capture export local-BLE proof-state ambiguity.

A terminal success means the pinned parent is mechanically RED at this boundary:
its schema exports a bare Bool while production uses false both for explicit
observed loss and for fail-closed proof revocation. This file changes no product
code and creates no physical authority.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "NembraApp" / "App" / "NembraCaptureEntrypoint.swift"


def section(source: str, start: str, end: str) -> str:
    a = source.find(start)
    if a < 0:
        raise AssertionError(f"missing start marker: {start}")
    b = source.find(end, a + len(start))
    if b < 0:
        raise AssertionError(f"missing end marker after {start}: {end}")
    return source[a:b]


def main() -> None:
    source = APP.read_text(encoding="utf-8")
    export_struct = section(source, "    struct Export: Codable {", "    struct Event: Codable {")
    make_export = section(source, "    private func makeExport(", "    func prepareExport()")
    watchdog = section(source, "    private func startWatchdog", "    private func invalidateSourceAuthority")

    # Current-parent ambiguity must be proven exactly, not guessed from one token.
    assert "let sdkLocalBLEOnline: Bool" in export_struct
    assert "schemaVersion: 10" in make_export
    assert "sdkLocalBLEOnline: sdkLocalBLEOnline" in make_export

    # Accepted true is earned by a fresh direct post-seal sample before export freeze.
    seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)")
    direct_read = watchdog.index("driver.isLocallyConnected(uuid: self.tuyaUUID)", seal)
    mirror = watchdog.index("self.sdkLocalBLEOnline = postSealLocalBLEOnline", direct_read)
    true_fence = watchdog.index("guard postSealLocalBLEOnline else", mirror)
    freeze = watchdog.index("self.sealedAcceptedExport = self.makeExport(", true_fence)
    assert seal < direct_read < mirror < true_fence < freeze

    # The same app Bool is also cleared on paths that explicitly do NOT earn an
    # observed disconnect fact. A bare exported false therefore cannot safely be
    # interpreted as observed-offline by a machine consumer.
    not_proven_markers = [
        "no disconnect is claimed",
        "no disconnect time is inferred",
        "package already retired this exact generation without another liveness sample or a Bluetooth-disconnect claim",
    ]
    assert any(marker in source for marker in not_proven_markers)
    assert source.count("sdkLocalBLEOnline = false") >= 4

    # Real observed transport loss remains separately represented by an explicit
    # terminal path/event, proving absence-of-proof and observed loss are distinct facts.
    assert "private func recordObservedTransportLoss" in source
    assert 'log("sdk_local_ble_dropped"' in source

    # Current schema has no explicit export vocabulary that prevents false from
    # being promoted to an observed-offline claim.
    assert "sdkLocalBLECurrentProof" not in export_struct
    assert "observed-online" not in make_export
    assert "not-proven" not in make_export

    evidence = {
        "schemaVersion": 10,
        "exportedField": "sdkLocalBLEOnline: Bool",
        "acceptedTrueRequiresFreshPostSealDirectSample": True,
        "internalFalseAlsoMeansNotProven": True,
        "observedTransportLossHasSeparateEvent": True,
        "bareFalseCanEncodeObservedOfflineSafely": False,
        "parentExportTruthSafe": False,
        "productionAcceptanceClaimed": False,
        "physicalAuthorityCreated": False,
    }
    print(json.dumps(evidence, sort_keys=True))


if __name__ == "__main__":
    main()
