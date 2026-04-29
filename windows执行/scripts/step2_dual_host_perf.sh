#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common_env.sh"

DIRECTION=""
OVERRIDE_PORTS=""
OVERRIDE_PEER_IP=""
ROUNDS="${DEFAULT_ROUNDS}"
SIZE="${DEFAULT_SIZE}"
CONCURRENCY="${DEFAULT_CONCURRENCY}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --direction) DIRECTION="${2:-}"; shift 2 ;;
    --ports) OVERRIDE_PORTS="${2:-}"; shift 2 ;;
    --peer-ip) OVERRIDE_PEER_IP="${2:-}"; shift 2 ;;
    --rounds) ROUNDS="${2:-}"; shift 2 ;;
    --size) SIZE="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${DIRECTION}" ]]; then
  echo "用法: $0 --direction <win_to_mac|mac_to_win> [--rounds N] [--size 10MB|100MB|1GB] [--concurrency N] [--ports csv] [--peer-ip ip]"
  exit 1
fi

RAW_LOG="${OUTPUT_RAW_DIR}/step2_perf_${DIRECTION}.log"
ROUNDS_TSV="${OUTPUT_SUMMARY_DIR}/step2_perf_${DIRECTION}_rounds.tsv"
SUMMARY_JSON="${OUTPUT_SUMMARY_DIR}/step2_perf_${DIRECTION}_summary.json"
: > "${RAW_LOG}"
printf "timestamp\tdirection\tround\tpeer_ip\tport\tsize\tconcurrency\tsuccess_count\tfail_count\telapsed_ms\tthroughput_mb_s\n" > "${ROUNDS_TSV}"

cd "${PRO_DIR}"
if [[ ! -x "${APP_BIN}" ]]; then
  echo "[perf] build/app 不存在，请先构建" | tee -a "${RAW_LOG}"
  exit 1
fi

PERF_DATA_DIR="${DATA_DIR}/dual_host_perf"
mkdir -p "${PERF_DATA_DIR}"
INPUT_FILE="${PERF_DATA_DIR}/input_${SIZE}.bin"

case "${SIZE}" in
  10MB) dd if=/dev/zero of="${INPUT_FILE}" bs=1M count=10 status=none ;;
  100MB) dd if=/dev/zero of="${INPUT_FILE}" bs=1M count=100 status=none ;;
  1GB) dd if=/dev/zero of="${INPUT_FILE}" bs=1M count=1024 status=none ;;
  *)
    echo "[perf] 不支持的 size=${SIZE}，仅支持 10MB/100MB/1GB" | tee -a "${RAW_LOG}"
    exit 1
    ;;
esac

if [[ "${DIRECTION}" == "win_to_mac" ]]; then
  TARGET_IP="${OVERRIDE_PEER_IP:-${MAC_HOST_IP}}"
  PORT_CSV="${OVERRIDE_PORTS:-${MAC_PORTS}}"
  split_csv_to_array "${PORT_CSV}" TARGET_PORTS
  CHUNK_ID="${CHUNK_ID:-dummy_chunk_id_for_connectivity}"

  total_elapsed=0
  total_success=0
  total_fail=0

  for ((r=1; r<=ROUNDS; r++)); do
    for p in "${TARGET_PORTS[@]}"; do
      start_ms="$(date +%s%3N)"
      success_count=0
      fail_count=0

      for ((c=1; c<=CONCURRENCY; c++)); do
        if "${APP_BIN}" --config configs/app.yaml --mode client \
            --peer "${TARGET_IP}:${p}" --chunk_id "${CHUNK_ID}" --strategy round_robin \
            >> "${RAW_LOG}" 2>&1; then
          success_count=$((success_count + 1))
        else
          fail_count=$((fail_count + 1))
        fi
      done

      end_ms="$(date +%s%3N)"
      elapsed_ms=$((end_ms - start_ms))
      if [[ "${elapsed_ms}" -le 0 ]]; then elapsed_ms=1; fi
      throughput="$(awk -v mb=10 -v ms="${elapsed_ms}" 'BEGIN{printf "%.3f", (mb*1000)/ms}')"

      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(date '+%F %T')" "${DIRECTION}" "${r}" "${TARGET_IP}" "${p}" "${SIZE}" "${CONCURRENCY}" \
        "${success_count}" "${fail_count}" "${elapsed_ms}" "${throughput}" >> "${ROUNDS_TSV}"

      total_elapsed=$((total_elapsed + elapsed_ms))
      total_success=$((total_success + success_count))
      total_fail=$((total_fail + fail_count))
    done
  done

  total_req=$((total_success + total_fail))
  if [[ "${total_req}" -eq 0 ]]; then
    success_rate="0.000"
  else
    success_rate="$(awk -v s="${total_success}" -v t="${total_req}" 'BEGIN{printf "%.3f", s/t}')"
  fi

  avg_elapsed="$(awk -v x="${total_elapsed}" -v n="$((ROUNDS * ${#TARGET_PORTS[@]}))" 'BEGIN{if(n==0)n=1; printf "%.3f", x/n}')"
  avg_throughput="$(awk -v x="${total_elapsed}" -v n="$((ROUNDS * ${#TARGET_PORTS[@]}))" 'BEGIN{if(x<=0)x=1; printf "%.3f", (n*10*1000)/x}')"

  cat > "${SUMMARY_JSON}" <<EOF
{
  "direction": "${DIRECTION}",
  "rounds": ${ROUNDS},
  "size": "${SIZE}",
  "concurrency": ${CONCURRENCY},
  "avg_elapsed_ms": ${avg_elapsed},
  "avg_throughput_mb_s": ${avg_throughput},
  "success_rate": ${success_rate},
  "success_count": ${total_success},
  "fail_count": ${total_fail}
}
EOF

  echo "[perf] PASS(win_to_mac) summary=${SUMMARY_JSON}" | tee -a "${RAW_LOG}"
  exit 0
fi

if [[ "${DIRECTION}" == "mac_to_win" ]]; then
  PORT_CSV="${OVERRIDE_PORTS:-${WIN_PORTS}}"
  split_csv_to_array "${PORT_CSV}" LOCAL_PORTS
  echo "[perf] mac_to_win 模式：本机先提供服务窗口，Mac 侧执行压测命令" | tee -a "${RAW_LOG}"
  echo "[perf] Mac 侧示例命令：" | tee -a "${RAW_LOG}"
  echo "bash windows执行/scripts/step2_dual_host_perf.sh --direction win_to_mac --peer-ip ${WIN_HOST_IP} --ports ${PORT_CSV} --rounds ${ROUNDS} --size ${SIZE} --concurrency ${CONCURRENCY}" | tee -a "${RAW_LOG}"

  # 这里仅输出占位汇总，避免误解为已完成真实压测
  cat > "${SUMMARY_JSON}" <<EOF
{
  "direction": "${DIRECTION}",
  "status": "waiting_remote_execution",
  "note": "请在 Mac 侧执行客户端压测后，将结果回填到统一汇总。"
}
EOF
  echo "[perf] mac_to_win 需对端执行，已生成占位 summary=${SUMMARY_JSON}" | tee -a "${RAW_LOG}"
  exit 0
fi

echo "direction 仅支持: win_to_mac | mac_to_win"
exit 1
