#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/field/install_one_time_capture.command")
source = path.read_text(encoding="utf-8")
old = '''/usr/bin/sudo /usr/bin/ditto "$APP" "$APP_INSTALL_STAGE" || \\
    die "Could not snapshot the exact signed app into protected install custody."
# The stage root is still root mode-0700 here, so the invoking user cannot race this seal. BSD
'''
new = '''/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE" || \\
    die "Could not snapshot the exact signed app into protected install custody without inherited ACL authority."
STAGED_ACL_PATH="$(/usr/bin/sudo /usr/bin/find "$APP_INSTALL_STAGE_ROOT" -acl -print -quit 2>/dev/null || true)"
[[ -z "$STAGED_ACL_PATH" ]] || \\
    die "Protected signed-app install stage retained an ACL at $STAGED_ACL_PATH; refuse to expose or install it."
unset STAGED_ACL_PATH || true
# The stage root is still root mode-0700 here, so the invoking user cannot race this seal. BSD
'''
count = source.count(old)
if count != 1:
    raise SystemExit(f"expected one signed-app staging marker, found {count}")
source = source.replace(old, new, 1)
path.write_text(source, encoding="utf-8")
