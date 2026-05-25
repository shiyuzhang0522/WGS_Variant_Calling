# WGS Variant Calling

This repository contains a germline whole-genome sequencing (WGS) variant
calling workflow based on GATK Best Practices. The main workflow converts paired
FASTQ files into per-sample GVCFs using BWA-MEM2 alignment, duplicate marking,
base quality score recalibration, and GATK HaplotypeCaller in GVCF mode.

## Repository Layout

```text
.
+-- WDL/
|   +-- XYCM_Germline_GVCF.wdl      # Production FASTQ-to-GVCF workflow
|   +-- build_wdl_inputs.py         # Builds per-sample Cromwell input JSONs
+-- Test.pipeline/                  # SLURM scripts used to validate each step
+-- LICENSE
+-- README.md
```

## Workflow Summary

The WDL workflow runs one sequencing unit at a time. Each unit is identified by:

```text
sample_uid = sample_name + "__" + read_group_id
```

Pipeline steps:

1. `FastqToSam`: convert paired FASTQs to unmapped BAM.
2. `SamToFastqAndBwaMem2`: align reads with BWA-MEM2.
3. `MergeBamAlignment`: merge aligned BAM with unmapped BAM metadata.
4. `MarkDuplicatesSpark`: mark duplicates and create duplicate metrics.
5. `SetNmMdAndUqTags`: refresh NM, MD, and UQ tags before BQSR.
6. `BaseRecalibrator`: build the BQSR recalibration table.
7. `ApplyBQSR`: apply base quality score recalibration.
8. `HaplotypeCallerGVCF`: emit the final `.g.vcf.gz` and `.tbi`.

## Required Software

The workflow expects these tools to be available in the runtime environment:

- GATK 4
- BWA-MEM2
- samtools
- Python 3 with `pandas` for `WDL/build_wdl_inputs.py`
- Cromwell or another WDL 1.0-compatible execution engine

The validation scripts in `Test.pipeline/` are written for SLURM and assume a
Conda environment named `gatk_germline`.

## Reference Bundle

`WDL/build_wdl_inputs.py` expects a GATK hg38 reference directory containing:

```text
Homo_sapiens_assembly38.fasta
Homo_sapiens_assembly38.fasta.fai
Homo_sapiens_assembly38.dict
Homo_sapiens_assembly38.fasta.0123
Homo_sapiens_assembly38.fasta.amb
Homo_sapiens_assembly38.fasta.ann
Homo_sapiens_assembly38.fasta.bwt.2bit.64
Homo_sapiens_assembly38.fasta.pac
Homo_sapiens_assembly38.dbsnp138.vcf
Homo_sapiens_assembly38.dbsnp138.vcf.idx
Mills_and_1000G_gold_standard.indels.hg38.vcf.gz
Mills_and_1000G_gold_standard.indels.hg38.vcf.gz.tbi
Homo_sapiens_assembly38.known_indels.vcf.gz
Homo_sapiens_assembly38.known_indels.vcf.gz.tbi
```

Build the BWA-MEM2 index with:

```bash
bwa-mem2 index Homo_sapiens_assembly38.fasta
```

## Metadata TSV

The input metadata file must be tab-delimited and include these columns:

```text
sample_name
fq1
fq2
read_group_id
library_name
platform_unit
platform_name
sequencing_center
```

Each row should describe one read group or sequencing unit. FASTQ paths should
be absolute paths or paths resolvable from the directory where
`build_wdl_inputs.py` is run.

See `WDL/metadata.example.tsv` for a minimal template.

## Build WDL Inputs

From the repository root:

```bash
python WDL/build_wdl_inputs.py \
  --metadata /path/to/XYCM_WGS_sample_metadata.tsv \
  --ref-dir /path/to/GATK.hg38 \
  --out-dir WDL/inputs
```

This writes:

- one input JSON per `sample_uid`
- `WDL/inputs/wdl_inputs_manifest.tsv`, a manifest listing generated JSON files

Common optional settings:

```bash
python WDL/build_wdl_inputs.py \
  --metadata /path/to/metadata.tsv \
  --ref-dir /path/to/GATK.hg38 \
  --out-dir WDL/inputs \
  --align-threads 16 \
  --markdup-threads 16 \
  --haplotypecaller-threads 16 \
  --gatk-path gatk \
  --bwa-mem2-path bwa-mem2 \
  --samtools-path samtools
```

## Run the WDL

Example Cromwell command:

```bash
java -jar cromwell.jar run \
  WDL/XYCM_Germline_GVCF.wdl \
  --inputs WDL/inputs/<sample_uid>.inputs.json
```

Final outputs include:

- `<sample_uid>.g.vcf.gz`
- `<sample_uid>.g.vcf.gz.tbi`
- duplicate metrics
- BQSR recalibration report
- per-step GATK logs and `/usr/bin/time -v` logs

## Validation SLURM Scripts

`Test.pipeline/` contains step-by-step SLURM scripts that were used to validate
the commands before the WDL was assembled. These scripts contain site-specific
absolute paths and are intended as command references, not portable production
entry points.

Use the WDL workflow for routine execution, and use the SLURM scripts when you
need to inspect or rerun a single validated command by hand.