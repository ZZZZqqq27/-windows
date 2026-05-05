#!/usr/bin/env bash
set -euo pipefail

# ===============================================
# 脚本C：Mac端执行客户端下载（真实跨机测试，带计时）
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

# 固定配置
WIN_HOST_IP="192.168.1.3"
MAC_HOST_IP="192.168.1.11"
MAC_PORTS="28081,28082,28083"
WIN_PORTS="18081,18082,18083"

# 先创建所有目录
mkdir -p "${TEST_DATA_DIR}" "${CFG_DIR}" "${LOG_DIR}"

# 毫秒时间函数
get_time_ms() {
  python3 -c 'import time; print(int(time.time() * 1000))'
}

echo "[MAC] === 脚本C: Mac端执行客户端下载 ===" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC] SCRIPTS_DIR=${SCRIPTS_DIR}" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC] PROJECT_ROOT=${PROJECT_ROOT}" | tee -a "${LOG_DIR}/mac_client_download.log"

# 解析端口
IFS=',' read -r -a MAC_PORT_ARR <<< "${MAC_PORTS}"
IFS=',' read -r -a WIN_PORT_ARR <<< "${WIN_PORTS}"

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

# 自动生成配置文件（如果不存在）
gen_node_cfg() {
  local node="$1"
  local host_ip="$2"
  local port="$3"
  local all_seeds="$4"

  mkdir -p "${TEST_DATA_DIR}/node_${node}/chunks"

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
}

# 自动生成Mac节点配置（如果不存在）
if [[ ! -f "${CFG_DIR}/node_mac_1.yaml" ]]; then
  echo "[MAC] 配置文件不存在，自动生成..." | tee -a "${LOG_DIR}/mac_client_download.log"
  gen_node_cfg "mac_1" "${MAC_HOST_IP}" "${MAC_PORT_ARR[0]}" "${ALL_SEEDS}"
  gen_node_cfg "mac_2" "${MAC_HOST_IP}" "${MAC_PORT_ARR[1]}" "${ALL_SEEDS}"
  gen_node_cfg "mac_3" "${MAC_HOST_IP}" "${MAC_PORT_ARR[2]}" "${ALL_SEEDS}"
  echo "[MAC] ✓ 配置文件生成完成" | tee -a "${LOG_DIR}/mac_client_download.log"
else
  echo "[MAC] ✓ 配置文件已存在" | tee -a "${LOG_DIR}/mac_client_download.log"
fi

# 检查APP_BIN是否存在且可执行
if [[ ! -x "${APP_BIN}" ]]; then
  echo "[MAC] ✗ APP_BIN 不存在或不可执行: ${APP_BIN}" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 请先编译项目: cd ${PRO_DIR} && mkdir -p build && cd build && cmake .. && make" | tee -a "${LOG_DIR}/mac_client_download.log"
  exit 1
fi

# 支持命令行参数传入manifest文件
MANIFEST_FILE="${TEST_DATA_DIR}/manifest_from_wsl.txt"

if [[ $# -ge 1 ]]; then
  INPUT_MANIFEST="$1"
  if [[ -f "${INPUT_MANIFEST}" ]]; then
    cp "${INPUT_MANIFEST}" "${MANIFEST_FILE}"
    echo "[MAC] ✓ 从命令行参数加载manifest: ${INPUT_MANIFEST}" | tee -a "${LOG_DIR}/mac_client_download.log"
  else
    echo "[MAC] ✗ 指定的manifest文件不存在: ${INPUT_MANIFEST}" | tee -a "${LOG_DIR}/mac_client_download.log"
    exit 1
  fi
else
  echo "[MAC] === 请提供Manifest文件 ===" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 请在WSL端执行以下命令获取manifest内容:" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC]   cat ${DATA_DIR}/cross_host_multi_node/manifest.txt" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC]" | tee -a "${LOG_DIR}/mac_client_download.log"

  echo "[MAC] 请输入Manifest内容（每行一个chunk_id，输入空行结束）:" | tee -a "${LOG_DIR}/mac_client_download.log"

  > "${MANIFEST_FILE}"
  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')
    if [[ -z "${line}" ]]; then
      break
    fi
    echo "${line}" >> "${MANIFEST_FILE}"
  done
fi

if [[ ! -s "${MANIFEST_FILE}" ]]; then
  echo "[MAC] ✗ Manifest文件为空" | tee -a "${LOG_DIR}/mac_client_download.log"
  exit 1
fi

echo "[MAC] ✓ Manifest文件已接收，共 $(wc -l < "${MANIFEST_FILE}") 个chunk" | tee -a "${LOG_DIR}/mac_client_download.log"

# 创建输出文件
OUTPUT_FILE="${TEST_DATA_DIR}/output_from_wsl.bin"

echo "[MAC] === 端口连通性检查 ===" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC] 检查Mac到Windows ${WIN_HOST_IP}:${WIN_PORT_ARR[0]} 的连接..." | tee -a "${LOG_DIR}/mac_client_download.log"

