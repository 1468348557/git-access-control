# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Git 门禁 (Git Gate) — a GitLab CI pipeline that enforces branch naming conventions and merge request rules for a multi-branch workflow. Scripts are hosted on an HTTP file server and downloaded by target projects at CI runtime via `ci_config_path`.

## Repository structure

```text
template/                  # 部署到 HTTP 服务器的文件，供业务项目 CI 下载
├── .gitlab-ci.yml         # CI Pipeline 定义（单 stage: gate）
└── scripts/
    └── git_gate.sh        # 门禁主脚本
server/
└── start-http.sh          # HTTP 文件服务器启动脚本
docs/
└── 部署指南.md             # 部署说明
git门禁规则.md              # 业务规则文档（权威来源）
```

## Pipeline

`template/.gitlab-ci.yml` defines a single `gate` stage, triggered on `push` and `merge_request_event`. Runner tag: `shell`. Scripts are downloaded from `${GATE_URL}` via curl at the start of each job.

## Script: `git_gate.sh`

Bash script (`set -euo pipefail`) that runs in GitLab CI. On `push` only branch naming is checked. On `merge_request_event`, five checks run in order:

1. **Branch naming** — Validates against allowed patterns; date portions must be real calendar dates.
2. **Merge direction** — Enforces allowed source→target pairs (see rules doc for full matrix).
3. **Diff size** — Counts added+deleted lines. ≤100 lines triggers auto-merge via GitLab API. >100 lines prints a warning (does not fail).
4. **MR title** — Title must contain 「合并」; hotfix/release→master with 「投产追板」 in description is exempt.
5. **Merge base** — Source must contain target's latest commit. Skipped for branches that both originate from master.

### CI variables consumed

| Variable | Usage |
| --- | --- |
| `CI_COMMIT_REF_NAME` | Branch name (push) |
| `CI_PIPELINE_SOURCE` | `push` or `merge_request_event` |
| `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME` | MR source branch |
| `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` | MR target branch |
| `CI_MERGE_REQUEST_TITLE` | MR title |
| `CI_MERGE_REQUEST_DESCRIPTION` | MR description (投产追板 exemption) |
| `CI_MERGE_REQUEST_IID` | MR IID (auto-merge API) |
| `CI_PROJECT_ID` | Project ID (auto-merge API) |
| `CI_API_V4_URL` / `CI_SERVER_URL` | GitLab API base URL |
| `GATE_URL` | HTTP server URL for script download |
| `GITLAB_PRIVATE_TOKEN` | PAT with `api` scope (auto-merge) |

## Business rules

`git门禁规则.md` is the authoritative source for allowed branch patterns, merge directions, and all validation rules. The script and the rules doc must stay in sync — when modifying either, update the other.

## CI variables (target projects)

| Variable | Description |
| --- | --- |
| `GATE_URL` | `http://21.73.16.160:8080/hobo-git-gate/template` |
| `GITLAB_PRIVATE_TOKEN` | Personal Access Token with `api` scope |

## Notes

- The HTTP server runs on port 8080, serving from `/home/hobo/hobo-git-gate/` via Python `http.server`.
- Crontab pulls the repo every minute; all target projects get the latest scripts on their next CI run.
- GitLab Shell runner runs as `gitlab-runner` user; `/tmp/gate` must be writable by this user.
