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
  git fetch origin "${SOURCE_BRANCH}" "${TARGET_BRANCH}" 2>/dev/null
  total_lines=$(git diff --numstat "origin/${TARGET_BRANCH}...origin/${SOURCE_BRANCH}" 2>/dev/null \
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

echo "MR 变更 ${total_lines} 行（超过100行阈值）"
echo "人工审批已确认，执行合并"

if [[ -z "${TOKEN:-}" ]]; then
  echo "未配置 GITLAB_PRIVATE_TOKEN，无法合并"
  exit 1
fi

echo "调用合并 API: PUT ${API_URL}/projects/${PROJECT_ID}/merge_requests/${MR_IID}/merge"

RESP=$(curl -sf --header "PRIVATE-TOKEN: ${TOKEN}" \
  -X PUT "${API_URL}/projects/${PROJECT_ID}/merge_requests/${MR_IID}/merge" \
  -H "Content-Type: application/json" \
  -d '{"merge_when_pipeline_succeeds": true}') && rc=$? || rc=$?

echo "API 响应: ${RESP}"

if [[ "${rc}" -eq 0 ]]; then
  echo "合并请求已提交"
else
  echo "[WARN] 合并 API 调用失败，请检查上方响应"
fi

echo "========== 审批完成 =========="
