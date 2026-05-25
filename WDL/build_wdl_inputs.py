#!/usr/bin/env python3

###############################################################################
# build_wdl_inputs.py
#
# PURPOSE
# -------
# Generate per-sample WDL input JSON files for the
# XYCM germline whole-genome sequencing (WGS) FASTQ-to-GVCF pipeline.
#
# OVERVIEW
# --------
# This script:
#
#   1. Reads the master sample metadata table:
#        XYCM_WGS_sample_metadata.tsv
#
#   2. Validates:
#        - FASTQ files
#        - reference bundle files
#        - BWA-MEM2 index files
#        - known-sites resources for BQSR
#
#   3. Builds one input JSON per sequencing unit (sample_uid),
#      where:
#
#        sample_uid = sample_name + "__" + read_group_id
#
#      Example:
#        MEL100__E250058805_L01_WGS2510043608-2-8074
#
#   4. Generates a manifest table summarizing all WDL input JSONs.
#
#
# DESIGN PRINCIPLES
# -----------------
# - Reproducible
# - Robust
# - Per-RG/sample-unit granularity
# - Compatible with Cromwell/WDL execution
# - Aligned with Broad GATK germline best practices
# - Suitable for large-scale production WGS processing
#
#
# OUTPUTS
# -------
# Per-sample JSON:
#
#   WDL/inputs/<sample_uid>.inputs.json
#
# Manifest:
#
#   WDL/inputs/wdl_inputs_manifest.tsv
#
#
# EXAMPLE
# -------
# python build_wdl_inputs.py \
#   --metadata XYCM_WGS_sample_metadata.tsv \
#   --ref-dir /path/to/GATK.hg38 \
#   --out-dir WDL/inputs
#
###############################################################################

import argparse
import json
import os
import re
from pathlib import Path

import pandas as pd


def sanitize_id(x: str) -> str:
    x = str(x).strip()
    x = re.sub(r"[^A-Za-z0-9_.-]+", "_", x)
    return x


def require_file(path: str, label: str) -> str:
    if not path:
        raise ValueError(f"Missing path for {label}")
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Missing {label}: {path}")
    return os.path.abspath(path)


