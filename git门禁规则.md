# Git 门禁规则

---

## 部署方式

门禁脚本和 CI 配置托管在 HTTP 服务器 `http://21.73.16.160:8080/hobo-git-gate/template/`，业务项目通过 `ci_config_path` 指向服务器，CI 运行时 curl 下载脚本，无需在业务项目中放置任何门禁文件。详细步骤见 [部署指南](docs/部署指南.md)。

---

## Runner 分组

门禁根据 MR 目标分支使用不同的 Runner：

| MR 目标分支 | Runner Tag | 说明 |
| --- | --- | --- |
| `hotfix*` / `release*` / `master` | `shell-critical` | 关键分支，专用 Runner 保障执行稳定性 |
| 其他分支 | `shell` | 常规门禁 Runner |

Push 事件统一使用 `shell` Runner。

---

## 触发方式

| 事件 | 触发检查 |
| --- | --- |
| Push（推送代码） | 仅分支命名校验 |
| MR（合并请求） | 分支命名 + 合并方向 + 变更行数 + MR 标题 + 基线校验 |
| MR → sit* | 直接放行，不做任何校验（含分支命名） |

---

## 1. 分支命名校验

所有 push 和 MR 事件均触发（MR → `sit*` 除外）。分支名必须匹配以下格式，且日期部分必须真实存在：

| 类型 | 正则 | 示例 |
| --- | --- | --- |
| FIX（缺陷修复） | `^FIX-[0-9]{8}-[0-9]{4}([-_].+)?$` | `FIX-20260513-0001` 或 `FIX-20260513-0001-修复描述` 或 `FIX-20260513-0001_uat` |
| REQ（需求） | `^REQ-[0-9]{8}-[0-9]{4}([-_].+)?$` | `REQ-20260513-0001` 或 `REQ-20260513-0001-需求描述` 或 `REQ-20260513-0001_uat` |
| PUB（公共） | `^PUB-[0-9]{8}-[0-9]{4}([-_].+)?$` | `PUB-20260513-0001` 或 `PUB-20260513-0001-发布描述` 或 `PUB-20260513-0001_uat` |
| hotfix | `^hotfix-[0-9]{8}$` | `hotfix-20260513` |
| release | `^release-[0-9]{8}$` | `release-20260513` |
| comp | `^comp` | `comp*`（任意内容） |
| feature | `^feature` | `feature*`（任意内容） |
| master | `^master` | `master` |
| uat | `^uat` | `uat*`（任意内容） |
| sit | `^sit` | `sit*`（任意内容） |

---

## 2. 合并方向校验（仅 MR）

> 目标分支为 `sit*` 的 MR 跳过所有校验，直接放行（含此项）。

源分支 → 目标分支必须在白名单内：

| 源分支 | 目标分支 |
| --- | --- |
| FIX / REQ / PUB | `uat` 开头 / `sit` 开头 / `hotfix` / `release` / FIX / REQ / PUB |
| comp | `uat` 开头 / `sit` 开头 / `hotfix` / `release` |
| feature | `uat` 开头 / `sit` 开头 / `hotfix` / `release` |
| master | 任意分支 |
| hotfix | `master` / `release` |
| release | `master` |

---

## 3. MR 变更行数校验（仅 MR）

> 目标分支为 `sit*` 的 MR 跳过所有校验，直接放行（含此项）。

计算源分支相对于目标分支的变更行数（新增 + 删除）：

| 条件 | 结果 |
| --- | --- |
| ≤ 100 行 | 流水线通过，自动调用 GitLab API 合并 |
| > 100 行 | 打印警告，需管理员在 GitLab 手动点击 Merge |

---

## 4. MR 标题校验（仅 MR）

> 目标分支为 `sit*` 的 MR 跳过所有校验，直接放行（含此项）。

| 条件 | 结果 |
| --- | --- |
| MR 标题包含「合并」 | 通过 |
| hotfix/release → master 且 MR 描述包含「投产追板」 | 通过（豁免「合并」关键字） |
| 其他情况 | 失败 |

---

## 5. 合并前基线校验（仅 MR）

> 目标分支为 `sit*` 的 MR 跳过所有校验，直接放行（含此项）。

检查源分支是否包含目标分支的最新提交：

| 合并方向 | 是否检查 | 说明 |
| --- | --- | --- |
| master → * | 跳过 | master 是基线，不检查 |
| FIX/REQ/PUB/comp/feature → uat* | 跳过 | 基于 master，与 uat 无继承关系 |
| FIX/REQ/PUB/comp/feature → sit* | 跳过 | 基于 master，与 sit 无继承关系 |
| FIX/REQ/PUB/comp/feature → hotfix/release | 跳过 | 基于 master，与 hotfix/release 无继承关系 |
| FIX/REQ/PUB → FIX/REQ/PUB | 跳过 | 均从 master 拉出，无继承关系 |
| hotfix → master | 检查 | 源分支必须包含 master 最新提交 |
| hotfix → release | 跳过 | 均从 master 拉出，无继承关系 |
| release → master | 检查 | 源分支必须包含 master 最新提交 |

---

## 6. 自动合并（仅 MR）

变更行数 ≤ 100 行时，`git_gate.sh` 直接调用 GitLab API 自动合并。> 100 行需管理员在 GitLab 手动点击 Merge。

### 前置条件

项目需配置 CI/CD 变量 `GITLAB_PRIVATE_TOKEN`（Personal Access Token，权限 `api`），用于自动合并。
