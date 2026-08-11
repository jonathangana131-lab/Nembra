#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/ci/es80_authenticated_stationary_final_go.py")
source = path.read_text(encoding="utf-8")
old = '''    paths=("scripts/ci/es80_authenticated_stationary_final_go.py","scripts/ci/es80_authenticated_stationary_signed_artifact.py","scripts/ci/es80_today_final_go_publication.py",AUTH_WORKFLOW_PATH,"scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
    blobs={path:git(root,"rev-parse",f"HEAD:{path}").lower() for path in paths}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",value) for value in blobs.values()): raise GoError("GO control-plane Git blob identity invalid")
    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"mainSHA":main_sha,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}
'''
new = '''    paths=("scripts/ci/es80_authenticated_stationary_final_go.py","scripts/ci/es80_authenticated_stationary_signed_artifact.py","scripts/ci/es80_today_final_go_publication.py",AUTH_WORKFLOW_PATH,"scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
    blobs={path:git(root,"rev-parse",f"HEAD:{path}").lower() for path in paths}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",value) for value in blobs.values()): raise GoError("GO control-plane Git blob identity invalid")
    for relative in paths:
        current=root/relative
        if not current.is_file() or current.is_symlink(): raise GoError("GO control-plane authority path is not a regular non-symlink file")
        verbose=git(root,"ls-files","-v","--",relative)
        tagged=git(root,"ls-files","-t","--",relative)
        if not verbose or verbose[:1].islower() or tagged.startswith("S "):
            raise GoError("GO control-plane authority path has suppressed index worktree tracking")
        actual_blob=git(root,"hash-object","--no-filters","--",relative).lower()
        if actual_blob!=blobs[relative]: raise GoError("GO control-plane authority worktree bytes differ from accepted Git blob")
    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"mainSHA":main_sha,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}
'''
if source.count(old) != 1:
    raise SystemExit("expected exact control_plane authority block was not found once")
path.write_text(source.replace(old, new), encoding="utf-8")
