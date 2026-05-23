#!/usr/bin/env bash
#SBATCH --job-name=HaplotypeCaller_test
#SBATCH --partition=partFAT2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --output=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/VariantCalling.1.HaplotypeCaller/logs/%x.%j.out
#SBATCH --error=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/VariantCalling.1.HaplotypeCaller/logs/%x.%j.err

set -euo pipefail

source /lustre/home/zhangsy/softwares/miniforge3/etc/profile.d/conda.sh
conda activate gatk_germline

echo "Using GATK:"
which gatk
gatk --version

input_bam="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.6.ApplyBQSR/MEL100.E250058805_L01_WGS2510043608-2-8074.aligned.duplicates_marked.recalibrated.bam"
input_bam_index="${input_bam%.bam}.bai"

ref_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Resource.bundle/GATK.hg38"
ref_fasta="${ref_dir}/Homo_sapiens_assembly38.fasta"
ref_fai="${ref_dir}/Homo_sapiens_assembly38.fasta.fai"
ref_dict="${ref_dir}/Homo_sapiens_assembly38.dict"

out_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/VariantCalling.1.HaplotypeCaller"
log_dir="${out_dir}/logs"
time_dir="${log_dir}/time"
tmp_dir="${out_dir}/tmp"

mkdir -p "${out_dir}" "${log_dir}" "${time_dir}" "${tmp_dir}"

sample_prefix=$(basename "${input_bam}" .aligned.duplicates_marked.recalibrated.bam)

output_gvcf="${out_dir}/${sample_prefix}.g.vcf.gz"
gatk_log="${log_dir}/${sample_prefix}.HaplotypeCaller.log"
time_log="${time_dir}/${sample_prefix}.time.log"

echo "===================================================="
echo "VariantCalling.Step1: HaplotypeCaller GVCF mode"
echo "Input BAM: ${input_bam}"
echo "Reference: ${ref_fasta}"
echo "Output GVCF: ${output_gvcf}"
echo "Started: $(date)"
echo "===================================================="

[[ -f "${input_bam}" ]] || { echo "ERROR: missing input BAM: ${input_bam}" >&2; exit 1; }
[[ -f "${input_bam_index}" ]] || { echo "ERROR: missing BAM index: ${input_bam_index}" >&2; exit 1; }

[[ -f "${ref_fasta}" ]] || { echo "ERROR: missing reference FASTA: ${ref_fasta}" >&2; exit 1; }
[[ -f "${ref_fai}" ]] || { echo "ERROR: missing reference FASTA index: ${ref_fai}" >&2; exit 1; }
[[ -f "${ref_dict}" ]] || { echo "ERROR: missing reference dictionary: ${ref_dict}" >&2; exit 1; }

if [[ -f "${output_gvcf}" ]]; then
    echo "SKIP: ${output_gvcf} already exists"
    exit 0
fi

/usr/bin/time -v -o "${time_log}" \
gatk --java-options "-Xms40G -Xmx40G -XX:ParallelGCThreads=2 -Djava.io.tmpdir=${tmp_dir}" \
    HaplotypeCaller \
    -R "${ref_fasta}" \
    -I "${input_bam}" \
    -O "${output_gvcf}" \
    -ERC GVCF \
    --native-pair-hmm-threads 16 \
    > "${gatk_log}" 2>&1

[[ -s "${output_gvcf}" ]] || { echo "ERROR: output GVCF not created: ${output_gvcf}" >&2; exit 1; }
[[ -s "${output_gvcf}.tbi" ]] || { echo "ERROR: output GVCF index not created: ${output_gvcf}.tbi" >&2; exit 1; }

echo "Completed: ${output_gvcf}"
echo "Finished: $(date)"
echo "Runtime/memory log: ${time_log}"
echo "GATK log: ${gatk_log}"