#!/bin/bash
# Wrapper for the NextFlow job submission that sets the environment before running the job
# Args:
#   - 1: Dataset name
#   - 2: CellPose model
DATASET=${1}
MODEL=${2:-default}

ml load Python/3.11.5-GCCcore-13.2.0
ml load Nextflow/23.10.0
ml load Java/11.0.20
ml load Perl-bundle-CPAN/5.38.0-GCCcore-13.2.0
ml load LibTIFF/4.6.0-GCCcore-13.2.0
ml load ImageMagick/7.1.1-34-GCCcore-13.2.0
source /mnt/scratch/projects/biol-imaging-2024/venv/bin/activate

CMD="srun --ntasks=1 --cpus-per-task 4 --mem=8G --time=120 nextflow run process_dataset.nf -work-dir ../Datasets/$DATASET/.work --dataset $DATASET"
if [ $MODEL != 'default' ]
then
    CMD="${CMD} --cellpose_model ${MODEL}"
fi
eval $CMD
