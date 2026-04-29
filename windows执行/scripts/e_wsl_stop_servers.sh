#!/usr/bin/env bash
set -euo pipefail

# ===============================================
# 脚本E：WSL端停止所有节点服务
# ===============================================

# 自动获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}"
PROJECT_ROOT="$(cd "${SCRIPTS_DIR}/../.." && pwd)"
PRO_DIR="${PROJECT_ROOT}/pro"

export PROJECT_ROOT
export PRO_DIR
export DATA_DIR="${PRO_DIR}/data"
export LOG_DIR="${PRO_DIR}/logs"

TEST_NAME="cross_host_multi_node"
TEST_DATA_DIR="${DATA_DIR}/${TEST_NAME}"

# 先创建目录再写日志
mkdir -p "${LOG_DIR}" "${TEST_DATA_DIR}"

echo "[WSL] === 脚本E: WSL端停止所有节点服务 ===" | tee -a "${LOG_DIR}/wsl_stop_servers.log"

# 清理WSL端节点进程
echo "[WSL] 停止WSL端节点进程..." | tee -a "${LOG_DIR}/wsl_stop_servers.log"

# 通过PID文件停止节点
for node in "win_1" "win_2" "win_3"; do
  PID_FILE="${TEST_DATA_DIR}/node_${node}.pid"
  if [[ -f "${PID_FILE}" ]]; then
    PID=$(cat "${PID_FILE}")
    echo "[WSL] 停止 node_${node} (PID: ${PID})..." | tee -a "${LOG_DIR}/wsl_stop_servers.log"
    kill "${PID}" 2>/dev/null || true
    wait "${PID}" 2>/dev/null || true
    rm -f "${PID_FILE}"
    echo "[WSL] ✓ node_${node} 已停止" | tee -a "${LOG_DIR}/wsl_stop_servers.log"
  else
    echo "[WSL] node_${node} 没有运行（PID文件不存在）" | tee -a "${LOG_DIR}/wsl_stop_servers.log"
  fi
done

# 额外清理可能残留的app进程
echo "[WSL] 清理残留的app进程..." | tee -a "${LOG_DIR}/wsl_stop_servers.log"
pkill -f "${PROJECT_ROOT}/pro/build/app" 2>/dev/null || true

echo "[WSL] === 脚本E执行完成 ===" | tee -a "${LOG_DIR}/wsl_stop_servers.log"
echo "[WSL] ✓ WSL端所有节点已停止" | tee -a "${LOG_DIR}/wsl_stop_servers.log"