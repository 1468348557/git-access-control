#!/usr/bin/env bash
set -euo pipefail

echo "========== Git 门禁开始 =========="

BRANCH_NAME="${CI_COMMIT_REF_NAME:-}"
PIPELINE_SOURCE="${CI_PIPELINE_SOURCE:-}"
MR_SOURCE_BRANCH="${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}"
MR_TARGET_BRANCH="${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}"
MR_TITLE="${CI_MERGE_REQUEST_TITLE:-}"

BRANCH_PATTERN='^((FIX|REQ|PUB)-[0-9]{8}-[0-9]{4}(-.+)?|(hotfix|release)-[0-9]{8}|comp|feature|master|uat|sit)'
BUSINESS_BRANCH_PATTERN='^(FIX|REQ|PUB)-[0-9]{8}-[0-9]{4}(-.+)?$'
HOTFIX_BRANCH_PATTERN='^hotfix-[0-9]{8}$'
RELEASE_BRANCH_PATTERN='^release-[0-9]{8}$'
COMP_BRANCH_PATTERN='^comp'
FEATURE_BRANCH_PATTERN='^feature'
UAT_TARGET_PATTERN='^uat'
SIT_TARGET_PATTERN='^sit'

fail() {
  echo ""
  echo "[FAIL] $1"
  echo ""
  exit 1
}

pass() {
  echo "[PASS] $1"
}

check_date_valid() {
  local date_part="$1"

  local formatted_date
  # macOS (BSD) 用 -j -f，Linux (GNU) 用 -d
  if formatted_date=$(date -j -f "%Y%m%d" "$date_part" +"%Y%m%d" 2>/dev/null); then
    :
  elif formatted_date=$(date -d "$date_part" +"%Y%m%d" 2>/dev/null); then
    :
  else
    return 1
  fi

  [[ "$formatted_date" == "$date_part" ]]
}

# 1. 分支命名校验
check_branch_name() {
  local branch="$1"

  echo "检查分支命名: $branch"

  if [[ ! "$branch" =~ $BRANCH_PATTERN ]]; then
    fail "分支命名不符合规范: $branch
允许格式:
  1. FIX-YYYYMMDD-NNNN[-额外名称]
  2. REQ-YYYYMMDD-NNNN[-额外名称]
  3. PUB-YYYYMMDD-NNNN[-额外名称]
  4. hotfix-YYYYMMDD
  5. release-YYYYMMDD
  6. comp*
  7. feature*"
  fi

  local date_part=""

  if [[ "$branch" =~ $BUSINESS_BRANCH_PATTERN ]]; then
    date_part="$(echo "$branch" | awk -F- '{print $2}')"
  elif [[ "$branch" =~ $HOTFIX_BRANCH_PATTERN ]]; then
    date_part="$(echo "$branch" | awk -F- '{print $2}')"
  elif [[ "$branch" =~ $RELEASE_BRANCH_PATTERN ]]; then
    date_part="$(echo "$branch" | awk -F- '{print $2}')"
  fi

  if [[ -n "$date_part" ]]; then
    if ! check_date_valid "$date_part"; then
      fail "分支名中的日期不合法: $date_part"
    fi
  fi

  pass "分支命名校验通过"
}

# 判断源分支是否为业务/comp/feature 类型
is_uat_style_source() {
  local branch="$1"
  [[ "$branch" =~ $BUSINESS_BRANCH_PATTERN ]] || \
  [[ "$branch" =~ $COMP_BRANCH_PATTERN ]] || \
  [[ "$branch" =~ $FEATURE_BRANCH_PATTERN ]]
}

