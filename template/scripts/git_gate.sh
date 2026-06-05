#!/usr/bin/env bash
set -euo pipefail

echo "========== Git 门禁开始 =========="

BRANCH_NAME="${CI_COMMIT_REF_NAME:-}"
PIPELINE_SOURCE="${CI_PIPELINE_SOURCE:-}"
MR_SOURCE_BRANCH="${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}"
MR_TARGET_BRANCH="${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}"
MR_TITLE="${CI_MERGE_REQUEST_TITLE:-}"

BRANCH_PATTERN='^((FIX|REQ|PUB)-[0-9]{8}-[0-9]{4}([-_].+)?|(hotfix|release)-[0-9]{8}|comp|feature|master|uat|sit)'
BUSINESS_BRANCH_PATTERN='^(FIX|REQ|PUB)-[0-9]{8}-[0-9]{4}([-_].+)?$'
HOTFIX_BRANCH_PATTERN='^hotfix-[0-9]{8}$'
RELEASE_BRANCH_PATTERN='^release-[0-9]{8}$'
COMP_BRANCH_PATTERN='^comp'
FEATURE_BRANCH_PATTERN='^feature'
UAT_TARGET_PATTERN='^uat'
SIT_TARGET_PATTERN='^sit'

# 全局缓存：避免 check_diff_size 和 check_merge_base 重复 fetch
_GIT_FETCHED_SOURCE=""
_GIT_FETCHED_TARGET=""
_GIT_SOURCE_SHA=""
_GIT_TARGET_SHA=""
DIFF_TOTAL_LINES=0

