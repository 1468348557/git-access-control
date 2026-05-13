# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Git 门禁 (Git Gate) — a GitLab CI pipeline script that enforces branch naming conventions and merge request rules for a multi-branch workflow.

## Pipeline

`.gitlab-ci.yml` defines a single-stage `gate` pipeline triggered on both `push` and `merge_request_event`. It runs `scripts/git_gate.sh` with a GitLab Shell runner. `GIT_DEPTH: "0"` ensures full history for merge-base checks.

## Script: `git_gate.sh`

Bash script (`set -euo pipefail`) that runs in GitLab CI. Three checks, executed in order:

1. **Branch naming** — Validates against: `FIX|REQ|PUB-YYYYMMDD-NNNN`, `hotfix-YYYYMMDD`, `release-YYYYMMDD`. Also checks that the date portion is a real calendar date.
2. **Merge direction** (MR only) — Enforces allowed source→target pairs:
   - `FIX/REQ/PUB-*` → `uat` or `uat_YYYYMMDD`
   - `hotfix-*` → `master`
   - `release-*` → `master`
3. **Merge base** (MR only) — Source branch must contain the target branch's latest commit (ancestor check via `git merge-base --is-ancestor`).

On `push` events, only branch naming is checked. On `merge_request_event`, all three checks run.

### CI variables consumed

| Variable | Source |
|---|---|
| `CI_COMMIT_REF_NAME` | Branch name (used on push) |
| `CI_PIPELINE_SOURCE` | `push` or `merge_request_event` |
| `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME` | MR source branch |
| `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` | MR target branch |

## Notes

- The CI config references `scripts/git_gate.sh` but the script is at repo root as `git_gate.sh`. Deployment likely copies it into `scripts/`.
- `git门禁规则` documents the business rules; the last line about "MRs over 100 lines need manual approval" is not yet implemented.
- GitLab Shell runner tag is `shell`.
