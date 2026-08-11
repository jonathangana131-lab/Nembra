#!/usr/bin/env python3
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = ".replace('\\\\\\\"', '\"')"
new = ".replace('\\\\\"', '\"')"
if source.count(old) != 1:
    raise SystemExit(f"quote normalization marker drifted: found {source.count(old)}")
path.write_text(source.replace(old, new, 1), encoding="utf-8")
