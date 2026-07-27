#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Joint Genotyping Pipeline
# Step 1. Inspect duplicated internal VCF sample IDs
# ==============================================================================

WORK_DIR="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/Joint_Genotyping"

MANIFEST="${WORK_DIR}/gvcf_manifest.tsv"
DUPLICATES="${WORK_DIR}/duplicated_vcf_sample_ids.txt"
OUT="${WORK_DIR}/duplicated_gvcf_records.tsv"

printf "sample_uid\tgvcf\tindex\tvcf_sample_id\n" > "${OUT}"

while IFS= read -r ID; do

    awk -F'\t' -v id="${ID}" '
        NR > 1 && $4 == id
    ' "${MANIFEST}" >> "${OUT}"

done < "${DUPLICATES}"

echo "============================================================"
echo "Duplicated gVCF records"
echo "============================================================"

column -t -s $'\t' "${OUT}"

echo
echo "Output: ${OUT}"

