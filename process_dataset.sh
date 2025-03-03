#!/bin/bash
# Wrapper for the NextFlow job submission that sets the environment before running the job
# Args:
#   - 1: Config file
#   - 2: (OPTIONAL): -resume if intending to resume
CONFIG=${1}
RESUME=${2:-default}

# Prepare paths
EXPERIMENT="$(basename $(dirname $(dirname ${CONFIG})))"
PROJECT_DIR="/mnt/scratch/projects/biol-imaging-2024/"
EXPERIMENT_DIR="$PROJECT_DIR/Experiments/$EXPERIMENT"
NEXTFLOW_FILE="$PROJECT_DIR/CellPhe-data-pipeline/process_dataset.nf"

# Load dependencies
ml load Python/3.11.5-GCCcore-13.2.0
ml load Nextflow/23.10.0
ml load Java/11.0.20
ml load Perl-bundle-CPAN/5.38.0-GCCcore-13.2.0
ml load LibTIFF/4.6.0-GCCcore-13.2.0
ml load ImageMagick/7.1.1-34-GCCcore-13.2.0
ml load Quarto/1.6.39-x86_64-linux
ml load R/4.4.1-gfbf-2023b
ml load R-bundle-CRAN/2024.06-foss-2023b
ml unload SciPy-bundle/2023.11-gfbf-2023b
source $PROJECT_DIR/venv/bin/activate
export CELLPOSE_LOCAL_MODELS_PATH=$PROJECT_DIR/cellpose
export PATH=$PATH:$PROJECT_DIR/bin/apache-maven-3.9.9/bin

# Run pipeline
cd $EXPERIMENT_DIR
CMD="srun --ntasks=1 --cpus-per-task 4 --mem=8G --time=120 nextflow run $NEXTFLOW_FILE -work-dir .work -params-file $CONFIG -ansi-log true"
if [ $RESUME == '-resume' ]
then
  CMD="$CMD -resume"
fi
eval $CMD
