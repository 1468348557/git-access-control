#!/usr/bin/env bash
set -euo pipefail

chmod +x .githooks/pre-push
git config core.hooksPath .githooks
echo "Hook 安装完成: .githooks/pre-push"
