#!/bin/bash
# Main script to run the entire workflow. Must be run from research0.
# Needs rclone setup with remotes CellPheGDrive, CellPheViking (might be able 
# to be setup automatically later)
#
# Args:
#   - source: Google Drive folder ID
#   - dataset: Dataset name for the output
#   - pattern: Any file matching pattern, i.e. "Brightfield-*.tiff"
GDRIVE_ID=${1}
DATASET=${2}
PATTERN=${3}
CONFIG=${4}
ml load tools/rclone

# Step 1: Transfer data and config to Viking
rclone --config .rclone.config copy -v --include "*$PATTERN*.companion.ome*" --include "*$PATTERN*.tif" --include "*$PATTERN*.tiff" --include "*$PATTERN*.TIF" --include "*$PATTERN*.TIFF" --include "*$PATTERN*.jpg" --include "*$PATTERN*.jpeg" --include "*$PATTERN*.JPG" --include "*$PATTERN*.JPEG" --drive-root-folder-id $GDRIVE_ID GDrive: Viking:/mnt/scratch/projects/biol-imaging-2024/Datasets/$DATASET/raw
rclone --config .rclone.config copyto -v $CONFIG Viking:/mnt/scratch/projects/biol-imaging-2024/Datasets/$DATASET/config.json

# Step 2: Submit the job to process the data (waits until complete)
NEXTFLOW_CMD="cd /mnt/scratch/projects/biol-imaging-2024/CellPhe-data-pipeline && ./process_dataset.sh $DATASET"
ssh viking "${NEXTFLOW_CMD}"

# Step 3: Only transfer outputs to network share on job success
if [ $? -eq 0 ]; then
    rclone --config .rclone.config copy --exclude ".work/**" -v Viking:/mnt/scratch/projects/biol-imaging-2024/Datasets/$DATASET /shared/storage/bioldata/bl-cellphe/Datasets/$DATASET
fi
