#!/usr/bin/env bash
#SBATCH --job-name=SamToFastqAndBwaMem_test
#SBATCH --partition=partFAT2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --output=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.1.SamToFastqAndBwaMem/logs/%x.%j.out
#SBATCH --error=/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.1.SamToFastqAndBwaMem/logs/%x.%j.err

set -euo pipefail

############################################################
## Activate conda environment
############################################################

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
## Input / output paths
############################################################

input_bam="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.0.fq2ubam/MEL100.E250058805_L01_WGS2510043608-2-8074.unmapped.bam"

ref_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Resource.bundle/GATK.hg38"

ref_fasta="${ref_dir}/Homo_sapiens_assembly38.fasta"

ref_fai="${ref_dir}/Homo_sapiens_assembly38.fasta.fai"
ref_dict="${ref_dir}/Homo_sapiens_assembly38.dict"

ref_alt="${ref_dir}/Homo_sapiens_assembly38.fasta.64.alt"
ref_sa="${ref_dir}/Homo_sapiens_assembly38.fasta.64.sa"
ref_ann="${ref_dir}/Homo_sapiens_assembly38.fasta.64.ann"
ref_bwt="${ref_dir}/Homo_sapiens_assembly38.fasta.64.bwt"
ref_pac="${ref_dir}/Homo_sapiens_assembly38.fasta.64.pac"
ref_amb="${ref_dir}/Homo_sapiens_assembly38.fasta.64.amb"

out_dir="/lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Tests_260519/Preprocessing.1.SamToFastqAndBwaMem"

log_dir="${out_dir}/logs"

time_dir="${log_dir}/time"

tmp_dir="${out_dir}/tmp"

mkdir -p "${out_dir}" "${log_dir}" "${time_dir}" "${tmp_dir}"

############################################################
## Output files
############################################################

sample_prefix=$(basename "${input_bam}" .unmapped.bam)

output_bam="${out_dir}/${sample_prefix}.unmerged.bam"

bwa_stderr_log="${log_dir}/${sample_prefix}.bwa-mem2.stderr.log"

pipeline_log="${log_dir}/${sample_prefix}.pipeline.log"

time_log="${time_dir}/${sample_prefix}.time.log"

############################################################
## Print job info
############################################################

echo "===================================================="
echo "Step1: SamToFastqAndBwaMem"
echo "Input uBAM: ${input_bam}"
echo "Reference: ${ref_fasta}"
echo "Output BAM: ${output_bam}"
echo "Started: $(date)"
echo "===================================================="

############################################################
## Sanity checks
############################################################

[[ -f "${input_bam}" ]] || {
    echo "ERROR: missing input BAM: ${input_bam}" >&2
    exit 1
}

[[ -f "${ref_fasta}" ]] || {
    echo "ERROR: missing reference FASTA: ${ref_fasta}" >&2
    exit 1
}

[[ -f "${ref_fai}" ]] || {
    echo "ERROR: missing reference FASTA index: ${ref_fai}" >&2
    exit 1
}

[[ -f "${ref_dict}" ]] || {
    echo "ERROR: missing reference dictionary: ${ref_dict}" >&2
    exit 1
}

[[ -f "${ref_alt}" ]] || {
    echo "ERROR: missing bwa-mem2 ALT file: ${ref_alt}" >&2
    exit 1
}

[[ -f "${ref_sa}" ]] || {
    echo "ERROR: missing bwa-mem2 SA index: ${ref_sa}" >&2
    exit 1
}

[[ -f "${ref_ann}" ]] || {
    echo "ERROR: missing bwa-mem2 ANN index: ${ref_ann}" >&2
    exit 1
}

[[ -f "${ref_bwt}" ]] || {
    echo "ERROR: missing bwa-mem2 BWT index: ${ref_bwt}" >&2
    exit 1
}

[[ -f "${ref_pac}" ]] || {
    echo "ERROR: missing bwa-mem2 PAC index: ${ref_pac}" >&2
    exit 1
}

[[ -f "${ref_amb}" ]] || {
    echo "ERROR: missing bwa-mem2 AMB index: ${ref_amb}" >&2
    exit 1
}

############################################################
## Skip existing output
############################################################

if [[ -f "${output_bam}" ]]; then
    echo "SKIP: ${output_bam} already exists"
    exit 0
fi

############################################################
## uBAM -> FASTQ -> BWA-MEM2 -> BAM
##
## This follows the Broad WDL logic:
##   SamToFastq INTERLEAVE=true
##   pipe to bwa/bwa-mem2 mem -p
##   pipe to samtools view
############################################################

/usr/bin/time -v -o "${time_log}" \
bash -c "
set -o pipefail

gatk SamToFastq \
    INPUT='${input_bam}' \
    FASTQ=/dev/stdout \
    INTERLEAVE=true \
    NON_PF=true \
| \
bwa-mem2 mem \
    -K 100000000 \
    -p \
    -v 3 \
    -t 16 \
    -Y \
    '${ref_fasta}' \
    /dev/stdin \
    2> '${bwa_stderr_log}' \
| \
samtools view \
    -1 \
    -o '${output_bam}' \
    -
" > "${pipeline_log}" 2>&1

############################################################
## Validate aligned BAM
############################################################

samtools quickcheck "${output_bam}"

samtools view -H "${output_bam}" | grep '^@SQ'

samtools view "${output_bam}" | sed -n '1p' > /dev/null

############################################################
## Finish
############################################################

echo "Completed: ${output_bam}"
echo "Finished: $(date)"
echo "Runtime/memory log: ${time_log}"
echo "Pipeline log: ${pipeline_log}"
echo "BWA-MEM2 stderr log: ${bwa_stderr_log}"