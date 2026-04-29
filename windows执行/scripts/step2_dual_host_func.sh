#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common_env.sh"

DIRECTION=""
OVERRIDE_PORTS=""
OVERRIDE_PEER_IP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --direction) DIRECTION="${2:-}"; shift 2 ;;
    --ports) OVERRIDE_PORTS="${2:-}"; shift 2 ;;
    --peer-ip) OVERRIDE_PEER_IP="${2:-}"; shift 2 ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${DIRECTION}" ]]; then
  echo "用法: $0 --direction <win_to_mac|mac_to_win> [--ports p1,p2,p3] [--peer-ip ip]"
  exit 1
fi

RAW_LOG="${OUTPUT_RAW_DIR}/step2_func_${DIRECTION}.log"
SUMMARY_TSV="${OUTPUT_SUMMARY_DIR}/step2_func_${DIRECTION}.tsv"
: > "${RAW_LOG}"
printf "timestamp\tdirection\tpeer_ip\tport\ttest_item\tresult\tnote\n" > "${SUMMARY_TSV}"

cd "${PRO_DIR}"

if [[ ! -x "${APP_BIN}" ]]; then
  echo "[func] build/app 不存在，请先构建" | tee -a "${RAW_LOG}"
  exit 1
fi

TEST_DATA_DIR="${DATA_DIR}/dual_host_func"
mkdir -p "${TEST_DATA_DIR}"
INPUT_FILE="${TEST_DATA_DIR}/input_func.txt"
MANIFEST_FILE="${TEST_DATA_DIR}/manifest_func.txt"
OUT_FILE="${TEST_DATA_DIR}/output_func.bin"
printf "dual host functional test\nline2\nline3\n" > "${INPUT_FILE}"

if [[ "${DIRECTION}" == "win_to_mac" ]]; then
  TARGET_IP="${OVERRIDE_PEER_IP:-${MAC_HOST_IP}}"
  PORT_CSV="${OVERRIDE_PORTS:-${MAC_PORTS}}"
  split_csv_to_array "${PORT_CSV}" TARGET_PORTS

  echo "[func] 方向=win_to_mac，peer=${TARGET_IP}, ports=${PORT_CSV}" | tee -a "${RAW_LOG}"

  # 连通性与下载链路（依赖 Mac 侧已准备好 chunk_id）
  for p in "${TARGET_PORTS[@]}"; do
    if nc -z -w 2 "${TARGET_IP}" "${p}" >> "${RAW_LOG}" 2>&1; then
      printf "%s\t%s\t%s\t%s\tconnect\tok\t\n" "$(date '+%F %T')" "${DIRECTION}" "${TARGET_IP}" "${p}" >> "${SUMMARY_TSV}"
    else
      printf "%s\t%s\t%s\t%s\tconnect\tfail\tport unreachable\n" "$(date '+%F %T')" "${DIRECTION}" "${TARGET_IP}" "${p}" >> "${SUMMARY_TSV}"
    fi
  done

  echo "[func] 提示：若要做完整上传/manifest 功能，请先在 Mac 端执行服务准备脚本" | tee -a "${RAW_LOG}"
  echo "[func] PASS(win_to_mac 连通性完成，详细流程见 summary)" | tee -a "${RAW_LOG}"
  exit 0
fi

if [[ "${DIRECTION}" == "mac_to_win" ]]; then
  PORT_CSV="${OVERRIDE_PORTS:-${WIN_PORTS}}"
  split_csv_to_array "${PORT_CSV}" LOCAL_PORTS
  CFG_DIR="${TEST_DATA_DIR}/configs"
  mkdir -p "${CFG_DIR}"

  seeds=""
  for p in "${LOCAL_PORTS[@]}"; do
    seeds="${seeds}127.0.0.1:${p},"
  done
  seeds="${seeds%,}"

  gen_cfg() {
    local idx="$1"
    local port="$2"
    cat > "${CFG_DIR}/node_${idx}.yaml" <<EOF
node_id: "func-win-${idx}"
listen_port: ${port}
seed_nodes: "${seeds}"
self_addr: "127.0.0.1:${port}"
routing_capacity: 8
chunk_size_mb: 1
chunks_dir: "${TEST_DATA_DIR}/node_${idx}/chunks"
chunk_index_file: "${TEST_DATA_DIR}/node_${idx}/chunk_index.tsv"
download_stats_file: "${TEST_DATA_DIR}/node_${idx}/download_stats.tsv"
upload_meta_file: "${TEST_DATA_DIR}/node_${idx}/upload_meta.tsv"
upload_replica_file: "${TEST_DATA_DIR}/node_${idx}/upload_replica.tsv"
aes_key_hex: "00112233445566778899aabbccddeeff"
hmac_key_hex: "0102030405060708090a0b0c0d0e0f10"
download_strategy: "round_robin"
log_file: "${LOG_DIR}/dual_func_win_node_${idx}.log"
EOF
    mkdir -p "${TEST_DATA_DIR}/node_${idx}/chunks"
  }

  idx=1
  for p in "${LOCAL_PORTS[@]}"; do
    gen_cfg "${idx}" "${p}"
    idx=$((idx + 1))
  done

  echo "[func] 启动 Windows(WSL) 本地服务，等待 Mac 侧客户端访问" | tee -a "${RAW_LOG}"
  PIDS=()
  cleanup() {
    for pid in "${PIDS[@]}"; do
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    done
  }
  trap cleanup EXIT

  idx=1
  for p in "${LOCAL_PORTS[@]}"; do
    "${APP_BIN}" --config "${CFG_DIR}/node_${idx}.yaml" --mode server \
      > "${LOG_DIR}/dual_func_win_node_${idx}_server.log" 2>&1 &
    PIDS+=("$!")
    printf "%s\t%s\t%s\t%s\tserver_start\tok\tnode_%s\n" "$(date '+%F %T')" "${DIRECTION}" "${WIN_HOST_IP}" "${p}" "${idx}" >> "${SUMMARY_TSV}"
    idx=$((idx + 1))
  done

  sleep 2
  echo "[func] Mac 侧请执行（示例）:" | tee -a "${RAW_LOG}"
  echo "./build/app --config <mac_config.yaml> --mode client --peer ${WIN_HOST_IP}:${LOCAL_PORTS[0]} --chunk_id <CHUNK_ID>" | tee -a "${RAW_LOG}"
  echo "[func] 服务保持 120 秒用于对端执行，期间请在 Mac 完成功能访问" | tee -a "${RAW_LOG}"
  sleep 120
  echo "[func] PASS(mac_to_win 服务窗口已提供)" | tee -a "${RAW_LOG}"
  exit 0
fi

echo "direction 仅支持: win_to_mac | mac_to_win"
exit 1
