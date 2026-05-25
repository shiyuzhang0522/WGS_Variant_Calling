# SLURM Validation Scripts

This directory contains step-by-step SLURM scripts used to validate the GATK
Best Practices commands before they were converted into the WDL workflow.

These scripts are useful as command references, but they are not fully portable:
they contain cluster-specific partitions, Conda paths, sample paths, reference
paths, and output directories.

## Step Order

1. `Preprocessing.0.fq2uBam.slurm`
2. `Preprocessing.Step1.SamToFastqAndBwaMem.slurm`
3. `Preprocessing.Step2.MergeBamAlignment.slurm.sh`
4. `Preprocessing.Step3.MarkDuplicatesSpark.slurm.sh`
5. `Preprocessing.Step4.SetNmMdAndUqTags.sh`
6. `Preprocessing.Step5.BaseRecalibrator.slurm.sh`
7. `Preprocessing.Step6.ApplyBQSR.slurm.sh`
8. `VariantCalling.Step1.HaplotypeCaller.GVCF.slurm.sh`

## Recommended Use

Use `WDL/XYCM_Germline_GVCF.wdl` for production or repeated runs. Use these
SLURM scripts when you need to inspect, debug, or manually rerun one pipeline
step with the original validated command structure.

Before submitting a script on a different system, update:

- `#SBATCH --partition`
- `#SBATCH --output` and `#SBATCH --error`
- Conda activation path and environment name
- input, output, metadata, and reference paths
- CPU and memory settings

See the root `README.md` for runtime, memory, and output-size benchmarks from
the validation sample.
