#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
path = root / "NembraApp/App/NembraCaptureEntrypoint.swift"
text = path.read_text(encoding="utf-8")
old = '''                        guard let self,
                              !update.isEmpty,
                              self.currentConnectionToken == token,
                              !self.acceptanceCutIsClosed else { return }
'''
new = '''                        guard let self,
                              !update.isEmpty,
                              self.currentConnectionToken == token,
                              self.phase == .observing,
                              !self.acceptanceCutIsClosed else { return }
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f"expected exact callback admission guard once, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
