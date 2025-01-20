#!/bin/bash
# Wrapper for the NextFlow job submission that sets the environment before running the job
# Args:
#   - 1: Dataset name
ml load Python/3.11.5-GCCcore-13.2.0
ml load Nextflow/23.10.0
ml load Java/11.0.20
ml load Perl-bundle-CPAN/5.38.0-GCCcore-13.2.0
ml load LibTIFF/4.6.0-GCCcore-13.2.0
source /mnt/scratch/projects/biol-imaging-2024/venv/bin/activate
nextflow run process_dataset.nf --dataset $1
