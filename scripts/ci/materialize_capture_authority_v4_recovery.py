from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
AUTHORING = Path(".github/workflows/capture-carrier-authority-v2-materialize-once.yml")


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return source.replace(old, new, 1)


def apply_reviewed_v2_transform() -> None:
    authoring = AUTHORING.read_text(encoding="utf-8")
    start = "          cat > \"${RUNNER_TEMP}/materialize_capture_authority_v2.py\" <<'PY'\n"
    end = "          PY\n\n      - name: Materialize against latest reviewed carrier source\n"
    if authoring.count(start) != 1 or authoring.count(end) != 1:
        raise SystemExit("reviewed V2 transform markers changed; refusing")
    body = authoring.split(start, 1)[1].split(end, 1)[0]
    lines = body.splitlines()
    if any(line and not line.startswith("          ") for line in lines):
        raise SystemExit("unexpected V2 transform indentation; refusing")
    script = "\n".join(line[10:] if line else "" for line in lines) + "\n"
    exec(compile(script, "capture-authority-v2", "exec"), {"__name__": "__main__"})


def apply_v3_fail_closed_corrections() -> None:
    source = APP.read_text(encoding="utf-8")
    source = replace_once(
        source,
        """            if phase == .failed {\n                fieldAuthorization.revoke()\n                operatorSafetyAttemptID = nil\n""",
        """            if phase == .failed {\n                if fieldAuthorization.stage != .armed {\n                    fieldAuthorization.revoke()\n                }\n                operatorSafetyAttemptID = nil\n""",
        "armed-preservation",
    )
    source = replace_once(
        source,
        """                            self.currentConnectionToken = nil\n                            self.localBLESettlementToken = nil\n                            self.sdkLocalBLEOnline = false\n                            self.driver = nil\n                            self.fieldAuthorization.revoke()\n                            self.phase = .failed\n                            self.message = \"Accepted observation could not freeze and seal one exact authorized artifact: \\(error.localizedDescription). Relaunch Capture before another attempt.\"\n                            self.log(\"field_authorization_exact_artifact_seal_failed\", [\n                                \"generation\": String(token.diagnosticGeneration)\n                            ])\n                            return\n""",
        """                            self.currentConnectionToken = nil\n                            self.localBLESettlementToken = nil\n                            self.sdkLocalBLEOnline = false\n                            self.driver = nil\n                            self.fieldAuthorization.revoke()\n                            self.failLocally(\n                                \"Accepted observation could not freeze and seal one exact authorized artifact: \\(error.localizedDescription). Relaunch Capture before another attempt.\",\n                                \"field_authorization_exact_artifact_seal_failed\"\n                            )\n                            return\n""",
        "seal-failure lifecycle",
    )
    APP.write_text(source, encoding="utf-8")


if __name__ == "__main__":
    apply_reviewed_v2_transform()
    apply_v3_fail_closed_corrections()
