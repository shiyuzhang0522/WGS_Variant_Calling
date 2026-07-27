#!/usr/bin/env bash
#SBATCH --job-name=XYCM_GenomicsDBImport
#SBATCH --partition=cpuQ
#SBATCH --qos=cpuq
#SBATCH --account=pi_dengguangtong
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=80G
#SBATCH --time=3-00:00:00
#SBATCH --array=1-25
#SBATCH --output=/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/Joint_Genotyping/GenomicsDBImport/logs/GenomicsDBImport.%A_%a.out
#SBATCH --error=/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/Joint_Genotyping/GenomicsDBImport/logs/GenomicsDBImport.%A_%a.err

set -euo pipefail

# ==============================================================================
# XYCM WGS Joint Genotyping Pipeline
# Step 3. GenomicsDBImport
#
# Purpose:
#   Import 449 single-sample HaplotypeCaller gVCFs into chromosome-specific
#   GenomicsDB workspaces for subsequent joint genotyping with GenotypeGVCFs.
#
# Chromosomes:
#   chr1-chr22, chrX, chrY, chrM
#
# Input:
#   genomicsdb.sample_map.tsv
#
# Output:
#   GenomicsDBImport/genomicsdb/<chromosome>/
#
# Cohort:
#   449 technical samples, including five intended technical replicate pairs.
# ==============================================================================


# ------------------------------------------------------------------------------
# 0. Configuration
# ------------------------------------------------------------------------------

JOINT_DIR="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/Joint_Genotyping"
WORK_DIR="${JOINT_DIR}/GenomicsDBImport"

SAMPLE_MAP="${JOINT_DIR}/genomicsdb.sample_map.tsv"

REF_DIR="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/Resource.bundle/GATK.hg38"
REF="${REF_DIR}/Homo_sapiens_assembly38.fasta"
REF_FAI="${REF}.fai"
REF_DICT="${REF_DIR}/Homo_sapiens_assembly38.dict"

DB_ROOT="${WORK_DIR}/genomicsdb"
TMP_ROOT="${WORK_DIR}/tmp"
STATUS_DIR="${WORK_DIR}/status"

EXPECTED_SAMPLES=449


# ------------------------------------------------------------------------------
# 1. Environment
# ------------------------------------------------------------------------------

source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate gatk_germline

command -v gatk >/dev/null 2>&1 || {
    echo "ERROR: gatk is not available in the current environment." >&2
    exit 1
}

cd "${WORK_DIR}"

mkdir -p \
    "${DB_ROOT}" \
    "${TMP_ROOT}" \
    "${STATUS_DIR}"


# ------------------------------------------------------------------------------
# 2. Chromosome assignment
#
# SLURM array:
#    1-22 -> chr1-chr22
#    23   -> chrX
#    24   -> chrY
#    25   -> chrM
# ------------------------------------------------------------------------------

CHROMS=(
    chr1
    chr2
    chr3
    chr4
    chr5
    chr6
    chr7
    chr8
    chr9
    chr10
    chr11
    chr12
    chr13
    chr14
    chr15
    chr16
    chr17
    chr18
    chr19
    chr20
    chr21
    chr22
    chrX
    chrY
    chrM
)

if [[ "${SLURM_ARRAY_TASK_ID}" -lt 1 || \
      "${SLURM_ARRAY_TASK_ID}" -gt "${#CHROMS[@]}" ]]; then
    echo "ERROR: invalid SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

IDX=$((SLURM_ARRAY_TASK_ID - 1))
CHR="${CHROMS[$IDX]}"

DB="${DB_ROOT}/${CHR}"
TMP="${TMP_ROOT}/${CHR}"
SUCCESS_FILE="${STATUS_DIR}/${CHR}.success"


# ------------------------------------------------------------------------------
# 3. Sample-map sanity checks
# ------------------------------------------------------------------------------

if [[ ! -s "${SAMPLE_MAP}" ]]; then
    echo "ERROR: sample map is missing or empty:" >&2
    echo "  ${SAMPLE_MAP}" >&2
    exit 1
fi

N_SAMPLES=$(wc -l < "${SAMPLE_MAP}")

if [[ "${N_SAMPLES}" -ne "${EXPECTED_SAMPLES}" ]]; then
    echo "ERROR: expected ${EXPECTED_SAMPLES} samples; found ${N_SAMPLES}." >&2
    exit 1
fi

N_UNIQUE_SAMPLES=$(cut -f1 "${SAMPLE_MAP}" | sort -u | wc -l)
N_UNIQUE_GVCFS=$(cut -f2 "${SAMPLE_MAP}" | sort -u | wc -l)

if [[ "${N_UNIQUE_SAMPLES}" -ne "${EXPECTED_SAMPLES}" ]]; then
    echo "ERROR: sample map does not contain ${EXPECTED_SAMPLES} unique sample IDs." >&2
    exit 1
fi

if [[ "${N_UNIQUE_GVCFS}" -ne "${EXPECTED_SAMPLES}" ]]; then
    echo "ERROR: sample map does not contain ${EXPECTED_SAMPLES} unique gVCF paths." >&2
    exit 1
fi


# ------------------------------------------------------------------------------
# 4. Reference sanity checks
# ------------------------------------------------------------------------------

if [[ ! -s "${REF}" ]]; then
    echo "ERROR: reference FASTA is missing or empty:" >&2
    echo "  ${REF}" >&2
    exit 1