def main():
    parser = argparse.ArgumentParser(
        description="Build per-sample WDL input JSONs for XYCM germline FASTQ-to-GVCF workflow."
    )

    parser.add_argument(
        "--metadata",
        required=True,
        help="Input metadata TSV, e.g. XYCM_WGS_sample_metadata.tsv",
    )
    parser.add_argument(
        "--out-dir",
        default="WDL/inputs",
        help="Output directory for per-sample JSON files",
    )

    parser.add_argument(
        "--ref-dir",
        required=True,
        help="GATK hg38 reference bundle directory",
    )

    parser.add_argument(
        "--workflow-name",
        default="XYCM_Germline_GVCF",
        help="Workflow name used as WDL input prefix",
    )

    parser.add_argument("--align-threads", type=int, default=16)
    parser.add_argument("--markdup-threads", type=int, default=16)
    parser.add_argument("--haplotypecaller-threads", type=int, default=16)

    parser.add_argument("--fastq-to-sam-mem-gb", type=int, default=4)
    parser.add_argument("--align-mem-gb", type=int, default=14)
    parser.add_argument("--merge-mem-gb", type=int, default=4)
    parser.add_argument("--markdup-mem-gb", type=int, default=16)
    parser.add_argument("--fixtags-mem-gb", type=int, default=16)
    parser.add_argument("--bqsr-mem-gb", type=int, default=8)
    parser.add_argument("--apply-bqsr-mem-gb", type=int, default=8)
    parser.add_argument("--haplotypecaller-mem-gb", type=int, default=40)

    parser.add_argument("--gatk-path", default="gatk")
    parser.add_argument("--bwa-mem2-path", default="bwa-mem2")
    parser.add_argument("--samtools-path", default="samtools")
    parser.add_argument("--compression-level", type=int, default=5)

    args = parser.parse_args()

    metadata = Path(args.metadata).resolve()
    out_dir = Path(args.out_dir).resolve()
    ref_dir = Path(args.ref_dir).resolve()

    out_dir.mkdir(parents=True, exist_ok=True)

    if not metadata.is_file():
        raise FileNotFoundError(f"Missing metadata TSV: {metadata}")
    if not ref_dir.is_dir():
        raise FileNotFoundError(f"Missing reference directory: {ref_dir}")

    ref_fasta = ref_dir / "Homo_sapiens_assembly38.fasta"

    resources = {
        "ref_fasta": ref_fasta,
        "ref_fasta_index": ref_dir / "Homo_sapiens_assembly38.fasta.fai",
        "ref_dict": ref_dir / "Homo_sapiens_assembly38.dict",

        "ref_0123": Path(str(ref_fasta) + ".0123"),
        "ref_amb": Path(str(ref_fasta) + ".amb"),
        "ref_ann": Path(str(ref_fasta) + ".ann"),
        "ref_bwt2bit64": Path(str(ref_fasta) + ".bwt.2bit.64"),
        "ref_pac": Path(str(ref_fasta) + ".pac"),

        "dbsnp_vcf": ref_dir / "Homo_sapiens_assembly38.dbsnp138.vcf",
        "dbsnp_vcf_index": ref_dir / "Homo_sapiens_assembly38.dbsnp138.vcf.idx",

        "mills_vcf": ref_dir / "Mills_and_1000G_gold_standard.indels.hg38.vcf.gz",
        "mills_vcf_index": ref_dir / "Mills_and_1000G_gold_standard.indels.hg38.vcf.gz.tbi",

        "known_indels_vcf": ref_dir / "Homo_sapiens_assembly38.known_indels.vcf.gz",
        "known_indels_vcf_index": ref_dir / "Homo_sapiens_assembly38.known_indels.vcf.gz.tbi",
    }

    for label, path in resources.items():
        require_file(str(path), label)

    df = pd.read_csv(metadata, sep="\t", dtype=str).fillna("")

    required_cols = [
        "sample_name",
        "fq1",
        "fq2",
        "read_group_id",
        "library_name",
        "platform_unit",
        "platform_name",
        "sequencing_center",
    ]

    missing_cols = [c for c in required_cols if c not in df.columns]
    if missing_cols:
        raise ValueError(f"Metadata is missing columns: {missing_cols}")

    manifest_rows = []

    for _, row in df.iterrows():
        sample_name = sanitize_id(row["sample_name"])
        read_group_id = sanitize_id(row["read_group_id"])
        sample_uid = sanitize_id(f"{sample_name}__{read_group_id}")

        fq1 = require_file(row["fq1"], f"{sample_uid} fq1")
        fq2 = require_file(row["fq2"], f"{sample_uid} fq2")

        prefix = args.workflow_name

        inputs = {
            f"{prefix}.sample_name": sample_name,
            f"{prefix}.sample_uid": sample_uid,
            f"{prefix}.fq1": fq1,
            f"{prefix}.fq2": fq2,
            f"{prefix}.read_group_id": row["read_group_id"],
            f"{prefix}.library_name": row["library_name"],
            f"{prefix}.platform_unit": row["platform_unit"],
            f"{prefix}.platform_name": row["platform_name"],
            f"{prefix}.sequencing_center": row["sequencing_center"],

            f"{prefix}.gatk_path": args.gatk_path,
            f"{prefix}.bwa_mem2_path": args.bwa_mem2_path,
            f"{prefix}.samtools_path": args.samtools_path,

            f"{prefix}.compression_level": args.compression_level,
            f"{prefix}.align_threads": args.align_threads,
            f"{prefix}.markdup_threads": args.markdup_threads,
            f"{prefix}.haplotypecaller_threads": args.haplotypecaller_threads,

            f"{prefix}.fastq_to_sam_mem_gb": args.fastq_to_sam_mem_gb,
            f"{prefix}.align_mem_gb": args.align_mem_gb,
            f"{prefix}.merge_mem_gb": args.merge_mem_gb,
            f"{prefix}.markdup_mem_gb": args.markdup_mem_gb,
            f"{prefix}.fixtags_mem_gb": args.fixtags_mem_gb,
            f"{prefix}.bqsr_mem_gb": args.bqsr_mem_gb,
            f"{prefix}.apply_bqsr_mem_gb": args.apply_bqsr_mem_gb,
            f"{prefix}.haplotypecaller_mem_gb": args.haplotypecaller_mem_gb,
        }

        for label, path in resources.items():
            inputs[f"{prefix}.{label}"] = str(path.resolve())

        json_path = out_dir / f"{sample_uid}.inputs.json"

        with open(json_path, "w") as f:
            json.dump(inputs, f, indent=2, sort_keys=True)
            f.write("\n")

        manifest_rows.append(
            {
                "sample_name": sample_name,
                "read_group_id": row["read_group_id"],
                "sample_uid": sample_uid,
                "fq1": fq1,
                "fq2": fq2,
                "inputs_json": str(json_path),
            }
        )

    manifest_path = out_dir / "wdl_inputs_manifest.tsv"
    pd.DataFrame(manifest_rows).to_csv(manifest_path, sep="\t", index=False)

    print(f"Generated {len(manifest_rows)} input JSON files")
    print(f"Manifest: {manifest_path}")


if __name__ == "__main__":
    main()

# Usage
# python build_wdl_inputs.py \
#  --metadata XYCM_WGS_sample_metadata.tsv \
#  --ref-dir /lustre/home/zhangsy/Project_XYCM_WGS/0.Variant.Calling/Resource.bundle/GATK.hg38 \
#  --out-dir WDL/inputs