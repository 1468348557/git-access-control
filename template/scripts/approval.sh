#!/usr/bin/env bash
set -euo pipefail

echo "========== 审批 & 自动合并 =========="

SOURCE_BRANCH="${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}"
TARGET_BRANCH="${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}"
API_URL="${CI_API_V4_URL:-${CI_SERVER_URL}/api/v4}"
PROJECT_ID="${CI_PROJECT_ID}"
MR_IID="${CI_MERGE_REQUEST_IID}"
TOKEN="${GITLAB_PRIVATE_TOKEN}"

# 计算变更行数（不依赖 gate 阶段的 artifacts）
if [[ -n "${SOURCE_BRANCH}" ]] && [[ -n "${TARGET_BRANCH}" ]]; then
  git fetch origin "${TARGET_BRANCH}" 2>/dev/null
  target_sha="$(git rev-parse FETCH_HEAD)"
  git fetch origin "${SOURCE_BRANCH}" 2>/dev/null
  source_sha="$(git rev-parse FETCH_HEAD)"
  total_lines=$(git diff --numstat "${target_sha}...${source_sha}" 2>/dev/null \
    | awk '{ added+=$1; deleted+=$2 } END { print (added+deleted+0) }')
  echo "变更总行数: ${total_lines}"
else
  echo "无法获取分支信息，跳过"
  exit 0
fi

if [[ "${total_lines}" -le 100 ]]; then
  echo "变更 ≤100 行，已由 gate 阶段自动合并，跳过"
  exit 0
fi

echo "MR 变更 ${total_lines} 行（超过100行阈值），人工审批已通过"
echo "请管理员在 GitLab 上点击 Merge 按钮完成合并"

echo "========== 审批完成 =========="
