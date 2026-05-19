#!/usr/bin/env bash
#SBATCH --job-name=fq2ubam_test
#SBATCH --partition=partFAT2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --output=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.0.fq2ubam/logs/%x.%j.out
#SBATCH --error=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.0.fq2ubam/logs/%x.%j.err

set -euo pipefail

############################################################
## Activate conda environment
############################################################

source /lustre/home/zhangsy/softwares/miniforge3/etc/profile.d/conda.sh
conda activate gatk_germline

echo "Using GATK:"
which gatk
gatk --version

echo "Using samtools:"
which samtools
samtools --version | head -n 1

############################################################
## Input / output paths
############################################################

metadata="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/XYCM_WGS_sample_metadata.tsv"

out_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.0.fq2ubam"

log_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.0.fq2ubam/logs"

time_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.0.fq2ubam/logs/time"

tmp_base="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.0.fq2ubam/tmp"

mkdir -p "${out_dir}" "${log_dir}" "${time_dir}" "${tmp_base}"

############################################################
## Test mode:
## Use the 1st data row in the metadata file
############################################################

line_num=2
line=$(sed -n "${line_num}p" "${metadata}")

IFS=$'\t' read -r \
    sample_name \
    batch_folder \
    sample_dir \
    fq1 \
    fq2 \
    fastq_prefix \
    run_id \
    lane \
    sequencing_center \
    library_name \
    read_group_id \
    platform_unit \
    platform_name <<< "${line}"

############################################################
## Output files
############################################################

out_bam="${out_dir}/${sample_name}.${read_group_id}.unmapped.bam"

gatk_log="${log_dir}/${sample_name}.${read_group_id}.FastqToSam.log"

time_log="${time_dir}/${sample_name}.${read_group_id}.time.log"

sample_tmp="${tmp_base}/${sample_name}.${read_group_id}"

mkdir -p "${sample_tmp}"

############################################################
## Print job info
############################################################

echo "===================================================="
echo "FASTQ -> uBAM test job"
echo "Metadata row: 1"
echo "Sample: ${sample_name}"
echo "Read group: ${read_group_id}"
echo "Library: ${library_name}"
echo "Platform unit: ${platform_unit}"
echo "Platform: ${platform_name}"
echo "Sequencing center: ${sequencing_center}"
echo "FASTQ1: ${fq1}"
echo "FASTQ2: ${fq2}"
echo "Output: ${out_bam}"
echo "Started: $(date)"
echo "===================================================="

############################################################
## Skip existing output
############################################################

if [[ -f "${out_bam}" ]]; then
    echo "SKIP: ${out_bam} already exists"
    exit 0
fi

############################################################
## Sanity check FASTQs
############################################################

[[ -f "${fq1}" ]] || {
    echo "ERROR: missing R1 FASTQ: ${fq1}" >&2
    exit 1
}

[[ -f "${fq2}" ]] || {
    echo "ERROR: missing R2 FASTQ: ${fq2}" >&2
    exit 1
}

############################################################
## Convert FASTQ -> uBAM
############################################################

/usr/bin/time -v -o "${time_log}" \
gatk FastqToSam \
    FASTQ="${fq1}" \
    FASTQ2="${fq2}" \
    OUTPUT="${out_bam}" \
    READ_GROUP_NAME="${read_group_id}" \
    SAMPLE_NAME="${sample_name}" \
    LIBRARY_NAME="${library_name}" \
    PLATFORM_UNIT="${platform_unit}" \
    PLATFORM="${platform_name}" \
    SEQUENCING_CENTER="${sequencing_center}" \
    CREATE_MD5_FILE=true \
    TMP_DIR="${sample_tmp}" \
    > "${gatk_log}" 2>&1

############################################################
## Validate uBAM
############################################################

samtools quickcheck "${out_bam}"

############################################################
## Clean temporary files
############################################################

rm -rf "${sample_tmp}"

############################################################
## Finish
############################################################

echo "Completed: ${out_bam}"
echo "Finished: $(date)"
echo "Runtime/memory log: ${time_log}"
echo "GATK log: ${gatk_log}"