# 带缓存的 fetch，同分支不重复拉取
_fetch_branch_cached() {
  local branch="$1"
  local out_var="$2"

  if [[ "$branch" == "${_GIT_FETCHED_SOURCE:-}" ]] && [[ -n "${_GIT_SOURCE_SHA:-}" ]]; then
    printf -v "$out_var" "%s" "${_GIT_SOURCE_SHA}"
    return 0
  fi
  if [[ "$branch" == "${_GIT_FETCHED_TARGET:-}" ]] && [[ -n "${_GIT_TARGET_SHA:-}" ]]; then
    printf -v "$out_var" "%s" "${_GIT_TARGET_SHA}"
    return 0
  fi

  git fetch origin "${branch}"
  printf -v "$out_var" "%s" "$(git rev-parse FETCH_HEAD)"
}

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
  1. FIX-YYYYMMDD-NNNN[-_额外名称]
  2. REQ-YYYYMMDD-NNNN[-_额外名称]
  3. PUB-YYYYMMDD-NNNN[-_额外名称]
  4. hotfix-YYYYMMDD
  5. release-YYYYMMDD
  6. comp*
  7. feature*
  8. master / uat* / sit*"
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

  _fetch_branch_cached "${target_branch}" "_GIT_TARGET_SHA"
  _GIT_FETCHED_TARGET="${target_branch}"
  _fetch_branch_cached "${source_branch}" "_GIT_SOURCE_SHA"
  _GIT_FETCHED_SOURCE="${source_branch}"

  # 二进制文件在 numstat 中显示为 "-  -"，awk 下转为 0
  # 每个二进制文件计 999 行，避免触发 ≤150 行的自动合并
  DIFF_TOTAL_LINES="$(git diff --numstat "${_GIT_TARGET_SHA}...${_GIT_SOURCE_SHA}" \
    | awk '{
      if ($1 == "-" && $2 == "-") { added+=999; deleted+=0 }
      else { added+=$1; deleted+=$2 }
    } END { print (added+deleted) }')"

  echo "变更总行数: ${DIFF_TOTAL_LINES}"

  if [[ "${DIFF_TOTAL_LINES}" -gt 150 ]]; then
    echo "[WARN] MR 变更超过150行（${DIFF_TOTAL_LINES}行），需要人工审批"
  else
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

  # hotfix/release → master 且标题含「投产追版」豁免「合并」关键字
  if [[ "$MR_SOURCE_BRANCH" =~ ^(hotfix|release)-[0-9]{8}$ ]] && \
     [[ "$MR_TARGET_BRANCH" == "master" ]] && \
     [[ "$MR_TITLE" == *投产追版* ]]; then
    pass "MR 标题校验通过（投产追版豁免）"
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

  # hotfix/release 之间互相合并，均从 master 拉出，不检查基线
  if [[ "$source_branch" =~ $HOTFIX_BRANCH_PATTERN ]] && \
     [[ "$target_branch" =~ $RELEASE_BRANCH_PATTERN ]]; then
    echo "hotfix -> release，跳过基线校验"
    return 0
  fi

  # FIX/REQ/PUB 之间互相合并，均从 master 拉出，不检查基线
  if [[ "$source_branch" =~ $BUSINESS_BRANCH_PATTERN ]] && \
     [[ "$target_branch" =~ $BUSINESS_BRANCH_PATTERN ]]; then
    echo "业务分支间合并，跳过基线校验"
    return 0
  fi

  echo "检查基线同步: ${source_branch} 是否包含 ${target_branch} 最新提交"

  # 复用 check_diff_size 已 fetch 的 SHA
  local target_commit source_commit
  _fetch_branch_cached "${target_branch}" "target_commit"
  _GIT_FETCHED_TARGET="${target_branch}"
  _GIT_TARGET_SHA="${target_commit}"
  _fetch_branch_cached "${source_branch}" "source_commit"
  _GIT_FETCHED_SOURCE="${source_branch}"
  _GIT_SOURCE_SHA="${source_commit}"

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

  # 合入 sit 分支的 MR 不做任何校验，直接放行
  if [[ "${PIPELINE_SOURCE}" == "merge_request_event" ]] && \
     [[ "${MR_TARGET_BRANCH:-}" =~ $SIT_TARGET_PATTERN ]]; then
    echo "目标分支为 sit*，跳过所有校验"
    echo "========== Git 门禁结束 =========="
    exit 0
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

    # ≤150 行直接调 API 自动合并
    if [[ "${DIFF_TOTAL_LINES}" -le 150 ]]; then
      echo "门禁通过，执行自动合并..."
      API_URL="${CI_API_V4_URL:-${CI_SERVER_URL}/api/v4}"
      TOKEN="${GITLAB_PRIVATE_TOKEN}"
      if [[ -n "${TOKEN:-}" ]]; then
        local max_retry=10
        local retry=0
        local merged=0
        while [[ $retry -lt $max_retry ]]; do
          retry=$((retry + 1))

          # 先查询 MR 状态，merge_status=checking 时调用 PUT /merge 会 405
          echo "查询 MR 状态 (第 ${retry}/${max_retry} 次)..."
          MR_INFO=$(curl -s -w "\n%{http_code}" --header "PRIVATE-TOKEN: ${TOKEN}" \
            "${API_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}") || true
          http_code=$(echo "${MR_INFO}" | tail -n1)
          mr_body=$(echo "${MR_INFO}" | sed '$d')

          if [[ "$http_code" != "200" ]]; then
            echo "MR 查询失败，HTTP ${http_code}，响应: ${mr_body}"
            if [[ $retry -lt $max_retry ]]; then
              echo "2 秒后重试..."
              sleep 2
            fi
            continue
          fi

          merge_status=$(echo "${mr_body}" | grep -o '"merge_status":"[^"]*"' | cut -d'"' -f4)
          mr_state=$(echo "${mr_body}" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
          echo "MR state=${mr_state}, merge_status=${merge_status}"

          # 已合并则直接退出
          if [[ "$mr_state" == "merged" ]]; then
            echo "MR 已合并，无需重复操作"
            merged=1
            break
          fi

          # 已关闭则退出
          if [[ "$mr_state" == "closed" ]]; then
            echo "[WARN] MR 已关闭，跳过自动合并"
            break
          fi

          # merge_status 为 checking 时，等 GitLab 异步检查完成再试
          if [[ "$merge_status" == "checking" ]]; then
            echo "merge_status 为 checking，等待 GitLab 异步检查完成..."
            sleep 3
            continue
          fi

          # 不可合并时输出详细原因
          if [[ "$merge_status" == "cannot_be_merged" ]]; then
            detailed_merge_status=$(echo "${mr_body}" | grep -o '"detailed_merge_status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            echo "[WARN] MR 不可自动合并 (merge_status=cannot_be_merged, detailed=${detailed_merge_status})，跳过自动合并"
            break
          fi

          # 可合并，调用合并 API（不传 merge_when_pipeline_succeeds，门禁已通过即表示本 pipeline 成功）
          echo "发起合并请求..."
          MERGE_RESP=$(curl -s -w "\n%{http_code}" --header "PRIVATE-TOKEN: ${TOKEN}" \
            -X PUT "${API_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/merge") || true
          http_code=$(echo "${MERGE_RESP}" | tail -n1)
          resp_body=$(echo "${MERGE_RESP}" | sed '$d')
          echo "HTTP ${http_code}, 响应: ${resp_body}"

          if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
            echo "合并成功"
            merged=1
            break
          fi

          # 405: MR 状态暂不可合并（可能在 checking 与 can_be_merged 之间），等一会重试
          if [[ "$http_code" == "405" ]]; then
            echo "收到 405，当前 merge_status=${merge_status}，3 秒后重试..."
            sleep 3
            continue
          fi

          # 409: MR 状态冲突（已有合并操作在进行）
          if [[ "$http_code" == "409" ]]; then
            echo "收到 409（状态冲突），2 秒后重试..."
            sleep 2
            continue
          fi

          if [[ $retry -lt $max_retry ]]; then
            echo "合并失败 (HTTP ${http_code})，2 秒后重试..."
            sleep 2
          fi
        done
        if [[ $merged -eq 0 ]]; then
          echo "[WARN] 合并 API 调用失败（已重试 ${max_retry} 次），响应见上方"
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
