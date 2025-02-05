#!/bin/bash
# Wrapper for the NextFlow job submission that sets the environment before running the job
# Args:
#   - 1: Dataset name
#   - 2: Config file
DATASET=${1}

ml load Python/3.11.5-GCCcore-13.2.0
ml load Nextflow/23.10.0
ml load Java/11.0.20
ml load Perl-bundle-CPAN/5.38.0-GCCcore-13.2.0
ml load LibTIFF/4.6.0-GCCcore-13.2.0
ml load ImageMagick/7.1.1-34-GCCcore-13.2.0
ml load Quarto/1.6.39-x86_64-linux
ml load R/4.4.1-gfbf-2023b
source /mnt/scratch/projects/biol-imaging-2024/venv/bin/activate
export CELLPOSE_LOCAL_MODELS_PATH=/mnt/scratch/projects/biol-imaging-2024/cellpose

CMD="srun --ntasks=1 --cpus-per-task 4 --mem=8G --time=120 nextflow run process_dataset.nf -work-dir ../Datasets/$DATASET/.work --dataset $DATASET -params-file ../Datasets/$DATASET/config.json"
eval $CMD
