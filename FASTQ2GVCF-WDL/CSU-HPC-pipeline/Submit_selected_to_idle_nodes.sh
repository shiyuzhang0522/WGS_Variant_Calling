#!/usr/bin/env bash
set -euo pipefail

SLURM_SCRIPT="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/submit.all_samples.cromwell.slurm.sh"
MANIFEST="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/inputs/wdl_inputs_manifest.tsv"
NODE_ASSIGNMENT_TSV="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/node_assignment.$(date +%Y%m%d_%H%M%S).tsv"

START_TASK="${1:?Usage: bash submit_selected_to_idle_nodes.sh <start_task> <end_task> [exclude_task_id]}"
END_TASK="${2:?Usage: bash submit_selected_to_idle_nodes.sh <start_task> <end_task> [exclude_task_id]}"
EXCLUDE_TASK="${3:-}"

if [[ ! -s "${SLURM_SCRIPT}" ]]; then
  echo "ERROR: missing SLURM script: ${SLURM_SCRIPT}" >&2
  exit 1
fi

if [[ ! -s "${MANIFEST}" ]]; then
  echo "ERROR: missing manifest: ${MANIFEST}" >&2
  exit 1
fi

MAX_TASK_ID=$(( $(wc -l < "${MANIFEST}") - 1 ))

if (( START_TASK < 1 || END_TASK > MAX_TASK_ID || START_TASK > END_TASK )); then
  echo "ERROR: invalid task range: ${START_TASK}-${END_TASK}" >&2
  echo "Valid range: 1-${MAX_TASK_ID}" >&2
  exit 1
fi

# Select only truly idle cpuQ nodes.
# This excludes drain, down, mix, alloc, inval, plnd, and idle* nodes.
mapfile -t IDLE_NODES < <(
  sinfo -N -h -p cpuQ -o "%N %T" \
    | awk '$2=="idle" {print $1}' \
    | sort -V
)

echo "=================================================="
echo "Sanity check: selected cpuQ nodes"
echo "Detected truly idle nodes: ${#IDLE_NODES[@]}"
echo
echo "First 20 selected nodes:"
printf '%s\n' "${IDLE_NODES[@]:0:20}"
echo
echo "State check for first 20 selected nodes:"
for node in "${IDLE_NODES[@]:0:20}"; do
  sinfo -N -h -n "${node}" -o "%N %T"
done
echo "=================================================="

TASK_IDS=()
for task_id in $(seq "${START_TASK}" "${END_TASK}"); do
  if [[ -n "${EXCLUDE_TASK}" && "${task_id}" -eq "${EXCLUDE_TASK}" ]]; then
    continue
  fi
  TASK_IDS+=("${task_id}")
done

echo "Task range requested : ${START_TASK}-${END_TASK}"
echo "Excluded task        : ${EXCLUDE_TASK:-None}"
echo "Tasks to submit      : ${#TASK_IDS[@]}"
echo "Idle nodes available : ${#IDLE_NODES[@]}"

if (( ${#IDLE_NODES[@]} < ${#TASK_IDS[@]} )); then
  echo "ERROR: insufficient truly idle cpuQ nodes." >&2
  exit 1
fi

echo -e "task_id\tsample_uid\tnode" > "${NODE_ASSIGNMENT_TSV}"

echo
echo "Node assignment preview:"
for i in "${!TASK_IDS[@]}"; do
  task_id="${TASK_IDS[$i]}"
  node="${IDLE_NODES[$i]}"
  sample_uid="$(awk -v n="${task_id}" 'NR==n+1 {print $1}' "${MANIFEST}")"

  echo -e "${task_id}\t${sample_uid}\t${node}" >> "${NODE_ASSIGNMENT_TSV}"

  if (( i < 20 )); then
    echo -e "${task_id}\t${sample_uid}\t${node}"
  fi
done

echo "=================================================="
echo "Node assignment saved to:"
echo "${NODE_ASSIGNMENT_TSV}"
echo "=================================================="

read -r -p "Proceed with sbatch submission? Type YES to continue: " CONFIRM

if [[ "${CONFIRM}" != "YES" ]]; then
  echo "Submission cancelled."
  exit 0
fi

for i in "${!TASK_IDS[@]}"; do
  task_id="${TASK_IDS[$i]}"
  node="${IDLE_NODES[$i]}"
  sample_uid="$(awk -v n="${task_id}" 'NR==n+1 {print $1}' "${MANIFEST}")"

  echo "Submitting task ${task_id} | ${sample_uid} | node=${node}"

  sbatch \
    --array="${task_id}-${task_id}" \
    --nodelist="${node}" \
    "${SLURM_SCRIPT}"

  sleep 1
done

echo "Done."