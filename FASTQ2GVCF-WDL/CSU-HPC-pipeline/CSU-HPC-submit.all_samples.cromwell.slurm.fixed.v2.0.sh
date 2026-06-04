#!/usr/bin/env bash
#SBATCH --job-name=XYCM_GVCF
#SBATCH --partition=cpuQ
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --qos=cpuq
#SBATCH --mem=90G
#SBATCH --output=/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/logs/XYCM_GVCF.%A_%a.out
#SBATCH --error=/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/logs/XYCM_GVCF.%A_%a.err
#SBATCH --account=pi_dengguangtong

set -euo pipefail

############################################################
## XYCM WGS Germline GVCF Cromwell SLURM wrapper
##
## Purpose:
##   Run one WDL input JSON per SLURM array task.
##
## Major fixes:
##   1. Correctly parse input JSON path from manifest column 6.
##   2. Detect Cromwell final outputs recursively.
##   3. Flatten final GVCF/TBI into FINAL_DIR.
##   4. Clean intermediate BAM/BAI/MD5 files and execution GVCF/TBI after success.
##   5. Exit nonzero if output checks fail, even when Cromwell RC=0.
##
## Author: Shelley
## Date Last Modified: 2026-06-04
############################################################

source /public/home/hpc8301200407/miniconda3/etc/profile.d/conda.sh
conda activate gatk_germline

WDL_DIR="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL"
WDL_FILE="${WDL_DIR}/XYCM_Germline_GVCF.v1.0.wdl"
INPUT_MANIFEST="${WDL_DIR}/inputs/wdl_inputs_manifest.tsv"

RUN_ROOT="${WDL_DIR}/runs/production"
FINAL_ROOT="${WDL_DIR}/final_outputs"
LOG_DIR="${WDL_DIR}/logs"
STATUS_DIR="${RUN_ROOT}/status"
STATUS_TSV="${RUN_ROOT}/production_status.tsv"
STATUS_LOCK="${STATUS_TSV}.lock"

CROMWELL_JAR="/public/home/hpc8301200407/miniconda3/envs/gatk_germline/share/cromwell/cromwell.jar"

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

# Manifest columns:
# sample_uid sample_name read_group_id fq1 fq2 inputs_json
# Skip header, so array task 1 maps to line 2.
INPUT_JSON="$(awk -v n="${SLURM_ARRAY_TASK_ID}" 'NR==n+1 {print $6}' "${INPUT_MANIFEST}")"

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
echo "PWD: $(pwd)"
echo "CONDA_DEFAULT_ENV: ${CONDA_DEFAULT_ENV:-NA}"
echo "SAMPLE_UID: ${SAMPLE_UID}"
echo "INPUT_JSON: ${INPUT_JSON}"
echo "RUN_DIR: ${RUN_DIR}"
echo "FINAL_DIR: ${FINAL_DIR}"
echo "SLURM_JOB_ID: ${SLURM_JOB_ID:-NA}"
echo "SLURM_ARRAY_TASK_ID: ${SLURM_ARRAY_TASK_ID}"
echo "WDL_FILE: ${WDL_FILE}"
echo "CROMWELL_JAR: ${CROMWELL_JAR}"
echo "=================================================="

echo "Software check:"
which gatk
which bwa-mem2
which samtools
which java
gatk --version
bwa-mem2 version || true
samtools --version | head -n 1
java -version || true

if [[ -s "${FINAL_GVCF}" && -s "${FINAL_TBI}" ]]; then
  END_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

  echo "SKIP: final GVCF already exists."
  echo "FINAL_GVCF: ${FINAL_GVCF}"
  echo "FINAL_TBI: ${FINAL_TBI}"

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

echo "Cromwell options:"
cat "${OPTIONS_JSON}"

cd "${RUN_DIR}"

set +e
java -jar "${CROMWELL_JAR}" \
  run "${WDL_FILE}" \
  --inputs "${INPUT_JSON}" \
  --options "${OPTIONS_JSON}"
RC=$?
set -e

END_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

echo "Cromwell return code: ${RC}"

FOUND_GVCF="$(find "${FINAL_DIR}" -name "${SAMPLE_UID}.g.vcf.gz" | head -n 1 || true)"
FOUND_TBI="$(find "${FINAL_DIR}" -name "${SAMPLE_UID}.g.vcf.gz.tbi" | head -n 1 || true)"

echo "FOUND_GVCF: ${FOUND_GVCF:-NA}"
echo "FOUND_TBI: ${FOUND_TBI:-NA}"

if [[ -n "${FOUND_GVCF}" && -s "${FOUND_GVCF}" && -n "${FOUND_TBI}" && -s "${FOUND_TBI}" ]]; then
  if [[ "${FOUND_GVCF}" != "${FINAL_GVCF}" ]]; then
    cp -v "${FOUND_GVCF}" "${FINAL_GVCF}"
    rm -v "${FOUND_GVCF}"
  fi

  if [[ "${FOUND_TBI}" != "${FINAL_TBI}" ]]; then
    cp -v "${FOUND_TBI}" "${FINAL_TBI}"
    rm -v "${FOUND_TBI}"
  fi
fi

if [[ "${RC}" -eq 0 && -s "${FINAL_GVCF}" && -s "${FINAL_TBI}" ]]; then
  echo "SUCCESS: ${SAMPLE_UID}"
  echo "FINAL_GVCF: ${FINAL_GVCF}"
  echo "FINAL_TBI: ${FINAL_TBI}"

  echo "Cleaning intermediate BAM/BAI/MD5 files and execution GVCF/TBI from RUN_DIR..."
  if [[ -d "${RUN_DIR}/cromwell-executions" ]]; then
    find "${RUN_DIR}/cromwell-executions" \
      \( -name "*.bam" \
         -o -name "*.bai" \
         -o -name "*.bam.md5" \
         -o -name "*.g.vcf.gz" \
         -o -name "*.g.vcf.gz.tbi" \) \
      -type f -print -delete || true
  fi

  touch "${SUCCESS_FLAG}"
  rm -f "${RUNNING_FLAG}" "${FAILED_FLAG}"

  append_status \
    "${SAMPLE_UID}" "SUCCESS" "${SLURM_JOB_ID:-NA}" "${SLURM_ARRAY_TASK_ID}" \
    "${START_TIME}" "${END_TIME}" "${RUN_DIR}" "${FINAL_DIR}" "${INPUT_JSON}"

else
  echo "FAILED: ${SAMPLE_UID}" >&2
  echo "Return code: ${RC}" >&2
  echo "Expected FINAL_GVCF: ${FINAL_GVCF}" >&2
  echo "Expected FINAL_TBI: ${FINAL_TBI}" >&2
  echo "FOUND_GVCF: ${FOUND_GVCF:-NA}" >&2
  echo "FOUND_TBI: ${FOUND_TBI:-NA}" >&2

  touch "${FAILED_FLAG}"
  rm -f "${RUNNING_FLAG}"

  append_status \
    "${SAMPLE_UID}" "FAILED" "${SLURM_JOB_ID:-NA}" "${SLURM_ARRAY_TASK_ID}" \
    "${START_TIME}" "${END_TIME}" "${RUN_DIR}" "${FINAL_DIR}" "${INPUT_JSON}"

  exit 1
fi

echo "=================================================="
echo "END TIME: ${END_TIME}"
echo "=================================================="