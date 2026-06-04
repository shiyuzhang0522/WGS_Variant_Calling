# FASTQ-to-GVCF WDL Workflow

This directory contains the portable workflow and the helper script used to
generate Cromwell input JSON files.

## Files

- `XYCM_Germline_GVCF.wdl`: end-to-end FASTQ-to-GVCF germline WGS workflow.
- `build_wdl_inputs.py`: validates metadata and reference resources, then writes
  one WDL input JSON per `sample_uid`.
- `metadata.example.tsv`: minimal tab-delimited metadata template.
- `CSU-HPC-pipeline/`: CSU-HPC-specific production deployment with its own WDL,
  metadata script, Cromwell input builder, and SLURM wrappers.

Use `XYCM_Germline_GVCF.wdl` and `build_wdl_inputs.py` for portable or new-site
workflow setup. Use `CSU-HPC-pipeline/` for the established CSU-HPC production
configuration.

## Workflow Inputs

The WDL expects sample metadata, paired FASTQ files, reference FASTA files,
BWA-MEM2 index files, and known-sites resources for BQSR. The easiest way to
prepare these inputs is to run:

```bash
python FASTQ2GVCF-WDL/build_wdl_inputs.py \
  --metadata /path/to/metadata.tsv \
  --ref-dir /path/to/GATK.hg38 \
  --out-dir FASTQ2GVCF-WDL/inputs
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

## CSU-HPC Production Files

The `CSU-HPC-pipeline/` folder contains the cluster-specific production version
used on CSU-HPC. It includes:

- `Create_XYCM_WGS_sample_metadata.sh` for discovering XYCM WGS FASTQ pairs and
  writing a metadata TSV.
- `CSU-HPC-build_wdl_inputs.py` for generating Cromwell input JSONs with
  CSU-HPC default paths.
- `XYCM_Germline_GVCF.v1.0.wdl`, the CSU-HPC production WDL.
- SLURM wrappers for running all samples or selected manifest tasks.

See `CSU-HPC-pipeline/README.md` for the recommended CSU-HPC run order.
