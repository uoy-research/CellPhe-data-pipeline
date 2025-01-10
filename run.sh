#!/bin/bash
# Main script to run the entire workflow. Must be run from research0.
# Needs rclone setup with remotes CellPheGDrive, CellPheViking (might be able 
# to be setup automatically later)
#
# Args:
#   - source: Google Drive folder ID
#   - dataset: Dataset name for the output
#   - pattern: Any ile matching pattern, i.e. "Brightfield-*.tiff"
#   - TODO Anything else? Memory needed for Slurm jobs?
ml load tools/rclone

# Step 1: Transfer data to Viking
rclone copy -v --include "$3" --drive-root-folder-id $1 CellPheGDrive: CellPheViking:/mnt/scratch/projects/biol-imaging-2024/Datasets/$2/raw

# Step 2: Submit the job to process the data (waits until complete)
ssh viking "cd /mnt/scratch/projects/biol-imaging-2024/CellPhe-data-pipeline && ./process_dataset.sh $2"

# Step 3: Transfers the outputs to the network share (mounted locally on research0)
rclone copy -v CellPheViking:/mnt/scratch/projects/biol-imaging-2024/Datasets/$2 /shared/storage/bioldata/bl-cellphe/Datasets/$2
