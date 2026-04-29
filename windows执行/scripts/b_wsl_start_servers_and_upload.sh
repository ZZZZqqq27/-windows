#!/usr/bin/env bash
set -euo pipefail

# ===============================================
# 脚本B：WSL端启动3个节点服务 + 上传文件
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

# 固定配置（与Mac端保持一致）
WIN_HOST_IP="192.168.1.3"
MAC_HOST_IP="192.168.1.11"
MAC_PORTS="28081,28082,28083"
WIN_PORTS="18081,18082,18083"

# 先创建目录再写日志
mkdir -p "${TEST_DATA_DIR}" "${CFG_DIR}" "${LOG_DIR}"

echo "[WSL] === 脚本B: WSL端启动3个节点服务 + 上传文件 ===" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] SCRIPTS_DIR=${SCRIPTS_DIR}" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] PROJECT_ROOT=${PROJECT_ROOT}" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] WIN_HOST_IP=${WIN_HOST_IP}, MAC_HOST_IP=${MAC_HOST_IP}" | tee -a "${LOG_DIR}/wsl_server_upload.log"

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
  echo "[WSL] 生成配置: node_${node}.yaml (端口: ${port})" | tee -a "${LOG_DIR}/wsl_server_upload.log"
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
echo "[WSL] 种子节点列表: ${ALL_SEEDS}" | tee -a "${LOG_DIR}/wsl_server_upload.log"

# 生成Windows节点配置
gen_node_cfg "win_1" "${WIN_HOST_IP}" "${WIN_PORT_ARR[0]}" "${ALL_SEEDS}"
gen_node_cfg "win_2" "${WIN_HOST_IP}" "${WIN_PORT_ARR[1]}" "${ALL_SEEDS}"
gen_node_cfg "win_3" "${WIN_HOST_IP}" "${WIN_PORT_ARR[2]}" "${ALL_SEEDS}"

# 检查APP_BIN是否存在且可执行
if [[ ! -x "${APP_BIN}" ]]; then
  echo "[WSL] ✗ APP_BIN 不存在或不可执行: ${APP_BIN}" | tee -a "${LOG_DIR}/wsl_server_upload.log"
  echo "[WSL] 请先编译项目: cd ${PRO_DIR} && mkdir -p build && cd build && cmake .. && make" | tee -a "${LOG_DIR}/wsl_server_upload.log"
  exit 1
fi

echo "[WSL] === 启动WSL端3个节点 ===" | tee -a "${LOG_DIR}/wsl_server_upload.log"

# 启动节点1
echo "[WSL] 启动 node_win_1 (${WIN_HOST_IP}:${WIN_PORT_ARR[0]})..." | tee -a "${LOG_DIR}/wsl_server_upload.log"
"${APP_BIN}" --config "${CFG_DIR}/node_win_1.yaml" --mode server \
  > "${LOG_DIR}/${TEST_NAME}_node_win_1_server.log" 2>&1 &
echo $! > "${TEST_DATA_DIR}/node_win_1.pid"
sleep 1

# 启动节点2
echo "[WSL] 启动 node_win_2 (${WIN_HOST_IP}:${WIN_PORT_ARR[1]})..." | tee -a "${LOG_DIR}/wsl_server_upload.log"
"${APP_BIN}" --config "${CFG_DIR}/node_win_2.yaml" --mode server \
  > "${LOG_DIR}/${TEST_NAME}_node_win_2_server.log" 2>&1 &
echo $! > "${TEST_DATA_DIR}/node_win_2.pid"
sleep 1

# 启动节点3
echo "[WSL] 启动 node_win_3 (${WIN_HOST_IP}:${WIN_PORT_ARR[2]})..." | tee -a "${LOG_DIR}/wsl_server_upload.log"
"${APP_BIN}" --config "${CFG_DIR}/node_win_3.yaml" --mode server \
  > "${LOG_DIR}/${TEST_NAME}_node_win_3_server.log" 2>&1 &
echo $! > "${TEST_DATA_DIR}/node_win_3.pid"
sleep 2

echo "[WSL] === WSL端3个节点启动完成 ===" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] 节点信息:" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL]   node_win_1: ${WIN_HOST_IP}:${WIN_PORT_ARR[0]}" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL]   node_win_2: ${WIN_HOST_IP}:${WIN_PORT_ARR[1]}" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL]   node_win_3: ${WIN_HOST_IP}:${WIN_PORT_ARR[2]}" | tee -a "${LOG_DIR}/wsl_server_upload.log"

# 等待节点稳定
sleep 3

# 创建测试文件
echo "[WSL] === 创建测试文件 ===" | tee -a "${LOG_DIR}/wsl_server_upload.log"
INPUT_FILE="${TEST_DATA_DIR}/input_test.bin"
MANIFEST_FILE="${TEST_DATA_DIR}/manifest.txt"

echo "[WSL] 生成10MB测试文件..." | tee -a "${LOG_DIR}/wsl_server_upload.log"
dd if=/dev/urandom of="${INPUT_FILE}" bs=1M count=10 2>/dev/null
echo "[WSL] 测试文件: ${INPUT_FILE} ($(du -h "${INPUT_FILE}" | awk '{print $1}'))" | tee -a "${LOG_DIR}/wsl_server_upload.log"

# 上传文件（使用win_1节点，复制到2个副本节点）
echo "[WSL] === 上传文件 ===" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] 从 node_win_1 上传文件，复制到2个副本节点..." | tee -a "${LOG_DIR}/wsl_server_upload.log"

"${APP_BIN}" --config "${CFG_DIR}/node_win_1.yaml" \
  --upload "${INPUT_FILE}" --replica 2 --manifest_out "${MANIFEST_FILE}" \
  >> "${LOG_DIR}/wsl_server_upload.log" 2>&1

if [[ $? -eq 0 ]]; then
  echo "[WSL] ✓ 上传成功" | tee -a "${LOG_DIR}/wsl_server_upload.log"
  echo "[WSL] Manifest文件: ${MANIFEST_FILE}" | tee -a "${LOG_DIR}/wsl_server_upload.log"

  # 获取第一个chunk_id用于测试
  CHUNK_ID=$(awk 'NR==1{print; exit}' "${MANIFEST_FILE}")
  echo "[WSL] 第一个Chunk ID: ${CHUNK_ID}" | tee -a "${LOG_DIR}/wsl_server_upload.log"
else
  echo "[WSL] ✗ 上传失败" | tee -a "${LOG_DIR}/wsl_server_upload.log"
  exit 1
fi

echo "[WSL] === 脚本B执行完成 ===" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL]" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] 请不要关闭当前 WSL 环境，确认 3 个 server 进程保持运行" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] 可使用 ss -lntp | grep 1808 检查端口监听" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL]" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] 下一步: 在Mac端执行脚本C: bash c_mac_run_client_download.sh" | tee -a "${LOG_DIR}/wsl_server_upload.log"
echo "[WSL] Manifest文件路径: ${MANIFEST_FILE}" | tee -a "${LOG_DIR}/wsl_server_upload.log"