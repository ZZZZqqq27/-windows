#!/usr/bin/env bash
set -euo pipefail

# 项目根目录
PROJECT_ROOT="/root/workspace/-windows"
PRO_DIR="${PROJECT_ROOT}/pro"

# Windows WSL 配置
WIN_HOST_IP="192.168.1.3"
WIN_PORTS="18081,18082,18083"

# Mac 配置
MAC_HOST_IP="192.168.1.11"
MAC_PORTS="28081,28082,28083"

# 目录配置
DATA_DIR="${PRO_DIR}/data"
LOG_DIR="${PRO_DIR}/logs"
OUTPUT_RAW_DIR="${PRO_DIR}/windows执行/output/raw"
OUTPUT_SUMMARY_DIR="${PRO_DIR}/windows执行/output/summary"
APP_BIN="${PRO_DIR}/build/app"

# 工具函数：分割逗号字符串到数组
split_csv_to_array() {
  local csv="$1"
  local -n arr="$2"
  IFS=',' read -ra arr <<< "${csv}"
}
