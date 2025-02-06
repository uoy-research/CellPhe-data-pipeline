#!/bin/bash
# Main script to run the entire workflow. Must be run from research0.
# Needs rclone setup with remotes CellPheGDrive, CellPheViking (might be able 
# to be setup automatically later)
#
# NB: This script is currently designed to be run for a single timelapse,
# i.e. one well and one imaging modality.
#
# Args:
#   - source: Google Drive folder ID
#   - experiment: Experiment name for the output, should be in the format
#   YYYY-mm-dd_experiment-name_microscope_cellline
#   - pattern: Any file matching pattern, i.e. "Brightfield-*.tiff"
#   - config: Config file providing pipeline parameters
GDRIVE_ID=${1}
EXPERIMENT=${2}
PATTERN=${3}
CONFIG=${4}
RESUME=${5:-default}
SITE=$(../tools/jq -r .folder_names.site $CONFIG)
IMAGE=$(../tools/jq -r .folder_names.image_type $CONFIG)
# TODO should add hash or something to make this unique
CONFIG_FN="config_${SITE}_${IMAGE}.json"
ml load tools/rclone

# Step 1: Transfer data and config to Viking
echo "Transferring data to Viking..."
rclone --config .rclone.config copy -v --include "*$PATTERN*.companion.ome*" --include "*$PATTERN*.tif" --include "*$PATTERN*.tiff" --include "*$PATTERN*.TIF" --include "*$PATTERN*.TIFF" --include "*$PATTERN*.jpg" --include "*$PATTERN*.jpeg" --include "*$PATTERN*.JPG" --include "*$PATTERN*.JPEG" --drive-root-folder-id $GDRIVE_ID GDrive: Viking:/mnt/scratch/projects/biol-imaging-2024/Experiments/$EXPERIMENT/raw/${SITE}_${IMAGE}
rclone --config .rclone.config copyto -v $CONFIG Viking:/mnt/scratch/projects/biol-imaging-2024/Experiments/$EXPERIMENT/$CONFIG_FN

# Step 2: Submit the job to process the data (waits until complete)
echo "Executing pipeline..."
NEXTFLOW_CMD="cd /mnt/scratch/projects/biol-imaging-2024/CellPhe-data-pipeline && ./process_dataset.sh $EXPERIMENT $CONFIG_FN $RESUME"
ssh viking "${NEXTFLOW_CMD}"

# Step 3: Transfer outputs to network share
echo "Transferring outputs to bioldata..."
rclone --config .rclone.config copy --no-update-modtime --exclude ".work/**" --exclude ".nextflow**" -v Viking:/mnt/scratch/projects/biol-imaging-2024/Experiments/$EXPERIMENT /shared/storage/bioldata/bl-cellphe/Experiments/$EXPERIMENT
