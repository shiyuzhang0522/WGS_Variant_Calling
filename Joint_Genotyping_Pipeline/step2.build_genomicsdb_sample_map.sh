#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Joint Genotyping Pipeline
# Step 1. Build final GenomicsDB sample map
# ==============================================================================

WORK_DIR="/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/Joint_Genotyping"

MANIFEST="${WORK_DIR}/gvcf_manifest.tsv"
SAMPLE_MAP="${WORK_DIR}/genomicsdb.sample_map.tsv"
EXCLUDED="${WORK_DIR}/excluded_gvcfs.tsv"

EXPECTED_N=449

# Lower-depth duplicate of MEL214 to exclude
EXCLUDE_UID="MEL214__E250167005_L01_WH_WGS2512070644-1-8371"

# ------------------------------------------------------------------------------
# 1.1 Record excluded sample
# ------------------------------------------------------------------------------

printf "sample_uid\tgvcf\tvcf_sample_id\treason\n" > "${EXCLUDED}"

awk -F'\t' -v uid="${EXCLUDE_UID}" 'BEGIN{OFS="\t"}
    NR>1 && $1==uid {
        print $1,$2,$4,"lower-depth duplicate; higher-depth E250083226 retained"
    }
' "${MANIFEST}" >> "${EXCLUDED}"

# ------------------------------------------------------------------------------
# 1.2 Build final GenomicsDB sample map
#
# Format required by GenomicsDBImport:
# technical_sample_id<TAB>gVCF_path
#
# No header.
# ------------------------------------------------------------------------------

awk -F'\t' -v uid="${EXCLUDE_UID}" 'BEGIN{OFS="\t"}
    NR>1 && $1!=uid {
        print $1,$2
    }
' "${MANIFEST}" > "${SAMPLE_MAP}"

# ------------------------------------------------------------------------------
# 1.3 Sanity checks
# ------------------------------------------------------------------------------

N_ENTRIES=$(wc -l < "${SAMPLE_MAP}")
N_SAMPLE_IDS=$(cut -f1 "${SAMPLE_MAP}" | sort -u | wc -l)
N_GVCFS=$(cut -f2 "${SAMPLE_MAP}" | sort -u | wc -l)

N_DUP_SAMPLE_IDS=$(cut -f1 "${SAMPLE_MAP}" | sort | uniq -d | wc -l)
N_DUP_GVCFS=$(cut -f2 "${SAMPLE_MAP}" | sort | uniq -d | wc -l)

echo "============================================================"
echo "Step 1: GenomicsDB sample-map summary"
echo "============================================================"
echo "Input gVCFs             : 450"
echo "Excluded gVCFs          : 1"
echo "Final sample-map entries: ${N_ENTRIES}"
echo "Unique technical IDs    : ${N_SAMPLE_IDS}"
echo "Unique gVCF paths       : ${N_GVCFS}"
echo "Duplicated technical IDs: ${N_DUP_SAMPLE_IDS}"
echo "Duplicated gVCF paths   : ${N_DUP_GVCFS}"

echo
echo "Excluded record:"
column -t -s $'\t' "${EXCLUDED}"

echo
echo "Technical replicate pairs retained:"
for id in MEL100 MEL101 MEL102 MEL302 MEL306; do
    grep "^${id}__" "${SAMPLE_MAP}" || true
done

# ------------------------------------------------------------------------------
# 1.4 Confirm retained MEL214
# ------------------------------------------------------------------------------

echo
echo "MEL214 retained:"
grep '^MEL214__' "${SAMPLE_MAP}" || true

# ------------------------------------------------------------------------------
# 1.5 Final decision
# ------------------------------------------------------------------------------

if [[ "${N_ENTRIES}" -ne "${EXPECTED_N}" || \
      "${N_SAMPLE_IDS}" -ne "${EXPECTED_N}" || \
      "${N_GVCFS}" -ne "${EXPECTED_N}" || \
      "${N_DUP_SAMPLE_IDS}" -ne 0 || \
      "${N_DUP_GVCFS}" -ne 0 ]]; then

    echo
    echo "ERROR: GenomicsDB sample map failed sanity checks."
    exit 1
fi

echo
echo "SUCCESS: final GenomicsDB sample map contains ${EXPECTED_N} unique technical samples."
echo
echo "Sample map:"
echo "${SAMPLE_MAP}"