# 2. 合并方向校验
check_merge_direction() {
  local source_branch="$1"
  local target_branch="$2"

  echo "检查合并方向: ${source_branch} -> ${target_branch}"

  if is_uat_style_source "${source_branch}"; then
    if [[ "$target_branch" =~ $UAT_TARGET_PATTERN ]] || \
       [[ "$target_branch" =~ $SIT_TARGET_PATTERN ]] || \
       [[ "$target_branch" =~ $HOTFIX_BRANCH_PATTERN ]] || \
       [[ "$target_branch" =~ $RELEASE_BRANCH_PATTERN ]]; then
      pass "合并方向校验通过"
      return 0
    fi
    # FIX/REQ/PUB 之间可以互相合并
    if [[ "$source_branch" =~ $BUSINESS_BRANCH_PATTERN ]] && \
       [[ "$target_branch" =~ $BUSINESS_BRANCH_PATTERN ]]; then
      pass "合并方向校验通过"
      return 0
    fi
    fail "不允许的合并方向: ${source_branch} -> ${target_branch}
允许方向:
  - FIX/REQ/PUB/comp/feature -> uat*
  - FIX/REQ/PUB/comp/feature -> sit*
  - FIX/REQ/PUB/comp/feature -> hotfix
  - FIX/REQ/PUB/comp/feature -> release
  - FIX/REQ/PUB -> FIX/REQ/PUB"
    fi

  if [[ "$source_branch" =~ $HOTFIX_BRANCH_PATTERN ]]; then
    if [[ "$target_branch" == "master" ]] || \
       [[ "$target_branch" =~ $RELEASE_BRANCH_PATTERN ]]; then
      pass "hotfix 分支合并方向校验通过"
      return 0
    else
      fail "不允许的合并方向: ${source_branch} -> ${target_branch}
允许方向:
  - hotfix -> master
  - hotfix -> release"
    fi
  fi

  if [[ "$source_branch" =~ $RELEASE_BRANCH_PATTERN ]]; then
    if [[ "$target_branch" == "master" ]]; then
      pass "release 分支合并方向校验通过"
      return 0
    else
      fail "不允许的合并方向: ${source_branch} -> ${target_branch}
允许方向:
  - release -> master"
    fi
  fi

  if [[ "$source_branch" == "master" ]]; then
    pass "master 合入任意分支，合并方向校验通过"
    return 0
  fi

  fail "未匹配到合法的源分支类型: ${source_branch}"
}

# 3. MR 变更行数校验
check_diff_size() {
  local source_branch="$1"
  local target_branch="$2"

  echo "检查 MR 变更行数: ${source_branch} -> ${target_branch}"

  git fetch origin "${target_branch}"
  local target_sha; target_sha="$(git rev-parse FETCH_HEAD)"
  git fetch origin "${source_branch}"
  local source_sha; source_sha="$(git rev-parse FETCH_HEAD)"

  local total_lines
  total_lines="$(git diff --numstat "${target_sha}...${source_sha}" \
    | awk '{ added+=$1; deleted+=$2 } END { print (added+deleted) }')"

  echo "变更总行数: ${total_lines}"

  if [[ "${total_lines}" -gt 100 ]]; then
    echo "NEEDS_APPROVAL:${total_lines}" > approval_status
    echo "[WARN] MR 变更超过100行（${total_lines}行），需要人工审批"
  else
    echo "PASS" > approval_status
    pass "MR 变更行数校验通过"
  fi
}

# 4. MR 标题校验
check_mr_title() {
  echo "检查 MR 标题: ${MR_TITLE}"

  if [[ "$MR_TITLE" == *合并* ]]; then
    pass "MR 标题校验通过"
    return 0
  fi

  # hotfix/release → master 且描述含「投产追板」豁免「合并」关键字
  local mr_description="${CI_MERGE_REQUEST_DESCRIPTION:-}"
  if [[ "$MR_SOURCE_BRANCH" =~ ^(hotfix|release)-[0-9]{8}$ ]] && \
     [[ "$MR_TARGET_BRANCH" == "master" ]] && \
     [[ "$mr_description" == *投产追板* ]]; then
    pass "MR 标题校验通过（投产追板豁免）"
    return 0
  fi

  fail "MR 标题不包含「合并」关键字，当前标题: ${MR_TITLE}"
}

