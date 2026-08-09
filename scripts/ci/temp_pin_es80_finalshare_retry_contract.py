#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
text = path.read_text(encoding="utf-8")
old = '''        XCTAssertTrue(\n            source.contains("guard let data = finalShareData"),\n            "A temporary Share-file retry must reuse retained verified bytes rather than mint a new evidence artifact."\n        )\n'''
new = '''        XCTAssertTrue(\n            source.contains("if finalShareData != nil,"),\n            "A temporary Share-file retry must require retained verified final Share bytes."\n        )\n        XCTAssertTrue(\n            source.contains("finalShareIntegrityReport != nil,"),\n            "A temporary Share-file retry must retain the exact integrity report rather than mint new evidence."\n        )\n        XCTAssertTrue(\n            source.contains("finalShareFilename != nil {"),\n            "A temporary Share-file retry must retain the verified filename alongside the verified bytes."\n        )\n'''
if text.count(old) != 1:
    raise SystemExit(f"expected exactly one stale retained-Share assertion block, found {text.count(old)}")
text = text.replace(old, new, 1)
if 'source.contains("guard let data = finalShareData")' in text:
    raise SystemExit("stale guard-let assertion survived transform")
for required in (
    'source.contains("if finalShareData != nil,")',
    'source.contains("finalShareIntegrityReport != nil,")',
    'source.contains("finalShareFilename != nil {")',
):
    if required not in text:
        raise SystemExit(f"missing retained Share authority assertion: {required}")
path.write_text(text, encoding="utf-8")
