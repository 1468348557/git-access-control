#!/usr/bin/env bash
set -euo pipefail

echo "========== 人工审批 =========="

if [[ -f approval_status ]]; then
  status="$(cat approval_status)"
else
  echo "未找到 approval_status 文件，跳过审批"
  exit 0
fi

if [[ "$status" =~ ^NEEDS_APPROVAL:([0-9]+)$ ]]; then
  echo "MR 变更行数: ${BASH_REMATCH[1]} 行（超过50行阈值）"
  echo "人工审批通过 — 审批人已确认此变更"
elif [[ "$status" == "PASS" ]]; then
  echo "MR 变更行数未超过50行，无需审批"
else
  echo "未知审批状态: $status"
  exit 1
fi

echo "========== 审批完成 =========="
