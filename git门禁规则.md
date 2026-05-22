Git 门禁规则

---

## 触发方式

| 事件 | 触发检查 |
|---|---|
| Push（推送代码） | 仅分支命名校验 |
| MR（创建合并请求） | 分支命名 + 合并方向 + 变更行数 + 提交信息 + 基线校验 + 人工审批 |

---

## 1. 分支命名校验

所有 push 和 MR 事件均触发。分支名必须匹配以下格式，且日期部分必须真实存在：

| 类型 | 正则 | 示例 |
|---|---|---|
| FIX（缺陷修复） | `^FIX-[0-9]{8}-[0-9]{4}(-.+)?$` | `FIX-20260513-0001` 或 `FIX-20260513-0001-修复描述` |
| REQ（需求） | `^REQ-[0-9]{8}-[0-9]{4}(-.+)?$` | `REQ-20260513-0001` 或 `REQ-20260513-0001-需求描述` |
| PUB（公共） | `^PUB-[0-9]{8}-[0-9]{4}(-.+)?$` | `PUB-20260513-0001` 或 `PUB-20260513-0001-发布描述` |
| hotfix | `^hotfix-[0-9]{8}$` | `hotfix-20260513` |
| release | `^release-[0-9]{8}$` | `release-20260513` |
| comp | `^comp` | `comp*`（任意内容） |
| feature | `^feature` | `feature*`（任意内容） |
| master | `^master$` | `master` |
| uat | `^uat` | `uat*`（任意内容） |
| sit | `^sit` | `sit*`（任意内容） |

---

## 2. 合并方向校验（仅 MR）

源分支 → 目标分支必须在白名单内：

| 源分支 | 目标分支 |
|---|---|
| FIX / REQ / PUB | `uat` 开头 / `sit` 开头 / `hotfix` / `release` |
| comp | `uat` 开头 / `sit` 开头 / `hotfix` / `release` |
| feature | `uat` 开头 / `sit` 开头 / `hotfix` / `release` |
| master | 任意分支 |
| hotfix | `master` |
| release | `master` |

---

## 3. MR 变更行数校验（仅 MR）

计算源分支相对于目标分支的变更行数（新增 + 删除）：

| 条件 | 结果 |
|---|---|
| ≤ 100 行 | 自动通过，写入 `PASS` 标记 |
| > 100 行 | 写入 `NEEDS_APPROVAL:<行数>` 标记，触发人工审批 |

---

## 4. MR 标题校验（仅 MR）

| 条件 | 结果 |
|---|---|
| MR 标题包含「合并」 | 通过 |
| hotfix/release → master 且 MR 描述包含「投产追板」 | 通过（豁免「合并」关键字） |
| 其他情况 | 失败 |

---

## 5. 合并前基线校验（仅 MR）

检查源分支是否包含目标分支的最新提交：

| 合并方向 | 是否检查 | 说明 |
|---|---|---|
| master → * | 跳过 | master 是基线，不检查 |
| FIX/REQ/PUB/comp/feature → uat* | 跳过 | 基于 master，与 uat 无继承关系 |
| FIX/REQ/PUB/comp/feature → sit* | 跳过 | 基于 master，与 sit 无继承关系 |
| FIX/REQ/PUB/comp/feature → hotfix/release | 跳过 | 基于 master，与 hotfix/release 无继承关系 |
| hotfix → master | 检查 | 源分支必须包含 master 最新提交 |
| release → master | 检查 | 源分支必须包含 master 最新提交 |

---

## 6. 自动合并 & 人工审批（仅 MR）

合并 API 调用时机根据 `approval_status`：

- `PASS`（变更 ≤100 行）→ Stage 1 `git_gate.sh` 直接调用 GitLab API 自动合并，不依赖 artifacts
- `NEEDS_APPROVAL:<行数>`（变更 >100 行）→ Stage 2 `approval.sh` 手动触发后调用 API 合并

### 前置条件

项目需配置 CI/CD 变量 `GITLAB_PRIVATE_TOKEN`（Personal Access Token，权限 `api`）。

`approval.sh` 独立计算变更行数，不依赖 gate 阶段的 artifacts，兼容 artifacts 不可用的环境。
