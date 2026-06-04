# CSU-HPC Pipeline

This folder contains the CSU-HPC-specific production files for the XYCM WGS
FASTQ-to-GVCF workflow. It uses the same core workflow steps as the portable
WDL in the parent directory, but the scripts here are configured for the
CSU-HPC environment, SLURM scheduler, Cromwell paths, reference bundle paths,
and XYCM WGS FASTQ locations.

These files are not intended to be portable without editing the absolute paths
and SLURM settings.

## Files

- `Create_XYCM_WGS_sample_metadata.sh`: scans configured FASTQ directories,
  detects paired-end FASTQs, and writes
  `/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/XYCM_WGS_sample_metadata.tsv`.
- `CSU-HPC-build_wdl_inputs.py`: validates the metadata and reference bundle,
  then writes one Cromwell input JSON per `sample_uid` plus
  `wdl_inputs_manifest.tsv`.
- `XYCM_Germline_GVCF.v1.0.wdl`: CSU-HPC production WDL. This version removes
  the prior upper memory bound and keeps the runtime resources configurable
  through the input JSONs.
- `CSU-HPC-submit.all_samples.cromwell.slurm.sh`: SLURM array wrapper for
  running Cromwell. It flattens final GVCF/TBI outputs, records status, and
  removes large intermediate BAM files after success.
- `CSU-HPC-submit.all_samples.cromwell.slurm.fixed.v2.0.sh`: updated SLURM
  wrapper with additional cleanup of execution GVCF/TBI copies after success.
  Use this as the preferred production submit script unless there is a reason
  to keep the older wrapper.
- `Submit_selected_to_idle_nodes.sh`: helper for submitting a selected manifest
  task range to truly idle `cpuQ` nodes only.

## Expected Environment

The scripts assume:

- SLURM partition `cpuQ`, QoS `cpuq`, and account `pi_XXX`.
- Conda environment `gatk_germline`.
- Cromwell jar at
  `/public/home/hpc8301200407/miniconda3/envs/gatk_germline/share/cromwell/cromwell.jar`.
- Working directory rooted at
  `/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL`.
- GATK hg38 reference bundle at
  `/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/Resource.bundle/GATK.hg38`.

Edit the paths in the scripts before using them on a different cluster or under
a different account.

## Metadata

Run:

```bash
bash Create_XYCM_WGS_sample_metadata.sh
```

The metadata script scans the configured FASTQ search directories and includes
any sample directory containing paired files matching `*_1.fq.gz` /
`*_2.fq.gz` or `*_1.fastq.gz` / `*_2.fastq.gz`.

The output TSV includes both portable WDL columns and CSU-HPC bookkeeping
columns:

```text
sample_uid
sample_name
batch_folder
sample_dir
fq1
fq2
fastq_prefix
run_id
lane
sequencing_center
library_name
read_group_id
platform_unit
platform_name
```

`sample_uid` is built as:

```text
sample_uid = sample_name + "__" + fastq_prefix
```

This allows multiple FASTQ pairs from the same biological sample to be tracked
separately.

## Build Cromwell Inputs

Run:

```bash
python CSU-HPC-build_wdl_inputs.py
```

By default this reads:

```text
/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/XYCM_WGS_sample_metadata.tsv
```

and writes input JSON files plus a manifest to:

```text
/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/inputs
```

The manifest columns are:

```text
sample_uid
sample_name
read_group_id
fq1
fq2
inputs_json
```

SLURM array task `1` maps to the first data row in this manifest.

## Run All Samples

Preferred submit script:

```bash
sbatch --array=1-<N> CSU-HPC-submit.all_samples.cromwell.slurm.fixed.v2.0.sh
```

Replace `<N>` with the number of rows in `wdl_inputs_manifest.tsv`, excluding
the header.

Outputs are written under:

```text
/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/final_outputs/<sample_uid>
```

Status files and the production status TSV are written under:

```text
/public/home/hpc8301200407/XYCM_WGS/Variant_Calling/WDL/runs/production
```

## Submit Selected Tasks To Idle Nodes

For targeted submission or resubmission:

```bash
bash Submit_selected_to_idle_nodes.sh <start_task> <end_task> [exclude_task_id]
```

The script:

- detects nodes whose state is exactly `idle` in partition `cpuQ`;
- previews task-to-node assignment;
- saves the assignment TSV;
- asks for `YES` before submitting one SLURM array task per selected node.

Example:

```bash
bash Submit_selected_to_idle_nodes.sh 20 40 31
```

This submits tasks 20 through 40, skipping task 31.
