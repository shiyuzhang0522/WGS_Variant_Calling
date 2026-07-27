#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Joint Genotyping Pipeline
# Step 0. Sanity check of 450 HaplotypeCaller gVCF outputs
# ==============================================================================

FINAL_DIR="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/final_outputs"
OUT_DIR="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/Joint_Genotyping"
EXPECTED_N=450

mkdir -p "${OUT_DIR}"

REPORT="${OUT_DIR}/gvcf_sanity_check.tsv"
MANIFEST="${OUT_DIR}/gvcf_manifest.tsv"
PROBLEMS="${OUT_DIR}/gvcf_sanity_check.problems.tsv"

# ------------------------------------------------------------------------------
# 0.0 Environment check
# ------------------------------------------------------------------------------

command -v bcftools >/dev/null 2>&1 || {
    echo "ERROR: bcftools is not available."
    echo "Please activate bcf_env before running this script."
    exit 1
}

echo "bcftools: $(command -v bcftools)"
bcftools --version | head -1
echo

# ------------------------------------------------------------------------------
# Initialize output files
# ------------------------------------------------------------------------------

printf "sample_uid\tgvcf\tindex\tvcf_sample_id\tgvcf_size_bytes\tstatus\n" > "${REPORT}"
printf "sample_uid\tgvcf\tindex\tvcf_sample_id\n" > "${MANIFEST}"
printf "sample_uid\tproblem\n" > "${PROBLEMS}"

echo "============================================================"
echo "Step 0: gVCF sanity check"
echo "Input directory : ${FINAL_DIR}"
echo "Expected gVCFs  : ${EXPECTED_N}"
echo "============================================================"

# ------------------------------------------------------------------------------
# 0.1 Count directories, gVCFs and indexes
# ------------------------------------------------------------------------------

N_DIR=$(find "${FINAL_DIR}" -mindepth 1 -maxdepth 1 -type d | wc -l)
N_GVCF=$(find "${FINAL_DIR}" -mindepth 2 -maxdepth 2 -type f -name "*.g.vcf.gz" | wc -l)
N_TBI=$(find "${FINAL_DIR}" -mindepth 2 -maxdepth 2 -type f -name "*.g.vcf.gz.tbi" | wc -l)

echo "Output directories : ${N_DIR}"
echo "gVCFs              : ${N_GVCF}"
echo "gVCF indexes       : ${N_TBI}"
echo

# ------------------------------------------------------------------------------
# 0.2 Check each output directory
# ------------------------------------------------------------------------------

