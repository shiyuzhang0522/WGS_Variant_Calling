#!/usr/bin/env bash
#SBATCH --job-name=ApplyBQSR_test
#SBATCH --partition=partFAT2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --output=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.6.ApplyBQSR/logs/%x.%j.out
#SBATCH --error=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.6.ApplyBQSR/logs/%x.%j.err

set -euo pipefail

source /lustre/home/zhangsy/softwares/miniforge3/etc/profile.d/conda.sh
conda activate gatk_germline

echo "Using GATK:"
which gatk
gatk --version

echo "Using samtools:"
which samtools
samtools --version | head -n 1

input_bam="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.4.SetNmMdAndUqTags/MEL100.E250058805_L01_WGS2510043608-2-8074.aligned.duplicates_marked.sorted.fixed.bam"
input_bam_index="${input_bam%.bam}.bai"

recal_report="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.5.BaseRecalibrator/MEL100.E250058805_L01_WGS2510043608-2-8074.recal_data.csv"

ref_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Resource.bundle/GATK.hg38"
ref_fasta="${ref_dir}/Homo_sapiens_assembly38.fasta"
ref_fai="${ref_dir}/Homo_sapiens_assembly38.fasta.fai"
ref_dict="${ref_dir}/Homo_sapiens_assembly38.dict"

out_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.6.ApplyBQSR"
log_dir="${out_dir}/logs"
time_dir="${log_dir}/time"
tmp_dir="${out_dir}/tmp"

mkdir -p "${out_dir}" "${log_dir}" "${time_dir}" "${tmp_dir}"

sample_prefix=$(basename "${input_bam}" .aligned.duplicates_marked.sorted.fixed.bam)

output_bam="${out_dir}/${sample_prefix}.aligned.duplicates_marked.recalibrated.bam"
gatk_log="${log_dir}/${sample_prefix}.ApplyBQSR.log"
time_log="${time_dir}/${sample_prefix}.time.log"

echo "===================================================="
echo "Step6: ApplyBQSR"
echo "Input BAM: ${input_bam}"
echo "Recalibration report: ${recal_report}"
echo "Reference: ${ref_fasta}"
echo "Output BAM: ${output_bam}"
echo "Started: $(date)"
echo "===================================================="

[[ -f "${input_bam}" ]] || { echo "ERROR: missing input BAM: ${input_bam}" >&2; exit 1; }
[[ -f "${input_bam_index}" ]] || { echo "ERROR: missing BAM index: ${input_bam_index}" >&2; exit 1; }

[[ -f "${recal_report}" ]] || { echo "ERROR: missing recalibration report: ${recal_report}" >&2; exit 1; }

[[ -f "${ref_fasta}" ]] || { echo "ERROR: missing reference FASTA: ${ref_fasta}" >&2; exit 1; }
[[ -f "${ref_fai}" ]] || { echo "ERROR: missing reference FASTA index: ${ref_fai}" >&2; exit 1; }
[[ -f "${ref_dict}" ]] || { echo "ERROR: missing reference dictionary: ${ref_dict}" >&2; exit 1; }

if [[ -f "${output_bam}" ]]; then
    echo "SKIP: ${output_bam} already exists"
    exit 0
fi

/usr/bin/time -v -o "${time_log}" \
gatk --java-options "-Xms4G -Djava.io.tmpdir=${tmp_dir}" \
    ApplyBQSR \
    -R "${ref_fasta}" \
    -I "${input_bam}" \
    -O "${output_bam}" \
    -bqsr "${recal_report}" \
    --add-output-sam-program-record \
    --create-output-bam-md5 \
    > "${gatk_log}" 2>&1

samtools quickcheck "${output_bam}"
samtools view -H "${output_bam}" | grep '^@HD'
samtools view -H "${output_bam}" | grep 'SO:coordinate'
samtools view -H "${output_bam}" | grep '^@RG'
samtools view -H "${output_bam}" | grep '^@PG'
samtools view "${output_bam}" | sed -n '1p' > /dev/null

echo "Completed: ${output_bam}"
echo "Finished: $(date)"
echo "Runtime/memory log: ${time_log}"
echo "GATK log: ${gatk_log}"