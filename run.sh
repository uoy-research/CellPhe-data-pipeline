#!/bin/bash
# Main script to run the entire workflow. Must be run from research0.
# Needs rclone setup with remotes CellPheGDrive, CellPheViking (might be able 
# to be setup automatically later)
#
# NB: This script is currently designed to be run for a single timelapse,
# i.e. one well and one imaging modality.
#
# Args:
#   - 1: source: Google Drive folder ID
#   YYYY-mm-dd_experiment-name_microscope_cellline
#   - 2: pattern: Any file matching pattern, i.e. "Brightfield-*.tiff"
#   - 3: config: Config file providing pipeline parameters. Must be saved in the configs sub-directory of an Experiment
#   - 4: (OPTIONAL): -resume if intending to resume
GDRIVE_ID=${1}
PATTERN=${2}
CONFIG=${3}
RESUME=${4:-default}

# Validate the provided config file
EXPERIMENT="$(basename $(dirname $(dirname ${CONFIG})))"
CONFIG_DIR="$(basename $(dirname ${CONFIG}))"
EXPERIMENT_DIR="$(basename $(dirname $(dirname $(dirname ${CONFIG}))))"
BASENAME="$(basename ${CONFIG})"
EXTENSION="${BASENAME##*.}"
if [[ $CONFIG_DIR != "configs" || $EXPERIMENT_DIR != "Experiments" || $EXTENSION != "json" ]]; then
    echo "Config must be a .json file residing in a 'configs' sub-directory of an Experiment."
    exit 1
fi

# Prepare paths
EXPERIMENT_PATH_VIKING="/mnt/scratch/projects/biol-imaging-2024/Experiments/$EXPERIMENT"
EXPERIMENT_PATH_RESEARCH0="/shared/storage/bioldata/bl-cellphe/Experiments/$EXPERIMENT"
CONFIG_PATH_VIKING="$EXPERIMENT_PATH_VIKING/configs/$BASENAME"
SITE=$(../tools/jq -r .folder_names.site $CONFIG)
IMAGE=$(../tools/jq -r .folder_names.image_type $CONFIG)
RAW_DATA_DIR="$EXPERIMENT_PATH_VIKING/raw/${SITE}_${IMAGE}"

ml load tools/rclone

# Step 1: Transfer data and config to Viking
echo "Transferring data to Viking..."
rclone --config .rclone.config copy -v --include "*$PATTERN*.companion.ome*" --include "*$PATTERN*.tif" --include "*$PATTERN*.tiff" --include "*$PATTERN*.TIF" --include "*$PATTERN*.TIFF" --include "*$PATTERN*.jpg" --include "*$PATTERN*.jpeg" --include "*$PATTERN*.JPG" --include "*$PATTERN*.JPEG" --drive-root-folder-id $GDRIVE_ID GDrive: Viking:$RAW_DATA_DIR
rclone --config .rclone.config copyto -v $CONFIG Viking:$CONFIG_PATH_VIKING

# Step 2: Submit the job to process the data (waits until complete)
echo "Executing pipeline..."
NEXTFLOW_CMD="cd /mnt/scratch/projects/biol-imaging-2024/CellPhe-data-pipeline && ./process_dataset.sh $CONFIG_PATH_VIKING $RESUME"
ssh viking "${NEXTFLOW_CMD}"

# Step 3: Transfer outputs to network share
echo "Transferring outputs to bioldata..."
rclone --config .rclone.config copy --no-update-modtime --exclude ".work/**" --exclude ".nextflow**" -v Viking:$EXPERIMENT_PATH_VIKING $EXPERIMENT_PATH_RESEARCH0
