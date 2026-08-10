from pathlib import Path

path = Path('.github/workflows/capture-field-build-provenance.yml')
text = path.read_text(encoding='utf-8')

old_checkout = '''      - uses: actions/checkout@v4

      - name: Validate private Tuya input provenance helper
'''
new_checkout = '''      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}

      - name: Bind job to exact checked-out source
        shell: bash
        env:
          EXPECTED_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
        run: |
          set -euo pipefail
          expected="$(printf '%s' "$EXPECTED_HEAD_SHA" | tr '[:upper:]' '[:lower:]')"
          actual="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
          [[ "$expected" =~ ^[0-9a-f]{40}$ ]]
          test "$actual" = "$expected"
          test -z "$(git status --porcelain=v1 --untracked-files=all)"
          printf 'CAPTURE_PROVENANCE_SOURCE_SHA=%s\\n' "$actual" >> "$GITHUB_ENV"
          printf 'Exact provenance source: %s\\n' "$actual"

      - name: Validate private Tuya input provenance helper
'''
if text.count(old_checkout) != 1:
    raise SystemExit(f'exact checkout anchor changed: {text.count(old_checkout)}')
text = text.replace(old_checkout, new_checkout, 1)

old_build = '''          sha='0123456789abcdef0123456789abcdef01234567'
          dependency_sha='abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'
          procedure='ES80-AUTHENTICATED-STATIONARY-v1'
          label='capture-v14-0123456789ab'
'''
new_build = '''          sha="${CAPTURE_PROVENANCE_SOURCE_SHA:?exact source was not established}"
          dependency_sha='abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'
          procedure='ES80-AUTHENTICATED-STATIONARY-v1'
          label="capture-v14-${sha:0:12}"
'''
if text.count(old_build) != 1:
    raise SystemExit(f'provenance build subject anchor changed: {text.count(old_build)}')
text = text.replace(old_build, new_build, 1)

required = (
    "ref: ${{ github.event.pull_request.head.sha || github.sha }}",
    'test -z "$(git status --porcelain=v1 --untracked-files=all)"',
    'CAPTURE_PROVENANCE_SOURCE_SHA=%s',
    'sha="${CAPTURE_PROVENANCE_SOURCE_SHA:?exact source was not established}"',
    'label="capture-v14-${sha:0:12}"',
    'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="$procedure"',
    'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";',
)
combined = text + Path('NembraCapture.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
for item in required:
    if item not in combined:
        raise SystemExit(f'missing exact provenance contract: {item}')

# The stronger unified path must not regress to an installer/provenance-only Info.plist override.
if 'INFOPLIST_KEY_NembraCaptureProcedureIdentifier="$procedure"' in text:
    raise SystemExit('direct Info.plist procedure override bypassed the unified Xcode build-setting path')

path.write_text(text, encoding='utf-8')
