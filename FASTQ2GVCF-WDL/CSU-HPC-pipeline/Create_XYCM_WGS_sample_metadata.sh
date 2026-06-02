#!/usr/bin/env bash
set -euo pipefail

############################################################
## Create XYCM-WGS sample metadata for CSU-HPC
##
## Purpose:
##   Scan WGS FASTQ directories, identify paired-end FASTQ files,
##   and generate sample metadata for WDL/Cromwell.
##
## Important:
##   This version does NOT restrict sample folders to MEL*/XY*/YBJ*.
##   It detects sample directories by the presence of *_1.fq.gz or
##   *_1.fastq.gz files, so Chinese-named folders such as 曾萍 and
##   罗新 will also be included.
##
## sample_name:
##   The sample folder name.
##
## sample_uid:
##   sample_name__fastq_prefix
##   This uniquely distinguishes multiple FASTQ pairs from the same
##   biological sample.
############################################################

out_tsv="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/XYCM_WGS_sample_metadata.tsv"
platform_name="DNBSEQ"

search_dirs=(
  "/public/home/hpc8301200407/F25A040010053_HOMkijwfR_20260327171920"
  "/nfs8301200407/F25A040010053-02_HOMrymthR_20260323110102"
  "/nfs8301200407/F25A040010053_HOMcuyxkR_20260323110101"
  "/nfs8301200407/F25A040010053_HOMkijwfR_20260323110101"
  "/nfs8301200407/F25A040010053_HOMudzgiR_20260323110101"
  "/nfs8301200407/F25A040010053_HOMyezpxR_20260323110102"
  "/nfs8301200407/XY_MEL_WGS/20251120"
  "/nfs8301200407/XY_MEL_WGS/20251130"
)

mkdir -p "$(dirname "${out_tsv}")"

echo -e "sample_uid\tsample_name\tbatch_folder\tsample_dir\tfq1\tfq2\tfastq_prefix\trun_id\tlane\tsequencing_center\tlibrary_name\tread_group_id\tplatform_unit\tplatform_name" > "${out_tsv}"

for base_dir in "${search_dirs[@]}"; do

    [[ -d "${base_dir}" ]] || {
        echo "WARNING: directory not found: ${base_dir}" >&2
        continue
    }

    find "${base_dir}" -type f \
        \( -name "*_1.fq.gz" -o -name "*_1.fastq.gz" \) \
        ! -name "._*" \
        | sort | while read -r fq1; do

        sample_dir="$(dirname "${fq1}")"
        sample_name="$(basename "${sample_dir}")"
        batch_folder="$(basename "$(dirname "${sample_dir}")")"

        if [[ "${fq1}" == *_1.fq.gz ]]; then
            fq2="${fq1%_1.fq.gz}_2.fq.gz"
            fq_base="$(basename "${fq1}")"
            fastq_prefix="${fq_base%_1.fq.gz}"
        else
            fq2="${fq1%_1.fastq.gz}_2.fastq.gz"
            fq_base="$(basename "${fq1}")"
            fastq_prefix="${fq_base%_1.fastq.gz}"
        fi

        [[ -f "${fq2}" ]] || {
            echo "WARNING: missing R2 for ${fq1}" >&2
            continue
        }

        IFS="_" read -r run_id lane sequencing_center library_name extra <<< "${fastq_prefix}"

        [[ -n "${run_id}" && -n "${lane}" && -n "${sequencing_center}" && -n "${library_name}" ]] || {
            echo "WARNING: cannot parse FASTQ prefix: ${fastq_prefix}" >&2
            continue
        }

        sample_uid="${sample_name}__${fastq_prefix}"
        read_group_id="${run_id}_${lane}_${library_name}"
        platform_unit="${run_id}.${lane}"

        echo -e "${sample_uid}\t${sample_name}\t${batch_folder}\t${sample_dir}\t${fq1}\t${fq2}\t${fastq_prefix}\t${run_id}\t${lane}\t${sequencing_center}\t${library_name}\t${read_group_id}\t${platform_unit}\t${platform_name}"

    done

done >> "${out_tsv}"

echo "Done: ${out_tsv}"
echo "Number of FASTQ pairs:"
tail -n +2 "${out_tsv}" | wc -l

echo "Checking duplicated sample_uid:"
cut -f1 "${out_tsv}" | tail -n +2 | sort | uniq -d