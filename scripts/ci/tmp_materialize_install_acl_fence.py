#!/usr/bin/env python3
from pathlib import Path

INSTALLER = Path("scripts/field/install_one_time_capture.command")
TEST = Path("scripts/ci/tests/test_capture_signed_app_install_custody.py")
WORKFLOW = Path(".github/workflows/capture-signed-app-install-custody.yml")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


source = INSTALLER.read_text(encoding="utf-8")
source = replace_once(
    source,
    '''/usr/bin/sudo /usr/bin/ditto "$APP" "$APP_INSTALL_STAGE" || die "Could not snapshot the signed app into the protected install stage."
/usr/bin/sudo /usr/sbin/chown -R root:wheel "$APP_INSTALL_STAGE_ROOT" || die "Could not root-own the protected signed-app install stage."
''',
    '''/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE" || die "Could not snapshot the signed app into the protected install stage without inherited ACL authority."
STAGE_ACL_ENTRY="$(/usr/bin/sudo /usr/bin/find "$APP_INSTALL_STAGE_ROOT" -acl -print -quit)" || \\
    die "Could not inspect the protected signed-app stage for extended ACL authority."
[[ -z "$STAGE_ACL_ENTRY" ]] || die "Protected signed-app stage retained an ACL; do not expose or install it."
unset STAGE_ACL_ENTRY
/usr/bin/sudo /usr/sbin/chown -R root:wheel "$APP_INSTALL_STAGE_ROOT" || die "Could not root-own the protected signed-app install stage."
''',
    "ditto ACL admission",
)
INSTALLER.write_text(source, encoding="utf-8")

text = TEST.read_text(encoding="utf-8")
text = replace_once(
    text,
    '''        snapshot_marker = '/usr/bin/sudo /usr/bin/ditto "$APP" "$APP_INSTALL_STAGE"'
        owner_marker = '/usr/bin/sudo /usr/sbin/chown -R root:wheel "$APP_INSTALL_STAGE_ROOT"'
''',
    '''        snapshot_marker = '/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE"'
        acl_marker = '/usr/bin/find "$APP_INSTALL_STAGE_ROOT" -acl -print -quit'
        owner_marker = '/usr/bin/sudo /usr/sbin/chown -R root:wheel "$APP_INSTALL_STAGE_ROOT"'
''',
    "source test ACL marker",
)
text = replace_once(
    text,
    '''            ("snapshot", snapshot_marker),
            ("owner", owner_marker),
''',
    '''            ("snapshot", snapshot_marker),
            ("acl", acl_marker),
            ("owner", owner_marker),
''',
    "source test ACL ordering input",
)
text = replace_once(
    text,
    '''        self.assertLess(indexes["fingerprint"], indexes["stage"])
        self.assertLess(indexes["stage"], indexes["snapshot"])
        self.assertLess(indexes["snapshot"], indexes["owner"])
''',
    '''        self.assertLess(indexes["fingerprint"], indexes["stage"])
        self.assertLess(indexes["stage"], indexes["snapshot"])
        self.assertLess(indexes["snapshot"], indexes["acl"])
        self.assertLess(indexes["acl"], indexes["owner"])
''',
    "source test ACL ordering assertions",
)
text = replace_once(
    text,
    '''        self.assertIn('same unprivileged uid', source)
''',
    '''        self.assertIn('same unprivileged uid', source)
        self.assertIn('Protected signed-app stage retained an ACL', source)
        self.assertNotIn('/usr/bin/sudo /usr/bin/ditto "$APP" "$APP_INSTALL_STAGE"', source)
''',
    "source test ACL assertions",
)
TEST.write_text(text, encoding="utf-8")

workflow = WORKFLOW.read_text(encoding="utf-8")
append = r'''

  macos-acl-copy:
    name: Prove ditto strips source ACL authority on macOS
    runs-on: xcode-27
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v6
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}

      - name: Bind ACL proof to exact checked-out source
        shell: bash
        env:
          EXPECTED_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
        run: |
          set -euo pipefail
          test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD_SHA"
          test -z "$(git status --porcelain=v1 --untracked-files=all)"

      - name: Prove production no-ACL copy on Darwin
        shell: bash
        run: |
          set -euo pipefail
          source_root="$(mktemp -d)"
          stage_root=""
          cleanup() {
            rm -rf -- "$source_root"
            if [[ -n "$stage_root" ]]; then sudo /bin/rm -rf -- "$stage_root"; fi
          }
          trap cleanup EXIT

          mkdir -p "$source_root/Nembra Capture.app"
          printf 'acl-bearing source\n' > "$source_root/Nembra Capture.app/subject.txt"
          /bin/chmod +a "$USER allow write" "$source_root/Nembra Capture.app/subject.txt"
          test -n "$(/usr/bin/find "$source_root" -acl -print -quit)"

          stage_root="$(sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX)"
          sudo /usr/bin/ditto --noacl "$source_root/Nembra Capture.app" "$stage_root/Nembra Capture.app"
          test -z "$(sudo /usr/bin/find "$stage_root" -acl -print -quit)"
'''
if "macos-acl-copy:" in workflow:
    raise SystemExit("macOS ACL proof already exists")
WORKFLOW.write_text(workflow.rstrip() + append + "\n", encoding="utf-8")
