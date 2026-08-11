#!/usr/bin/env python3
from pathlib import Path

ISSUER=Path('scripts/ci/es80_authenticated_stationary_final_go.py')
WORKFLOW=Path('.github/workflows/capture-authenticated-stationary-final-go.yml')
source=ISSUER.read_text(encoding='utf-8')
old='''    blobs={path:git(root,"rev-parse",f"HEAD:{path}").lower() for path in paths}\n    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",value) for value in blobs.values()): raise GoError("GO control-plane Git blob identity invalid")\n    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"mainSHA":main_sha,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}\n'''
new='''    blobs={path:git(root,"rev-parse",f"HEAD:{path}").lower() for path in paths}\n    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",value) for value in blobs.values()): raise GoError("GO control-plane Git blob identity invalid")\n    for path in paths:\n        verbose=git(root,"ls-files","-v","--",path)\n        tagged=git(root,"ls-files","-t","--",path)\n        if not verbose or verbose[:1].islower() or tagged.startswith("S "):\n            raise GoError("GO control-plane authority path has suppressed index worktree tracking")\n        actual_blob=git(root,"hash-object","--no-filters","--",path).lower()\n        if actual_blob!=blobs[path]:\n            raise GoError("GO control-plane authority worktree bytes differ from accepted Git blob")\n    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"mainSHA":main_sha,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}\n'''
if source.count(old)!=1: raise SystemExit(f'issuer anchor count={source.count(old)}')
ISSUER.write_text(source.replace(old,new,1),encoding='utf-8')
workflow=WORKFLOW.read_text(encoding='utf-8')
path_line='      - scripts/ci/tests/test_es80_authenticated_stationary_signed_artifact_device_custody.py\n'
extra=path_line+'      - scripts/ci/tests/test_es80_final_go_control_worktree_custody.py\n'
if workflow.count(path_line)!=2: raise SystemExit('workflow path anchor drift')
workflow=workflow.replace(path_line,extra)
run_line='          python3 scripts/ci/tests/test_es80_authenticated_stationary_signed_artifact_device_custody.py\n'
if workflow.count(run_line)!=1: raise SystemExit('workflow run anchor drift')
workflow=workflow.replace(run_line,run_line+'          python3 scripts/ci/tests/test_es80_final_go_control_worktree_custody.py\n',1)
WORKFLOW.write_text(workflow,encoding='utf-8')
