#!/usr/bin/env python3
from pathlib import Path

workflow_path = Path('.github/workflows/capture-standalone-visual-evidence.yml')
harness_path = Path('scripts/ci/capture_standalone_visual_evidence.sh')
test_path = Path('scripts/ci/tests/test_capture_standalone_visual_evidence.py')

workflow = workflow_path.read_text(encoding='utf-8')
harness = harness_path.read_text(encoding='utf-8')
test = test_path.read_text(encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}: {old!r}')
    return text.replace(old, new, 1)

workflow = replace_once(
    workflow,
    "          grep -Fq 'static let fieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\"' NembraApp/App/NembraCaptureBuildIdentity.swift\n",
    "          grep -Fq 'static let requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\"' NembraApp/App/NembraCaptureBuildIdentity.swift\n"
    "          grep -Fq 'static var fieldProcedureIdentifier: String' NembraApp/App/NembraCaptureBuildIdentity.swift\n"
    "          grep -Fq 'current.procedureIdentifier' NembraApp/App/NembraCaptureBuildIdentity.swift\n",
    'workflow required procedure declaration',
)
workflow = replace_once(
    workflow,
    "          grep -Fq 'procedureIdentifier == Self.fieldProcedureIdentifier' NembraApp/App/NembraCaptureBuildIdentity.swift\n",
    "          grep -Fq 'procedureIdentifier == Self.requiredFieldProcedureIdentifier' NembraApp/App/NembraCaptureBuildIdentity.swift\n",
    'workflow authority equality',
)
workflow = replace_once(
    workflow,
    '          assert record["procedureIdentifier"] == "ES80-AUTHENTICATED-STATIONARY-v1"\n',
    '          assert record["requiredProcedureIdentifier"] == "ES80-AUTHENTICATED-STATIONARY-v1"\n'
    '          assert record["procedureIdentifier"] == record["requiredProcedureIdentifier"]\n',
    'workflow manifest procedure assertion',
)

harness = replace_once(
    harness,
    'if [[ ! -f "$IDENTITY_SOURCE" ]] || ! grep -Fq "static let fieldProcedureIdentifier = \\"$EXPECTED_PROCEDURE_IDENTIFIER\\"" "$IDENTITY_SOURCE"; then\n'
    '  echo "Standalone Capture source does not declare the canonical stationary procedure." >&2\n'
    '  exit 19\n'
    'fi\n',
    'if [[ ! -f "$IDENTITY_SOURCE" ]] || \\\n'
    '   ! grep -Fq "static let requiredFieldProcedureIdentifier = \\"$EXPECTED_PROCEDURE_IDENTIFIER\\"" "$IDENTITY_SOURCE" || \\\n'
    '   ! grep -Fq "static var fieldProcedureIdentifier: String" "$IDENTITY_SOURCE" || \\\n'
    '   ! grep -Fq "current.procedureIdentifier" "$IDENTITY_SOURCE"; then\n'
    '  echo "Standalone Capture source does not preserve required-vs-built stationary procedure truth." >&2\n'
    '  exit 19\n'
    'fi\n',
    'harness source procedure truth',
)
harness = replace_once(
    harness,
    '    "procedureIdentifier": procedure_identifier,\n',
    '    "requiredProcedureIdentifier": "ES80-AUTHENTICATED-STATIONARY-v1",\n'
    '    "procedureIdentifier": procedure_identifier,\n',
    'harness manifest required procedure',
)

test = replace_once(
    test,
    "    'static let fieldProcedureIdentifier = \\\"$EXPECTED_PROCEDURE_IDENTIFIER\\\"',\n",
    "    'static let requiredFieldProcedureIdentifier = \\\"$EXPECTED_PROCEDURE_IDENTIFIER\\\"',\n"
    "    'static var fieldProcedureIdentifier: String',\n"
    "    'current.procedureIdentifier',\n",
    'test harness source procedure requirements',
)
test = replace_once(
    test,
    "    'procedureIdentifier == Self.fieldProcedureIdentifier',\n",
    "    'procedureIdentifier == Self.requiredFieldProcedureIdentifier',\n",
    'test workflow authority equality',
)
test = replace_once(
    test,
    "    '\"procedureIdentifier\": procedure_identifier',\n",
    "    '\"requiredProcedureIdentifier\": \"ES80-AUTHENTICATED-STATIONARY-v1\"',\n"
    "    '\"procedureIdentifier\": procedure_identifier',\n",
    'test manifest required procedure',
)

workflow_path.write_text(workflow, encoding='utf-8')
harness_path.write_text(harness, encoding='utf-8')
test_path.write_text(test, encoding='utf-8')
