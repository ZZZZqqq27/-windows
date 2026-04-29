#!/usr/bin/env bash

# 公共环境变量（按你的实际环境修改）

# 仓库根目录（默认按当前脚本相对位置推导）
REPO_ROOT_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-${REPO_ROOT_DEFAULT}}"
PRO_DIR="${PRO_DIR:-${PROJECT_ROOT}/pro}"
APP_BIN="${APP_BIN:-${PRO_DIR}/build/app}"

# 双机 IP（请修改为真实值）
WIN_HOST_IP="${WIN_HOST_IP:-192.168.1.101}"
MAC_HOST_IP="${MAC_HOST_IP:-192.168.1.102}"

# 端口列表（逗号分隔）
WIN_PORTS="${WIN_PORTS:-18081,18082,18083}"
MAC_PORTS="${MAC_PORTS:-28081,28082,28083}"

# 测试参数默认值
DEFAULT_ROUNDS="${DEFAULT_ROUNDS:-3}"
DEFAULT_SIZE="${DEFAULT_SIZE:-10MB}"
DEFAULT_CONCURRENCY="${DEFAULT_CONCURRENCY:-1}"

# 数据和日志目录
WIN_EXEC_DIR="${WIN_EXEC_DIR:-${PROJECT_ROOT}/windows执行}"
OUTPUT_RAW_DIR="${OUTPUT_RAW_DIR:-${WIN_EXEC_DIR}/output/raw}"
OUTPUT_SUMMARY_DIR="${OUTPUT_SUMMARY_DIR:-${WIN_EXEC_DIR}/output/summary}"
LOG_DIR="${LOG_DIR:-${PRO_DIR}/logs}"
DATA_DIR="${DATA_DIR:-${PRO_DIR}/data}"

mkdir -p "${OUTPUT_RAW_DIR}" "${OUTPUT_SUMMARY_DIR}" "${LOG_DIR}" "${DATA_DIR}"

split_csv_to_array() {
  local csv="$1"
  local -n out_ref="$2"
  IFS=',' read -r -a out_ref <<< "${csv}"
}
