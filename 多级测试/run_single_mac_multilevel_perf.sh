#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRO_DIR="${ROOT_DIR}/pro"
cd "${PRO_DIR}"

NODE_COUNTS="${NODE_COUNTS:-3,8,14,16}"
CONCURRENCY_LEVELS="${CONCURRENCY_LEVELS:-1,8,16}"
ROUNDS="${ROUNDS:-2}"
FILE_SIZE_MB="${FILE_SIZE_MB:-0.4}"
FILE_COUNT="${FILE_COUNT:-96}"
BASE_PORT="${BASE_PORT:-9600}"
ONLY_GROUP="${ONLY_GROUP:-}"
SKIP_BUILD="${SKIP_BUILD:-0}"

OUT_DIR="${ROOT_DIR}/output/single_mac_multilevel"
RAW_DIR="${OUT_DIR}/raw"
SUMMARY_DIR="${OUT_DIR}/summary"
DATA_ROOT="${ROOT_DIR}/data/single_mac_multilevel"
mkdir -p "${RAW_DIR}" "${SUMMARY_DIR}" "${DATA_ROOT}" "${PRO_DIR}/logs"

RUN_TAG="$(date +%Y%m%d_%H%M%S)"
RUN_TSV="${SUMMARY_DIR}/runs_${RUN_TAG}.tsv"
GROUP_SUMMARY="${SUMMARY_DIR}/group_summary_${RUN_TAG}.tsv"
EXPLAIN_MD="${SUMMARY_DIR}/结果说明_${RUN_TAG}.md"

printf "timestamp\tgroup_id\tround\tnode_count\tconcurrency\tmode\tfile_count\tfile_size_mb\tsuccess\tfail\telapsed_ms\tthroughput_mb_s\n" > "${RUN_TSV}"
printf "group_id\tnode_count\tconcurrency\tmode\trounds\tavg_elapsed_ms\tavg_throughput_mb_s\tsuccess_rate\n" > "${GROUP_SUMMARY}"

cat > "${EXPLAIN_MD}" <<EOF
# 单机多级性能测试结果说明（中文详细版）

## 1. 本次测试的文件输出（持久化）

本次执行会生成以下**持久化文件**，脚本结束后不会丢失：

