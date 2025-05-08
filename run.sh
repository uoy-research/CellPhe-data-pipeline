#!/bin/bash
# Main script to run the entire workflow. Must be run from research0.
# Needs rclone setup with remotes CellPheViking and CellPheGDrive (if accessing datasets on Google Drive).
#
# NB: This script is currently designed to be run for a single timelapse,
# i.e. one well and one imaging modality.
#
# Args:
#   - 1: -b (optional). Whether to interpret the source as a bioldata folder. If not present assumes it is a GoogleDrive ID
#   - 2: source: Google Drive folder ID OR path to bioldata folder
#   - 3: pattern: Any file matching pattern, i.e. "Brightfield-*.tiff"
#   - 4: config: Config file providing pipeline parameters. Must be saved in the configs sub-directory of an Experiment

print_usage() {
    printf "Usage: run.sh GDRIVEID B2 /path/to/config.json OR run.sh -b /path/to/folder/on/bioldata B2 /path/to/config.json"
}

bioldata=false

while getopts 'b' flag; do
  case "${flag}" in
    b) bioldata=true ;;
    *) print_usage
       exit 1 ;;
  esac
done
SOURCE=${@:$OPTIND:1}
PATTERN=${@:$OPTIND+1:1}
CONFIG=${@:$OPTIND+2:1}

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
OUTBOUND_CMD="rclone --config .rclone.config copy --stats-log-level NOTICE --include \"*$PATTERN*.companion.ome*\" --include \"*$PATTERN*.tif\" --include \"*$PATTERN*.tiff\" --include \"*$PATTERN*.TIF\" --include \"*$PATTERN*.TIFF\" --include \"*$PATTERN*.jpg\" --include \"*$PATTERN*.jpeg\" --include \"*$PATTERN*.JPG\" --include \"*$PATTERN*.JPEG\""

# Add source folder
if [[ $bioldata = true ]]
then
    OUTBOUND_CMD="$OUTBOUND_CMD \"$SOURCE\""
else
    OUTBOUND_CMD="$OUTBOUND_CMD --drive-root-folder-id $SOURCE GDrive:"
fi

# Destination is always the same
OUTBOUND_CMD="$OUTBOUND_CMD Viking:$RAW_DATA_DIR"

# Copy data to viking
echo "Transferring data to Viking..."
eval $OUTBOUND_CMD
# Also copy config file
rclone --config .rclone.config copyto -v $CONFIG Viking:$CONFIG_PATH_VIKING

# Step 2: Submit the job to process the data (waits until complete)
echo "Executing pipeline..."
NEXTFLOW_CMD="cd /mnt/scratch/projects/biol-imaging-2024/CellPhe-data-pipeline && ./process_dataset.sh $CONFIG_PATH_VIKING -resume"
ssh viking "${NEXTFLOW_CMD}"

# Step 3: Transfer outputs to network share
echo "Transferring outputs to bioldata..."
rclone --config .rclone.config copy --stats-log-level NOTICE --no-update-modtime --exclude ".work/**" --exclude ".nextflow**" --exclude ".launch/**" Viking:$EXPERIMENT_PATH_VIKING $EXPERIMENT_PATH_RESEARCH0