# 5. 合并前基线校验
check_merge_base() {
  local source_branch="$1"
  local target_branch="$2"

  # master 合入任意分支时不检查基线
  if [[ "$source_branch" == "master" ]]; then
    echo "master -> ${target_branch}，跳过基线校验"
    return 0
  fi

  # 业务/comp/feature 分支从 master 拉出，合到 uat*/sit*/hotfix/release 时不检查基线
  if is_uat_style_source "${source_branch}"; then
    if [[ "$target_branch" =~ $UAT_TARGET_PATTERN ]] || \
       [[ "$target_branch" =~ $SIT_TARGET_PATTERN ]] || \
       [[ "$target_branch" =~ $HOTFIX_BRANCH_PATTERN ]] || \
       [[ "$target_branch" =~ $RELEASE_BRANCH_PATTERN ]]; then
      echo "基于 master 的分支 -> ${target_branch}，跳过基线校验"
      return 0
    fi
  fi

  echo "检查基线同步: ${source_branch} 是否包含 ${target_branch} 最新提交"

  git fetch origin "${target_branch}"
  local target_commit; target_commit="$(git rev-parse FETCH_HEAD)"
  git fetch origin "${source_branch}"
  local source_commit; source_commit="$(git rev-parse FETCH_HEAD)"

  echo "target_commit=${target_commit}"
  echo "source_commit=${source_commit}"

  if git merge-base --is-ancestor "${target_commit}" "${source_commit}"; then
    pass "基线校验通过，源分支已包含目标分支最新提交"
  else
    fail "基线校验失败：源分支未包含目标分支最新提交
请先同步 ${target_branch} 最新代码到 ${source_branch}，再重新提交 MR"
  fi
}

main() {
  local current_branch=""

  if [[ -n "${MR_SOURCE_BRANCH}" ]]; then
    current_branch="${MR_SOURCE_BRANCH}"
  else
    current_branch="${BRANCH_NAME}"
  fi

  if [[ -z "${current_branch}" ]]; then
    fail "无法获取当前分支名"
  fi

  check_branch_name "${current_branch}"

  if [[ "${PIPELINE_SOURCE}" == "merge_request_event" ]]; then
    echo "当前为 MR 流水线"

    if [[ -z "${MR_SOURCE_BRANCH}" || -z "${MR_TARGET_BRANCH}" ]]; then
      fail "MR 环境变量缺失，无法进行 MR 校验"
    fi

    check_merge_direction "${MR_SOURCE_BRANCH}" "${MR_TARGET_BRANCH}"
    check_diff_size "${MR_SOURCE_BRANCH}" "${MR_TARGET_BRANCH}"
    check_mr_title
    check_merge_base "${MR_SOURCE_BRANCH}" "${MR_TARGET_BRANCH}"

    # PASS 情况下直接调 API 合并（不依赖 artifacts）
    if [[ -f approval_status ]] && [[ "$(cat approval_status)" == "PASS" ]]; then
      echo "门禁通过，执行自动合并..."
      API_URL="${CI_API_V4_URL:-${CI_SERVER_URL}/api/v4}"
      TOKEN="${GITLAB_PRIVATE_TOKEN}"
      if [[ -n "${TOKEN:-}" ]]; then
        RESP=$(curl -s --header "PRIVATE-TOKEN: ${TOKEN}" \
          -X PUT "${API_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/merge" \
          -H "Content-Type: application/json" \
          -d '{"merge_when_pipeline_succeeds": true}') || true
        echo "API 响应: ${RESP}"
        if echo "${RESP}" | grep -q '"state":"merged"' || echo "${RESP}" | grep -q '"merge_when_pipeline_succeeds":true'; then
          echo "合并请求已提交"
        else
          echo "[WARN] 合并 API 调用失败，响应见上方"
        fi
      else
        echo "[WARN] 未配置 GITLAB_PRIVATE_TOKEN，跳过自动合并"
      fi
    fi
  else
    echo "当前不是 MR 流水线，仅执行分支命名校验"
  fi

  echo "========== Git 门禁结束 =========="
}

main "$@"
