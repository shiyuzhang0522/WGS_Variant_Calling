# WDL Workflow

This directory contains the portable workflow and the helper script used to
generate Cromwell input JSON files.

## Files

- `XYCM_Germline_GVCF.wdl`: end-to-end FASTQ-to-GVCF germline WGS workflow.
- `build_wdl_inputs.py`: validates metadata and reference resources, then writes
  one WDL input JSON per `sample_uid`.

## Workflow Inputs

The WDL expects sample metadata, paired FASTQ files, reference FASTA files,
BWA-MEM2 index files, and known-sites resources for BQSR. The easiest way to
prepare these inputs is to run:

```bash
python WDL/build_wdl_inputs.py \
  --metadata /path/to/metadata.tsv \
  --ref-dir /path/to/GATK.hg38 \
  --out-dir WDL/inputs
```

## Metadata Columns

Required metadata columns:

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

Each metadata row becomes one workflow input JSON. The generated `sample_uid`
combines the sample name and read-group ID:

```text
sample_uid = sample_name + "__" + read_group_id
```

## Outputs

The workflow emits a GVCF, GVCF index, duplicate metrics, BQSR report, and
per-step logs for each `sample_uid`.