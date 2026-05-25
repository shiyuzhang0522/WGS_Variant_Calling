# WGS Variant Calling

This repository contains a germline whole-genome sequencing (WGS) variant
calling workflow based on GATK Best Practices. The main workflow converts paired
FASTQ files into per-sample GVCFs using BWA-MEM2 alignment, duplicate marking,
base quality score recalibration, and GATK HaplotypeCaller in GVCF mode.

## Repository Layout

```text
.
+-- FASTQ2GVCF-WDL/
|   +-- XYCM_Germline_GVCF.wdl      # Production FASTQ-to-GVCF workflow
|   +-- build_wdl_inputs.py         # Builds per-sample Cromwell input JSONs
|   +-- metadata.example.tsv        # Minimal metadata template
|   +-- README.md                   # WDL-specific usage notes
+-- Test.pipeline/                  # SLURM scripts used to validate each step
+-- LICENSE
+-- README.md
```

## Workflow Summary

The **FASTQ2GVCF-WDL** workflow runs one sequencing unit at a time. Each unit is identified by:

```text
sample_uid = sample_name + "__" + read_group_id
```

Pipeline steps:

1. `FastqToSam`: convert paired FASTQs to unmapped BAM.
2. `SamToFastqAndBwaMem2`: align reads with BWA-MEM2.
3. `MergeBamAlignment`: merge aligned BAM with unmapped BAM metadata.
4. `MarkDuplicatesSpark`: mark duplicates and create duplicate metrics.
5. `SetNmMdAndUqTags`: refresh/fix NM, MD, and UQ tags before BQSR.
6. `BaseRecalibrator`: build the BQSR recalibration table.
7. `ApplyBQSR`: apply base quality score recalibration.
8. `HaplotypeCallerGVCF`: emit the final `.g.vcf.gz` and `.tbi`.

## Required Software

The workflow expects these tools to be available in the runtime environment:

- GATK 4
- BWA-MEM2
- samtools
- Python 3 with `pandas` for `FASTQ2GVCF-WDL/build_wdl_inputs.py`
- Cromwell or another WDL 1.0-compatible execution engine

The validation scripts in `Test.pipeline/` are written for SLURM and assume a
Conda environment named `gatk_germline`.

## Benchmark

The following benchmark was collected from one validation sample:

```text
MEL100.E250058805_L01_WGS2510043608-2-8074
```

These values are intended for cluster planning and rough runtime estimates.
Actual runtime and memory use will vary with sample coverage, FASTQ size,
filesystem performance, scheduler configuration, and available CPU resources.

| Step | Script / task | Purpose | Threads | Elapsed time | JVM total memory | Main output |
| --- | --- | --- | ---: | ---: | ---: | --- |
| 0 | `Step0.FastqToSam.test.slurm` | FASTQ to uBAM | 2 | 76 min | 889192448 bytes | `*.unmapped.bam` (43 GB) |
| 1 | `Step1.SamToFastqAndBwaMem.test.slurm.sh` | Map to reference | 16 | 130.33 min | 1224736768 bytes | `*.unmerged.bam` (59 GB) |
| 2 | `Preprocessing.Step2.MergeBamAlignment.test.sh` | Merge aligned BAM with uBAM metadata | 2 | 123.55 min | 4294967296 bytes | `*.aligned.unsorted.bam` (58 GB) |
| 3 | `Preprocessing.Step3.MarkDuplicatesSpark.test.sh` | Mark duplicates and sort BAM | 16 | 659.78 min | 8589934592 bytes | `*.aligned.duplicates_marked.sorted.bam` (35 GB) |
| 4 | `Step4.SetNmMdAndUqTags.test.sh` | Refresh NM, MD, and UQ tags | 2 | 80.93 min | 4294967296 bytes | `*.aligned.duplicates_marked.sorted.fixed.bam` (30 GB) |
| 5 | `Step5.BaseRecalibrator.test.sh` | Build BQSR recalibration table | 1 | 192.06 min | 4294967296 bytes | `*.recal_data.csv` |
| 6 | `Step6.ApplyBQSR.test.sh` | Apply BQSR to BAM | 2 | 211.37 min | 4294967296 bytes | `*.aligned.duplicates_marked.recalibrated.bam` (66 GB) |
| 7 | `VariantCalling.Step1.HaplotypeCaller.GVCF.test.sh` | Call variants in GVCF mode | 16 | 933.18 min | 42949672960 bytes | `*.g.vcf.gz` (5.3 GB) |

Overall per-sample runtime was approximately 40 hours, typically completing
within two days. The maximum observed JVM memory usage was ~40 GB during the
**HaplotypeCaller** step, which represented the primary computational
bottleneck of the pipeline.

## Reference Bundle

`FASTQ2GVCF-WDL/build_wdl_inputs.py` expects a GATK hg38 reference directory containing:

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

Each row should describe one read group. FASTQ paths should
be absolute paths or paths resolvable from the directory where
`build_wdl_inputs.py` is run.

See `FASTQ2GVCF-WDL/metadata.example.tsv` for a minimal template.

## Build WDL Inputs

From the repository root:

```bash
python FASTQ2GVCF-WDL/build_wdl_inputs.py \
  --metadata /path/to/XYCM_WGS_sample_metadata.tsv \
  --ref-dir /path/to/GATK.hg38 \
  --out-dir FASTQ2GVCF-WDL/inputs
```

This writes:

- one input JSON per `sample_uid`
- `FASTQ2GVCF-WDL/inputs/wdl_inputs_manifest.tsv`, a manifest listing generated JSON files

Common optional settings:

```bash
python FASTQ2GVCF-WDL/build_wdl_inputs.py \
  --metadata /path/to/metadata.tsv \
  --ref-dir /path/to/GATK.hg38 \
  --out-dir FASTQ2GVCF-WDL/inputs \
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
  FASTQ2GVCF-WDL/XYCM_Germline_GVCF.wdl \
  --inputs FASTQ2GVCF-WDL/inputs/<sample_uid>.inputs.json
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

## ⚠️ Platform-Specific Notes
This variant calling pipeline was validated using ~30× whole-genome sequencing
(WGS) data generated on the **BGI DNBSEQ-T7 platform**. When applying the
pipeline to data from other sequencing platforms (for example, Illumina),
certain parameters and filtering settings may require adjustment.

## 📬 Contact

For questions, suggestions, or bug reports, please open an issue in this
repository or contact:

shiyuzhang0522@gmail.com
