#!/bin/bash
# run_pipeline_on_viking
# ~~~~~~~~~~~~~~~~~~~~~~
#
# Wrapper for running the NextFlow pipeline on Viking sets up the environment 
# and prepares pipeline arguments, before running.
#
# NB: THIS WILL ONLY RUN ON VIKING!
#
# Args:
#   - 1: Config file

# Retrieve timelapse_id from config
CONFIG=${1}
CONFIG=$(realpath $CONFIG)
TIMELAPSE_ID=$(jq -r .folder_names.timelapse_id $CONFIG)

# Ensure clean environment
ml purge

# Prepare paths - inputs
EXPERIMENT_PATH="$(dirname $(dirname ${CONFIG}))"
EXPERIMENT="$(basename ${EXPERIMENT_PATH})"
PROJECT_DIR_LONGSHIP="/mnt/longship/projects/biol-imaging-2024/"
NEXTFLOW_FILE="$PROJECT_DIR_LONGSHIP/CellPhe-data-pipeline/main.nf"
RAW_DATA_DIR="$EXPERIMENT_PATH/raw/${TIMELAPSE_ID}"

# Outputs
PROJECT_DIR_SCRATCH="/mnt/scratch/projects/biol-imaging-2024/"
EXPERIMENT_DIR_SCRATCH="$PROJECT_DIR_SCRATCH/Experiments/$EXPERIMENT"
LAUNCH_DIR="$EXPERIMENT_DIR_SCRATCH/.launch/${TIMELAPSE_ID}"

# Load dependencies
ml load Nextflow/23.10.0
ml load Apptainer/latest
export CELLPOSE_LOCAL_MODELS_PATH=$PROJECT_DIR_LONGSHIP/cellpose

# Run pipeline from a directory specific to this timelapse
mkdir -p $LAUNCH_DIR
cd $LAUNCH_DIR
export NXF_APPTAINER_CACHEDIR=$PROJECT_DIR_SCRATCH/apptainer_cache
CMD="nextflow run $NEXTFLOW_FILE -profile york_viking -work-dir .work --raw_dir $RAW_DATA_DIR --output_dir $EXPERIMENT_DIR_SCRATCH -params-file $CONFIG -ansi-log true -resume"
eval $CMD
