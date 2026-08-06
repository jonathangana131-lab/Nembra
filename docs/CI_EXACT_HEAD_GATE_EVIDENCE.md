# Xcode 27 exact-head PR gate live evidence

Date: 2026-08-06
Worker: `chat-f2k7q`

This document is the durable live-validation record for the supplemental `Xcode 27 PR Exact-Head QA` workflow.

## Purpose

The v5 swarm needs a way to obtain required exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator proof even when connector-authored `parallel/**` branch updates do not emit the repository's older push workflow.

PR #35 introduced a trusted exact-head resolver and Xcode gate. PR #39 added same-repository non-draft `pull_request` triggers because a connector-created `/xcode27` comment on PR #34 produced no `issue_comment` workflow run.

This evidence PR intentionally starts **non-draft** from fresh `main` so its own `pull_request.opened` event can test the new automatic acceptance path without editing another worker's branch.

## Expected first-run contract

For this PR's opening head, GitHub Actions should:

1. create an `Xcode 27 PR Exact-Head QA` run from the `pull_request` `opened` event;
2. execute `Resolve trusted same-repo PR head` on `ubuntu-latest`;
3. resolve this PR's immutable head SHA and confirm its head repository is Nembra;
4. start `Build, test, and capture exact PR head` on `xcode-27`;
5. check out the resolved SHA;
6. print expected and actual checkout SHA and fail if they differ;
7. run project structure checks, `Packages/NembraCore` tests, and the Xcode 27 Simulator capture script;
8. upload the normal Simulator evidence artifact.

## Evidence state

`pull_request.opened`: **PENDING LIVE PROOF**

`synchronize after ready`: **PENDING LIVE PROOF**

Exact final-head Simulator QA: **PENDING LIVE PROOF**

No physical AOVOPRO ES80 behavior is tested or implied by this workflow evidence.

## Next evidence checkpoint

After the first run is observed, update this document with the run ID, resolved head, job/step result, and any real failure. Because the PR remains non-draft, that document update should emit a `pull_request.synchronize` event and request a second exact-head gate on the new final documentation head. Only the second unchanged-head result can serve as this PR's merge proof.
