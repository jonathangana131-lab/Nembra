from pathlib import Path
p=Path(__file__).resolve().parents[2]/'NembraApp/App/NembraCaptureEntrypoint.swift'
s=p.read_text()
old1='''            .accessibilityElement(children: .combine)\n        } else {'''
new1='''            .accessibilityElement(children: .combine)\n            .accessibilityLabel(\n                test.phase == .accepted\n                    ? "All 4 Capture steps complete, Seal"\n                    : "Step \\(currentStageIndex + 1) of 4, \\(stageLabels[currentStageIndex])"\n            )\n        } else {'''
old2='''.accessibilityLabel("Step \\(index + 1), \\(label)\\(index == currentStageIndex ? ", current" : index < currentStageIndex ? ", complete" : ", upcoming")")'''
new2='''.accessibilityLabel("Step \\(index + 1), \\(label)\\(test.phase == .accepted || index < currentStageIndex ? ", complete" : index == currentStageIndex ? ", current" : ", upcoming")")'''
for old,new in ((old1,new1),(old2,new2)):
    if s.count(old)!=1: raise SystemExit(f'target count {s.count(old)} for {old[:60]!r}')
    s=s.replace(old,new,1)
p.write_text(s)
stage=s[s.index('    private var stageRail: some View'):s.index('    private var primarySurface: some View')]
for t in ('All 4 Capture steps complete, Seal','test.phase == .accepted || index < currentStageIndex', '.accessibilityLabel('):
    if t not in stage: raise SystemExit(f'missing {t}')
