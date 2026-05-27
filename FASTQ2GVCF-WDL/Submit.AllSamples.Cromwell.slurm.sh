#!/usr/bin/env bash
#SBATCH --job-name=XYCM_GVCF
#SBATCH --partition=partFAT2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=90G
#SBATCH --output=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/WDL/logs/XYCM_GVCF.%A_%a.out
#SBATCH --error=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/WDL/logs/XYCM_GVCF.%A_%a.err

# Date Lastly Modified: 2026-5-27
# Author: Shelley

set -euo pipefail

source /lustre/home/zhangsy/softwares/miniforge3/etc/profile.d/conda.sh
conda activate gatk_germline

WDL_DIR="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/WDL"
WDL_FILE="${WDL_DIR}/XYCM_Germline_GVCF.wdl"
INPUT_MANIFEST="${WDL_DIR}/inputs/wdl_inputs_manifest.tsv"
RUN_ROOT="${WDL_DIR}/runs/production"
FINAL_ROOT="${WDL_DIR}/final_outputs"
LOG_DIR="${WDL_DIR}/logs"
STATUS_DIR="${RUN_ROOT}/status"
STATUS_TSV="${RUN_ROOT}/production_status.tsv"
STATUS_LOCK="${STATUS_TSV}.lock"
CROMWELL_JAR="/lustre/home/zhangsy/softwares/miniforge3/envs/gatk_germline/share/cromwell/cromwell.jar"

mkdir -p "${RUN_ROOT}" "${FINAL_ROOT}" "${LOG_DIR}" "${STATUS_DIR}"

append_status() {
  local sample_uid="$1"
  local status="$2"
  local slurm_job_id="$3"
  local slurm_array_task_id="$4"
  local start_time="$5"
  local end_time="$6"
  local run_dir="$7"
  local final_dir="$8"
  local input_json="$9"

  {
    flock -x 200

    if [[ ! -s "${STATUS_TSV}" ]]; then
      echo -e "sample_uid\tstatus\tslurm_job_id\tslurm_array_task_id\tstart_time\tend_time\trun_dir\tfinal_dir\tinput_json" > "${STATUS_TSV}"
    fi

    echo -e "${sample_uid}\t${status}\t${slurm_job_id}\t${slurm_array_task_id}\t${start_time}\t${end_time}\t${run_dir}\t${final_dir}\t${input_json}" >> "${STATUS_TSV}"
  } 200>"${STATUS_LOCK}"
}

if [[ ! -s "${WDL_FILE}" ]]; then
  echo "ERROR: missing WDL file: ${WDL_FILE}" >&2
  exit 1
fi

if [[ ! -s "${INPUT_MANIFEST}" ]]; then
  echo "ERROR: missing input manifest: ${INPUT_MANIFEST}" >&2
  exit 1
fi

if [[ ! -s "${CROMWELL_JAR}" ]]; then
  echo "ERROR: missing Cromwell jar: ${CROMWELL_JAR}" >&2
  exit 1
fi

if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  echo "ERROR: this script must be submitted as a SLURM array job." >&2
  exit 1
fi

INPUT_JSON="$(awk -v n="${SLURM_ARRAY_TASK_ID}" 'NR==n {print $2}' "${INPUT_MANIFEST}")"

if [[ -z "${INPUT_JSON}" || ! -s "${INPUT_JSON}" ]]; then
  echo "ERROR: invalid input JSON for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}: ${INPUT_JSON}" >&2
  exit 1
fi

SAMPLE_UID="$(basename "${INPUT_JSON}" .inputs.json)"
RUN_DIR="${RUN_ROOT}/${SAMPLE_UID}"
FINAL_DIR="${FINAL_ROOT}/${SAMPLE_UID}"
OPTIONS_JSON="${RUN_DIR}/cromwell.options.production.json"

RUNNING_FLAG="${STATUS_DIR}/${SAMPLE_UID}.running"
SUCCESS_FLAG="${STATUS_DIR}/${SAMPLE_UID}.success"
FAILED_FLAG="${STATUS_DIR}/${SAMPLE_UID}.failed"

FINAL_GVCF="${FINAL_DIR}/${SAMPLE_UID}.g.vcf.gz"
FINAL_TBI="${FINAL_DIR}/${SAMPLE_UID}.g.vcf.gz.tbi"

mkdir -p "${RUN_DIR}" "${FINAL_DIR}"

START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

echo "=================================================="
echo "START TIME: ${START_TIME}"
echo "HOSTNAME: $(hostname)"
echo "SAMPLE_UID: ${SAMPLE_UID}"
echo "INPUT_JSON: ${INPUT_JSON}"
echo "RUN_DIR: ${RUN_DIR}"
echo "FINAL_DIR: ${FINAL_DIR}"
echo "SLURM_JOB_ID: ${SLURM_JOB_ID:-NA}"
echo "SLURM_ARRAY_TASK_ID: ${SLURM_ARRAY_TASK_ID}"
echo "=================================================="

if [[ -s "${FINAL_GVCF}" && -s "${FINAL_TBI}" ]]; then
  END_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "SKIP: final GVCF already exists."
  echo "FINAL_GVCF: ${FINAL_GVCF}"

  touch "${SUCCESS_FLAG}"
  rm -f "${RUNNING_FLAG}" "${FAILED_FLAG}"

  append_status \
    "${SAMPLE_UID}" "SKIPPED" "${SLURM_JOB_ID:-NA}" "${SLURM_ARRAY_TASK_ID}" \
    "${START_TIME}" "${END_TIME}" "${RUN_DIR}" "${FINAL_DIR}" "${INPUT_JSON}"

  exit 0
fi

rm -f "${SUCCESS_FLAG}" "${FAILED_FLAG}"
touch "${RUNNING_FLAG}"

cat > "${OPTIONS_JSON}" <<EOT
{
  "final_workflow_outputs_dir": "${FINAL_DIR}",
  "use_relative_output_paths": true,
  "delete_intermediate_output_files": true
}
EOT

cd "${RUN_DIR}"

set +e
java -jar "${CROMWELL_JAR}" \
  run "${WDL_FILE}" \
  --inputs "${INPUT_JSON}" \
  --options "${OPTIONS_JSON}"
RC=$?
set -e

END_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

if [[ "${RC}" -eq 0 && -s "${FINAL_GVCF}" && -s "${FINAL_TBI}" ]]; then
  echo "SUCCESS: ${SAMPLE_UID}"

  touch "${SUCCESS_FLAG}"
  rm -f "${RUNNING_FLAG}" "${FAILED_FLAG}"

  append_status \
    "${SAMPLE_UID}" "SUCCESS" "${SLURM_JOB_ID:-NA}" "${SLURM_ARRAY_TASK_ID}" \
    "${START_TIME}" "${END_TIME}" "${RUN_DIR}" "${FINAL_DIR}" "${INPUT_JSON}"
else
  echo "FAILED: ${SAMPLE_UID}" >&2
  echo "Return code: ${RC}" >&2

  touch "${FAILED_FLAG}"
  rm -f "${RUNNING_FLAG}"

  append_status \
    "${SAMPLE_UID}" "FAILED" "${SLURM_JOB_ID:-NA}" "${SLURM_ARRAY_TASK_ID}" \
    "${START_TIME}" "${END_TIME}" "${RUN_DIR}" "${FINAL_DIR}" "${INPUT_JSON}"

  exit "${RC}"
fi

echo "=================================================="
echo "END TIME: ${END_TIME}"
echo "=================================================="

# Usage: 
# sbatch --array=1-16%4 /lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/WDL/submit.all_samples.cromwell.slurm.sh