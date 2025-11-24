#!/bin/bash
# Wrapper for the NextFlow job submission that sets the environment before running the job
# Args:
#   - 1: Config file

# Get config with absolute path
CONFIG=${1}
CONFIG=$(realpath $CONFIG)
# Parse config to get site and image
SITE=$(jq -r .folder_names.site $CONFIG)
IMAGE=$(jq -r .folder_names.image_type $CONFIG)

# Ensure clean environment
ml purge

# Prepare paths - inputs
EXPERIMENT_PATH="$(dirname $(dirname ${CONFIG}))"
EXPERIMENT="$(basename ${EXPERIMENT_PATH})"
PROJECT_DIR_LONGSHIP="/mnt/longship/projects/biol-imaging-2024/"
NEXTFLOW_FILE="$PROJECT_DIR_LONGSHIP/CellPhe-data-pipeline/process_dataset.nf"
RAW_DATA_DIR="$EXPERIMENT_PATH/raw/${SITE}_${IMAGE}"

# Outputs
PROJECT_DIR_SCRATCH="/mnt/scratch/projects/biol-imaging-2024/"
EXPERIMENT_DIR_SCRATCH="$PROJECT_DIR_SCRATCH/Experiments/$EXPERIMENT"
LAUNCH_DIR="$EXPERIMENT_DIR_SCRATCH/.launch/${SITE}_${IMAGE}"

# Load dependencies
ml load Nextflow/23.10.0
ml load Apptainer/latest
source $PROJECT_DIR_LONGSHIP/venv/bin/activate
export CELLPOSE_LOCAL_MODELS_PATH=$PROJECT_DIR_LONGSHIP/cellpose
export PATH=$PATH:$PROJECT_DIR_LONGSHIP/bin/apache-maven-3.9.9/bin

# Run pipeline from a directory specific to this timelapse
mkdir -p $LAUNCH_DIR
cd $LAUNCH_DIR
export NXF_APPTAINER_CACHEDIR=$PROJECT_DIR_SCRATCH/apptainer_cache
CMD="nextflow run $NEXTFLOW_FILE -work-dir .work --raw_dir $RAW_DATA_DIR --output_dir $EXPERIMENT_DIR_SCRATCH -params-file $CONFIG -ansi-log true -resume"
eval $CMD