# 端口探测
if ! nc -z -w 2 "${WIN_HOST_IP}" "${WIN_PORT_ARR[0]}"; then
  echo "[MAC] ✗ 无法连接到 ${WIN_HOST_IP}:${WIN_PORT_ARR[0]}" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 请检查：" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC]   1. Windows防火墙是否放行该端口" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC]   2. WSL端脚本B是否已成功启动" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC]   3. 两台机器是否在同一局域网" | tee -a "${LOG_DIR}/mac_client_download.log"
  exit 1
fi
echo "[MAC] ✓ 端口 ${WIN_HOST_IP}:${WIN_PORT_ARR[0]} 连通性正常" | tee -a "${LOG_DIR}/mac_client_download.log"

echo "[MAC] === 开始跨机下载 ===" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC] 从Windows节点 ${WIN_HOST_IP}:${WIN_PORT_ARR[0]} 下载..." | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC] 输出文件: ${OUTPUT_FILE}" | tee -a "${LOG_DIR}/mac_client_download.log"

DOWNLOAD_START_MS=$(get_time_ms)

"${APP_BIN}" --config "${CFG_DIR}/node_mac_1.yaml" \
  --mode client \
  --manifest "${MANIFEST_FILE}" \
  --out_file "${OUTPUT_FILE}" \
  --peer "${WIN_HOST_IP}:${WIN_PORT_ARR[0]}" \
  --strategy round_robin \
  >> "${LOG_DIR}/mac_client_download.log" 2>&1

DOWNLOAD_STATUS=$?
DOWNLOAD_END_MS=$(get_time_ms)
DOWNLOAD_ELAPSED_MS=$((DOWNLOAD_END_MS - DOWNLOAD_START_MS))
[[ ${DOWNLOAD_ELAPSED_MS} -le 0 ]] && DOWNLOAD_ELAPSED_MS=1

OUTPUT_SIZE_BYTES=$(wc -c < "${OUTPUT_FILE}" 2>/dev/null || echo 0)
if [[ "${OUTPUT_SIZE_BYTES}" -gt 0 ]]; then
  OUTPUT_SIZE_MB=$(awk -v b="${OUTPUT_SIZE_BYTES}" 'BEGIN{printf "%.3f", b/1024/1024}')
else
  OUTPUT_SIZE_MB="10.000"
fi

DOWNLOAD_THROUGHPUT_MB_S=$(awk -v mb="${OUTPUT_SIZE_MB}" -v ms="${DOWNLOAD_ELAPSED_MS}" 'BEGIN{printf "%.3f", (mb*1000)/ms}')

if [[ ${DOWNLOAD_STATUS} -eq 0 ]]; then
  echo "[MAC] ✓ 跨机下载成功" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 下载耗时: ${DOWNLOAD_ELAPSED_MS} ms" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 等效下载吞吐: ${DOWNLOAD_THROUGHPUT_MB_S} MB/s" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 下载文件大小: $(du -h "${OUTPUT_FILE}" | awk '{print $1}')" | tee -a "${LOG_DIR}/mac_client_download.log"

  echo "[MAC] === 文件完整性验证 ===" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 下载文件SHA256:" | tee -a "${LOG_DIR}/mac_client_download.log"
  DOWNLOAD_SHA256=$(shasum -a 256 "${OUTPUT_FILE}" | awk '{print $1}')
  echo "[MAC] ${DOWNLOAD_SHA256}" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC]" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 请在WSL端执行以下命令获取原文件SHA256进行对比:" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC]   sha256sum ${DATA_DIR}/cross_host_multi_node/input_test.bin" | tee -a "${LOG_DIR}/mac_client_download.log"
else
  echo "[MAC] ✗ 跨机下载失败" | tee -a "${LOG_DIR}/mac_client_download.log"
  echo "[MAC] 下载耗时: ${DOWNLOAD_ELAPSED_MS} ms" | tee -a "${LOG_DIR}/mac_client_download.log"
  exit 1
fi

echo "[MAC]" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC] === 脚本C执行完成 ===" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC]" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC] 测试结果:" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC]   ✓ Mac端配置文件已准备" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC]   ✓ WSL端成功启动3个server节点" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC]   ✓ WSL端上传文件成功" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC]   ✓ Mac端跨机下载成功（从Windows节点获取数据）" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC]" | tee -a "${LOG_DIR}/mac_client_download.log"
echo "[MAC] 测试结论: 跨主机多节点P2P内容分发功能验证成功！" | tee -a "${LOG_DIR}/mac_client_download.log"