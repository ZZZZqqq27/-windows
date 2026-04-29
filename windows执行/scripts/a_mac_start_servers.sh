#!/usr/bin/env bash
set -euo pipefail

# ===============================================
# 脚本A：Mac端启动3个节点服务
# ===============================================

# 自动获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}"
PROJECT_ROOT="$(cd "${SCRIPTS_DIR}/../.." && pwd)"
PRO_DIR="${PROJECT_ROOT}/pro"

export PROJECT_ROOT
export PRO_DIR
export APP_BIN="${PRO_DIR}/build/app"
export LOG_DIR="${PRO_DIR}/logs"
export DATA_DIR="${PRO_DIR}/data"

TEST_NAME="cross_host_multi_node"
TEST_DATA_DIR="${DATA_DIR}/${TEST_NAME}"
CFG_DIR="${TEST_DATA_DIR}/configs"

# 固定配置（与WSL端保持一致）
WIN_HOST_IP="192.168.1.3"
MAC_HOST_IP="192.168.1.11"
MAC_PORTS="28081,28082,28083"
WIN_PORTS="18081,18082,18083"

# 先创建目录再写日志
mkdir -p "${TEST_DATA_DIR}" "${CFG_DIR}" "${LOG_DIR}"

echo "[MAC] === 脚本A: Mac端启动3个节点服务 ===" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC] SCRIPTS_DIR=${SCRIPTS_DIR}" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC] PROJECT_ROOT=${PROJECT_ROOT}" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC] WIN_HOST_IP=${WIN_HOST_IP}, MAC_HOST_IP=${MAC_HOST_IP}" | tee -a "${LOG_DIR}/mac_servers.log"

# 解析端口
IFS=',' read -r -a MAC_PORT_ARR <<< "${MAC_PORTS}"
IFS=',' read -r -a WIN_PORT_ARR <<< "${WIN_PORTS}"

# 生成节点配置
gen_node_cfg() {
  local node="$1"
  local host_ip="$2"
  local port="$3"
  local all_seeds="$4"

  cat > "${CFG_DIR}/node_${node}.yaml" <<EOF
node_id: "${TEST_NAME}-${node}"
listen_port: ${port}
seed_nodes: "${all_seeds}"
self_addr: "${host_ip}:${port}"
routing_capacity: 8
chunk_size_mb: 1
chunks_dir: "${TEST_DATA_DIR}/node_${node}/chunks"
chunk_index_file: "${TEST_DATA_DIR}/node_${node}/chunk_index.tsv"
download_stats_file: "${TEST_DATA_DIR}/node_${node}/download_stats.tsv"
upload_meta_file: "${TEST_DATA_DIR}/node_${node}/upload_meta.tsv"
upload_replica_file: "${TEST_DATA_DIR}/node_${node}/upload_replica.tsv"
aes_key_hex: "00112233445566778899aabbccddeeff"
hmac_key_hex: "0102030405060708090a0b0c0d0e0f10"
download_strategy: "round_robin"
log_file: "${LOG_DIR}/${TEST_NAME}_node_${node}.log"
EOF
  mkdir -p "${TEST_DATA_DIR}/node_${node}/chunks"
  echo "[MAC] 生成配置: node_${node}.yaml (端口: ${port})" | tee -a "${LOG_DIR}/mac_servers.log"
}

# 生成所有种子节点
generate_all_seeds() {
  local seeds=""
  for i in 0 1 2; do
    seeds="${seeds}${WIN_HOST_IP}:${WIN_PORT_ARR[$i]},"
    seeds="${seeds}${MAC_HOST_IP}:${MAC_PORT_ARR[$i]},"
  done
  echo "${seeds%,}"
}

ALL_SEEDS=$(generate_all_seeds)
echo "[MAC] 种子节点列表: ${ALL_SEEDS}" | tee -a "${LOG_DIR}/mac_servers.log"

# 生成Mac节点配置
gen_node_cfg "mac_1" "${MAC_HOST_IP}" "${MAC_PORT_ARR[0]}" "${ALL_SEEDS}"
gen_node_cfg "mac_2" "${MAC_HOST_IP}" "${MAC_PORT_ARR[1]}" "${ALL_SEEDS}"
gen_node_cfg "mac_3" "${MAC_HOST_IP}" "${MAC_PORT_ARR[2]}" "${ALL_SEEDS}"

# 检查APP_BIN是否存在且可执行
if [[ ! -x "${APP_BIN}" ]]; then
  echo "[MAC] ✗ APP_BIN 不存在或不可执行: ${APP_BIN}" | tee -a "${LOG_DIR}/mac_servers.log"
  echo "[MAC] 请先编译项目: cd ${PRO_DIR} && mkdir -p build && cd build && cmake .. && make" | tee -a "${LOG_DIR}/mac_servers.log"
  exit 1
fi

echo "[MAC] === 启动Mac端3个节点 ===" | tee -a "${LOG_DIR}/mac_servers.log"

# 启动节点1
echo "[MAC] 启动 node_mac_1 (${MAC_HOST_IP}:${MAC_PORT_ARR[0]})..." | tee -a "${LOG_DIR}/mac_servers.log"
"${APP_BIN}" --config "${CFG_DIR}/node_mac_1.yaml" --mode server \
  > "${LOG_DIR}/${TEST_NAME}_node_mac_1_server.log" 2>&1 &
echo $! > "${TEST_DATA_DIR}/node_mac_1.pid"
sleep 1

# 启动节点2
echo "[MAC] 启动 node_mac_2 (${MAC_HOST_IP}:${MAC_PORT_ARR[1]})..." | tee -a "${LOG_DIR}/mac_servers.log"
"${APP_BIN}" --config "${CFG_DIR}/node_mac_2.yaml" --mode server \
  > "${LOG_DIR}/${TEST_NAME}_node_mac_2_server.log" 2>&1 &
echo $! > "${TEST_DATA_DIR}/node_mac_2.pid"
sleep 1

# 启动节点3
echo "[MAC] 启动 node_mac_3 (${MAC_HOST_IP}:${MAC_PORT_ARR[2]})..." | tee -a "${LOG_DIR}/mac_servers.log"
"${APP_BIN}" --config "${CFG_DIR}/node_mac_3.yaml" --mode server \
  > "${LOG_DIR}/${TEST_NAME}_node_mac_3_server.log" 2>&1 &
echo $! > "${TEST_DATA_DIR}/node_mac_3.pid"
sleep 2

echo "[MAC] === Mac端3个节点启动完成 ===" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC] 节点信息:" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC]   node_mac_1: ${MAC_HOST_IP}:${MAC_PORT_ARR[0]}" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC]   node_mac_2: ${MAC_HOST_IP}:${MAC_PORT_ARR[1]}" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC]   node_mac_3: ${MAC_HOST_IP}:${MAC_PORT_ARR[2]}" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC]" | tee -a "${LOG_DIR}/mac_servers.log"
echo "[MAC] 下一步: 在WSL端执行脚本B: bash b_wsl_start_servers_and_upload.sh" | tee -a "${LOG_DIR}/mac_servers.log"