while IFS= read -r SAMPLE_DIR; do

    SAMPLE_UID=$(basename "${SAMPLE_DIR}")

    mapfile -t GVCFS < <(
        find "${SAMPLE_DIR}" -maxdepth 1 -type f -name "*.g.vcf.gz" | sort
    )

    # Exactly one gVCF should exist in each sample directory
    if [[ ${#GVCFS[@]} -ne 1 ]]; then
        printf "%s\tExpected exactly 1 gVCF; found %d\n" \
            "${SAMPLE_UID}" "${#GVCFS[@]}" >> "${PROBLEMS}"
        continue
    fi

    GVCF="${GVCFS[0]}"
    TBI="${GVCF}.tbi"
    STATUS="PASS"
    VCF_SAMPLE="NA"

    # Check gVCF existence and size
    if [[ ! -s "${GVCF}" ]]; then
        printf "%s\tgVCF missing or empty\n" \
            "${SAMPLE_UID}" >> "${PROBLEMS}"
        STATUS="FAIL"
    fi

    # Check index existence and size
    if [[ ! -s "${TBI}" ]]; then
        printf "%s\tTBI missing or empty\n" \
            "${SAMPLE_UID}" >> "${PROBLEMS}"
        STATUS="FAIL"
    fi

    if [[ "${STATUS}" == "PASS" ]]; then

        # Check that VCF header can be read
        if ! bcftools view -h "${GVCF}" >/dev/null 2>&1; then
            printf "%s\tCannot read gVCF header\n" \
                "${SAMPLE_UID}" >> "${PROBLEMS}"
            STATUS="FAIL"
        fi

        # Extract internal VCF sample ID
        if [[ "${STATUS}" == "PASS" ]]; then
            mapfile -t SAMPLE_IDS < <(
                bcftools query -l "${GVCF}" 2>/dev/null
            )

            if [[ ${#SAMPLE_IDS[@]} -ne 1 ]]; then
                printf "%s\tExpected exactly 1 VCF sample; found %d\n" \
                    "${SAMPLE_UID}" "${#SAMPLE_IDS[@]}" >> "${PROBLEMS}"
                STATUS="FAIL"
            else
                VCF_SAMPLE="${SAMPLE_IDS[0]}"
            fi
        fi

        # Check that tabix index is readable
        if [[ "${STATUS}" == "PASS" ]]; then
            if ! bcftools index -n "${GVCF}" >/dev/null 2>&1; then
                printf "%s\tCannot read gVCF index\n" \
                    "${SAMPLE_UID}" >> "${PROBLEMS}"
                STATUS="FAIL"
            fi
        fi
    fi

    SIZE=$(stat -c%s "${GVCF}" 2>/dev/null || echo 0)

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
        "${SAMPLE_UID}" \
        "${GVCF}" \
        "${TBI}" \
        "${VCF_SAMPLE}" \
        "${SIZE}" \
        "${STATUS}" >> "${REPORT}"

    if [[ "${STATUS}" == "PASS" ]]; then
        printf "%s\t%s\t%s\t%s\n" \
            "${SAMPLE_UID}" \
            "${GVCF}" \
            "${TBI}" \
            "${VCF_SAMPLE}" >> "${MANIFEST}"
    fi

done < <(
    find "${FINAL_DIR}" -mindepth 1 -maxdepth 1 -type d | sort
)

# ------------------------------------------------------------------------------
# 0.3 Summary
# ------------------------------------------------------------------------------

N_PASS=$(awk -F'\t' 'NR>1 && $6=="PASS" {n++} END {print n+0}' "${REPORT}")
N_FAIL=$(awk -F'\t' 'NR>1 && $6=="FAIL" {n++} END {print n+0}' "${REPORT}")
N_PROBLEM=$(awk 'NR>1 {n++} END {print n+0}' "${PROBLEMS}")

echo
echo "============================================================"
echo "Sanity-check summary"
echo "============================================================"
echo "Expected       : ${EXPECTED_N}"
echo "Directories    : ${N_DIR}"
echo "gVCFs          : ${N_GVCF}"
echo "Indexes        : ${N_TBI}"
echo "PASS           : ${N_PASS}"
echo "FAIL           : ${N_FAIL}"
echo "Problems       : ${N_PROBLEM}"

# ------------------------------------------------------------------------------
# 0.4 Check duplicated internal VCF sample IDs
# ------------------------------------------------------------------------------

DUPLICATES="${OUT_DIR}/duplicated_vcf_sample_ids.txt"

awk -F'\t' 'NR>1 {print $4}' "${MANIFEST}" \
    | sort \
    | uniq -d \
    > "${DUPLICATES}"

echo
echo "Duplicated internal VCF sample IDs:"

if [[ -s "${DUPLICATES}" ]]; then
    cat "${DUPLICATES}"
else
    echo "None"
fi

echo
echo "Report     : ${REPORT}"
echo "Manifest   : ${MANIFEST}"
echo "Problems   : ${PROBLEMS}"
echo "Duplicates : ${DUPLICATES}"

# ------------------------------------------------------------------------------
# 0.5 Final decision
# ------------------------------------------------------------------------------

if [[ "${N_DIR}" -ne "${EXPECTED_N}" || \
      "${N_GVCF}" -ne "${EXPECTED_N}" || \
      "${N_TBI}" -ne "${EXPECTED_N}" || \
      "${N_PASS}" -ne "${EXPECTED_N}" ]]; then

    echo
    echo "ERROR: gVCF sanity check did not pass for all ${EXPECTED_N} samples."
    exit 1
fi

echo
echo "SUCCESS: all ${EXPECTED_N} gVCFs passed the basic sanity check."