1. 逐轮明细：\`${RUN_TSV}\`
2. 分组汇总：\`${GROUP_SUMMARY}\`
3. 中文说明：\`${EXPLAIN_MD}\`（本文件）

---

## 2. 逐轮明细 runs_*.tsv 字段解释（非常详细）

- \`timestamp\`：该条结果写入时间（本地时间），用于追踪测试发生时刻。
- \`group_id\`：分组唯一标识，格式为 \`N{节点数}_C{并发度}_F{文件数}_S{单文件大小MB}MB\`。
  - 例：\`N8_C16_F96_S2MB\` 表示 8 个服务端节点、客户端并发 16、总文件数 96、每个文件 2MB。
- \`round\`：轮次编号（从 1 开始），每组通常跑多轮（默认 3 轮）用于降低偶然波动影响。
- \`node_count\`：服务端节点数量（同机不同端口多进程模拟）。
- \`concurrency\`：客户端下载并发度。
  - 值为 1 代表串行批量（一次只下载 1 个）。
  - 值大于 1 代表并行批量（同时发起多个下载任务）。
- \`mode\`：模式文字，\`serial\` 表示串行，\`parallel\` 表示并行。
- \`file_count\`：该组总下载文件数量（每轮都按该数量执行）。
- \`file_size_mb\`：单文件大小（MB）。
- \`success\`：该轮成功下载次数。
- \`fail\`：该轮失败次数。
- \`elapsed_ms\`：该轮总耗时（毫秒），从该轮第一条请求开始到最后一条请求结束。
- \`throughput_mb_s\`：该轮吞吐（MB/s），计算公式：\`(file_count * file_size_mb) / (elapsed_ms / 1000)\`。

---

## 3. 分组汇总 group_summary_*.tsv 字段解释（非常详细）

- \`group_id\` / \`node_count\` / \`concurrency\` / \`mode\`：含义同上，用于标识组别。
- \`rounds\`：该分组实际执行轮数。
- \`avg_elapsed_ms\`：该分组平均每轮耗时（毫秒）。
- \`avg_throughput_mb_s\`：该分组平均吞吐（MB/s）。
- \`success_rate\`：该组总成功率，计算公式：\`总成功次数 / (总成功次数 + 总失败次数)\`。

---

## 4. 如何判断“数据点够不够多”

建议标准（本脚本默认配置已覆盖）：

1. 节点维度：至少覆盖多个节点数量（默认 \`3,8,14,16\`）。
2. 并发维度：至少覆盖串行和两档并行（默认 \`1,8,16\`）。
3. 轮次维度：每组至少 3 轮（默认 \`ROUNDS=3\`）。
4. 总点数估算：
   - 分组数 = 节点组数 × 并发组数
   - 明细点数 = 分组数 × 轮次
   - 默认：\`4 × 3 × 3 = 36\` 个逐轮数据点（不含汇总行）

36 个逐轮点通常足以做趋势判断与横向对比；如果你希望统计更稳，可把 \`ROUNDS\` 提高到 5 或 7。

---

## 5. 推荐解读方法（中文）

1. **同节点看并发**：固定 \`node_count\`，比较 \`concurrency=1/8/16\` 的 \`avg_elapsed_ms\` 与 \`avg_throughput_mb_s\`。
2. **同并发看节点**：固定 \`concurrency\`，比较 \`node_count=3/8/14/16\` 的变化趋势。
3. **先看成功率**：如果 \`success_rate\` 明显下降，优先看稳定性，再看吞吐。
4. **关注极限点**：高并发高节点（如 N16_C16）若吞吐不再上升，说明接近瓶颈区。

---

## 6. 防止“跑完没有数据”

脚本启动时就会先创建并写入表头到 TSV 文件；每组每轮完成后立即追加写入。  
只要脚本有执行到任何一轮，\`${RUN_TSV}\` 和 \`${GROUP_SUMMARY}\` 都会留下可追溯数据。
EOF

if [[ "${SKIP_BUILD}" != "1" ]]; then
  echo "[perf] build app"
  cmake -S . -B build
  cmake --build build
fi
APP_BIN="${PRO_DIR}/build/app"
if [[ ! -x "${APP_BIN}" ]]; then
  echo "[perf] build/app not found"
  exit 1
fi

cleanup_pids=()
cleanup() {
  for pid in "${cleanup_pids[@]:-}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" || true
      wait "${pid}" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

split_csv() {
  local csv="$1"
  IFS=',' read -r -a temp_arr <<< "$csv"
  eval "$2=(\"\${temp_arr[@]}\")"
}

get_time_ms() {
  python3 -c 'import time; print(int(time.time() * 1000))'
}

wait_server_ready() {
  local log_file="$1"
  local waited=0
  while [[ ${waited} -lt 30 ]]; do
    if [[ -f "${log_file}" ]] && grep -q 'tcp server waiting for client' "${log_file}"; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "[perf] server not ready: ${log_file}"
  return 1
}

prepare_dataset() {
  local n="$1"
  local dataset_dir="${DATA_ROOT}/dataset_n${n}_f${FILE_COUNT}_s${FILE_SIZE_MB}mb"
  mkdir -p "${dataset_dir}"
  for ((i=1; i<=FILE_COUNT; i++)); do
    local f="${dataset_dir}/f_$(printf '%03d' "${i}").bin"
    if [[ ! -f "${f}" ]]; then
      # 把 MB 转成 KB，用整数 count
      local size_kb=$(awk 'BEGIN{printf("%d",'"${FILE_SIZE_MB}"' * 1024)}')
      dd if=/dev/urandom of="${f}" bs=1k count="${size_kb}" status=none
    fi
  done
  echo "${dataset_dir}"
}

start_nodes() {
  local n="$1"
  local run_root="$2"
  local dataset_dir="$3"
  local cfg_dir="${run_root}/configs"
  mkdir -p "${cfg_dir}"

  local seeds=""
  for ((i=1; i<=n; i++)); do
    local port=$((BASE_PORT + i))
    seeds+="127.0.0.1:${port},"
  done
  seeds="${seeds%,}"

  for ((i=1; i<=n; i++)); do
    local node_id="node-${i}"
    local port=$((BASE_PORT + i))
    cat > "${cfg_dir}/${node_id}.yaml" <<YAML
node_id: "${node_id}"
listen_port: ${port}
seed_nodes: "${seeds}"
self_addr: "127.0.0.1:${port}"
chunks_dir: "${run_root}/${node_id}/chunks"
chunk_index_file: "${run_root}/${node_id}/chunk_index.tsv"
aes_key_hex: "00112233445566778899aabbccddeeff"
hmac_key_hex: "0102030405060708090a0b0c0d0e0f10"
log_file: "logs/single_mac_${RUN_TAG}_${node_id}.log"
YAML
  done

  local upload_pids=()
  for ((i=1; i<=n; i++)); do
    (
      local cfg="${cfg_dir}/node-${i}.yaml"
      for f in "${dataset_dir}"/*.bin; do
        "${APP_BIN}" --config "${cfg}" --input "${f}" >/dev/null 2>&1
      done
    ) &
    upload_pids+=("$!")
  done
  for pid in "${upload_pids[@]}"; do
    wait "${pid}"
  done

  for ((i=1; i<=n; i++)); do
    local cfg="${cfg_dir}/node-${i}.yaml"
    local slog="${RAW_DIR}/server_n${n}_node${i}_${RUN_TAG}.log"
    "${APP_BIN}" --config "${cfg}" --mode server > "${slog}" 2>&1 &
    cleanup_pids+=("$!")
  done

  for ((i=1; i<=n; i++)); do
    wait_server_ready "${RAW_DIR}/server_n${n}_node${i}_${RUN_TAG}.log"
  done

  echo "${cfg_dir}"
}

run_group() {
  local n="$1"
  local c="$2"
  local mode="parallel"
  if [[ "${c}" -eq 1 ]]; then
    mode="serial"
  fi
  local gid="N${n}_C${c}_F${FILE_COUNT}_S${FILE_SIZE_MB}MB"
  if [[ -n "${ONLY_GROUP}" && "${gid}" != "${ONLY_GROUP}" ]]; then
    return 0
  fi

  echo "[perf] group=${gid}"
  local run_root="${DATA_ROOT}/run_${gid}_${RUN_TAG}"
  mkdir -p "${run_root}"

  local dataset_dir
  dataset_dir="$(prepare_dataset "${n}")"
  local cfg_dir
  cfg_dir="$(start_nodes "${n}" "${run_root}" "${dataset_dir}")"

  # 彻底移除 mapfile，兼容所有 bash
  chunk_ids=()
  while IFS= read -r line; do
    chunk_ids+=("$line")
  done < <(awk '{print $1}' "${run_root}/node-1/chunk_index.tsv" | head -n "${FILE_COUNT}")

  if [[ "${#chunk_ids[@]}" -eq 0 ]]; then
    echo "[perf] no chunk ids found for ${gid}"
    exit 1
  fi

  local total_elapsed=0
  local total_success=0
  local total_fail=0

  for ((r=1; r<=ROUNDS; r++)); do
    local start_ms end_ms elapsed_ms
    start_ms="$(get_time_ms)"
    local success=0
    local fail=0

    if [[ "${c}" -eq 1 ]]; then
      for cid in "${chunk_ids[@]}"; do
        if "${APP_BIN}" --config "${cfg_dir}/node-1.yaml" --mode client \
          --peer "127.0.0.1:$((BASE_PORT + 1))" --chunk_id "${cid}" --strategy round_robin \
          >> "${RAW_DIR}/${gid}_client_${RUN_TAG}.log" 2>&1; then
          success=$((success + 1))
        else
          fail=$((fail + 1))
        fi
      done
    else
      pids=()
      stats=()
      active=0
      idx=0
      for cid in "${chunk_ids[@]}"; do
        idx=$((idx + 1))
        (
          if "${APP_BIN}" --config "${cfg_dir}/node-1.yaml" --mode client \
            --peer "127.0.0.1:$((BASE_PORT + 1))" --chunk_id "${cid}" --strategy round_robin \
            >> "${RAW_DIR}/${gid}_client_${RUN_TAG}.log" 2>&1; then
            echo ok
          else
            echo fail
          fi
        ) > "${run_root}/job_${r}_${idx}.status" &
        pids+=("$!")
        active=$((active + 1))
        if [[ ${active} -ge ${c} ]]; then
          wait "${pids[0]}" || true
          pids=("${pids[@]:1}")
          active=$((active - 1))
        fi
      done
      for pid in "${pids[@]}"; do wait "${pid}" || true; done

      while IFS= read -r s; do
        if [[ "${s}" == "ok" ]]; then success=$((success + 1)); else fail=$((fail + 1)); fi
      done < <(cat "${run_root}"/job_${r}_*.status)
    fi

    end_ms="$(get_time_ms)"
    elapsed_ms=$((end_ms - start_ms))
    [[ "${elapsed_ms}" -le 0 ]] && elapsed_ms=1

    local throughput
    throughput="$(awk -v f="${FILE_COUNT}" -v s="${FILE_SIZE_MB}" -v ms="${elapsed_ms}" 'BEGIN{printf "%.3f", (f*s*1000)/ms}')"

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$(date '+%F %T')" "${gid}" "${r}" "${n}" "${c}" "${mode}" "${FILE_COUNT}" "${FILE_SIZE_MB}" \
      "${success}" "${fail}" "${elapsed_ms}" "${throughput}" >> "${RUN_TSV}"

    total_elapsed=$((total_elapsed + elapsed_ms))
    total_success=$((total_success + success))
    total_fail=$((total_fail + fail))
  done

  local avg_elapsed avg_tp success_rate total_req
  avg_elapsed="$(awk -v x="${total_elapsed}" -v n="${ROUNDS}" 'BEGIN{printf "%.3f", x/n}')"
  avg_tp="$(awk -v x="${total_elapsed}" -v f="${FILE_COUNT}" -v s="${FILE_SIZE_MB}" -v n="${ROUNDS}" 'BEGIN{printf "%.3f", (n*f*s*1000)/x}')"
  total_req=$((total_success + total_fail))
  success_rate="$(awk -v ok="${total_success}" -v all="${total_req}" 'BEGIN{if(all==0){print "0.000"}else{printf "%.3f", ok/all}}')"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "${gid}" "${n}" "${c}" "${mode}" "${ROUNDS}" "${avg_elapsed}" "${avg_tp}" "${success_rate}" >> "${GROUP_SUMMARY}"

  cleanup
  cleanup_pids=()
}

node_arr=()
conc_arr=()
split_csv "${NODE_COUNTS}" node_arr
split_csv "${CONCURRENCY_LEVELS}" conc_arr

for n in "${node_arr[@]}"; do
  for c in "${conc_arr[@]}"; do
    run_group "${n}" "${c}"
  done
done

echo "[perf] done"
echo "[perf] runs: ${RUN_TSV}"
echo "[perf] summary: ${GROUP_SUMMARY}"
echo "[perf] 说明文档: ${EXPLAIN_MD}"