fi

if [[ ! -s "${REF_FAI}" ]]; then
    echo "ERROR: reference FASTA index is missing or empty:" >&2
    echo "  ${REF_FAI}" >&2
    exit 1
fi

if [[ ! -s "${REF_DICT}" ]]; then
    echo "ERROR: reference sequence dictionary is missing or empty:" >&2
    echo "  ${REF_DICT}" >&2
    exit 1
fi

# Confirm assigned chromosome exists in the reference.
# Use awk instead of a grep -q pipeline to avoid false failures under pipefail.
if ! awk -F'\t' -v chr="${CHR}" '
    $1 == chr {found=1}
    END {exit !found}
' "${REF_FAI}"; then
    echo "ERROR: ${CHR} is absent from the reference FASTA index." >&2
    exit 1
fi


# ------------------------------------------------------------------------------
# 5. Prevent accidental overwrite
# ------------------------------------------------------------------------------

if [[ -e "${DB}" ]]; then
    echo "ERROR: GenomicsDB workspace already exists:" >&2
    echo "  ${DB}" >&2
    echo "Remove it explicitly before rerunning ${CHR}." >&2
    exit 1
fi

rm -rf "${TMP}"
mkdir -p "${TMP}"

rm -f "${SUCCESS_FILE}"


# ------------------------------------------------------------------------------
# 6. Job information
# ------------------------------------------------------------------------------

echo "=============================================================================="
echo "XYCM WGS - GenomicsDBImport"
echo "=============================================================================="
echo "Start time           : $(date --iso-8601=seconds)"
echo "Hostname             : $(hostname)"
echo "SLURM job ID         : ${SLURM_JOB_ID}"
echo "SLURM array task     : ${SLURM_ARRAY_TASK_ID}"
echo "Partition            : ${SLURM_JOB_PARTITION:-NA}"
echo "Chromosome           : ${CHR}"
echo "Samples              : ${N_SAMPLES}"
echo "Sample map           : ${SAMPLE_MAP}"
echo "Reference            : ${REF}"
echo "Working directory    : ${WORK_DIR}"
echo "Workspace            : ${DB}"
echo "Temporary directory  : ${TMP}"
echo "CPUs requested       : ${SLURM_CPUS_PER_TASK}"
echo "Memory requested     : ${SLURM_MEM_PER_NODE:-NA} MB"
echo "=============================================================================="
echo

gatk --version
echo


# ------------------------------------------------------------------------------
# 7. GenomicsDBImport
#
# --sample-name-map
#   Supplies all 449 gVCFs and assigns the unique technical sample names
#   generated in Step 2.
#
# --intervals
#   Restricts each array task to one primary chromosome.
#
# --batch-size 50
#   Imports all 449 samples in batches, reducing simultaneous open-file and
#   memory pressure.
#
# --reader-threads 2
#   Uses two VCF reader threads.
#
# --tmp-dir
#   Uses an independent temporary directory for each chromosome.
# ------------------------------------------------------------------------------

gatk \
    --java-options "-Xms8G -Xmx64G -XX:ParallelGCThreads=2 -Djava.io.tmpdir=${TMP}" \
    GenomicsDBImport \
    --reference "${REF}" \
    --sample-name-map "${SAMPLE_MAP}" \
    --genomicsdb-workspace-path "${DB}" \
    --intervals "${CHR}" \
    --batch-size 50 \
    --reader-threads 2 \
    --tmp-dir "${TMP}"


# ------------------------------------------------------------------------------
# 8. Validate GenomicsDB workspace
# ------------------------------------------------------------------------------

if [[ ! -d "${DB}" ]]; then
    echo "ERROR: GenomicsDB workspace was not created:" >&2
    echo "  ${DB}" >&2
    exit 1
fi

if [[ ! -s "${DB}/callset.json" ]]; then
    echo "ERROR: callset.json is missing or empty:" >&2
    echo "  ${DB}/callset.json" >&2
    exit 1
fi

if [[ ! -s "${DB}/vidmap.json" ]]; then
    echo "ERROR: vidmap.json is missing or empty:" >&2
    echo "  ${DB}/vidmap.json" >&2
    exit 1
fi


# ------------------------------------------------------------------------------
# 9. Write success marker
# ------------------------------------------------------------------------------

{
    echo "chromosome=${CHR}"
    echo "samples=${N_SAMPLES}"
    echo "workspace=${DB}"
    echo "reference=${REF}"
    echo "slurm_job_id=${SLURM_JOB_ID}"
    echo "slurm_array_task_id=${SLURM_ARRAY_TASK_ID}"
    echo "completed=$(date --iso-8601=seconds)"
} > "${SUCCESS_FILE}"


# ------------------------------------------------------------------------------
# 10. Remove temporary files after successful completion
# ------------------------------------------------------------------------------

rm -rf "${TMP}"


# ------------------------------------------------------------------------------
# 11. Final report
# ------------------------------------------------------------------------------

echo
echo "=============================================================================="
echo "SUCCESS: GenomicsDBImport completed"
echo "=============================================================================="
echo "Chromosome : ${CHR}"
echo "Samples    : ${N_SAMPLES}"
echo "Workspace  : ${DB}"
echo "Status     : ${SUCCESS_FILE}"
echo "End time   : $(date --iso-8601=seconds)"
echo "=============================================================================="

