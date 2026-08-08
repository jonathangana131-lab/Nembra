from pathlib import Path

path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift")
source = path.read_text()

payload_anchor = """    struct Payload {
"""
preview = """    /// Read-only package staging information for recoverable pre-consumption checks.
    ///
    /// This is not capture authority: it deliberately carries no recorder or raw power-cycle
    /// evidence. Construction is producer-file private so another package file cannot mint a
    /// lookalike preview and substitute a caller-selected target. The exact admission identity
    /// lets the eventual consumer prove the consumed payload is the same sealed handoff it staged.
    struct StagingPreview: Equatable, Sendable {
        let admissionIdentity: UUID
        let peripheralIdentifier: UUID
        let issuedAtUptimeNanoseconds: UInt64

        fileprivate init(
            admissionIdentity: UUID,
            peripheralIdentifier: UUID,
            issuedAtUptimeNanoseconds: UInt64
        ) {
            self.admissionIdentity = admissionIdentity
            self.peripheralIdentifier = peripheralIdentifier
            self.issuedAtUptimeNanoseconds = issuedAtUptimeNanoseconds
        }
    }

    struct Payload {
"""
if source.count(payload_anchor) != 1:
    raise SystemExit("expected exactly one Payload anchor")
source = source.replace(payload_anchor, preview, 1)

consume_anchor = """    func consume() throws -> Payload {
"""
preview_method = """    /// Exposes only enough sealed producer state to perform recoverable controller staging before
    /// the one-shot ownership handoff is burned. A consumed admission cannot be previewed again.
    func stagingPreview() throws -> StagingPreview {
        guard !hasBeenConsumed else {
            throw ConsumptionError.alreadyConsumed
        }
        return StagingPreview(
            admissionIdentity: payload.admissionIdentity,
            peripheralIdentifier: payload.peripheralIdentifier,
            issuedAtUptimeNanoseconds: payload.issuedAtUptimeNanoseconds
        )
    }

    func consume() throws -> Payload {
"""
if source.count(consume_anchor) != 1:
    raise SystemExit("expected exactly one consume anchor")
source = source.replace(consume_anchor, preview_method, 1)
path.write_text(source)
