#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common_env.sh"

RAW_LOG="${OUTPUT_RAW_DIR}/step1_windows_smoke.log"
SUMMARY_TSV="${OUTPUT_SUMMARY_DIR}/step1_windows_smoke.tsv"
SMOKE_DATA_DIR="${DATA_DIR}/win_smoke"
CFG_DIR="${SMOKE_DATA_DIR}/configs"

split_csv_to_array "${WIN_PORTS}" PORTS
if [[ "${#PORTS[@]}" -lt 2 ]]; then
  echo "[step1] WIN_PORTS 至少需要 2 个端口" | tee -a "${RAW_LOG}"
  exit 1
fi

mkdir -p "${SMOKE_DATA_DIR}" "${CFG_DIR}" "${LOG_DIR}"
: > "${RAW_LOG}"
printf "timestamp\tport\tresult\tnote\n" > "${SUMMARY_TSV}"

echo "[step1] PRO_DIR=${PRO_DIR}" | tee -a "${RAW_LOG}"
cd "${PRO_DIR}"

if [[ ! -x "${APP_BIN}" ]]; then
  echo "[step1] build/app 不存在，开始构建..." | tee -a "${RAW_LOG}"
  cmake -S . -B build >> "${RAW_LOG}" 2>&1
  cmake --build build >> "${RAW_LOG}" 2>&1
fi

INPUT_FILE="${SMOKE_DATA_DIR}/input.txt"
MANIFEST_FILE="${SMOKE_DATA_DIR}/manifest.txt"
OUT_FILE="${SMOKE_DATA_DIR}/output.bin"
printf "windows smoke test line1\nline2\nline3\n" > "${INPUT_FILE}"

gen_cfg() {
  local node="$1"
  local port="$2"
  local seeds="$3"
  cat > "${CFG_DIR}/node_${node}.yaml" <<EOF
node_id: "win-smoke-${node}"
listen_port: ${port}
seed_nodes: "${seeds}"
self_addr: "127.0.0.1:${port}"
routing_capacity: 8
chunk_size_mb: 1
chunks_dir: "${SMOKE_DATA_DIR}/node_${node}/chunks"
chunk_index_file: "${SMOKE_DATA_DIR}/node_${node}/chunk_index.tsv"
download_stats_file: "${SMOKE_DATA_DIR}/node_${node}/download_stats.tsv"
upload_meta_file: "${SMOKE_DATA_DIR}/node_${node}/upload_meta.tsv"
upload_replica_file: "${SMOKE_DATA_DIR}/node_${node}/upload_replica.tsv"
aes_key_hex: "00112233445566778899aabbccddeeff"
hmac_key_hex: "0102030405060708090a0b0c0d0e0f10"
download_strategy: "round_robin"
log_file: "${LOG_DIR}/win_smoke_node_${node}.log"
EOF
  mkdir -p "${SMOKE_DATA_DIR}/node_${node}/chunks"
}

seeds=""
for p in "${PORTS[@]}"; do
  seeds="${seeds}127.0.0.1:${p},"
done
seeds="${seeds%,}"

gen_cfg 1 "${PORTS[0]}" "${seeds}"
gen_cfg 2 "${PORTS[1]}" "${seeds}"
if [[ "${#PORTS[@]}" -ge 3 ]]; then
  gen_cfg 3 "${PORTS[2]}" "${seeds}"
fi

PIDS=()
cleanup() {
  for pid in "${PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT

start_server() {
  local node="$1"
  "${APP_BIN}" --config "${CFG_DIR}/node_${node}.yaml" --mode server \
    > "${LOG_DIR}/win_smoke_node_${node}_server.log" 2>&1 &
  PIDS+=("$!")
}

start_server 2
if [[ "${#PORTS[@]}" -ge 3 ]]; then
  start_server 3
fi
sleep 2

echo "[step1] 执行上传并生成 manifest" | tee -a "${RAW_LOG}"
"${APP_BIN}" --config "${CFG_DIR}/node_1.yaml" \
  --upload "${INPUT_FILE}" --replica 2 --manifest_out "${MANIFEST_FILE}" \
  >> "${RAW_LOG}" 2>&1

CHUNK_ID="$(awk 'NR==1{print; exit}' "${MANIFEST_FILE}")"
if [[ -z "${CHUNK_ID}" ]]; then
  echo "[step1] 未拿到 CHUNK_ID，失败" | tee -a "${RAW_LOG}"
  exit 1
fi

start_server 1
sleep 1

test_port() {
  local port="$1"
  if "${APP_BIN}" --config "${CFG_DIR}/node_1.yaml" --mode client \
      --peer "127.0.0.1:${port}" --chunk_id "${CHUNK_ID}" --strategy round_robin \
      >> "${RAW_LOG}" 2>&1; then
    printf "%s\t%s\tok\tchunk_download\n" "$(date '+%F %T')" "${port}" >> "${SUMMARY_TSV}"
  else
    printf "%s\t%s\tfail\tchunk_download\n" "$(date '+%F %T')" "${port}" >> "${SUMMARY_TSV}"
    return 1
  fi
}

for p in "${PORTS[@]}"; do
  test_port "${p}"
done

echo "[step1] 验证 manifest 下载" | tee -a "${RAW_LOG}"
"${APP_BIN}" --config "${CFG_DIR}/node_1.yaml" --mode client \
  --peer "127.0.0.1:${PORTS[0]}" --manifest "${MANIFEST_FILE}" --out_file "${OUT_FILE}" \
  --strategy round_robin >> "${RAW_LOG}" 2>&1

cmp "${INPUT_FILE}" "${OUT_FILE}"

echo "[step1] PASS" | tee -a "${RAW_LOG}"
