#!/usr/bin/env bash
#SBATCH --job-name=BaseRecalibrator_test
#SBATCH --partition=partFAT2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --output=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.5.BaseRecalibrator/logs/%x.%j.out
#SBATCH --error=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.5.BaseRecalibrator/logs/%x.%j.err

set -euo pipefail

source /lustre/home/zhangsy/softwares/miniforge3/etc/profile.d/conda.sh
conda activate gatk_germline

echo "Using GATK:"
which gatk
gatk --version

############################################################
## Input BAM
############################################################

input_bam="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.4.SetNmMdAndUqTags/MEL100.E250058805_L01_WGS2510043608-2-8074.aligned.duplicates_marked.sorted.fixed.bam"
input_bam_index="${input_bam%.bam}.bai"

############################################################
## Reference and known sites
############################################################

ref_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Resource.bundle/GATK.hg38"

ref_fasta="${ref_dir}/Homo_sapiens_assembly38.fasta"
ref_fai="${ref_dir}/Homo_sapiens_assembly38.fasta.fai"
ref_dict="${ref_dir}/Homo_sapiens_assembly38.dict"

dbsnp_vcf="${ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf"
dbsnp_idx="${ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf.idx"

mills_vcf="${ref_dir}/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz"
mills_tbi="${ref_dir}/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz.tbi"

known_indels_vcf="${ref_dir}/Homo_sapiens_assembly38.known_indels.vcf.gz"
known_indels_tbi="${ref_dir}/Homo_sapiens_assembly38.known_indels.vcf.gz.tbi"

############################################################
## Output paths
############################################################

out_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.5.BaseRecalibrator"
log_dir="${out_dir}/logs"
time_dir="${log_dir}/time"
tmp_dir="${out_dir}/tmp"

mkdir -p "${out_dir}" "${log_dir}" "${time_dir}" "${tmp_dir}"

sample_prefix=$(basename "${input_bam}" .aligned.duplicates_marked.sorted.fixed.bam)

recal_report="${out_dir}/${sample_prefix}.recal_data.csv"
gatk_log="${log_dir}/${sample_prefix}.BaseRecalibrator.log"
time_log="${time_dir}/${sample_prefix}.time.log"

echo "===================================================="
echo "Step5: BaseRecalibrator"
echo "Input BAM: ${input_bam}"
echo "Reference: ${ref_fasta}"
echo "dbSNP: ${dbsnp_vcf}"
echo "Known indels 1: ${mills_vcf}"
echo "Known indels 2: ${known_indels_vcf}"
echo "Output report: ${recal_report}"
echo "Started: $(date)"
echo "===================================================="

############################################################
## Sanity checks
############################################################

[[ -f "${input_bam}" ]] || { echo "ERROR: missing input BAM: ${input_bam}" >&2; exit 1; }
[[ -f "${input_bam_index}" ]] || { echo "ERROR: missing BAM index: ${input_bam_index}" >&2; exit 1; }

[[ -f "${ref_fasta}" ]] || { echo "ERROR: missing reference FASTA: ${ref_fasta}" >&2; exit 1; }
[[ -f "${ref_fai}" ]] || { echo "ERROR: missing reference FASTA index: ${ref_fai}" >&2; exit 1; }
[[ -f "${ref_dict}" ]] || { echo "ERROR: missing reference dictionary: ${ref_dict}" >&2; exit 1; }

[[ -f "${dbsnp_vcf}" ]] || { echo "ERROR: missing dbSNP VCF: ${dbsnp_vcf}" >&2; exit 1; }
[[ -f "${dbsnp_idx}" ]] || { echo "ERROR: missing dbSNP index: ${dbsnp_idx}" >&2; exit 1; }

[[ -f "${mills_vcf}" ]] || { echo "ERROR: missing Mills indel VCF: ${mills_vcf}" >&2; exit 1; }
[[ -f "${mills_tbi}" ]] || { echo "ERROR: missing Mills indel index: ${mills_tbi}" >&2; exit 1; }

[[ -f "${known_indels_vcf}" ]] || { echo "ERROR: missing known indels VCF: ${known_indels_vcf}" >&2; exit 1; }
[[ -f "${known_indels_tbi}" ]] || { echo "ERROR: missing known indels index: ${known_indels_tbi}" >&2; exit 1; }

if [[ -f "${recal_report}" ]]; then
    echo "SKIP: ${recal_report} already exists"
    exit 0
fi

############################################################
## Generate BQSR recalibration model
############################################################

/usr/bin/time -v -o "${time_log}" \
gatk --java-options "-Xms4G -Djava.io.tmpdir=${tmp_dir}" \
    BaseRecalibrator \
    -R "${ref_fasta}" \
    -I "${input_bam}" \
    -O "${recal_report}" \
    --known-sites "${dbsnp_vcf}" \
    --known-sites "${mills_vcf}" \
    --known-sites "${known_indels_vcf}" \
    > "${gatk_log}" 2>&1

############################################################
## Validate output
############################################################

[[ -s "${recal_report}" ]] || {
    echo "ERROR: recalibration report was not created or is empty: ${recal_report}" >&2
    exit 1
}

head -n 20 "${recal_report}"

echo "Completed: ${recal_report}"
echo "Finished: $(date)"
echo "Runtime/memory log: ${time_log}"
echo "GATK log: ${gatk_log}"