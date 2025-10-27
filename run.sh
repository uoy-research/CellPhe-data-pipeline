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
EXPERIMENT_PATH_VIKING_SCRATCH="/mnt/scratch/projects/biol-imaging-2024/Experiments/$EXPERIMENT"
EXPERIMENT_PATH_VIKING_LONGSHIP="/mnt/longship/projects/biol-imaging-2024/Experiments/$EXPERIMENT"
EXPERIMENT_PATH_RESEARCH0_STORAGE="/shared/storage/bioldata/bl-cellphe/Experiments/$EXPERIMENT"
EXPERIMENT_PATH_RESEARCH0_LONGSHIP="/shared/longship/projects/biol-imaging-2024/Experiments/$EXPERIMENT"
CONFIG_PATH_VIKING="$EXPERIMENT_PATH_VIKING_LONGSHIP/configs/$BASENAME"
CONFIG_PATH_RESEARCH0="$EXPERIMENT_PATH_RESEARCH0_LONGSHIP/configs/$BASENAME"
SITE=$(../tools/jq -r .folder_names.site $CONFIG)
IMAGE=$(../tools/jq -r .folder_names.image_type $CONFIG)
RAW_DATA_DIR="$EXPERIMENT_PATH_RESEARCH0_LONGSHIP/raw/${SITE}_${IMAGE}"

ml load tools/rclone

# Step 1: Transfer data and config to Viking
OUTBOUND_CMD="rclone --config .rclone.config copy --stats-log-level NOTICE"

# Add source folder and including patterns. NB: Bioldata sources *only* contain the timelapse images so we don't need to provide a pattern
if [[ $bioldata = true ]]
then
    INCLUDES=""
    SOURCE_CMD="\"$SOURCE\""
else
    INCLUDES="--include \"*$PATTERN*.companion.ome*\" --include \"*$PATTERN*.tif\" --include \"*$PATTERN*.tiff\" --include \"*$PATTERN*.TIF\" --include \"*$PATTERN*.TIFF\" --include \"*$PATTERN*.jpg\" --include \"*$PATTERN*.jpeg\" --include \"*$PATTERN*.JPG\" --include \"*$PATTERN*.JPEG\""
    SOURCE_CMD="--drive-root-folder-id $SOURCE GDrive:"
fi
OUTBOUND_CMD="$OUTBOUND_CMD $INCLUDES $SOURCE_CMD"

# Destination is always the same
OUTBOUND_CMD="$OUTBOUND_CMD $RAW_DATA_DIR"

# Copy data to viking
echo "Transferring data to Viking..."
eval $OUTBOUND_CMD
# Also copy config file
rclone --config .rclone.config copyto -v $CONFIG $CONFIG_PATH_RESEARCH0

# Step 2: Submit the job to process the data (waits until complete)
echo "Executing pipeline..."
NEXTFLOW_CMD="cd /mnt/longship/projects/biol-imaging-2024/CellPhe-data-pipeline && ./process_dataset.sh $CONFIG_PATH_VIKING -resume"
ssh viking "${NEXTFLOW_CMD}"

# Step 3: Move outputs from scratch to longship
echo "Moving outputs to longship..."
MOVE_OUTPUTS_LONGSHIP_CMD="rsync --progress -vru --exclude .launch --remove-source-files $EXPERIMENT_PATH_VIKING_SCRATCH/ $EXPERIMENT_PATH_VIKING_LONGSHIP/"
ssh viking "${MOVE_OUTPUTS_LONGSHIP_CMD}"

# Step 4: Copy outputs from longship to bioldata
echo "Transferring outputs to bioldata..."
rsync --progress -vru $EXPERIMENT_PATH_RESEARCH0_LONGSHIP/ $EXPERIMENT_PATH_RESEARCH0_STORAGE/
