#!/usr/bin/env bash
#SBATCH --job-name=MarkDuplicatesSpark_test
#SBATCH --partition=partFAT2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --output=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.3.MarkDuplicatesSpark/logs/%x.%j.out
#SBATCH --error=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.3.MarkDuplicatesSpark/logs/%x.%j.err

set -euo pipefail

source /lustre/home/zhangsy/softwares/miniforge3/etc/profile.d/conda.sh
conda activate gatk_germline

echo "Using GATK:"
which gatk
gatk --version

echo "Using samtools:"
which samtools
samtools --version | head -n 1

input_bam="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.2.MergeBamAlignment/MEL100.E250058805_L01_WGS2510043608-2-8074.aligned.unsorted.bam"

out_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.3.MarkDuplicatesSpark"
log_dir="${out_dir}/logs"
time_dir="${log_dir}/time"
tmp_dir="${out_dir}/tmp"

mkdir -p "${out_dir}" "${log_dir}" "${time_dir}" "${tmp_dir}"

sample_prefix=$(basename "${input_bam}" .aligned.unsorted.bam)

output_bam="${out_dir}/${sample_prefix}.aligned.duplicates_marked.sorted.bam"
metrics_file="${out_dir}/${sample_prefix}.duplicate_metrics.txt"

gatk_log="${log_dir}/${sample_prefix}.MarkDuplicatesSpark.log"
time_log="${time_dir}/${sample_prefix}.time.log"

echo "===================================================="
echo "Step3: MarkDuplicatesSpark"
echo "Input BAM: ${input_bam}"
echo "Output BAM: ${output_bam}"
echo "Metrics: ${metrics_file}"
echo "Started: $(date)"
echo "===================================================="

[[ -f "${input_bam}" ]] || {
    echo "ERROR: missing input BAM: ${input_bam}" >&2
    exit 1
}

if [[ -f "${output_bam}" ]]; then
    echo "SKIP: ${output_bam} already exists"
    exit 0
fi

/usr/bin/time -v -o "${time_log}" \
gatk --java-options "-Xms8G -Djava.io.tmpdir=${tmp_dir}" \
    MarkDuplicatesSpark \
    -I "${input_bam}" \
    -O "${output_bam}" \
    -M "${metrics_file}" \
    --conf "spark.local.dir=${tmp_dir}" \
    --conf "spark.executor.cores=16" \
    --create-output-bam-index true \
    > "${gatk_log}" 2>&1

samtools quickcheck "${output_bam}"
samtools view -H "${output_bam}" | grep '^@HD'
samtools view -H "${output_bam}" | grep '^@RG'
samtools view -H "${output_bam}" | grep '^@PG'
samtools view "${output_bam}" | sed -n '1p' > /dev/null

echo "Completed: ${output_bam}"
echo "Finished: $(date)"
echo "Runtime/memory log: ${time_log}"
echo "GATK log: ${gatk_log}"
echo "Duplicate metrics: ${metrics_file}"