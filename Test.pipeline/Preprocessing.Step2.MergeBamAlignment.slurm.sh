#!/usr/bin/env bash
#SBATCH --job-name=MergeBamAlignment_test
#SBATCH --partition=partFAT2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --output=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.2.MergeBamAlignment/logs/%x.%j.out
#SBATCH --error=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.2.MergeBamAlignment/logs/%x.%j.err

# This script is to merge the original uBAM and the BWA/BWA-MEM2 aligned BAM using GATK's MergeBamAlignment tool, which will also add program records to the output BAM to document the BWA version and command line used for alignment.
set -euo pipefail

source /lustre/home/zhangsy/softwares/miniforge3/etc/profile.d/conda.sh
conda activate gatk_germline

echo "Using GATK:"
which gatk
gatk --version

echo "Using bwa-mem2:"
which bwa-mem2
bwa-mem2 version

echo "Using samtools:"
which samtools
samtools --version | head -n 1

############################################################
## Input files
############################################################

unmapped_bam="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.0.fq2ubam/MEL100.E250058805_L01_WGS2510043608-2-8074.unmapped.bam"

aligned_bam="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.1.SamToFastqAndBwaMem/MEL100.E250058805_L01_WGS2510043608-2-8074.unmerged.bam"

ref_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Resource.bundle/GATK.hg38"
ref_fasta="${ref_dir}/Homo_sapiens_assembly38.fasta"
ref_fai="${ref_dir}/Homo_sapiens_assembly38.fasta.fai"
ref_dict="${ref_dir}/Homo_sapiens_assembly38.dict"

############################################################
## Output paths
############################################################

out_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.2.MergeBamAlignment"
log_dir="${out_dir}/logs"
time_dir="${log_dir}/time"
tmp_dir="${out_dir}/tmp"

mkdir -p "${out_dir}" "${log_dir}" "${time_dir}" "${tmp_dir}"

sample_prefix=$(basename "${unmapped_bam}" .unmapped.bam)

output_bam="${out_dir}/${sample_prefix}.aligned.unsorted.bam"
gatk_log="${log_dir}/${sample_prefix}.MergeBamAlignment.log"
time_log="${time_dir}/${sample_prefix}.time.log"

############################################################
## BWA program record
############################################################

bwa_version=$(bwa-mem2 version 2>&1 | head -n 1 || true)

bwa_commandline="bwa-mem2 mem -K 100000000 -p -v 3 -t 16 -Y ${ref_fasta}"

echo "===================================================="
echo "Step2: MergeBamAlignment"
echo "Unmapped BAM: ${unmapped_bam}"
echo "Aligned BAM: ${aligned_bam}"
echo "Reference: ${ref_fasta}"
echo "Output BAM: ${output_bam}"
echo "BWA version: ${bwa_version}"
echo "BWA command line: ${bwa_commandline}"
echo "Started: $(date)"
echo "===================================================="

############################################################
## Sanity checks
############################################################

[[ -f "${unmapped_bam}" ]] || { echo "ERROR: missing uBAM: ${unmapped_bam}" >&2; exit 1; }
[[ -f "${aligned_bam}" ]] || { echo "ERROR: missing aligned BAM: ${aligned_bam}" >&2; exit 1; }

[[ -f "${ref_fasta}" ]] || { echo "ERROR: missing reference FASTA: ${ref_fasta}" >&2; exit 1; }
[[ -f "${ref_fai}" ]] || { echo "ERROR: missing reference FASTA index: ${ref_fai}" >&2; exit 1; }
[[ -f "${ref_dict}" ]] || { echo "ERROR: missing reference dictionary: ${ref_dict}" >&2; exit 1; }

if [[ -f "${output_bam}" ]]; then
    echo "SKIP: ${output_bam} already exists"
    exit 0
fi

############################################################
## Merge original uBAM and BWA/BWA-MEM2 aligned BAM
############################################################

/usr/bin/time -v -o "${time_log}" \
gatk --java-options "-Dsamjdk.compression_level=5 -Xms4G -Djava.io.tmpdir=${tmp_dir}" \
    MergeBamAlignment \
    --VALIDATION_STRINGENCY SILENT \
    --EXPECTED_ORIENTATIONS FR \
    --ATTRIBUTES_TO_RETAIN X0 \
    --ALIGNED_BAM "${aligned_bam}" \
    --UNMAPPED_BAM "${unmapped_bam}" \
    --OUTPUT "${output_bam}" \
    --REFERENCE_SEQUENCE "${ref_fasta}" \
    --PAIRED_RUN true \
    --SORT_ORDER "unsorted" \
    --IS_BISULFITE_SEQUENCE false \
    --ALIGNED_READS_ONLY false \
    --CLIP_ADAPTERS false \
    --MAX_RECORDS_IN_RAM 2000000 \
    --ADD_MATE_CIGAR true \
    --MAX_INSERTIONS_OR_DELETIONS -1 \
    --PRIMARY_ALIGNMENT_STRATEGY MostDistant \
    --PROGRAM_RECORD_ID "bwamem" \
    --PROGRAM_GROUP_VERSION "${bwa_version}" \
    --PROGRAM_GROUP_COMMAND_LINE "${bwa_commandline}" \
    --PROGRAM_GROUP_NAME "bwamem" \
    --UNMAPPED_READ_STRATEGY COPY_TO_TAG \
    --ALIGNER_PROPER_PAIR_FLAGS true \
    --UNMAP_CONTAMINANT_READS true \
    > "${gatk_log}" 2>&1

############################################################
## Validate output
############################################################

samtools quickcheck "${output_bam}"
samtools view -H "${output_bam}" | grep '^@RG'
samtools view -H "${output_bam}" | grep '^@PG'
samtools view "${output_bam}" | sed -n '1p' > /dev/null

echo "Completed: ${output_bam}"
echo "Finished: $(date)"
echo "Runtime/memory log: ${time_log}"
echo "GATK log: ${gatk_log}"