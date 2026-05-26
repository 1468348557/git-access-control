#!/usr/bin/env bash
# Git 门禁 HTTP 文件服务器启动脚本
# 用法: bash server/start-http.sh

set -euo pipefail

SERVER_ROOT="/home/hobo/hobo-git-gate"
PORT=8080

if [[ ! -d "${SERVER_ROOT}" ]]; then
  echo "错误: 门禁仓库不存在 ${SERVER_ROOT}"
  echo "请先执行: git clone git@gitlab.spdb.com:zh-1087/hobo-git-gate.git ${SERVER_ROOT}"
  exit 1
fi

# 检查是否已在运行
if pgrep -f "http.server ${PORT}" > /dev/null; then
  echo "HTTP 服务器已在运行 (端口 ${PORT})"
  exit 0
fi

# 从 /home/hobo 启动，URL 路径包含 /hobo-git-gate/
nohup python3 -m http.server "${PORT}" --directory /home/hobo > /home/hobo/http-server.log 2>&1 &
echo "HTTP 服务器已启动: http://$(hostname -I 2>/dev/null || echo 'localhost'):${PORT}/hobo-git-gate/"
